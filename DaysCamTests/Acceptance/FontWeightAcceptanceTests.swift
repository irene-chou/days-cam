import CryptoKit
import XCTest
@testable import DaysCam

/// TASK-89 part 1 independent QA (#367). The expected tables below are typed
/// from Issue #362 (core-style verification table and the Lead's 89.1
/// confirmation), not read back from `FontCatalog`.
@MainActor
final class FontWeightAcceptanceTests: XCTestCase {
    private struct Face { let id: String; let postScript: String }

    private static let approved: [OverlayFontID: (defaultID: String, faces: [Face])] = [
        .pingFang: ("semibold", [Face(id: "light", postScript: "PingFangTC-Light"),
                                 Face(id: "regular", postScript: "PingFangTC-Regular"),
                                 Face(id: "semibold", postScript: "PingFangTC-Semibold")]),
        .notoSerifTC: ("bold", [Face(id: "regular", postScript: "NotoSerifTC-Regular"),
                                Face(id: "bold", postScript: "NotoSerifTC-Bold"),
                                Face(id: "black", postScript: "NotoSerifTC-Black")]),
        .hiraginoSans: ("w6", [Face(id: "w3", postScript: "HiraginoSansTC-W3"),
                               Face(id: "w6", postScript: "HiraginoSansTC-W6")]),
        .songti: ("bold", [Face(id: "light", postScript: "STSongti-TC-Light"),
                           Face(id: "regular", postScript: "STSongti-TC-Regular"),
                           Face(id: "bold", postScript: "STSongti-TC-Bold")]),
        .kaiti: ("bold", [Face(id: "regular", postScript: "STKaitiTC-Regular"),
                          Face(id: "bold", postScript: "STKaitiTC-Bold"),
                          Face(id: "black", postScript: "STKaitiTC-Black")]),
        .yuanti: ("bold", [Face(id: "light", postScript: "STYuanti-TC-Light"),
                           Face(id: "regular", postScript: "STYuanti-TC-Regular"),
                           Face(id: "bold", postScript: "STYuanti-TC-Bold")]),
        .hannotate: ("w7", [Face(id: "w5", postScript: "HannotateTC-W5"),
                            Face(id: "w7", postScript: "HannotateTC-W7")]),
        .chenyuluoyan: ("thin", [Face(id: "thin", postScript: "ChenYuluoyan-2.0-Thin")])
    ]

    private struct AllAvailable: FontAvailabilityProviding {
        func state(for fontID: OverlayFontID) -> FontState { .available }
    }

    // MARK: - 89.1

    func test_acceptance_89_1_listMatchesLeadApproval() throws {
        for fontID in OverlayFontID.allCases {
            let entry = FontCatalog.entry(for: fontID)
            XCTAssertLessThanOrEqual(entry.weights.count, 3, "\(fontID) at most three")
            XCTAssertEqual(Set(entry.weights.map(\.id)).count, entry.weights.count, "\(fontID) ids unique")
            if let expected = Self.approved[fontID] {
                XCTAssertEqual(entry.weights.map(\.id), expected.faces.map(\.id), "\(fontID) ids and order")
                XCTAssertEqual(entry.weights.map(\.postScriptName), expected.faces.map(\.postScript), "\(fontID)")
                XCTAssertEqual(entry.defaultWeight.id, expected.defaultID, "\(fontID) default")
            } else {
                XCTAssertEqual(entry.weights.count, 1, "\(fontID) not on the list stays single-weight")
            }
            // Default face is the legacy face: same PostScript name as the font always drew.
            XCTAssertEqual(entry.defaultWeight.postScriptName, entry.postScriptName, "\(fontID)")
            XCTAssertEqual(entry.defaultWeight.postScriptName, fontID.postScriptName)
        }
    }

    func test_acceptance_89_1_legacyDefaultPostScriptNamesUnchanged() {
        let legacy: [OverlayFontID: String] = [
            .pingFang: "PingFangTC-Semibold", .notoSerifTC: "NotoSerifTC-Bold",
            .hiraginoSans: "HiraginoSansTC-W6", .songti: "STSongti-TC-Bold",
            .kaiti: "STKaitiTC-Bold", .yuanti: "STYuanti-TC-Bold",
            .hannotate: "HannotateTC-W7", .chenyuluoyan: "ChenYuluoyan-2.0-Thin",
            .iansui: "Iansui-Regular", .huninn: "jf-openhuninn-2.1"
        ]
        for (fontID, name) in legacy {
            XCTAssertEqual(FontCatalog.entry(for: fontID).defaultWeight.postScriptName, name, "\(fontID)")
        }
    }

    func test_acceptance_89_1_newNotoAssetsMatchVerifiedFacts() throws {
        let facts: [(String, Int, String)] = [
            ("regular", 7_936_104, "63515eb0622d589a2f4062e8757c598b3da3bffd053f69abd181c210158ef10c"),
            ("black", 8_122_092, "55c68df309e702cdb56b9ffd6b8185468afc0cb070aa9c2f14099de0cae64d12"),
            ("bold", 8_253_304, "3ca2b3294ec84b795d0a45695e78e3612a44dce50f9fc776cd40206340a5768d")
        ]
        let entry = FontCatalog.entry(for: .notoSerifTC)
        for (id, bytes, sha) in facts {
            let asset = try XCTUnwrap(entry.weight(for: id).openSource, id)
            XCTAssertEqual(asset.byteCount, bytes, id)
            XCTAssertEqual(asset.sha256, sha, id)
            XCTAssertEqual(asset.fileName, "NotoSerifTC-\(id.prefix(1).uppercased() + id.dropFirst()).otf")
            // New faces pin the upstream commit; the existing Bold keeps its dayscam-fonts v2 URLs.
            let pinned = id != "bold"
            for url in [asset.primaryURL, asset.fallbackURL] {
                XCTAssertEqual(url.absoluteString.contains("f8d157532fbfaeda587e826d4cd5b21a49186f7c"), pinned, id)
                XCTAssertTrue(url.absoluteString.hasSuffix(asset.repositoryPath) || pinned, id)
            }
            XCTAssertFalse(asset.copyright.isEmpty)
            XCTAssertFalse(asset.licenseFileNames.isEmpty)
        }
    }

    // MARK: - 89.2 / 89.4 / 89.6

    func test_acceptance_89_2_legacyJSONWithoutWeightLoadsDefaultForEveryFont() throws {
        for fontID in OverlayFontID.allCases {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(OverlayStyle(fontID: fontID))) as? [String: Any])
            json.removeValue(forKey: "fontWeight")
            let style = try JSONDecoder().decode(OverlayStyle.self,
                                                 from: JSONSerialization.data(withJSONObject: json))
            let entry = FontCatalog.entry(for: fontID)
            XCTAssertEqual(style.fontID, fontID)
            XCTAssertEqual(style.resolvedFontWeight.id, entry.defaultWeight.id, "\(fontID)")
            // Pre-TASK-89 resolution policy: the legacy PostScript name, loaded if this device can.
            let before = OverlayMetrics.resolvedFont(state: .available, postScriptName: entry.postScriptName)
            let font = OverlayMetrics.resolvedFont(for: style, availability: AllAvailable())
            XCTAssertEqual(font, before, "\(fontID) same face as before")
            XCTAssertEqual(entry.defaultWeight.postScriptName, entry.postScriptName)
        }
    }

    func test_acceptance_89_4_changingFontResetsWeightAndSameFontKeeps() throws {
        var style = OverlayStyle(fontID: .notoSerifTC, fontWeight: "black")
        XCTAssertEqual(style.fontWeight, "black")
        style.fontID = .notoSerifTC
        XCTAssertEqual(style.fontWeight, "black", "assigning the same font keeps the weight")
        style.fontID = .kaiti
        XCTAssertEqual(style.fontWeight, "bold", "different font resets to that font's default")
        style.fontWeight = "black"
        style.fontID = .pingFang
        XCTAssertEqual(style.fontWeight, "semibold")
        XCTAssertEqual(style.resolvedFontWeight.postScriptName, "PingFangTC-Semibold")
        // Weight id from another family is not honoured, in either entry path.
        XCTAssertEqual(OverlayStyle(fontID: .kaiti, fontWeight: "light").fontWeight, "bold")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(OverlayStyle(fontID: .kaiti))) as? [String: Any])
        json["fontWeight"] = "light"
        let decoded = try JSONDecoder().decode(OverlayStyle.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.fontWeight, "bold")
        // Round trip keeps a valid choice.
        let chosen = OverlayStyle(fontID: .kaiti, fontWeight: "black")
        let reopened = try JSONDecoder().decode(OverlayStyle.self, from: JSONEncoder().encode(chosen))
        XCTAssertEqual(reopened, chosen)
        XCTAssertEqual(reopened.fontWeight, "black")
    }

    func test_acceptance_89_6_malformedWeightFallsBackAndKeepsEveryOtherSetting() throws {
        let original = OverlayStyle(fontID: .songti, textColor: try XCTUnwrap(OverlayColor(hex: "#FF8800")),
                                    outline: .stroke, sizeScale: 130)
        let good = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(original)) as? [String: Any])
        let bad: [Any] = ["", "BOLD", "thin", 7, 1.5, true, [String](), ["id": "bold"], NSNull(), " bold"]
        for value in bad {
            var json = good
            json["fontWeight"] = value
            let style = try JSONDecoder().decode(OverlayStyle.self,
                                                 from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(style, original, "\(value)")
            XCTAssertEqual(style.resolvedFontWeight.postScriptName, "STSongti-TC-Bold", "\(value)")
        }
    }

    func test_acceptance_89_6_profileFileWithBadWeightStillLoadsEveryProfile() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QA89-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "QA89-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var records: [[String: Any]] = []
        var expected: [CameraProfile] = []
        let values: [Any?] = [nil, "nope", 3, ["a": 1], NSNull(), "black"]
        for (index, value) in values.enumerated() {
            var profile = CameraProfile(name: "p\(index)", startDate: DateFixture.components(2025, 1, 15))
            profile.style = OverlayStyle(fontID: .notoSerifTC)
            var record = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(profile)) as? [String: Any])
            var style = try XCTUnwrap(record["style"] as? [String: Any])
            if let value { style["fontWeight"] = value } else { style.removeValue(forKey: "fontWeight") }
            record["style"] = style
            records.append(record)
            if value as? String == "black" { profile.style.fontWeight = "black" }
            expected.append(profile)
        }
        let url = folder.appendingPathComponent(ProfileStore.fileName)
        try JSONSerialization.data(withJSONObject: records).write(to: url)
        let store = ProfileStore(directory: folder, calendar: DateFixture.taipei, defaults: defaults)
        let loaded = store.load()
        XCTAssertEqual(loaded.map(\.name), expected.map(\.name))
        XCTAssertEqual(loaded, expected)
        XCTAssertEqual(loaded.map(\.style.fontWeight), ["bold", "bold", "bold", "bold", "bold", "black"])
    }

    // MARK: - 89.5 library

    private final class Fetcher: FontFileFetching, @unchecked Sendable {
        private let lock = NSLock()
        private var log: [URL] = []
        let payloads: [String: Data]
        var failing: Set<String> = []
        init(payloads: [String: Data]) { self.payloads = payloads }
        var requested: [URL] { lock.withLock { log } }
        func fetch(from url: URL, to destination: URL,
                   progress: @escaping @Sendable (Double) -> Void) async throws {
            lock.withLock { log.append(url) }
            let key = url.lastPathComponent
            if failing.contains(key) { throw URLError(.badServerResponse) }
            try (payloads[key] ?? Data()).write(to: destination)
            progress(1)
        }
    }

    private final class Registrar: FontRegistering, @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [URL] = []
        var registered: [URL] { lock.withLock { calls } }
        func register(fontAt url: URL) -> Bool { lock.withLock { calls.append(url) }; return true }
        func unregister(fontAt url: URL) {}
    }

    private final class IdleMatcher: SystemFontMatching, @unchecked Sendable {
        func startMatching(postScriptName: String, handler: @escaping @Sendable (SystemFontMatchEvent) -> Bool) {}
    }

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private let payloads: [String: Data] = [
        "face-regular.otf": Data("regular bytes".utf8),
        "face-bold.otf": Data("bold bytes!".utf8),
        "face-black.otf": Data("black bytes!!".utf8)
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QA89Lib-\(UUID().uuidString)", isDirectory: true)
        suiteName = "QA89Lib-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func asset(_ key: String, digestOf data: Data? = nil) throws -> OpenSourceFontAsset {
        let payload = payloads[key] ?? Data()
        let digest = SHA256.hash(data: data ?? payload).map { String(format: "%02x", $0) }.joined()
        return OpenSourceFontAsset(
            fileName: key, repositoryPath: key, byteCount: payload.count, sha256: digest,
            primaryURL: try XCTUnwrap(URL(string: "https://primary.invalid/\(key)")),
            fallbackURL: try XCTUnwrap(URL(string: "https://fallback.invalid/\(key)")),
            version: "1", copyright: "test", licenseFileNames: [])
    }

    private func makeLibrary(fetcher: Fetcher, registrar: Registrar) throws -> FontLibrary {
        let regular = try asset("face-regular.otf")
        let bold = try asset("face-bold.otf")
        let black = try asset("face-black.otf")
        func option(_ id: String, _ face: String, _ asset: OpenSourceFontAsset) -> FontWeightOption {
            FontWeightOption(id: id, displayName: id, postScriptName: face,
                             downloadSizeMegabytes: 1, openSource: asset)
        }
        return FontLibrary(directory: directory, fetcher: fetcher, registrar: registrar,
                           matcher: IdleMatcher(), defaults: defaults) { fontID in
            let real = FontCatalog.entry(for: fontID)
            guard fontID == .notoSerifTC else { return real }
            return FontCatalogEntry(
                fontID: fontID, displayName: real.displayName, section: real.section, source: .openSource,
                postScriptName: "NotoSerifTC-Bold", downloadSizeMegabytes: 1, openSource: bold,
                weights: [option("regular", "NotoSerifTC-Regular", regular),
                          option("bold", "NotoSerifTC-Bold", bold),
                          option("black", "NotoSerifTC-Black", black)])
        }
    }

    private func wait(until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
    }

    func test_acceptance_89_5_eachWeightDownloadsAloneAndIsNotRepeated() async throws {
        let fetcher = Fetcher(payloads: payloads)
        let registrar = Registrar()
        let library = try makeLibrary(fetcher: fetcher, registrar: registrar)
        var finished: [FontDownloadID] = []
        var legacyFinished: [OverlayFontID] = []
        let cancellable = library.weightDownloadDidFinish.sink { finished.append($0) }
        let legacyCancellable = library.downloadDidFinish.sink { legacyFinished.append($0) }
        defer { cancellable.cancel(); legacyCancellable.cancel() }

        XCTAssertEqual(library.state(for: .notoSerifTC, weightID: "black"), .notDownloaded)
        XCTAssertTrue(library.download(.notoSerifTC, weightID: "black"))
        try await wait { library.state(for: .notoSerifTC, weightID: "black") == .available }

        XCTAssertEqual(library.state(for: .notoSerifTC, weightID: "black"), .available)
        XCTAssertEqual(library.state(for: .notoSerifTC, weightID: "regular"), .notDownloaded, "sibling untouched")
        XCTAssertEqual(library.state(for: .notoSerifTC, weightID: "bold"), .notDownloaded, "default untouched")
        XCTAssertEqual(library.state(for: .notoSerifTC), .notDownloaded, "legacy default-face query")
        XCTAssertEqual(fetcher.requested.map(\.lastPathComponent), ["face-black.otf"])
        XCTAssertEqual(finished, [FontDownloadID(fontID: .notoSerifTC, weightID: "black")])
        XCTAssertEqual(legacyFinished, [], "default-face event must stay silent for another face")
        XCTAssertEqual(library.states[.notoSerifTC], .notDownloaded)

        // Already present: asking again must not fetch again.
        XCTAssertFalse(library.download(.notoSerifTC, weightID: "black"))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(fetcher.requested.count, 1)

        // Siblings download independently and each reaches its own file.
        XCTAssertTrue(library.download(.notoSerifTC, weightID: "regular"))
        XCTAssertTrue(library.download(.notoSerifTC, weightID: "bold"))
        try await wait {
            library.state(for: .notoSerifTC, weightID: "regular") == .available
                && library.state(for: .notoSerifTC, weightID: "bold") == .available
        }
        XCTAssertEqual(Set(fetcher.requested.map(\.lastPathComponent)),
                       ["face-black.otf", "face-regular.otf", "face-bold.otf"])
        XCTAssertEqual(fetcher.requested.count, 3)
        XCTAssertEqual(legacyFinished, [.notoSerifTC], "default face completion now reported once")
        XCTAssertEqual(library.state(for: .notoSerifTC), .available)
        XCTAssertEqual(library.states[.notoSerifTC], .available)
        let paths = ["regular", "bold", "black"].map { library.storedFileURL(for: .notoSerifTC, weightID: $0) }
        XCTAssertEqual(Set(paths).count, 3, "three distinct files")
        XCTAssertEqual(library.storedFileURL(for: .notoSerifTC).lastPathComponent, "notoSerifTC.otf",
                       "default face keeps the pre-TASK-89 file name")
        XCTAssertEqual(library.storedFileURL(for: .notoSerifTC, weightID: "bold"),
                       library.storedFileURL(for: .notoSerifTC))
        for url in paths { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent) }
        XCTAssertEqual(registrar.registered.count, 3)
        XCTAssertEqual(try Data(contentsOf: paths[2]), payloads["face-black.otf"])

        // Relaunch: every face is rebuilt from disk without the network.
        let second = try makeLibrary(fetcher: fetcher, registrar: registrar)
        await second.prepareAtLaunch(priority: .notoSerifTC, weightID: "black")
        XCTAssertEqual(second.state(for: .notoSerifTC, weightID: "black"), .available, "priority face settles first")
        try await wait {
            ["regular", "bold"].allSatisfy { second.state(for: .notoSerifTC, weightID: $0) == .available }
        }
        for id in ["regular", "bold", "black"] {
            XCTAssertEqual(second.state(for: .notoSerifTC, weightID: id), .available, id)
        }
        XCTAssertEqual(fetcher.requested.count, 3)

        // Delete one face only.
        XCTAssertTrue(second.delete(.notoSerifTC, weightID: "regular"))
        XCTAssertEqual(second.state(for: .notoSerifTC, weightID: "regular"), .notDownloaded)
        XCTAssertEqual(second.state(for: .notoSerifTC, weightID: "black"), .available)
        XCTAssertEqual(second.state(for: .notoSerifTC, weightID: "bold"), .available)
    }

    func test_acceptance_89_5_failedWeightNeverBecomesAvailableNorSignalsSuccess() async throws {
        // A wrong-hash file, a server error, and a network failure.
        let fetcher = Fetcher(payloads: payloads)
        fetcher.failing = ["face-regular.otf"]
        var tampered = payloads
        tampered["face-black.otf"] = Data("tampered".utf8)
        let tamperedFetcher = Fetcher(payloads: tampered)
        tamperedFetcher.failing = ["face-regular.otf"]
        let registrar = Registrar()
        let library = try makeLibrary(fetcher: tamperedFetcher, registrar: registrar)
        var finished: [FontDownloadID] = []
        var legacyFinished: [OverlayFontID] = []
        let c1 = library.weightDownloadDidFinish.sink { finished.append($0) }
        let c2 = library.downloadDidFinish.sink { legacyFinished.append($0) }
        defer { c1.cancel(); c2.cancel() }

        // Default face first, so we can prove failures elsewhere do not disturb it.
        XCTAssertTrue(library.download(.notoSerifTC))
        try await wait { library.state(for: .notoSerifTC) == .available }
        XCTAssertEqual(library.state(for: .notoSerifTC), .available)

        XCTAssertTrue(library.download(.notoSerifTC, weightID: "regular"))
        XCTAssertTrue(library.download(.notoSerifTC, weightID: "black"))
        func isFailed(_ id: String) -> Bool {
            if case .failed = library.state(for: .notoSerifTC, weightID: id) { return true }
            return false
        }
        try await wait { isFailed("regular") && isFailed("black") }
        XCTAssertTrue(isFailed("regular"), "server error is a failure")
        XCTAssertTrue(isFailed("black"), "checksum mismatch is a failure")
        XCTAssertEqual(library.state(for: .notoSerifTC, weightID: "bold"), .available, "default stays available")
        XCTAssertEqual(library.state(for: .notoSerifTC), .available)
        XCTAssertEqual(finished, [FontDownloadID(fontID: .notoSerifTC, weightID: "bold")],
                       "no completion event for failed faces")
        XCTAssertEqual(legacyFinished, [.notoSerifTC])
        for id in ["regular", "black"] {
            let url = library.storedFileURL(for: .notoSerifTC, weightID: id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "\(id) leaves no file")
        }
        XCTAssertEqual(registrar.registered.count, 1, "nothing but the default face was registered")

        // Resolution of a failed face must not claim it is drawable.
        let resolved = OverlayMetrics.resolvedFont(
            for: OverlayStyle(fontID: .notoSerifTC, fontWeight: "black"), availability: library)
        XCTAssertEqual(resolved, .pingFang)
        _ = fetcher
    }

    private final class RecordingMatcher: SystemFontMatching, @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []
        var matched: [String] { lock.withLock { names } }
        func startMatching(postScriptName: String, handler: @escaping @Sendable (SystemFontMatchEvent) -> Bool) {
            lock.withLock { names.append(postScriptName) }
        }
    }

    func test_acceptance_89_5_systemFacesMatchTheirOwnExactPostScriptName() async throws {
        let matcher = RecordingMatcher()
        let library = FontLibrary(directory: directory, fetcher: Fetcher(payloads: [:]), registrar: Registrar(),
                                  matcher: matcher, defaults: defaults)
        XCTAssertTrue(library.download(.songti, weightID: "light"))
        XCTAssertTrue(library.download(.kaiti, weightID: "black"))
        XCTAssertTrue(library.download(.songti))
        try await wait { matcher.matched.count == 3 }
        XCTAssertEqual(Set(matcher.matched), ["STSongti-TC-Light", "STKaitiTC-Black", "STSongti-TC-Bold"])
        XCTAssertFalse(library.download(.songti, weightID: "light"), "already in progress: not duplicated")
        XCTAssertEqual(matcher.matched.count, 3)
        // Unknown weight ids resolve to the default face unit, never a new one.
        XCTAssertFalse(library.download(.songti, weightID: "nonsense"))
        XCTAssertEqual(library.state(for: .songti, weightID: "nonsense"), library.state(for: .songti))
    }
}
