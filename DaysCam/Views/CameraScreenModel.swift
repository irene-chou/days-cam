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

    /// The pending capture-time failure alert, if any (PRD §7.3). `nil` when
    /// nothing should be shown.
    @Published private(set) var captureError: CaptureAlertError?

    /// Bakes the overlay into a captured image. Defaults to the real
    /// `OverlayRenderer`. Injectable so this model is testable without a
    /// real `UIGraphicsImageRenderer` pass, and so `capturePhoto()` can run
    /// it off the main thread without capturing `self` into a background
    /// closure (see `processCapturedImage`).
    private let bake: (UIImage, String, OverlayTheme, OverlayPosition) -> UIImage?

    /// Saves a baked photo to the system photo library. Defaults to the real
    /// `PhotoSaver`. Injectable for tests, and so `processCapturedImage` can
    /// call it from a background queue without capturing `self` (same
    /// reasoning as `bake`).
    private let save: (UIImage, @escaping (Result<Void, PhotoSaveError>) -> Void) -> Void

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

    /// How `presentSavedToast` schedules the toast's own auto-dismiss.
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
         calendar: Calendar = .autoupdatingCurrent,
         calculator: DayCountCalculator = DayCountCalculator(),
         renderer: TemplateRenderer = TemplateRenderer(),
         bake: @escaping (UIImage, String, OverlayTheme, OverlayPosition) -> UIImage? = { image, text, theme, position in
             OverlayRenderer().bake(image: image, text: text, theme: theme, position: position)
         },
         save: @escaping (UIImage, @escaping (Result<Void, PhotoSaveError>) -> Void) -> Void = { image, completion in
             PhotoSaver().save(image, completion: completion)
         },
         scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { work in
             DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
         }) {
        self.cameraService = cameraService
        self.profileStore = profileStore
        self.calendar = calendar
        self.calculator = calculator
        self.renderer = renderer
        self.bake = bake
        self.save = save
        self.scheduleToastDismiss = scheduleToastDismiss
        self.profiles = profileStore.profiles
        self.selectedProfileID = profileStore.selectedProfileID
        self.showsCorruptionRecoveredAlert = profileStore.didRecoverFromCorruption
        self.profileListModel = ProfileListModel.adapting(to: profileStore, calendar: calendar)
        bindToProfileStore()
        bindToCameraService()
        bindToClockNotifications()
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
        // TEMP(TASK-17): adapter until TASK-21/24 replaces this view layer
        return (capturedAt, text, OverlayTheme.theme(for: ThemeID(nearestTo: profile.style)), profile.position.legacyAnchor)
    }

    /// Triggers a capture.
    ///
    /// No-ops while `isShutterDisabled` (which already covers "a capture is
    /// already in flight," so this doubles as the FR-5.5 debounce) or before
    /// any profile is selected.
    func capturePhoto() {
        guard !isShutterDisabled, let selectedProfile else { return }
        isCapturing = true
        // Computed here, synchronously, on the main actor — before the
        // capture even starts, let alone before anything hops to a
        // background queue. `capturedAt` must be the instant the shutter was
        // pressed, not the instant baking happens to get around to running
        // (PRD §6.5.5, TASK-10 10.4).
        let context = captureContext(for: selectedProfile)

        cameraService.capturePhoto { [weak self] result in
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
                              context: (capturedAt: Date, text: String, theme: OverlayTheme, position: OverlayPosition)) {
        // Redundant with `capturePhoto()`'s own assignment in the real flow
        // (already `true` by the time this runs there) — kept here so this
        // method is self-contained: a test calling it directly exercises the
        // same `true` → `false` transition production code goes through,
        // rather than starting from (and asserting against) a value nobody
        // in the test ever set.
        isCapturing = true
        let bake = self.bake
        let save = self.save
        DispatchQueue.global(qos: .userInitiated).async {
            // core-dev's reminder: a 12MP photo in a wide-gamut color space
            // can make `UIGraphicsImageRenderer` pick a 16-bit format, ~97MB
            // per bake — without this, memory piles up across rapid presses
            // (PRD acceptance 10.22) instead of being reclaimed between them.
            let baked = autoreleasepool {
                bake(image, context.text, context.theme, context.position)
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
                // `PhotoSaver.save`'s completion already guarantees main —
                // deliberately not wrapped in another `DispatchQueue.main.async`
                // here, or the toast would appear one run-loop turn after
                // `isCapturing` resets, rather than in the same update.
                switch result {
                case .success:
                    self.presentSavedToast(thumbnail: thumbnail)
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

    /// Shows the "已儲存" confirmation toast and schedules it to fade out
    /// after 1.5 seconds (PRD FR-5.4). Called from `processCapturedImage`'s
    /// `save` completion on a successful save, with an already-downscaled
    /// thumbnail (never the full-resolution baked photo).
    ///
    /// Each call gets a fresh `ToastState.id`, so two saves close together
    /// restart the fade-out rather than comparing equal and no-oping (see
    /// `ToastState`'s own doc comment) — and the dismiss guards on that same
    /// `id`, so an older toast's timer firing late can't cut a newer one
    /// short (PRD acceptance 10.22: rapid shutter presses must not make the
    /// toast disappear early or stack up).
    func presentSavedToast(thumbnail: UIImage? = nil) {
        let state = ToastState(message: "已儲存", thumbnail: thumbnail)
        toastState = state
        scheduleToastDismiss { [weak self] in
            guard self?.toastState?.id == state.id else { return }
            self?.toastState = nil
        }
    }
}
