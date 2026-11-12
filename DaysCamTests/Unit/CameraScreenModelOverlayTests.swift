import Combine
import UIKit
import XCTest
@testable import DaysCam

/// #724: the camera's day HUD in place of the overlay preview — the day text
/// of a photo taken now and the record's name, following the switcher and
/// midnight — and (#656, #712) the shutter saving the photo cropped to the
/// ratio but never with the overlay (FR-20.4).
@MainActor
final class CameraScreenModelOverlayTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteNames: [String] = []
    private var now = Date()

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CameraScreenModelOverlayTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = try makeSuite()
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
        let toastSpy: SchedulerSpy
    }

    private func makeStore() -> ProfileStore {
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { [now] in now },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        store.load()
        return store
    }

    @discardableResult
    private func addRecord(to store: ProfileStore, name: String, start: DateComponents,
                           units: Set<DisplayUnit>? = nil) throws -> CameraProfile {
        var profile = CameraProfile(name: name, startDate: start)
        if let units { profile.displayUnits = units }
        return try store.add(profile)
    }

    private func makeRig(store: ProfileStore? = nil, record: CameraProfile? = nil,
                         save: @escaping CameraScreenModel.Save = { _, _, _, completion in
                             completion(.success(RecordSaveOutcome(assetID: "asset", albumID: nil)))
                         },
                         captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil,
                         calculator: DayCountCalculator? = nil) throws -> Rig {
        let store = store ?? makeStore()
        let calculator = calculator ?? DayCountCalculator(calendar: DateFixture.taipei, now: { [now] in now })
        let spy = SchedulerSpy()
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
                                      levelDefaults: defaults)
        return Rig(model: model, store: store, toastSpy: spy)
    }

    // MARK: - 724-1: the HUD

    /// 724-1: the shared scenario (小寶 from 2026-01-01, today 2026-01-10)
    /// reads 「第 10 天」 over 「2026.01.10」, as one VoiceOver label; no name.
    func test_724_1_hudIsTheDayAndTheRecordName() throws {
        let store = makeStore()
        let record = try addRecord(to: store, name: "小寶", start: DateFixture.components(2026, 1, 1))
        let rig = try makeRig(store: store, record: record)
        let hud = try XCTUnwrap(rig.model.dayHUD)
        XCTAssertEqual(hud.dayText, "第 10 天")
        XCTAssertEqual(hud.dateText, "2026.01.10")
        XCTAssertFalse(hud.isBeforeStart)
        XCTAssertEqual(hud.accessibilityLabel, "第 10 天，2026.01.10")
        XCTAssertFalse(hud.accessibilityLabel.contains("小寶"), "the name is in the switcher, not the HUD")
    }

    /// 724-1: the HUD is interface, not the overlay: the record's 疊字,
    /// 天數, 日期 and 名稱 switches change neither line.
    func test_724_1_hudIgnoresTheOverlaySwitches() throws {
        let store = makeStore()
        var record = try addRecord(to: store, name: "小寶", start: DateFixture.components(2026, 1, 1))
        for (overlay, dayCount, date, name) in [(false, false, false, true), (true, true, true, true)] {
            record.showOverlay = overlay
            record.showDayCount = dayCount
            record.showDate = date
            record.showName = name
            try store.updateAndWait(record)
            let rig = try makeRig(store: store, record: record)
            XCTAssertEqual(rig.model.dayHUD?.dayText, "第 10 天", "date \(date)")
            XCTAssertEqual(rig.model.dayHUD?.dateText, "2026.01.10", "date \(date): the date even when the record prints none")
        }
    }

    /// 724-1: no record, no HUD.
    func test_724_1_noHUDOnceTheRecordIsGone() throws {
        let store = makeStore()
        let record = try addRecord(to: store, name: "小寶", start: DateFixture.components(2026, 1, 1))
        let rig = try makeRig(store: store, record: record)
        XCTAssertNotNil(rig.model.dayHUD)
        try store.delete(id: record.id)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(rig.model.dayHUD)
    }

    // MARK: - 724-4: switching records

    /// 724-4: the switcher swaps the HUD's text and name at once; a record
    /// with 月＋天 reads 「3 個月又 6 天」.
    func test_724_4_switchingRecordSwapsTheHUD() throws {
        let store = makeStore()
        let first = try addRecord(to: store, name: "小寶", start: DateFixture.components(2026, 1, 1))
        let second = try addRecord(to: store, name: "小芽", start: DateFixture.components(2025, 10, 4),
                                   units: [.month, .day])
        let rig = try makeRig(store: store, record: first)
        XCTAssertEqual(rig.model.dayHUD?.dayText, "第 10 天")

        rig.model.selectRecord(second.id)

        XCTAssertEqual(rig.model.dayHUD, CameraScreenModel.DayHUD(dayText: "3 個月又 6 天", dateText: "2026.01.10",
                                                                 isBeforeStart: false))
    }

    /// 724-4: the HUD takes the photo wall's first (longest) text.
    func test_724_4_hudIsTheWallsFirstText() throws {
        let store = makeStore()
        let record = try addRecord(to: store, name: "小芽", start: DateFixture.components(2024, 8, 5),
                                   units: [.year, .month, .week, .day])
        let rig = try makeRig(store: store, record: record)
        let profile = try XCTUnwrap(rig.model.profile)
        let wall = PhotoWallModel.dayMarkTexts(creationDate: now, profile: profile, calendar: DateFixture.taipei)
        XCTAssertGreaterThan(wall.texts.count, 1, "a text the wall would shorten")
        XCTAssertEqual(rig.model.dayHUD?.dayText, wall.texts.first)
    }

    // MARK: - 724-5: before the start, midnight

    /// 724-5: a start date after today reads 「前 N 天」 in the before-start
    /// ink; a normal day stays white.
    func test_724_5_beforeStartUsesTheBeforeStartInk() throws {
        let store = makeStore()
        let record = try addRecord(to: store, name: "未來", start: DateFixture.components(2026, 2, 1))
        let rig = try makeRig(store: store, record: record)
        let hud = try XCTUnwrap(rig.model.dayHUD)
        XCTAssertEqual(hud.dayText, "前 22 天")
        XCTAssertEqual(hud.dateText, "2026.01.10", "today's date, not the start date")
        XCTAssertTrue(hud.isBeforeStart)
        XCTAssertEqual(CameraDayHUD.dayInk(isBeforeStart: hud.isBeforeStart), CameraTheme.inkOnPhotoBeforeStart)
        XCTAssertEqual(CameraDayHUD.dayInk(isBeforeStart: false), CameraTheme.inkOnPhoto)
    }

    /// 724-5: after midnight `refreshOverlay()` bumps `refreshTick` and the
    /// HUD reads the new day; nothing is cached.
    func test_724_5_hudFollowsMidnight() throws {
        let store = makeStore()
        let record = try addRecord(to: store, name: "小寶", start: DateFixture.components(2026, 1, 1))
        let clock = ClockBox(now)
        let rig = try makeRig(store: store, record: record,
                              calculator: DayCountCalculator(calendar: DateFixture.taipei, now: clock.read))
        XCTAssertEqual(rig.model.dayHUD?.dayText, "第 10 天")
        XCTAssertEqual(rig.model.dayHUD?.dateText, "2026.01.10")
        var changes = 0
        let watch = rig.model.objectWillChange.sink { changes += 1 }
        defer { watch.cancel() }

        clock.value = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 0))
        let tick = rig.model.refreshTick
        rig.model.refreshOverlay()

        XCTAssertEqual(rig.model.refreshTick, tick + 1)
        XCTAssertGreaterThan(changes, 0, "the view redraws")
        XCTAssertEqual(rig.model.dayHUD?.dayText, "第 11 天")
        XCTAssertEqual(rig.model.dayHUD?.dateText, "2026.01.11", "the date follows midnight too")
    }

    private final class ClockBox {
        var value: Date
        init(_ value: Date) { self.value = value }
        func read() -> Date { value }
    }

    // MARK: - 724-7: no panel condition left

    /// 724-7: with no style sheet, the switcher is only held by a countdown
    /// and the level runs with nothing open.
    func test_724_7_nothingWaitsForAPanel() throws {
        let rig = try makeRig()
        XCTAssertFalse(rig.model.isRecordSwitcherDisabled)
        rig.model.toggleLevel()
        XCTAssertTrue(rig.model.levelConditions(isSceneActive: true).shouldRun)
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

    /// 724-8／712-3: the saved 3:4 image is the camera's, unchanged — no
    /// overlay or HUD baked in and not cropped, with the overlay switched on.
    func test_724_8_savedImageIsTheCleanOriginal() throws {
        let original = photo()
        let originalData = try XCTUnwrap(original.pngData())
        let store = makeStore()
        var record = try addRecord(to: store, name: "小寶", start: DateFixture.components(2026, 1, 1))
        record.showOverlay = true
        record.showFilmDate = true
        try store.updateAndWait(record)
        let saves = SaveRecorder()
        let rig = try makeRig(store: store, record: record, save: saves.save,
                              captureImage: { _, completion in completion(.success(original)) })
        XCTAssertNotNil(rig.model.dayHUD)
        rig.model.beginCapture()
        waitForSave(saves)
        let saved = try XCTUnwrap(saves.images.first, "724-8 a photo was saved")
        XCTAssertEqual(try XCTUnwrap(saved.pngData()), originalData, "724-8／712-3 nothing baked in, 3:4 not cropped")
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
