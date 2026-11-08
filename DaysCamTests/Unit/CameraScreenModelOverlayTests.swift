import UIKit
import XCTest
@testable import DaysCam

/// #656, #712: the camera's overlay preview — the text always drawn in the
/// viewfinder (FR-20.2, FR-20.6), the style sheet opened from it or from the
/// 文字樣式 key (FR-20.10), and the shutter saving the photo cropped to the
/// ratio but never with the overlay (FR-20.4).
@MainActor
final class CameraScreenModelOverlayTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var tipsDefaults = UserDefaults.standard
    private var suiteNames: [String] = []
    private var now = Date()

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CameraScreenModelOverlayTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = try makeSuite()
        tipsDefaults = try makeSuite()
        now = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        suiteNames.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        try super.tearDownWithError()
    }

    private func makeSuite() throws -> UserDefaults {
        let name = "CameraScreenModelOverlayTests-\(UUID().uuidString)"
        suiteNames.append(name)
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    // MARK: - Helpers

    private final class SchedulerSpy {
        private(set) var scheduled: [() -> Void] = []
        func schedule(_ work: @escaping () -> Void) { scheduled.append(work) }
    }

    private final class SaveRecorder {
        private(set) var images: [UIImage] = []
        private(set) var albumTitles: [String] = []
        func save(_ image: UIImage, _ albumIdentifier: String?, _ albumTitle: String,
                  _ completion: @escaping (Result<RecordSaveOutcome, PhotoSaveError>) -> Void) {
            images.append(image)
            albumTitles.append(albumTitle)
            completion(.success(RecordSaveOutcome(assetID: "asset", albumID: nil)))
        }
    }

    private struct Rig {
        let model: CameraScreenModel
        let store: ProfileStore
        let center: StyleEditingCenter
        let toastSpy: SchedulerSpy
        let tips: FirstRunTips
    }

    private func makeStore() -> ProfileStore {
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { [now] in now },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        store.load()
        return store
    }

    @discardableResult
    private func addRecord(to store: ProfileStore, name: String, start: DateComponents,
                           sizeScale: Int? = nil) throws -> CameraProfile {
        var profile = CameraProfile(name: name, startDate: start)
        if let sizeScale { profile.style.sizeScale = sizeScale }
        return try store.add(profile)
    }

    private func makeRig(store: ProfileStore? = nil, record: CameraProfile? = nil,
                         save: @escaping CameraScreenModel.Save = { _, _, _, completion in
                             completion(.success(RecordSaveOutcome(assetID: "asset", albumID: nil)))
                         },
                         captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil,
                         tips: FirstRunTips? = nil) throws -> Rig {
        let store = store ?? makeStore()
        let calculator = DayCountCalculator(calendar: DateFixture.taipei, now: { [now] in now })
        let center = StyleEditingCenter(profileStore: store, calendar: DateFixture.taipei, calculator: calculator)
        let spy = SchedulerSpy()
        let tips = tips ?? FirstRunTips(defaults: tipsDefaults)
        let service = CameraService(isCaptureSupported: false)
        let model = CameraScreenModel(cameraService: service,
                                      profileStore: store,
                                      profileID: try XCTUnwrap(record?.id ?? store.profiles.first?.id),
                                      captureSettingsStore: CaptureSettingsStore(defaults: defaults),
                                      calendar: DateFixture.taipei,
                                      calculator: calculator,
                                      save: save,
                                      captureImage: captureImage,
                                      scheduleToastDismiss: spy.schedule,
                                      styleCenter: center,
                                      tips: tips)
        return Rig(model: model, store: store, center: center, toastSpy: spy, tips: tips)
    }

    // MARK: - 712-6: no switch

    /// 712-6: the overlay is always drawn for a record, in every record.
    func test_712_6_overlayIsAlwaysDrawn() throws {
        let rig = try makeRig()
        XCTAssertTrue(rig.model.showsOverlay)
        let other = try addRecord(to: rig.store, name: "第二個", start: DateFixture.components(2026, 1, 1))
        rig.model.selectRecord(other.id)
        XCTAssertTrue(rig.model.showsOverlay)
    }

    // MARK: - 712-2: the ratio key

    /// 712-2: 3:4 → 1:1 → 9:16 → 3:4, remembered by the app (a new store on
    /// the same defaults reads it back).
    func test_712_2_ratioCyclesAndIsRemembered() throws {
        let rig = try makeRig()
        XCTAssertEqual(rig.model.captureAspectRatio, .threeByFour)
        rig.model.cycleAspectRatio()
        XCTAssertEqual(rig.model.captureAspectRatio, .oneByOne)
        rig.model.cycleAspectRatio()
        XCTAssertEqual(rig.model.captureAspectRatio, .nineBySixteen)
        XCTAssertEqual(CaptureSettingsStore(defaults: defaults).captureAspectRatio, .nineBySixteen,
                       "712-2 survives a relaunch")
        rig.model.cycleAspectRatio()
        XCTAssertEqual(rig.model.captureAspectRatio, .threeByFour)
        XCTAssertEqual(try makeRig(store: rig.store).model.captureAspectRatio, .threeByFour)
    }

    // MARK: - 3, 5: the text

    /// 3: the text is what exporting a photo taken now would print.
    func test_656_3_textIsThePhotoMomentRenderedNow() throws {
        let rig = try makeRig()
        let profile = try XCTUnwrap(rig.model.profile)
        let expected = TemplateRenderer().render(profile: profile, capturedAt: now,
                                                 calendar: DateFixture.taipei, moment: .photo)
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(rig.model.overlayText, expected)
    }

    /// 3: a start date in the future prints 「前 N 天」, like the export.
    func test_656_3_futureStartDatePrintsDaysBefore() throws {
        let store = makeStore()
        let record = try addRecord(to: store, name: "未來", start: DateFixture.components(2026, 2, 1))
        let rig = try makeRig(store: store, record: record)
        XCTAssertTrue(rig.model.overlayText.contains("前"), "656-3 got \(rig.model.overlayText)")
    }

    /// 5: the switcher swaps the text and the style at once.
    func test_656_5_switchingRecordChangesTextAndStyle() throws {
        let store = makeStore()
        let first = try addRecord(to: store, name: "甲", start: DateFixture.components(2026, 1, 1), sizeScale: 100)
        let second = try addRecord(to: store, name: "乙", start: DateFixture.components(2025, 6, 1), sizeScale: 150)
        let rig = try makeRig(store: store, record: first)
        let firstText = rig.model.overlayText
        XCTAssertEqual(rig.model.overlayStyle.sizeScale, 100)

        rig.model.selectRecord(second.id)

        XCTAssertNotEqual(rig.model.overlayText, firstText)
        XCTAssertEqual(rig.model.overlayStyle.sizeScale, 150)
        XCTAssertEqual(rig.model.overlayPlacement, second.position)
        XCTAssertEqual(rig.model.stylePanelNote, "改動存到「乙」；拍的照片仍是原圖，匯出時才印上")
    }

    /// 3／FR-20.6: the text follows the clock (midnight), nothing is cached.
    func test_656_3_textFollowsTheClock() throws {
        let store = makeStore()
        let record = try addRecord(to: store, name: "鐘", start: DateFixture.components(2026, 1, 1))
        let clock = ClockBox(now)
        let calculator = DayCountCalculator(calendar: DateFixture.taipei, now: clock.read)
        let model = CameraScreenModel(cameraService: CameraService(isCaptureSupported: false),
                                      profileStore: store, profileID: record.id,
                                      captureSettingsStore: CaptureSettingsStore(defaults: defaults),
                                      calendar: DateFixture.taipei, calculator: calculator,
                                      tips: FirstRunTips(defaults: tipsDefaults))
        let before = model.overlayText
        clock.value = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 0))
        XCTAssertNotEqual(model.overlayText, before)
    }

    private final class ClockBox {
        var value: Date
        init(_ value: Date) { self.value = value }
        func read() -> Date { value }
    }

    // MARK: - 4: same metrics as the bake

    /// 4: the viewfinder draws with the same `OverlayMetrics` as the bake: the
    /// font size and the block's place, scaled to the photo, agree.
    func test_656_4_viewfinderMetricsMatchTheBake() throws {
        let rig = try makeRig()
        let style = rig.model.overlayStyle
        let text = rig.model.overlayText
        let viewfinder = CGSize(width: 393, height: 524)
        let photo = CGSize(width: 3024, height: 4032)
        let scale = photo.width / viewfinder.width

        let viewfinderFont = OverlayTextView.fittedFontSize(for: text, style: style, frameSize: viewfinder)
        let bakedFont = OverlayRenderer.fittedFontSize(for: text, style: style, frameSize: photo, font: .pingFang)
        XCTAssertEqual(viewfinderFont * scale, bakedFont, accuracy: bakedFont * 0.02, "656-4 font size")

        let placement = OverlayPlacement.custom(x: 0.3, y: 0.7)
        let block = CGSize(width: 120, height: 40)
        let viewfinderOrigin = OverlayTextView.origin(forBlockSize: block, frameSize: viewfinder, placement: placement)
        let bakedOrigin = OverlayMetrics.origin(forBlockSize: CGSize(width: block.width * scale, height: block.height * scale),
                                                in: photo, placement: placement)
        XCTAssertEqual(viewfinderOrigin.x * scale, bakedOrigin.x, accuracy: 1, "656-4 x")
        XCTAssertEqual(viewfinderOrigin.y * scale, bakedOrigin.y, accuracy: 1, "656-4 y")
    }

    // MARK: - 6, 8, 9: the sheet, the taps, the hint

    /// 6: a tap on the text opens the sheet; the checkmark closes it.
    func test_656_6_tapOnTextOpensTheSheetAndCheckmarkCloses() throws {
        let rig = try makeRig()
        rig.model.handleOverlayTextTap()
        XCTAssertTrue(rig.model.panelModel.isOpen)
        XCTAssertTrue(rig.model.panelModel.isOverlayDraggable)
        XCTAssertNotNil(rig.model.styleTabModel)
        XCTAssertNotNil(rig.model.positionTabModel)

        // A tap on the text again must not close it.
        rig.model.handleOverlayTextTap()
        XCTAssertTrue(rig.model.panelModel.isOpen)

        rig.model.closeStylePanel()
        XCTAssertFalse(rig.model.panelModel.isOpen)
    }

    /// 8: only a touch on the text is shielded from focus.
    func test_656_8_onlyTheTextIsShieldedFromFocus() throws {
        let rig = try makeRig()
        rig.model.overlayTextFrame = CGRect(x: 10, y: 10, width: 100, height: 40)
        XCTAssertTrue(rig.model.viewfinderTouchStartsOnOverlayText(at: CGPoint(x: 20, y: 20)))
        XCTAssertFalse(rig.model.viewfinderTouchStartsOnOverlayText(at: CGPoint(x: 300, y: 300)),
                       "656-8 outside the text is focus")
    }

    /// 6: the sheet edits the selected record, so the switcher waits, the
    /// shutter is out and focus does not start under it.
    func test_656_6_sheetBlocksSwitcherShutterAndFocus() throws {
        let store = makeStore()
        let first = try addRecord(to: store, name: "甲", start: DateFixture.components(2026, 1, 1))
        let second = try addRecord(to: store, name: "乙", start: DateFixture.components(2026, 1, 1))
        let rig = try makeRig(store: store, record: first)
        rig.model.handleOverlayTextTap()

        XCTAssertTrue(rig.model.isRecordSwitcherDisabled)
        rig.model.selectRecord(second.id)
        XCTAssertEqual(rig.model.selectedProfileID, first.id)
        XCTAssertFalse(rig.model.focusModel.canAcceptGesture())
    }

    /// 9: the hint shows until the sheet was opened once, in any later
    /// launch too.
    func test_656_9_hintGoesAwayForGoodOnceTheSheetWasOpened() throws {
        let rig = try makeRig()
        XCTAssertTrue(rig.model.showsOverlayTip)

        rig.model.handleOverlayTextTap()
        rig.model.closeStylePanel()
        XCTAssertFalse(rig.model.showsOverlayTip)

        let later = try makeRig(store: rig.store, tips: FirstRunTips(defaults: tipsDefaults))
        XCTAssertFalse(later.model.showsOverlayTip, "656-9 never again")
    }

    /// 9: UI tests count the hint as seen unless they ask for it.
    func test_656_9_uiTestsSeeNoHintByDefault() throws {
        let rig = try makeRig(tips: FirstRunTips(defaults: tipsDefaults, seenByDefault: true))
        XCTAssertFalse(rig.model.showsOverlayTip)
    }

    // MARK: - 7, 11: edits go to the record

    /// 7／11: a drag written through the sheet's adapter lands in the stored
    /// record (the viewer and the 文字樣式 page read the same record).
    func test_656_7_dragSavesThePositionToTheRecord() throws {
        let rig = try makeRig()
        let id = try XCTUnwrap(rig.model.profile?.id)
        rig.model.handleOverlayTextTap()

        rig.model.panelModel.overlayDragHandler?.overlayDragEnded(center: CGPoint(x: 100, y: 200),
                                                                  viewfinderSize: CGSize(width: 400, height: 500))

        let stored = try XCTUnwrap(rig.store.profiles.first { $0.id == id })
        guard case let .custom(x, y) = stored.position else { return XCTFail("656-7 got \(stored.position)") }
        XCTAssertEqual(x, 0.25, accuracy: 0.001)
        XCTAssertEqual(y, 0.4, accuracy: 0.001)
        waitForMain()
        XCTAssertEqual(rig.model.overlayPlacement, stored.position, "the viewfinder follows the record")
    }

    /// 11: a style written through the sheet's style tab is in the store and
    /// shows in the viewfinder's overlay style at once.
    func test_656_11_styleTabWritesTheRecord() throws {
        let rig = try makeRig()
        let id = try XCTUnwrap(rig.model.profile?.id)
        rig.model.handleOverlayTextTap()
        let styleTab = try XCTUnwrap(rig.model.styleTabModel)

        styleTab.setSizeScale(150)

        let stored = try XCTUnwrap(rig.store.profiles.first { $0.id == id })
        XCTAssertEqual(stored.style.sizeScale, 150)
        waitForMain()
        XCTAssertEqual(rig.model.overlayStyle.sizeScale, 150)
    }

    private func waitForMain() {
        let settled = expectation(description: "main queue drains")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }

    // MARK: - 10, 712-3, 712-7: what the shutter saves

    /// A 3:4 portrait photo of `size` points, one color, at the screen scale.
    private func photo(_ size: CGSize = CGSize(width: 12, height: 16), color: UIColor = .systemTeal) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func waitForSave(_ saves: SaveRecorder, count: Int = 1) {
        let deadline = Date().addingTimeInterval(3)
        while saves.images.count < count && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// 10／712-3: after the sheet was opened and edited, the saved 3:4 image
    /// is the camera's, unchanged — no overlay baked in and not cropped.
    func test_656_10_savedImageIsTheCleanOriginal() throws {
        let original = photo()
        let originalData = try XCTUnwrap(original.pngData())

        func shoot(editFirst: Bool) throws -> Data {
            let saves = SaveRecorder()
            let rig = try makeRig(save: saves.save,
                                  captureImage: { _, completion in completion(.success(original)) })
            if editFirst {
                rig.model.handleOverlayTextTap()
                rig.model.panelModel.overlayDragHandler?.overlayDragEnded(center: CGPoint(x: 90, y: 120),
                                                                          viewfinderSize: CGSize(width: 120, height: 160))
                rig.model.closeStylePanel()
            }
            rig.model.beginCapture()
            waitForSave(saves)
            let saved = try XCTUnwrap(saves.images.first, "656-10 a photo was saved")
            return try XCTUnwrap(saved.pngData())
        }

        let edited = try shoot(editFirst: true)
        let untouched = try shoot(editFirst: false)
        XCTAssertEqual(edited, untouched, "656-10 editing the style changes nothing saved")
        XCTAssertEqual(edited, originalData, "656-10／712-3 no overlay baked in, 3:4 not cropped")
    }

    /// 712-3: at 1:1 and 9:16 the saved photo has the ratio's shape, cut from
    /// the middle, with the camera's own pixels (no overlay); a landscape
    /// photo stays landscape, as in 1.3.0.
    func test_712_3_savedPhotoIsCroppedToTheRatio() throws {
        let cases: [(CaptureAspectRatio, CGSize, CGFloat)] = [
            (.oneByOne, CGSize(width: 30, height: 40), 1),
            (.nineBySixteen, CGSize(width: 36, height: 48), 9.0 / 16),
            (.oneByOne, CGSize(width: 40, height: 30), 1),
            (.nineBySixteen, CGSize(width: 48, height: 36), 16.0 / 9),
        ]
        for (ratio, size, aspect) in cases {
            let original = photo(size)
            let saves = SaveRecorder()
            let rig = try makeRig(save: saves.save,
                                  captureImage: { _, completion in completion(.success(original)) })
            while rig.model.captureAspectRatio != ratio { rig.model.cycleAspectRatio() }
            rig.model.beginCapture()
            waitForSave(saves)
            let saved = try XCTUnwrap(saves.images.first, "\(ratio) \(size) saved")
            let cgImage = try XCTUnwrap(saved.cgImage)
            XCTAssertEqual(CGFloat(cgImage.width) / CGFloat(cgImage.height), aspect, accuracy: 0.02, "\(ratio) \(size)")
            XCTAssertEqual(saved.imageOrientation, .up)
            let cropped = try XCTUnwrap(CameraScreenModel.cropped(original, to: ratio)?.pngData())
            XCTAssertEqual(try XCTUnwrap(saved.pngData()), cropped, "712-3 only cropped, nothing drawn")
        }
    }

    /// 712-3: the crop window is the centered `ImageCropper` window, in
    /// pixels, and 3:4 hands the same image back.
    func test_712_3_cropUsesTheCenteredWindow() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        XCTAssertTrue(CameraScreenModel.cropped(image, to: .threeByFour) === image, "712-3 3:4 is not cropped")
        let square = try XCTUnwrap(CameraScreenModel.cropped(image, to: .oneByOne)?.cgImage)
        XCTAssertEqual(square.width, 300)
        XCTAssertEqual(square.height, 300)
        let tall = try XCTUnwrap(CameraScreenModel.cropped(image, to: .nineBySixteen)?.cgImage)
        XCTAssertEqual(CGSize(width: tall.width, height: tall.height),
                       ImageCropper.cropRect(forPixelSize: CGSize(width: 300, height: 400), ratio: .nineBySixteen).size)
    }

    /// 712-7: a photo still on its way keeps the ratio and the record of the
    /// moment the shutter was pressed, whatever is switched before it is
    /// saved.
    func test_712_7_photoKeepsTheRatioAndRecordOfTheShutterPress() throws {
        let store = makeStore()
        let first = try addRecord(to: store, name: "甲", start: DateFixture.components(2026, 1, 1))
        let second = try addRecord(to: store, name: "乙", start: DateFixture.components(2026, 1, 1))
        let original = photo(CGSize(width: 30, height: 40))
        var pending: ((Result<UIImage, CameraCaptureError>) -> Void)?
        let saves = SaveRecorder()
        let rig = try makeRig(store: store, record: first, save: saves.save,
                              captureImage: { _, completion in pending = completion })
        rig.model.cycleAspectRatio()
        XCTAssertEqual(rig.model.captureAspectRatio, .oneByOne)
        rig.model.beginCapture()
        let deliver = try XCTUnwrap(pending, "the shutter fired")

        rig.model.cycleAspectRatio()
        rig.model.selectRecord(second.id)
        XCTAssertEqual(rig.model.captureAspectRatio, .nineBySixteen)
        XCTAssertEqual(rig.model.selectedProfileID, second.id)
        deliver(.success(original))
        waitForSave(saves)

        let saved = try XCTUnwrap(saves.images.first?.cgImage)
        XCTAssertEqual(saved.width, saved.height, "712-7 cropped at the pressed 1:1")
        XCTAssertEqual(saves.albumTitles, ["甲"], "712-7 saved for the pressed record")
    }
}
