import Combine
import CryptoKit
import Photos
import UIKit
import XCTest
@testable import DaysCam

/// TASK-89 independent QA of the ui-shell wiring (PR #373): 89.2 regression,
/// 89.3 baking (preview and bake follow the chosen weight) and the
/// per-weight launch preparation. Since #621 the bake happens on the export
/// page and fonts are applied through `StyleEditingCenter`, so "preview" is
/// the export preview and "shutter" is the export's bake (Lead-authorized
/// change). Unlike the developer tests it uses the
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

    /// What the export's bake received.
    private final class BakeRecorder: @unchecked Sendable {
        struct Call { let font: ResolvedOverlayFont; let style: OverlayStyle }
        private let lock = NSLock()
        private var calls: [Call] = []
        var last: Call? { lock.lock(); defer { lock.unlock() }; return calls.last }
        func add(_ call: Call) { lock.lock(); calls.append(call); lock.unlock() }
    }

    /// A one-photo library whose original can be held until released, so a
    /// test can change the font library while the export is in flight.
    @MainActor
    private final class HeldPhotoLibrary: RecordAlbumLibrary {
        var holds = false
        private(set) var isWaiting = false
        private var held: CheckedContinuation<Void, Never>?

        func release() {
            holds = false
            held?.resume()
            held = nil
        }

        func authorizationStatus() -> PHAuthorizationStatus { .authorized }
        func requestReadWriteAccess() async -> PHAuthorizationStatus { .authorized }
        func photos(albumIdentifier: String?, fallbackIDs: [String]) -> [RecordPhoto] { [] }
        func photoCount(albumIdentifier: String?, fallbackIDs: [String]) -> Int? { 0 }
        func userAlbums() -> [AlbumSummary] { [] }
        func addAssets(_ ids: [String], albumIdentifier: String?, albumTitle: String) async throws -> String { "album" }
        func removeAssets(_ ids: [String], fromAlbum albumIdentifier: String) async throws {}
        func deleteAssets(_ ids: [String]) async -> Bool { false }
        func changes() -> AsyncStream<Void> { AsyncStream { _ in } }
        func thumbnail(id: String, targetSize: CGSize) async -> UIImage? { nil }
        func displayImage(id: String, targetSize: CGSize) async -> UIImage? { nil }
        func fullImage(id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> UIImage {
            if holds {
                isWaiting = true
                await withCheckedContinuation { held = $0 }
            }
            return UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { _ in }
        }
    }

    private struct Harness {
        let center: StyleEditingCenter
        let store: ProfileStore
        let library: FakeShellFontLibrary
        let profile: CameraProfile
        let now: Date

        /// The 文字樣式 page (preview font) and the export pipeline (baked
        /// font) of a photo taken at `now`, with the app's own resolver over
        /// `library` (#647 moved the export from the page to
        /// `PhotoExportPipeline`).
        @MainActor
        struct ExportRun {
            let page: ExportModel
            let pipeline: PhotoExportPipeline
            let photo: RecordPhoto
            let store: ProfileStore
            let profileID: UUID
            let resolveFont: @MainActor (OverlayStyle) -> ResolvedOverlayFont

            var overlayFont: ResolvedOverlayFont { page.overlayFont }

            func export() async {
                guard let profile = store.profiles.first(where: { $0.id == profileID }) else { return }
                _ = await pipeline.export(photo: photo, profile: profile, resolveFont: resolveFont)
            }
        }

        @MainActor
        func makeExport(recorder: BakeRecorder, photoLibrary: HeldPhotoLibrary? = nil) -> ExportRun {
            let library = self.library
            let photoLibrary = photoLibrary ?? HeldPhotoLibrary()
            let photo = RecordPhoto(id: "photo", creationDate: now)
            let resolve: @MainActor (OverlayStyle) -> ResolvedOverlayFont = {
                OverlayMetrics.resolvedFont(for: $0, availability: library)
            }
            let page = ExportModel(
                profileID: profile.id,
                photo: photo,
                store: store,
                library: photoLibrary,
                editor: center.makeStyleEditor(for: profile.id),
                calendar: DateFixture.taipei,
                resolveFont: resolve)
            let pipeline = PhotoExportPipeline(
                library: photoLibrary,
                calendar: DateFixture.taipei,
                bake: { image, _, style, _, font, _, _, _ in
                    recorder.add(BakeRecorder.Call(font: font, style: style))
                    return image
                },
                save: { _, completion in completion(.success("asset")) })
            return ExportRun(page: page, pipeline: pipeline, photo: photo, store: store,
                             profileID: profile.id, resolveFont: resolve)
        }

        /// The font and style the export's bake receives right now.
        @MainActor
        func bakedCall() async -> BakeRecorder.Call? {
            let recorder = BakeRecorder()
            await makeExport(recorder: recorder).export()
            return recorder.last
        }

        /// The face the export preview draws with right now.
        @MainActor
        var previewFont: ResolvedOverlayFont {
            makeExport(recorder: BakeRecorder()).overlayFont
        }
    }

    /// One selected profile, built with the **default** resolver.
    private func makeHarness(fontID: OverlayFontID, weight: String?,
                             states: [OverlayFontID: FontState] = [:]) throws -> Harness {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        var profile = CameraProfile(name: "A", startDate: DateFixture.components(2026, 1, 1))
        profile.style.fontID = fontID
        if let weight { profile.style.fontWeight = weight }
        _ = try store.add(profile)
        store.select(id: profile.id)
        let library = FakeShellFontLibrary(states)
        let center = StyleEditingCenter(profileStore: store, fontLibrary: library, calendar: DateFixture.taipei,
                                        calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
                                        notify: { _ in })
        return Harness(center: center, store: store, library: library,
                       profile: try XCTUnwrap(store.profiles.first { $0.id == profile.id }), now: now)
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

    /// Black not downloaded while Bold (the default) is: both the export
    /// preview and the export's bake stay PingFang; once black is available
    /// the very face NotoSerifTC-Black is drawn, never Bold; photo pixels differ.
    func test_acceptance_89_3_chosenWeightReachesPreviewAndShutterBake() async throws {
        try registerFixtures()
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .available])
        XCTAssertEqual(harness.profile.style.fontWeight, "black")

        XCTAssertEqual(harness.previewFont, .pingFang, "89.3: default weight available is not black available")
        let before = await harness.bakedCall()
        XCTAssertEqual(before?.font, .pingFang, "89.3 export bake")

        harness.library.finishDownload(.notoSerifTC, weightID: "black")
        let preview = harness.previewFont
        let bakedAfter = await harness.bakedCall()
        let shutter = try XCTUnwrap(bakedAfter)
        XCTAssertEqual(preview.postScriptName, "NotoSerifTC-Black", "89.3 preview")
        XCTAssertEqual(shutter.font.postScriptName, "NotoSerifTC-Black", "89.3 export bake")
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

    /// The export's bake uses the font resolved when the checkmark was
    /// pressed, even if the weight changes while the original downloads
    /// (FR-5.14 holds per weight); the preview follows the library afresh.
    func test_acceptance_89_3_contextFontIsFixedAtShutterTime() async throws {
        try registerFixtures()
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .available])
        harness.library.finishDownload(.notoSerifTC, weightID: "black")
        let photoLibrary = HeldPhotoLibrary()
        photoLibrary.holds = true
        let recorder = BakeRecorder()
        let export = harness.makeExport(recorder: recorder, photoLibrary: photoLibrary)
        let task = Task { await export.export() }
        for _ in 0..<100 where !photoLibrary.isWaiting { try await Task.sleep(nanoseconds: 10_000_000) }
        harness.library.set(.notDownloaded, for: .notoSerifTC, weightID: "black")
        photoLibrary.release()
        await task.value
        XCTAssertEqual(recorder.last?.font.postScriptName, "NotoSerifTC-Black")
        XCTAssertEqual(export.overlayFont, .pingFang, "preview follows the library afresh")
    }

    /// Built-in weights need no download and must come out as that exact face.
    func test_acceptance_89_3_pingFangWeightsResolveToTheirOwnFace() async throws {
        try XCTSkipIf(UIFont(name: "PingFangTC-Light", size: 20) == nil, "PingFang Light not installed here")
        for (weight, face) in [("light", "PingFangTC-Light"), ("regular", "PingFangTC-Regular"),
                               ("semibold", "PingFangTC-Semibold")] {
            let harness = try makeHarness(fontID: .pingFang, weight: weight)
            let baked = await harness.bakedCall()
            XCTAssertEqual(baked?.font.postScriptName, face, weight)
            XCTAssertEqual(harness.previewFont.postScriptName, face, weight)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("profiles.json"))
        }
    }

    // MARK: - Preparation per font and weight

    func test_acceptance_89_3_launchPreparationNamesFontAndWeight() async throws {
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .available])
        let task = Task { await harness.center.prepareFontsAtLaunch() }
        for _ in 0..<50 where harness.library.launchPriorityWeights.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        task.cancel()
        XCTAssertEqual(harness.library.launchPriorities, [.notoSerifTC])
        XCTAssertEqual(harness.library.launchPriorityWeights, ["black"])
    }

    /// Download event for a different weight of the same font must not make
    /// the chosen one available, for the preview or the bake.
    func test_acceptance_89_3_otherWeightsDownloadEventDoesNotMakeChosenWeightAvailable() async throws {
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .available])
        harness.library.finishDownload(.notoSerifTC, weightID: "regular")
        let baked = await harness.bakedCall()
        XCTAssertEqual(baked?.font, .pingFang)
        XCTAssertEqual(harness.previewFont, .pingFang)
    }

    // MARK: - pending font applications stay per font (PR assumption)

    /// Choosing a font by ID while a non-default weight is stored must never
    /// write a weight the user did not choose, nor lose the stored one when
    /// the same font is re-applied.
    func test_acceptance_89_3_applyFontKeepsOrResetsWeightNeverInventsOne() async throws {
        let harness = try makeHarness(fontID: .notoSerifTC, weight: "black", states: [.notoSerifTC: .available, .huninn: .available])
        let id = harness.profile.id

        harness.center.applyFont(.notoSerifTC, profileID: id)
        XCTAssertEqual(harness.store.profiles.first { $0.id == id }?.style.fontWeight, "black",
                       "re-applying the current font keeps its weight")

        harness.center.applyFont(.huninn, profileID: id)
        XCTAssertEqual(harness.store.profiles.first { $0.id == id }?.style.fontWeight,
                       FontCatalog.entry(for: .huninn).defaultWeight.id)

        harness.center.applyFont(.notoSerifTC, profileID: id)
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
        harness.center.applyFont(.notoSerifTC, profileID: id)
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
    /// export: the baked font equals the catalog default face's resolution.
    func test_acceptance_89_2_legacyProfileOnShellUsesDefaultFace() async throws {
        let harness = try makeHarness(fontID: .pingFang, weight: nil)
        XCTAssertEqual(harness.profile.style.fontWeight, FontCatalog.entry(for: .pingFang).defaultWeight.id)
        let baked = await harness.bakedCall()
        XCTAssertEqual(baked?.font.postScriptName,
                       OverlayMetrics.resolvedFont(for: .pingFang, availability: harness.library).postScriptName)
    }
}

