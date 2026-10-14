import AVFoundation
import Combine
import CryptoKit
import Photos
import XCTest
@testable import DaysCam

/// TASK-89 independent QA of the ui-shell wiring (PR #373): 89.2 regression,
/// 89.3 baking (preview and shutter follow the chosen weight) and the
/// per-weight launch preparation. Unlike the developer tests it uses the
/// app's own resolver (no stand-in face), and, when `DAYSCAM_FONT_FIXTURES`
/// points at a folder holding NotoSerifTC-Bold.otf and NotoSerifTC-Black.otf,
/// registers the real fonts so the drawn pixels can be compared.
@MainActor
final class FontWeightShellAcceptanceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FontWeightShellAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "FontWeightShellAcceptance-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - Doubles and helpers

    private final class StubAuthorizer: CameraAuthorizing {
        func authorizationStatus() -> AVAuthorizationStatus { .notDetermined }
        func requestAccess(completion: @escaping (Bool) -> Void) { completion(false) }
    }

    private final class EmptyDeviceProvider: CaptureDeviceProviding {
        func device(for facing: CameraFacing) -> AVCaptureDevice? { nil }
    }

    private final class EmptyThumbnailLibrary: GalleryLibrary {
        func readStatus() -> PHAuthorizationStatus { .denied }
        func requestReadAccess() async -> PHAuthorizationStatus { .denied }
        func latestVisiblePhotoIDs(limit: Int) -> [String] { [] }
        func photos() -> [GalleryPhoto] { [] }
        func deletePhoto(id: String) async -> Bool { false }
        func image(id: String, targetSize: CGSize) async -> UIImage? { nil }
    }

    private struct Harness {
        let model: CameraScreenModel
        let store: ProfileStore
        let library: FakeShellFontLibrary
        let profile: CameraProfile
    }

    /// One selected profile, built with the **default** resolver.
    private func makeHarness(fontID: OverlayFontID, weight: String?,
                             states: [OverlayFontID: FontState] = [:],
                             timeout: TimeInterval = 3) throws -> Harness {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        var profile = CameraProfile(name: "A", startDate: DateFixture.components(2026, 1, 1))
        profile.style.fontID = fontID
        if let weight { profile.style.fontWeight = weight }
        _ = try store.add(profile)
        store.select(id: profile.id)
        let library = FakeShellFontLibrary(states)
        let service = CameraService(authorizer: StubAuthorizer(), deviceProvider: EmptyDeviceProvider(),
                                    flashCapabilityProvider: nil, isCaptureSupported: false)
        let model = CameraScreenModel(
            cameraService: service,
            profileStore: store,
            captureSettingsStore: CaptureSettingsStore(defaults: defaults),
            capturedPhotoStore: CapturedPhotoStore(directory: directory.appendingPathComponent("photos", isDirectory: true)),
            calendar: DateFixture.taipei,
            calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
            cropRect: { size, _ in CGRect(origin: .zero, size: size) },
            bake: { _, _, _, _, _, _, _ in UIImage() },
            save: { _, completion in completion(.success("asset")) },
            scheduleToastDismiss: { _ in },
            makeThumbnailLibrary: { _ in EmptyThumbnailLibrary() },
            fontLibrary: library,
            fontPreparationTimeout: timeout)
        return Harness(model: model, store: store, library: library,
                       profile: try XCTUnwrap(store.profiles.first { $0.id == profile.id }))
    }

    private func registerFixtures() throws {
        guard let path = ProcessInfo.processInfo.environment["DAYSCAM_FONT_FIXTURES"] else {
            throw XCTSkip("DAYSCAM_FONT_FIXTURES not set; the Noto Serif fixture files are not in the repo")
        }
        for name in ["NotoSerifTC-Bold.otf", "NotoSerifTC-Black.otf"] {
            var error: Unmanaged<CFError>?
            let url = URL(fileURLWithPath: path).appendingPathComponent(name) as CFURL
            _ = CTFontManagerRegisterFontsForURL(url, .process, &error)
        }
        try XCTSkipIf(UIFont(name: "NotoSerifTC-Black", size: 20) == nil, "fixture fonts did not register")
    }

    private func digest(of font: ResolvedOverlayFont, style: OverlayStyle) throws -> String {
        let canvas = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320)).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
        }
        let baked = try XCTUnwrap(OverlayRenderer().bake(
            image: canvas, text: "第 10 天", style: style,
            placement: .anchor(.bottomTrailing), font: font)?.cgImage)
        let data = try XCTUnwrap(baked.dataProvider?.data) as Data
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 80_000_000) }

    // MARK: - 89.3 shutter and preview follow the chosen weight (real resolver)

    /// Black not downloaded while Bold (the default) is: both the viewfinder
    /// and the shutter context stay PingFang; once black is available the
    /// very face NotoSerifTC-Black is drawn, never Bold; photo pixels differ.
    func test_acceptance_89_3_chosenWeightReachesPreviewAndShutterBake() throws {
        try registerFixtures()
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .available])
        XCTAssertEqual(harness.profile.style.fontWeight, "black")

        XCTAssertEqual(harness.model.overlayFont, .pingFang, "89.3: default weight available is not black available")
        XCTAssertEqual(harness.model.captureContext(for: harness.profile).font, .pingFang, "89.3 shutter")

        harness.library.finishDownload(.notoSerifTC, weightID: "black")
        let preview = harness.model.overlayFont
        let shutter = harness.model.captureContext(for: harness.profile)
        XCTAssertEqual(preview.postScriptName, "NotoSerifTC-Black", "89.3 preview")
        XCTAssertEqual(shutter.font.postScriptName, "NotoSerifTC-Black", "89.3 shutter")
        XCTAssertEqual(shutter.style.fontWeight, "black")

        var boldStyle = harness.profile.style
        boldStyle.fontWeight = "bold"
        let boldFont = OverlayMetrics.resolvedFont(for: boldStyle, availability: harness.library)
        XCTAssertEqual(boldFont.postScriptName, "NotoSerifTC-Bold")
        XCTAssertNotEqual(try digest(of: shutter.font, style: shutter.style),
                          try digest(of: boldFont, style: boldStyle), "89.3: baked pixels differ by weight")
        XCTAssertNotEqual(try digest(of: shutter.font, style: shutter.style),
                          try digest(of: .pingFang, style: shutter.style), "89.3: not PingFang")
    }

    /// The bake the shutter performs uses the context font captured at press
    /// time, even if the weight changes afterwards (FR-5.14 holds per weight).
    func test_acceptance_89_3_contextFontIsFixedAtShutterTime() throws {
        try registerFixtures()
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .available])
        harness.library.finishDownload(.notoSerifTC, weightID: "black")
        let context = harness.model.captureContext(for: harness.profile)
        harness.library.set(.notDownloaded, for: .notoSerifTC, weightID: "black")
        XCTAssertEqual(context.font.postScriptName, "NotoSerifTC-Black")
        XCTAssertEqual(harness.model.overlayFont, .pingFang, "preview follows the library afresh")
    }

    /// Built-in weights need no download and must come out as that exact face.
    func test_acceptance_89_3_pingFangWeightsResolveToTheirOwnFace() throws {
        try XCTSkipIf(UIFont(name: "PingFangTC-Light", size: 20) == nil, "PingFang Light not installed here")
        for (weight, face) in [("light", "PingFangTC-Light"), ("regular", "PingFangTC-Regular"),
                               ("semibold", "PingFangTC-Semibold")] {
            let harness = try makeHarness(fontID: .pingFang, weight: weight)
            XCTAssertEqual(harness.model.captureContext(for: harness.profile).font.postScriptName, face, weight)
            XCTAssertEqual(harness.model.overlayFont.postScriptName, face, weight)
        }
    }

    // MARK: - Preparation per font and weight

    func test_acceptance_89_3_launchPreparationNamesFontAndWeight() async throws {
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .available])
        let task = Task { await harness.model.prepareFontsAtLaunch() }
        for _ in 0..<50 where harness.library.launchPriorityWeights.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        task.cancel()
        XCTAssertEqual(harness.library.launchPriorities, [.notoSerifTC])
        XCTAssertEqual(harness.library.launchPriorityWeights, ["black"])
    }

    /// The default face becoming available must not release a shutter that is
    /// waiting on a different weight; only that weight's own state does.
    func test_acceptance_89_3_shutterWaitsOnTheChosenWeightOnly() throws {
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .preparing])
        harness.library.set(.preparing, for: .notoSerifTC, weightID: "black")
        XCTAssertTrue(harness.model.isWaitingForFont)
        XCTAssertTrue(harness.model.isShutterDisabled)

        harness.library.set(.available, for: .notoSerifTC)
        XCTAssertTrue(harness.model.isWaitingForFont, "default face finishing says nothing about black")

        harness.library.set(.available, for: .notoSerifTC, weightID: "black")
        XCTAssertFalse(harness.model.isWaitingForFont)

        // The reverse: default preparing, chosen weight settled -> not waiting.
        let other = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .preparing])
        other.library.set(.available, for: .notoSerifTC, weightID: "black")
        XCTAssertFalse(other.model.isWaitingForFont, "waiting is about the chosen face, not the font's default")
    }

    /// Download event for a different weight of the same font must not apply
    /// or release anything for the chosen one.
    func test_acceptance_89_3_otherWeightsDownloadEventDoesNotMakeChosenWeightAvailable() throws {
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .available])
        harness.library.finishDownload(.notoSerifTC, weightID: "regular")
        XCTAssertEqual(harness.model.captureContext(for: harness.profile).font, .pingFang)
    }

    // MARK: - pending font applications stay per font (PR assumption)

    /// Choosing a font by ID while a non-default weight is stored must never
    /// write a weight the user did not choose, nor lose the stored one when
    /// the same font is re-applied.
    func test_acceptance_89_3_applyFontKeepsOrResetsWeightNeverInventsOne() async throws {
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .available, .huninn: .available])
        let id = harness.profile.id

        harness.model.applyFont(.notoSerifTC, profileID: id)
        XCTAssertEqual(harness.store.profiles.first { $0.id == id }?.style.fontWeight, "black",
                       "re-applying the current font keeps its weight")

        harness.model.applyFont(.huninn, profileID: id)
        XCTAssertEqual(harness.store.profiles.first { $0.id == id }?.style.fontWeight,
                       FontCatalog.entry(for: .huninn).defaultWeight.id)

        harness.model.applyFont(.notoSerifTC, profileID: id)
        XCTAssertEqual(harness.store.profiles.first { $0.id == id }?.style.fontWeight,
                       FontCatalog.entry(for: .notoSerifTC).defaultWeight.id,
                       "switching back lands on the default weight, not the earlier black")
    }

    /// An undownloaded font requested by ID downloads its default face only,
    /// and is applied (default weight) once that finishes; a different weight
    /// finishing in between must not trigger the application.
    func test_acceptance_89_3_pendingApplicationWaitsForTheDefaultFaceOnly() async throws {
        let harness = try makeHarness(fontID: .huninn, weight: nil, states: [.huninn: .available])
        let id = harness.profile.id
        harness.model.applyFont(.notoSerifTC, profileID: id)
        XCTAssertEqual(harness.library.downloads, [.notoSerifTC])
        XCTAssertEqual(harness.store.profiles.first { $0.id == id }?.style.fontID, .huninn)

        harness.library.finishDownload(.notoSerifTC, weightID: "black")
        await settle()
        XCTAssertEqual(harness.store.profiles.first { $0.id == id }?.style.fontID, .huninn,
                       "a non-default weight finishing is not the requested default face")

        harness.library.finishDownload(.notoSerifTC)
        await settle()
        let applied = harness.store.profiles.first { $0.id == id }?.style
        XCTAssertEqual(applied?.fontID, .notoSerifTC)
        XCTAssertEqual(applied?.fontWeight, FontCatalog.entry(for: .notoSerifTC).defaultWeight.id)
    }

    // MARK: - 89.2 regression: legacy profiles resolve and bake like main

    /// Legacy JSON (no `fontWeight`) decodes to the default weight and the
    /// shell resolver returns the very same face as the fontID-only resolver
    /// of origin/main; with the pixel dump of
    /// `FontWeightPixelBaselineAcceptanceTests` that makes the bake identical.
    func test_acceptance_89_2_legacyStyleResolvesLikeFontIDOnlyAndBakesIdentically() throws {
        struct Availability: FontAvailabilityProviding {
            let state: FontState
            func state(for fontID: OverlayFontID) -> FontState { state }
        }
        for fontID in OverlayFontID.allCases {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(OverlayStyle(fontID: fontID, outline: .stroke, shadow: .soft))) as? [String: Any])
            json.removeValue(forKey: "fontWeight")
            let style = try JSONDecoder().decode(
                OverlayStyle.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(style.fontWeight, FontCatalog.entry(for: fontID).defaultWeight.id, "\(fontID)")
            for state in [FontState.available, .notDownloaded] {
                let provider = Availability(state: state)
                let shell = OverlayMetrics.resolvedFont(for: style, availability: provider)
                let legacy = OverlayMetrics.resolvedFont(for: fontID, availability: provider)
                XCTAssertEqual(shell, legacy, "\(fontID) \(state)")
                XCTAssertEqual(try digest(of: shell, style: style), try digest(of: legacy, style: style), "\(fontID) \(state)")
            }
        }
    }

    /// A legacy profile on disk (no fontWeight key) goes through the real
    /// shell: captureContext font equals the catalog default face's resolution.
    func test_acceptance_89_2_legacyProfileOnShellUsesDefaultFace() throws {
        let harness = try makeHarness(fontID: .pingFang, weight: nil)
        XCTAssertEqual(harness.profile.style.fontWeight, FontCatalog.entry(for: .pingFang).defaultWeight.id)
        XCTAssertEqual(harness.model.captureContext(for: harness.profile).font.postScriptName,
                       OverlayMetrics.resolvedFont(for: .pingFang, availability: harness.library).postScriptName)
    }
}
