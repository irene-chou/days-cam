import AVFoundation
import Combine
import UIKit
import XCTest
@testable import DaysCam

/// Covers `CameraScreenModel`: how it turns `CameraService`'s published state
/// into what the viewfinder should show (placeholder, shutter-disabled,
/// transient status message), that it forwards its lifecycle/action calls to
/// the service (TASK-07), and how it turns the selected `CameraProfile` into
/// overlay text/theme/position via `TemplateRenderer` (TASK-08).
///
/// Like `CameraServiceTests`, every test stubs `CameraAuthorizing` and
/// `CaptureDeviceProviding` so nothing here touches real hardware or a real
/// permission prompt. A `CaptureDeviceProviding` that hands back a real
/// device is impossible on the simulator, so — matching `CameraServiceTests`'
/// own documented boundary — the fully-`.running` shutter-enabled state is a
/// B-level (device) acceptance item, not covered here.
///
/// The profile side uses a real `ProfileStore` backed by a temporary
/// directory and an isolated `UserDefaults` suite, same as
/// `ProfileListModelProfileStoreAdapterTests`.
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

    // MARK: - Helpers

    private func fixedNow() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
    }

    private func makeProfileStore(now: Date, seed: [CameraProfile] = []) -> ProfileStore {
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults)
        if seed.isEmpty {
            store.load() // seeds the one default profile
        } else {
            for profile in seed {
                _ = try? store.add(profile)
            }
        }
        return store
    }

    private func makeModel(status: AVAuthorizationStatus = .notDetermined,
                           captureSupported: Bool = false,
                           profileStore: ProfileStore? = nil,
                           now: Date = Date(),
                           flashCapabilityProvider: FlashCapabilityProviding? = nil,
                           captureSettingsStore: CaptureSettingsStore? = nil,
                           countdownTicker: CountdownTicker = SystemCountdownTicker(),
                           crop: @escaping (UIImage, CaptureAspectRatio) -> UIImage = { image, _ in image },
                           bake: @escaping (UIImage, String, OverlayStyle, OverlayPlacement) -> UIImage? = { _, _, _, _ in UIImage() },
                           save: @escaping (UIImage, @escaping (Result<String, PhotoSaveError>) -> Void) -> Void = { _, completion in completion(.success("asset-1")) },
                           captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil,
                           scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { _ in }) -> (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore) {
        makeModel(status: status,
                 captureSupported: captureSupported,
                 profileStore: profileStore,
                 nowProvider: { now },
                 flashCapabilityProvider: flashCapabilityProvider,
                 captureSettingsStore: captureSettingsStore,
                 countdownTicker: countdownTicker,
                 crop: crop,
                 bake: bake,
                 save: save,
                 captureImage: captureImage,
                 scheduleToastDismiss: scheduleToastDismiss)
    }

    /// Like `makeModel(...)`, but takes a clock closure rather than a fixed
    /// `Date` — for tests that need to move time *after* construction to
    /// prove a value is recomputed rather than cached (see `MutableClock`).
    ///
    /// `scheduleToastDismiss` defaults to never firing, so a toast a test
    /// presents stays put until the test inspects it; tests that care about
    /// the dismiss itself (or the ordering between two scheduled dismissals)
    /// pass their own `SchedulerSpy` and invoke it explicitly.
    ///
    /// `captureSettingsStore` defaults to a fresh store backed by this test's
    /// own isolated `defaults` suite (not `.standard`) — otherwise the
    /// persisted `captureAspectRatio`/`showsGrid` fields would leak between
    /// test runs the way `ProfileStore`'s own isolation already prevents for
    /// profiles. `capturedPhotoStore` similarly gets its own subdirectory of
    /// this test's temporary `directory`, so `recordCapturedAsset` never
    /// touches the real `Application Support/DaysCam/photos.json`.
    private func makeModel(status: AVAuthorizationStatus = .notDetermined,
                           captureSupported: Bool = false,
                           profileStore: ProfileStore? = nil,
                           nowProvider: @escaping () -> Date,
                           flashCapabilityProvider: FlashCapabilityProviding? = nil,
                           captureSettingsStore: CaptureSettingsStore? = nil,
                           countdownTicker: CountdownTicker = SystemCountdownTicker(),
                           crop: @escaping (UIImage, CaptureAspectRatio) -> UIImage = { image, _ in image },
                           bake: @escaping (UIImage, String, OverlayStyle, OverlayPlacement) -> UIImage? = { _, _, _, _ in UIImage() },
                           save: @escaping (UIImage, @escaping (Result<String, PhotoSaveError>) -> Void) -> Void = { _, completion in completion(.success("asset-1")) },
                           captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil,
                           scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { _ in }) -> (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore) {
        let authorizer = StubAuthorizer(status: status)
        let provider = EmptyDeviceProvider()
        let service = CameraService(authorizer: authorizer,
                                    deviceProvider: provider,
                                    flashCapabilityProvider: flashCapabilityProvider,
                                    isCaptureSupported: captureSupported)
        let store = profileStore ?? makeProfileStore(now: nowProvider())
        let resolvedCaptureSettingsStore = captureSettingsStore ?? CaptureSettingsStore(defaults: defaults)
        let capturedPhotoStore = CapturedPhotoStore(directory: directory.appendingPathComponent("captured-photos", isDirectory: true))
        let model = CameraScreenModel(cameraService: service,
                                      profileStore: store,
                                      captureSettingsStore: resolvedCaptureSettingsStore,
                                      capturedPhotoStore: capturedPhotoStore,
                                      calendar: DateFixture.taipei,
                                      calculator: DayCountCalculator(calendar: DateFixture.taipei, now: nowProvider),
                                      crop: crop,
                                      countdownTicker: countdownTicker,
                                      bake: bake,
                                      save: save,
                                      captureImage: captureImage,
                                      scheduleToastDismiss: scheduleToastDismiss)
        return (model, service, provider, store)
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
    /// prove a value is recomputed live rather than cached at `init` time —
    /// two separately-constructed models each with their own *fixed* clock
    /// cannot tell those apart (code review finding).
    private final class MutableClock {
        var current: Date
        init(_ date: Date) { current = date }
        func now() -> Date { current }
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

    // MARK: - showsPlaceholder / isCaptureUnsupported
    //
    // Code review finding: the original `isShutterDisabled` tests below this
    // point each asserted the *composite* while only ever driving one
    // sub-condition — deleting any single clause from the real
    // implementation would still leave these green, because `status` can
    // never reach `.running` without a real capture device (same limitation
    // `CameraServiceTests` documents), so `isSessionNotRunning` is
    // unconditionally true everywhere in this test target regardless of what
    // else is true. Testing each sub-property (`isCaptureUnsupported`,
    // `needsPermissionGuidance`, `isSessionNotRunning`) directly, rather than
    // only through the OR'd composite, is what actually catches a broken
    // individual condition.

    func testIsCaptureUnsupportedTrueWhenCaptureNotSupported() {
        let (model, _, _, _) = makeModel(captureSupported: false)
        XCTAssertTrue(model.isCaptureUnsupported)
        XCTAssertTrue(model.showsPlaceholder)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testIsCaptureUnsupportedFalseWhenCaptureSupported() {
        let (model, _, _, _) = makeModel(captureSupported: true)
        XCTAssertFalse(model.isCaptureUnsupported)
        XCTAssertFalse(model.showsPlaceholder)
    }

    // MARK: - needsPermissionGuidance

    func testNeedsPermissionGuidanceTrueWhenDenied() {
        let (model, service, _, _) = makeModel(status: .denied, captureSupported: true)
        model.onAppear()
        waitUntil { service.permission == .denied }
        XCTAssertTrue(model.needsPermissionGuidance)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testNeedsPermissionGuidanceTrueWhenRestricted() {
        let (model, service, _, _) = makeModel(status: .restricted, captureSupported: true)
        model.onAppear()
        waitUntil { service.permission == .restricted }
        XCTAssertTrue(model.needsPermissionGuidance)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testNeedsPermissionGuidanceFalseWhenAuthorized() {
        let (model, service, _, _) = makeModel(status: .authorized, captureSupported: false)
        model.onAppear()
        waitUntil { service.permission == .authorized }
        XCTAssertFalse(model.needsPermissionGuidance)
    }

    // MARK: - isSessionNotRunning

    func testIsSessionNotRunningTrueBeforeOnAppear() {
        let (model, _, _, _) = makeModel(captureSupported: true)
        XCTAssertTrue(model.isSessionNotRunning)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testIsSessionNotRunningTrueForSimulatorPlaceholderStatus() {
        // Documents the actual boundary explained above: `.unavailable(.simulator)`
        // is as close to "not idle" as this test target can reach, and it is
        // still not `.running`.
        let (model, service, _, _) = makeModel(status: .authorized, captureSupported: false)
        model.onAppear()
        waitUntil { service.status == .unavailable(.simulator) }
        XCTAssertTrue(model.isSessionNotRunning)
    }

    // MARK: - statusMessage

    func testStatusMessageNilWhenIdle() {
        let (model, _, _, _) = makeModel(captureSupported: true)
        XCTAssertNil(model.statusMessage)
    }

    func testStatusMessageNilForSimulatorPlaceholder() {
        // The simulator gets its own placeholder + label; the generic
        // "相機暫時無法使用" message would be redundant on top of it.
        let (model, service, _, _) = makeModel(status: .authorized, captureSupported: false)
        model.onAppear()
        waitUntil { service.status == .unavailable(.simulator) }
        XCTAssertNil(model.statusMessage)
    }

    func testStatusMessageForNoCaptureDevice() {
        // `EmptyDeviceProvider` always hands back nil, so an authorized,
        // capture-supported session still fails to configure.
        let (model, service, _, _) = makeModel(status: .authorized, captureSupported: true)
        model.onAppear()
        waitUntil { service.status == .unavailable(.noCaptureDevice) }
        XCTAssertEqual(model.statusMessage, "相機暫時無法使用")
    }

    func testStatusMessageForInterruption() {
        let (model, service, _, _) = makeModel(captureSupported: true)
        NotificationCenter.default.post(name: AVCaptureSession.wasInterruptedNotification, object: service.session)
        waitUntil { service.status == .interrupted }
        XCTAssertEqual(model.statusMessage, "相機暫時無法使用")
    }

    // MARK: - CameraService change forwarding (Critical, code review finding)

    func testModelPublishesWhenCameraServicePermissionChanges() {
        // `cameraService` is a nested `ObservableObject` this model reads
        // directly (`permission`, `status`) but `CameraScreen` only
        // `@ObservedObject`s this model, not `cameraService` itself — without
        // forwarding `cameraService.objectWillChange`, SwiftUI never learns a
        // permission grant/denial or a status change happened, so the
        // guidance screen would never appear/disappear and the shutter could
        // stay disabled forever once `.running` is reached on a device.
        let (model, service, _, _) = makeModel(status: .authorized, captureSupported: false)
        var fired = false
        let cancellable = model.objectWillChange.sink { fired = true }
        defer { cancellable.cancel() }

        model.onAppear()
        waitUntil { service.permission == .authorized }

        XCTAssertTrue(fired)
    }

    // MARK: - Lifecycle forwarding

    func testOnAppearStartsTheService() {
        let (model, service, _, _) = makeModel(status: .authorized, captureSupported: false)
        XCTAssertEqual(service.permission, .notDetermined)
        model.onAppear()
        waitUntil { service.permission == .authorized }
    }

    func testOnDisappearStopsTheService() {
        let (model, service, _, _) = makeModel(status: .authorized, captureSupported: false)
        model.onAppear()
        waitUntil { service.status == .unavailable(.simulator) }
        model.onDisappear()
        waitUntil { service.status == .idle }
    }

    // MARK: - switchCamera forwarding

    func testSwitchCameraNoOpsWhenCaptureNotSupported() {
        let (model, _, provider, _) = makeModel(captureSupported: false)
        model.switchCamera()
        // The guard in `CameraService.switchCamera()` returns before ever
        // touching the session queue, so this is observable synchronously.
        XCTAssertTrue(provider.requestedFacings.isEmpty)
    }

    func testSwitchCameraForwardsToServiceWhenCaptureSupported() {
        let (model, _, provider, _) = makeModel(captureSupported: true)
        model.switchCamera()
        waitUntil { !provider.requestedFacings.isEmpty }
        XCTAssertEqual(provider.requestedFacings, [.front])
    }

    // MARK: - Profile-driven overlay (TASK-08)

    func testOverlayTextForFreshInstallIsDayOne() throws {
        // 8.1: a fresh install seeds one default profile with startDate ==
        // today, so the overlay reads "第 1 天" with no further setup.
        let now = try fixedNow() // 2026-01-10
        let (model, _, _, _) = makeModel(now: now)
        XCTAssertEqual(model.overlayText, "第 1 天")
    }

    func testOverlayTextIncrementsWithTheCaptureMomentNotTheSeedMoment() throws {
        // 8.2: re-rendering a day later must read "第 2 天", proving
        // `overlayText` is computed from the live capture moment on every
        // access rather than cached from when the profile was seeded
        // (PRD §6.4). One model with a *mutable* clock, not two separately
        // constructed models each with a fixed clock — two independent
        // models each reading a value fixed at construction cannot tell a
        // cached value apart from a correctly recomputed one; that would
        // pass even if `overlayText` snapshotted the text once in `init`
        // (code review finding).
        let seedDay = try fixedNow() // 2026-01-10
        let clock = MutableClock(seedDay)
        let store = makeProfileStore(now: seedDay)
        let (model, _, _, _) = makeModel(profileStore: store, nowProvider: clock.now)
        XCTAssertEqual(model.overlayText, "第 1 天")

        clock.current = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 8))
        XCTAssertEqual(model.overlayText, "第 2 天")
    }

    func testOverlayTextShowsDateInsteadOfDayCountWhenConfiguredTo() throws {
        // 8.3: date-only display must never read "第 N 天" (PRD FR-2.17).
        let seedDay = try fixedNow() // 2026-01-10
        let store = makeProfileStore(now: seedDay)
        var dateOnly = try XCTUnwrap(store.profiles.first)
        dateOnly.showDayCount = false
        dateOnly.showDate = true
        try store.update(dateOnly)

        let nextDay = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 8))
        let (model, _, _, _) = makeModel(profileStore: store, now: nextDay)
        XCTAssertEqual(model.overlayText, "2026.01.11")
    }

    func testOverlayTextPrefixesTheNameWhenShowNameIsOn() throws {
        // 8.4/8.5: name on prepends "{name} ", name off leaves no stray space.
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        var withName = try XCTUnwrap(store.profiles.first) // name defaults to "預設"
        withName.showName = true
        try store.update(withName)

        let (shown, _, _, _) = makeModel(profileStore: store, now: now)
        XCTAssertEqual(shown.overlayText, "預設 第 1 天")

        withName.showName = false
        try store.update(withName)
        let (hidden, _, _, _) = makeModel(profileStore: store, now: now)
        XCTAssertEqual(hidden.overlayText, "第 1 天")
    }

    func testOverlayThemeAndPositionFollowTheSelectedProfileAndSwitchingDoesNotLeak() throws {
        // 8.13: each profile keeps its own position/theme; switching between
        // them must not overwrite the other's.
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let defaultProfile = try XCTUnwrap(store.profiles.first)

        var second = CameraProfile(name: "小寶",
                                   startDate: DateFixture.components(2026, 1, 1),
                                   position: .anchor(.topLeading),
                                   style: OverlayStyle(legacyTheme: .retroOrange))
        second = try store.add(second) // FR-1.10: add also auto-selects it

        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        XCTAssertEqual(model.selectedProfileID, second.id)
        XCTAssertEqual(model.overlayPlacement, .anchor(.topLeading))
        XCTAssertEqual(model.overlayStyle, OverlayStyle(legacyTheme: .retroOrange))

        store.select(id: defaultProfile.id)
        // The mirroring sink is dispatched via `.receive(on: .main)`, so it
        // needs a main-queue pump before it is observable, same as
        // `ProfileListModelProfileStoreAdapterTests`.
        waitUntil { model.selectedProfileID == defaultProfile.id }
        XCTAssertEqual(model.overlayPlacement, .anchor(.bottomTrailing))
        XCTAssertEqual(model.overlayStyle, OverlayStyle())
    }

    func testProfilesAndSelectionMirrorTheStoreAfterConstruction() throws {
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        let expectation = expectation(description: "profiles mirrored")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(model.profiles.map(\.name), ["預設", "小寶"])
        XCTAssertEqual(model.selectedProfileID, store.selectedProfileID)
    }

    // MARK: - Display settings sheet (TASK-11)

    func testPresentDisplaySettingsBuildsAModelForTheSelectedProfile() throws {
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        XCTAssertFalse(model.isDisplaySettingsPresented)

        model.presentDisplaySettings()

        XCTAssertTrue(model.isDisplaySettingsPresented)
        XCTAssertEqual(model.displaySettingsModel?.profile.id, model.selectedProfileID)
    }

    func testDismissDisplaySettingsClearsTheModel() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now)
        model.presentDisplaySettings()
        XCTAssertTrue(model.isDisplaySettingsPresented)

        model.dismissDisplaySettings()

        XCTAssertFalse(model.isDisplaySettingsPresented)
        XCTAssertNil(model.displaySettingsModel)
    }

    func testDisplaySettingsChangesWriteThroughToTheProfileStore() throws {
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        model.presentDisplaySettings()
        let sheetModel = try XCTUnwrap(model.displaySettingsModel)

        sheetModel.setShowName(true)

        XCTAssertTrue(store.profiles.first?.showName ?? false)
        // `model.profiles` mirrors the store via a `.receive(on: .main)` sink,
        // so it needs a pump before the viewfinder's own overlay reflects the
        // change — same as the other mirroring tests above.
        waitUntil { model.selectedProfile?.showName == true }
        XCTAssertTrue(model.overlayText.hasPrefix("預設"))
    }

    func testPresentDisplaySettingsIsANoOpWithoutASelectedProfile() throws {
        // Defensive backstop: `selectedProfile` should never actually be nil
        // once the app has launched (FR-1.8 guarantees a non-empty list), but
        // the guard exists so this can never force-unwrap.
        let now = try fixedNow()
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults)
        // Deliberately never call `store.load()`, so `profiles` stays empty
        // and `selectedProfileID` stays nil.
        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        model.presentDisplaySettings()

        XCTAssertFalse(model.isDisplaySettingsPresented)
    }

    // MARK: - Profile switcher (TASK-13)

    func testCurrentProfileNameReflectsTheSelectedProfile() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now)
        XCTAssertEqual(model.currentProfileName, "預設")
    }

    func testSelectProfileForwardsToTheStoreAndUpdatesTheOverlay() throws {
        // 13.4/13.5: switching must reach the store (so `lastUsedProfileID`
        // persists, FR-1.5) and the viewfinder's overlay must follow.
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let second = try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        let defaultProfile = try XCTUnwrap(store.profiles.first { $0.id != second.id })

        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        XCTAssertEqual(model.selectedProfileID, second.id) // FR-1.10 auto-select on add

        model.selectProfile(id: defaultProfile.id)

        XCTAssertEqual(store.selectedProfileID, defaultProfile.id)
        XCTAssertEqual(store.lastUsedProfileID, defaultProfile.id)
        waitUntil { model.currentProfileName == "預設" }
        // Default profile was seeded with startDate == `now` itself, so under
        // `.dayOne` this is day 1.
        XCTAssertEqual(model.overlayText, "第 1 天")
    }

    func testPresentProfileManagementShowsTheList() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now)
        XCTAssertFalse(model.isProfileListPresented)

        model.presentProfileManagement()

        XCTAssertTrue(model.isProfileListPresented)
    }

    func testProfileListModelSharesTheSameStoreAsTheScreen() throws {
        // The management list and the switcher must never fall out of sync —
        // both are views onto the same `ProfileStore`.
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        XCTAssertEqual(model.profileListModel.profiles.map(\.id), store.profiles.map(\.id))

        try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        waitUntil { model.profileListModel.profiles.count == 2 }
        XCTAssertEqual(model.profiles.count, 2)
    }

    // MARK: - Shutter capture context (TASK-10 acceptance 10.3, 10.4)

    func testCaptureContextRecomputesTextForANewCapturedMoment() throws {
        // 10.3/14.1/14.8/14.9: rendering once at 2026-01-10 then again at
        // 2026-01-11 for the same profile must produce "第 2 天", not a
        // value stuck at "第 1 天" — proof the text is recomputed from
        // `capturedAt`, never cached. One model with a *mutable* clock, not
        // two separately constructed models each with a fixed clock — same
        // reasoning as `testOverlayTextIncrementsWithTheCaptureMomentNotTheSeedMoment`
        // (code review finding). This also covers 14.8/14.9 (the two
        // acceptance items TASK-14's own notes call the easiest to miss):
        // `refreshOverlay()`/`refreshTick` are never touched anywhere in
        // this test, so it equally proves a capture is correct whether or
        // not a viewfinder refresh happened first (an earlier, separate test
        // for that turned out to be redundant with this one — same review).
        let seedDay = try fixedNow() // 2026-01-10
        let clock = MutableClock(seedDay)
        let store = makeProfileStore(now: seedDay)
        let profile = try XCTUnwrap(store.profiles.first) // startDate == seedDay, dayOne
        let (model, _, _, _) = makeModel(profileStore: store, nowProvider: clock.now)

        XCTAssertEqual(model.captureContext(for: profile).text, "第 1 天")

        clock.current = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 8))
        XCTAssertEqual(model.captureContext(for: profile).text, "第 2 天")
    }

    func testCaptureContextCapturedAtOriginatesFromTheInjectedClockOnly() throws {
        // 10.4: `capturedAt` must come from exactly the clock this model was
        // given — nothing in the call chain (`TemplateRenderer` included)
        // reads the system clock on its own. `grep -n "Date()"
        // DaysCam/Services/TemplateRenderer.swift` finds no matches, which is
        // what makes this deterministic instead of merely "close enough."
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now)
        let profile = try XCTUnwrap(model.profiles.first)

        XCTAssertEqual(model.captureContext(for: profile).capturedAt, now)
    }

    func testCaptureContextCarriesTheProfilesThemeAndPosition() throws {
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        var styled = try XCTUnwrap(store.profiles.first)
        styled.style = OverlayStyle(legacyTheme: .filmStrip)
        styled.position = .anchor(.topLeading)
        try store.update(styled)

        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        let context = model.captureContext(for: styled)
        XCTAssertEqual(context.style, OverlayStyle(legacyTheme: .filmStrip))
        XCTAssertEqual(context.placement, .anchor(.topLeading))
    }

    func testCapturePhotoIsANoOpWhenTheShutterIsDisabled() throws {
        // `isShutterDisabled` requires `cameraService.status == .running`,
        // which never happens without a real capture device (same boundary
        // `CameraServiceTests` documents — `EmptyDeviceProvider` always
        // returns nil). `capturePhoto()` must not flip `isCapturing` or crash
        // when tapped in that state, matching what the disabled shutter
        // button already prevents in the UI.
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now)
        XCTAssertTrue(model.isShutterDisabled)

        model.capturePhoto()

        XCTAssertFalse(model.isCapturing)
    }

    // MARK: - Cross-midnight / foreground refresh (TASK-14)

    func testRefreshOverlayPublishesAChange() throws {
        // The viewfinder's re-render trigger, independent of the
        // notification plumbing below — `refreshOverlay()` is what the
        // notification observers call, and what these tests call directly.
        let (model, _, _, _) = makeModel(now: try fixedNow())
        var fired = false
        let cancellable = model.objectWillChange.sink { fired = true }
        defer { cancellable.cancel() }

        model.refreshOverlay()

        XCTAssertTrue(fired)
    }

    /// Subscribes to `model.$refreshTick` and captures which thread the
    /// *first* change after subscribing is delivered on.
    ///
    /// Combine delivers to every subscriber of a publisher on whatever
    /// thread that publisher's value was actually produced on, unless
    /// something upstream redirects it — so this test subscriber sees
    /// exactly the same thread `CameraScreenModel`'s own internal sink would
    /// have mutated `refreshTick` from. Posting from a background queue
    /// (rather than the main queue an earlier version of this test used) is
    /// what makes this a real test: `NSCalendarDayChanged` is not
    /// documented to arrive on the main thread, and posting from main would
    /// pass even without `bindToClockNotifications`'s `.receive(on: .main)`
    /// (code review finding).
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
        // 14.3/14.4: the calendar rolling over while the app sits on the
        // camera screen must not require anything else to happen first, and
        // must land on the main thread even though it was posted from a
        // background queue (a real possibility for this notification).
        let (model, _, _, _) = makeModel(now: try fixedNow())

        let deliveredOnMain = threadRefreshTickChangeIsDeliveredOn(model) {
            NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        }

        XCTAssertEqual(deliveredOnMain, true)
    }

    func testWillEnterForegroundNotificationTriggersARefreshOnTheMainThread() throws {
        // 14.3/14.7: returning from the background must refresh immediately,
        // not wait for some other unrelated change, and must land on main.
        let (model, _, _, _) = makeModel(now: try fixedNow())

        let deliveredOnMain = threadRefreshTickChangeIsDeliveredOn(model) {
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        }

        XCTAssertEqual(deliveredOnMain, true)
    }

    func testCaptureContextTextForDateOnlyReflectsTheNewCapturedDate() throws {
        // 14.2: the date-only branch must track the capture moment exactly
        // like the day-count branch does (14.1, same as TASK-10's 10.3 —
        // see testCaptureContextRecomputesTextForANewCapturedMoment).
        let seedDay = try fixedNow() // 2026-01-10
        let clock = MutableClock(seedDay)
        let store = makeProfileStore(now: seedDay)
        var dateOnly = try XCTUnwrap(store.profiles.first)
        dateOnly.showDayCount = false
        dateOnly.showDate = true
        try store.update(dateOnly)
        let (model, _, _, _) = makeModel(profileStore: store, nowProvider: clock.now)

        XCTAssertEqual(model.captureContext(for: dateOnly).text, "2026.01.10")

        clock.current = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 8))
        XCTAssertEqual(model.captureContext(for: dateOnly).text, "2026.01.11")
    }

    // MARK: - Data-recovery alert (TASK-15 acceptance 15.1)

    /// Writes unreadable bytes straight to `store`'s file, bypassing every
    /// check the store makes — mirrors `ProfileStoreTests`' own
    /// `writeRawProfiles` helper, just for garbage instead of valid records.
    private func corrupt(_ store: ProfileStore) throws {
        let garbage = try XCTUnwrap("這不是 JSON".data(using: .utf8))
        try garbage.write(to: store.fileURL)
    }

    func testShowsCorruptionRecoveredAlertTrueWhenTheStoreJustRecovered() throws {
        let now = try fixedNow()
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults)
        try corrupt(store)
        store.load()
        XCTAssertTrue(store.didRecoverFromCorruption) // sanity check on the fixture

        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        XCTAssertTrue(model.showsCorruptionRecoveredAlert)
    }

    func testShowsCorruptionRecoveredAlertFalseOnANormalLaunch() throws {
        let (model, _, _, _) = makeModel(now: try fixedNow()) // makeProfileStore seeds cleanly
        XCTAssertFalse(model.showsCorruptionRecoveredAlert)
    }

    func testDismissCorruptionRecoveredAlertClearsIt() throws {
        let now = try fixedNow()
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults)
        try corrupt(store)
        store.load()
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        XCTAssertTrue(model.showsCorruptionRecoveredAlert)

        model.dismissCorruptionRecoveredAlert()

        XCTAssertFalse(model.showsCorruptionRecoveredAlert)
    }

    // MARK: - Saved toast (TASK-15, PRD FR-5.4; 0.2 TASK-21 generalizes this to showToast)

    func testShowToastShowsTheGivenMessage() throws {
        let (model, _, _, _) = makeModel(now: try fixedNow())
        model.showToast(message: "已儲存")
        XCTAssertEqual(model.toastState?.message, "已儲存")
    }

    func testShowToastCarriesTheThumbnail() throws {
        let (model, _, _, _) = makeModel(now: try fixedNow())
        let thumbnail = UIImage()
        model.showToast(message: "已儲存", thumbnail: thumbnail)
        XCTAssertTrue(model.toastState?.thumbnail === thumbnail)
    }

    func testShowToastDismissesWhenTheScheduledCallbackFires() throws {
        let spy = SchedulerSpy()
        let (model, _, _, _) = makeModel(now: try fixedNow(), scheduleToastDismiss: spy.schedule)

        model.showToast(message: "已儲存")
        XCTAssertNotNil(model.toastState)
        XCTAssertEqual(spy.scheduled.count, 1)

        spy.scheduled[0]()

        XCTAssertNil(model.toastState)
    }

    func testANewerToastSurvivesAnOlderDismissTimerFiringLate() throws {
        // PRD acceptance 10.22 (rapid shutter presses): the toast must not
        // be cut short by an earlier save's dismiss timer firing after a
        // second, newer toast has already replaced it — nor must the toasts
        // stack up.
        let spy = SchedulerSpy()
        let (model, _, _, _) = makeModel(now: try fixedNow(), scheduleToastDismiss: spy.schedule)

        model.showToast(message: "已儲存")
        let firstID = model.toastState?.id
        model.showToast(message: "已儲存")
        let secondID = model.toastState?.id
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(spy.scheduled.count, 2)

        spy.scheduled[0]() // the first toast's stale dismiss, firing late

        XCTAssertEqual(model.toastState?.id, secondID) // second toast untouched

        spy.scheduled[1]() // the second toast's own dismiss

        XCTAssertNil(model.toastState)
    }

    // MARK: - "尚未開始" for a future start date (TASK-15 acceptance 15.3–15.5)

    private func makeFutureProfile(store: ProfileStore) throws -> CameraProfile {
        var future = try XCTUnwrap(store.profiles.first)
        future.startDate = DateFixture.components(2026, 1, 1) // after `now` below
        try store.update(future)
        return future
    }

    func testOverlayTextShowsNotStartedForAFutureStartDate() throws {
        // 15.3: start date 2026-01-01, "now" 2025-12-01.
        let now = try XCTUnwrap(DateFixture.date(2025, 12, 1, hour: 8))
        let store = makeProfileStore(now: now)
        _ = try makeFutureProfile(store: store)

        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        XCTAssertEqual(model.overlayText, "尚未開始")
    }

    func testOverlayTextShowsNotStartedForEveryLegalUnitPair() throws {
        // 15.3: "八種單位組合逐一切換皆顯示尚未開始".
        let now = try XCTUnwrap(DateFixture.date(2025, 12, 1, hour: 8))
        let store = makeProfileStore(now: now)
        var future = try makeFutureProfile(store: store)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        // The eight 0.1 pairs as their PRD 0.2 §4.3 unit sets.
        let legacySets: [Set<DisplayUnit>] = [
            [.day], [.week, .day], [.week], [.month, .day], [.month],
            [.year, .month, .day], [.year, .month], [.year]
        ]
        for units in legacySets {
            future.displayUnits = units
            try store.update(future)
            XCTAssertEqual(model.overlayText, "尚未開始", "\(units)")
        }
    }

    func testOverlayTextShowsDateInsteadOfNotStartedWhenDateOnlyIsConfigured() throws {
        // 15.4: turning off the day count and on the date must show the
        // date, never "尚未開始" (that text only ever applies to the elapsed
        // amount).
        let now = try XCTUnwrap(DateFixture.date(2025, 12, 1, hour: 8))
        let store = makeProfileStore(now: now)
        var future = try makeFutureProfile(store: store)
        future.showDayCount = false
        future.showDate = true
        try store.update(future)

        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        XCTAssertEqual(model.overlayText, "2025.12.01")
    }

    func testOverlayTextPrefixesNameEvenWhenNotStarted() throws {
        // 15.5: showName still applies on top of "尚未開始".
        let now = try XCTUnwrap(DateFixture.date(2025, 12, 1, hour: 8))
        let store = makeProfileStore(now: now)
        var future = try makeFutureProfile(store: store)
        future.name = "小寶"
        future.showName = true
        try store.update(future)

        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        XCTAssertEqual(model.overlayText, "小寶 尚未開始")
    }

    func testCaptureContextShowsNotStartedForAFutureStartDate() throws {
        // The bake path must agree with the viewfinder on this, same as
        // every other overlayText/captureContext pairing in this file.
        let now = try XCTUnwrap(DateFixture.date(2025, 12, 1, hour: 8))
        let store = makeProfileStore(now: now)
        let future = try makeFutureProfile(store: store)

        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        XCTAssertEqual(model.captureContext(for: future).text, "尚未開始")
    }

    // MARK: - processCapturedImage (TASK-10 bake wiring)

    private func sampleContext(_ now: Date) -> (capturedAt: Date, text: String, style: OverlayStyle, placement: OverlayPlacement) {
        (capturedAt: now, text: "第 1 天", style: OverlayStyle(), placement: .anchor(.bottomTrailing))
    }

    func testProcessCapturedImagePassesTheContextThroughToBake() throws {
        let now = try fixedNow()
        var received: (image: UIImage?, text: String?, style: OverlayStyle?, placement: OverlayPlacement?)
        let bakeExp = expectation(description: "bake called")
        let sourceImage = UIImage()
        let (model, _, _, _) = makeModel(now: now, bake: { image, text, style, placement in
            received = (image, text, style, placement)
            bakeExp.fulfill()
            return UIImage()
        })

        model.processCapturedImage(sourceImage, context: sampleContext(now))

        wait(for: [bakeExp], timeout: 2)
        XCTAssertTrue(received.image === sourceImage)
        XCTAssertEqual(received.text, "第 1 天")
        XCTAssertEqual(received.style, OverlayStyle())
        XCTAssertEqual(received.placement, .anchor(.bottomTrailing))
    }

    func testProcessCapturedImageCropsBeforeBakingUsingTheConfiguredAspectRatio() throws {
        // PRD 0.2 FR-5.7′: "先裁再烘焙" — the configured
        // `captureSettingsStore.captureAspectRatio` must reach `crop` before
        // `bake` ever sees the image.
        let now = try fixedNow()
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.setAspectRatio(.oneByOne)
        var receivedRatio: CaptureAspectRatio?
        let cropExp = expectation(description: "crop called")
        let (model, _, _, _) = makeModel(now: now,
                                         captureSettingsStore: settings,
                                         crop: { image, ratio in
                                             receivedRatio = ratio
                                             cropExp.fulfill()
                                             return image
                                         },
                                         bake: { _, _, _, _ in UIImage() })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        wait(for: [cropExp], timeout: 2)
        XCTAssertEqual(receivedRatio, .oneByOne)
    }

    func testProcessCapturedImageSurfacesCaptureErrorWhenBakeFails() throws {
        // PRD §7.3: baking failure — not one of PhotoSaver's save errors,
        // does not depend on it landing.
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now, bake: { _, _, _, _ in nil })
        XCTAssertNil(model.captureError)

        model.processCapturedImage(UIImage(), context: sampleContext(now))
        // `processCapturedImage` sets this synchronously, before dispatching
        // to the background queue — same as `capturePhoto()`'s own
        // assignment does in the real flow.
        XCTAssertTrue(model.isCapturing)

        waitUntil { model.captureError != nil }
        XCTAssertEqual(model.captureError?.message, "照片處理失敗，請再試一次。")
        XCTAssertFalse(model.captureError?.showsSettingsAction ?? true)
        // 10.22: the bake-failure branch must not leave the shutter stuck
        // disabled — a genuine `true` → `false` transition, not merely
        // "still false" (mutation-verified: deleting the reset here left
        // this red).
        waitUntil { model.isCapturing == false }
    }

    func testProcessCapturedImageDoesNotCallSaveWhenBakeFails() throws {
        var saveCalled = false
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _ in nil },
                                         save: { _, completion in
                                             saveCalled = true
                                             completion(.success("asset-1"))
                                         })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.captureError != nil }
        XCTAssertFalse(saveCalled)
    }

    func testProcessCapturedImagePassesTheBakedImageToSave() throws {
        let now = try fixedNow()
        let bakedImage = UIImage()
        var receivedImage: UIImage?
        let saveExp = expectation(description: "save called")
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _ in bakedImage },
                                         save: { image, completion in
                                             receivedImage = image
                                             saveExp.fulfill()
                                             completion(.success("asset-1"))
                                         })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        wait(for: [saveExp], timeout: 2)
        XCTAssertTrue(receivedImage === bakedImage)
    }

    func testProcessCapturedImagePresentsSavedToastOnSaveSuccess() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(.success("asset-1")) })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.toastState != nil }
        XCTAssertEqual(model.toastState?.message, "已儲存")
        XCTAssertNil(model.captureError)
        waitUntil { model.isCapturing == false }
    }

    func testProcessCapturedImageDownscalesTheThumbnailForTheToast() throws {
        // Review-anticipated finding: the toast must not hold the
        // full-resolution baked photo just to draw it at 44x44.
        let now = try fixedNow()
        let largeSize = CGSize(width: 1000, height: 800)
        let large = UIGraphicsImageRenderer(size: largeSize).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: largeSize))
        }
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _ in large },
                                         save: { _, completion in completion(.success("asset-1")) })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.toastState != nil }
        let thumbnail = try XCTUnwrap(model.toastState?.thumbnail)
        XCTAssertLessThan(thumbnail.size.width, largeSize.width)
        XCTAssertLessThan(thumbnail.size.height, largeSize.height)
        XCTAssertEqual(max(thumbnail.size.width, thumbnail.size.height), 88, accuracy: 0.5)
    }

    func testProcessCapturedImageSurfacesCaptureErrorOnPermissionDenied() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(.failure(.permissionDenied)) })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.captureError != nil }
        XCTAssertEqual(model.captureError?.message, PhotoSaveError.permissionDenied.displayMessage)
        XCTAssertTrue(model.captureError?.showsSettingsAction ?? false)
        XCTAssertNil(model.toastState)
        waitUntil { model.isCapturing == false }
    }

    func testProcessCapturedImageSurfacesCaptureErrorOnSaveFailed() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(.failure(.saveFailed("磁碟空間不足"))) })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.captureError != nil }
        XCTAssertEqual(model.captureError?.message, "儲存失敗：磁碟空間不足。請確認裝置儲存空間後再試一次。")
        XCTAssertFalse(model.captureError?.showsSettingsAction ?? true)
        XCTAssertNil(model.toastState)
        waitUntil { model.isCapturing == false }
    }

    func testProcessCapturedImageResetsIsCapturingWhenSaveCompletes() throws {
        // 10.22: `save` must not leave the shutter permanently disabled once
        // it calls back, whichever way it resolves.
        let now = try fixedNow()
        var storedCompletion: ((Result<String, PhotoSaveError>) -> Void)?
        let completionStored = expectation(description: "save completion captured")
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _ in UIImage() },
                                         save: { _, completion in
                                             storedCompletion = completion
                                             completionStored.fulfill()
                                         })

        model.processCapturedImage(UIImage(), context: sampleContext(now))
        XCTAssertTrue(model.isCapturing) // set synchronously, before backgrounding

        wait(for: [completionStored], timeout: 2)

        // Not resolved yet: `save`'s own completion is still pending,
        // deliberately not called above — `isCapturing` must still be
        // `true` here, or this test would prove nothing about the reset
        // below actually being *caused* by the completion firing.
        XCTAssertNotNil(storedCompletion)
        XCTAssertTrue(model.isCapturing)

        storedCompletion?(.success("asset-1"))

        waitUntil { model.isCapturing == false }
    }

    // MARK: - Overlay panel shell (PRD 0.2 FR-8, TASK-22 acceptance 22.4)

    func testPanelModelChangesAreForwardedToTheScreenModel() throws {
        // PR #60 review: CameraScreen only observes CameraScreenModel, so the
        // nested panel model's changes must re-publish through it.
        let (model, _, _, _) = makeModel(now: try fixedNow())
        var sends = 0
        let cancellable = model.objectWillChange.sink { _ in sends += 1 }
        defer { cancellable.cancel() }

        model.panelModel.open()
        XCTAssertGreaterThan(sends, 0, "open() must re-render CameraScreen")
        let afterOpen = sends
        model.panelModel.selectedTab = .position
        XCTAssertGreaterThan(sends, afterOpen, "switching tabs must re-render")
        let afterTab = sends
        model.panelModel.close()
        XCTAssertGreaterThan(sends, afterTab, "close() must re-render")
    }

    func testCapturingWhilePanelIsOpenRunsNormallyAndKeepsItOpen() throws {
        // 22.4: opening the panel must not disable the shutter or otherwise
        // couple into the capture pipeline, and a capture must not close it.
        let now = try fixedNow()
        var captureCallCount = 0
        let (model, _, _, _) = makeModel(now: now,
                                         captureImage: { _, completion in
                                             captureCallCount += 1
                                             completion(.success(UIImage()))
                                         })
        let profile = try XCTUnwrap(model.selectedProfile)
        model.panelModel.open()

        model.beginCapture(profile: profile) // bypasses the hardware-gated
                                              // public `capturePhoto()`, same
                                              // reasoning as every other
                                              // direct call in this file.

        XCTAssertEqual(captureCallCount, 1)
        XCTAssertTrue(model.panelModel.isOpen, "capturing must not close the panel")
    }

    // MARK: - 天數規則 tab wiring (PRD 0.2 FR-13, TASK-22 hooking up TASK-25's RulesTabModel)

    func testRulesTabModelTracksTheSelectedProfile() throws {
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        let first = try XCTUnwrap(model.rulesTabModel)
        XCTAssertEqual(first.profile.id, model.selectedProfileID)

        let second = try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        waitUntil { model.selectedProfileID == second.id }

        let updated = try XCTUnwrap(model.rulesTabModel)
        XCTAssertEqual(updated.profile.id, second.id)
    }

    func testRulesTabModelKeepsTheSameInstanceAcrossUnrelatedChanges() throws {
        // Rebuilding on every unrelated re-render would discard an
        // in-progress name edit (same class of bug `displaySettingsModel`'s
        // own doc comment documents).
        let (model, _, _, _) = makeModel(now: try fixedNow())
        let first = try XCTUnwrap(model.rulesTabModel)

        model.refreshOverlay() // bumps `refreshTick`, unrelated to the profile

        let second = try XCTUnwrap(model.rulesTabModel)
        XCTAssertTrue(first === second)
    }

    // MARK: - Camera toolbar (PRD 0.2 FR-7, TASK-21 acceptance 21.1–21.5)

    private final class StubFlashCapabilityProvider: FlashCapabilityProviding {
        let hasFlash: Bool
        init(hasFlash: Bool) { self.hasFlash = hasFlash }
        func hasFlash(for facing: CameraFacing) -> Bool { hasFlash }
    }

    func testProfileMenuItemsAreExactlyTheProfilesInStoreOrderWithNoManagementEntry() throws {
        // 21.1: the menu is just names, in `ProfileStore`'s order — no
        // synthetic "管理設定檔" entry mixed into the model-level list (that
        // entry point moved out of the menu in FR-7.11; `CameraScreen`'s
        // `Menu` correspondingly no longer adds one).
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        XCTAssertEqual(model.profileMenuItems.map(\.name), store.profiles.map(\.name))
        XCTAssertEqual(model.profileMenuItems.count, store.profiles.count)
    }

    func testFlashToolIsDisabledWhenNoFlashIsAvailable() throws {
        // 21.2. `switchCamera()` cannot actually reach the front camera in
        // this test harness (`EmptyDeviceProvider` always returns `nil`, the
        // same boundary PR #41's 19.4 documents), so this exercises
        // `isFlashAvailable`'s other `false` condition — a back camera with
        // no flash unit — which disables the button the same way the front
        // camera does. Flagged in this PR's description so this isn't
        // mistaken for an untested "front camera" branch.
        let (model, _, _, _) = makeModel(now: try fixedNow(),
                                         flashCapabilityProvider: StubFlashCapabilityProvider(hasFlash: false))
        XCTAssertTrue(model.isFlashToolDisabled)
    }

    func testFlashToolIsNotDisabledWhenFlashIsAvailable() throws {
        let (model, _, _, _) = makeModel(now: try fixedNow(),
                                         flashCapabilityProvider: StubFlashCapabilityProvider(hasFlash: true))
        XCTAssertFalse(model.isFlashToolDisabled)
    }

    func testActiveToolsReflectTheirCaptureSettings() throws {
        // 21.3: flash auto, timer 3s, grid on → all three `isActive`.
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleFlash() // .off -> .auto
        settings.cycleTimer() // .off -> .threeSeconds
        settings.toggleGrid() // false -> true
        let (model, _, _, _) = makeModel(now: try fixedNow(), captureSettingsStore: settings)

        XCTAssertTrue(model.isFlashToolActive)
        XCTAssertTrue(model.isTimerToolActive)
        XCTAssertTrue(model.isGridToolActive)
    }

    func testToolsAreNotActiveAtTheirDefaults() throws {
        let (model, _, _, _) = makeModel(now: try fixedNow())
        XCTAssertFalse(model.isFlashToolActive)
        XCTAssertFalse(model.isTimerToolActive)
        XCTAssertFalse(model.isGridToolActive)
    }

    // MARK: - Bottom-bar thumbnail (PRD 0.2 FR-15.2, TASK-21 acceptance 21.4/21.5)

    func testLatestThumbnailIsNilBeforeAnyCaptureThisLaunch() throws {
        // 21.4 (the reachable half — no read permission is ever requested by
        // this model, so the "icon" fallback in the view is simply whatever
        // renders when this is `nil`).
        let (model, _, _, _) = makeModel(now: try fixedNow())
        XCTAssertNil(model.latestThumbnailImage)
    }

    func testLatestThumbnailIsTheBakedResultAfterACaptureThisLaunch() throws {
        // 21.5.
        let now = try fixedNow()
        let baked = UIImage()
        let (model, _, _, _) = makeModel(now: now, bake: { _, _, _, _ in baked })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.latestThumbnailImage != nil }
    }

    func testSuccessfulSaveRecordsTheAssetInCapturedPhotoStore() throws {
        // PRD 0.2 FR-15.1: the identifier `save` returns must reach
        // `capturedPhotoStore.capturedAssetIDs`, not just the in-memory
        // thumbnail.
        let now = try fixedNow()
        let capturedPhotoStore = CapturedPhotoStore(directory: directory.appendingPathComponent("recorded-photos", isDirectory: true))
        let store = makeProfileStore(now: now)
        let service = CameraService(authorizer: StubAuthorizer(status: .notDetermined), deviceProvider: EmptyDeviceProvider())
        let model = CameraScreenModel(cameraService: service,
                                      profileStore: store,
                                      capturedPhotoStore: capturedPhotoStore,
                                      calendar: DateFixture.taipei,
                                      calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
                                      bake: { _, _, _, _ in UIImage() },
                                      save: { _, completion in completion(.success("new-asset-id")) })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { capturedPhotoStore.capturedAssetIDs.contains("new-asset-id") }
    }

    // MARK: - Timer countdown (PRD 0.2 FR-7.6, TASK-21 acceptance 19.8–19.10)

    func testCountdownTicksDownThenCapturesExactlyOnce() throws {
        // 19.8: 3-second timer, 3 injected ticks → countdownRemaining goes
        // 3, 2, 1, nil, and the real capture fires exactly once, after the
        // third tick (not before).
        let now = try fixedNow()
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleTimer() // .off -> .threeSeconds
        let ticker = FakeCountdownTicker()
        var captureCallCount = 0
        let (model, _, _, _) = makeModel(now: now,
                                         captureSettingsStore: settings,
                                         countdownTicker: ticker,
                                         captureImage: { _, completion in
                                             captureCallCount += 1
                                             completion(.success(UIImage()))
                                         })
        let profile = try XCTUnwrap(model.selectedProfile)

        model.beginCapture(profile: profile)
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
        let now = try fixedNow()
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleTimer() // .off -> .threeSeconds
        settings.cycleTimer() // .threeSeconds -> .tenSeconds
        let ticker = FakeCountdownTicker()
        var captureCallCount = 0
        let (model, _, _, _) = makeModel(now: now,
                                         captureSettingsStore: settings,
                                         countdownTicker: ticker,
                                         captureImage: { _, completion in
                                             captureCallCount += 1
                                             completion(.success(UIImage()))
                                         })
        let profile = try XCTUnwrap(model.selectedProfile)

        model.beginCapture(profile: profile)
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

    func testCountdownCapturesAtTheInstantItActuallyFinishesNotWhenItStarted() throws {
        // 19.10: countdown starts at 23:59:59, finishes at 00:00:02 the next
        // day — the baked text must reflect the moment the countdown
        // actually finished (第 11 天), not the moment the shutter was first
        // pressed (which would still be 第 10 天).
        let seedDay = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 23, minute: 59, second: 59))
        let clock = MutableClock(seedDay)
        // Started 2026-01-01, dayOne: Jan 10 is 第 10 天, Jan 11 is 第 11 天
        // (the shared fixture `docs/TASKS-0.2-ui-redesign.md` uses).
        let store = makeProfileStore(now: seedDay, seed: [
            CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1))
        ])
        let profile = try XCTUnwrap(store.profiles.first)
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleTimer() // .off -> .threeSeconds
        let ticker = FakeCountdownTicker()
        var receivedText: String?
        let (model, _, _, _) = makeModel(profileStore: store,
                                         nowProvider: clock.now,
                                         captureSettingsStore: settings,
                                         countdownTicker: ticker,
                                         bake: { _, text, _, _ in
                                             receivedText = text
                                             return UIImage()
                                         },
                                         captureImage: { _, completion in completion(.success(UIImage())) })

        model.beginCapture(profile: profile)
        clock.current = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 0, minute: 0, second: 2))
        ticker.tick()
        ticker.tick()
        ticker.tick()

        waitUntil { receivedText != nil }
        XCTAssertEqual(receivedText, "第 11 天")
    }
}
