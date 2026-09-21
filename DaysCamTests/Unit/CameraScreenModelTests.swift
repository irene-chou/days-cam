import AVFoundation
import Combine
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
                           now: Date = Date()) -> (CameraScreenModel, CameraService, EmptyDeviceProvider, ProfileStore) {
        let authorizer = StubAuthorizer(status: status)
        let provider = EmptyDeviceProvider()
        let service = CameraService(authorizer: authorizer, deviceProvider: provider, isCaptureSupported: captureSupported)
        let store = profileStore ?? makeProfileStore(now: now)
        let model = CameraScreenModel(cameraService: service,
                                      profileStore: store,
                                      calendar: DateFixture.taipei,
                                      calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }))
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

    // MARK: - showsPlaceholder

    func testShowsPlaceholderWhenCaptureNotSupported() {
        let (model, _, _, _) = makeModel(captureSupported: false)
        XCTAssertTrue(model.showsPlaceholder)
    }

    func testDoesNotShowPlaceholderWhenCaptureSupported() {
        let (model, _, _, _) = makeModel(captureSupported: true)
        XCTAssertFalse(model.showsPlaceholder)
    }

    // MARK: - isShutterDisabled

    func testShutterDisabledWhenCaptureNotSupported() {
        let (model, _, _, _) = makeModel(captureSupported: false)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testShutterDisabledBeforeSessionStarts() {
        // captureSupported: true, but `onAppear` was never called, so status
        // is still `.idle` — the shutter must not be enabled before a live
        // picture is actually on screen.
        let (model, _, _, _) = makeModel(captureSupported: true)
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testShutterDisabledWhenPermissionDenied() {
        let (model, service, _, _) = makeModel(status: .denied, captureSupported: true)
        model.onAppear()
        waitUntil { service.permission == .denied }
        XCTAssertTrue(model.isShutterDisabled)
    }

    func testShutterDisabledWhenPermissionRestricted() {
        let (model, service, _, _) = makeModel(status: .restricted, captureSupported: true)
        model.onAppear()
        waitUntil { service.permission == .restricted }
        XCTAssertTrue(model.isShutterDisabled)
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
        // (PRD §6.4) — the store here is untouched between the two models.
        let seedDay = try fixedNow() // 2026-01-10
        let store = makeProfileStore(now: seedDay)
        let (dayOneModel, _, _, _) = makeModel(profileStore: store, now: seedDay)
        XCTAssertEqual(dayOneModel.overlayText, "第 1 天")

        let nextDay = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 8))
        let (dayTwoModel, _, _, _) = makeModel(profileStore: store, now: nextDay)
        XCTAssertEqual(dayTwoModel.overlayText, "第 2 天")
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
}
