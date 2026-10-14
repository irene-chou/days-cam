import AVFoundation
import Photos
import XCTest
@testable import DaysCam

/// TASK-93 (#392) independent QA of PR #396: 93.13 (viewfinder text and baked
/// text come from one `TemplateRenderer` output), 93.14 (capture time is
/// passed explicitly) and 93.16 evidence (a photo baked with the 93.3
/// settings). Everything else in 93.x is covered by the developer table tests.
@MainActor
final class ZeroSmallestUnitAcceptanceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZeroSmallestUnit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ZeroSmallestUnit-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

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

    private struct BakeCall { let text: String; let style: OverlayStyle; let placement: OverlayPlacement }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [BakeCall] = []
        var all: [BakeCall] { lock.lock(); defer { lock.unlock() }; return calls }
        func add(_ call: BakeCall) { lock.lock(); calls.append(call); lock.unlock() }
    }

    /// 93.3: years + months, started 2026-10-01, "now" 2026-10-11 10:00 Taipei.
    private func makeProfile(units: Set<DisplayUnit>) -> CameraProfile {
        CameraProfile(name: "QA", startDate: DateFixture.components(2026, 10, 1),
                      countingRule: .dayOne, showDayCount: true, showDate: false, showName: false,
                      displayUnits: units)
    }

    private func makeModel(now: @escaping () -> Date, profile: CameraProfile, recorder: Recorder,
                           bakeOutput: @escaping (UIImage, String, OverlayStyle, OverlayPlacement) -> UIImage?)
        throws -> (CameraScreenModel, ProfileStore) {
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: now, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        _ = try store.add(profile)
        store.select(id: profile.id)
        let service = CameraService(authorizer: StubAuthorizer(), deviceProvider: EmptyDeviceProvider(),
                                    flashCapabilityProvider: nil, isCaptureSupported: false)
        let source = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { _ in }
        let model = CameraScreenModel(
            cameraService: service,
            profileStore: store,
            captureSettingsStore: CaptureSettingsStore(defaults: defaults),
            capturedPhotoStore: CapturedPhotoStore(directory: directory.appendingPathComponent("photos", isDirectory: true)),
            calendar: DateFixture.taipei,
            calculator: DayCountCalculator(calendar: DateFixture.taipei, now: now),
            cropRect: { size, _ in CGRect(origin: .zero, size: size) },
            bake: { image, text, style, placement, _, _, _ in
                recorder.add(BakeCall(text: text, style: style, placement: placement))
                return bakeOutput(image, text, style, placement)
            },
            save: { _, completion in completion(.success("asset")) },
            captureImage: { _, completion in completion(.success(source)) },
            scheduleToastDismiss: { _ in },
            makeThumbnailLibrary: { _ in EmptyThumbnailLibrary() })
        return (model, store)
    }

    // MARK: - 93.13

    /// Viewfinder text, shutter context text and the text handed to the bake
    /// closure on a real shutter run are all the renderer's output: `0 個月`.
    func test_acceptance_93_13_previewAndBakedTextShareOneRendererOutput() async throws {
        let now = try XCTUnwrap(DateFixture.date(2026, 10, 11, hour: 10))
        let profile = makeProfile(units: [.year, .month])
        let recorder = Recorder()
        let (model, store) = try makeModel(now: { now }, profile: profile, recorder: recorder) { _, _, _, _ in UIImage() }
        let stored = try XCTUnwrap(store.profiles.first { $0.id == profile.id })

        let expected = TemplateRenderer().render(profile: stored, capturedAt: now, calendar: DateFixture.taipei)
        XCTAssertEqual(expected, "0 個月", "93.3 via the renderer")
        XCTAssertEqual(model.overlayText, expected, "93.13 viewfinder")
        XCTAssertEqual(model.captureContext(for: stored).text, expected, "93.13 shutter context")

        model.beginCapture(profile: stored)
        for _ in 0..<100 where recorder.all.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(recorder.all.map(\.text), ["0 個月"], "93.13 text reaching the bake step")
        XCTAssertEqual(recorder.all.first?.text, model.overlayText, "93.13 preview == baked")
    }

    /// Each smallest-unit variant also matches between preview and bake.
    func test_acceptance_93_13_otherSmallestUnitsMatchToo() async throws {
        let now = try XCTUnwrap(DateFixture.date(2026, 10, 11, hour: 10))
        let cases: [(Set<DisplayUnit>, DateComponents, String)] = [
            ([.year], DateFixture.components(2026, 1, 15), "0 年"),
            ([.week], DateFixture.components(2026, 10, 8), "0 週"),
            ([.year, .month, .day], DateFixture.components(2026, 10, 11), "0 天")
        ]
        for (units, start, expectedText) in cases {
            var profile = makeProfile(units: units)
            profile.startDate = start
            if units == [.week] { profile.countingRule = .dayOne }
            let recorder = Recorder()
            let (model, store) = try makeModel(now: { now }, profile: profile, recorder: recorder) { _, _, _, _ in UIImage() }
            let stored = try XCTUnwrap(store.profiles.first { $0.id == profile.id })
            XCTAssertEqual(model.overlayText, expectedText, "\(units)")
            model.beginCapture(profile: stored)
            for _ in 0..<100 where recorder.all.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
            XCTAssertEqual(recorder.all.first?.text, expectedText, "bake text \(units)")
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("profiles.json"))
        }
    }

    // MARK: - 93.14

    /// Capture time comes from the injected clock, passed explicitly: moving
    /// the clock changes the text, and the file/EXIF clock never matters.
    func test_acceptance_93_14_capturedAtIsExplicit() throws {
        let profile = makeProfile(units: [.year, .month])
        let renderer = TemplateRenderer()
        let early = try XCTUnwrap(DateFixture.date(2026, 10, 11, hour: 10))
        let later = try XCTUnwrap(DateFixture.date(2026, 11, 1, hour: 10))
        XCTAssertEqual(renderer.render(profile: profile, capturedAt: early, calendar: DateFixture.taipei), "0 個月")
        XCTAssertEqual(renderer.render(profile: profile, capturedAt: later, calendar: DateFixture.taipei), "1 個月",
                       "the explicit capturedAt, not the wall clock, decides")
    }

    /// Static: the renderer reads no clock, EXIF or file dates, and no
    /// hard-coded `0 天` literal remains.
    func test_acceptance_93_14_rendererSourceReadsNoClockOrFileDates() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DaysCam/Services/TemplateRenderer.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let code = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        for forbidden in ["Date()", "Date.now", "creationDate", "CGImageSource", "kCGImagePropertyExif",
                          "attributesOfItem", "\"0 天\"", "allZeroText ="] {
            XCTAssertFalse(code.contains(forbidden), "93.14 / 93.x: renderer must not contain \(forbidden)")
        }
        XCTAssertTrue(code.contains("capturedAt"))
    }

    // MARK: - 93.16 evidence

    /// Bakes a photo through the real shutter pipeline with the 93.3 settings
    /// and writes it as a PNG (B' evidence; the simulator cannot take photos).
    func test_acceptance_93_16_bakedPhotoEvidence() async throws {
        let now = try XCTUnwrap(DateFixture.date(2026, 10, 11, hour: 10))
        let profile = makeProfile(units: [.year, .month])
        let recorder = Recorder()
        let backdrop: (UIImage, String, OverlayStyle, OverlayPlacement) -> UIImage? = { _, text, style, placement in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let photo = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200), format: format).image { context in
                let colors = [UIColor(red: 0.30, green: 0.45, blue: 0.60, alpha: 1).cgColor,
                              UIColor(red: 0.85, green: 0.70, blue: 0.50, alpha: 1).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    context.cgContext.drawLinearGradient(gradient, start: .zero,
                                                         end: CGPoint(x: 900, y: 1200), options: [])
                }
            }
            return OverlayRenderer().bake(image: photo, text: text, style: style, placement: placement, font: .pingFang)
        }
        let output = LockedImage()
        let (model, store) = try makeModel(now: { now }, profile: profile, recorder: recorder) { image, text, style, placement in
            let baked = backdrop(image, text, style, placement)
            output.set(baked)
            return baked
        }
        let stored = try XCTUnwrap(store.profiles.first { $0.id == profile.id })
        model.beginCapture(profile: stored)
        for _ in 0..<150 where output.value == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let baked = try XCTUnwrap(output.value, "93.16 bake produced no image")
        XCTAssertEqual(recorder.all.first?.text, "0 個月", "93.16 baked text")
        let png = try XCTUnwrap(baked.pngData())
        let folder = ProcessInfo.processInfo.environment["DAYSCAM_QA_OUT"] ?? NSTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("93.16_baked_zero-month.png"))
        let attachment = XCTAttachment(image: baked)
        attachment.name = "396_93.16_baked_0-months"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private final class LockedImage: @unchecked Sendable {
        private let lock = NSLock()
        private var image: UIImage?
        var value: UIImage? { lock.lock(); defer { lock.unlock() }; return image }
        func set(_ new: UIImage?) { lock.lock(); image = new; lock.unlock() }
    }
}
