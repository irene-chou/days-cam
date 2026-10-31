import AVFoundation
import Combine
import UIKit
import XCTest
@testable import DaysCam

/// Covers `CameraScreenModel` (PRD 2.0 FR-20, #621): how it turns
/// `CameraService`'s published state into what the viewfinder should show,
/// the 「第 N 天」 HUD, the shutter's capture state machine and how the clean
/// original is saved into the record's album and written back to the record.
///
/// Like `CameraServiceTests`, every test stubs `CameraAuthorizing` and
/// `CaptureDeviceProviding` so nothing here touches real hardware or a real
/// permission prompt. The fully-`.running` shutter-enabled state is a B-level
/// (device) acceptance item, not covered here.
///
/// The profile side uses a real `ProfileStore` backed by a temporary
/// directory and an isolated `UserDefaults` suite.
@MainActor
final class CameraScreenModelTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CameraScreenModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CameraScreenModelTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - Doubles (mirrors CameraServiceTests' private doubles)

    private final class StubAuthorizer: CameraAuthorizing {
        var status: AVAuthorizationStatus
        init(status: AVAuthorizationStatus) { self.status = status }
        func authorizationStatus() -> AVAuthorizationStatus { status }
        func requestAccess(completion: @escaping (Bool) -> Void) {
            let granted = status == .authorized
            completion(granted)
        }
    }

    private final class EmptyDeviceProvider: CaptureDeviceProviding {
        private(set) var requestedFacings: [CameraFacing] = []
        func device(for facing: CameraFacing) -> AVCaptureDevice? {
            requestedFacings.append(facing)
            return nil
        }
    }

    private final class StubFlashCapabilityProvider: FlashCapabilityProviding {
        let hasFlash: Bool
        init(hasFlash: Bool) { self.hasFlash = hasFlash }
        func hasFlash(for facing: CameraFacing) -> Bool { hasFlash }
    }

    /// A `CountdownTicker` a test drives one tick at a time, instead of
    /// waiting on a real clock (TASK-21, acceptance 19.8–19.10).
    private final class FakeCountdownTicker: CountdownTicker {
        private(set) var startCallCount = 0
        private(set) var stopCallCount = 0
        private var onTick: (() -> Void)?

        func start(onTick: @escaping () -> Void) {
            startCallCount += 1
            self.onTick = onTick
        }

        func stop() {
            stopCallCount += 1
            onTick = nil
        }

        /// Simulates one second passing. A no-op once `stop()` has been
        /// called, so a test that ticks past the countdown's end (by
        /// mistake, or to prove nothing fires twice) does not crash.
        func tick() {
            onTick?()
        }
    }

    /// Records every save the model starts and holds its completion, so a
    /// test answers (or never answers) each one by hand.
    private final class SaveRecorder {
        struct Call {
            let image: UIImage
            let albumIdentifier: String?
            let albumTitle: String
            let completion: (Result<RecordSaveOutcome, PhotoSaveError>) -> Void
        }

        private(set) var calls: [Call] = []

        func save(_ image: UIImage, _ albumIdentifier: String?, _ albumTitle: String,
                  _ completion: @escaping (Result<RecordSaveOutcome, PhotoSaveError>) -> Void) {
            calls.append(Call(image: image, albumIdentifier: albumIdentifier,
                              albumTitle: albumTitle, completion: completion))
        }
    }

    /// Holds the shutter's capture completions, so a test hands photos back
    /// one at a time.
    private final class CaptureRecorder {
        private(set) var completions: [(Result<UIImage, CameraCaptureError>) -> Void] = []

        func capture(_ flashMode: FlashMode,
                     _ completion: @escaping (Result<UIImage, CameraCaptureError>) -> Void) {
            completions.append(completion)
        }
    }

    /// Records scheduled dismiss callbacks without running them, so a test
    /// can invoke them in whatever order it wants to (e.g. an older toast's
    /// dismiss firing after a newer toast was presented).
    private final class SchedulerSpy {
        private(set) var scheduled: [() -> Void] = []
        func schedule(_ work: @escaping () -> Void) {
            scheduled.append(work)
        }
    }

    /// A clock whose reading can be moved after construction, so a test can
    /// prove a value is recomputed live rather than cached at `init` time.
    private final class MutableClock {
        var current: Date
        init(_ date: Date) { current = date }
        func now() -> Date { current }
    }

    /// A latest-photo read that waits for the test to let it finish — models
    /// a slow library read.
    @MainActor
    private final class GatedPhotoLoader {
        private(set) var isWaiting = false
        private var continuation: CheckedContinuation<Void, Never>?
        let image: UIImage?

        init(image: UIImage?) { self.image = image }

        func load() async -> UIImage? {
            isWaiting = true
            await withCheckedContinuation { continuation = $0 }
            isWaiting = false
            return image
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    // MARK: - Helpers

    private func fixedNow() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
    }

    private func outcome(_ assetID: String = "asset-1", album: String? = nil) -> RecordSaveOutcome {
        RecordSaveOutcome(assetID: assetID, albumID: album)
    }

    /// A store holding the one seeded default record.
    private func makeProfileStore(clock: MutableClock) -> ProfileStore {
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: clock.now,
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        store.load()
        return store
    }

    @discardableResult
    private func addRecord(to store: ProfileStore,
                           name: String = "小寶",
                           start: DateComponents = DateFixture.components(2026, 1, 1),
                           albumIdentifier: String? = nil,
                           fallbackAssetIDs: [String] = []) throws -> CameraProfile {
        var profile = CameraProfile(name: name, startDate: start, albumIdentifier: albumIdentifier)
        profile.fallbackAssetIDs = fallbackAssetIDs
        return try store.add(profile)
    }

    private func storedRecord(_ id: UUID, in store: ProfileStore) throws -> CameraProfile {
        try XCTUnwrap(store.profiles.first { $0.id == id })
    }

    private func destination(of record: CameraProfile) -> CameraScreenModel.CaptureDestination {
        CameraScreenModel.CaptureDestination(profileID: record.id, albumTitle: record.name)
    }

    /// Builds a model for `record` (the store's first record when `nil`).
    /// `clock` defaults to 2026-01-10 08:00; `captureSettingsStore` to a store
    /// backed by this test's own `defaults` suite so settings never leak
    /// between runs. `scheduleToastDismiss` defaults to never firing, so a
    /// toast stays put until the test inspects it.
    private func makeModel(status: AVAuthorizationStatus = .notDetermined,
                           captureSupported: Bool = false,
                           clock: MutableClock? = nil,
                           profileStore: ProfileStore? = nil,
                           record: CameraProfile? = nil,
                           flashCapabilityProvider: FlashCapabilityProviding? = nil,
                           captureSettingsStore: CaptureSettingsStore? = nil,
                           countdownTicker: CountdownTicker = SystemCountdownTicker(),
                           saveCoordinator: CaptureSaveCoordinator? = nil,
                           save: @escaping CameraScreenModel.Save = { _, _, _, completion in
                               completion(.success(RecordSaveOutcome(assetID: "asset-1", albumID: nil)))
                           },
                           captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil,
                           scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { _ in },
                           loadLatestPhoto: @escaping @MainActor () async -> UIImage? = { nil },
                           reportFailureAfterClose: @escaping @MainActor (CaptureAlertError, Int) -> Void = { _, _ in },
                           reportRecordWriteFailure: @escaping @MainActor (Error) -> Void = { _ in },
                           saveTimeout: TimeInterval = 30) throws
        -> (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore) {
        let resolvedClock = try clock ?? MutableClock(fixedNow())
        let provider = EmptyDeviceProvider()
        let service = CameraService(authorizer: StubAuthorizer(status: status),
                                    deviceProvider: provider,
                                    flashCapabilityProvider: flashCapabilityProvider,
                                    isCaptureSupported: captureSupported)
        let store = profileStore ?? makeProfileStore(clock: resolvedClock)
        let profileID = try XCTUnwrap(record?.id ?? store.profiles.first?.id)
        let model = CameraScreenModel(cameraService: service,
                                      profileStore: store,
                                      profileID: profileID,
                                      captureSettingsStore: captureSettingsStore ?? CaptureSettingsStore(defaults: defaults),
                                      calendar: DateFixture.taipei,
                                      calculator: DayCountCalculator(calendar: DateFixture.taipei, now: resolvedClock.now),
                                      countdownTicker: countdownTicker,
                                      saveCoordinator: saveCoordinator,
                                      save: save,
                                      captureImage: captureImage,
                                      loadLatestPhoto: loadLatestPhoto,
                                      reportFailureAfterClose: reportFailureAfterClose,
                                      reportRecordWriteFailure: reportRecordWriteFailure,
                                      scheduleToastDismiss: scheduleToastDismiss,
                                      saveTimeout: saveTimeout)
        return (model, service, provider, store)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 2) {
        if condition() { return }
        let exp = expectation(description: "condition became true")
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() || Date() >= deadline {
                exp.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: poll)
        }
        poll()
        wait(for: [exp], timeout: timeout + 1)
        XCTAssertTrue(condition(), "condition never became true within \(timeout)s")
    }

    private func solidImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    /// A photo whose pixel buffer is `pixelSize`, shown at `scale` and
    /// `orientation` the way AVFoundation hands one over.
    private func makePhoto(pixelSize: CGSize, scale: CGFloat = 1,
                           orientation: UIImage.Orientation = .up) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let base = UIGraphicsImageRenderer(size: pixelSize, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: pixelSize))
        }
        let cgImage = try XCTUnwrap(base.cgImage)
        return UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
    }

    // MARK: - showsPlaceholder / isCaptureUnsupported
    //
    // `status` can never reach `.running` without a real capture device (same
    // limitation `CameraServiceTests` documents), so `isSessionNotRunning` is
    // unconditionally true everywhere in this test target. Testing each
    // sub-property directly, rather than only through the OR'd composite
    // `isShutterDisabled`, is what catches a broken individual condition.

    func testIsCaptureUnsupportedTrueWhenCaptureNotSupported() throws {
        let (model, _, _, _) = try makeModel(captureSupported: false)
        XCTAssertTrue(model.isCaptureUnsupported)
        XCTAssertTrue(model.showsPlaceholder)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testIsCaptureUnsupportedFalseWhenCaptureSupported() throws {
        let (model, _, _, _) = try makeModel(captureSupported: true)
        XCTAssertFalse(model.isCaptureUnsupported)
        XCTAssertFalse(model.showsPlaceholder)
    }

    // MARK: - needsPermissionGuidance

    func testNeedsPermissionGuidanceTrueWhenDenied() throws {
        let (model, service, _, _) = try makeModel(status: .denied, captureSupported: true)
        model.onAppear()
        waitUntil { service.permission == .denied }
        XCTAssertTrue(model.needsPermissionGuidance)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testNeedsPermissionGuidanceTrueWhenRestricted() throws {
        let (model, service, _, _) = try makeModel(status: .restricted, captureSupported: true)
        model.onAppear()
        waitUntil { service.permission == .restricted }
        XCTAssertTrue(model.needsPermissionGuidance)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testNeedsPermissionGuidanceFalseWhenAuthorized() throws {
        let (model, service, _, _) = try makeModel(status: .authorized, captureSupported: false)
        model.onAppear()
        waitUntil { service.permission == .authorized }
        XCTAssertFalse(model.needsPermissionGuidance)
    }

    // MARK: - isSessionNotRunning

    func testIsSessionNotRunningTrueBeforeOnAppear() throws {
        let (model, _, _, _) = try makeModel(captureSupported: true)
        XCTAssertTrue(model.isSessionNotRunning)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testIsSessionNotRunningTrueForSimulatorPlaceholderStatus() throws {
        // `.unavailable(.simulator)` is as close to "not idle" as this test
        // target can reach, and it is still not `.running`.
        let (model, service, _, _) = try makeModel(status: .authorized, captureSupported: false)
        model.onAppear()
        waitUntil { service.status == .unavailable(.simulator) }
        XCTAssertTrue(model.isSessionNotRunning)
    }

    // MARK: - statusMessage

    func testStatusMessageNilWhenIdle() throws {
        let (model, _, _, _) = try makeModel(captureSupported: true)
        XCTAssertNil(model.statusMessage)
    }

    func testStatusMessageNilForSimulatorPlaceholder() throws {
        // The simulator gets its own placeholder + label; the generic
        // "相機暫時無法使用" message would be redundant on top of it.
        let (model, service, _, _) = try makeModel(status: .authorized, captureSupported: false)
        model.onAppear()
        waitUntil { service.status == .unavailable(.simulator) }
        XCTAssertNil(model.statusMessage)
    }

    func testStatusMessageForNoCaptureDevice() throws {
        // `EmptyDeviceProvider` always hands back nil, so an authorized,
        // capture-supported session still fails to configure.
        let (model, service, _, _) = try makeModel(status: .authorized, captureSupported: true)
        model.onAppear()
        waitUntil { service.status == .unavailable(.noCaptureDevice) }
        XCTAssertEqual(model.statusMessage, "相機暫時無法使用")
    }

    func testStatusMessageForInterruption() throws {
        let (model, service, _, _) = try makeModel(captureSupported: true)
        NotificationCenter.default.post(name: AVCaptureSession.wasInterruptedNotification, object: service.session)
        waitUntil { service.status == .interrupted }
        XCTAssertEqual(model.statusMessage, "相機暫時無法使用")
    }

    // MARK: - CameraService change forwarding

    func testModelPublishesWhenCameraServicePermissionChanges() throws {
        // `cameraService` is a nested `ObservableObject` this model reads
        // directly (`permission`, `status`) but `CameraScreen` only observes
        // this model — without forwarding `cameraService.objectWillChange`,
        // SwiftUI never learns a permission or status change happened.
        let (model, service, _, _) = try makeModel(status: .authorized, captureSupported: false)
        var fired = false
        let cancellable = model.objectWillChange.sink { fired = true }
        defer { cancellable.cancel() }

        model.onAppear()
        waitUntil { service.permission == .authorized }

        XCTAssertTrue(fired)
    }

    // MARK: - Lifecycle forwarding

    func testOnAppearStartsTheService() throws {
        let (model, service, _, _) = try makeModel(status: .authorized, captureSupported: false)
        XCTAssertEqual(service.permission, .notDetermined)
        model.onAppear()
        waitUntil { service.permission == .authorized }
    }

    /// 621-9: closing the camera stops the session.
    func test_621_9_onDisappearStopsTheService() throws {
        let (model, service, _, _) = try makeModel(status: .authorized, captureSupported: false)
        model.onAppear()
        waitUntil { service.status == .unavailable(.simulator) }
        model.onDisappear()
        waitUntil { service.status == .idle }
    }

    /// Closing the camera mid-countdown stops the ticker and takes no photo.
    func testOnDisappearCancelsARunningCountdownWithoutCapturing() throws {
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleTimer() // 3 seconds
        let ticker = FakeCountdownTicker()
        let captures = CaptureRecorder()
        let (model, _, _, _) = try makeModel(captureSettingsStore: settings, countdownTicker: ticker,
                                             captureImage: captures.capture)
        model.beginCapture()
        XCTAssertEqual(model.countdownRemaining, 3)

        model.onDisappear()

        XCTAssertNil(model.countdownRemaining)
        XCTAssertEqual(ticker.stopCallCount, 1)
        ticker.tick()
        XCTAssertTrue(captures.completions.isEmpty)
    }

    // MARK: - switchCamera forwarding

    func testSwitchCameraNoOpsWhenCaptureNotSupported() throws {
        let (model, _, provider, _) = try makeModel(captureSupported: false)
        model.switchCamera()
        // The guard in `CameraService.switchCamera()` returns before ever
        // touching the session queue, so this is observable synchronously.
        XCTAssertTrue(provider.requestedFacings.isEmpty)
    }

    func testSwitchCameraForwardsToServiceWhenCaptureSupported() throws {
        let (model, _, provider, _) = try makeModel(captureSupported: true)
        model.switchCamera()
        waitUntil { !provider.requestedFacings.isEmpty }
        XCTAssertEqual(provider.requestedFacings, [.front])
    }

    // MARK: - Day HUD (FR-20.2)

    /// 2026-01-01 start, today 2026-01-10: 「第 10 天」.
    func testDayHUDShowsTheElapsedDay() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record)
        XCTAssertEqual(model.dayHUDText, "第 10 天")
    }

    /// The HUD reads the clock on every access, it is not cached.
    func testDayHUDFollowsTheClock() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record)
        XCTAssertEqual(model.dayHUDText, "第 10 天")

        clock.current = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 8))
        XCTAssertEqual(model.dayHUDText, "第 11 天")
    }

    /// A start date still ahead reads 「還有 N 天」.
    func testDayHUDCountsDownToAFutureStartDate() throws {
        let clock = MutableClock(try XCTUnwrap(DateFixture.date(2025, 12, 1, hour: 8)))
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record)
        XCTAssertEqual(model.dayHUDText, "還有 31 天")
    }

    /// Whatever units, format or parts the record prints, the HUD is the
    /// elapsed days alone.
    func testDayHUDIgnoresTheRecordsUnitsFormatAndParts() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)

        var unitsAndFormat = CameraProfile(name: "年月日", startDate: DateFixture.components(2026, 1, 1))
        unitsAndFormat.displayUnits = [.year, .month, .day]
        unitsAndFormat.dayCountFormat = .dDay
        let first = try store.add(unitsAndFormat)

        var dateOnly = CameraProfile(name: "只有日期", startDate: DateFixture.components(2026, 1, 1))
        dateOnly.showDayCount = false
        dateOnly.showDate = true
        dateOnly.showName = true
        let second = try store.add(dateOnly)

        for record in [first, second] {
            let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record)
            XCTAssertEqual(model.dayHUDText, "第 10 天", record.name)
        }
    }

    // MARK: - Cross-midnight / foreground refresh (TASK-14)

    func testRefreshOverlayPublishesAChange() throws {
        // The HUD's re-render trigger, independent of the notification
        // plumbing below.
        let (model, _, _, _) = try makeModel()
        var fired = false
        let cancellable = model.objectWillChange.sink { fired = true }
        defer { cancellable.cancel() }

        model.refreshOverlay()

        XCTAssertTrue(fired)
    }

    /// Subscribes to `model.$refreshTick` and captures which thread the
    /// *first* change after subscribing is delivered on. Posting from a
    /// background queue is what makes this a real test: `NSCalendarDayChanged`
    /// is not documented to arrive on the main thread.
    private func threadRefreshTickChangeIsDeliveredOn(_ model: CameraScreenModel,
                                                       postingFrom queue: DispatchQueue = .global(),
                                                       post: @escaping () -> Void) -> Bool? {
        var deliveredOnMain: Bool?
        let exp = expectation(description: "refreshTick changed")
        let cancellable = model.$refreshTick.dropFirst().sink { _ in
            deliveredOnMain = Thread.isMainThread
            exp.fulfill()
        }
        defer { cancellable.cancel() }

        queue.async(execute: post)

        wait(for: [exp], timeout: 2)
        return deliveredOnMain
    }

    func testCalendarDayChangedNotificationTriggersARefreshOnTheMainThread() throws {
        let (model, _, _, _) = try makeModel()

        let deliveredOnMain = threadRefreshTickChangeIsDeliveredOn(model) {
            NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        }

        XCTAssertEqual(deliveredOnMain, true)
    }

    func testWillEnterForegroundNotificationTriggersARefreshOnTheMainThread() throws {
        let (model, _, _, _) = try makeModel()

        let deliveredOnMain = threadRefreshTickChangeIsDeliveredOn(model) {
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        }

        XCTAssertEqual(deliveredOnMain, true)
    }

    // MARK: - Toast ("已取消")

    func testShowToastShowsTheGivenMessage() throws {
        let (model, _, _, _) = try makeModel()
        model.showToast(message: "已取消")
        XCTAssertEqual(model.toastState?.message, "已取消")
    }

    func testShowToastCarriesTheThumbnail() throws {
        let (model, _, _, _) = try makeModel()
        let thumbnail = UIImage()
        model.showToast(message: "已取消", thumbnail: thumbnail)
        XCTAssertTrue(model.toastState?.thumbnail === thumbnail)
    }

    func testShowToastDismissesWhenTheScheduledCallbackFires() throws {
        let spy = SchedulerSpy()
        let (model, _, _, _) = try makeModel(scheduleToastDismiss: spy.schedule)

        model.showToast(message: "已取消")
        XCTAssertNotNil(model.toastState)
        XCTAssertEqual(spy.scheduled.count, 1)

        spy.scheduled[0]()

        XCTAssertNil(model.toastState)
    }

    func testANewerToastSurvivesAnOlderDismissTimerFiringLate() throws {
        // The toast must not be cut short by an earlier toast's dismiss timer
        // firing after a newer toast has already replaced it.
        let spy = SchedulerSpy()
        let (model, _, _, _) = try makeModel(scheduleToastDismiss: spy.schedule)

        model.showToast(message: "已取消")
        let firstID = model.toastState?.id
        model.showToast(message: "已取消")
        let secondID = model.toastState?.id
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(spy.scheduled.count, 2)

        spy.scheduled[0]() // the first toast's stale dismiss, firing late

        XCTAssertEqual(model.toastState?.id, secondID) // second toast untouched

        spy.scheduled[1]() // the second toast's own dismiss

        XCTAssertNil(model.toastState)
    }

    // MARK: - Shutter entry point

    func testCapturePhotoIsANoOpWhenTheShutterIsDisabled() throws {
        // `isShutterDisabled` requires `cameraService.status == .running`,
        // which never happens without a real capture device. `capturePhoto()`
        // must not flip `isCapturing` or crash in that state.
        let (model, _, _, _) = try makeModel()
        XCTAssertTrue(model.isShutterDisabled)

        model.capturePhoto()

        XCTAssertFalse(model.isCapturing)
    }

    // MARK: - Capture trigger

    func testCaptureTriggerFiresWhenTheShutterReallyFiresNotWhileCountingDownOrCancelling() throws {
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleTimer() // 3 seconds
        let ticker = FakeCountdownTicker()
        let captures = CaptureRecorder()
        let (model, _, _, _) = try makeModel(captureSettingsStore: settings, countdownTicker: ticker,
                                             captureImage: captures.capture)

        model.beginCapture()
        XCTAssertEqual(model.captureTriggerCount, 0)
        ticker.tick()
        ticker.tick()
        XCTAssertEqual(model.captureTriggerCount, 0)
        ticker.tick() // reaches zero
        XCTAssertEqual(model.captureTriggerCount, 1)
    }

    func testCaptureTriggerFiresImmediatelyWithoutATimer() throws {
        let captures = CaptureRecorder()
        let (model, _, _, _) = try makeModel(captureImage: captures.capture)
        model.beginCapture()
        XCTAssertEqual(model.captureTriggerCount, 1)
    }

    // MARK: - Where a photo goes (FR-20.4)

    /// The shutter saves into the album of the record the camera belongs to,
    /// titled with the record's name.
    func testShutterSavesForTheCamerasRecordTitledWithItsName() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store, name: "小寶", albumIdentifier: "album-1")
        let captures = CaptureRecorder()
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record,
                                             save: saves.save, captureImage: captures.capture)

        model.beginCapture()
        captures.completions[0](.success(UIImage()))

        waitUntil { saves.calls.count == 1 }
        XCTAssertEqual(saves.calls[0].albumTitle, "小寶")
        XCTAssertEqual(saves.calls[0].albumIdentifier, "album-1")
    }

    // MARK: - 621-1 the saved photo is the original

    /// 621-1: whatever orientation the camera hands over, the save receives
    /// the same pixels, upright and uncropped.
    func test_621_1_saveReceivesTheOriginalPixelSizeUpright() throws {
        let cases: [(orientation: UIImage.Orientation, scale: CGFloat, expectedPixels: CGSize)] = [
            (.up, 1, CGSize(width: 400, height: 300)),
            (.right, 1, CGSize(width: 300, height: 400)),
            (.up, 2, CGSize(width: 400, height: 300)),
            (.right, 2, CGSize(width: 300, height: 400))
        ]
        for testCase in cases {
            let saves = SaveRecorder()
            let clock = MutableClock(try fixedNow())
            let store = makeProfileStore(clock: clock)
            let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, save: saves.save)
            let record = try XCTUnwrap(store.profiles.first)
            let photo = try makePhoto(pixelSize: CGSize(width: 400, height: 300), scale: testCase.scale,
                                      orientation: testCase.orientation)

            model.processCapturedImage(photo, destination: destination(of: record))

            waitUntil { saves.calls.count == 1 }
            let saved = saves.calls[0].image
            let label = "orientation \(testCase.orientation.rawValue) @\(testCase.scale)x"
            XCTAssertEqual(saved.size.width * saved.scale, testCase.expectedPixels.width, "621-1 \(label)")
            XCTAssertEqual(saved.size.height * saved.scale, testCase.expectedPixels.height, "621-1 \(label)")
            XCTAssertEqual(saved.imageOrientation, .up, "621-1 \(label)")
        }
    }

    // MARK: - 621-2 full access

    /// 621-2: a record with no album learns the one the first photo created.
    func test_621_2_authorizedWritesTheNewAlbumIDWhenTheRecordHadNone() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store, name: "小寶")
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record, save: saves.save)

        model.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { saves.calls.count == 1 }
        XCTAssertNil(saves.calls[0].albumIdentifier)
        XCTAssertEqual(saves.calls[0].albumTitle, "小寶")
        saves.calls[0].completion(.success(outcome("A", album: "album-1")))

        XCTAssertEqual(try storedRecord(record.id, in: store).albumIdentifier, "album-1")
        XCTAssertTrue(try storedRecord(record.id, in: store).fallbackAssetIDs.isEmpty)
        waitUntil { model.inFlightSaveCount == 0 }
    }

    /// 621-2: the same album id is not written again.
    func test_621_2_authorizedWithTheSameAlbumIDDoesNotRewriteTheRecord() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store, albumIdentifier: "album-1")
        let before = try storedRecord(record.id, in: store)

        clock.current = clock.current.addingTimeInterval(3600)
        CameraScreenModel.record(outcome("A", album: "album-1"), savedFor: destination(of: record),
                                 albumAtSave: "album-1", in: store, reportWriteFailure: { XCTFail("no write failure expected: \($0)") })

        let after = try storedRecord(record.id, in: store)
        XCTAssertEqual(after.albumIdentifier, "album-1")
        XCTAssertTrue(after.fallbackAssetIDs.isEmpty)
        XCTAssertEqual(after.updatedAt, before.updatedAt, "621-2 no rewrite")
    }

    /// 621-2: an album deleted in 「照片」 and created again replaces the old id.
    func test_621_2_authorizedWritesTheRecreatedAlbumID() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store, albumIdentifier: "old")
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record, save: saves.save)

        model.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { saves.calls.count == 1 }
        XCTAssertEqual(saves.calls[0].albumIdentifier, "old")
        saves.calls[0].completion(.success(outcome("A", album: "new")))

        XCTAssertEqual(try storedRecord(record.id, in: store).albumIdentifier, "new")
        waitUntil { model.inFlightSaveCount == 0 }
    }

    /// 621-2: a record bound to another album while the save ran keeps that
    /// binding; the photo is kept by id so it still shows on the wall.
    func test_621_2_authorizedKeepsAnAlbumBoundWhileTheSaveRan() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store, albumIdentifier: "other")

        CameraScreenModel.record(outcome("A", album: "album-1"), savedFor: destination(of: record),
                                 albumAtSave: nil, in: store, reportWriteFailure: { XCTFail("no write failure expected: \($0)") })
        CameraScreenModel.record(outcome("A", album: "album-1"), savedFor: destination(of: record),
                                 albumAtSave: nil, in: store, reportWriteFailure: { XCTFail("no write failure expected: \($0)") })

        let after = try storedRecord(record.id, in: store)
        XCTAssertEqual(after.albumIdentifier, "other")
        XCTAssertEqual(after.fallbackAssetIDs, ["A"], "once, not twice")
    }

    /// 621-2: two photos in a row for a record without an album create one
    /// album: saves run one at a time and the album is read when a save
    /// starts, so the second one goes into the first one's album.
    func test_621_2_secondPhotoSavesIntoTheAlbumTheFirstCreated() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record, save: saves.save)

        model.processCapturedImage(UIImage(), destination: destination(of: record))
        model.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { model.captureFlights.count == 2 && saves.calls.count == 1 }
        XCTAssertNil(saves.calls[0].albumIdentifier)
        XCTAssertEqual(saves.calls.count, 1, "the second save waits for the first")

        saves.calls[0].completion(.success(outcome("A", album: "album-1")))

        XCTAssertEqual(saves.calls.count, 2)
        XCTAssertEqual(saves.calls[1].albumIdentifier, "album-1", "621-2")
        saves.calls[1].completion(.success(outcome("B", album: "album-1")))
        XCTAssertEqual(try storedRecord(record.id, in: store).albumIdentifier, "album-1")
        waitUntil { model.inFlightSaveCount == 0 }
    }

    // MARK: - 621-3 limited access

    /// 621-3: no album id back (limited access): the asset id joins
    /// `fallbackAssetIDs` and the album binding is left alone.
    func test_621_3_limitedAppendsTheAssetIDAndLeavesTheAlbumAlone() throws {
        for album in [nil, "album-1"] as [String?] {
            let clock = MutableClock(try fixedNow())
            let store = makeProfileStore(clock: clock)
            let record = try addRecord(to: store, albumIdentifier: album, fallbackAssetIDs: ["earlier"])
            let saves = SaveRecorder()
            let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record, save: saves.save)

            model.processCapturedImage(UIImage(), destination: destination(of: record))
            waitUntil { saves.calls.count == 1 }
            saves.calls[0].completion(.success(outcome("L1", album: nil)))

            let after = try storedRecord(record.id, in: store)
            XCTAssertEqual(after.fallbackAssetIDs, ["earlier", "L1"], "621-3 album \(String(describing: album))")
            XCTAssertEqual(after.albumIdentifier, album, "621-3 no album is created")
            waitUntil { model.inFlightSaveCount == 0 }
        }
    }

    /// 621-3: the same asset id is not added twice.
    func test_621_3_limitedDoesNotAppendTheSameAssetIDTwice() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)

        for _ in 0..<2 {
            CameraScreenModel.record(outcome("L1", album: nil), savedFor: destination(of: record),
                                     albumAtSave: nil, in: store, reportWriteFailure: { XCTFail("no write failure expected: \($0)") })
        }

        XCTAssertEqual(try storedRecord(record.id, in: store).fallbackAssetIDs, ["L1"])
    }

    // MARK: - Flights, thumbnail and announcements

    func testProcessCapturedImageStartsAFlightInsteadOfAToastOnSaveSuccess() throws {
        // Issue #148 (S.10): no "已儲存" toast; one flight instead.
        let (model, _, _, _) = try makeModel()
        let record = try XCTUnwrap(model.profile)

        model.processCapturedImage(UIImage(), destination: destination(of: record))

        waitUntil { model.captureFlights.count == 1 }
        XCTAssertEqual(model.captureFlights.first?.status, .saved)
        XCTAssertNil(model.toastState)
        XCTAssertNil(model.captureError)
        // The thumbnail only changes once the flight lands.
        XCTAssertNil(model.latestThumbnailImage)
        waitUntil { model.inFlightSaveCount == 0 }
    }

    func testLandingASavedFlightReplacesTheThumbnailAndRemovesIt() throws {
        let (model, _, _, _) = try makeModel()
        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))
        waitUntil { model.captureFlights.count == 1 }
        let id = try XCTUnwrap(model.captureFlights.first?.id)

        model.flightDidLand(id: id)

        XCTAssertNotNil(model.latestThumbnailImage)
        XCTAssertTrue(model.captureFlights.isEmpty)
        XCTAssertEqual(model.thumbnailLandingCount, 1)
    }

    func testThumbnailStaysOnTheNewPhotoAfterLandingEvenWhenALaterCaptureFails() throws {
        // Issue #148 (flicker fix): once a flight lands, the thumbnail must
        // never fall back to nil — a later failed capture included.
        var results: [Result<RecordSaveOutcome, PhotoSaveError>] = [.success(outcome()), .failure(.saveFailed("x"))]
        let (model, _, _, _) = try makeModel(save: { _, _, _, completion in completion(results.removeFirst()) })
        let target = destination(of: try XCTUnwrap(model.profile))
        model.processCapturedImage(UIImage(), destination: target)
        waitUntil { model.captureFlights.count == 1 }
        model.flightDidLand(id: model.captureFlights[0].id)
        let landed = try XCTUnwrap(model.latestThumbnailImage)

        model.processCapturedImage(UIImage(), destination: target)
        waitUntil { model.captureFlights.first?.status == .failed }
        model.removeCaptureFlight(id: model.captureFlights[0].id)

        XCTAssertTrue(model.latestThumbnailImage === landed)
    }

    func testSaveSuccessAnnouncesForVoiceOverAndFailureDoesNot() throws {
        var results: [Result<RecordSaveOutcome, PhotoSaveError>] = [.success(outcome()), .failure(.saveFailed("x"))]
        let (model, _, _, _) = try makeModel(save: { _, _, _, completion in completion(results.removeFirst()) })
        let target = destination(of: try XCTUnwrap(model.profile))
        var announcements: [String] = []
        model.announce = { announcements.append($0) }

        model.processCapturedImage(UIImage(), destination: target)
        waitUntil { announcements == ["已儲存"] }
        model.processCapturedImage(UIImage(), destination: target)
        waitUntil { model.captureFlights.contains { $0.status == .failed } }

        XCTAssertEqual(announcements, ["已儲存"])
    }

    func testFlightLandingBeforeSaveCompletesWaitsForTheSave() throws {
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(save: saves.save)
        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))
        waitUntil { model.captureFlights.count == 1 && saves.calls.count == 1 }
        let id = try XCTUnwrap(model.captureFlights.first?.id)

        model.flightDidLand(id: id)
        XCTAssertNil(model.latestThumbnailImage)
        XCTAssertEqual(model.captureFlights.count, 1)

        saves.calls[0].completion(.success(outcome()))
        XCTAssertNotNil(model.latestThumbnailImage)
        XCTAssertTrue(model.captureFlights.isEmpty)
    }

    func testBackToBackCapturesEachGetTheirOwnFlight() throws {
        let (model, _, _, _) = try makeModel()
        let target = destination(of: try XCTUnwrap(model.profile))
        for _ in 0..<3 {
            model.processCapturedImage(UIImage(), destination: target)
        }
        waitUntil { model.captureFlights.count == 3 }
        XCTAssertEqual(Set(model.captureFlights.map(\.id)).count, 3)
    }

    func testProcessCapturedImageDownscalesTheThumbnailAndFlightImage() throws {
        // The thumbnail (88pt) and flight picture (300pt) must not hold the
        // full-resolution photo.
        let largeSize = CGSize(width: 2000, height: 1600)
        let large = UIGraphicsImageRenderer(size: largeSize).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: largeSize))
        }
        let (model, _, _, _) = try makeModel()

        model.processCapturedImage(large, destination: destination(of: try XCTUnwrap(model.profile)))

        // Downscaling a 2000×1600 bitmap is slow on a loaded runner.
        waitUntil({ model.captureFlights.count == 1 }, timeout: 10)
        let flight = try XCTUnwrap(model.captureFlights.first)
        // 128.2: points are `maxDimension`; pixels are points * the screen
        // scale, once (not squared by the renderer's own scale).
        let scale = UIScreen.main.scale
        func pixels(_ image: UIImage) -> CGSize {
            CGSize(width: image.cgImage?.width ?? 0, height: image.cgImage?.height ?? 0)
        }
        let thumbnailPixels = pixels(flight.thumbnail)
        let flightPixels = pixels(flight.image)
        XCTAssertEqual(max(thumbnailPixels.width, thumbnailPixels.height),
                       CameraScreenModel.thumbnailMaxDimension * scale, accuracy: 1, "128.2")
        XCTAssertEqual(max(flightPixels.width, flightPixels.height),
                       CameraScreenModel.flightImageMaxDimension * scale, accuracy: 1, "128.2")
        XCTAssertEqual(flight.thumbnail.scale, scale)
        XCTAssertEqual(max(flight.thumbnail.size.width, flight.thumbnail.size.height),
                       CameraScreenModel.thumbnailMaxDimension, accuracy: 1)
    }

    /// 128.2: the pixel size follows the scale argument, never 3x by accident.
    func testThumbnailPixelSizeFollowsTheRequestedScale() {
        let size = CGSize(width: 2000, height: 1500)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: size, format: format).image { _ in }
        for scale in [1, 2, 3] as [CGFloat] {
            let thumb = CameraScreenModel.thumbnail(of: source, maxDimension: 88, scale: scale)
            XCTAssertEqual(thumb.cgImage?.width, Int(88 * scale), "128.2 @\(scale)x")
            XCTAssertEqual(thumb.cgImage?.height, Int((88 * scale * 0.75).rounded()), "128.2 @\(scale)x")
            XCTAssertEqual(thumb.scale, scale)
        }
        let small = CameraScreenModel.thumbnail(of: source, maxDimension: 5000, scale: 3)
        XCTAssertEqual(small.cgImage?.width, 2000, "never upscaled")
    }

    // MARK: - 621-4 failures and timeouts

    /// 621-4: a failed save raises the alert, frees the place and shows no
    /// success feedback.
    func test_621_4_saveFailureRaisesTheAlertAndFreesThePlace() throws {
        let (model, _, _, _) = try makeModel(save: { _, _, _, completion in
            completion(.failure(.saveFailed("磁碟空間不足")))
        })
        var announcements: [String] = []
        model.announce = { announcements.append($0) }

        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))

        waitUntil { model.captureError != nil && model.inFlightSaveCount == 0 }
        XCTAssertEqual(model.captureError?.message, "儲存失敗：磁碟空間不足。請確認裝置儲存空間後再試一次。")
        XCTAssertFalse(model.captureError?.showsSettingsAction ?? true)
        XCTAssertFalse(announcements.contains("已儲存"), "621-4 no success feedback")
        XCTAssertEqual(model.captureFlights.first?.status, .failed, "621-4")
        XCTAssertNil(model.toastState)
        XCTAssertNil(model.latestThumbnailImage)
    }

    /// 621-4 (#636 review): a save that fails after the camera closed is
    /// handed to the app, not left on the closed camera; nothing is in flight.
    func test_621_4_saveFailureAfterTheCameraClosedReachesTheApp() throws {
        let saves = SaveRecorder()
        var reported: [(CaptureAlertError, Int)] = []
        let (model, service, _, _) = try makeModel(save: saves.save,
                                                   reportFailureAfterClose: { reported.append(($0, $1)) })
        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))
        waitUntil { saves.calls.count == 1 }

        model.onDisappear()
        XCTAssertEqual(service.status, .idle)
        saves.calls[0].completion(.failure(.permissionDenied))

        waitUntil { model.inFlightSaveCount == 0 }
        XCTAssertEqual(model.inFlightSaveCount, 0)
        XCTAssertNil(model.captureError, "the closed camera shows nothing")
        XCTAssertEqual(reported.count, 1)
        XCTAssertEqual(reported.first?.1, 1)
        XCTAssertTrue(reported.first?.0.showsSettingsAction ?? false)
    }

    /// 621-4 (#636 review): a timeout after the camera closed reaches the app too.
    func test_621_4_saveTimeoutAfterTheCameraClosedReachesTheApp() throws {
        var reported: [(CaptureAlertError, Int)] = []
        let (model, _, _, _) = try makeModel(save: { _, _, _, _ in },
                                             reportFailureAfterClose: { reported.append(($0, $1)) },
                                             saveTimeout: 0.2)
        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))
        waitUntil { model.captureFlights.count == 1 }
        model.onDisappear()

        waitUntil({ model.inFlightSaveCount == 0 && !reported.isEmpty }, timeout: 3)
        XCTAssertEqual(model.inFlightSaveCount, 0)
        XCTAssertNil(model.captureError)
        XCTAssertEqual(reported.map(\.0.message), ["照片儲存逾時，這張可能沒有存進相簿。請再試一次。"])
    }

    /// 621-4 (#636 review): an alert still up when the camera closes is handed
    /// on once with its count, and the camera's own is cleared.
    func test_621_4_pendingAlertIsHandedOnWhenTheCameraCloses() throws {
        var reported: [(CaptureAlertError, Int)] = []
        let (model, _, _, _) = try makeModel(reportFailureAfterClose: { reported.append(($0, $1)) })
        model.reportPhotoFailure(message: "A", showsSettingsAction: false)
        model.reportPhotoFailure(message: "B", showsSettingsAction: false)

        model.onDisappear()

        XCTAssertNil(model.captureError)
        XCTAssertEqual(reported.count, 1)
        XCTAssertEqual(reported.first?.0.message, "2 張照片未儲存")
        XCTAssertEqual(reported.first?.1, 2)
    }

    /// Closing without a pending alert reports nothing.
    func test_621_4_closingWithoutFailuresReportsNothing() throws {
        var reported: [(CaptureAlertError, Int)] = []
        let (model, _, _, _) = try makeModel(reportFailureAfterClose: { reported.append(($0, $1)) })
        model.onDisappear()
        XCTAssertTrue(reported.isEmpty)
    }

    /// #636 review: a record write that fails (disk) is reported, not dropped.
    func test_621_3_failedRecordWriteIsReported() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)
        let saves = SaveRecorder()
        var writeFailures: [Error] = []
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record, save: saves.save,
                                             reportRecordWriteFailure: { writeFailures.append($0) })
        model.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { saves.calls.count == 1 }

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        saves.calls[0].completion(.success(outcome("L1", album: nil)))

        XCTAssertEqual(writeFailures.count, 1, "the failed write reaches the app")
        XCTAssertTrue(try storedRecord(record.id, in: store).fallbackAssetIDs.isEmpty, "rolled back")
        waitUntil { model.inFlightSaveCount == 0 }
    }

    /// 621-4: a permission failure offers the settings button.
    func test_621_4_permissionDeniedOffersTheSettingsAction() throws {
        let (model, _, _, _) = try makeModel(save: { _, _, _, completion in
            completion(.failure(.permissionDenied))
        })

        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))

        waitUntil { model.captureError != nil && model.inFlightSaveCount == 0 }
        XCTAssertEqual(model.captureError?.message, PhotoSaveError.permissionDenied.displayMessage)
        XCTAssertTrue(model.captureError?.showsSettingsAction ?? false)
    }

    /// A failed save does not touch the record.
    func testFailedSaveLeavesTheRecordUntouched() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store, albumIdentifier: "album-1")
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record, save: { _, _, _, completion in
            completion(.failure(.saveFailed("x")))
        })

        model.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { model.inFlightSaveCount == 0 && model.captureError != nil }

        let after = try storedRecord(record.id, in: store)
        XCTAssertEqual(after.albumIdentifier, "album-1")
        XCTAssertTrue(after.fallbackAssetIDs.isEmpty)
    }

    /// 621-4: a save that never calls back is given up on after the timeout:
    /// the photo is reported as failed (never saved), its place is freed.
    func test_621_4_saveTimeoutRaisesTheAlertAndFreesThePlace() throws {
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(save: saves.save, saveTimeout: 0.05)
        var announcements: [String] = []
        model.announce = { announcements.append($0) }

        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))
        XCTAssertEqual(model.inFlightSaveCount, 1)

        waitUntil { model.inFlightSaveCount == 0 }
        XCTAssertEqual(model.captureError?.message, "照片儲存逾時，這張可能沒有存進相簿。請再試一次。")
        XCTAssertEqual(model.captureFlights.first?.status, .failed, "621-4 failed, not saved")
        XCTAssertTrue(announcements.isEmpty, "621-4 nothing is announced as saved")
        XCTAssertFalse(model.isShutterBusy)
    }

    /// 621-4: the callback arriving after the timeout reports nothing again
    /// and the count never goes negative, but the photo that did reach the
    /// library is still recorded on the record.
    func test_621_4_lateSaveCallbackAfterTheTimeoutIsIgnoredButStillRecorded() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record,
                                             save: saves.save, saveTimeout: 0.05)
        var announcements: [String] = []
        model.announce = { announcements.append($0) }

        model.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { saves.calls.count == 1 }
        waitUntil { model.inFlightSaveCount == 0 }
        let errorAfterTimeout = model.captureError
        XCTAssertNotNil(errorAfterTimeout)
        XCTAssertNil(try storedRecord(record.id, in: store).albumIdentifier)

        saves.calls[0].completion(.success(outcome("late-asset", album: "album-9")))

        XCTAssertEqual(model.inFlightSaveCount, 0, "621-4 never negative")
        XCTAssertEqual(model.captureFlights.first?.status, .failed, "621-4 still failed")
        XCTAssertEqual(model.captureError, errorAfterTimeout, "621-4 not reported twice")
        XCTAssertTrue(announcements.isEmpty)
        XCTAssertEqual(try storedRecord(record.id, in: store).albumIdentifier, "album-9", "621-4 still recorded")

        // A photo saved normally later is counted on its own.
        model.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { saves.calls.count == 2 }
        XCTAssertEqual(model.inFlightSaveCount, 1)
        saves.calls[1].completion(.success(outcome("asset-2", album: "album-9")))
        XCTAssertEqual(model.inFlightSaveCount, 0)
    }

    /// A save answered in time is not touched by its (cancelled) timeout.
    func testSaveAnsweredInTimeIsNotReportedAsTimedOut() throws {
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(save: saves.save, saveTimeout: 0.2)

        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))
        waitUntil { saves.calls.count == 1 }
        saves.calls[0].completion(.success(outcome()))

        let timeoutWindow = expectation(description: "timeout window passes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { timeoutWindow.fulfill() }
        wait(for: [timeoutWindow], timeout: 2)

        XCTAssertEqual(model.captureFlights.first?.status, .saved)
        XCTAssertNil(model.captureError)
        XCTAssertEqual(model.inFlightSaveCount, 0)
    }

    /// Two failed photos before the alert is dismissed read as a count; after
    /// dismissing, a new failure shows its own message again.
    func testTwoFailuresAreCountedInOneAlert() throws {
        let (model, captures, saves) = try makePipelineModel()

        for index in 0..<2 {
            takePhoto(model, captures, at: index)
            waitUntil { model.captureFlights.count == index + 1 }
        }
        waitUntil { saves.calls.count == 1 }
        saves.calls[0].completion(.failure(.saveFailed("磁碟空間不足")))
        XCTAssertEqual(model.captureError?.message, "儲存失敗：磁碟空間不足。請確認裝置儲存空間後再試一次。")
        waitUntil { saves.calls.count == 2 }
        saves.calls[1].completion(.failure(.permissionDenied))

        XCTAssertEqual(model.captureError?.message, "2 張照片未儲存")
        XCTAssertEqual(model.captureError?.showsSettingsAction, true, "the settings button is kept if any failure needs it")

        model.dismissCaptureError()
        takePhoto(model, captures, at: 2)
        waitUntil { saves.calls.count == 3 }
        saves.calls[2].completion(.failure(.saveFailed("磁碟空間不足")))
        XCTAssertEqual(model.captureError?.message, "儲存失敗：磁碟空間不足。請確認裝置儲存空間後再試一次。")
    }

    /// A camera-level failure frees the shutter and leaves nothing in flight.
    func testCameraFailureLeavesNothingInFlight() throws {
        let (model, captures, _) = try makePipelineModel()

        model.beginCapture()
        captures.completions[0](.failure(.failed("x")))

        XCTAssertFalse(model.isShutterBusy, "129.5 the shutter never stays stuck")
        XCTAssertEqual(model.inFlightSaveCount, 0)
    }

    /// The save count goes 1 → 0 when the save calls back, whichever way.
    func testProcessCapturedImageDropsTheInFlightCountWhenSaveCompletes() throws {
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(save: saves.save)

        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))
        XCTAssertEqual(model.inFlightSaveCount, 1) // counted synchronously, before backgrounding

        waitUntil { saves.calls.count == 1 }
        XCTAssertEqual(model.inFlightSaveCount, 1, "not answered yet")

        saves.calls[0].completion(.success(outcome()))

        waitUntil { model.inFlightSaveCount == 0 }
    }

    // MARK: - 621-5 concurrency limit

    private func makePipelineModel(saveTimeout: TimeInterval = 30) throws
        -> (CameraScreenModel, CaptureRecorder, SaveRecorder) {
        let captures = CaptureRecorder()
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(save: saves.save, captureImage: captures.capture,
                                             saveTimeout: saveTimeout)
        return (model, captures, saves)
    }

    /// Fires the shutter and hands the camera's photo back.
    private func takePhoto(_ model: CameraScreenModel, _ captures: CaptureRecorder, at index: Int) {
        model.beginCapture()
        captures.completions[index](.success(UIImage()))
    }

    /// 621-5: the shutter is free again as soon as the camera hands the photo
    /// back, even while the first photo is still being saved, and the second
    /// photo's result never lands on the first one's flight.
    func test_621_5_shutterIsFreeWhileTheFirstPhotoIsStillSaving() throws {
        let (model, captures, saves) = try makePipelineModel()

        model.beginCapture()
        XCTAssertTrue(model.isShutterBusy, "621-5 busy while the camera is capturing")
        captures.completions[0](.success(UIImage()))
        waitUntil { saves.calls.count == 1 }
        XCTAssertFalse(model.isCapturing)
        XCTAssertEqual(model.inFlightSaveCount, 1)
        XCTAssertFalse(model.isShutterBusy, "621-5 the shutter can be pressed again")

        takePhoto(model, captures, at: 1)
        waitUntil { model.captureFlights.count == 2 }
        let ids = model.captureFlights.map(\.id)
        XCTAssertEqual(saves.calls.count, 1, "the second save waits for the first")

        saves.calls[0].completion(.success(outcome("asset-1")))
        XCTAssertEqual(model.captureFlights.first { $0.id == ids[0] }?.status, .saved)
        XCTAssertEqual(model.captureFlights.first { $0.id == ids[1] }?.status, .saving, "621-5 second untouched")
        XCTAssertEqual(saves.calls.count, 2)
        saves.calls[1].completion(.success(outcome("asset-2")))
        XCTAssertEqual(model.captureFlights.first { $0.id == ids[1] }?.status, .saved)
    }

    /// 621-5: two photos in flight keep the shutter disabled; either one
    /// finishing frees it.
    func test_621_5_shutterIsDisabledWithTwoInFlightAndFreedWhenOneFinishes() throws {
        let (model, captures, saves) = try makePipelineModel()

        for index in 0..<2 {
            takePhoto(model, captures, at: index)
            waitUntil { model.captureFlights.count == index + 1 }
        }
        XCTAssertEqual(model.inFlightSaveCount, 2)
        XCTAssertEqual(CameraScreenModel.maxInFlightSaves, 2)
        XCTAssertTrue(model.isShutterBusy, "621-5 at the limit")

        waitUntil { saves.calls.count == 1 }
        saves.calls[0].completion(.success(outcome("asset-1")))
        XCTAssertEqual(model.inFlightSaveCount, 1)
        XCTAssertFalse(model.isShutterBusy, "621-5 freed")

        takePhoto(model, captures, at: 2)
        waitUntil { model.captureFlights.count == 2 }
        XCTAssertTrue(model.isShutterBusy, "621-5 full again")
        waitUntil { saves.calls.count == 2 }
        saves.calls[1].completion(.failure(.saveFailed("x")))
        XCTAssertFalse(model.isShutterBusy, "621-5 a failure frees it too")
    }

    /// 621-5 (#636 review): a camera opened while the previous one's photos
    /// are still saving shares their count, so closing and reopening never
    /// passes the limit.
    func test_621_5_reopenedCameraSharesTheInFlightLimit() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store, albumIdentifier: "album-1")
        let coordinator = CaptureSaveCoordinator()
        let saves = SaveRecorder()
        let (first, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record,
                                             saveCoordinator: coordinator, save: saves.save)
        first.processCapturedImage(UIImage(), destination: destination(of: record))
        first.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { first.captureFlights.count == 2 && saves.calls.count == 1 }
        first.onDisappear()

        let (second, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record,
                                              saveCoordinator: coordinator, save: saves.save)
        XCTAssertEqual(second.inFlightSaveCount, 2, "the closed camera's photos still count")
        XCTAssertTrue(second.isShutterBusy, "621-5 the new camera starts at the limit")
        XCTAssertTrue(second.isShutterDisabled)

        saves.calls[0].completion(.success(outcome("A", album: "album-1")))
        XCTAssertEqual(second.inFlightSaveCount, 1)
        XCTAssertFalse(second.isShutterBusy, "one answered frees one place")

        second.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { second.captureFlights.count == 1 }
        XCTAssertEqual(coordinator.inFlightCount, 2)
        XCTAssertTrue(second.isShutterBusy, "never more than two across cameras")

        waitUntil { saves.calls.count == 2 }
        saves.calls[1].completion(.success(outcome("B", album: "album-1")))
        waitUntil { saves.calls.count == 3 }
        saves.calls[2].completion(.success(outcome("C", album: "album-1")))
        waitUntil { coordinator.inFlightCount == 0 }
        XCTAssertEqual(coordinator.inFlightCount, 0)
    }

    /// 621-2 (#636 review): a record without an album gets one album even
    /// when two camera models save for it: the second waits for the first
    /// and saves into the album it created.
    func test_621_2_twoCamerasCreateOneAlbumForARecordWithoutOne() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)
        let coordinator = CaptureSaveCoordinator()
        let saves = SaveRecorder()
        let (first, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record,
                                             saveCoordinator: coordinator, save: saves.save)
        first.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { saves.calls.count == 1 }
        first.onDisappear()

        let (second, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record,
                                              saveCoordinator: coordinator, save: saves.save)
        second.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { second.captureFlights.count == 1 }
        XCTAssertEqual(saves.calls.count, 1, "the second camera's save waits for the first")
        XCTAssertNil(saves.calls[0].albumIdentifier)

        saves.calls[0].completion(.success(outcome("A", album: "album-1")))
        waitUntil { saves.calls.count == 2 }
        XCTAssertEqual(saves.calls[1].albumIdentifier, "album-1", "saved into the album the first created")
        saves.calls[1].completion(.success(outcome("B", album: "album-1")))

        let stored = try storedRecord(record.id, in: store)
        XCTAssertEqual(stored.albumIdentifier, "album-1")
        XCTAssertTrue(stored.fallbackAssetIDs.isEmpty, "no second album, nothing to fall back on")
        waitUntil { coordinator.inFlightCount == 0 }
    }

    /// 621-5: a failed first save and a successful second one each land on
    /// their own photo.
    func test_621_5_eachPhotoReportsItsOwnSaveResult() throws {
        let (model, captures, saves) = try makePipelineModel()
        var announcements: [String] = []
        model.announce = { announcements.append($0) }

        for index in 0..<2 {
            takePhoto(model, captures, at: index)
            waitUntil { model.captureFlights.count == index + 1 }
        }
        let ids = model.captureFlights.map(\.id)

        waitUntil { saves.calls.count == 1 }
        saves.calls[0].completion(.failure(.saveFailed("磁碟空間不足")))
        XCTAssertEqual(saves.calls.count, 2)
        saves.calls[1].completion(.success(outcome("asset-2")))

        XCTAssertEqual(model.captureFlights.first { $0.id == ids[0] }?.status, .failed, "621-5 first failed")
        XCTAssertEqual(model.captureFlights.first { $0.id == ids[1] }?.status, .saved, "621-5 second saved")
        XCTAssertNotNil(model.captureError, "621-5 the failure is reported")
        XCTAssertEqual(announcements, ["已儲存"], "621-5 only the successful photo is announced as saved")
        XCTAssertEqual(model.inFlightSaveCount, 0)
    }

    /// A save that times out hands the queue to the next photo.
    func testTimedOutSaveLetsTheNextPhotoSave() throws {
        let (model, captures, saves) = try makePipelineModel(saveTimeout: 0.05)

        for index in 0..<2 {
            takePhoto(model, captures, at: index)
            waitUntil { model.captureFlights.count == index + 1 }
        }
        waitUntil { saves.calls.count == 2 }
        waitUntil { model.inFlightSaveCount == 0 }

        XCTAssertEqual(model.captureFlights.map(\.status), [.failed, .failed])
        XCTAssertEqual(model.captureError?.message, "2 張照片未儲存")
    }

    // MARK: - The camera closing while saving

    /// A photo still saving when the camera closes (the model is released) is
    /// still saved, and its album is still written back to the record.
    func testSaveStillRecordsWhenTheModelIsReleasedBeforeItAnswers() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)
        let saves = SaveRecorder()
        var made: (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore)? =
            try makeModel(clock: clock, profileStore: store, record: record, save: saves.save)

        made?.0.processCapturedImage(UIImage(), destination: destination(of: record))
        waitUntil { saves.calls.count == 1 }
        made?.0.onDisappear()
        made = nil // the camera closed

        saves.calls[0].completion(.success(outcome("A", album: "album-1")))

        XCTAssertEqual(try storedRecord(record.id, in: store).albumIdentifier, "album-1")
    }

    /// #636 review: the camera closes (the model is released) between the
    /// shutter and the photo coming back; the photo is still saved and
    /// written back to the record.
    func testPhotoArrivingAfterTheModelIsReleasedIsStillSaved() throws {
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)
        let saves = SaveRecorder()
        let captures = CaptureRecorder()
        var made: (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore)? =
            try makeModel(clock: clock, profileStore: store, record: record, save: saves.save,
                          captureImage: captures.capture)

        made?.0.beginCapture()
        XCTAssertEqual(captures.completions.count, 1, "the shutter fired")
        made?.0.onDisappear()
        made = nil // the camera closed before the photo came back

        captures.completions[0](.success(UIImage()))
        waitUntil { saves.calls.count == 1 }
        XCTAssertEqual(saves.calls.count, 1, "the photo still reaches the save")
        saves.calls[0].completion(.success(outcome("A", album: "album-1")))

        XCTAssertEqual(try storedRecord(record.id, in: store).albumIdentifier, "album-1")
    }

    /// #636 review: same, and the save fails: the failure reaches the app.
    func testPhotoArrivingAfterTheModelIsReleasedReportsItsSaveFailure() throws {
        let saves = SaveRecorder()
        let captures = CaptureRecorder()
        var reported: [(CaptureAlertError, Int)] = []
        var made: (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore)? =
            try makeModel(save: saves.save, captureImage: captures.capture,
                          reportFailureAfterClose: { reported.append(($0, $1)) })
        let coordinator = try XCTUnwrap(made?.0.saveCoordinator)

        made?.0.beginCapture()
        made?.0.onDisappear()
        made = nil

        captures.completions[0](.success(UIImage()))
        waitUntil { saves.calls.count == 1 }
        saves.calls[0].completion(.failure(.saveFailed("磁碟空間不足")))

        XCTAssertEqual(reported.count, 1, "the failure reaches the 紀錄 list")
        XCTAssertEqual(coordinator.inFlightCount, 0)
    }

    /// 639-1: the shutter fires, the camera closes before the photo comes
    /// back, and `stop()` answers the capture with `.notRunning`: the 紀錄
    /// list is told the photo was not taken, nothing counts as saved.
    func test_639_1_closingRightAfterTheShutterReportsThePhotoNotTaken() throws {
        let saves = SaveRecorder()
        let captures = CaptureRecorder()
        var reported: [(CaptureAlertError, Int)] = []
        var made: (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore)? =
            try makeModel(save: saves.save, captureImage: captures.capture,
                          reportFailureAfterClose: { reported.append(($0, $1)) })
        let coordinator = try XCTUnwrap(made?.0.saveCoordinator)

        made?.0.beginCapture()
        XCTAssertEqual(captures.completions.count, 1, "the shutter fired")
        made?.0.onDisappear()
        made = nil // the camera's view dropped the model

        captures.completions[0](.failure(.notRunning))

        XCTAssertEqual(reported.count, 1, "the lost photo reaches the 紀錄 list")
        XCTAssertEqual(reported.first?.0.message, CameraScreenModel.captureFailureMessage(.notRunning))
        XCTAssertEqual(reported.first?.1, 1)
        XCTAssertTrue(saves.calls.isEmpty, "nothing is saved or reported as saved")
        XCTAssertEqual(coordinator.inFlightCount, 0)
    }

    /// 639-1, the other outcome: the photo comes back after the camera
    /// closed; it is saved and nothing is reported as failed.
    func test_639_1_closingRightAfterTheShutterStillSavesAPhotoThatArrives() throws {
        let saves = SaveRecorder()
        let captures = CaptureRecorder()
        var reported: [(CaptureAlertError, Int)] = []
        let (model, _, _, _) = try makeModel(save: saves.save, captureImage: captures.capture,
                                             reportFailureAfterClose: { reported.append(($0, $1)) })

        model.beginCapture()
        model.onDisappear()
        captures.completions[0](.success(UIImage()))
        waitUntil { saves.calls.count == 1 }
        saves.calls[0].completion(.success(outcome()))

        XCTAssertTrue(reported.isEmpty)
        XCTAssertEqual(model.inFlightSaveCount, 0)
    }

    /// A capture-level failure while the camera is open raises the alert
    /// instead of leaving a flash with no photo (#639).
    func testCaptureFailureWhileOpenRaisesTheAlert() throws {
        let (model, captures, _) = try makePipelineModel()

        model.beginCapture()
        captures.completions[0](.failure(.noImageData))

        XCTAssertEqual(model.captureError?.message, CameraScreenModel.captureFailureMessage(.noImageData))
        XCTAssertFalse(model.isShutterBusy)
    }

    /// Closing the camera does not cancel a save in progress.
    func testOnDisappearKeepsASaveInProgress() throws {
        let saves = SaveRecorder()
        let (model, _, _, _) = try makeModel(save: saves.save)
        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))
        waitUntil { saves.calls.count == 1 }

        model.onDisappear()
        XCTAssertEqual(model.inFlightSaveCount, 1)
        saves.calls[0].completion(.success(outcome()))

        XCTAssertEqual(model.inFlightSaveCount, 0)
        XCTAssertNil(model.captureError)
    }

    // MARK: - Camera tools (PRD 0.2 FR-7, TASK-21 acceptance 21.1–21.3)

    func testFlashToolIsDisabledWhenNoFlashIsAvailable() throws {
        // A back camera with no flash unit disables the button the same way
        // the front camera does (`EmptyDeviceProvider` cannot reach the front
        // camera in this harness).
        let (model, _, _, _) = try makeModel(flashCapabilityProvider: StubFlashCapabilityProvider(hasFlash: false))
        XCTAssertTrue(model.isFlashToolDisabled)
    }

    func testFlashToolIsNotDisabledWhenFlashIsAvailable() throws {
        let (model, _, _, _) = try makeModel(flashCapabilityProvider: StubFlashCapabilityProvider(hasFlash: true))
        XCTAssertFalse(model.isFlashToolDisabled)
    }

    func testActiveToolsReflectTheirCaptureSettings() throws {
        // 21.3: flash auto, timer 3s, grid on → all three `isActive`.
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleFlash() // .off -> .auto
        settings.cycleTimer() // .off -> .threeSeconds
        settings.toggleGrid() // false -> true
        let (model, _, _, _) = try makeModel(captureSettingsStore: settings)

        XCTAssertTrue(model.isFlashToolActive)
        XCTAssertTrue(model.isTimerToolActive)
        XCTAssertTrue(model.isGridToolActive)
    }

    func testToolsAreNotActiveAtTheirDefaults() throws {
        let (model, _, _, _) = try makeModel()
        XCTAssertFalse(model.isFlashToolActive)
        XCTAssertFalse(model.isTimerToolActive)
        XCTAssertFalse(model.isGridToolActive)
    }

    // MARK: - Latest photo (FR-20.5)

    func testLatestThumbnailIsNilBeforeAnyCapture() throws {
        let (model, _, _, _) = try makeModel()
        XCTAssertNil(model.latestThumbnailImage)
    }

    func testLoadLatestThumbnailShowsTheLoadedPhoto() async throws {
        let loaded = solidImage(.red)
        let (model, _, _, _) = try makeModel(loadLatestPhoto: { loaded })

        await model.loadLatestThumbnail()

        XCTAssertTrue(model.latestThumbnailImage === loaded)
    }

    func testLoadLatestThumbnailKeepsNilWhenTheRecordHasNoPhoto() async throws {
        let (model, _, _, _) = try makeModel(loadLatestPhoto: { nil })

        await model.loadLatestThumbnail()

        XCTAssertNil(model.latestThumbnailImage)
    }

    /// The read happens once per camera, however often the view asks.
    func testLoadLatestThumbnailReadsOnlyOnce() async throws {
        var readCount = 0
        let (model, _, _, _) = try makeModel(loadLatestPhoto: {
            readCount += 1
            return UIImage()
        })

        await model.loadLatestThumbnail()
        await model.loadLatestThumbnail()

        XCTAssertEqual(readCount, 1)
    }

    /// A photo that lands while the read is still running wins over it.
    func testPhotoLandingDuringTheLatestPhotoReadIsNotOverwritten() throws {
        let loader = GatedPhotoLoader(image: solidImage(.red))
        let (model, _, _, _) = try makeModel(loadLatestPhoto: { await loader.load() })
        let finished = expectation(description: "latest photo read finished")
        Task {
            await model.loadLatestThumbnail()
            finished.fulfill()
        }
        waitUntil { loader.isWaiting }

        model.processCapturedImage(UIImage(), destination: destination(of: try XCTUnwrap(model.profile)))
        waitUntil { model.captureFlights.count == 1 }
        model.flightDidLand(id: try XCTUnwrap(model.captureFlights.first?.id))
        let landed = try XCTUnwrap(model.latestThumbnailImage)

        loader.resume()
        wait(for: [finished], timeout: 3)

        XCTAssertTrue(model.latestThumbnailImage === landed)
    }

    // MARK: - Tools capsule is closed by the controls

    func testSwitchCameraAndShutterCollapseTheToolsCapsule() throws {
        let (model, _, _, _) = try makeModel()
        model.toggleCameraTools()
        model.switchCamera()
        XCTAssertFalse(model.isCameraToolsExpanded)

        model.toggleCameraTools()
        model.capturePhoto()
        XCTAssertFalse(model.isCameraToolsExpanded)
    }

    // MARK: - Timer countdown (PRD 0.2 FR-7.6, TASK-21 acceptance 19.8–19.10)

    func testCountdownTicksDownThenCapturesExactlyOnce() throws {
        // 19.8: 3-second timer, 3 injected ticks → countdownRemaining goes
        // 3, 2, 1, nil, and the real capture fires exactly once, after the
        // third tick (not before).
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleTimer() // .off -> .threeSeconds
        let ticker = FakeCountdownTicker()
        var captureCallCount = 0
        let (model, _, _, _) = try makeModel(captureSettingsStore: settings,
                                             countdownTicker: ticker,
                                             captureImage: { _, completion in
                                                 captureCallCount += 1
                                                 completion(.success(UIImage()))
                                             })

        model.beginCapture()
        XCTAssertEqual(model.countdownRemaining, 3)
        XCTAssertEqual(captureCallCount, 0)

        ticker.tick()
        XCTAssertEqual(model.countdownRemaining, 2)
        XCTAssertEqual(captureCallCount, 0)

        ticker.tick()
        XCTAssertEqual(model.countdownRemaining, 1)
        XCTAssertEqual(captureCallCount, 0)

        ticker.tick()
        XCTAssertNil(model.countdownRemaining)
        XCTAssertEqual(captureCallCount, 1)
    }

    func testCancellingMidCountdownStopsTheTickerAndCapturesNothing() throws {
        // 19.9: 10-second timer, 2 ticks, then the shutter is pressed again
        // → cancels: countdownRemaining nil, capture never fires, "已取消"
        // toast.
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleTimer() // .off -> .threeSeconds
        settings.cycleTimer() // .threeSeconds -> .tenSeconds
        let ticker = FakeCountdownTicker()
        var captureCallCount = 0
        let (model, _, _, _) = try makeModel(captureSettingsStore: settings,
                                             countdownTicker: ticker,
                                             captureImage: { _, completion in
                                                 captureCallCount += 1
                                                 completion(.success(UIImage()))
                                             })

        model.beginCapture()
        ticker.tick()
        ticker.tick()
        XCTAssertEqual(model.countdownRemaining, 8)

        // The cancel branch of `capturePhoto()` — unlike its start branch —
        // does not depend on `isShutterDisabled`, so it is reachable through
        // the public entry point even in this hardware-less test harness.
        model.capturePhoto()

        XCTAssertNil(model.countdownRemaining)
        XCTAssertEqual(captureCallCount, 0)
        XCTAssertEqual(ticker.stopCallCount, 1)
        XCTAssertEqual(model.toastState?.message, "已取消")
    }

    func testCountdownThatEndsAfterMidnightStillCapturesOnceAndTheHUDFollowsTheClock() throws {
        // 19.10: the countdown starts at 23:59:59 and ends the next day. The
        // photo carries no moment (FR-20.6); only the HUD reads the clock.
        let clock = MutableClock(try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 23, minute: 59, second: 59)))
        let store = makeProfileStore(clock: clock)
        let record = try addRecord(to: store)
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleTimer() // .off -> .threeSeconds
        let ticker = FakeCountdownTicker()
        var captureCallCount = 0
        let (model, _, _, _) = try makeModel(clock: clock, profileStore: store, record: record,
                                             captureSettingsStore: settings,
                                             countdownTicker: ticker,
                                             captureImage: { _, completion in
                                                 captureCallCount += 1
                                                 completion(.success(UIImage()))
                                             })
        XCTAssertEqual(model.dayHUDText, "第 10 天")

        model.beginCapture()
        clock.current = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 0, minute: 0, second: 2))
        ticker.tick()
        ticker.tick()
        ticker.tick()

        XCTAssertEqual(captureCallCount, 1)
        XCTAssertEqual(model.dayHUDText, "第 11 天")
    }

    // MARK: - SaveSlot

    /// Codex P2 on #532: a settled slot must not stay alive through its own
    /// timeout closure, or every photo would leak one.
    func testSettledSaveSlotIsReleased() {
        weak var weakSlot: CameraScreenModel.SaveSlot?
        autoreleasepool {
            let slot = CameraScreenModel.SaveSlot()
            weakSlot = slot
            slot.timeout = DispatchWorkItem { _ = slot.isSettled }
            slot.settle()
            XCTAssertTrue(slot.isSettled)
            XCTAssertNil(slot.timeout, "the cycle is broken")
        }
        XCTAssertNil(weakSlot, "the slot is freed once settled")
    }

    // MARK: - viewfinderRotation (#572)

    private func makeRotationModel(override: CGFloat?) throws -> (CameraScreenModel, CameraService) {
        let service = CameraService(isCaptureSupported: false)
        let clock = MutableClock(try fixedNow())
        let store = makeProfileStore(clock: clock)
        let model = CameraScreenModel(
            cameraService: service,
            profileStore: store,
            profileID: try XCTUnwrap(store.profiles.first?.id),
            captureSettingsStore: CaptureSettingsStore(defaults: defaults),
            captureRotationAngleOverride: override)
        return (model, service)
    }

    /// #572-4: without a camera the service stays at 90, which is portrait.
    func testViewfinderRotationIsPortraitWithoutACamera() throws {
        let (model, _) = try makeRotationModel(override: nil)
        XCTAssertEqual(model.viewfinderRotation, .portrait)
    }

    /// #572-4: the override fixes the rotation from the start.
    func testViewfinderRotationUsesTheOverride() throws {
        XCTAssertEqual(try makeRotationModel(override: 0).0.viewfinderRotation, .landscapeTopLeft)
        XCTAssertEqual(try makeRotationModel(override: 180).0.viewfinderRotation, .landscapeTopRight)
        XCTAssertEqual(try makeRotationModel(override: 270).0.viewfinderRotation, .upsideDown)
    }

    /// #572-4: with no override the rotation follows the service's angle.
    func testViewfinderRotationFollowsTheServiceAngle() throws {
        let (model, service) = try makeRotationModel(override: nil)
        service.publish(viewfinderRotationAngle: 0)
        waitUntil { model.viewfinderRotation == .landscapeTopLeft }
        service.publish(viewfinderRotationAngle: 90)
        waitUntil { model.viewfinderRotation == .portrait }
    }

    /// #572-4: the override wins over later service changes.
    func testOverrideWinsOverTheService() throws {
        let (model, service) = try makeRotationModel(override: 0)
        service.publish(viewfinderRotationAngle: 180)
        let settled = expectation(description: "main queue drains")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(model.viewfinderRotation, .landscapeTopLeft)
    }
}
