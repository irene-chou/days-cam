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
    /// The camera tools' state (PRD 0.2 §4.4): flash, timer, aspect ratio,
    /// grid. Exposed (not `private`) the same way `cameraService` is, so
    /// `CameraToolbar` can read it directly; this model forwards its change
    /// notifications the same way it does for `cameraService`
    /// (`bindToCaptureSettingsStore`).
    let captureSettingsStore: CaptureSettingsStore
    /// Where a successful save's asset identifier is recorded (PRD 0.2
    /// FR-15.1). Reading it directly (e.g. the gallery in TASK-29) never
    /// needs this model.
    let capturedPhotoStore: CapturedPhotoStore
    private let profileStore: ProfileStore
    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer
    /// Crops a captured 4:3 photo to `captureSettingsStore.captureAspectRatio`
    /// before it is baked (PRD 0.2 FR-5.7′: "先裁再烘焙"). Defaults to the
    /// real `ImageCropper`. Injectable so tests can confirm the pipeline
    /// crops before baking without depending on real pixel math (already
    /// covered by `ImageCropperTests`).
    private let crop: (UIImage, CaptureAspectRatio) -> UIImage
    /// Drives the timer countdown (PRD 0.2 FR-7.6). Defaults to the real
    /// `SystemCountdownTicker`. Injectable so tests can advance the
    /// countdown one tick at a time instead of waiting on a real clock.
    private let countdownTicker: CountdownTicker

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

    /// Drives the overlay panel's shell (PRD 0.2 FR-8, TASK-22): whether
    /// it's open and which first-level tab is selected. Built once and
    /// reused, same reasoning as `profileListModel` — it owns no data that
    /// depends on `selectedProfile`, so there is nothing to go stale.
    let panelModel = OverlayPanelModel()

    /// The 天數規則 tab's model (PRD 0.2 FR-13, TASK-25's `RulesTabView`).
    /// Rebuilt only when `selectedProfileID` actually changes — same
    /// reasoning as `displaySettingsModel`'s own doc comment: the panel's
    /// tab-content closure re-runs on unrelated `@Published` changes while
    /// it's on screen, and rebuilding a fresh `RulesTabModel` on every one of
    /// those would discard an in-progress name edit each time.
    @Published private(set) var rulesTabModel: RulesTabModel?

    /// True from the moment the shutter is tapped until the photo pipeline
    /// finishes, success or failure (PRD FR-5.5: disabled while saving).
    @Published private(set) var isCapturing = false

    /// The pending capture-time failure alert, if any (PRD §7.3). `nil` when
    /// nothing should be shown.
    @Published private(set) var captureError: CaptureAlertError?

    /// The remaining whole seconds of an in-progress timer countdown (PRD 0.2
    /// FR-7.6); `nil` when no countdown is running. Set the instant the
    /// shutter starts one (before the first tick), then ticks down once per
    /// second via `countdownTicker` until it reaches `nil`, at which point
    /// the photo is actually captured.
    @Published private(set) var countdownRemaining: Int?

    /// The most recently baked photo from *this app launch*, held in memory
    /// (PRD 0.2 FR-15.2's first branch — needs no photo-library read
    /// permission). `nil` until the first successful save; the bottom bar's
    /// thumbnail button falls back to the photo icon while it is `nil`.
    ///
    /// Deliberately does not yet implement FR-15.2's second branch ("has read
    /// permission → the newest surviving `capturedAssetIDs` entry's photo") —
    /// that needs a `PHAsset` thumbnail loader this codebase does not have
    /// yet, and belongs with the gallery infrastructure TASK-29 is already
    /// building. Flagged as an assumption in this PR's description.
    @Published private(set) var latestThumbnailImage: UIImage?

    /// Bakes the overlay into a captured image. Defaults to the real
    /// `OverlayRenderer`. Injectable so this model is testable without a
    /// real `UIGraphicsImageRenderer` pass, and so `capturePhoto()` can run
    /// it off the main thread without capturing `self` into a background
    /// closure (see `processCapturedImage`).
    private let bake: (UIImage, String, OverlayStyle, OverlayPlacement) -> UIImage?

    /// Saves a baked photo to the system photo library, returning its new
    /// `PHAsset.localIdentifier` on success (PRD 0.2 FR-15.1). Defaults to
    /// the real `PhotoSaver.saveReturningIdentifier`. Injectable for tests,
    /// and so `processCapturedImage` can call it from a background queue
    /// without capturing `self` (same reasoning as `bake`).
    private let save: (UIImage, @escaping (Result<String, PhotoSaveError>) -> Void) -> Void

    /// Fires the actual shutter. Defaults to `cameraService.capturePhoto`
    /// (set in `init` rather than in the parameter list, since the default
    /// has to close over the specific `cameraService` instance this model
    /// was built with — unlike `bake`/`save`/`crop`, which each construct an
    /// unrelated fresh object). Injectable so `CameraScreenModelTests` can
    /// exercise the countdown state machine (acceptance 19.8–19.10) end to
    /// end without needing `cameraService.status == .running`, which — like
    /// every other real-hardware path in this app — cannot be reached from a
    /// unit test (same boundary `CameraServiceTests` documents).
    private let captureImage: (FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void

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

    /// True for the one launch right after `profileStore.load()` found an
    /// unreadable `profiles.json` and silently re-seeded (PRD §7.3, TASK-15
    /// acceptance 15.1). Captured once at `init` rather than mirrored from
    /// `profileStore.$didRecoverFromCorruption` — the store only ever sets
    /// this during `load()`, which has already happened by the time this
    /// model is constructed, so it can't change again during this launch,
    /// and capturing it once is what keeps the alert from reappearing if
    /// `profiles` happens to re-publish later for an unrelated reason.
    @Published private(set) var showsCorruptionRecoveredAlert: Bool

    /// The pending "已儲存" toast, if any (PRD FR-5.4). `nil` when nothing
    /// should be shown.
    @Published private(set) var toastState: ToastState?

    /// How `showToast` schedules the toast's own auto-dismiss.
    /// Injected so tests don't have to wait a real 1.5 seconds; the default
    /// is the real delay.
    ///
    /// Pre-existing "passing non-sendable parameter 'work' to function
    /// expecting a @Sendable closure" warning here (present since `d2d7329`,
    /// before this file's `bake`/`processCapturedImage` work): marking `work`
    /// `@Sendable` to silence it turns out to be a real fix, not a
    /// formality — the default implementation's dismiss closure mutates
    /// `self.toastState`, a main-actor-isolated property, and `@Sendable`
    /// makes the compiler correctly refuse that from what it then treats as
    /// a "could run anywhere" closure. Fixing it properly needs
    /// `@MainActor @Sendable` on the parameter (the closure is Sendable *and*
    /// guaranteed to run on the main actor) plus checking every call site
    /// still type-checks — left alone for now to keep this PR to its actual
    /// scope; tracked as a follow-up.
    private let scheduleToastDismiss: (@escaping () -> Void) -> Void

    private var cancellables = Set<AnyCancellable>()

    /// - Parameter calendar: Defaults to `.autoupdatingCurrent`, not
    ///   `.current`. `.current` is a snapshot taken once, at call time — a
    ///   user who launches the app in Taipei and later opens it again in New
    ///   York would still have the overlay compute midnight in Taipei,
    ///   silently violating PRD §6.3's "the day count follows the device's
    ///   current time zone" (a review finding; PRD §6.3 was corrected to
    ///   name `.autoupdatingCurrent` explicitly). Tests still pass a pinned
    ///   `Calendar` (e.g. `DateFixture.taipei`), which is unaffected.
    init(cameraService: CameraService,
         profileStore: ProfileStore,
         captureSettingsStore: CaptureSettingsStore = CaptureSettingsStore(),
         capturedPhotoStore: CapturedPhotoStore = CapturedPhotoStore(),
         calendar: Calendar = .autoupdatingCurrent,
         calculator: DayCountCalculator = DayCountCalculator(),
         renderer: TemplateRenderer = TemplateRenderer(),
         crop: @escaping (UIImage, CaptureAspectRatio) -> UIImage = { image, aspectRatio in
             ImageCropper().crop(image, to: aspectRatio)
         },
         countdownTicker: CountdownTicker = SystemCountdownTicker(),
         bake: @escaping (UIImage, String, OverlayStyle, OverlayPlacement) -> UIImage? = { image, text, style, placement in
             OverlayRenderer().bake(image: image, text: text, style: style, placement: placement)
         },
         save: @escaping (UIImage, @escaping (Result<String, PhotoSaveError>) -> Void) -> Void = { image, completion in
             PhotoSaver().saveReturningIdentifier(image, completion: completion)
         },
         captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil,
         scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { work in
             DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
         }) {
        self.cameraService = cameraService
        self.captureSettingsStore = captureSettingsStore
        self.capturedPhotoStore = capturedPhotoStore
        self.profileStore = profileStore
        self.calendar = calendar
        self.calculator = calculator
        self.renderer = renderer
        self.crop = crop
        self.countdownTicker = countdownTicker
        self.bake = bake
        self.save = save
        self.captureImage = captureImage ?? { [cameraService] flashMode, completion in
            cameraService.capturePhoto(flashMode: flashMode, completion: completion)
        }
        self.scheduleToastDismiss = scheduleToastDismiss
        self.profiles = profileStore.profiles
        self.selectedProfileID = profileStore.selectedProfileID
        self.showsCorruptionRecoveredAlert = profileStore.didRecoverFromCorruption
        self.profileListModel = ProfileListModel.adapting(to: profileStore, calendar: calendar)
        bindToProfileStore()
        bindToCameraService()
        bindToCaptureSettingsStore()
        bindToClockNotifications()
        refreshRulesTabModelIfNeeded()
    }

    private func bindToProfileStore() {
        profileStore.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.profiles = $0 }
            .store(in: &cancellables)
        profileStore.$selectedProfileID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.selectedProfileID = $0
                self?.refreshRulesTabModelIfNeeded()
            }
            .store(in: &cancellables)
    }

    /// Rebuilds `rulesTabModel` only when `selectedProfileID` has actually
    /// changed since it was last built — see `rulesTabModel`'s own doc
    /// comment for why that matters.
    private func refreshRulesTabModelIfNeeded() {
        guard rulesTabModel?.profile.id != selectedProfileID else { return }
        guard let selectedProfile else {
            rulesTabModel = nil
            return
        }
        rulesTabModel = RulesTabModel(profile: selectedProfile,
                                     calendar: calendar,
                                     calculator: calculator,
                                     renderer: renderer) { [weak self] updated in
            try self?.profileStore.update(updated)
        }
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

    /// Same reasoning as `bindToCameraService`: `captureSettingsStore` is a
    /// nested `ObservableObject`, and `CameraToolbar` only observes this
    /// model, so a flash/timer/ratio/grid change would never trigger a
    /// re-render without forwarding it here.
    private func bindToCaptureSettingsStore() {
        captureSettingsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Listens for the two clock-driven events that can make `overlayText`
    /// stale on screen (PRD §6.4, TASK-14): the calendar day rolling over
    /// while the app sits on the camera screen, and the app returning to the
    /// foreground after any amount of time away.
    ///
    /// Goes through `NotificationCenter.default.publisher(for:)` rather than
    /// the closure-based `addObserver(forName:object:queue:using:)` on
    /// purpose: that API's closure is `nonisolated`, so calling
    /// `refreshOverlay()` (a main-actor method) from inside it is only a
    /// warning today but an error under the Swift 6 language mode (review
    /// finding). The publisher form's `.receive(on:)` keeps the delivery
    /// hop explicit and lets Combine (not a raw `queue:` argument) do the
    /// actor hop, and folds the subscriptions into `cancellables` — no
    /// separate observer bookkeeping or `deinit` needed.
    private func bindToClockNotifications() {
        let center = NotificationCenter.default
        center.publisher(for: .NSCalendarDayChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshOverlay() }
            .store(in: &cancellables)
        center.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshOverlay() }
            .store(in: &cancellables)
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

    /// The style `selectedProfile` draws its overlay with (PRD 0.2 §4.2).
    var overlayStyle: OverlayStyle {
        selectedProfile?.style ?? OverlayStyle()
    }

    /// Where `selectedProfile` draws its overlay: a grid anchor or a custom
    /// center (PRD 0.2 §4.1).
    var overlayPlacement: OverlayPlacement {
        selectedProfile?.position ?? .default
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

    /// The profile switcher's menu items: exactly the profiles, in
    /// `ProfileStore`'s order, with no synthetic "manage profiles" entry
    /// mixed in — that entry point moves to the bottom bar's own key
    /// (TASK-26), so 0.2's menu is just names (PRD 0.2 FR-7.11, acceptance
    /// 21.1).
    var profileMenuItems: [CameraProfile] {
        profiles
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

// MARK: - Camera toolbar (PRD 0.2 FR-7, TASK-21)

extension CameraScreenModel {
    /// Whether the flash button should be disabled: the front camera, or a
    /// back camera with no flash unit (PRD 0.2 FR-7.4, acceptance 21.2).
    var isFlashToolDisabled: Bool {
        !cameraService.isFlashAvailable
    }

    /// Whether the flash icon should render in the `active` color (PRD 0.2
    /// FR-7.10, acceptance 21.3): on whenever the mode isn't `.off`, even if
    /// `isFlashToolDisabled` — the front camera still shows what it's set
    /// to, it just can't fire it.
    var isFlashToolActive: Bool {
        captureSettingsStore.flashMode != .off
    }

    /// Whether the timer icon should render in the `active` color (PRD 0.2
    /// FR-7.10, acceptance 21.3).
    var isTimerToolActive: Bool {
        captureSettingsStore.timerSeconds != .off
    }

    /// Whether the grid icon should render in the `active` color (PRD 0.2
    /// FR-7.10, acceptance 21.3).
    var isGridToolActive: Bool {
        captureSettingsStore.showsGrid
    }

    /// Cycles the flash button (PRD 0.2 FR-7.4). A no-op while
    /// `isFlashToolDisabled` is not enforced here — the button itself is
    /// disabled in the view, matching every other disabled control in this
    /// model (e.g. the shutter).
    func cycleFlash() {
        captureSettingsStore.cycleFlash()
    }

    /// Cycles the timer button 關 → 3 秒 → 10 秒 → 關 (PRD 0.2 FR-7.5).
    func cycleTimer() {
        captureSettingsStore.cycleTimer()
    }

    /// Selects the capture aspect ratio (PRD 0.2 FR-7.7).
    func selectAspectRatio(_ ratio: CaptureAspectRatio) {
        captureSettingsStore.setAspectRatio(ratio)
    }

    /// Flips the grid overlay (PRD 0.2 FR-7.9).
    func toggleGrid() {
        captureSettingsStore.toggleGrid()
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
    func captureContext(for profile: CameraProfile) -> (capturedAt: Date, text: String, style: OverlayStyle, placement: OverlayPlacement) {
        let capturedAt = calculator.now()
        let text = renderer.render(profile: profile, capturedAt: capturedAt, calendar: calendar)
        return (capturedAt, text, profile.style, profile.position)
    }

    /// Triggers a capture, or cancels an in-progress timer countdown (PRD 0.2
    /// FR-7.6).
    ///
    /// While `countdownRemaining != nil` this always cancels, regardless of
    /// `isShutterDisabled` — the countdown itself already proved the shutter
    /// was enabled when it started, and a disabled check here would strand
    /// the countdown with no way to cancel it if some other state changed
    /// mid-count (acceptance 19.9).
    ///
    /// Otherwise a no-op while `isShutterDisabled` (which already covers "a
    /// capture is already in flight," so this doubles as the FR-5.5
    /// debounce) or before any profile is selected.
    func capturePhoto() {
        guard countdownRemaining == nil else {
            cancelCountdown()
            return
        }
        guard !isShutterDisabled, let selectedProfile else { return }
        beginCapture(profile: selectedProfile)
    }

    /// Starts capturing `profile`: immediately when
    /// `captureSettingsStore.timerSeconds == .off` (exactly like before
    /// TASK-21), otherwise it starts the countdown and the real capture
    /// happens only once `tickCountdown` reaches zero (PRD 0.2 FR-7.6).
    ///
    /// Deliberately not `private`, for the same reason `captureContext(for:)`
    /// below is not: reaching this from a real `capturePhoto()` call needs
    /// `cameraService.status == .running`, unavailable without real capture
    /// hardware (same boundary `CameraServiceTests` documents). This is what
    /// `CameraScreenModelTests` calls directly to drive the countdown state
    /// machine end to end (acceptance 19.8–19.10) with an injected
    /// `countdownTicker`/`captureImage`, without needing a real device.
    func beginCapture(profile: CameraProfile) {
        let seconds = captureSettingsStore.timerSeconds.rawValue
        guard seconds > 0 else {
            performCapture(profile: profile)
            return
        }
        countdownRemaining = seconds
        countdownTicker.start { [weak self] in
            self?.tickCountdown(profile: profile)
        }
    }

    /// One second of an in-progress countdown (PRD 0.2 FR-7.6, acceptance
    /// 19.8): decrements `countdownRemaining`, and on the tick that reaches
    /// zero, stops the ticker, clears `countdownRemaining` to `nil` and
    /// triggers the real capture — never before then, so the overlay's date
    /// and day count are computed from the instant the countdown actually
    /// finishes, not the instant the shutter was first pressed (PRD §6.4,
    /// acceptance 19.10).
    private func tickCountdown(profile: CameraProfile) {
        guard let remaining = countdownRemaining else { return }
        let next = remaining - 1
        guard next > 0 else {
            countdownTicker.stop()
            countdownRemaining = nil
            performCapture(profile: profile)
            return
        }
        countdownRemaining = next
    }

    /// Cancels an in-progress countdown without capturing (PRD 0.2 FR-7.6,
    /// acceptance 19.9).
    private func cancelCountdown() {
        countdownTicker.stop()
        countdownRemaining = nil
        showToast(message: "已取消")
    }

    /// Actually fires the shutter — either immediately (no timer) or once a
    /// countdown reaches zero.
    private func performCapture(profile: CameraProfile) {
        isCapturing = true
        // Computed here, synchronously, on the main actor — before the
        // capture even starts, let alone before anything hops to a
        // background queue. `capturedAt` must be the instant the shutter
        // actually fires, not the instant the shutter was first pressed if a
        // countdown was running (PRD §6.5.5, TASK-10 10.4, 0.2 acceptance
        // 19.10).
        let context = captureContext(for: profile)
        let flashMode = captureSettingsStore.flashMode

        captureImage(flashMode) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(image):
                self.processCapturedImage(image, context: context)
            case .failure:
                // A pre-TASK-9/10 capture-level failure (no hardware, not
                // running, AVFoundation error). Not one of PRD §7.3's named
                // scenarios (those are the bake/save failures the pipeline
                // below reports) — the shutter simply becomes tappable again
                // rather than staying disabled forever, same as any other
                // completion.
                self.isCapturing = false
            }
        }
    }

    /// Bakes `image` and saves the result, off the main thread (baking a
    /// 12-megapixel photo measured ~60–80ms in the simulator; core-dev's own
    /// numbers for a real device were pending as of this commit, but
    /// stalling the main thread for that long every shutter press is not
    /// acceptable regardless).
    ///
    /// `bake` and `save` are captured into locals *before* dispatching
    /// rather than referenced as `self.bake`/`self.save` from inside the
    /// background closure: `self` is `@MainActor`-isolated, and the
    /// background closure must not touch it until the explicit hop back to
    /// `DispatchQueue.main` for the bake-failure branch below (the
    /// save-completion branch needs no such hop — see its own comment).
    /// `bake`/`save` are themselves just plain function values once
    /// captured, not main-actor-isolated accesses.
    ///
    /// Deliberately not `private`: reaching this from a real `capturePhoto()`
    /// call needs `cameraService.status == .running`, which — like
    /// `captureContext(for:)` above — is unavailable without real capture
    /// hardware (same boundary `CameraServiceTests` documents). This is what
    /// `CameraScreenModelTests` calls directly to verify the bake-failure,
    /// save-success and save-failure branches, and that `isCapturing` ends
    /// up `false` on every one of them (PRD acceptance 10.22).
    func processCapturedImage(_ image: UIImage,
                              context: (capturedAt: Date, text: String, style: OverlayStyle, placement: OverlayPlacement)) {
        // Redundant with `capturePhoto()`'s own assignment in the real flow
        // (already `true` by the time this runs there) — kept here so this
        // method is self-contained: a test calling it directly exercises the
        // same `true` → `false` transition production code goes through,
        // rather than starting from (and asserting against) a value nobody
        // in the test ever set.
        isCapturing = true
        let crop = self.crop
        let bake = self.bake
        let save = self.save
        let aspectRatio = captureSettingsStore.captureAspectRatio
        DispatchQueue.global(qos: .userInitiated).async {
            // core-dev's reminder: a 12MP photo in a wide-gamut color space
            // can make `UIGraphicsImageRenderer` pick a 16-bit format, ~97MB
            // per bake — without this, memory piles up across rapid presses
            // (PRD acceptance 10.22) instead of being reclaimed between them.
            let baked = autoreleasepool { () -> UIImage? in
                // Crop first, then bake (PRD 0.2 FR-5.7′): the overlay's
                // margin and font size are derived from the *cropped*
                // image's short edge, matching what the viewfinder already
                // showed for the same aspect ratio (FR-5.9, FR-5.11).
                let cropped = crop(image, aspectRatio)
                return bake(cropped, context.text, context.style, context.placement)
            }
            guard let baked else {
                // PRD §7.3: baking failure. Not saved, no success toast.
                DispatchQueue.main.async { [weak self] in
                    self?.captureError = CaptureAlertError(message: "照片處理失敗，請再試一次。",
                                                           showsSettingsAction: false)
                    self?.isCapturing = false
                }
                return
            }
            // Downscaled here, off the main thread, alongside the bake work
            // it depends on — a 12MP `UIImage` is not something the toast
            // should hold onto full-size for its 1.5 seconds on screen just
            // to draw it at 44x44 (review-anticipated finding).
            let thumbnail = Self.thumbnail(of: baked)

            save(baked) { [weak self] result in
                guard let self else { return }
                // `PhotoSaver.saveReturningIdentifier`'s completion already
                // guarantees main — deliberately not wrapped in another
                // `DispatchQueue.main.async` here, or the toast would appear
                // one run-loop turn after `isCapturing` resets, rather than
                // in the same update.
                switch result {
                case let .success(assetID):
                    // PRD 0.2 FR-15.1/FR-15.2: record the new asset so the
                    // gallery (TASK-29) can find it later, and update the
                    // in-memory thumbnail immediately — this is the "captured
                    // this launch" branch FR-15.2 wants shown without any
                    // read permission.
                    self.capturedPhotoStore.recordCapturedAsset(assetID)
                    self.latestThumbnailImage = thumbnail
                    self.showToast(message: "已儲存", thumbnail: thumbnail)
                case let .failure(error):
                    self.captureError = CaptureAlertError(message: error.displayMessage,
                                                          showsSettingsAction: error.showsSettingsAction)
                }
                self.isCapturing = false
            }
        }
    }

    /// A small copy of `image`, for the toast (PRD FR-5.4) — never the
    /// full-resolution baked photo.
    private static func thumbnail(of image: UIImage, maxDimension: CGFloat = 88) -> UIImage {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image }
        let scale = maxDimension / largestSide
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

// MARK: - Error handling & toast (TASK-15)

extension CameraScreenModel {
    /// Dismisses the one-time data-recovery alert (PRD §7.3, 15.1). Call
    /// when the user taps the alert's only button.
    func dismissCorruptionRecoveredAlert() {
        showsCorruptionRecoveredAlert = false
    }

    /// Dismisses a capture-time failure alert (PRD §7.3, TASK-10).
    func dismissCaptureError() {
        captureError = nil
    }

    /// Shows a transient confirmation toast and schedules it to fade out
    /// after 1.5 seconds (PRD FR-5.4, 0.2 FR-7.6's "已取消"). Called from
    /// `processCapturedImage`'s `save` completion on a successful save (with
    /// an already-downscaled thumbnail, never the full-resolution baked
    /// photo) and from `cancelCountdown()` (no thumbnail).
    ///
    /// Each call gets a fresh `ToastState.id`, so two toasts close together
    /// restart the fade-out rather than comparing equal and no-oping (see
    /// `ToastState`'s own doc comment) — and the dismiss guards on that same
    /// `id`, so an older toast's timer firing late can't cut a newer one
    /// short (PRD acceptance 10.22: rapid shutter presses must not make the
    /// toast disappear early or stack up).
    func showToast(message: String, thumbnail: UIImage? = nil) {
        let state = ToastState(message: message, thumbnail: thumbnail)
        toastState = state
        scheduleToastDismiss { [weak self] in
            guard self?.toastState?.id == state.id else { return }
            self?.toastState = nil
        }
    }
}
