import CryptoKit
import XCTest
@testable import DaysCam

/// TASK-33 independent QA. Two end-to-end scenarios through the public
/// `FontLibrary` API with fakes written separately from the developer's unit
/// tests:
/// - 33.7: an open-source font downloaded, the library rebuilt (a relaunch),
///   `prepareAtLaunch` makes it available again without touching the network.
/// - 33.10a / FR-5.15: a recorded system font that the system has cleared is
///   never re-downloaded: the match is cancelled, the font leaves
///   `downloadedSystemFontIDs` and is `notDownloaded`.
@MainActor
final class FontLibraryAcceptanceTests: XCTestCase {
    private final class CountingFetcher: FontFileFetching, @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        let payload: Data
        init(payload: Data) { self.payload = payload }
        var requested: [URL] { lock.withLock { urls } }
        func fetch(from url: URL, to destination: URL,
                   progress: @escaping @Sendable (Double) -> Void) async throws {
            lock.withLock { urls.append(url) }
            try payload.write(to: destination)
            progress(1)
        }
    }

    private final class CountingRegistrar: FontRegistering, @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [URL] = []
        var registered: [URL] { lock.withLock { calls } }
        func register(fontAt url: URL) -> Bool { lock.withLock { calls.append(url) }; return true }
        func unregister(fontAt url: URL) {}
    }

    private final class CapturingMatcher: SystemFontMatching, @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [@Sendable (SystemFontMatchEvent) -> Bool] = []
        var matchCount: Int { lock.withLock { handlers.count } }
        func startMatching(postScriptName: String,
                           handler: @escaping @Sendable (SystemFontMatchEvent) -> Bool) {
            lock.withLock { handlers.append(handler) }
        }
        func send(_ event: SystemFontMatchEvent) -> Bool {
            let handler = lock.withLock { handlers.last }
            return handler?(event) ?? false
        }
    }

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FontLibraryAcceptance-\(UUID().uuidString)", isDirectory: true)
        suiteName = "FontLibraryAcceptance-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeLibrary(fetcher: FontFileFetching, registrar: FontRegistering,
                             matcher: SystemFontMatching, asset: OpenSourceFontAsset) -> FontLibrary {
        FontLibrary(directory: directory, fetcher: fetcher, registrar: registrar, matcher: matcher,
                    defaults: defaults) { fontID in
            let real = FontCatalog.entry(for: fontID)
            guard fontID == .huninn else { return real }
            return FontCatalogEntry(fontID: fontID, displayName: real.displayName, section: real.section,
                                    source: .openSource, postScriptName: real.postScriptName,
                                    downloadSizeMegabytes: real.downloadSizeMegabytes, openSource: asset)
        }
    }

    /// 33.7
    func test_acceptance_33_7_downloadedOpenSourceFontSurvivesRelaunchWithoutNetwork() async throws {
        let payload = Data("acceptance font bytes".utf8)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let asset = OpenSourceFontAsset(
            fileName: "acc.ttf", repositoryPath: "acc.ttf", byteCount: payload.count, sha256: digest,
            primaryURL: try XCTUnwrap(URL(string: "https://primary.invalid/acc.ttf")),
            fallbackURL: try XCTUnwrap(URL(string: "https://fallback.invalid/acc.ttf")),
            version: "1", copyright: "test", licenseFileNames: [])
        let fetcher = CountingFetcher(payload: payload)
        let registrar = CountingRegistrar()
        let matcher = CapturingMatcher()

        let first = makeLibrary(fetcher: fetcher, registrar: registrar, matcher: matcher, asset: asset)
        XCTAssertTrue(first.download(.huninn))
        let deadline = Date().addingTimeInterval(5)
        while first.state(for: .huninn) != .available, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(first.state(for: .huninn), .available)
        XCTAssertEqual(fetcher.requested.count, 1)
        XCTAssertEqual(registrar.registered.count, 1)

        // "Relaunch": a fresh library over the same directory and defaults.
        let second = makeLibrary(fetcher: fetcher, registrar: registrar, matcher: matcher, asset: asset)
        await second.prepareAtLaunch(priority: .huninn)

        XCTAssertEqual(second.state(for: .huninn), .available, "33.7 available after relaunch")
        XCTAssertEqual(fetcher.requested.count, 1, "33.7 no new network request")
        XCTAssertEqual(registrar.registered.count, 2, "33.7 registered again in the new process")
        XCTAssertEqual(matcher.matchCount, 0, "33.10b no system font matched")
    }

    /// 33.10a / FR-5.15
    func test_acceptance_33_10a_systemFontClearedBySystemIsCancelledNotDownloaded() async throws {
        defaults.set(["xingkai"], forKey: FontLibrary.downloadedSystemFontIDsKey)
        let matcher = CapturingMatcher()
        let fetcher = CountingFetcher(payload: Data())
        let registrar = CountingRegistrar()
        let library = FontLibrary(directory: directory, fetcher: fetcher, registrar: registrar,
                                  matcher: matcher, defaults: defaults)
        XCTAssertEqual(library.state(for: .xingkai), .preparing)

        let prepared = Task { await library.prepareAtLaunch(priority: .xingkai) }
        let deadline = Date().addingTimeInterval(5)
        while matcher.matchCount == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(matcher.matchCount, 1, "the recorded font is matched at launch")

        // The system reports it would download 54 MB.
        let keepGoing = matcher.send(.downloadWillBegin(totalBytes: 54_000_000))
        await prepared.value

        XCTAssertFalse(keepGoing, "33.10a the handler returns false: the match is cancelled")
        XCTAssertFalse(matcher.send(.downloading(fraction: 0.1, totalBytes: 54_000_000)),
                       "33.10a still cancelled: no bytes are accepted")
        XCTAssertEqual(library.state(for: .xingkai), .notDownloaded, "33.10a")
        XCTAssertEqual(library.downloadedSystemFontIDs, [], "33.10a removed from the list")
        XCTAssertEqual(defaults.stringArray(forKey: FontLibrary.downloadedSystemFontIDsKey) ?? [], [],
                       "33.10a persisted")
        XCTAssertEqual(matcher.matchCount, 1, "33.10a no second match (no automatic download)")
        XCTAssertTrue(fetcher.requested.isEmpty)
    }

    /// 33.10a / FR-5.15, any download state without a byte count (Lead: "不附下載量")
    func test_acceptance_33_10a_downloadReportWithoutByteCountIsAlsoCancelled() async throws {
        defaults.set(["xingkai"], forKey: FontLibrary.downloadedSystemFontIDsKey)
        let matcher = CapturingMatcher()
        let fetcher = CountingFetcher(payload: Data())
        let registrar = CountingRegistrar()
        let library = FontLibrary(directory: directory, fetcher: fetcher, registrar: registrar,
                                  matcher: matcher, defaults: defaults)
        XCTAssertEqual(library.state(for: .xingkai), .preparing)

        let prepared = Task { await library.prepareAtLaunch(priority: .xingkai) }
        let deadline = Date().addingTimeInterval(5)
        while matcher.matchCount == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(matcher.matchCount, 1, "the recorded font is matched at launch")

        // The system reports it will download, with no size.
        let keepGoing = matcher.send(.downloadWillBegin(totalBytes: 0))
        await prepared.value

        XCTAssertFalse(keepGoing, "33.10a the handler returns false: the match is cancelled")
        XCTAssertFalse(matcher.send(.downloading(fraction: 0.1, totalBytes: 54_000_000)),
                       "33.10a still cancelled: no bytes are accepted")
        XCTAssertEqual(library.state(for: .xingkai), .notDownloaded, "33.10a")
        XCTAssertEqual(library.downloadedSystemFontIDs, [], "33.10a removed from the list")
        XCTAssertEqual(defaults.stringArray(forKey: FontLibrary.downloadedSystemFontIDsKey) ?? [], [],
                       "33.10a persisted")
        XCTAssertEqual(matcher.matchCount, 1, "33.10a no second match (no automatic download)")
        XCTAssertTrue(fetcher.requested.isEmpty)
    }
}
