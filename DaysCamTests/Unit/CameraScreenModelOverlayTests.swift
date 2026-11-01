import UIKit
import XCTest
@testable import DaysCam

/// #656: the camera's overlay preview — the switch (FR-20.9), the text drawn
/// in the viewfinder (FR-20.2, FR-20.6), the style sheet opened from it
/// (FR-20.10) and the clean original the shutter still saves (FR-20.4).
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
        func save(_ image: UIImage, _ albumIdentifier: String?, _ albumTitle: String,
                  _ completion: @escaping (Result<RecordSaveOutcome, PhotoSaveError>) -> Void) {
            images.append(image)
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
                                      overlayPreviewDefaults: defaults,
                                      tips: tips)
        return Rig(model: model, store: store, center: center, toastSpy: spy, tips: tips)
    }

    // MARK: - 2: the switch

    /// 1／2: on by default; a flip is remembered across models (app level).
    func test_656_2_switchDefaultsToOnAndIsRemembered() throws {
        let rig = try makeRig()
        XCTAssertTrue(rig.model.isOverlayPreviewOn)
        XCTAssertTrue(rig.model.showsOverlay)

        rig.model.toggleOverlayPreview()
        XCTAssertFalse(rig.model.isOverlayPreviewOn)
        XCTAssertFalse(rig.model.showsOverlay)

        let reopened = try makeRig(store: rig.store)
        XCTAssertFalse(reopened.model.isOverlayPreviewOn, "656-2 survives closing and reopening the camera")
    }

    /// 2: not per record — another record sees the same state.
    func test_656_2_switchDoesNotDependOnTheRecord() throws {
        let rig = try makeRig()
        let other = try addRecord(to: rig.store, name: "第二個", start: DateFixture.components(2026, 1, 1))
        rig.model.toggleOverlayPreview()
        let second = try makeRig(store: rig.store, record: other)
        XCTAssertFalse(second.model.isOverlayPreviewOn)
    }

    /// 1: each flip says so in the middle of the screen, then the toast goes.
    func test_656_1_toggleShowsACenterToast() throws {
        let rig = try makeRig()
        rig.model.toggleOverlayPreview()
        XCTAssertEqual(rig.model.centerToast?.message, "疊字預覽 關閉")
        rig.model.toggleOverlayPreview()
        XCTAssertEqual(rig.model.centerToast?.message, "疊字預覽 開啟")

        // The first toast's dismiss fires late and must not take the newer one.
        rig.toastSpy.scheduled[0]()
        XCTAssertEqual(rig.model.centerToast?.message, "疊字預覽 開啟")
        rig.toastSpy.scheduled[1]()
        XCTAssertNil(rig.model.centerToast)
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
                                      overlayPreviewDefaults: defaults, tips: FirstRunTips(defaults: tipsDefaults))
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

    /// 8: with the preview off there is no way into the sheet and no text
    /// to shield from focus.
    func test_656_8_noSheetAndNoShieldWhilePreviewIsOff() throws {
        let rig = try makeRig()
        rig.model.overlayTextFrame = CGRect(x: 10, y: 10, width: 100, height: 40)
        XCTAssertTrue(rig.model.viewfinderTouchStartsOnOverlayText(at: CGPoint(x: 20, y: 20)))
        XCTAssertFalse(rig.model.viewfinderTouchStartsOnOverlayText(at: CGPoint(x: 300, y: 300)),
                       "656-8 outside the text is focus")

        rig.model.toggleOverlayPreview()
        rig.model.handleOverlayTextTap()
        XCTAssertFalse(rig.model.panelModel.isOpen)
        XCTAssertFalse(rig.model.viewfinderTouchStartsOnOverlayText(at: CGPoint(x: 20, y: 20)),
                       "656-8 off: the whole viewfinder is focus")
    }

    /// 6: no sheet during a countdown, and turning the preview off closes it.
    func test_656_6_sheetNeedsThePreviewAndNoCountdown() throws {
        let rig = try makeRig()
        rig.model.handleOverlayTextTap()
        rig.model.toggleOverlayPreview()
        XCTAssertFalse(rig.model.panelModel.isOpen)
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

    /// 9: the hint shows with the preview on until the sheet was opened once,
    /// in any later launch too; off, it is not shown.
    func test_656_9_hintGoesAwayForGoodOnceTheSheetWasOpened() throws {
        let rig = try makeRig()
        XCTAssertTrue(rig.model.showsOverlayTip)

        rig.model.toggleOverlayPreview()
        XCTAssertFalse(rig.model.showsOverlayTip)
        rig.model.toggleOverlayPreview()
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

    // MARK: - 10: the shutter still saves the clean original

    /// 10: with the preview on and the sheet opened and edited, the saved
    /// image is the camera's, unchanged — same as with the preview off.
    func test_656_10_savedImageIsTheCleanOriginal() throws {
        let original = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 16)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 16))
        }
        let originalData = try XCTUnwrap(original.pngData())

        func shoot(previewOn: Bool, editFirst: Bool) throws -> Data {
            let saves = SaveRecorder()
            let rig = try makeRig(save: saves.save,
                                  captureImage: { _, completion in completion(.success(original)) })
            if !previewOn { rig.model.toggleOverlayPreview() }
            if editFirst {
                rig.model.handleOverlayTextTap()
                rig.model.panelModel.overlayDragHandler?.overlayDragEnded(center: CGPoint(x: 90, y: 120),
                                                                          viewfinderSize: CGSize(width: 120, height: 160))
                rig.model.closeStylePanel()
            }
            rig.model.beginCapture()
            let deadline = Date().addingTimeInterval(3)
            while saves.images.isEmpty && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            let saved = try XCTUnwrap(saves.images.first, "656-10 a photo was saved")
            return try XCTUnwrap(saved.pngData())
        }

        let withPreview = try shoot(previewOn: true, editFirst: true)
        let withoutPreview = try shoot(previewOn: false, editFirst: false)
        XCTAssertEqual(withPreview, withoutPreview, "656-10 preview on or off, the same image")
        XCTAssertEqual(withPreview, originalData, "656-10 no overlay baked in")
    }
}
