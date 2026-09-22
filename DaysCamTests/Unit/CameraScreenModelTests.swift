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
                           scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { _ in }) -> (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore) {
        makeModel(status: status,
                 captureSupported: captureSupported,
                 profileStore: profileStore,
                 nowProvider: { now },
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
    private func makeModel(status: AVAuthorizationStatus = .notDetermined,
                           captureSupported: Bool = false,
                           profileStore: ProfileStore? = nil,
                           nowProvider: @escaping () -> Date,
                           scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { _ in }) -> (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore) {
        let authorizer = StubAuthorizer(status: status)
        let provider = EmptyDeviceProvider()
        let service = CameraService(authorizer: authorizer, deviceProvider: provider, isCaptureSupported: captureSupported)
        let store = profileStore ?? makeProfileStore(now: nowProvider())
        let model = CameraScreenModel(cameraService: service,
                                      profileStore: store,
                                      calendar: DateFixture.taipei,
                                      calculator: DayCountCalculator(calendar: DateFixture.taipei, now: nowProvider),
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
                                   position: .topLeading,
                                   themeID: .retroOrange)
        second = try store.add(second) // FR-1.10: add also auto-selects it

        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        XCTAssertEqual(model.selectedProfileID, second.id)
        XCTAssertEqual(model.overlayPosition, .topLeading)
        XCTAssertEqual(model.overlayTheme.id, .retroOrange)

        store.select(id: defaultProfile.id)
        // The mirroring sink is dispatched via `.receive(on: .main)`, so it
        // needs a main-queue pump before it is observable, same as
        // `ProfileListModelProfileStoreAdapterTests`.
        waitUntil { model.selectedProfileID == defaultProfile.id }
        XCTAssertEqual(model.overlayPosition, .bottomTrailing)
        XCTAssertEqual(model.overlayTheme.id, .classicWhite)
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
        styled.themeID = .filmStrip
        styled.position = .topLeading
        try store.update(styled)

        let (model, _, _, _) = makeModel(profileStore: store, now: now)
        let context = model.captureContext(for: styled)
        XCTAssertEqual(context.theme.id, .filmStrip)
        XCTAssertEqual(context.position, .topLeading)
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

    // MARK: - Saved toast (TASK-15, PRD FR-5.4)

    func testPresentSavedToastShowsTheConfirmationMessage() throws {
        let (model, _, _, _) = makeModel(now: try fixedNow())
        model.presentSavedToast()
        XCTAssertEqual(model.toastState?.message, "已儲存")
    }

    func testPresentSavedToastCarriesTheThumbnail() throws {
        let (model, _, _, _) = makeModel(now: try fixedNow())
        let thumbnail = UIImage()
        model.presentSavedToast(thumbnail: thumbnail)
        XCTAssertTrue(model.toastState?.thumbnail === thumbnail)
    }

    func testPresentSavedToastDismissesWhenTheScheduledCallbackFires() throws {
        let spy = SchedulerSpy()
        let (model, _, _, _) = makeModel(now: try fixedNow(), scheduleToastDismiss: spy.schedule)

        model.presentSavedToast()
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

        model.presentSavedToast()
        let firstID = model.toastState?.id
        model.presentSavedToast()
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

        XCTAssertEqual(DisplayUnitTrack.legalPairs.count, 8)
        for pair in DisplayUnitTrack.legalPairs {
            future.largestUnit = pair.largest
            future.smallestUnit = pair.smallest
            try store.update(future)
            XCTAssertEqual(model.overlayText, "尚未開始",
                           "largest=\(pair.largest) smallest=\(pair.smallest)")
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
}
