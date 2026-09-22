import Combine
import Foundation
import UIKit

/// Drives PRD S-1, the camera screen: camera lifecycle, permission/status
/// interpretation, the profile-driven overlay (TASK-08), the display-settings
/// sheet entry (TASK-11), the profile switcher (TASK-13), the shutter's
/// capture state machine (TASK-10) and the cross-midnight/foreground refresh
/// (TASK-14). `CameraScreen` only lays out whatever this model currently
/// says — see `docs/TASKS.md`'s note on why UI-level acceptance criteria
/// live here rather than in the view.
///
/// Like `ProfileListModel.adapting(to:)`, this is one of the boundary types
/// that does depend on `ProfileStore`'s concrete type — a screen-level model
/// has to be the place real services get wired together. It mirrors the
/// store's `@Published profiles`/`selectedProfileID` the same way that
/// adapter does.
@MainActor
final class CameraScreenModel: ObservableObject {
    let cameraService: CameraService
    private let profileStore: ProfileStore
    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer

    /// Mirrors `profileStore.profiles`. The caller (`DaysCamApp`) is expected
    /// to have already called `profileStore.load()` before building this
    /// model, so this starts non-empty (PRD §2.2/§4.3 guarantee at least one
    /// profile always exists).
    @Published private(set) var profiles: [CameraProfile] = []
    /// Mirrors `profileStore.selectedProfileID`.
    @Published private(set) var selectedProfileID: UUID?
    /// Non-nil while PRD S-4 (the display-settings sheet) should be shown.
    /// Built once per presentation and held here — same reasoning as
    /// `ProfileListModel.activeEditModel`: a `.sheet` content closure re-runs
    /// on unrelated `@Published` changes while the sheet is up (in
    /// particular `profiles`/`selectedProfileID` ticking from an unrelated
    /// store write), and rebuilding there would discard in-progress edits.
    @Published private(set) var displaySettingsModel: DisplaySettingsModel?
    /// Non-nil while PRD S-2 (the profile management list, reached via the
    /// switcher's "管理設定檔" entry) should be shown.
    @Published var isProfileListPresented = false

    /// Drives the management list. Built once and reused — unlike
    /// `displaySettingsModel`, this does not need to be rebuilt per
    /// presentation, since `ProfileListModel` already owns its own
    /// create/edit/delete sheet state independently of whether it is
    /// currently on screen.
    let profileListModel: ProfileListModel

    /// True from the moment the shutter is tapped until the photo pipeline
    /// finishes, success or failure (PRD FR-5.5: disabled while saving).
    @Published private(set) var isCapturing = false

    /// Everything from "image captured" through "baked and saved to the
    /// photo library," injected so this model is testable without the real
    /// `OverlayRenderer`/`PhotoSaver` — TASK-09's baking and TASK-10's own
    /// `PhotoSaver` (core-dev's half) are not available on this branch yet.
    ///
    /// The default is a placeholder that only calls `completion`, so the
    /// capture state machine (the debounce, the disabled-while-capturing
    /// shutter) is real and testable today; a follow-up commit replaces this
    /// with the real bake → save pipeline once those land. Nothing about the
    /// state machine changes when that happens — only what this closure does.
    private let photoPipeline: (UIImage, String, OverlayTheme, OverlayPosition, @escaping () -> Void) -> Void

    /// Bumped whenever the calendar day changes or the app returns to the
    /// foreground (TASK-14). `overlayText` already recomputes from the live
    /// clock on every access, so nothing about *that* was ever stale — the
    /// bug this fixes is that nothing told SwiftUI to ask again: none of
    /// this model's other `@Published` properties change just because time
    /// passed, so without this tick the viewfinder would keep showing
    /// whatever it last rendered until something unrelated (a profile edit,
    /// a permission change) happened to trigger a re-render. Nothing reads
    /// this value; its only job is to be `@Published` (PRD §6.4).
    @Published private(set) var refreshTick = 0

    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []

    init(cameraService: CameraService,
         profileStore: ProfileStore,
         calendar: Calendar = .current,
         calculator: DayCountCalculator = DayCountCalculator(),
         renderer: TemplateRenderer = TemplateRenderer(),
         photoPipeline: @escaping (UIImage, String, OverlayTheme, OverlayPosition, @escaping () -> Void) -> Void = { _, _, _, _, completion in completion() }) {
        self.cameraService = cameraService
        self.profileStore = profileStore
        self.calendar = calendar
        self.calculator = calculator
        self.renderer = renderer
        self.photoPipeline = photoPipeline
        self.profiles = profileStore.profiles
        self.selectedProfileID = profileStore.selectedProfileID
        self.profileListModel = ProfileListModel.adapting(to: profileStore, calendar: calendar)
        bindToProfileStore()
        bindToCameraService()
        bindToClockNotifications()
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func bindToProfileStore() {
        profileStore.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.profiles = $0 }
            .store(in: &cancellables)
        profileStore.$selectedProfileID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.selectedProfileID = $0 }
            .store(in: &cancellables)
    }

    /// Forwards `cameraService`'s own change notifications to this object's.
    ///
    /// `cameraService` is a nested `ObservableObject` read directly by both
    /// this model (`permission`, `status`, `isCaptureSupported`) and
    /// `CameraScreen` (`cameraService.permission.needsGuidance`) — but
    /// `CameraScreen` only `@ObservedObject`s *this* model, and SwiftUI has
    /// no idea a view depends on a second object nested inside the first.
    /// Without this, a permission grant/denial or a status change
    /// (`.idle` → `.running`, an interruption starting or ending) never
    /// triggers a re-render: the guidance screen wouldn't appear or
    /// disappear, and the shutter would stay disabled forever once `.running`
    /// is actually reached on a device (code review finding, verified by the
    /// team lead).
    private func bindToCameraService() {
        cameraService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Listens for the two clock-driven events that can make `overlayText`
    /// stale on screen (PRD §6.4, TASK-14): the calendar day rolling over
    /// while the app sits on the camera screen, and the app returning to the
    /// foreground after any amount of time away.
    private func bindToClockNotifications() {
        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(forName: .NSCalendarDayChanged,
                                                         object: nil,
                                                         queue: .main) { [weak self] _ in
            self?.refreshOverlay()
        })
        notificationObservers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                         object: nil,
                                                         queue: .main) { [weak self] _ in
            self?.refreshOverlay()
        })
    }

    /// Forces the viewfinder to re-render against the current moment.
    ///
    /// Exists as its own method (rather than inlined into the notification
    /// closures) so tests can call it directly without posting real
    /// `NotificationCenter` notifications.
    func refreshOverlay() {
        refreshTick += 1
    }

    /// Called when the screen appears. Permission is requested here, not at
    /// app launch (PRD §2.2).
    func onAppear() {
        cameraService.start()
    }

    /// Called when the screen disappears. Pairs with `onAppear` — per
    /// `CameraService.stop()`'s own doc comment, a screen that stops on
    /// backgrounding must call `onAppear` again on the way back.
    ///
    /// In the app as it stands today this effectively never fires:
    /// `CameraScreen` is the `WindowGroup`'s only, root-level view, so
    /// neither presenting a sheet over it nor backgrounding the app removes
    /// it from the view hierarchy (SwiftUI only calls `onDisappear` when a
    /// view actually leaves the hierarchy). Kept for correctness — a future
    /// multi-screen navigation would make it fire — and so `cameraService`
    /// isn't left running if that changes. Reacting to backgrounding itself
    /// is TASK-14's scope, not this one's.
    func onDisappear() {
        cameraService.stop()
    }

    func switchCamera() {
        cameraService.switchCamera()
    }

    /// The label the placeholder viewfinder shows in the simulator (PRD §2.4).
    static let simulatorPlaceholderText = "模擬器不支援拍照"

    /// Whether this build cannot capture at all (the simulator, PRD §2.4).
    /// Also decides whether the viewfinder shows the placeholder background.
    var isCaptureUnsupported: Bool {
        !cameraService.isCaptureSupported
    }

    /// Whether the app currently lacks camera permission — the guidance
    /// screen (PRD S-5) should cover the viewfinder in this state.
    var needsPermissionGuidance: Bool {
        cameraService.permission.needsGuidance
    }

    /// Whether the session is not actually showing a live picture right now:
    /// covers `.idle` (not started yet), `.interrupted` and every
    /// `.unavailable` reason alike.
    var isSessionNotRunning: Bool {
        cameraService.status != .running
    }

    /// Whether the viewfinder should show the simulator/placeholder
    /// background instead of a live preview (PRD §2.4).
    var showsPlaceholder: Bool {
        isCaptureUnsupported
    }

    /// Whether the shutter should be disabled right now.
    ///
    /// True whenever a live picture is not actually on screen (no capture
    /// support, permission not granted, session not `.running`), or while a
    /// capture is already in flight (PRD FR-5.5). Single source of truth for
    /// both the button's `.disabled` state and `capturePhoto()`'s own guard.
    var isShutterDisabled: Bool {
        isCaptureUnsupported || needsPermissionGuidance || isSessionNotRunning || isCapturing
    }

    /// A transient reason the viewfinder cannot show a live picture even
    /// though permission is fine — an interruption or a session failure
    /// (PRD §2.4). `nil` when nothing needs to be said (including the
    /// simulator, which has its own placeholder rather than this message).
    var statusMessage: String? {
        switch cameraService.status {
        case .interrupted, .unavailable(.sessionFailure), .unavailable(.noCaptureDevice):
            return "相機暫時無法使用"
        case .idle, .running, .unavailable(.simulator):
            return nil
        }
    }
}

// MARK: - Profile-driven overlay (TASK-08)

extension CameraScreenModel {
    /// The profile currently applied to the viewfinder, or `nil` only in the
    /// brief window before `profileStore.load()` has populated `profiles`
    /// (never observable once the app has actually launched, PRD FR-1.8).
    var selectedProfile: CameraProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    /// The overlay text for `selectedProfile` as of right now.
    ///
    /// Re-rendered on every access rather than cached, using
    /// `TemplateRenderer` directly — the same renderer TASK-10's shutter must
    /// call again at capture time (PRD §6.4), so the viewfinder is never the
    /// source of truth for what gets baked into the photo.
    var overlayText: String {
        guard let selectedProfile else { return "" }
        return renderer.render(profile: selectedProfile, capturedAt: calculator.now(), calendar: calendar)
    }

    /// The theme `selectedProfile` draws its overlay with.
    var overlayTheme: OverlayTheme {
        OverlayTheme.theme(for: selectedProfile?.themeID ?? .classicWhite)
    }

    /// The anchor point `selectedProfile` draws its overlay at.
    var overlayPosition: OverlayPosition {
        selectedProfile?.position ?? .bottomTrailing
    }
}

// MARK: - Display settings sheet (TASK-11)

extension CameraScreenModel {
    /// Whether PRD S-4 should be shown.
    var isDisplaySettingsPresented: Bool {
        displaySettingsModel != nil
    }

    /// Opens the display-settings sheet for the currently selected profile.
    /// A no-op in the brief window before any profile is selected.
    func presentDisplaySettings() {
        guard let selectedProfile else { return }
        displaySettingsModel = DisplaySettingsModel(profile: selectedProfile,
                                                    calendar: calendar,
                                                    calculator: calculator,
                                                    renderer: renderer) { [weak self] updated in
            try self?.profileStore.update(updated)
        }
    }

    func dismissDisplaySettings() {
        displaySettingsModel = nil
    }
}

// MARK: - Profile switcher (TASK-13)

extension CameraScreenModel {
    /// The label the switcher button shows, e.g. "預設" (PRD FR-1.4).
    var currentProfileName: String {
        selectedProfile?.name ?? ""
    }

    /// Switches the camera to `id` without leaving the camera screen
    /// (PRD FR-1.4). Forwards straight to the store, which also persists
    /// `lastUsedProfileID` (PRD FR-1.5) — this model does not repeat that.
    func selectProfile(id: UUID) {
        profileStore.select(id: id)
    }

    func presentProfileManagement() {
        isProfileListPresented = true
    }
}

// MARK: - Shutter (TASK-10)

extension CameraScreenModel {
    /// What the shutter would bake into a photo of `profile` taken right now.
    ///
    /// `capturedAt` comes from `calculator.now()` — the one place in the
    /// whole app that reads the clock for the photo pipeline (PRD §6.5.5,
    /// TASK-10 acceptance 10.4). `TemplateRenderer` never calls `Date()`
    /// itself, and neither will `OverlayRenderer` once it lands; both only
    /// ever receive `capturedAt` as a parameter.
    ///
    /// The text is rendered fresh on every call — never read from the
    /// already-computed `overlayText` — so two calls separated by the clock
    /// moving (a shutter press straddling midnight, PRD §6.4) or the profile
    /// changing produce different text instead of a stale, baked-in string
    /// (TASK-10 acceptance 10.3).
    ///
    /// Deliberately not `private`: `CameraService.capturePhoto` can only
    /// reach `.success` with a real capture device, which is unavailable in
    /// the simulator (same boundary `CameraServiceTests` documents), so this
    /// is what `CameraScreenModelTests` calls directly to verify 10.3/10.4
    /// without needing to drive a full capture through real hardware.
    func captureContext(for profile: CameraProfile) -> (capturedAt: Date, text: String, theme: OverlayTheme, position: OverlayPosition) {
        let capturedAt = calculator.now()
        let text = renderer.render(profile: profile, capturedAt: capturedAt, calendar: calendar)
        return (capturedAt, text, OverlayTheme.theme(for: profile.themeID), profile.position)
    }

    /// Triggers a capture.
    ///
    /// No-ops while `isShutterDisabled` (which already covers "a capture is
    /// already in flight," so this doubles as the FR-5.5 debounce) or before
    /// any profile is selected.
    func capturePhoto() {
        guard !isShutterDisabled, let selectedProfile else { return }
        isCapturing = true
        let context = captureContext(for: selectedProfile)

        cameraService.capturePhoto { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(image):
                self.photoPipeline(image, context.text, context.theme, context.position) { [weak self] in
                    self?.isCapturing = false
                }
            case .failure:
                // TASK-15 wires the PRD §7.3 error presentation; for now the
                // shutter simply becomes tappable again rather than staying
                // disabled forever.
                self.isCapturing = false
            }
        }
    }
}
