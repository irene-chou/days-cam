import Combine
import CoreText
import Foundation

// MARK: - System font matching

/// What a system-font match reports while it runs (PRD 0.3 §4.4, FR-5.15).
enum SystemFontMatchEvent: Equatable, Sendable {
    /// CoreText is about to download; `totalBytes` is the whole download.
    case downloadWillBegin(totalBytes: Int64)
    /// A download is under way.
    case downloading(fraction: Double, totalBytes: Int64)
    /// An error was reported mid-way. Not final: iOS reports e.g.
    /// `CTFontManagerErrorDomain` #302 and still matches (research report A,
    /// note 1), so only `finished` decides the outcome.
    case failed
    /// The match is over. `matched` is whether the font was matched in the end;
    /// `offline` is whether a "no connection" error was seen.
    case finished(matched: Bool, offline: Bool)
}

/// Starts a CoreText font match. Injected so unit tests never download.
protocol SystemFontMatching: Sendable {
    /// Starts matching the font named `postScriptName`.
    ///
    /// `handler` may be called from any thread. Returning `false` from it
    /// cancels the match. A match that cannot even start reports
    /// `.finished(matched: false, ...)`.
    func startMatching(postScriptName: String,
                       handler: @escaping @Sendable (SystemFontMatchEvent) -> Bool)
}

/// `CTFontDescriptorMatchFontDescriptorsWithProgressHandler` as a
/// `SystemFontMatching`.
struct CoreTextSystemFontMatcher: SystemFontMatching {
    func startMatching(postScriptName: String,
                       handler: @escaping @Sendable (SystemFontMatchEvent) -> Bool) {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: postScriptName] as CFDictionary)
        let tracker = Tracker()
        let started = CTFontDescriptorMatchFontDescriptorsWithProgressHandler([descriptor] as CFArray, nil) { state, parameters in
            let info = parameters as NSDictionary
            if let size = info[kCTFontDescriptorMatchingTotalAssetSize] as? NSNumber {
                tracker.noteTotal(size.int64Value)
            }
            switch state {
            case .willBeginDownloading:
                return handler(.downloadWillBegin(totalBytes: tracker.total))
            case .downloading:
                let percentage = (info[kCTFontDescriptorMatchingPercentage] as? NSNumber)?.doubleValue ?? 0
                return handler(.downloading(fraction: percentage / 100, totalBytes: tracker.total))
            case .didMatch:
                tracker.matched = true
                return true
            case .didFailWithError:
                if let error = info[kCTFontDescriptorMatchingError] as? NSError, Self.isOffline(error) {
                    tracker.offline = true
                }
                return handler(.failed)
            case .didFinish:
                _ = handler(.finished(matched: tracker.matched, offline: tracker.offline))
                return true
            default:
                return true
            }
        }
        if !started {
            _ = handler(.finished(matched: false, offline: false))
        }
    }

    /// Whether `error` (or the error it wraps) is "no network connection".
    private static func isOffline(_ error: NSError) -> Bool {
        let offlineCodes = [NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed,
                            NSURLErrorInternationalRoamingOff, NSURLErrorNetworkConnectionLost]
        if error.domain == NSURLErrorDomain, offlineCodes.contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isOffline(underlying) }
        return false
    }

    /// What one match has seen so far; CoreText calls from its own queue.
    private final class Tracker: @unchecked Sendable {
        private let lock = NSLock()
        private var storedTotal: Int64 = 0
        private var storedMatched = false
        private var storedOffline = false

        var total: Int64 { lock.withLock { storedTotal } }
        var matched: Bool {
            get { lock.withLock { storedMatched } }
            set { lock.withLock { storedMatched = newValue } }
        }
        var offline: Bool {
            get { lock.withLock { storedOffline } }
            set { lock.withLock { storedOffline = newValue } }
        }

        func noteTotal(_ value: Int64) {
            lock.withLock { storedTotal = max(storedTotal, value) }
        }
    }
}

// MARK: - FontLibrary

/// Downloads, verifies, registers, matches and deletes the overlay fonts, and
/// publishes each font's `FontState` (PRD 0.3 §4.2, §4.4, FR-5.15, FR-16.6 to
/// FR-16.14).
///
/// All state lives on the main actor. Network, hashing and CoreText callbacks
/// run elsewhere and return to the main actor before touching it. Every
/// network, file-system, CoreText-registration, CoreText-matching and
/// `UserDefaults` dependency is injected so unit tests never go online.
///
/// Observing results: watch `states`, or `downloadDidFinish` for the moment a
/// download completes (the caller applies the font to the profile that started
/// it, PRD A-8).
@MainActor
final class FontLibrary: ObservableObject, FontAvailabilityProviding {
    /// `UserDefaults` key listing the system fonts the user downloaded in-app.
    static let downloadedSystemFontIDsKey = "downloadedSystemFontIDs"
    /// Seconds a launch-time system-font match may take (FR-5.15).
    static let defaultLaunchTimeout: TimeInterval = 3

    /// The state of every font. `pingFang` is always `.available`.
    @Published private(set) var states: [OverlayFontID: FontState] = [:]
    /// Fires with the font ID each time a download finishes successfully.
    let downloadDidFinish = PassthroughSubject<OverlayFontID, Never>()

    private let directory: URL
    private let fetcher: FontFileFetching
    private let registrar: FontRegistering
    private let matcher: SystemFontMatching
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let launchTimeout: TimeInterval
    private let entryProvider: (OverlayFontID) -> FontCatalogEntry

    private var operations: [OverlayFontID: Operation] = [:]
    private var hasPreparedAtLaunch = false
    /// System fonts waiting for their launch-time match, in order.
    private var launchQueue: [(fontID: OverlayFontID, postScriptName: String)] = []
    private var activeLaunchFont: OverlayFontID?
    private var settleWaiters: [OverlayFontID: [CheckedContinuation<Void, Never>]] = [:]

    /// Creates a library.
    ///
    /// Fonts that are on the device (an open-source file, or a system font in
    /// `downloadedSystemFontIDs`) start `.preparing`; call `prepareAtLaunch`
    /// to settle them. Everything else starts `.notDownloaded`.
    ///
    /// - Parameters:
    ///   - directory: where open-source fonts are stored. Defaults to
    ///     `Application Support/Fonts`; tests pass a temporary directory.
    ///   - entryProvider: the font catalog; tests substitute small fake assets.
    init(directory: URL? = nil,
         fetcher: FontFileFetching = URLSessionFontFetcher(),
         registrar: FontRegistering = CoreTextFontRegistrar(),
         matcher: SystemFontMatching = CoreTextSystemFontMatcher(),
         defaults: UserDefaults = .standard,
         fileManager: FileManager = .default,
         launchTimeout: TimeInterval = FontLibrary.defaultLaunchTimeout,
         entryProvider: @escaping (OverlayFontID) -> FontCatalogEntry = FontCatalog.entry(for:)) {
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.fetcher = fetcher
        self.registrar = registrar
        self.matcher = matcher
        self.defaults = defaults
        self.fileManager = fileManager
        self.launchTimeout = launchTimeout
        self.entryProvider = entryProvider

        let downloaded = Set(downloadedSystemFontIDs)
        for fontID in OverlayFontID.allCases {
            let entry = entryProvider(fontID)
            switch entry.source {
            case .builtIn:
                states[fontID] = .available
            case .openSource:
                states[fontID] = fileManager.fileExists(atPath: storedFileURL(for: fontID).path)
                    ? .preparing : .notDownloaded
            case .system:
                states[fontID] = downloaded.contains(fontID) ? .preparing : .notDownloaded
            }
        }
    }

    // MARK: Reading

    /// The current state of `fontID`.
    func state(for fontID: OverlayFontID) -> FontState {
        states[fontID] ?? .notDownloaded
    }

    /// The system fonts the user downloaded in-app, in catalog order.
    var downloadedSystemFontIDs: [OverlayFontID] {
        let raw = Set(defaults.stringArray(forKey: Self.downloadedSystemFontIDsKey) ?? [])
        return OverlayFontID.allCases.filter {
            entryProvider($0).source == .system && raw.contains($0.rawValue)
        }
    }

    /// `Application Support/Fonts` (or the injected directory).
    var fontsDirectory: URL { directory }

    /// Where the open-source font `fontID` is stored once downloaded.
    func storedFileURL(for fontID: OverlayFontID) -> URL {
        let fileExtension = entryProvider(fontID).openSource?.fileExtension ?? "ttf"
        return directory.appendingPathComponent("\(fontID.rawValue).\(fileExtension)")
    }

    // MARK: Commands

    /// Starts downloading `fontID` (FR-16.6, FR-16.10).
    ///
    /// Allowed from `.notDownloaded` and `.failed` only; a font that is already
    /// downloading, preparing or available, and `pingFang`, are ignored.
    /// Several fonts may download at once. Watch `states` and
    /// `downloadDidFinish` for the outcome.
    ///
    /// - Returns: whether a download was started.
    @discardableResult
    func download(_ fontID: OverlayFontID) -> Bool {
        switch state(for: fontID) {
        case .notDownloaded, .failed: break
        case .available, .preparing, .downloading: return false
        }
        let entry = entryProvider(fontID)
        switch entry.source {
        case .builtIn:
            return false
        case .openSource:
            guard let asset = entry.openSource else { return false }
            startOpenSourceDownload(fontID, asset: asset)
        case .system:
            startSystemDownload(fontID, postScriptName: entry.postScriptName)
        }
        return true
    }

    /// Cancels a download in progress; the font returns to `.notDownloaded` and
    /// the temporary file is removed (FR-16.7). Does nothing for any other state.
    func cancel(_ fontID: OverlayFontID) {
        guard case .downloading = state(for: fontID), let operation = operations[fontID] else { return }
        end(operation, for: fontID)
        setState(.notDownloaded, for: fontID)
    }

    /// Deletes a downloaded open-source font: unregisters it and removes the
    /// file (FR-16.12, A-3).
    ///
    /// The caller must already have moved the profiles using it to another font
    /// (`ProfileStore.replaceFont(_:with:)`); this only touches files and
    /// registration.
    ///
    /// - Returns: `false` for `pingFang` and system fonts, which cannot be
    ///   deleted, or when the file could not be removed.
    @discardableResult
    func delete(_ fontID: OverlayFontID) -> Bool {
        guard entryProvider(fontID).source == .openSource else { return false }
        if let operation = operations[fontID] {
            end(operation, for: fontID)
        }
        let url = storedFileURL(for: fontID)
        if fileManager.fileExists(atPath: url.path) {
            registrar.unregister(fontAt: url)
            try? fileManager.removeItem(at: url)
            guard !fileManager.fileExists(atPath: url.path) else { return false }
        }
        setState(.notDownloaded, for: fontID)
        return true
    }

    /// Cancels every download in progress; each becomes `.failed(.other)` and its
    /// temporary file is removed. Call when the App goes to the background
    /// (FR-16.11).
    func cancelAllDownloads() {
        for (fontID, operation) in operations {
            guard case .downloading = state(for: fontID) else { continue }
            end(operation, for: fontID)
            setState(.failed(.other), for: fontID)
        }
    }

    /// Settles the fonts that are on the device (FR-5.15): registers and
    /// verifies the open-source files, and matches the system fonts in
    /// `downloadedSystemFontIDs`. A match that would download (the system
    /// cleared the font) is cancelled and the font becomes `.notDownloaded`;
    /// nothing is ever downloaded here. A match not finished within the launch
    /// timeout is cancelled and the font becomes `.failed(.other)`.
    ///
    /// Returns once `priority` (the current profile's font) has left
    /// `.preparing`, or once every font has when `priority` is `nil`. The other
    /// fonts keep settling on their own.
    ///
    /// Call it once, at launch. A second call on the same library returns at
    /// once and does nothing.
    ///
    /// System fonts are matched one after another (the priority font first), so
    /// each font's 3 seconds count from when its own match starts.
    func prepareAtLaunch(priority: OverlayFontID? = nil) async {
        guard !hasPreparedAtLaunch else { return }
        hasPreparedAtLaunch = true
        removeStaleTemporaryFiles()
        let downloaded = Set(downloadedSystemFontIDs)
        var order = OverlayFontID.allCases.filter { state(for: $0) == .preparing }
        if let priority, let index = order.firstIndex(of: priority) {
            order.insert(order.remove(at: index), at: 0)
        }
        for fontID in order where operations[fontID] == nil {
            let entry = entryProvider(fontID)
            switch entry.source {
            case .openSource:
                if let asset = entry.openSource { startOpenSourcePreparation(fontID, asset: asset) }
            case .system:
                if downloaded.contains(fontID) {
                    launchQueue.append((fontID, entry.postScriptName))
                } else {
                    setState(.notDownloaded, for: fontID)
                }
            case .builtIn:
                break
            }
        }
        startNextLaunchMatch()
        for fontID in priority.map({ [$0] }) ?? OverlayFontID.allCases {
            await waitUntilSettled(fontID)
        }
    }

    /// Settles one font now, for a profile switched to a `.preparing` font
    /// (FR-5.16), so the 3-second limit (FR-5.15) holds however long the
    /// launch queue is.
    ///
    /// A font still waiting in the launch queue leaves it and is matched at
    /// once, alongside whatever match is running; its 3 seconds count from now.
    /// A font already being matched is just waited for; a font that is not
    /// `.preparing` returns immediately. Outcomes follow `prepareAtLaunch`: a
    /// download report cancels the match (`.notDownloaded`), a timeout is
    /// `.failed(.other)`.
    func prepare(_ fontID: OverlayFontID) async {
        guard state(for: fontID) == .preparing else { return }
        if operations[fontID] == nil {
            launchQueue.removeAll { $0.fontID == fontID }
            let entry = entryProvider(fontID)
            switch entry.source {
            case .openSource:
                if let asset = entry.openSource { startOpenSourcePreparation(fontID, asset: asset) }
            case .system:
                startLaunchMatch(fontID, postScriptName: entry.postScriptName)
            case .builtIn:
                break
            }
        }
        await waitUntilSettled(fontID)
    }

    // MARK: State

    private func setState(_ newState: FontState, for fontID: OverlayFontID) {
        guard states[fontID] != newState else { return }
        states[fontID] = newState
        if newState != .preparing, let waiters = settleWaiters.removeValue(forKey: fontID) {
            waiters.forEach { $0.resume() }
        }
    }

    private func waitUntilSettled(_ fontID: OverlayFontID) async {
        guard state(for: fontID) == .preparing else { return }
        await withCheckedContinuation { continuation in
            settleWaiters[fontID, default: []].append(continuation)
        }
    }

    // MARK: Operations

    /// One download, preparation or match. A callback that finds its operation
    /// is no longer the current one for its font is stale and does nothing.
    fileprivate final class Operation {
        let id = UUID()
        let session = MatchSession()
        var task: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
        var temporaryURL: URL?
    }

    private func isCurrent(_ operation: Operation, for fontID: OverlayFontID) -> Bool {
        operations[fontID] === operation
    }

    /// Makes `operation` stale, stops its work and removes its temporary file.
    private func end(_ operation: Operation, for fontID: OverlayFontID) {
        if operations[fontID] === operation { operations[fontID] = nil }
        operation.session.cancel()
        operation.task?.cancel()
        operation.timeoutTask?.cancel()
        if let url = operation.temporaryURL { try? fileManager.removeItem(at: url) }
    }

    private func removeStaleTemporaryFiles() {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let inUse = Set(operations.values.compactMap { $0.temporaryURL?.lastPathComponent })
        for name in names where name.hasSuffix(Self.temporarySuffix) && !inUse.contains(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static let temporarySuffix = ".download"

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let root = base ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent("Fonts", isDirectory: true)
    }

    /// Runs `work` on the main actor from any thread, in call order.
    private nonisolated func onMain(_ work: @escaping @MainActor (FontLibrary) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                work(self)
            }
        }
    }
}

// MARK: - Open-source fonts

private extension FontLibrary {
    func startOpenSourceDownload(_ fontID: OverlayFontID, asset: OpenSourceFontAsset) {
        let operation = Operation()
        let temporaryURL = directory.appendingPathComponent(
            "\(fontID.rawValue).\(asset.fileExtension).\(operation.id.uuidString)\(Self.temporarySuffix)")
        operation.temporaryURL = temporaryURL
        operations[fontID] = operation
        setState(.downloading(progress: 0), for: fontID)
        operation.task = Task { [weak self] in
            await self?.runOpenSourceDownload(fontID, asset: asset, operation: operation, temporaryURL: temporaryURL)
        }
    }

    func runOpenSourceDownload(_ fontID: OverlayFontID,
                               asset: OpenSourceFontAsset,
                               operation: Operation,
                               temporaryURL: URL) async {
        defer { try? fileManager.removeItem(at: temporaryURL) }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fail(fontID, operation: operation, reason: .other)
            return
        }

        var reason = FontFailureReason.other
        for url in [asset.primaryURL, asset.fallbackURL] {
            guard isCurrent(operation, for: fontID) else { return }
            do {
                try await fetcher.fetch(from: url, to: temporaryURL) { [weak self] fraction in
                    self?.onMain { library in
                        library.noteProgress(fraction, for: fontID, operation: operation)
                    }
                }
                guard isCurrent(operation, for: fontID) else { return }
                let isValid = await Task.detached(priority: .utility) {
                    FontFileVerifier.isValid(fileAt: temporaryURL, for: asset)
                }.value
                guard isCurrent(operation, for: fontID) else { return }
                if isValid {
                    install(fontID, from: temporaryURL, operation: operation)
                    return
                }
                try? fileManager.removeItem(at: temporaryURL)
                reason = .other
            } catch is CancellationError {
                return
            } catch FontFetchError.noNetwork {
                // No connection fails at once; the fallback host would not help.
                reason = .noNetwork
                break
            } catch FontFetchError.storage {
                // A disk problem would repeat on the fallback host.
                reason = .other
                break
            } catch {
                reason = .other
            }
        }
        fail(fontID, operation: operation, reason: reason)
    }

    func noteProgress(_ fraction: Double, for fontID: OverlayFontID, operation: Operation) {
        guard isCurrent(operation, for: fontID), case .downloading(let last) = state(for: fontID) else { return }
        let clamped = min(max(fraction, 0), 1)
        // Skip tiny steps so observers are not republished on every chunk.
        guard clamped - last >= 0.01 else { return }
        setState(.downloading(progress: clamped), for: fontID)
    }

    /// Moves a verified file into place, excludes it from backup and registers it.
    func install(_ fontID: OverlayFontID, from temporaryURL: URL, operation: Operation) {
        let destination = storedFileURL(for: fontID)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                registrar.unregister(fontAt: destination)
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDestination = destination
            try mutableDestination.setResourceValues(values)
        } catch {
            try? fileManager.removeItem(at: destination)
            fail(fontID, operation: operation, reason: .other)
            return
        }
        guard registrar.register(fontAt: destination) else {
            try? fileManager.removeItem(at: destination)
            fail(fontID, operation: operation, reason: .other)
            return
        }
        operations[fontID] = nil
        setState(.available, for: fontID)
        downloadDidFinish.send(fontID)
    }

    func fail(_ fontID: OverlayFontID, operation: Operation, reason: FontFailureReason) {
        guard isCurrent(operation, for: fontID) else { return }
        operations[fontID] = nil
        setState(.failed(reason), for: fontID)
    }

    /// Verifies and registers an open-source file found at launch (4.2).
    func startOpenSourcePreparation(_ fontID: OverlayFontID, asset: OpenSourceFontAsset) {
        let operation = Operation()
        operations[fontID] = operation
        let url = storedFileURL(for: fontID)
        operation.task = Task { [weak self] in
            guard FileManager.default.fileExists(atPath: url.path) else {
                self?.finishPreparation(fontID, operation: operation, outcome: .missing)
                return
            }
            let isValid = await Task.detached(priority: .utility) {
                FontFileVerifier.isValid(fileAt: url, for: asset)
            }.value
            self?.finishPreparation(fontID, operation: operation, outcome: isValid ? .valid : .corrupt)
        }
    }

    enum PreparationOutcome { case missing, corrupt, valid }

    func finishPreparation(_ fontID: OverlayFontID, operation: Operation, outcome: PreparationOutcome) {
        guard isCurrent(operation, for: fontID) else { return }
        operations[fontID] = nil
        let url = storedFileURL(for: fontID)
        switch outcome {
        case .missing:
            setState(.notDownloaded, for: fontID)
        case .corrupt:
            try? fileManager.removeItem(at: url)
            setState(.failed(.other), for: fontID)
        case .valid:
            if registrar.register(fontAt: url) {
                setState(.available, for: fontID)
            } else {
                try? fileManager.removeItem(at: url)
                setState(.failed(.other), for: fontID)
            }
        }
    }
}

// MARK: - System fonts

private extension FontLibrary {
    /// A user-started download of a system font (FR-16.6).
    func startSystemDownload(_ fontID: OverlayFontID, postScriptName: String) {
        let operation = Operation()
        operations[fontID] = operation
        setState(.downloading(progress: 0), for: fontID)
        let session = operation.session
        matcher.startMatching(postScriptName: postScriptName) { [weak self] event in
            if session.isCancelled { return false }
            self?.onMain { library in
                library.handleDownloadEvent(event, for: fontID, operation: operation)
            }
            return true
        }
    }

    func handleDownloadEvent(_ event: SystemFontMatchEvent, for fontID: OverlayFontID, operation: Operation) {
        guard isCurrent(operation, for: fontID) else { return }
        switch event {
        case .downloadWillBegin, .failed:
            break
        case .downloading(let fraction, _):
            setState(.downloading(progress: min(max(fraction, 0), 1)), for: fontID)
        case .finished(let matched, let offline):
            operation.session.cancel()
            operations[fontID] = nil
            if matched {
                var ids = Set(defaults.stringArray(forKey: Self.downloadedSystemFontIDsKey) ?? [])
                ids.insert(fontID.rawValue)
                defaults.set(Array(ids).sorted(), forKey: Self.downloadedSystemFontIDsKey)
                setState(.available, for: fontID)
                downloadDidFinish.send(fontID)
            } else {
                setState(.failed(offline ? .noNetwork : .other), for: fontID)
            }
        }
    }

    /// A launch-time match of a font already recorded as downloaded (FR-5.15).
    func startLaunchMatch(_ fontID: OverlayFontID, postScriptName: String) {
        let operation = Operation()
        operations[fontID] = operation
        let session = operation.session

        let timeout = launchTimeout
        operation.timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.timeOutLaunchMatch(fontID, operation: operation)
        }

        matcher.startMatching(postScriptName: postScriptName) { [weak self] event in
            if session.isCancelled { return false }
            switch event {
            case .downloadWillBegin, .downloading:
                // Any download report means the system cleared the font,
                // whatever size it carries. Stop before any byte is fetched.
                session.cancel()
                self?.onMain { library in
                    library.handleLaunchWouldDownload(fontID, operation: operation)
                }
                return false
            default:
                self?.onMain { library in
                    library.handleLaunchEvent(event, for: fontID, operation: operation)
                }
                return true
            }
        }
    }

    func handleLaunchEvent(_ event: SystemFontMatchEvent, for fontID: OverlayFontID, operation: Operation) {
        guard isCurrent(operation, for: fontID), case .finished(let matched, _) = event else { return }
        end(operation, for: fontID)
        setState(matched ? .available : .failed(.other), for: fontID)
        launchMatchEnded(fontID)
    }

    func handleLaunchWouldDownload(_ fontID: OverlayFontID, operation: Operation) {
        guard isCurrent(operation, for: fontID) else { return }
        end(operation, for: fontID)
        let remaining = downloadedSystemFontIDs.filter { $0 != fontID }.map(\.rawValue)
        defaults.set(remaining, forKey: Self.downloadedSystemFontIDsKey)
        setState(.notDownloaded, for: fontID)
        launchMatchEnded(fontID)
    }

    func timeOutLaunchMatch(_ fontID: OverlayFontID, operation: Operation) {
        guard isCurrent(operation, for: fontID), state(for: fontID) == .preparing else { return }
        end(operation, for: fontID)
        setState(.failed(.other), for: fontID)
        launchMatchEnded(fontID)
    }

    /// Starts the next queued launch match, if none is running.
    func startNextLaunchMatch() {
        guard activeLaunchFont == nil else { return }
        while !launchQueue.isEmpty {
            let next = launchQueue.removeFirst()
            guard state(for: next.fontID) == .preparing, operations[next.fontID] == nil else { continue }
            activeLaunchFont = next.fontID
            startLaunchMatch(next.fontID, postScriptName: next.postScriptName)
            return
        }
    }

    func launchMatchEnded(_ fontID: OverlayFontID) {
        guard activeLaunchFont == fontID else { return }
        activeLaunchFont = nil
        startNextLaunchMatch()
    }
}

// MARK: - Cancellation flag

/// A flag CoreText's progress handler reads from its own thread to learn that
/// the match was cancelled (the handler cancels by returning `false`).
final class MatchSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    /// Whether the match was cancelled or is over.
    var isCancelled: Bool { lock.withLock { cancelled } }

    /// Marks the match cancelled.
    func cancel() { lock.withLock { cancelled = true } }
}
