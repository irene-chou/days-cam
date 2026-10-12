import AVFoundation
import Combine
import Photos
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
/// `ProfileManagerModelTests`.
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

    /// `seedShowsName` keeps the TASK-119 default (name on) for the seeded
    /// profile; most tests predate it and assert text without the name.
    private func makeProfileStore(now: Date, seed: [CameraProfile] = [], seedShowsName: Bool = false) -> ProfileStore {
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        if seed.isEmpty {
            store.load() // seeds the one default profile
            if !seedShowsName, var seeded = store.profiles.first {
                seeded.showName = false
                try? store.update(seeded)
            }
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
                           cropRect: @escaping (CGSize, CaptureAspectRatio) -> CGRect = { size, _ in CGRect(origin: .zero, size: size) },
                           bake: @escaping (UIImage, String, OverlayStyle, OverlayPlacement, ResolvedOverlayFont, CGRect?) -> UIImage? = { _, _, _, _, _, _ in UIImage() },
                           save: @escaping (UIImage, @escaping (Result<String, PhotoSaveError>) -> Void) -> Void = { _, completion in completion(.success("asset-1")) },
                           captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil,
                           scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { _ in },
                           thumbnailLibrary: GalleryLibrary? = nil,
                           fontLibrary: (any FontShellControlling)? = nil,
                           saveTimeout: TimeInterval = 30) -> (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore) {
        makeModel(status: status,
                 captureSupported: captureSupported,
                 profileStore: profileStore,
                 nowProvider: { now },
                 flashCapabilityProvider: flashCapabilityProvider,
                 captureSettingsStore: captureSettingsStore,
                 countdownTicker: countdownTicker,
                 cropRect: cropRect,
                 bake: bake,
                 save: save,
                 captureImage: captureImage,
                 scheduleToastDismiss: scheduleToastDismiss,
                 thumbnailLibrary: thumbnailLibrary,
                 fontLibrary: fontLibrary,
                 saveTimeout: saveTimeout)
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
                           cropRect: @escaping (CGSize, CaptureAspectRatio) -> CGRect = { size, _ in CGRect(origin: .zero, size: size) },
                           bake: @escaping (UIImage, String, OverlayStyle, OverlayPlacement, ResolvedOverlayFont, CGRect?) -> UIImage? = { _, _, _, _, _, _ in UIImage() },
                           save: @escaping (UIImage, @escaping (Result<String, PhotoSaveError>) -> Void) -> Void = { _, completion in completion(.success("asset-1")) },
                           captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil,
                           scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { _ in },
                           thumbnailLibrary: GalleryLibrary? = nil,
                           fontLibrary: (any FontShellControlling)? = nil,
                           fontPreparationTimeout: TimeInterval = 3,
                           saveTimeout: TimeInterval = 30) -> (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore) {
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
                                      cropRect: cropRect,
                                      countdownTicker: countdownTicker,
                                      bake: bake,
                                      save: save,
                                      captureImage: captureImage,
                                      scheduleToastDismiss: scheduleToastDismiss,
                                      makeThumbnailLibrary: { _ in thumbnailLibrary ?? FakeThumbnailLibrary(status: .denied) },
                                      fontLibrary: fontLibrary,
                                      fontPreparationTimeout: fontPreparationTimeout,
                                      saveTimeout: saveTimeout)
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
        // today, so the overlay reads "我的紀錄 第 1 天" (TASK-119) with no further setup.
        let now = try fixedNow() // 2026-01-10
        let store = makeProfileStore(now: now, seedShowsName: true)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        XCTAssertEqual(model.overlayText, "\(ProfileStore.defaultProfileName) 第 1 天")
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

    func testDateOnlyConfigurationShowsTheDateAlone() throws {
        // 8.3 again (TASK-107 #426 reverses TASK-47): a date-only profile is
        // stored as such and prints the capture date alone the next day —
        // never "第 2 天" (PRD FR-2.17, 107.6).
        let seedDay = try fixedNow() // 2026-01-10
        let store = makeProfileStore(now: seedDay)
        var dateOnly = try XCTUnwrap(store.profiles.first)
        dateOnly.showDayCount = false
        dateOnly.showDate = true
        try store.update(dateOnly)

        let nextDay = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 8))
        let (model, _, _, _) = makeModel(profileStore: store, now: nextDay)
        XCTAssertEqual(model.overlayText, "2026.01.11", "107.6")
    }

    func testOverlayTextPrefixesTheNameWhenShowNameIsOn() throws {
        // 8.4/8.5: name on prepends "{name} ", name off leaves no stray space.
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        var withName = try XCTUnwrap(store.profiles.first) // name defaults to the seed name
        withName.showName = true
        try store.update(withName)

        let (shown, _, _, _) = makeModel(profileStore: store, now: now)
        XCTAssertEqual(shown.overlayText, "\(ProfileStore.defaultProfileName) 第 1 天")

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
        // `ProfileManagerModelTests`.
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

        XCTAssertEqual(model.profiles.map(\.name), [ProfileStore.defaultProfileName, "小寶"])
        XCTAssertEqual(model.selectedProfileID, store.selectedProfileID)
    }

    // MARK: - Profile switcher (TASK-13)

    func testCurrentProfileNameReflectsTheSelectedProfile() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now)
        XCTAssertEqual(model.currentProfileName, ProfileStore.defaultProfileName)
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
        waitUntil { model.currentProfileName == ProfileStore.defaultProfileName }
        // Default profile was seeded with startDate == `now` itself, so under
        // `.dayOne` this is day 1.
        XCTAssertEqual(model.overlayText, "第 1 天")
    }

    func testPresentProfileManagementShowsThePanel() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now)
        XCTAssertFalse(model.isProfileManagerPresented)

        model.presentProfileManagement()
        XCTAssertTrue(model.isProfileManagerPresented)

        model.dismissProfileManagement()
        XCTAssertFalse(model.isProfileManagerPresented)
    }

    func testProfileManagerModelSharesTheSameStoreAsTheScreen() throws {
        // The management panel and the switcher must never fall out of sync —
        // both are views onto the same `ProfileStore`.
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        XCTAssertEqual(model.profileManagerModel.profiles.map(\.id), store.profiles.map(\.id))

        try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        XCTAssertEqual(model.profileManagerModel.profiles.count, 2)
        waitUntil { model.profiles.count == 2 }
    }

    func testAddingFromTheManagerKeepsTheSheetAndPanelAsTheyWere() throws {
        // #226 R-7: new profile selected and its edit page pushed; the sheet
        // stays open and the overlay panel is left untouched.
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        model.openOverlayPanel()
        model.panelModel.selectedTab = .style
        model.presentProfileManagement()

        model.profileManagerModel.addProfile()

        XCTAssertEqual(store.profiles.count, 2)
        XCTAssertEqual(store.selectedProfileID, store.profiles.last?.id)
        XCTAssertTrue(model.isProfileManagerPresented)
        XCTAssertEqual(model.profileManagerModel.path, [store.profiles.last?.id].compactMap { $0 })
        XCTAssertEqual(model.panelModel.selectedTab, .style)
        XCTAssertTrue(model.panelModel.isOpen)
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
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
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
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
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

        XCTAssertEqual(model.overlayText, "還有 31 天")
    }

    func testOverlayTextShowsNotStartedForEveryLegalUnitPair() throws {
        // 15.3: "八種單位組合逐一切換皆顯示尚未開始", re-baselined by
        // TASK-140 (#487): the countdown reads in the checked units.
        let now = try XCTUnwrap(DateFixture.date(2025, 12, 1, hour: 8))
        let store = makeProfileStore(now: now)
        var future = try makeFutureProfile(store: store)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        // The eight 0.1 pairs as their PRD 0.2 §4.3 unit sets.
        let legacySets: [(Set<DisplayUnit>, String)] = [
            ([.day], "還有 31 天"), ([.week, .day], "還有 4 週又 3 天"), ([.week], "還有 4 週"),
            ([.month, .day], "還有 1 個月"), ([.month], "還有 1 個月"),
            ([.year, .month, .day], "還有 1 個月"), ([.year, .month], "還有 1 個月"), ([.year], "還有 31 天")
        ]
        for (units, expected) in legacySets {
            future.displayUnits = units
            try store.update(future)
            // The model mirrors the store on the main queue; without this
            // every iteration would read the first set's profile.
            let mirrored = expectation(description: "profiles mirrored")
            DispatchQueue.main.async { mirrored.fulfill() }
            wait(for: [mirrored], timeout: 1)
            XCTAssertEqual(model.overlayText, expected, "\(units)")
        }
    }

    func testDateOnlyConfigurationShowsTheDateAloneBeforeTheStart() throws {
        // 15.4 again (TASK-107 reverses TASK-47): with the day count off a
        // future start date prints nothing about it — the date part alone.
        let now = try XCTUnwrap(DateFixture.date(2025, 12, 1, hour: 8))
        let store = makeProfileStore(now: now)
        var future = try makeFutureProfile(store: store)
        future.showDayCount = false
        future.showDate = true
        try store.update(future)

        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        XCTAssertEqual(model.overlayText, "2025.12.01", "107.2")
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

        XCTAssertEqual(model.overlayText, "小寶 還有 31 天")
    }

    func testCaptureContextShowsNotStartedForAFutureStartDate() throws {
        // The bake path must agree with the viewfinder on this, same as
        // every other overlayText/captureContext pairing in this file.
        let now = try XCTUnwrap(DateFixture.date(2025, 12, 1, hour: 8))
        let store = makeProfileStore(now: now)
        let future = try makeFutureProfile(store: store)

        let (model, _, _, _) = makeModel(profileStore: store, now: now)

        XCTAssertEqual(model.captureContext(for: future).text, "還有 31 天")
    }

    // MARK: - processCapturedImage (TASK-10 bake wiring)

    private func sampleContext(_ now: Date) -> CameraScreenModel.CaptureContext {
        (capturedAt: now, text: "第 1 天", style: OverlayStyle(), placement: .anchor(.bottomTrailing), font: .pingFang)
    }

    func testProcessCapturedImagePassesTheContextThroughToBake() throws {
        let now = try fixedNow()
        var received: (image: UIImage?, text: String?, style: OverlayStyle?, placement: OverlayPlacement?)
        let bakeExp = expectation(description: "bake called")
        let sourceImage = UIImage()
        let (model, _, _, _) = makeModel(now: now, bake: { image, text, style, placement, _, _ in
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

    /// 128.1: one `bake` call, carrying the crop window for the configured
    /// ratio computed from the photo's pixel size (orientation-normalized).
    func testProcessCapturedImageBakesOnceWithTheCropWindow() throws {
        let now = try fixedNow()
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.setAspectRatio(.oneByOne)
        let photoSize = CGSize(width: 400, height: 300)
        let photo = UIGraphicsImageRenderer(size: photoSize,
                                            format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { _ in }
        var receivedPixelSize: CGSize?
        var receivedRatio: CaptureAspectRatio?
        var bakeRects: [CGRect?] = []
        let lock = NSLock()
        let bakeExp = expectation(description: "bake called")
        let (model, _, _, _) = makeModel(now: now,
                                         captureSettingsStore: settings,
                                         cropRect: { size, ratio in
                                             receivedPixelSize = size
                                             receivedRatio = ratio
                                             return CGRect(x: 50, y: 0, width: 300, height: 300)
                                         },
                                         bake: { _, _, _, _, _, rect in
                                             lock.lock(); bakeRects.append(rect); lock.unlock()
                                             bakeExp.fulfill()
                                             return UIImage()
                                         })

        model.processCapturedImage(photo, context: sampleContext(now))

        wait(for: [bakeExp], timeout: 2)
        XCTAssertEqual(receivedPixelSize, photoSize, "128.1")
        XCTAssertEqual(receivedRatio, .oneByOne, "128.1")
        XCTAssertEqual(bakeRects.count, 1, "128.1")
        XCTAssertEqual(bakeRects.first ?? nil, CGRect(x: 50, y: 0, width: 300, height: 300), "128.1")
    }

    func testProcessCapturedImageSurfacesCaptureErrorWhenBakeFails() throws {
        // PRD §7.3: baking failure — not one of PhotoSaver's save errors,
        // does not depend on it landing.
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now, bake: { _, _, _, _, _, _ in nil })
        XCTAssertNil(model.captureError)

        model.processCapturedImage(UIImage(), context: sampleContext(now))
        // `processCapturedImage` counts the photo synchronously, before
        // dispatching to the background queue.
        XCTAssertEqual(model.inFlightSaveCount, 1)

        waitUntil { model.captureError != nil }
        XCTAssertEqual(model.captureError?.message, "照片處理失敗，請再試一次。")
        XCTAssertFalse(model.captureError?.showsSettingsAction ?? true)
        // 10.22: the bake-failure branch must not leave the shutter stuck
        // disabled — a genuine 1 → 0 transition, not merely "still 0".
        waitUntil { model.inFlightSaveCount == 0 }
    }

    func testProcessCapturedImageDoesNotCallSaveWhenBakeFails() throws {
        var saveCalled = false
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in nil },
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
                                         bake: { _, _, _, _, _, _ in bakedImage },
                                         save: { image, completion in
                                             receivedImage = image
                                             saveExp.fulfill()
                                             completion(.success("asset-1"))
                                         })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        wait(for: [saveExp], timeout: 2)
        XCTAssertTrue(receivedImage === bakedImage)
    }

    func testProcessCapturedImageStartsAFlightInsteadOfAToastOnSaveSuccess() throws {
        // Issue #148 (S.10): no "已儲存" toast; one flight instead.
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(.success("asset-1")) })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.captureFlights.count == 1 }
        XCTAssertEqual(model.captureFlights.first?.status, .saved)
        XCTAssertNil(model.toastState)
        XCTAssertNil(model.captureError)
        // The thumbnail only changes once the flight lands.
        XCTAssertNil(model.latestThumbnailImage)
        waitUntil { model.inFlightSaveCount == 0 }
    }

    func testLandingASavedFlightReplacesTheThumbnailAndRemovesIt() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(.success("asset-1")) })
        model.processCapturedImage(UIImage(), context: sampleContext(now))
        waitUntil { model.captureFlights.count == 1 }
        let id = try XCTUnwrap(model.captureFlights.first?.id)

        model.flightDidLand(id: id)

        XCTAssertNotNil(model.latestThumbnailImage)
        XCTAssertTrue(model.captureFlights.isEmpty)
        XCTAssertEqual(model.thumbnailLandingCount, 1)
    }

    func testThumbnailStaysOnTheNewPhotoAfterLandingEvenWhenALaterCaptureFails() throws {
        // Issue #148 (flicker fix): once a flight lands, the thumbnail must
        // never fall back to nil (the placeholder icon) — a later failed
        // capture or flight removal included.
        let now = try fixedNow()
        var results: [Result<String, PhotoSaveError>] = [.success("asset-1"), .failure(.saveFailed("x"))]
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(results.removeFirst()) })
        model.processCapturedImage(UIImage(), context: sampleContext(now))
        waitUntil { model.captureFlights.count == 1 }
        model.flightDidLand(id: model.captureFlights[0].id)
        let landed = try XCTUnwrap(model.latestThumbnailImage)

        model.processCapturedImage(UIImage(), context: sampleContext(now))
        waitUntil { model.captureFlights.first?.status == .failed }
        model.removeCaptureFlight(id: model.captureFlights[0].id)

        XCTAssertTrue(model.latestThumbnailImage === landed)
    }

    func testSaveSuccessAnnouncesForVoiceOverAndFailureDoesNot() throws {
        let now = try fixedNow()
        var results: [Result<String, PhotoSaveError>] = [.success("asset-1"), .failure(.saveFailed("x"))]
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(results.removeFirst()) })
        var announcements: [String] = []
        model.announce = { announcements.append($0) }

        model.processCapturedImage(UIImage(), context: sampleContext(now))
        waitUntil { announcements == ["已儲存"] }
        model.processCapturedImage(UIImage(), context: sampleContext(now))
        waitUntil { model.captureFlights.contains { $0.status == .failed } }

        XCTAssertEqual(announcements, ["已儲存"])
    }

    func testCaptureTriggerFiresWhenTheShutterReallyFiresNotWhileCountingDownOrCancelling() throws {
        let now = try fixedNow()
        let settings = CaptureSettingsStore(defaults: defaults)
        settings.cycleTimer() // 3 seconds
        let ticker = FakeCountdownTicker()
        let (model, _, _, store) = makeModel(now: now, captureSettingsStore: settings, countdownTicker: ticker,
                                             captureImage: { _, _ in })
        let profile = try XCTUnwrap(store.profiles.first)

        model.beginCapture(profile: profile)
        XCTAssertEqual(model.captureTriggerCount, 0)
        ticker.tick()
        ticker.tick()
        XCTAssertEqual(model.captureTriggerCount, 0)
        ticker.tick() // reaches zero
        XCTAssertEqual(model.captureTriggerCount, 1)
    }

    func testCaptureTriggerFiresImmediatelyWithoutATimer() throws {
        let now = try fixedNow()
        let (model, _, _, store) = makeModel(now: now, captureImage: { _, _ in })
        model.beginCapture(profile: try XCTUnwrap(store.profiles.first))
        XCTAssertEqual(model.captureTriggerCount, 1)
    }

    func testFlightLandingBeforeSaveCompletesWaitsForTheSave() throws {
        let now = try fixedNow()
        var finishSave: ((Result<String, PhotoSaveError>) -> Void)?
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in finishSave = completion })
        model.processCapturedImage(UIImage(), context: sampleContext(now))
        waitUntil { model.captureFlights.count == 1 && finishSave != nil }
        let id = try XCTUnwrap(model.captureFlights.first?.id)

        model.flightDidLand(id: id)
        XCTAssertNil(model.latestThumbnailImage)
        XCTAssertEqual(model.captureFlights.count, 1)

        finishSave?(.success("asset-1"))
        XCTAssertNotNil(model.latestThumbnailImage)
        XCTAssertTrue(model.captureFlights.isEmpty)
    }

    func testBackToBackCapturesEachGetTheirOwnFlight() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(.success("asset")) })
        for _ in 0..<3 {
            model.processCapturedImage(UIImage(), context: sampleContext(now))
        }
        waitUntil { model.captureFlights.count == 3 }
        XCTAssertEqual(Set(model.captureFlights.map(\.id)).count, 3)
    }

    func testProcessCapturedImageDownscalesTheThumbnailAndFlightImage() throws {
        // The thumbnail (88px) and flight picture (600px) must not hold the
        // full-resolution baked photo.
        let now = try fixedNow()
        let largeSize = CGSize(width: 2000, height: 1600)
        let large = UIGraphicsImageRenderer(size: largeSize).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: largeSize))
        }
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in large },
                                         save: { _, completion in completion(.success("asset-1")) })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.captureFlights.count == 1 }
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

    func testProcessCapturedImageSurfacesCaptureErrorOnPermissionDenied() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(.failure(.permissionDenied)) })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.captureError != nil }
        XCTAssertEqual(model.captureError?.message, PhotoSaveError.permissionDenied.displayMessage)
        XCTAssertTrue(model.captureError?.showsSettingsAction ?? false)
        XCTAssertNil(model.toastState)
        // Issue #148 (S.10): the flight is marked failed and the thumbnail never changes.
        XCTAssertEqual(model.captureFlights.first?.status, .failed)
        XCTAssertNil(model.latestThumbnailImage)
        waitUntil { model.inFlightSaveCount == 0 }
    }

    func testProcessCapturedImageSurfacesCaptureErrorOnSaveFailed() throws {
        let now = try fixedNow()
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(.failure(.saveFailed("磁碟空間不足"))) })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.captureError != nil }
        XCTAssertEqual(model.captureError?.message, "儲存失敗：磁碟空間不足。請確認裝置儲存空間後再試一次。")
        XCTAssertFalse(model.captureError?.showsSettingsAction ?? true)
        XCTAssertNil(model.toastState)
        waitUntil { model.inFlightSaveCount == 0 }
    }

    func testProcessCapturedImageDropsTheInFlightCountWhenSaveCompletes() throws {
        // 10.22: `save` must not leave the shutter permanently disabled once
        // it calls back, whichever way it resolves.
        let now = try fixedNow()
        var storedCompletion: ((Result<String, PhotoSaveError>) -> Void)?
        let completionStored = expectation(description: "save completion captured")
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in
                                             storedCompletion = completion
                                             completionStored.fulfill()
                                         })

        model.processCapturedImage(UIImage(), context: sampleContext(now))
        XCTAssertEqual(model.inFlightSaveCount, 1) // counted synchronously, before backgrounding

        wait(for: [completionStored], timeout: 2)

        // Not resolved yet: `save`'s own completion is still pending,
        // deliberately not called above — the count must still be 1 here,
        // or this test would prove nothing about the drop below actually
        // being *caused* by the completion firing.
        XCTAssertNotNil(storedCompletion)
        XCTAssertEqual(model.inFlightSaveCount, 1)

        storedCompletion?(.success("asset-1"))

        waitUntil { model.inFlightSaveCount == 0 }
    }

    // MARK: - TASK-129 (#469) shutter unlocks after capture; bake/save pipeline

    private final class CaptureHarness {
        var captures: [(Result<UIImage, CameraCaptureError>) -> Void] = []
        var saves: [(Result<String, PhotoSaveError>) -> Void] = []
        let lock = NSLock()
        var bakedTexts: [String] = []
        var firstBakeGate: DispatchSemaphore?
    }

    private func makePipelineModel(harness: CaptureHarness, profileStore: ProfileStore, clock: MutableClock,
                                   saveTimeout: TimeInterval = 30) -> CameraScreenModel {
        let (model, _, _, _) = makeModel(
            profileStore: profileStore,
            nowProvider: clock.now,
            bake: { _, text, _, _, _, _ in
                harness.lock.lock()
                let isFirst = harness.bakedTexts.isEmpty
                harness.bakedTexts.append(text)
                harness.lock.unlock()
                if isFirst { harness.firstBakeGate?.wait() }
                return UIImage()
            },
            save: { _, completion in harness.saves.append(completion) },
            captureImage: { _, completion in harness.captures.append(completion) },
            saveTimeout: saveTimeout)
        return model
    }

    private func twoProfiles() throws -> (ProfileStore, CameraProfile, CameraProfile, MutableClock) {
        let day = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        let a = CameraProfile(name: "A", startDate: DateFixture.components(2026, 1, 1))
        let b = CameraProfile(name: "B", startDate: DateFixture.components(2026, 1, 5))
        let store = makeProfileStore(now: day, seed: [a, b])
        return (store, store.profiles[0], store.profiles[1], MutableClock(day))
    }

    /// 129.1: the shutter is free again as soon as the camera hands the
    /// photo back, even while the first photo is still being saved, and the
    /// second photo's result never lands on the first one's flight.
    func testShutterIsFreeWhileTheFirstPhotoIsStillSaving() throws {
        let (store, a, _, clock) = try twoProfiles()
        let harness = CaptureHarness()
        let model = makePipelineModel(harness: harness, profileStore: store, clock: clock)

        model.beginCapture(profile: a)
        XCTAssertTrue(model.isShutterBusy, "129.1 busy while the camera is capturing")
        harness.captures[0](.success(UIImage()))
        waitUntil { harness.saves.count == 1 }
        XCTAssertFalse(model.isCapturing)
        XCTAssertEqual(model.inFlightSaveCount, 1)
        XCTAssertFalse(model.isShutterBusy, "129.1 the shutter can be pressed again")

        model.beginCapture(profile: a)
        harness.captures[1](.success(UIImage()))
        waitUntil { harness.saves.count == 2 }
        let ids = model.captureFlights.map(\.id)
        XCTAssertEqual(ids.count, 2)

        harness.saves[1](.success("asset-2"))
        XCTAssertEqual(model.captureFlights.first { $0.id == ids[0] }?.status, .saving, "129.1 first untouched")
        XCTAssertEqual(model.captureFlights.first { $0.id == ids[1] }?.status, .saved)
        harness.saves[0](.success("asset-1"))
        XCTAssertEqual(model.captureFlights.first { $0.id == ids[0] }?.status, .saved)
    }

    /// 129.2: two photos in flight keep the shutter disabled; either one
    /// finishing frees it.
    func testShutterIsDisabledWithTwoInFlightAndFreedWhenEitherFinishes() throws {
        let (store, a, _, clock) = try twoProfiles()
        let harness = CaptureHarness()
        let model = makePipelineModel(harness: harness, profileStore: store, clock: clock)

        for index in 0..<2 {
            model.beginCapture(profile: a)
            harness.captures[index](.success(UIImage()))
            waitUntil { harness.saves.count == index + 1 }
        }
        XCTAssertEqual(model.inFlightSaveCount, 2)
        XCTAssertTrue(model.isShutterBusy, "129.2 at the limit")

        harness.saves[1](.success("asset-2")) // the later one finishes first
        XCTAssertEqual(model.inFlightSaveCount, 1)
        XCTAssertFalse(model.isShutterBusy, "129.2 freed")

        model.beginCapture(profile: a)
        harness.captures[2](.success(UIImage()))
        waitUntil { harness.saves.count == 3 }
        XCTAssertTrue(model.isShutterBusy, "129.2 full again")
        harness.saves[0](.failure(.saveFailed("x")))
        XCTAssertFalse(model.isShutterBusy, "129.2 a failure frees it too")
    }

    /// 129.3: a failed first save and a successful second one each land on
    /// their own photo.
    func testEachPhotoReportsItsOwnSaveResult() throws {
        let (store, a, _, clock) = try twoProfiles()
        let harness = CaptureHarness()
        let model = makePipelineModel(harness: harness, profileStore: store, clock: clock)
        var announcements: [String] = []
        model.announce = { announcements.append($0) }

        for index in 0..<2 {
            model.beginCapture(profile: a)
            harness.captures[index](.success(UIImage()))
            waitUntil { harness.saves.count == index + 1 }
        }
        let ids = model.captureFlights.map(\.id)

        harness.saves[0](.failure(.saveFailed("磁碟空間不足")))
        harness.saves[1](.success("asset-2"))

        XCTAssertEqual(model.captureFlights.first { $0.id == ids[0] }?.status, .failed, "129.3 first failed")
        XCTAssertEqual(model.captureFlights.first { $0.id == ids[1] }?.status, .saved, "129.3 second saved")
        XCTAssertNotNil(model.captureError, "129.3 the failure is reported")
        XCTAssertEqual(announcements, ["已儲存"], "129.3 only the successful photo is announced as saved")
        XCTAssertEqual(model.inFlightSaveCount, 0)
    }

    /// 129.4: each photo is baked with the profile and moment it was taken
    /// with, even when the profile changes while the first is still baking.
    func testEachPhotoIsBakedWithTheSettingsAtItsOwnCaptureTime() throws {
        let (store, a, b, clock) = try twoProfiles()
        let harness = CaptureHarness()
        harness.firstBakeGate = DispatchSemaphore(value: 0)
        let model = makePipelineModel(harness: harness, profileStore: store, clock: clock)

        model.beginCapture(profile: a) // Jan 10: A is day 10
        harness.captures[0](.success(UIImage()))
        waitUntil { harness.lock.lock(); defer { harness.lock.unlock() }; return harness.bakedTexts.count == 1 }

        // The first photo is still baking; the profile changes and time moves on.
        clock.current = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 8))
        model.beginCapture(profile: b) // Jan 11: B is day 7
        harness.captures[1](.success(UIImage()))
        harness.firstBakeGate?.signal()
        waitUntil { harness.saves.count == 2 }

        XCTAssertEqual(harness.bakedTexts, ["第 10 天", "第 7 天"], "129.4")
    }

    /// Two failed photos before the alert is dismissed read as a count; after
    /// dismissing, a new failure shows its own message again.
    func testTwoFailuresAreCountedInOneAlert() throws {
        let (store, a, _, clock) = try twoProfiles()
        let harness = CaptureHarness()
        let model = makePipelineModel(harness: harness, profileStore: store, clock: clock)

        for index in 0..<2 {
            model.beginCapture(profile: a)
            harness.captures[index](.success(UIImage()))
            waitUntil { harness.saves.count == index + 1 }
        }
        harness.saves[0](.failure(.saveFailed("磁碟空間不足")))
        XCTAssertEqual(model.captureError?.message, "儲存失敗：磁碟空間不足。請確認裝置儲存空間後再試一次。")
        harness.saves[1](.failure(.permissionDenied))

        XCTAssertEqual(model.captureError?.message, "2 張照片未儲存")
        XCTAssertEqual(model.captureError?.showsSettingsAction, true, "the settings button is kept if any failure needs it")

        model.dismissCaptureError()
        model.beginCapture(profile: a)
        harness.captures[2](.success(UIImage()))
        waitUntil { harness.saves.count == 3 }
        harness.saves[2](.failure(.saveFailed("磁碟空間不足")))
        XCTAssertEqual(model.captureError?.message, "儲存失敗：磁碟空間不足。請確認裝置儲存空間後再試一次。")
    }

    /// 151.1: a save that never calls back is given up on after the timeout:
    /// the photo is reported as failed (never saved), its place is freed and
    /// the shutter works again.
    func testSaveTimeoutFreesThePlaceAndReportsFailure() throws {
        let (store, a, _, clock) = try twoProfiles()
        let harness = CaptureHarness()
        let model = makePipelineModel(harness: harness, profileStore: store, clock: clock, saveTimeout: 0.1)
        var announcements: [String] = []
        model.announce = { announcements.append($0) }

        for index in 0..<2 {
            model.beginCapture(profile: a)
            harness.captures[index](.success(UIImage()))
            waitUntil { harness.saves.count == index + 1 }
        }
        XCTAssertTrue(model.isShutterBusy, "151.1 both places taken")

        waitUntil { model.inFlightSaveCount == 0 }

        XCTAssertFalse(model.isShutterBusy, "151.1 the shutter works again")
        XCTAssertEqual(model.captureFlights.map(\.status), [.failed, .failed], "151.1 failed, not saved")
        XCTAssertEqual(model.captureError?.message, "2 張照片未儲存")
        XCTAssertTrue(announcements.isEmpty, "151.1 nothing is announced as saved")
    }

    /// 151.2: the callback arriving after the timeout reports nothing again
    /// and the count stays at zero, even with a later photo in flight.
    func testLateSaveCallbackAfterTheTimeoutIsIgnored() throws {
        let (store, a, _, clock) = try twoProfiles()
        let harness = CaptureHarness()
        let model = makePipelineModel(harness: harness, profileStore: store, clock: clock, saveTimeout: 0.1)
        var announcements: [String] = []
        model.announce = { announcements.append($0) }

        model.beginCapture(profile: a)
        harness.captures[0](.success(UIImage()))
        waitUntil { harness.saves.count == 1 }
        waitUntil { model.inFlightSaveCount == 0 }
        let errorAfterTimeout = model.captureError
        XCTAssertEqual(model.captureFlights.first?.status, .failed)

        harness.saves[0](.success("late-asset"))

        XCTAssertEqual(model.inFlightSaveCount, 0, "151.2 never negative")
        XCTAssertEqual(model.captureFlights.first?.status, .failed, "151.2 still failed")
        XCTAssertEqual(model.captureError, errorAfterTimeout, "151.2 not reported twice")
        XCTAssertTrue(announcements.isEmpty)

        // A photo saved normally later is counted on its own.
        model.beginCapture(profile: a)
        harness.captures[1](.success(UIImage()))
        waitUntil { harness.saves.count == 2 }
        XCTAssertEqual(model.inFlightSaveCount, 1)
        harness.saves[1](.success("asset-2"))
        XCTAssertEqual(model.inFlightSaveCount, 0)
    }

    /// A save answered in time is not touched by its (cancelled) timeout.
    func testSaveAnsweredInTimeIsNotReportedAsTimedOut() throws {
        let (store, a, _, clock) = try twoProfiles()
        let harness = CaptureHarness()
        let model = makePipelineModel(harness: harness, profileStore: store, clock: clock, saveTimeout: 0.2)

        model.beginCapture(profile: a)
        harness.captures[0](.success(UIImage()))
        waitUntil { harness.saves.count == 1 }
        harness.saves[0](.success("asset-1"))

        let wait = expectation(description: "timeout window passes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { wait.fulfill() }
        self.wait(for: [wait], timeout: 2)

        XCTAssertEqual(model.captureFlights.first?.status, .saved)
        XCTAssertNil(model.captureError)
        XCTAssertEqual(model.inFlightSaveCount, 0)
    }

    /// A camera-level failure frees the shutter and leaves nothing in flight.
    func testCameraFailureLeavesNothingInFlight() throws {
        let (store, a, _, clock) = try twoProfiles()
        let harness = CaptureHarness()
        let model = makePipelineModel(harness: harness, profileStore: store, clock: clock)

        model.beginCapture(profile: a)
        harness.captures[0](.failure(.failed("x")))

        XCTAssertFalse(model.isShutterBusy, "129.5 the shutter never stays stuck")
        XCTAssertEqual(model.inFlightSaveCount, 0)
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

    // MARK: - 樣式／格式／位置 tab wiring (#65, P.2–P.4)

    func testStyleFormatPositionTabModelsAreNotNilOnceAProfileIsSelected() throws {
        // P.2
        let (model, _, _, _) = makeModel(now: try fixedNow())
        XCTAssertNotNil(model.styleTabModel)
        XCTAssertNotNil(model.formatTabModel)
        XCTAssertNotNil(model.positionTabModel)
    }

    func testStyleFormatPositionTabModelsTrackTheSelectedProfile() throws {
        // P.2
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        let firstStyle = try XCTUnwrap(model.styleTabModel)
        let firstFormat = try XCTUnwrap(model.formatTabModel)
        let firstPosition = try XCTUnwrap(model.positionTabModel)
        XCTAssertEqual(firstStyle.profile.id, model.selectedProfileID)
        XCTAssertEqual(firstFormat.displaySettings.profile.id, model.selectedProfileID)
        XCTAssertEqual(firstPosition.profile.id, model.selectedProfileID)

        let second = try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        waitUntil { model.selectedProfileID == second.id }

        let updatedStyle = try XCTUnwrap(model.styleTabModel)
        let updatedFormat = try XCTUnwrap(model.formatTabModel)
        let updatedPosition = try XCTUnwrap(model.positionTabModel)
        XCTAssertEqual(updatedStyle.profile.id, second.id)
        XCTAssertEqual(updatedFormat.displaySettings.profile.id, second.id)
        XCTAssertEqual(updatedPosition.profile.id, second.id)
    }

    func testStyleFormatPositionTabModelsKeepTheSameInstanceAcrossUnrelatedChanges() throws {
        // Same reasoning as `testStyleTabModelKeepsTheSameInstanceAcrossUnrelatedChanges`.
        let (model, _, _, _) = makeModel(now: try fixedNow())
        let firstStyle = try XCTUnwrap(model.styleTabModel)
        let firstFormat = try XCTUnwrap(model.formatTabModel)
        let firstPosition = try XCTUnwrap(model.positionTabModel)

        model.refreshOverlay() // bumps `refreshTick`, unrelated to the profile

        XCTAssertTrue(firstStyle === model.styleTabModel)
        XCTAssertTrue(firstFormat === model.formatTabModel)
        XCTAssertTrue(firstPosition === model.positionTabModel)
    }

    // MARK: - 拖曳轉接 (#65's `PositionDragAdapter`, equivalent to 24.8/24.9 — P.3, P.4)

    func testOverlayDragHandlerConvertsAViewfinderCenterDragIntoHalfHalf() throws {
        // P.3
        let now = try fixedNow()
        let store = makeProfileStore(now: now, seed: [
            CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1), position: .anchor(.middleCenter))
        ])
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        XCTAssertEqual(model.positionTabModel?.profile.position, .anchor(.middleCenter))

        let handler = try XCTUnwrap(model.panelModel.overlayDragHandler)
        handler.overlayDragEnded(center: CGPoint(x: 144, y: 192), viewfinderSize: CGSize(width: 288, height: 384))

        XCTAssertEqual(model.positionTabModel?.profile.position, .custom(x: 0.5, y: 0.5))
    }

    func testOverlayDragHandlerClampsADragThatEndsOutsideTheViewfinder() throws {
        // P.4
        let now = try fixedNow()
        let store = makeProfileStore(now: now, seed: [
            CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1), position: .anchor(.middleCenter))
        ])
        let (model, _, _, _) = makeModel(profileStore: store, now: now, fontLibrary: FakeShellFontLibrary([.huninn: .available]))

        let handler = try XCTUnwrap(model.panelModel.overlayDragHandler)
        // Past the 288x384 viewfinder.
        handler.overlayDragEnded(center: CGPoint(x: 400, y: 500),
                                 viewfinderSize: CGSize(width: 288, height: 384))

        guard case let .custom(x, y) = model.positionTabModel?.profile.position else {
            return XCTFail("expected a .custom position")
        }
        XCTAssertLessThanOrEqual(x, 1, "P.4")
        XCTAssertLessThanOrEqual(y, 1, "P.4")
    }

    // MARK: - 跨分頁不互相覆蓋 (#70, M.1–M.5)

    func testSequentialEditsAcrossAllThreeTabsAllSurvive() throws {
        // M.1
        let now = try fixedNow()
        let store = makeProfileStore(now: now, seed: [
            CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1))
        ])
        let (model, _, _, _) = makeModel(profileStore: store, now: now, fontLibrary: FakeShellFontLibrary([.huninn: .available]))

        model.styleTabModel?.selectFont(.huninn)
        model.positionTabModel?.selectAnchor(.bottomLeading)
        model.formatTabModel?.displaySettings.setShowDate(true)

        let stored = try XCTUnwrap(store.profiles.first)
        XCTAssertEqual(stored.style.fontID, .huninn, "M.1: 樣式改動仍在")
        XCTAssertEqual(stored.position, .anchor(.bottomLeading), "M.1: 位置改動仍在")
        XCTAssertTrue(stored.showDate, "M.1: 格式改動仍在")
    }

    func testSequentialEditsAcrossAllThreeTabsInReverseOrderAllSurvive() throws {
        // M.2
        let now = try fixedNow()
        let store = makeProfileStore(now: now, seed: [
            CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1))
        ])
        let (model, _, _, _) = makeModel(profileStore: store, now: now, fontLibrary: FakeShellFontLibrary([.huninn: .available]))

        model.formatTabModel?.displaySettings.setShowDate(true)
        model.positionTabModel?.selectAnchor(.bottomLeading)
        model.styleTabModel?.selectFont(.huninn)

        let stored = try XCTUnwrap(store.profiles.first)
        XCTAssertEqual(stored.style.fontID, .huninn, "M.2: 樣式改動仍在")
        XCTAssertEqual(stored.position, .anchor(.bottomLeading), "M.2: 位置改動仍在")
        XCTAssertTrue(stored.showDate, "M.2: 格式改動仍在")
    }

    func testDragThenStyleChangeKeepsTheDraggedPosition() throws {
        // M.3
        let now = try fixedNow()
        let store = makeProfileStore(now: now, seed: [
            CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1), position: .anchor(.middleCenter))
        ])
        let (model, _, _, _) = makeModel(profileStore: store, now: now, fontLibrary: FakeShellFontLibrary([.huninn: .available]))

        let handler = try XCTUnwrap(model.panelModel.overlayDragHandler)
        handler.overlayDragEnded(center: CGPoint(x: 144, y: 192), viewfinderSize: CGSize(width: 288, height: 384))
        model.styleTabModel?.selectFont(.huninn)

        let stored = try XCTUnwrap(store.profiles.first)
        XCTAssertEqual(stored.position, .custom(x: 0.5, y: 0.5), "M.3: 拖曳結果仍在")
        XCTAssertEqual(stored.style.fontID, .huninn)
    }

    func testRenamingOutsideThePanelThenChangingStyleKeepsTheNewName() throws {
        // M.4
        let now = try fixedNow()
        let store = makeProfileStore(now: now, seed: [
            CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1))
        ])
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        let selected = try XCTUnwrap(model.selectedProfile)

        // Simulates a rename from outside the panel (e.g. the management
        // list, TASK-26) — not through any tab model's own `updateProfile`.
        var renamed = selected
        renamed.name = "阿寶"
        try store.update(renamed)

        model.styleTabModel?.selectTextColor(.black)

        let stored = try XCTUnwrap(store.profiles.first)
        XCTAssertEqual(stored.name, "阿寶", "M.4: 面板外的改名仍在")
        XCTAssertEqual(stored.style.textColor, .black)
    }

    func testSwitchingToFormatTabAfterAStyleChangeDoesNotLoseTheStyleInTheStore() throws {
        // M.5: the store itself must never lose the style change — whether
        // `formatTabModel`'s own working copy also reflects it live is a
        // separate, ui-panel-owned concern (see this test's own comment).
        let now = try fixedNow()
        let store = makeProfileStore(now: now, seed: [
            CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1))
        ])
        let (model, _, _, _) = makeModel(profileStore: store, now: now, fontLibrary: FakeShellFontLibrary([.huninn: .available]))

        model.styleTabModel?.selectFont(.huninn)
        model.panelModel.selectedTab = .content // switching tabs never rebuilds (same profile)

        let stored = try XCTUnwrap(store.profiles.first)
        XCTAssertEqual(stored.style.fontID, .huninn, "M.5: store 端沒有遺失樣式改動")
        // Not asserted: `model.formatTabModel?.displaySettings.profile.style`
        // — `FormatTabView` never reads `style`/`position` today (grep
        // confirms), so this is not currently user-visible; syncing a tab's
        // own working copy live across tabs would need ui-panel to add a
        // refresh API to `DisplaySettingsModel`/`StyleTabModel`/
        // `PositionTabModel`/`RulesTabModel`, which this card does not do
        // (flagged to Lead per #70's own escape hatch).
    }

    // MARK: - Camera toolbar (PRD 0.2 FR-7, TASK-21 acceptance 21.1–21.5)

    private final class StubFlashCapabilityProvider: FlashCapabilityProviding {
        let hasFlash: Bool
        init(hasFlash: Bool) { self.hasFlash = hasFlash }
        func hasFlash(for facing: CameraFacing) -> Bool { hasFlash }
    }

    func testPresentProfileManagementOpensOnTheListWithPanelUntouched() throws {
        // 44.1/44.2 (replaces 21.1's menu items): the chip opens the sheet on
        // its list whatever the panel is doing, and leaves the panel alone.
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        model.openOverlayPanel()
        model.panelModel.selectedTab = .position
        model.profileManagerModel.edit(id: store.profiles[1].id)

        model.presentProfileManagement()

        XCTAssertTrue(model.isProfileManagerPresented)
        XCTAssertTrue(model.profileManagerModel.path.isEmpty)
        XCTAssertTrue(model.panelModel.isOpen)
        XCTAssertEqual(model.panelModel.selectedTab, .position)
    }

    func testEditPageWritesMergeOntoFieldsAnotherTabChanged() throws {
        // 44.11 (#70): the edit page's write must not revert a field another
        // tab wrote after the page's model was built.
        let now = try fixedNow()
        let store = makeProfileStore(now: now)
        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        let original = try XCTUnwrap(store.profiles.first)
        let rules = model.profileManagerModel.rulesModel(for: original)

        var other = original
        other.showDate = !original.showDate
        try store.update(other)
        rules.setName("改名")

        let saved = try XCTUnwrap(store.profiles.first)
        XCTAssertEqual(saved.name, "改名")
        XCTAssertEqual(saved.showDate, other.showDate, "showDate written elsewhere must survive")
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

    // MARK: - Ratio button cycling (PRD 0.2 FR-7.7, acceptance 90/B.2/B.5)

    func testCycleAspectRatioStepsThroughAllCasesInDeclaredOrder() throws {
        let (model, _, _, _) = makeModel(now: try fixedNow())
        XCTAssertEqual(model.captureSettingsStore.captureAspectRatio, .threeByFour)

        model.cycleAspectRatio()
        XCTAssertEqual(model.captureSettingsStore.captureAspectRatio, .oneByOne)

        model.cycleAspectRatio()
        XCTAssertEqual(model.captureSettingsStore.captureAspectRatio, .nineBySixteen)

        model.cycleAspectRatio()
        XCTAssertEqual(model.captureSettingsStore.captureAspectRatio, .threeByFour)
    }

    func testCycleAspectRatioPersistsAcrossRelaunch() throws {
        // 90/B.5: still backed by `CaptureSettingsStore`'s existing
        // `UserDefaults` persistence — cycling doesn't bypass it.
        let settings = CaptureSettingsStore(defaults: defaults)
        let (model, _, _, _) = makeModel(now: try fixedNow(), captureSettingsStore: settings)
        model.cycleAspectRatio()

        let relaunchedSettings = CaptureSettingsStore(defaults: defaults)
        XCTAssertEqual(relaunchedSettings.captureAspectRatio, .oneByOne)
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
        let (model, _, _, _) = makeModel(now: now, bake: { _, _, _, _, _, _ in baked })

        model.processCapturedImage(UIImage(), context: sampleContext(now))

        waitUntil { model.captureFlights.count == 1 }
        model.flightDidLand(id: model.captureFlights[0].id)
        XCTAssertNotNil(model.latestThumbnailImage)
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
                                      bake: { _, _, _, _, _, _ in UIImage() },
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
                                         bake: { _, text, _, _, _, _ in
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

    // MARK: - Launch thumbnail from the library (FR-15.2 second branch, issue #182)

    @MainActor
    private final class FakeThumbnailLibrary: GalleryLibrary {
        var status: PHAuthorizationStatus
        /// Newest first; an id missing from `images` has no loadable image.
        var items: [String]
        var images: [String: UIImage]
        private(set) var requestCount = 0

        init(status: PHAuthorizationStatus, items: [String] = [], images: [String: UIImage] = [:]) {
            self.status = status
            self.items = items
            self.images = images
        }

        func readStatus() -> PHAuthorizationStatus { status }
        func requestReadAccess() async -> PHAuthorizationStatus {
            requestCount += 1
            return status
        }
        /// Counts the pruning read (`photos()` drops ids from the store); the
        /// launch thumbnail must never use it.
        private(set) var photosCallCount = 0
        func latestVisiblePhotoIDs(limit: Int) -> [String] { Array(items.prefix(limit)) }
        func photos() -> [GalleryPhoto] {
            photosCallCount += 1
            return items.map { GalleryPhoto(id: $0, creationDate: nil) }
        }
        func deletePhoto(id: String) async -> Bool {
            items.removeAll { $0 == id }
            return true
        }
        /// When set, the next `image(id:)` captures its result, then waits for
        /// `resumeSuspendedImage()` — models a slow library read.
        var suspendNextImage = false
        private(set) var isSuspended = false
        private var continuation: CheckedContinuation<Void, Never>?

        func image(id: String, targetSize: CGSize) async -> UIImage? {
            let result = images[id]
            if suspendNextImage {
                suspendNextImage = false
                isSuspended = true
                await withCheckedContinuation { continuation = $0 }
                isSuspended = false
            }
            return result
        }

        func resumeSuspendedImage() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func solidImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    func testLaunchThumbnailUsesFirstPhotoWhenReadAccessGranted() async throws {
        let first = solidImage(.red)
        let library = FakeThumbnailLibrary(status: .authorized, items: ["a", "b", "c"],
                                           images: ["a": first, "b": solidImage(.green), "c": solidImage(.blue)])
        let (model, _, _, _) = makeModel(thumbnailLibrary: library)

        await model.loadLaunchThumbnail()

        XCTAssertTrue(model.latestThumbnailImage === first)
    }

    func testLaunchThumbnailUsesSecondPhotoWhenFirstIsGone() async throws {
        // The deleted first photo is simply no longer listed.
        let second = solidImage(.green)
        let library = FakeThumbnailLibrary(status: .authorized, items: ["b", "c"],
                                           images: ["b": second, "c": solidImage(.blue)])
        let (model, _, _, _) = makeModel(thumbnailLibrary: library)

        await model.loadLaunchThumbnail()

        XCTAssertTrue(model.latestThumbnailImage === second)
    }

    func testLaunchThumbnailSkipsAPhotoWhoseImageCannotBeLoaded() async throws {
        let second = solidImage(.green)
        let library = FakeThumbnailLibrary(status: .limited, items: ["a", "b"], images: ["b": second])
        let (model, _, _, _) = makeModel(thumbnailLibrary: library)

        await model.loadLaunchThumbnail()

        XCTAssertTrue(model.latestThumbnailImage === second)
    }

    func testLaunchThumbnailStaysIconWithoutReadAccessAndNeverPrompts() async throws {
        for status in [PHAuthorizationStatus.notDetermined, .denied, .restricted] {
            let library = FakeThumbnailLibrary(status: status, items: ["a"], images: ["a": solidImage(.red)])
            let (model, _, _, _) = makeModel(thumbnailLibrary: library)

            await model.loadLaunchThumbnail()

            XCTAssertNil(model.latestThumbnailImage, "status \(status.rawValue)")
            XCTAssertEqual(library.requestCount, 0, "status \(status.rawValue)")
        }
    }

    func testLaunchThumbnailDoesNotReplaceThisLaunchsBakedPhoto() throws {
        let now = try fixedNow()
        let library = FakeThumbnailLibrary(status: .authorized, items: ["a"], images: ["a": solidImage(.red)])
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(.success("asset-1")) },
                                         thumbnailLibrary: library)
        model.processCapturedImage(UIImage(), context: sampleContext(now))
        waitUntil { model.captureFlights.count == 1 }
        model.flightDidLand(id: try XCTUnwrap(model.captureFlights.first?.id))
        let baked = try XCTUnwrap(model.latestThumbnailImage)

        let loaded = expectation(description: "launch thumbnail load finished")
        Task {
            await model.loadLaunchThumbnail()
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 3)

        XCTAssertTrue(model.latestThumbnailImage === baked)
    }

    func testLaunchThumbnailNeverUsesThePruningRead() async throws {
        let library = FakeThumbnailLibrary(status: .limited, items: ["a"], images: ["a": solidImage(.red)])
        let (model, _, _, _) = makeModel(thumbnailLibrary: library)

        await model.loadLaunchThumbnail()
        await model.refreshThumbnailFromLibrary(replacingExisting: true)

        XCTAssertEqual(library.photosCallCount, 0)
    }

    func testFailedImageLoadKeepsTheCurrentThumbnail() async throws {
        let shown = solidImage(.red)
        let library = FakeThumbnailLibrary(status: .authorized, items: ["a", "b"], images: ["a": shown])
        let (model, _, _, _) = makeModel(thumbnailLibrary: library)
        await model.loadLaunchThumbnail()
        XCTAssertTrue(model.latestThumbnailImage === shown)

        library.images = [:] // e.g. iCloud offline: ids listed, nothing loads
        await model.refreshThumbnailFromLibrary(replacingExisting: true)

        XCTAssertTrue(model.latestThumbnailImage === shown)
    }

    func testStaleLaunchReadFinishingLateDoesNotOverwriteNewerRefresh() async throws {
        let stale = solidImage(.red)
        let fresh = solidImage(.green)
        let library = FakeThumbnailLibrary(status: .authorized, items: ["a", "b"], images: ["a": stale, "b": fresh])
        let (model, _, _, _) = makeModel(thumbnailLibrary: library)
        library.suspendNextImage = true
        let launch = Task { await model.loadLaunchThumbnail() }
        while !library.isSuspended { await Task.yield() }

        // The user deletes the newest photo and closes the gallery meanwhile.
        _ = await library.deletePhoto(id: "a")
        await model.refreshThumbnailFromLibrary(replacingExisting: true)
        XCTAssertTrue(model.latestThumbnailImage === fresh)

        library.resumeSuspendedImage()
        await launch.value

        XCTAssertTrue(model.latestThumbnailImage === fresh)
    }

    func testCaptureLandingDuringLibraryReadWins() throws {
        let now = try fixedNow()
        let library = FakeThumbnailLibrary(status: .authorized, items: ["a"], images: ["a": solidImage(.red)])
        let (model, _, _, _) = makeModel(now: now,
                                         bake: { _, _, _, _, _, _ in UIImage() },
                                         save: { _, completion in completion(.success("asset-1")) },
                                         thumbnailLibrary: library)
        library.suspendNextImage = true
        let finished = expectation(description: "launch read finished")
        Task {
            await model.loadLaunchThumbnail()
            finished.fulfill()
        }
        waitUntil { library.isSuspended }

        model.processCapturedImage(UIImage(), context: sampleContext(now))
        waitUntil { model.captureFlights.count == 1 }
        model.flightDidLand(id: try XCTUnwrap(model.captureFlights.first?.id))
        let baked = try XCTUnwrap(model.latestThumbnailImage)

        library.resumeSuspendedImage()
        wait(for: [finished], timeout: 3)

        XCTAssertTrue(model.latestThumbnailImage === baked)
    }

    func testClosingGalleryAfterDeletingNewestPhotoUpdatesThumbnail() async throws {
        let first = solidImage(.red)
        let second = solidImage(.green)
        let library = FakeThumbnailLibrary(status: .authorized, items: ["a", "b"], images: ["a": first, "b": second])
        let (model, _, _, _) = makeModel(thumbnailLibrary: library)
        await model.loadLaunchThumbnail()
        XCTAssertTrue(model.latestThumbnailImage === first)

        _ = await library.deletePhoto(id: "a")
        await model.refreshThumbnailFromLibrary(replacingExisting: true)
        XCTAssertTrue(model.latestThumbnailImage === second)

        _ = await library.deletePhoto(id: "b")
        await model.refreshThumbnailFromLibrary(replacingExisting: true)
        XCTAssertNil(model.latestThumbnailImage)
    }

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
}
