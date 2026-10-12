import Combine
import CryptoKit
import XCTest
@testable import DaysCam

// MARK: - Fakes

/// A scripted network. Never connects.
private final class FakeFetcher: FontFileFetching, @unchecked Sendable {
    enum Behavior {
        case data(Data)
        case fail(FontFetchError)
        /// Writes some bytes, then waits until cancelled.
        case hang
    }

    private let lock = NSLock()
    private var behaviors: [URL: Behavior] = [:]
    private var requested: [URL] = []
    /// Called after a .data body is written, before returning.
    var onFetched: (@Sendable () -> Void)?

    var requestedURLs: [URL] { lock.withLock { requested } }

    func script(_ url: URL, _ behavior: Behavior) {
        lock.withLock { behaviors[url] = behavior }
    }

    func fetch(from url: URL,
               to destination: URL,
               progress: @escaping @Sendable (Double) -> Void) async throws {
        let behavior: Behavior? = lock.withLock {
            requested.append(url)
            return behaviors[url]
        }
        switch behavior {
        case .data(let data):
            progress(0.5)
            try data.write(to: destination)
            progress(1)
            onFetched?()
        case .fail(let error):
            throw error
        case .hang:
            try Data("partial".utf8).write(to: destination)
            try await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        case nil:
            throw FontFetchError.other
        }
    }
}

private final class FakeRegistrar: FontRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private var registered: [URL] = []
    private var unregistered: [URL] = []
    private var shouldSucceed = true
    private var mainThreadCalls = 0

    /// How many `register` calls ran on the main thread.
    var mainThreadRegistrations: Int { lock.withLock { mainThreadCalls } }

    var registeredURLs: [URL] { lock.withLock { registered } }
    var unregisteredURLs: [URL] { lock.withLock { unregistered } }

    func failRegistration() { lock.withLock { shouldSucceed = false } }

    func register(fontAt url: URL) -> Bool {
        lock.withLock {
            if Thread.isMainThread { mainThreadCalls += 1 }
            registered.append(url)
            return shouldSucceed
        }
    }

    func unregister(fontAt url: URL) {
        lock.withLock { unregistered.append(url) }
    }
}

/// Counts full SHA-256 verifications while delegating to the real verifier.
private final class CountingVerifier: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }

    func verify(_ url: URL, _ asset: OpenSourceFontAsset) -> Bool {
        lock.withLock { count += 1 }
        return FontFileVerifier.isValid(fileAt: url, for: asset)
    }
}

/// A scripted CoreText matcher: the test plays CoreText by sending events.
private final class FakeMatcher: SystemFontMatching, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [String: [@Sendable (SystemFontMatchEvent) -> Bool]] = [:]
    private var started: [String] = []
    /// Bytes "downloaded": events delivered while the handler had not cancelled.
    private var delivered = 0

    var startedNames: [String] { lock.withLock { started } }

    func startMatching(postScriptName: String,
                       handler: @escaping @Sendable (SystemFontMatchEvent) -> Bool) {
        lock.withLock {
            started.append(postScriptName)
            handlers[postScriptName, default: []].append(handler)
        }
    }

    /// Sends `event` to the latest match of `name`; returns what the handler
    /// answered (`false` = the match was cancelled).
    @discardableResult
    func send(_ event: SystemFontMatchEvent, to name: String) -> Bool {
        let handler = lock.withLock { handlers[name]?.last }
        return handler?(event) ?? false
    }

    /// Sends to the match started first, the one an earlier test step cancelled.
    @discardableResult
    func sendToFirst(_ event: SystemFontMatchEvent, to name: String) -> Bool {
        let handler = lock.withLock { handlers[name]?.first }
        return handler?(event) ?? false
    }
}

// MARK: - Tests

/// A file manager whose `fileExists` can be told to report every file as missing.
private final class ScriptedFileManager: FileManager {
    var reportsEverythingMissing = false
    private(set) var existenceChecks = 0

    override func fileExists(atPath path: String) -> Bool {
        existenceChecks += 1
        return reportsEverythingMissing ? false : super.fileExists(atPath: path)
    }
}

/// Covers TASK-33 acceptance 33.1 ... 33.12 (PRD 0.3 §4.2, §4.4, FR-5.15,
/// FR-16.6 ... FR-16.14). Network, registration and matching are all fakes.
@MainActor
final class FontLibraryTests: XCTestCase {

    private let fontData = Data("pretend this is a font file".utf8)
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private var fetcher = FakeFetcher()
    private var registrar = FakeRegistrar()
    private var matcher = FakeMatcher()
    private var cancellables = Set<AnyCancellable>()

    private var huninnAsset: OpenSourceFontAsset {
        let digest = SHA256.hash(data: fontData).map { String(format: "%02x", $0) }.joined()
        return OpenSourceFontAsset(
            fileName: "jf-openhuninn-2.1.ttf", repositoryPath: "huninn/jf-openhuninn-2.1.ttf",
            byteCount: fontData.count, sha256: digest,
            primaryURL: URL(string: "https://primary.example/huninn.ttf")!,
            fallbackURL: URL(string: "https://fallback.example/huninn.ttf")!,
            version: "2.1", copyright: "test", licenseFileNames: [])
    }

    private var regularAsset: OpenSourceFontAsset {
        OpenSourceFontAsset(fileName: "NotoSerifTC-Regular.otf", repositoryPath: "noto/NotoSerifTC-Regular.otf",
                            byteCount: fontData.count, sha256: huninnAsset.sha256,
                            primaryURL: URL(string: "https://primary.example/noto-regular.otf")!,
                            fallbackURL: URL(string: "https://fallback.example/noto-regular.otf")!,
                            version: "2.003", copyright: "test", licenseFileNames: [])
    }

    func testWeightDownloadsAreIndependentAndDoNotRepeat() async {
        let library = makeLibrary()
        fetcher.script(regularAsset.primaryURL, .data(fontData))
        var completed: [FontDownloadID] = []
        library.weightDownloadDidFinish.sink { completed.append($0) }.store(in: &cancellables)
        XCTAssertTrue(library.download(.notoSerifTC, weightID: "regular"))
        XCTAssertFalse(library.download(.notoSerifTC, weightID: "regular"))
        XCTAssertEqual(library.state(for: .notoSerifTC), .notDownloaded)
        await waitUntil("regular available") { library.state(for: .notoSerifTC, weightID: "regular") == .available }
        XCTAssertFalse(library.download(.notoSerifTC, weightID: "regular"))
        XCTAssertEqual(fetcher.requestedURLs, [regularAsset.primaryURL])
        XCTAssertEqual(completed, [FontDownloadID(fontID: .notoSerifTC, weightID: "regular")])
        XCTAssertEqual(library.storedFileURL(for: .notoSerifTC).lastPathComponent, "notoSerifTC.otf")
        XCTAssertEqual(library.storedFileURL(for: .notoSerifTC, weightID: "regular").lastPathComponent, "notoSerifTC-regular.otf")
        XCTAssertTrue(library.download(.notoSerifTC))
        await waitUntil("bold available") { library.state(for: .notoSerifTC) == .available }
        let relaunched = makeLibrary()
        await relaunched.prepareAtLaunch(priority: .notoSerifTC, weightID: "regular")
        XCTAssertEqual(relaunched.state(for: .notoSerifTC, weightID: "regular"), .available)
        await relaunched.prepare(.notoSerifTC)
        XCTAssertEqual(relaunched.state(for: .notoSerifTC), .available)
        XCTAssertEqual(fetcher.requestedURLs, [regularAsset.primaryURL, notoAsset.primaryURL])
        XCTAssertTrue(relaunched.delete(.notoSerifTC, weightID: "regular"))
        XCTAssertEqual(relaunched.state(for: .notoSerifTC), .available)
        XCTAssertEqual(relaunched.state(for: .notoSerifTC, weightID: "regular"), .notDownloaded)
    }

    func testFailedWeightDoesNotChangeAvailableDefaultOrEmitCompletion() async {
        let library = makeLibrary()
        XCTAssertTrue(library.download(.notoSerifTC))
        await waitUntil("bold available") { library.state(for: .notoSerifTC) == .available }
        fetcher.script(regularAsset.primaryURL, .fail(.noNetwork))
        var completed: [FontDownloadID] = []
        library.weightDownloadDidFinish.sink { completed.append($0) }.store(in: &cancellables)
        XCTAssertTrue(library.download(.notoSerifTC, weightID: "regular"))
        await waitUntil("regular failed") { library.state(for: .notoSerifTC, weightID: "regular") == .failed(.noNetwork) }
        XCTAssertEqual(library.state(for: .notoSerifTC), .available)
        XCTAssertTrue(completed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.storedFileURL(for: .notoSerifTC, weightID: "regular").path))
    }

    func testSystemWeightsMatchExactNamesAndPersistSeparately() async {
        let library = makeLibrary()
        XCTAssertTrue(library.download(.songti, weightID: "light"))
        XCTAssertTrue(library.download(.songti, weightID: "regular"))
        XCTAssertEqual(matcher.startedNames, ["STSongti-TC-Light", "STSongti-TC-Regular"])
        matcher.send(.finished(matched: true, offline: false), to: "STSongti-TC-Light")
        matcher.send(.finished(matched: false, offline: false), to: "STSongti-TC-Regular")
        await settle()
        XCTAssertEqual(library.state(for: .songti, weightID: "light"), .available)
        XCTAssertEqual(library.state(for: .songti, weightID: "regular"), .failed(.other))
        XCTAssertEqual(library.state(for: .songti), .notDownloaded)
        XCTAssertEqual(defaults.stringArray(forKey: "downloadedSystemFontWeights"), ["songti/light"])
        XCTAssertTrue(library.downloadedSystemFontIDs.isEmpty)
        let relaunched = makeLibrary()
        XCTAssertEqual(relaunched.state(for: .songti, weightID: "light"), .preparing)
        let task = Task { await relaunched.prepareAtLaunch(priority: .songti, weightID: "light") }
        await waitUntil("light launch match") { matcher.startedNames.count == 3 }
        matcher.send(.finished(matched: true, offline: false), to: "STSongti-TC-Light")
        await task.value
        XCTAssertEqual(relaunched.state(for: .songti, weightID: "light"), .available)
    }

    private var notoAsset: OpenSourceFontAsset {
        OpenSourceFontAsset(
            fileName: "NotoSerifTC-Bold.otf", repositoryPath: "noto/NotoSerifTC-Bold.otf",
            byteCount: fontData.count, sha256: huninnAsset.sha256,
            primaryURL: URL(string: "https://primary.example/noto.otf")!,
            fallbackURL: URL(string: "https://fallback.example/noto.otf")!,
            version: "2.003", copyright: "test", licenseFileNames: [])
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FontLibraryTests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "FontLibraryTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        fetcher = FakeFetcher()
        registrar = FakeRegistrar()
        matcher = FakeMatcher()
        fetcher.script(huninnAsset.primaryURL, .data(fontData))
        fetcher.script(huninnAsset.fallbackURL, .data(fontData))
        fetcher.script(notoAsset.primaryURL, .data(fontData))
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: Helpers

    private func makeLibrary(launchTimeout: TimeInterval = 3,
                             fileManager: FileManager = .default,
                             verifyFile: @escaping @Sendable (URL, OpenSourceFontAsset) -> Bool = FontFileVerifier.isValid(fileAt:for:)) -> FontLibrary {
        let huninn = huninnAsset
        let noto = notoAsset
        let regular = regularAsset
        return FontLibrary(directory: directory, fetcher: fetcher, registrar: registrar, matcher: matcher,
                           defaults: defaults, fileManager: fileManager,
                           launchTimeout: launchTimeout, verifyFile: verifyFile) { fontID in
            let real = FontCatalog.entry(for: fontID)
            switch fontID {
            case .huninn:
                return FontCatalogEntry(fontID: fontID, displayName: real.displayName, section: real.section,
                                        source: .openSource, postScriptName: real.postScriptName,
                                        downloadSizeMegabytes: real.downloadSizeMegabytes, openSource: huninn)
            case .notoSerifTC:
                return FontCatalogEntry(fontID: fontID, displayName: real.displayName, section: real.section,
                                        source: .openSource, postScriptName: real.postScriptName,
                                        downloadSizeMegabytes: real.downloadSizeMegabytes, openSource: noto,
                                        weights: [FontWeightOption(id: "regular", displayName: "標準", postScriptName: "NotoSerifTC-Regular", downloadSizeMegabytes: 0.1, openSource: regular),
                                                  FontWeightOption(id: "bold", displayName: "粗", postScriptName: real.postScriptName, downloadSizeMegabytes: 0.1, openSource: noto)])
            default:
                return real
            }
        }
    }

    /// Waits until `condition` holds; polls because the work runs off the main actor.
    private func waitUntil(_ message: String,
                           timeout: TimeInterval = 5,
                           file: StaticString = #filePath,
                           line: UInt = #line,
                           _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(message)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Lets every callback already queued for the main queue run.
    private func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        await Task.yield()
    }

    private func temporaryFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".download") }
    }

    private func recordStates(of library: FontLibrary, _ fontID: OverlayFontID) -> () -> [FontState] {
        var seen: [FontState] = [library.state(for: fontID)]
        library.$states.sink { states in
            if let state = states[fontID], seen.last != state { seen.append(state) }
        }.store(in: &cancellables)
        return { seen }
    }

    // MARK: A. Open-source fonts

    /// 33.1
    func test_download_verifiesStoresAndRegisters() async throws {
        let library = makeLibrary()
        let seen = recordStates(of: library, .huninn)
        XCTAssertEqual(library.state(for: .huninn), .notDownloaded, "33.1")

        XCTAssertTrue(library.download(.huninn))
        XCTAssertEqual(library.state(for: .huninn), .downloading(progress: 0), "33.1")
        await waitUntil("huninn available") { library.state(for: .huninn) == .available }

        XCTAssertEqual(seen().first, .notDownloaded, "33.1")
        XCTAssertTrue(seen().contains(.downloading(progress: 0)), "33.1")
        XCTAssertEqual(seen().last, .available, "33.1")
        let stored = library.storedFileURL(for: .huninn)
        XCTAssertEqual(stored.deletingLastPathComponent().lastPathComponent, directory.lastPathComponent, "33.1")
        XCTAssertEqual(stored.lastPathComponent, "huninn.ttf", "33.1")
        XCTAssertEqual(try Data(contentsOf: stored), fontData, "33.1")
        let values = try stored.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true, "33.1 not backed up")
        XCTAssertEqual(registrar.registeredURLs, [stored], "33.1 registered once")
        XCTAssertTrue(temporaryFiles().isEmpty, "33.1 no temporary file left")
    }

    /// A finished download is announced so the caller can apply it (A-8).
    func test_download_announcesCompletion() async {
        let library = makeLibrary()
        var finished: [OverlayFontID] = []
        library.downloadDidFinish.sink { finished.append($0) }.store(in: &cancellables)

        library.download(.huninn)
        await waitUntil("announce") { !finished.isEmpty }

        XCTAssertEqual(finished, [.huninn])
    }

    /// 33.2
    func test_download_sha256Mismatch_failsAndLeavesNothing() async {
        fetcher.script(huninnAsset.primaryURL, .data(Data("tampered file of the same!".utf8)))
        fetcher.script(huninnAsset.fallbackURL, .data(Data("tampered file of the same!".utf8)))
        let library = makeLibrary()

        library.download(.huninn)
        await waitUntil("huninn failed") { library.state(for: .huninn) == .failed(.other) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: library.storedFileURL(for: .huninn).path), "33.2")
        XCTAssertTrue(temporaryFiles().isEmpty, "33.2")
        XCTAssertTrue(registrar.registeredURLs.isEmpty, "33.2")
    }

    /// 33.2: a file of the wrong size is rejected too.
    func test_download_wrongSize_fails() async {
        fetcher.script(huninnAsset.primaryURL, .data(fontData + Data([0])))
        fetcher.script(huninnAsset.fallbackURL, .data(fontData + Data([0])))
        let library = makeLibrary()

        library.download(.huninn)
        await waitUntil("huninn failed") { library.state(for: .huninn) == .failed(.other) }

        XCTAssertTrue(registrar.registeredURLs.isEmpty, "33.2")
    }

    /// 33.3
    func test_download_primaryFails_usesFallback() async {
        fetcher.script(huninnAsset.primaryURL, .fail(.other))
        let library = makeLibrary()

        library.download(.huninn)
        await waitUntil("huninn available") { library.state(for: .huninn) == .available }

        XCTAssertEqual(fetcher.requestedURLs, [huninnAsset.primaryURL, huninnAsset.fallbackURL], "33.3")
    }

    /// 33.4
    func test_download_noNetwork_failsAtOnceWithoutFallback() async {
        fetcher.script(huninnAsset.primaryURL, .fail(.noNetwork))
        let library = makeLibrary()

        library.download(.huninn)
        await waitUntil("huninn failed") { library.state(for: .huninn) == .failed(.noNetwork) }

        XCTAssertEqual(fetcher.requestedURLs, [huninnAsset.primaryURL], "33.4")
    }

    /// Both hosts failing for another reason is `.other`; a retry works.
    func test_download_bothFail_thenRetrySucceeds() async {
        fetcher.script(huninnAsset.primaryURL, .fail(.other))
        fetcher.script(huninnAsset.fallbackURL, .fail(.other))
        let library = makeLibrary()
        library.download(.huninn)
        await waitUntil("failed") { library.state(for: .huninn) == .failed(.other) }

        fetcher.script(huninnAsset.primaryURL, .data(fontData))
        XCTAssertTrue(library.download(.huninn), "retry from failed")
        await waitUntil("available") { library.state(for: .huninn) == .available }
    }

    /// Registration failing is a failed download, not a success.
    func test_download_registrationFails_failsAndDeletesFile() async {
        registrar.failRegistration()
        let library = makeLibrary()

        library.download(.huninn)
        await waitUntil("failed") { library.state(for: .huninn) == .failed(.other) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: library.storedFileURL(for: .huninn).path))
    }

    /// 33.5
    func test_cancel_returnsToNotDownloadedAndClearsTemporaryFile() async {
        fetcher.script(huninnAsset.primaryURL, .hang)
        let library = makeLibrary()
        library.download(.huninn)
        await waitUntil("temporary file written") { !temporaryFiles().isEmpty }

        library.cancel(.huninn)

        XCTAssertEqual(library.state(for: .huninn), .notDownloaded, "33.5")
        XCTAssertTrue(temporaryFiles().isEmpty, "33.5")
        await settle()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(library.state(for: .huninn), .notDownloaded, "33.5 stays cancelled")
        XCTAssertTrue(temporaryFiles().isEmpty, "33.5 stale task leaves nothing")
        XCTAssertTrue(registrar.registeredURLs.isEmpty)
    }

    /// 33.6
    func test_delete_removesFileAndRegistration() async {
        let library = makeLibrary()
        library.download(.huninn)
        await waitUntil("available") { library.state(for: .huninn) == .available }
        let stored = library.storedFileURL(for: .huninn)

        XCTAssertTrue(library.delete(.huninn), "33.6")

        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path), "33.6")
        XCTAssertEqual(registrar.unregisteredURLs, [stored], "33.6")
        XCTAssertEqual(library.state(for: .huninn), .notDownloaded, "33.6")
    }

    /// 33.6: system fonts and PingFang cannot be deleted (A-3).
    func test_delete_refusesSystemFontsAndPingFang() {
        let library = makeLibrary()

        XCTAssertFalse(library.delete(.songti), "33.6")
        XCTAssertFalse(library.delete(.pingFang), "33.6")
        XCTAssertEqual(library.state(for: .pingFang), .available, "33.6")
        XCTAssertTrue(registrar.unregisteredURLs.isEmpty, "33.6")
    }

    /// Deleting while downloading stops the download.
    func test_delete_whileDownloading_cancelsIt() async {
        fetcher.script(huninnAsset.primaryURL, .hang)
        let library = makeLibrary()
        library.download(.huninn)
        await waitUntil("partial file") { !temporaryFiles().isEmpty }

        XCTAssertTrue(library.delete(.huninn))

        XCTAssertEqual(library.state(for: .huninn), .notDownloaded)
        XCTAssertTrue(temporaryFiles().isEmpty)
    }

    /// 33.7
    func test_relaunch_registersExistingFileWithoutDownloading() async {
        let first = makeLibrary()
        first.download(.huninn)
        await waitUntil("available") { first.state(for: .huninn) == .available }
        let requestsBefore = fetcher.requestedURLs.count

        let relaunched = makeLibrary()
        XCTAssertEqual(relaunched.state(for: .huninn), .preparing, "33.7")
        await relaunched.prepareAtLaunch(priority: .huninn)

        XCTAssertEqual(relaunched.state(for: .huninn), .available, "33.7")
        XCTAssertEqual(fetcher.requestedURLs.count, requestsBefore, "33.7 no new request")
        XCTAssertEqual(registrar.registeredURLs.count, 2, "33.7 registered again for the new process")
        XCTAssertEqual(relaunched.state(for: .notoSerifTC), .notDownloaded, "33.7")
    }

    /// 33.8: the file is gone.
    func test_relaunch_fileDeletedBeforePreparing_isNotDownloaded() async throws {
        let first = makeLibrary()
        first.download(.huninn)
        await waitUntil("available") { first.state(for: .huninn) == .available }
        let relaunched = makeLibrary()
        try FileManager.default.removeItem(at: relaunched.storedFileURL(for: .huninn))

        await relaunched.prepareAtLaunch(priority: .huninn)

        XCTAssertEqual(relaunched.state(for: .huninn), .notDownloaded, "33.8")
    }

    /// Launch preparation must use the injected file manager, not `FileManager.default`.
    func test_prepareAtLaunch_usesInjectedFileManager() async {
        let first = makeLibrary()
        first.download(.huninn)
        await waitUntil("available") { first.state(for: .huninn) == .available }

        let scripted = ScriptedFileManager()
        let relaunched = makeLibrary(fileManager: scripted)
        XCTAssertEqual(relaunched.state(for: .huninn), .preparing)
        scripted.reportsEverythingMissing = true
        let checksBefore = scripted.existenceChecks

        await relaunched.prepareAtLaunch(priority: .huninn)

        XCTAssertGreaterThan(scripted.existenceChecks, checksBefore, "existence check went through the injected manager")
        XCTAssertEqual(relaunched.state(for: .huninn), .notDownloaded, "injected manager's answer is honoured")
    }

    /// 33.8: the file no longer matches its SHA-256.
    func test_relaunch_corruptFile_failsAndIsRemoved() async throws {
        let first = makeLibrary()
        first.download(.huninn)
        await waitUntil("available") { first.state(for: .huninn) == .available }
        let relaunched = makeLibrary()
        try Data("damaged on disk, same length!".utf8).write(to: relaunched.storedFileURL(for: .huninn))
        let registeredBefore = registrar.registeredURLs.count

        await relaunched.prepareAtLaunch(priority: .huninn)

        XCTAssertEqual(relaunched.state(for: .huninn), .failed(.other), "33.8")
        XCTAssertFalse(FileManager.default.fileExists(atPath: relaunched.storedFileURL(for: .huninn).path), "33.8")
        XCTAssertEqual(registrar.registeredURLs.count, registeredBefore, "33.8 corrupt file not registered")
    }

    /// 132.1: a matching marker skips the SHA-256 pass; a changed size or date re-verifies.
    func test_relaunch_matchingMarker_skipsFullVerification() async throws {
        let first = makeLibrary()
        first.download(.huninn)
        await waitUntil("available") { first.state(for: .huninn) == .available }
        let verifier = CountingVerifier()

        let relaunched = makeLibrary(verifyFile: verifier.verify)
        await relaunched.prepareAtLaunch(priority: .huninn)

        XCTAssertEqual(relaunched.state(for: .huninn), .available)
        XCTAssertEqual(verifier.calls, 0, "132.1 marker match")

        // Same content, newer modification date: marker mismatch re-verifies.
        let url = relaunched.storedFileURL(for: .huninn)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        let touched = makeLibrary(verifyFile: verifier.verify)
        await touched.prepareAtLaunch(priority: .huninn)
        XCTAssertEqual(touched.state(for: .huninn), .available)
        XCTAssertEqual(verifier.calls, 1, "132.1 date changed")

        // The re-verification refreshed the marker.
        let again = makeLibrary(verifyFile: verifier.verify)
        await again.prepareAtLaunch(priority: .huninn)
        XCTAssertEqual(verifier.calls, 1, "132.1 marker refreshed")

        // Different size re-verifies too.
        try Data("a different size entirely, longer".utf8).write(to: url)
        let resized = makeLibrary(verifyFile: verifier.verify)
        await resized.prepareAtLaunch(priority: .huninn)
        XCTAssertEqual(verifier.calls, 2, "132.1 size changed")
    }

    /// 132.1: a file with no marker (installed by an older build) is verified once.
    func test_relaunch_missingMarker_verifiesOnce() async {
        let first = makeLibrary()
        first.download(.huninn)
        await waitUntil("available") { first.state(for: .huninn) == .available }
        defaults.removeObject(forKey: FontLibrary.verificationMarkersKey)
        let verifier = CountingVerifier()

        let relaunched = makeLibrary(verifyFile: verifier.verify)
        await relaunched.prepareAtLaunch(priority: .huninn)
        XCTAssertEqual(relaunched.state(for: .huninn), .available)
        XCTAssertEqual(verifier.calls, 1)

        let again = makeLibrary(verifyFile: verifier.verify)
        await again.prepareAtLaunch(priority: .huninn)
        XCTAssertEqual(verifier.calls, 1, "marker written after the fallback check")
    }

    /// 132.2: a corrupt file whose marker no longer matches is still `.corrupt`.
    func test_relaunch_corruptFileWithStaleMarker_stillFails() async throws {
        let first = makeLibrary()
        first.download(.huninn)
        await waitUntil("available") { first.state(for: .huninn) == .available }
        let relaunched = makeLibrary()
        try Data("damaged on disk, same length!".utf8).write(to: relaunched.storedFileURL(for: .huninn))

        await relaunched.prepareAtLaunch(priority: .huninn)

        XCTAssertEqual(relaunched.state(for: .huninn), .failed(.other), "132.2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: relaunched.storedFileURL(for: .huninn).path))
        let markers = defaults.dictionary(forKey: FontLibrary.verificationMarkersKey) ?? [:]
        XCTAssertNil(markers[relaunched.storedFileURL(for: .huninn).lastPathComponent], "marker cleared")
    }

    /// 132.3: CoreText registration never runs on the main thread.
    func test_registration_doesNotRunOnMainThread() async {
        let first = makeLibrary()
        first.download(.huninn)
        await waitUntil("available") { first.state(for: .huninn) == .available }
        XCTAssertEqual(registrar.registeredURLs.count, 1)

        let relaunched = makeLibrary()
        await relaunched.prepareAtLaunch(priority: .huninn)
        XCTAssertEqual(relaunched.state(for: .huninn), .available)
        XCTAssertEqual(registrar.registeredURLs.count, 2)
        XCTAssertEqual(registrar.mainThreadRegistrations, 0, "132.3")
    }

    /// Leftover temporary files from a killed download are cleaned at launch.
    func test_prepareAtLaunch_removesStaleTemporaryFiles() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("huninn.ttf.ABC.download"))
        let library = makeLibrary()

        await library.prepareAtLaunch()

        XCTAssertTrue(temporaryFiles().isEmpty)
    }

    // MARK: B. System fonts

    /// 33.9: an error mid-way (e.g. #302) does not fail a match that succeeds.
    func test_systemDownload_midwayErrorButMatched_isAvailable() async {
        let library = makeLibrary()
        var finished: [OverlayFontID] = []
        library.downloadDidFinish.sink { finished.append($0) }.store(in: &cancellables)

        library.download(.songti)
        XCTAssertEqual(library.state(for: .songti), .downloading(progress: 0), "33.9")
        XCTAssertEqual(matcher.startedNames, ["STSongti-TC-Bold"], "33.9")
        XCTAssertTrue(matcher.send(.downloading(fraction: 0.4, totalBytes: 100), to: "STSongti-TC-Bold"))
        await waitUntil("progress") { library.state(for: .songti) == .downloading(progress: 0.4) }
        XCTAssertTrue(matcher.send(.failed, to: "STSongti-TC-Bold"), "33.9 an error does not cancel")
        matcher.send(.finished(matched: true, offline: false), to: "STSongti-TC-Bold")
        await waitUntil("available") { library.state(for: .songti) == .available }

        XCTAssertEqual(library.state(for: .songti), .available, "33.9")
        XCTAssertEqual(library.downloadedSystemFontIDs, [.songti], "33.9")
        XCTAssertEqual(defaults.stringArray(forKey: "downloadedSystemFontIDs"), ["songti"], "33.9")
        XCTAssertEqual(finished, [.songti], "33.9")
    }

    /// 33.9: at launch too.
    func test_launch_midwayErrorButMatched_isAvailable() async {
        defaults.set(["liHei"], forKey: "downloadedSystemFontIDs")
        let library = makeLibrary()
        XCTAssertEqual(library.state(for: .liHei), .preparing, "33.9")

        let prepared = Task { await library.prepareAtLaunch(priority: .liHei) }
        await waitUntil("match started") { !matcher.startedNames.isEmpty }
        matcher.send(.failed, to: "LiHeiPro")
        matcher.send(.finished(matched: true, offline: false), to: "LiHeiPro")
        await prepared.value

        XCTAssertEqual(library.state(for: .liHei), .available, "33.9")
    }

    /// A system font that ends unmatched fails; a "no connection" error says so.
    func test_systemDownload_unmatched_failsWithReason() async {
        let library = makeLibrary()
        library.download(.songti)
        library.download(.liHei)

        matcher.send(.finished(matched: false, offline: true), to: "STSongti-TC-Bold")
        matcher.send(.finished(matched: false, offline: false), to: "LiHeiPro")
        await waitUntil("both failed") {
            library.state(for: .songti) == .failed(.noNetwork) && library.state(for: .liHei) == .failed(.other)
        }

        XCTAssertTrue(library.downloadedSystemFontIDs.isEmpty, "a failed font is not remembered")
    }

    /// Cancelling a system download: the match is told to stop.
    func test_cancel_systemDownload_cancelsMatch() async {
        let library = makeLibrary()
        library.download(.songti)

        library.cancel(.songti)

        XCTAssertEqual(library.state(for: .songti), .notDownloaded)
        XCTAssertFalse(matcher.send(.downloading(fraction: 0.2, totalBytes: 100), to: "STSongti-TC-Bold"),
                       "the progress handler answers false")
        matcher.send(.finished(matched: true, offline: false), to: "STSongti-TC-Bold")
        await settle()
        XCTAssertEqual(library.state(for: .songti), .notDownloaded, "late callbacks are ignored")
        XCTAssertTrue(library.downloadedSystemFontIDs.isEmpty)
    }

    /// 33.10: no answer within the timeout. Matches run one after another and
    /// each font's timeout counts from its own start, so the next one is not
    /// judged by time the previous one used.
    func test_launch_matchTimesOut_failsAndIgnoresLateCallbacks() async {
        defaults.set(["liHei", "xingkai"], forKey: "downloadedSystemFontIDs")
        let library = makeLibrary(launchTimeout: 0.4)

        let prepared = Task { await library.prepareAtLaunch(priority: .liHei) }
        await waitUntil("first started") { matcher.startedNames == ["LiHeiPro"] }
        XCTAssertEqual(library.state(for: .xingkai), .preparing, "33.10 queued behind the priority font")

        await prepared.value

        XCTAssertEqual(library.state(for: .liHei), .failed(.other), "33.10")
        XCTAssertFalse(matcher.send(.downloading(fraction: 0.1, totalBytes: 0), to: "LiHeiPro"),
                       "33.10 the matcher is told to cancel")
        matcher.send(.finished(matched: true, offline: false), to: "LiHeiPro")
        await settle()
        XCTAssertEqual(library.state(for: .liHei), .failed(.other), "33.10 late callbacks ignored")
        XCTAssertTrue(library.downloadedSystemFontIDs.contains(.liHei), "a timeout keeps the record")

        // The second font starts only now; answering 0.3 s later, i.e. 0.7 s
        // after the first began, must not count as a timeout.
        await waitUntil("second started") { matcher.startedNames == ["LiHeiPro", "STXingkaiTC-Bold"] }
        try? await Task.sleep(nanoseconds: 300_000_000)
        matcher.send(.finished(matched: true, offline: false), to: "STXingkaiTC-Bold")
        await waitUntil("xingkai available") { library.state(for: .xingkai) == .available }

        XCTAssertTrue(library.download(.liHei), "33.10 retry allowed")
        XCTAssertEqual(matcher.startedNames.filter { $0 == "LiHeiPro" }.count, 2, "33.10")
    }

    /// 33.10a: a download report without any size still means "would download".
    func test_launch_downloadReportWithoutSize_isCancelled() async {
        defaults.set(["xingkai", "liHei"], forKey: "downloadedSystemFontIDs")
        let library = makeLibrary()

        let prepared = Task { await library.prepareAtLaunch(priority: .xingkai) }
        await waitUntil("started") { !matcher.startedNames.isEmpty }
        let answer = matcher.send(.downloadWillBegin(totalBytes: 0), to: "STXingkaiTC-Bold")
        await prepared.value

        XCTAssertFalse(answer, "33.10a size 0 still cancels")
        XCTAssertEqual(library.state(for: .xingkai), .notDownloaded, "33.10a")
        XCTAssertEqual(library.downloadedSystemFontIDs, [.liHei], "33.10a")
        // The queue moves on to the next font.
        await waitUntil("next started") { matcher.startedNames.contains("LiHeiPro") }
    }

    /// `downloading` without a size cancels too.
    func test_launch_downloadingWithoutSize_isCancelled() async {
        defaults.set(["xingkai"], forKey: "downloadedSystemFontIDs")
        let library = makeLibrary()

        let prepared = Task { await library.prepareAtLaunch(priority: .xingkai) }
        await waitUntil("started") { !matcher.startedNames.isEmpty }
        let answer = matcher.send(.downloading(fraction: 0, totalBytes: 0), to: "STXingkaiTC-Bold")
        await prepared.value

        XCTAssertFalse(answer)
        XCTAssertEqual(library.state(for: .xingkai), .notDownloaded)
        XCTAssertTrue(library.downloadedSystemFontIDs.isEmpty)
    }

    /// prepareAtLaunch runs once per library, and never removes the temporary
    /// file of a download in progress.
    func test_prepareAtLaunch_secondCallDoesNothing_andKeepsActiveTemporaryFile() async {
        fetcher.script(huninnAsset.primaryURL, .hang)
        defaults.set(["liHei"], forKey: "downloadedSystemFontIDs")
        let library = makeLibrary(launchTimeout: 0.3)
        let first = Task { await library.prepareAtLaunch() }
        await waitUntil("match started") { !matcher.startedNames.isEmpty }
        library.download(.huninn)
        await waitUntil("partial file") { !temporaryFiles().isEmpty }
        let before = temporaryFiles()

        await library.prepareAtLaunch(priority: .huninn)

        XCTAssertEqual(temporaryFiles(), before, "a running download keeps its temporary file")
        XCTAssertEqual(library.state(for: .liHei), .preparing, "the second call did not wait or restart")
        XCTAssertEqual(matcher.startedNames, ["LiHeiPro"], "no second match")
        await first.value
        await library.prepareAtLaunch()
        XCTAssertEqual(matcher.startedNames, ["LiHeiPro"], "still one match")
        library.cancelAllDownloads()
    }

    private func queueSixSystemFonts() {
        defaults.set(["liHei", "hiraginoSans", "liSong", "biauKai", "weibei", "wawa"],
                     forKey: "downloadedSystemFontIDs")
    }

    /// FR-5.16: the sixth queued font is matched at once, in parallel, and is
    /// settled long before the queue would have reached it.
    func test_prepare_sixthQueuedFont_isMatchedAtOnceWithoutAffectingOthers() async {
        queueSixSystemFonts()
        let library = makeLibrary(launchTimeout: 3)
        let launch = Task { await library.prepareAtLaunch() }
        await waitUntil("first started") { matcher.startedNames == ["LiHeiPro"] }

        let started = Date()
        let prepared = Task { await library.prepare(.wawa) }
        await waitUntil("wawa started") { matcher.startedNames.contains("DFWaWaTC-W5") }
        XCTAssertEqual(matcher.startedNames, ["LiHeiPro", "DFWaWaTC-W5"], "started alongside the running match")
        matcher.send(.finished(matched: true, offline: false), to: "DFWaWaTC-W5")
        await prepared.value

        XCTAssertEqual(library.state(for: .wawa), .available)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertEqual(library.state(for: .liHei), .preparing, "the running match is untouched")
        XCTAssertEqual(library.state(for: .hiraginoSans), .preparing, "queued fonts are untouched")
        // The queue later skips the font that is already settled.
        matcher.send(.finished(matched: true, offline: false), to: "LiHeiPro")
        await waitUntil("next in queue") { matcher.startedNames.contains("HiraginoSansTC-W6") }
        XCTAssertEqual(library.state(for: .liHei), .available)
        XCTAssertEqual(matcher.startedNames.filter { $0 == "DFWaWaTC-W5" }.count, 1, "matched once")
        launch.cancel()
    }

    /// FR-5.15: the out-of-queue match also times out 3 seconds after it starts.
    func test_prepare_timesOutFromItsOwnStart() async {
        queueSixSystemFonts()
        let library = makeLibrary(launchTimeout: 0.4)
        let launch = Task { await library.prepareAtLaunch() }
        await waitUntil("first started") { matcher.startedNames == ["LiHeiPro"] }
        try? await Task.sleep(nanoseconds: 300_000_000)

        let started = Date()
        await library.prepare(.wawa)

        XCTAssertEqual(library.state(for: .wawa), .failed(.other))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.4 + 1.0, "counted from its own start")
        XCTAssertFalse(matcher.send(.downloading(fraction: 0.1, totalBytes: 0), to: "DFWaWaTC-W5"))
        launch.cancel()
    }

    /// prepareAtLaunch(priority:) and prepare() waiting for the same font get
    /// the same result from a single match.
    func test_prepare_andPrepareAtLaunchWaitingForSameFont_shareOneMatch() async {
        defaults.set(["liHei"], forKey: "downloadedSystemFontIDs")
        let library = makeLibrary()
        let launch = Task { await library.prepareAtLaunch(priority: .liHei) }
        await waitUntil("match started") { matcher.startedNames == ["LiHeiPro"] }
        let prepared = Task { await library.prepare(.liHei) }
        await Task.yield()

        matcher.send(.finished(matched: true, offline: false), to: "LiHeiPro")
        await launch.value
        await prepared.value

        XCTAssertEqual(library.state(for: .liHei), .available)
        XCTAssertEqual(matcher.startedNames, ["LiHeiPro"], "matched once")
    }

    /// A download report cancels a prepare() match too; a settled font returns at once.
    func test_prepare_wouldDownload_cancelsAndSettledReturnsAtOnce() async {
        queueSixSystemFonts()
        let library = makeLibrary()
        let launch = Task { await library.prepareAtLaunch() }
        await waitUntil("first started") { !matcher.startedNames.isEmpty }

        let prepared = Task { await library.prepare(.wawa) }
        await waitUntil("wawa started") { matcher.startedNames.contains("DFWaWaTC-W5") }
        XCTAssertFalse(matcher.send(.downloadWillBegin(totalBytes: 0), to: "DFWaWaTC-W5"))
        await prepared.value

        XCTAssertEqual(library.state(for: .wawa), .notDownloaded)
        XCTAssertFalse(library.downloadedSystemFontIDs.contains(.wawa))
        await library.prepare(.wawa)
        await library.prepare(.pingFang)
        launch.cancel()
    }

    /// A disk error does not try the fallback host.
    func test_download_storageFailure_doesNotTryFallback() async {
        fetcher.script(huninnAsset.primaryURL, .fail(.storage))
        let library = makeLibrary()

        library.download(.huninn)
        await waitUntil("failed") { library.state(for: .huninn) == .failed(.other) }

        XCTAssertEqual(fetcher.requestedURLs, [huninnAsset.primaryURL])
    }

    /// Moving the verified file into place fails: failed, no fallback, no registration.
    func test_download_moveFails_doesNotTryFallback() async throws {
        let directoryToLock = directory
        fetcher.onFetched = {
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directoryToLock.path)
        }
        let library = makeLibrary()

        library.download(.huninn)
        await waitUntil("failed") { library.state(for: .huninn) == .failed(.other) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)

        XCTAssertEqual(fetcher.requestedURLs, [huninnAsset.primaryURL])
        XCTAssertTrue(registrar.registeredURLs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.storedFileURL(for: .huninn).path))
    }

    /// 33.10a: the system cleared the font, so the match would download.
    func test_launch_matchWouldDownload_isCancelledAndForgotten() async {
        defaults.set(["xingkai", "liHei"], forKey: "downloadedSystemFontIDs")
        let library = makeLibrary()

        let prepared = Task { await library.prepareAtLaunch(priority: .xingkai) }
        await waitUntil("started") { matcher.startedNames.contains("STXingkaiTC-Bold") }
        let answer = matcher.send(.downloadWillBegin(totalBytes: 54_000_000), to: "STXingkaiTC-Bold")
        await prepared.value

        XCTAssertFalse(answer, "33.10a the handler cancels the match")
        XCTAssertEqual(library.state(for: .xingkai), .notDownloaded, "33.10a")
        XCTAssertEqual(library.downloadedSystemFontIDs, [.liHei], "33.10a removed from the list")
        XCTAssertEqual(defaults.stringArray(forKey: "downloadedSystemFontIDs"), ["liHei"], "33.10a")
        // Nothing was downloaded, and later callbacks change nothing.
        XCTAssertFalse(matcher.send(.downloading(fraction: 0.1, totalBytes: 54_000_000), to: "STXingkaiTC-Bold"))
        matcher.send(.finished(matched: true, offline: false), to: "STXingkaiTC-Bold")
        await settle()
        XCTAssertEqual(library.state(for: .xingkai), .notDownloaded, "33.10a")
    }

    /// 33.10a: a download progress report with bytes counts as "would download".
    func test_launch_downloadingEventWithBytes_isCancelled() async {
        defaults.set(["xingkai"], forKey: "downloadedSystemFontIDs")
        let library = makeLibrary()

        let prepared = Task { await library.prepareAtLaunch(priority: .xingkai) }
        await waitUntil("started") { !matcher.startedNames.isEmpty }
        let answer = matcher.send(.downloading(fraction: 0, totalBytes: 54_000_000), to: "STXingkaiTC-Bold")
        await prepared.value

        XCTAssertFalse(answer, "33.10a")
        XCTAssertEqual(library.state(for: .xingkai), .notDownloaded, "33.10a")
        XCTAssertTrue(library.downloadedSystemFontIDs.isEmpty, "33.10a")
    }

    /// 33.10b
    func test_launch_emptyList_matchesNothing() async {
        let library = makeLibrary()

        await library.prepareAtLaunch(priority: .songti)
        await library.prepareAtLaunch()

        XCTAssertTrue(matcher.startedNames.isEmpty, "33.10b")
        for fontID in OverlayFontID.allCases where FontCatalog.entry(for: fontID).source == .system {
            XCTAssertEqual(library.state(for: fontID), .notDownloaded, "33.10b \(fontID)")
        }
    }

    /// 33.10c
    func test_cancelAllDownloads_failsEveryDownloadAndClearsTemporaryFiles() async {
        fetcher.script(huninnAsset.primaryURL, .hang)
        let library = makeLibrary()
        library.download(.huninn)
        library.download(.songti)
        await waitUntil("partial file") { !temporaryFiles().isEmpty }

        library.cancelAllDownloads()

        XCTAssertEqual(library.state(for: .huninn), .failed(.other), "33.10c")
        XCTAssertEqual(library.state(for: .songti), .failed(.other), "33.10c")
        XCTAssertTrue(temporaryFiles().isEmpty, "33.10c")
        XCTAssertFalse(matcher.send(.downloading(fraction: 0.3, totalBytes: 100), to: "STSongti-TC-Bold"), "33.10c")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(library.state(for: .huninn), .failed(.other), "33.10c stale task changes nothing")

        // Back in the foreground the user can retry.
        fetcher.script(huninnAsset.primaryURL, .data(fontData))
        XCTAssertTrue(library.download(.huninn))
        await waitUntil("retry works") { library.state(for: .huninn) == .available }
    }

    // MARK: Guards

    /// Starting a download is only allowed from not-downloaded or failed.
    func test_download_ignoredWhenAlreadyBusyOrAvailable() async {
        fetcher.script(huninnAsset.primaryURL, .hang)
        let library = makeLibrary()

        XCTAssertFalse(library.download(.pingFang))
        XCTAssertTrue(library.download(.huninn))
        XCTAssertFalse(library.download(.huninn), "already downloading")
        XCTAssertTrue(library.download(.songti))
        XCTAssertFalse(library.download(.songti), "already downloading")
        library.cancelAllDownloads()
    }

    /// FontAvailabilityProviding: PingFang is always available.
    func test_pingFangIsAlwaysAvailable() {
        let library = makeLibrary()
        let provider: FontAvailabilityProviding = library
        XCTAssertEqual(provider.state(for: .pingFang), .available)
        XCTAssertEqual(provider.state(for: .kaiti), .notDownloaded)
    }

    // MARK: 33.12 Integration (simulator, needs network)

    /// 33.12: really match `LiHeiPro`. Skipped without a network.
    func test_integration_realMatchOfLiHeiPro() async throws {
        let library = FontLibrary(directory: directory, defaults: defaults)

        library.download(.liHei)
        await waitUntil("match over", timeout: 180) {
            switch library.state(for: .liHei) {
            case .downloading: return false
            default: return true
            }
        }

        if case .failed(let reason) = library.state(for: .liHei) {
            throw XCTSkip("33.12 skipped: the real match failed (\(reason)); this run has no usable network")
        }
        XCTAssertEqual(library.state(for: .liHei), .available, "33.12")
        XCTAssertNotNil(UIFont(name: "LiHeiPro", size: 17), "33.12")
        XCTAssertEqual(library.downloadedSystemFontIDs, [.liHei], "33.12")
    }
}
