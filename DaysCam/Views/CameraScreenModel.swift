import Combine
import Foundation
import UIKit

/// Drives PRD S-1, the camera screen: camera lifecycle, permission/status
/// interpretation, the profile-driven overlay (TASK-08), the profile
/// switcher (TASK-13), the management panel entry (TASK-26), the shutter's
/// capture state machine (TASK-10) and the cross-midnight/foreground refresh
/// (TASK-14). `CameraScreen` only lays out whatever this model currently
/// says — see `docs/TASKS.md`'s note on why UI-level acceptance criteria
/// live here rather than in the view.
///
/// Like `ProfileManagerModel`, this is one of the boundary types
/// that does depend on `ProfileStore`'s concrete type — a screen-level model
/// has to be the place real services get wired together. It mirrors the
/// store's `@Published profiles`/`selectedProfileID` the same way that
/// adapter does.
@MainActor
final class CameraScreenModel: ObservableObject {
    let cameraService: CameraService
    /// Pinch-to-zoom state of the viewfinder (TASK-61). Only `isPinching` is
    /// forwarded to this object's changes (the overlay drag switch reads it);
    /// the rest changes every frame of a pinch and is observed by the capsule
    /// alone (issue #280).
    let zoomModel: ViewfinderZoomModel
    /// Tap-to-focus, exposure drag and AE/AF lock on the viewfinder (issue
    /// #303). Observed by `FocusExposureOverlay` alone, so a drag redraws
    /// only that.
    let focusModel: ViewfinderFocusModel
    #if DEBUG
    private let fakeFocusBackend: FakeFocusExposureBackend?
    #endif
    /// Whether the quick-zoom capsule is open (issue #302).
    let zoomExpansion = ZoomPresetExpansion()
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
    /// Where each overlay font's availability, download and launch
    /// preparation come from (PRD 0.3). The real `FontLibrary` in the app;
    /// tests inject a fake.
    let fontLibrary: any FontShellControlling
    /// Seconds the shutter waits for a `preparing` font before giving up and
    /// drawing PingFang (PRD 0.3 FR-5.15). Injectable so tests need not wait
    /// the real 3 seconds.
    private let fontPreparationTimeout: TimeInterval
    /// Turns a style's font and weight into the face to draw
    /// (`OverlayMetrics.resolvedFont(for: style, ...)` in the app).
    /// Injectable so tests can resolve to a face that ships with iOS instead
    /// of a downloaded one.
    private let resolveFont: @MainActor (OverlayStyle, any FontAvailabilityProviding) -> ResolvedOverlayFont
    /// "Profile → font" the user asked for that is still downloading; the
    /// download finishing writes it (PRD 0.3 FR-5.18, A-8). One entry per
    /// profile, the last request wins. Owned here, not by the font list, so
    /// closing the list changes nothing (FR-16.11).
    private var pendingFontApplications: [UUID: OverlayFontID] = [:]
    /// Fonts whose launch/switch preparation ran past the timeout; the
    /// shutter no longer waits for them (they still resolve to PingFang until
    /// `available`).
    private var timedOutPreparingFonts: Set<FontDownloadID> = []
    private var preparationTimeoutTasks: [FontDownloadID: Task<Void, Never>] = [:]
    /// The profile the font hooks last saw as current.
    private var lastSeenProfileID: UUID?
    /// Profile/font pairs the "needs re-download" notice was already shown
    /// for during this launch (FR-16.14: once).
    private var noticedUnavailableFonts: Set<UnavailableFontNotice> = []
    private struct UnavailableFontNotice: Hashable {
        let profileID: UUID
        let fontID: OverlayFontID
    }
    private let makeGalleryModel: @MainActor (CapturedPhotoStore) -> GalleryModel
    private let makeThumbnailLibrary: @MainActor (CapturedPhotoStore) -> GalleryLibrary
    private var didLoadLaunchThumbnail = false
    /// Bumped by every library refresh; only the newest request may write.
    private var thumbnailRefreshGeneration = 0
    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer
    /// Picks the crop window for a captured photo of the given pixel size at
    /// `captureSettingsStore.captureAspectRatio` (PRD 0.2 FR-5.7′). The
    /// window is handed to `bake`, which crops and draws in one pass
    /// (TASK-128). Defaults to `ImageCropper.cropRect`. Injectable so tests
    /// can confirm what `bake` receives without depending on real pixel math
    /// (already covered by `ImageCropperTests`).
    private let cropRect: (CGSize, CaptureAspectRatio) -> CGRect
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
    /// Whether the management panel (PRD 0.2 FR-9, S-6) is showing.
    @Published var isProfileManagerPresented = false
    /// The photo browsing screen (TASK-29), presented full screen once read
    /// access has been answered (`openGallery()`).
    @Published var isGalleryPresented = false
    /// The browsing screen's model, created fresh each time it opens.
    private(set) var galleryModel: GalleryModel?

    /// Whether the flash／timer／grid capsule below the toolbar is showing
    /// (issue #135). Never persisted: every launch starts collapsed.
    @Published private(set) var isCameraToolsExpanded = false

    /// Drives the 設定檔 sheet. Built once and reused: it mirrors the store
    /// itself, so there is nothing to go stale between presentations. Its
    /// edit page writes through a `TabProfileWriter` (#70, R-8).
    private(set) lazy var profileManagerModel = ProfileManagerModel(
        store: profileStore,
        calculator: calculator,
        renderer: renderer,
        makeRulesModel: { [weak self] profile in
            guard let self else { return RulesTabModel(profile: profile) { _ in } }
            let writer = TabProfileWriter(baseline: profile, profileStore: self.profileStore)
            return RulesTabModel(profile: profile,
                                 calendar: self.calendar,
                                 calculator: self.calculator,
                                 renderer: self.renderer,
                                 updateProfile: writer.write)
        }
    )

    /// Drives the overlay panel's shell (PRD 0.2 FR-8, TASK-22): whether
    /// it's open and which first-level tab is selected. Built once and
    /// reused, same reasoning as `profileManagerModel` — it owns no data that
    /// depends on `selectedProfile`, so there is nothing to go stale.
    let panelModel = OverlayPanelModel()

    /// The first-launch two-step spotlight (TASK-96, #400). Its changes are
    /// forwarded to this object's `objectWillChange` (see
    /// `bindToOnboarding`), the same way `cameraService`'s are, so
    /// `CameraScreen` re-renders when a step changes.
    let onboarding: OnboardingSpotlightModel
    /// Where the overlay text block currently sits, in the viewfinder's
    /// coordinates; the view keeps it current (TASK-105). Not published: it
    /// only gates touches and must not redraw anything.
    var overlayTextFrame: CGRect = .null

    /// The 樣式 tab's model (PRD 0.2 FR-10, TASK-23's `StyleTabView`).
    /// Rebuilt only when `selectedProfileID` actually changes — see
    /// `refreshOverlayPanelTabModelsIfNeeded`.
    @Published private(set) var styleTabModel: StyleTabModel?

    /// The 格式 tab's model (PRD 0.2 FR-11, TASK-24's `FormatTabView`).
    /// Rebuilt alongside `styleTabModel`.
    @Published private(set) var formatTabModel: FormatTabModel?
    /// The content tab's writer, kept so its baseline can follow the store
    /// when the tab takes over an external change (TASK-109).
    private var formatWriter: TabProfileWriter?

    /// The 位置 tab's model (PRD 0.2 FR-12, TASK-24's `PositionTabView`).
    /// Rebuilt alongside `styleTabModel`; `panelModel.overlayDragHandler` is
    /// kept pointed at a fresh `PositionDragAdapter` wrapping this instance
    /// every time it changes (see `positionDragAdapter`).
    @Published private(set) var positionTabModel: PositionTabModel?

    /// Bridges `panelModel.overlayDragHandler`'s translation-based reports to
    /// `positionTabModel`'s center-based `applyDrag` (#65's "轉接"). Held
    /// strongly here — `overlayDragHandler` is `weak` (see its own doc
    /// comment), so nothing else keeps this alive.
    private var positionDragAdapter: PositionDragAdapter?

    /// True from the moment the shutter fires until AVFoundation hands back
    /// the photo (or fails), success or failure. Only this span keeps the
    /// shutter from firing again (PRD FR-5.5, as read by TASK-129, #469);
    /// baking and saving are counted by `inFlightSaveCount`.
    @Published private(set) var isCapturing = false

    /// How many captured photos are still being baked or saved. Goes up when
    /// a photo arrives from the camera and down when that photo's bake fails
    /// or its save calls back, success or failure.
    @Published private(set) var inFlightSaveCount = 0

    /// The most photos baked or saved at once; at the limit the shutter stays
    /// disabled so full-resolution images cannot pile up in memory (~100MB
    /// each, TASK-129 assumption).
    static let maxInFlightSaves = 2

    /// Whether a capture or a full pipeline keeps the shutter disabled.
    var isShutterBusy: Bool {
        isCapturing || inFlightSaveCount >= Self.maxInFlightSaves
    }

    /// How long a photo may wait for its save to call back before it is given
    /// up on (TASK-151, #529).
    static let defaultSaveTimeout: TimeInterval = 30
    private let saveTimeout: TimeInterval

    /// One photo's place among the in-flight ones. Settled exactly once: by
    /// the save's callback, or by the timeout if that never comes.
    final class SaveSlot {
        private(set) var isSettled = false
        /// The pending timeout. Its closure captures the slot, so `settle()`
        /// must drop it or the two keep each other alive.
        var timeout: DispatchWorkItem?

        /// Marks the slot answered, cancels the timeout and breaks the
        /// slot ↔ timeout cycle. Every path that ends a save calls this.
        func settle() {
            isSettled = true
            timeout?.cancel()
            timeout = nil
        }
    }

    /// Bakes one photo at a time, in capture order.
    private let pipelineQueue = DispatchQueue(label: "dayscam.capture-pipeline", qos: .userInitiated)

    /// The pending capture-time failure alert, if any (PRD §7.3). `nil` when
    /// nothing should be shown.
    @Published private(set) var captureError: CaptureAlertError?

    /// Photos that failed since the failure alert was last dismissed.
    private var unacknowledgedFailureCount = 0

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
    /// Before anything is captured this launch it is filled from the photo
    /// library (FR-15.2's second branch) by `loadLaunchThumbnail()`, but only
    /// when read access was already granted — never by asking for it
    /// (FR-15.3). Closing the gallery re-reads it, so deleting the newest
    /// photo there updates the thumbnail (`dismissGallery()`).
    @Published private(set) var latestThumbnailImage: UIImage?

    /// Photos currently flying from the viewfinder into the thumbnail
    /// button, one entry per capture (issue #148). Replaces the old save-confirmation
    /// toast on success. `CaptureFlightView` plays each one and reports back
    /// through `flightDidLand(id:)`/`removeCaptureFlight(id:)`.
    @Published private(set) var captureFlights: [CaptureFlight] = []

    /// Bumped the instant the shutter really fires — no timer: when the
    /// button is pressed; with a timer: when the countdown reaches zero.
    /// Never bumped while counting down or on cancel. The view flashes the
    /// viewfinder and plays the light haptic off this (issue #148).
    @Published private(set) var captureTriggerCount = 0

    /// Speaks `message` to VoiceOver (a no-op when it is off). Replaceable so
    /// tests can observe the call without posting a real notification.
    var announce: (String) -> Void = { message in
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// Bumped each time a landed flight replaces `latestThumbnailImage`, so
    /// the thumbnail button can play its small bounce.
    @Published private(set) var thumbnailLandingCount = 0

    /// Bakes the overlay into a captured image. Defaults to the real
    /// `OverlayRenderer`. Injectable so this model is testable without a
    /// real `UIGraphicsImageRenderer` pass, and so `capturePhoto()` can run
    /// it off the main thread without capturing `self` into a background
    /// closure (see `processCapturedImage`).
    private let bake: (UIImage, String, OverlayStyle, OverlayPlacement, ResolvedOverlayFont, CGRect?) -> UIImage?

    /// Saves a baked photo to the system photo library, returning its new
    /// `PHAsset.localIdentifier` on success (PRD 0.2 FR-15.1). Defaults to
    /// the real `PhotoSaver.saveReturningIdentifier`. Injectable for tests,
    /// and so `processCapturedImage` can call it from a background queue
    /// without capturing `self` (same reasoning as `bake`).
    private let save: (UIImage, @escaping (Result<String, PhotoSaveError>) -> Void) -> Void

    /// Fires the actual shutter. Defaults to `cameraService.capturePhoto`
    /// (set in `init` rather than in the parameter list, since the default
    /// has to close over the specific `cameraService` instance this model
    /// was built with — unlike `bake`/`save`/`cropRect`, which each construct an
    /// unrelated fresh object). Injectable so `CameraScreenModelTests` can
    /// exercise the countdown state machine (acceptance 19.8–19.10) end to
    /// end without needing `cameraService.status == .running`, which — like
    /// every other real-hardware path in this app — cannot be reached from a
    /// unit test (same boundary `CameraServiceTests` documents).
    private let captureImage: (FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void

    /// Tells the camera which flash mode the next photo will use, so the photo
    /// output can prepare for it (TASK-130). Defaults to
    /// `cameraService.prepareCapture`; injectable so tests can see the calls.
    private let prepareCapture: (FlashMode) -> Void

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

    /// The pending toast (only "已取消" now), if any (PRD FR-5.4). `nil` when nothing
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
    private var saveFailureToastPending = false
    /// Whether the app is in the foreground and active; injectable for tests.
    private let isApplicationActive: () -> Bool

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
         cropRect: @escaping (CGSize, CaptureAspectRatio) -> CGRect = { pixelSize, aspectRatio in
             ImageCropper.cropRect(forPixelSize: pixelSize, ratio: aspectRatio)
         },
         countdownTicker: CountdownTicker = SystemCountdownTicker(),
         bake: @escaping (UIImage, String, OverlayStyle, OverlayPlacement, ResolvedOverlayFont, CGRect?) -> UIImage? = { image, text, style, placement, font, cropRect in
             OverlayRenderer().bake(image: image, text: text, style: style, placement: placement, font: font, cropRect: cropRect)
         },
         save: @escaping (UIImage, @escaping (Result<String, PhotoSaveError>) -> Void) -> Void = { image, completion in
             PhotoSaver().saveReturningIdentifier(image, completion: completion)
         },
         captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil,
         prepareCapture: ((FlashMode) -> Void)? = nil,
         isApplicationActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active },
         scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { work in
             DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
         },
         makeGalleryModel: @escaping @MainActor (CapturedPhotoStore) -> GalleryModel = { store in
             GalleryModel(library: SystemGalleryLibrary(store: store))
         },
         makeThumbnailLibrary: @escaping @MainActor (CapturedPhotoStore) -> GalleryLibrary = { store in
             SystemGalleryLibrary(store: store)
         },
         fontLibrary: (any FontShellControlling)? = nil,
         onboarding: OnboardingSpotlightModel = OnboardingSpotlightModel(),
         fontPreparationTimeout: TimeInterval = FontLibrary.defaultLaunchTimeout,
         saveTimeout: TimeInterval = CameraScreenModel.defaultSaveTimeout,
         resolveFont: @escaping @MainActor (OverlayStyle, any FontAvailabilityProviding) -> ResolvedOverlayFont = {
             OverlayMetrics.resolvedFont(for: $0, availability: $1)
         }) {
        self.resolveFont = resolveFont
        self.saveTimeout = saveTimeout
        self.onboarding = onboarding
        self.fontLibrary = fontLibrary ?? InertFontLibrary()
        self.fontPreparationTimeout = fontPreparationTimeout
        self.makeGalleryModel = makeGalleryModel
        self.makeThumbnailLibrary = makeThumbnailLibrary
        self.cameraService = cameraService
        #if DEBUG
        let fakeFocusBackend = FakeFocusExposureBackend.isEnabled ? FakeFocusExposureBackend() : nil
        self.fakeFocusBackend = fakeFocusBackend
        #endif
        let focusActions = FocusExposureActions(
            focusAndExpose: { [cameraService] in cameraService.focusAndExpose(at: $0) },
            lock: { [cameraService] in cameraService.lockFocusAndExposure(at: $0) },
            setBias: { [cameraService] in cameraService.setExposureBias($0) },
            setBiasForRequest: { [cameraService] in cameraService.setExposureBias($0, forFocusRequestID: $1) },
            deviceBiasRange: { [cameraService] in cameraService.exposureBiasRange })
        let focusModel: ViewfinderFocusModel
        #if DEBUG
        if let fakeFocusBackend {
            // No camera to convert with: the fake takes the point as a share
            // of the viewfinder.
            focusModel = ViewfinderFocusModel(
                actions: fakeFocusBackend.actions,
                convert: { point, size in
                    size.width > 0 && size.height > 0 ? CGPoint(x: point.x / size.width, y: point.y / size.height) : nil
                },
                // Slow simulators need time to find the reticle; the fade-out
                // test asks for the real one.
                hideDelay: ProcessInfo.processInfo.arguments.contains("-UITestFocusQuickFade") ? .seconds(2) : .seconds(60))
            fakeFocusBackend.attach(focusModel)
        } else {
            focusModel = ViewfinderFocusModel(actions: focusActions)
        }
        #else
        focusModel = ViewfinderFocusModel(actions: focusActions)
        #endif
        self.focusModel = focusModel
        self.zoomModel = ViewfinderZoomModel(initialFactor: cameraService.zoomFactor,
                                             zoomRange: { [cameraService] in
                                                 Self.usesUITestZoomPlan ? ZoomRange(minimum: 0.5, maximum: 10) : cameraService.zoomRange
                                             },
                                             applyFactor: { [cameraService] in cameraService.setZoomFactor($0) },
                                             applyPreset: { [cameraService, focusModel] in
                                                 // A new lens starts at continuous auto (issue #303).
                                                 focusModel.hideReticle()
                                                 cameraService.setZoom(displayFactor: $0, animated: true)
                                             })
        self.captureSettingsStore = captureSettingsStore
        self.capturedPhotoStore = capturedPhotoStore
        self.profileStore = profileStore
        self.calendar = calendar
        self.calculator = calculator
        self.renderer = renderer
        self.cropRect = cropRect
        self.countdownTicker = countdownTicker
        self.bake = bake
        self.save = save
        self.captureImage = captureImage ?? { [cameraService] flashMode, completion in
            cameraService.capturePhoto(flashMode: flashMode, completion: completion)
        }
        self.prepareCapture = prepareCapture ?? { [cameraService] flashMode in
            cameraService.prepareCapture(flashMode: flashMode)
        }
        self.isApplicationActive = isApplicationActive
        self.scheduleToastDismiss = scheduleToastDismiss
        self.profiles = profileStore.profiles
        self.selectedProfileID = profileStore.selectedProfileID
        self.lastSeenProfileID = profileStore.selectedProfileID
        self.showsCorruptionRecoveredAlert = profileStore.didRecoverFromCorruption
        bindToProfileStore()
        bindToCameraService()
        bindToZoomModel()
        bindToFocusModel()
        bindToCaptureSettingsStore()
        bindToFlashMode()
        bindToPanelModel()
        bindToClockNotifications()
        bindToFontLibrary()
        bindToOnboarding()
        refreshOverlayPanelTabModelsIfNeeded()
        // The launch-time preparation of the current profile's font starts
        // counting its 3 seconds now (FR-5.15); `prepareFontsAtLaunch()`
        // does the actual work.
        if let style = selectedProfile?.style {
            startPreparationTimeoutIfNeeded(for: Self.downloadID(of: style))
        }
    }

    /// Shows the save-failed toast held back while the app was inactive, if
    /// the failure is still unresolved. Internal so tests can call it.
    func showPendingSaveFailureToast() {
        guard saveFailureToastPending, profileStore.lastWriteError != nil else {
            saveFailureToastPending = false
            return
        }
        saveFailureToastPending = false
        showToast(message: Self.profileSaveFailedMessage)
    }

    /// Shown when the profile file could not be written.
    static let profileSaveFailedMessage = "無法儲存設定"

    private func bindToProfileStore() {
        profileStore.$profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profiles in
                guard let self else { return }
                self.profiles = profiles
                // The style tab's own copy must pick up a font written outside
                // it (`applyFont`; PRD 0.3 FR-5.18).
                if let styleTabModel = self.styleTabModel,
                   let latest = profiles.first(where: { $0.id == styleTabModel.profile.id }) {
                    styleTabModel.applyExternalChanges(from: latest)
                }
                // The content tab's 名稱 switch is the edit page's 寫在照片上
                // (TASK-109): whichever wrote last, the other shows it.
                if let formatTabModel = self.formatTabModel,
                   let latest = profiles.first(where: { $0.id == formatTabModel.displaySettings.profile.id }) {
                    self.formatWriter?.adopt(latest)
                    formatTabModel.displaySettings.applyExternalChanges(from: latest)
                }
            }
            .store(in: &cancellables)
        // Profile writes are debounced (#464), so a failed save no longer
        // surfaces as a throw from `update`; this is where the user hears of
        // it. Only failing/not-failing is compared, not the error text (it
        // carries a random temp file name): one failure shows once, however
        // many retries fail again, and a successful retry re-arms it.
        profileStore.$lastWriteError
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasError in
                guard let self else { return }
                guard hasError else {
                    self.saveFailureToastPending = false
                    return
                }
                // The 設定檔 sheet covers the screen's toast, and every
                // add／duplicate／delete／reorder／edit there now looks
                // successful to `ProfileManagerModel`: use the sheet's own
                // alert, which stays until dismissed.
                if self.isProfileManagerPresented {
                    self.profileManagerModel.lastError = self.profileStore.lastWriteError
                        ?? ProfileStoreError.writeFailed("")
                    return
                }
                // A flush on the way to the background fails while nobody is
                // looking, and the toast would time out before they return:
                // hold it until the app is active again.
                if self.isApplicationActive() {
                    self.showToast(message: Self.profileSaveFailedMessage)
                } else {
                    self.saveFailureToastPending = true
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.showPendingSaveFailureToast() }
            .store(in: &cancellables)
        profileStore.$selectedProfileID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.selectedProfileID = $0
                self?.refreshOverlayPanelTabModelsIfNeeded()
                self?.selectedProfileDidChange()
            }
            .store(in: &cancellables)
    }

    /// Rebuilds every overlay-panel tab model — `styleTabModel`,
    /// `formatTabModel` and `positionTabModel` (plus its drag adapter) — only
    /// when `selectedProfileID` has actually changed since they were last
    /// built (rebuilding on every unrelated re-render would discard whatever
    /// the user is mid-edit on).
    ///
    /// All three are rebuilt together, gated on the same check, so they can
    /// never point at different profiles at once.
    ///
    /// Each tab model holds its own full `CameraProfile` copy and always
    /// calls its `updateProfile` closure with that *entire* copy, even
    /// though any one mutation only ever touches the handful of fields that
    /// tab actually owns (樣式 → `style`; 位置 → `position`; 格式 →
    /// `showDayCount`/`showDate`/`showName`/`displayUnits`/`useAgeWording`,
    /// and also `position`/`style`, as `DisplaySettingsModel` carries them; 天數規則 → `name`/`startDate`/
    /// `countingRule`). Passing that closure straight to
    /// `profileStore.update` would blindly overwrite the store's current
    /// record with this tab's own copy, silently reverting whatever fields
    /// a *different* tab (or a rename elsewhere) wrote in the
    /// meantime — exactly #70's reported bug. Every closure below instead
    /// goes through a `TabProfileWriter` (this file's own type, just below),
    /// which merges only the fields that changed since that tab's own last
    /// write onto the store's current record.
    private func refreshOverlayPanelTabModelsIfNeeded() {
        guard styleTabModel?.profile.id != selectedProfileID else { return }
        guard let selectedProfile else {
            styleTabModel = nil
            formatTabModel = nil
            positionTabModel = nil
            positionDragAdapter = nil
            panelModel.overlayDragHandler = nil
            return
        }

        let styleWriter = TabProfileWriter(baseline: selectedProfile, profileStore: profileStore)
        styleTabModel = StyleTabModel(
            profile: selectedProfile,
            fontLibrary: fontLibrary,
            applyFont: { [weak self] fontID, profileID in
                self?.applyFont(fontID, profileID: profileID)
            },
            allProfiles: { [weak self] in self?.profiles ?? [] },
            updateProfile: { [weak self] profile in
                let previous = self?.profileStore.profiles.first { $0.id == profile.id }
                try styleWriter.write(profile)
                // A weight chosen in the font list writes font and weight
                // without `applyFont`; it is the newest font choice for this
                // profile, so a download still pending for it must not land
                // afterwards (#458).
                if let previous,
                   previous.style.fontID != profile.style.fontID
                    || previous.style.fontWeight != profile.style.fontWeight {
                    self?.pendingFontApplications[profile.id] = nil
                }
            })

        let formatWriter = TabProfileWriter(baseline: selectedProfile, profileStore: profileStore)
        self.formatWriter = formatWriter
        let displaySettings = DisplaySettingsModel(profile: selectedProfile,
                                                   calendar: calendar,
                                                   calculator: calculator,
                                                   renderer: renderer,
                                                   updateProfile: formatWriter.write)
        formatTabModel = FormatTabModel(displaySettings: displaySettings)

        let positionWriter = TabProfileWriter(baseline: selectedProfile, profileStore: profileStore)
        let newPositionTabModel = PositionTabModel(profile: selectedProfile, updateProfile: positionWriter.write)
        positionTabModel = newPositionTabModel
        let adapter = PositionDragAdapter(positionTabModel: newPositionTabModel)
        positionDragAdapter = adapter
        panelModel.overlayDragHandler = adapter
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

    /// Makes the tour's fresh-install decision, forwards its changes like
    /// `bindToCameraService` does, and feeds it every camera permission
    /// value: a due tour starts once the permission prompt has been
    /// answered — granted or denied — never while the system prompt is
    /// still up (TASK-96, 96.8, 96.16, 96.17).
    /// `CameraService.publish(permission:)` already delivers on the main
    /// queue.
    private func bindToOnboarding() {
        // The one-time fresh-install decision (#400): `ProfileStore.load()`
        // already ran in `DaysCamApp` by the time this model exists.
        onboarding.decideIfNeeded(isFreshInstall: profileStore.didSeedFreshInstall)
        onboarding.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cameraService.$permission
            .sink { [weak self] permission in self?.onboarding.cameraPermissionDidChange(permission) }
            .store(in: &cancellables)
    }

    /// The quick-zoom buttons the current camera offers (issue #279); empty
    /// until a camera is configured.
    var zoomPresets: [ZoomPreset] {
        Self.usesUITestZoomPlan ? Self.uiTestZoomPresets : cameraService.availableZoomPresets
    }

    /// The simulator has no camera and so no zoom plan; the UI tests pass
    /// `-UITestZoomPresets` to get a fixed one (issue #302). Debug builds only.
    private static let uiTestZoomPresets = [ZoomPreset(displayFactor: 0.5),
                                            ZoomPreset(displayFactor: 1),
                                            ZoomPreset(displayFactor: 2)]
    private static var usesUITestZoomPlan: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITestZoomPresets")
        #else
        false
        #endif
    }

    /// Forwards only `isPinching` (issue #280), and starts the next pinch at
    /// 1× after a camera switch, which resets the zoom.
    private func bindToZoomModel() {
        zoomModel.$isPinching
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cameraService.$facing
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.zoomModel.resetRequestedFactor() }
            .store(in: &cancellables)
    }

    /// Feeds the service's focus/exposure answers to `focusModel`, and tells it
    /// when a gesture may start and when the camera changes under it.
    private func bindToFocusModel() {
        focusModel.canAcceptGesture = { [weak self] in
            guard let self else { return false }
            guard !panelModel.isOpen, !isCameraToolsExpanded, !zoomExpansion.isExpanded else { return false }
            #if DEBUG
            if fakeFocusBackend != nil { return true }
            #endif
            return !isCaptureUnsupported && !needsPermissionGuidance && !isSessionNotRunning
        }
        focusModel.isPinching = { [weak self] in self?.zoomModel.isPinching ?? false }
        focusModel.shouldIgnoreTouch = { [weak self] in self?.viewfinderTouchStartsOnOverlayText(at: $0) ?? false }
        cameraService.focusExposureStatePublisher
            .sink { [weak self] in self?.focusModel.receive($0) }
            .store(in: &cancellables)
        cameraService.focusExposureTapResetPublisher
            .sink { [weak self] in self?.focusModel.receiveTapReset(appliedRequestID: $0) }
            .store(in: &cancellables)
        cameraService.focusExposureResetPublisher
            .sink { [weak self] in self?.focusModel.receiveReset(appliedRequestID: $0) }
            .store(in: &cancellables)
        cameraService.focusExposureFailurePublisher
            .sink { [weak self] _ in self?.focusModel.receiveFailure() }
            .store(in: &cancellables)
        cameraService.$facing
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.focusModel.hideReticle() }
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

    /// Prepares the photo output for the flash mode now selected and for each
    /// later change (TASK-130). The current value is delivered at once; the
    /// camera remembers it until its session is configured.
    private func bindToFlashMode() {
        captureSettingsStore.$flashMode
            .removeDuplicates()
            .sink { [weak self] flashMode in self?.prepareCapture(flashMode) }
            .store(in: &cancellables)
    }

    /// Same reasoning as `bindToCameraService`: `CameraScreen` and
    /// `OverlayPanelView` observe only this model and read `panelModel`'s
    /// state through it, so opening/closing the panel or switching tabs would
    /// never re-render without forwarding the nested model's changes here
    /// (PR #60 review).
    private func bindToPanelModel() {
        panelModel.objectWillChange
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
        prepareCapture(captureSettingsStore.flashMode)
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
        collapseCameraTools()
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
        isCaptureUnsupported || needsPermissionGuidance || isSessionNotRunning || isShutterBusy
            || isWaitingForFont
    }

    /// Whether the current profile's font is still being matched after
    /// launch or a profile switch, within its 3 seconds (PRD 0.3 FR-5.15):
    /// the shutter waits so a photo is never baked in PingFang by mistake.
    var isWaitingForFont: Bool {
        guard let style = selectedProfile?.style else { return false }
        let unit = Self.downloadID(of: style)
        return fontLibrary.state(for: unit.fontID, weightID: unit.weightID) == .preparing
            && !timedOutPreparingFonts.contains(unit)
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

    /// The face the viewfinder draws `overlayStyle` with: the profile's font
    /// when it is `available`, PingFang otherwise (PRD 0.3 FR-5.14). Resolved
    /// afresh on every read, so the viewfinder follows the library.
    var overlayFont: ResolvedOverlayFont {
        resolveFont(overlayStyle, fontLibrary)
    }

    /// Where `selectedProfile` draws its overlay: a grid anchor or a custom
    /// center (PRD 0.2 §4.1).
    var overlayPlacement: OverlayPlacement {
        selectedProfile?.position ?? .default
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
        collapseCameraTools()
        profileStore.select(id: id)
    }

    /// Opens the 設定檔 sheet on its list (#226 R-1), whatever the panel is
    /// doing; the panel's state is left alone.
    func presentProfileManagement() {
        collapseCameraTools()
        profileManagerModel.resetNavigation()
        isProfileManagerPresented = true
    }

    /// A highlighted tour target was tapped (TASK-96, 96.4／96.5): the tour
    /// ends, recorded as seen, and the button does what it always does.
    func onboardingTargetTapped(_ target: OnboardingTarget) {
        onboarding.targetTapped()
        switch target {
        case .profileChip: presentProfileManagement()
        case .overlayPanelButton: openOverlayPanel()
        // Look-only (96.19): the mask never lets a tap reach it.
        case .overlayText: break
        }
    }

    /// The thumbnail was tapped (PRD 0.2 FR-15.3): ask for `.readWrite`
    /// the first time (never earlier), then open the gallery — it shows its
    /// own permission-denied state when the answer was no.
    func openGallery() {
        guard galleryModel == nil else { return }
        collapseCameraTools()
        let model = makeGalleryModel(capturedPhotoStore)
        galleryModel = model
        Task { [weak self] in
            await model.requestAccessAndLoad()
            self?.isGalleryPresented = true
        }
    }

    func dismissGallery() {
        isGalleryPresented = false
        galleryModel = nil
        // The user may have deleted the newest photo in the gallery.
        Task { [weak self] in await self?.refreshThumbnailFromLibrary(replacingExisting: true) }
    }

    /// Fills the thumbnail from the library on launch (PRD 0.2 FR-15.2,
    /// second branch). Runs once; does nothing when a photo was already
    /// captured this launch or when read access is not already granted, so
    /// it never prompts (FR-15.3).
    func loadLaunchThumbnail() async {
        guard !didLoadLaunchThumbnail else { return }
        didLoadLaunchThumbnail = true
        await refreshThumbnailFromLibrary(replacingExisting: false)
    }

    /// Shows the first still-existing captured photo, or the photo icon when
    /// none is left. `replacingExisting` lets the gallery-close path
    /// override the in-memory baked image; a capture landing while the read
    /// is in flight always wins.
    func refreshThumbnailFromLibrary(replacingExisting: Bool) async {
        guard replacingExisting || latestThumbnailImage == nil else { return }
        let library = makeThumbnailLibrary(capturedPhotoStore)
        switch library.readStatus() {
        case .authorized, .limited: break
        default: return
        }
        let landings = thumbnailLandingCount
        thumbnailRefreshGeneration += 1
        let generation = thumbnailRefreshGeneration
        // Never `photos()`: that prunes ids under `.limited` access.
        let ids = library.latestVisiblePhotoIDs(limit: 3)
        var loaded: UIImage?
        for id in ids {
            loaded = await library.image(id: id, targetSize: Self.libraryThumbnailSize)
            if loaded != nil { break }
        }
        // A newer refresh supersedes this one; a capture landing wins too.
        guard generation == thumbnailRefreshGeneration,
              landings == thumbnailLandingCount else { return }
        if let loaded {
            latestThumbnailImage = loaded
        } else if ids.isEmpty && replacingExisting {
            // Only a confirmed-empty list clears the thumbnail; a failed
            // load (offline iCloud, PhotoKit error) keeps what is shown.
            latestThumbnailImage = nil
        }
    }

    private static let libraryThumbnailSize = CGSize(width: 200, height: 200)

    func dismissProfileManagement() {
        isProfileManagerPresented = false
        // Swiping the sheet down or tapping outside it leaves whatever page
        // it was on — including a just-added profile's (TASK-106).
        profileManagerModel.sheetDidDismiss()
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

    /// Cycles to the next ratio in `CaptureAspectRatio.allCases`' declared
    /// order (3:4 → 1:1 → 9:16 → 3:4…), wrapping back to the first after the
    /// last (PRD 0.2 FR-7.7, human decision 2026-09-27: the ratio button now
    /// cycles on tap instead of opening a picker menu).
    func cycleAspectRatio() {
        collapseCameraTools()
        let ratios = CaptureAspectRatio.allCases
        let currentIndex = ratios.firstIndex(of: captureSettingsStore.captureAspectRatio) ?? 0
        let nextIndex = (currentIndex + 1) % ratios.count
        selectAspectRatio(ratios[nextIndex])
    }

    /// Opens or closes the tools capsule (issue #135).
    func toggleCameraTools() {
        isCameraToolsExpanded.toggle()
    }

    /// Closes the tools capsule; a no-op when it is already closed. Called by
    /// every other control that acts while the capsule is up (issue #135).
    func collapseCameraTools() {
        if isCameraToolsExpanded {
            isCameraToolsExpanded = false
        }
    }

    /// Opens the overlay panel, collapsing the tools capsule first (issue #135).
    func openOverlayPanel() {
        collapseCameraTools()
        panelModel.open()
        noticeUnavailableFontIfNeeded()
    }

    /// Closes the overlay panel, collapsing the tools capsule too (issue #135).
    func closeOverlayPanel() {
        collapseCameraTools()
        panelModel.close()
    }

    /// A tap on the viewfinder outside the overlay text: the same thing as
    /// any other tap outside the panel (`handleTapOutsidePanel`).
    func handleViewfinderTap() {
        handleTapOutsidePanel()
    }

    /// A tap on the overlay text itself (TASK-105, #420): opens the panel
    /// while it is closed, on whichever tab it was last on; does nothing
    /// while it is open — the text is what the panel edits, so tapping it
    /// must not collapse the panel (contrast `handleViewfinderTap`).
    func handleOverlayTextTap() {
        zoomExpansion.collapse()
        guard !panelModel.isOpen else { return }
        openOverlayPanel()
    }

    /// Whether a viewfinder touch beginning at `point` (viewfinder
    /// coordinates) lands on the overlay text, where it belongs to the text's
    /// own tap and must not focus or adjust exposure (105.3).
    func viewfinderTouchStartsOnOverlayText(at point: CGPoint) -> Bool {
        !overlayTextFrame.isNull && overlayTextFrame.contains(point)
    }

    /// A tap anywhere outside the panel — the viewfinder, the blank space
    /// beside and below it, the gaps between the toolbar's buttons (TASK-97,
    /// #401; PRD 0.2 FR-8.7). While the tools capsule is up it only closes
    /// the capsule — the tap is consumed, so an open panel stays open (issue
    /// #135); otherwise it closes the panel. The toolbar's buttons never
    /// reach here: they do their own thing and leave the panel open (human
    /// decision 2026-10-10).
    func handleTapOutsidePanel() {
        zoomExpansion.collapse()
        if isCameraToolsExpanded {
            collapseCameraTools()
        } else if panelModel.isOpen {
            panelModel.close()
        }
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
    ///
    /// `font` is resolved here, on the main actor, at the moment the shutter
    /// fires (a timer: when the countdown reaches zero) and travels with the
    /// context to the background baking, which never reads the font library
    /// (PRD 0.3 FR-5.14, FR-16.14).
    func captureContext(for profile: CameraProfile) -> CaptureContext {
        let capturedAt = calculator.now()
        let text = renderer.render(profile: profile, capturedAt: capturedAt, calendar: calendar)
        let font = resolveFont(profile.style, fontLibrary)
        return (capturedAt, text, profile.style, profile.position, font)
    }

    /// Everything the baking needs, fixed at the instant the shutter fires.
    typealias CaptureContext = (capturedAt: Date, text: String, style: OverlayStyle, placement: OverlayPlacement, font: ResolvedOverlayFont)

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
        collapseCameraTools()
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
        captureTriggerCount += 1
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
                // The photo is counted as in flight before the capture span
                // ends, so the shutter never flickers enabled in between.
                self.processCapturedImage(image, context: context)
                self.isCapturing = false
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
    /// save-success and save-failure branches, and that `inFlightSaveCount`
    /// drops back on every one of them (PRD acceptance 10.22).
    func processCapturedImage(_ image: UIImage, context: CaptureContext) {
        // Counted here, synchronously on the main actor, so a test calling
        // this directly goes through the same `+1` → `-1` transition as the
        // real flow. `context` was fixed when the shutter fired, so a profile
        // switch while this photo is still baking cannot change it.
        inFlightSaveCount += 1
        let cropRect = self.cropRect
        let bake = self.bake
        let save = self.save
        let aspectRatio = captureSettingsStore.captureAspectRatio
        // Only the identity is kept for the timing log, so a pending save
        // timeout does not hold the full-resolution photo in memory.
        let imageKey = ObjectIdentifier(image)
        pipelineQueue.async {
            // core-dev's reminder: a 12MP photo in a wide-gamut color space
            // can make `UIGraphicsImageRenderer` pick a 16-bit format, ~97MB
            // per bake — without this, memory piles up across rapid presses
            // (PRD acceptance 10.22) instead of being reclaimed between them.
            let baked = autoreleasepool { () -> UIImage? in
                // One pass: `bake` crops to the window and draws the overlay
                // (PRD 0.2 FR-5.7′). The overlay's margin and font size are
                // derived from the *cropped* canvas's short edge, matching
                // what the viewfinder already showed for the same aspect
                // ratio (FR-5.9, FR-5.11).
                let pixelSize = CGSize(width: image.size.width * image.scale,
                                       height: image.size.height * image.scale)
                let window = cropRect(pixelSize, aspectRatio)
                return bake(image, context.text, context.style, context.placement, context.font, window)
            }
            guard let baked else {
                // PRD §7.3: baking failure. Not saved, no success toast.
                CaptureTiming.discard(imageKey)
                DispatchQueue.main.async { [weak self] in
                    self?.reportPhotoFailure(message: "照片處理失敗，請再試一次。", showsSettingsAction: false)
                    self?.inFlightSaveCount -= 1
                }
                return
            }
            // Downscaled here, off the main thread, alongside the bake work
            // it depends on: a 12MP `UIImage` is not something the thumbnail
            // (88px) or the flight animation (~600px) should hold on to.
            let thumbnail = Self.thumbnail(of: baked)
            CaptureTiming.mark(.baked, for: imageKey)
            let flightImage = Self.thumbnail(of: baked, maxDimension: Self.flightImageMaxDimension)
            let flightID = UUID()

            // The flight starts as soon as the photo is baked, in parallel
            // with the library write (issue #148 assumption 2). `save` is
            // started from main, after the flight exists, so its completion
            // can never arrive before the flight it updates.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.captureFlights.append(CaptureFlight(id: flightID, image: flightImage, thumbnail: thumbnail))
                let slot = SaveSlot()
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self, !slot.isSettled else { return }
                    // The save never called back: give the place up and say
                    // so, rather than report a save nobody confirmed.
                    slot.settle()
                    CaptureTiming.discard(imageKey)
                    self.markFlightFailed(id: flightID)
                    self.reportPhotoFailure(message: "照片儲存逾時，這張可能沒有存進相簿。請再試一次。",
                                            showsSettingsAction: false)
                    self.inFlightSaveCount -= 1
                }
                slot.timeout = timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + self.saveTimeout, execute: timeout)
                save(baked) { [weak self] result in
                    guard let self else { return }
                    // `PhotoSaver.saveReturningIdentifier`'s completion
                    // already guarantees main.
                    guard !slot.isSettled else {
                        // Answered after the timeout already reported this
                        // photo and freed its place: nothing is reported or
                        // counted twice, but a photo that did reach the
                        // library is still recorded for the gallery.
                        if case let .success(assetID) = result {
                            self.capturedPhotoStore.recordCapturedAsset(assetID)
                        }
                        return
                    }
                    slot.settle()
                    switch result {
                    case let .success(assetID):
                        CaptureTiming.mark(.saved, for: imageKey)
                        // PRD 0.2 FR-15.1/FR-15.2: record the new asset so
                        // the gallery (TASK-29) can find it later.
                        self.capturedPhotoStore.recordCapturedAsset(assetID)
                        self.markFlightSaved(id: flightID)
                        // Nothing is shown on screen for a save any more, so
                        // VoiceOver users hear it instead (issue #148).
                        self.announce("已儲存")
                    case let .failure(error):
                        CaptureTiming.discard(imageKey)
                        self.markFlightFailed(id: flightID)
                        self.reportPhotoFailure(message: error.displayMessage,
                                                showsSettingsAction: error.showsSettingsAction)
                    }
                    self.inFlightSaveCount -= 1
                }
            }
        }
    }

    /// Longest side of the picture used for the flight animation, in points.
    /// The picture is drawn at its start frame for a moment and then shrinks,
    /// so it is sized for the animation, not for the full viewfinder.
    static let flightImageMaxDimension: CGFloat = 300

    /// Longest side of the toast / footer thumbnail, in points. The tile
    /// those two show is 44pt and aspect-fills, so 88pt keeps the short side
    /// at 44pt or more down to a 1:2 photo.
    static let thumbnailMaxDimension: CGFloat = 88

    /// A small copy of `image`, for the toast (PRD FR-5.4) — never the
    /// full-resolution baked photo.
    ///
    /// `maxDimension` is in points; the bitmap is `maxDimension * scale`
    /// pixels on its longest side and the returned image carries that
    /// `scale`, so it displays sharp at `maxDimension` points and is not
    /// multiplied by the screen scale a second time (#468). `scale` defaults
    /// to the main screen's.
    static func thumbnail(of image: UIImage,
                          maxDimension: CGFloat = thumbnailMaxDimension,
                          scale: CGFloat = UIScreen.main.scale) -> UIImage {
        let sourcePixels = CGSize(width: image.size.width * image.scale,
                                  height: image.size.height * image.scale)
        let targetPixels = maxDimension * scale
        let largestSide = max(sourcePixels.width, sourcePixels.height)
        guard largestSide > targetPixels else { return image }
        let ratio = targetPixels / largestSide
        let pixelSize = CGSize(width: max(1, (sourcePixels.width * ratio).rounded()),
                               height: max(1, (sourcePixels.height * ratio).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let drawn = UIGraphicsImageRenderer(size: pixelSize, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: pixelSize)) }
        guard let cgImage = drawn.cgImage else { return drawn }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
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
        unacknowledgedFailureCount = 0
    }

    /// Shows the failure alert for one photo that was not saved. Failures that
    /// arrive before the alert is dismissed are counted, so two failed photos
    /// read "2 張照片未儲存" instead of the second alert hiding the first
    /// (TASK-129, #469); a single failure keeps its own message.
    func reportPhotoFailure(message: String, showsSettingsAction: Bool) {
        let previous = unacknowledgedFailureCount > 0 ? captureError : nil
        unacknowledgedFailureCount += 1
        guard unacknowledgedFailureCount > 1 else {
            captureError = CaptureAlertError(message: message, showsSettingsAction: showsSettingsAction)
            return
        }
        captureError = CaptureAlertError(message: "\(unacknowledgedFailureCount) 張照片未儲存",
                                         showsSettingsAction: showsSettingsAction || (previous?.showsSettingsAction ?? false))
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

// MARK: - Fonts (PRD 0.3, TASK-35)

/// What the camera screen needs from the font library: availability and the
/// list's cancel/delete (`FontListControlling`), plus download, preparation
/// and the background cancel. `FontLibrary` conforms; tests inject a fake.
@MainActor
protocol FontShellControlling: FontListControlling {
    /// Fires with the exact font and weight each time a download finishes
    /// successfully; the state is already `.available` by then. The older
    /// per-font event only speaks for the default weight.
    var weightDownloadDidFinish: PassthroughSubject<FontDownloadID, Never> { get }
    /// Starts a download; `false` when none was started.
    @discardableResult func download(_ fontID: OverlayFontID) -> Bool
    /// Settles one `.preparing` font now (FR-5.16).
    func prepare(_ fontID: OverlayFontID) async
    /// Settles one exact face.
    func prepare(_ fontID: OverlayFontID, weightID: String?) async
    /// Settles the fonts on the device after launch (FR-5.15).
    func prepareAtLaunch(priority: OverlayFontID?) async
    /// Same, with the priority font's exact weight first.
    func prepareAtLaunch(priority: OverlayFontID?, weightID: String?) async
    /// Cancels every download in progress (FR-16.11).
    func cancelAllDownloads()
}

extension FontLibrary: FontShellControlling {}

/// The library `CameraScreenModel` uses when none is injected: only PingFang
/// is usable and nothing downloads. Keeps previews and unrelated tests off
/// the file system and the network.
@MainActor
private final class InertFontLibrary: FontShellControlling {
    let objectWillChange = ObservableObjectPublisher()
    let weightDownloadDidFinish = PassthroughSubject<FontDownloadID, Never>()

    func state(for fontID: OverlayFontID) -> FontState {
        fontID == .pingFang ? .available : .notDownloaded
    }
    func cancel(_ fontID: OverlayFontID) {}
    func delete(_ fontID: OverlayFontID) -> Bool { false }
    func download(_ fontID: OverlayFontID) -> Bool { false }
    func prepare(_ fontID: OverlayFontID) async {}
    func prepare(_ fontID: OverlayFontID, weightID: String?) async {}
    func prepareAtLaunch(priority: OverlayFontID?) async {}
    func prepareAtLaunch(priority: OverlayFontID?, weightID: String?) async {}
    func cancelAllDownloads() {}
}

extension CameraScreenModel {
    /// The exact face `style` draws with, as the font library counts it.
    static func downloadID(of style: OverlayStyle) -> FontDownloadID {
        FontDownloadID(fontID: style.fontID, weightID: style.resolvedFontWeight.id)
    }

    /// Settles the fonts on the device after launch, the current profile's
    /// font first (PRD 0.3 FR-5.15). Returns once that font is settled; the
    /// shutter waits for it, for at most `fontPreparationTimeout`. Call once,
    /// from the screen's `.task`.
    func prepareFontsAtLaunch() async {
        await fontLibrary.prepareAtLaunch(priority: selectedProfile?.style.fontID,
                                          weightID: selectedProfile?.style.resolvedFontWeight.id)
    }

    /// The app went to the background: pending downloads stop and nobody is
    /// left waiting to be applied (PRD 0.3 FR-16.11).
    func sceneDidEnterBackground() {
        pendingFontApplications.removeAll()
        fontLibrary.cancelAllDownloads()
    }

    /// The one way a font is written to a profile (PRD 0.3 FR-5.18).
    ///
    /// An `available` font is written to `profileID` at once, and any earlier
    /// request still pending for that profile is dropped. Anything else is
    /// downloaded, and written to **that** profile once the download finishes
    /// (A-8), even if the list was closed or another profile is current by
    /// then; a later request for the same profile replaces this one, and a
    /// cancelled, failed or interrupted download drops it.
    func applyFont(_ fontID: OverlayFontID, profileID: UUID) {
        switch fontLibrary.state(for: fontID) {
        case .available:
            pendingFontApplications[profileID] = nil
            writeFont(fontID, to: profileID)
        case .preparing:
            pendingFontApplications[profileID] = fontID
            Task { [weak self] in
                await self?.fontLibrary.prepare(fontID)
                self?.fontLibraryDidChange()
            }
        case .notDownloaded, .failed, .downloading:
            pendingFontApplications[profileID] = fontID
            fontLibrary.download(fontID)
            fontLibraryDidChange()
        }
    }

    /// Writes `fontID` into the stored profile and keeps the style tab's copy
    /// in step. A profile that no longer exists is skipped.
    ///
    /// - Returns: whether the profile now has `fontID`; `false` for a missing
    ///   profile or a failed save (which shows its own message).
    @discardableResult
    private func writeFont(_ fontID: OverlayFontID, to profileID: UUID) -> Bool {
        guard var latest = profileStore.profiles.first(where: { $0.id == profileID }) else { return false }
        if latest.style.fontID != fontID {
            latest.style.fontID = fontID
            do {
                // Waits for the disk: "applied" must not be announced for a
                // save that then fails (#492).
                try profileStore.updateAndWait(latest)
            } catch {
                showToast(message: "無法儲存字型設定")
                return false
            }
        }
        syncStyleTabModelWithStore()
        return true
    }

    /// Hands the style tab the store's latest copy of its profile (FR-5.18).
    fileprivate func syncStyleTabModelWithStore() {
        guard let styleTabModel,
              let latest = profileStore.profiles.first(where: { $0.id == styleTabModel.profile.id }) else { return }
        styleTabModel.applyExternalChanges(from: latest)
    }

    /// Follows the library: finishes or drops pending applications, and
    /// redraws what depends on font state (the viewfinder, the shutter).
    fileprivate func bindToFontLibrary() {
        fontLibrary.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                // `objectWillChange` fires before the change lands.
                DispatchQueue.main.async { self?.fontLibraryDidChange() }
            }
            .store(in: &cancellables)
        fontLibrary.weightDownloadDidFinish
            .sink { [weak self] _ in self?.fontLibraryDidChange() }
            .store(in: &cancellables)
    }

    /// Settles every pending application against the font's current state.
    func fontLibraryDidChange() {
        for (profileID, fontID) in pendingFontApplications {
            switch fontLibrary.state(for: fontID) {
            case .available:
                pendingFontApplications[profileID] = nil
                guard profileStore.profiles.contains(where: { $0.id == profileID }) else { continue }
                // The user has since picked a weight of another font for this
                // profile and it is still downloading: that is the newer
                // choice, so this one must not land first (#458).
                if let list = styleTabModel?.fontList, list.profileID == profileID,
                   let newer = list.pendingWeight, newer.fontID != fontID { continue }
                if writeFont(fontID, to: profileID) { announceApplied(fontID) }
            case .notDownloaded, .failed:
                pendingFontApplications[profileID] = nil
            case .preparing, .downloading:
                break
            }
        }
    }

    /// "已套用「<名稱>」" (FR-16.6): in the font list when it is open, on the
    /// camera screen otherwise.
    private func announceApplied(_ fontID: OverlayFontID) {
        let text = "已套用「\(fontID.displayName)」"
        if let list = styleTabModel?.fontLibraryModel {
            list.post(text)
        } else {
            showToast(message: text)
        }
    }

    /// The selected profile changed: a `.preparing` font starts matching now
    /// instead of waiting in the launch queue (FR-5.16), and an unusable one
    /// is announced once (FR-16.14).
    func selectedProfileDidChange() {
        guard let profile = selectedProfile, profile.id != lastSeenProfileID else { return }
        lastSeenProfileID = profile.id
        let unit = Self.downloadID(of: profile.style)
        if fontLibrary.state(for: unit.fontID, weightID: unit.weightID) == .preparing {
            timedOutPreparingFonts.remove(unit)
            startPreparationTimeoutIfNeeded(for: unit)
            Task { [weak self] in
                await self?.fontLibrary.prepare(unit.fontID, weightID: unit.weightID)
                guard self?.selectedProfileID == profile.id else { return }
                self?.noticeUnavailableFontIfNeeded()
            }
        } else {
            noticeUnavailableFontIfNeeded()
        }
    }

    /// Gives a `.preparing` font its 3 seconds from now; after that the
    /// shutter stops waiting (FR-5.15, FR-5.16).
    fileprivate func startPreparationTimeoutIfNeeded(for unit: FontDownloadID) {
        guard fontLibrary.state(for: unit.fontID, weightID: unit.weightID) == .preparing else { return }
        preparationTimeoutTasks[unit]?.cancel()
        let seconds = fontPreparationTimeout
        preparationTimeoutTasks[unit] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.timedOutPreparingFonts.insert(unit)
            self.objectWillChange.send()
        }
    }

    /// "「<名稱>」需要重新下載，暫時用蘋方", once per profile and font during
    /// this launch, when the current profile's font is neither available,
    /// preparing nor downloading (FR-16.14).
    func noticeUnavailableFontIfNeeded() {
        guard let profile = selectedProfile else { return }
        let fontID = profile.style.fontID
        switch fontLibrary.state(for: fontID, weightID: profile.style.resolvedFontWeight.id) {
        case .available, .preparing, .downloading:
            return
        case .notDownloaded, .failed:
            let notice = UnavailableFontNotice(profileID: profile.id, fontID: fontID)
            guard noticedUnavailableFonts.insert(notice).inserted else { return }
            showToast(message: "「\(fontID.displayName)」需要重新下載，暫時用蘋方")
        }
    }
}

// MARK: - Overlay-panel write-through (#70)

/// One overlay-panel tab's `updateProfile` closure, wrapped so a write only
/// applies the fields *that tab itself* actually changed since its own last
/// write, merged onto whatever `profileStore` currently holds for the same
/// profile — instead of blindly overwriting the whole record with that
/// tab's own (possibly stale, since another tab — or a rename elsewhere —
/// could have written since this tab's model was built) full
/// `CameraProfile` copy.
///
/// Every tab model (`StyleTabModel`, `DisplaySettingsModel`,
/// `PositionTabModel`, `RulesTabModel` — three of those four owned by
/// ui-panel, off-limits for this card per #70) always calls its
/// `updateProfile` closure with its *entire* working copy on every change,
/// even though a single mutation only ever touches the handful of fields
/// that tab owns. Diffing that copy against `baseline` — this tab's own
/// copy immediately before the mutation that just happened — recovers which
/// fields actually changed without needing any of those types to expose
/// that themselves.
///
/// Assumes only one tab writes at a time (this card's own stated
/// assumption, matching how the panel's UI only ever has one tab active) —
/// not built to reconcile two genuinely concurrent writes to the same
/// profile.
@MainActor
final class TabProfileWriter {
    private var baseline: CameraProfile
    private let profileStore: ProfileStore

    init(baseline: CameraProfile, profileStore: ProfileStore) {
        self.baseline = baseline
        self.profileStore = profileStore
    }

    /// Merges whatever changed between `baseline` and `updated` onto the
    /// store's current record for the same profile, persists that, and
    /// advances `baseline` to `updated` so the next write from this same tab
    /// diffs against this one.
    func write(_ updated: CameraProfile) throws {
        guard let latest = profileStore.profiles.first(where: { $0.id == updated.id }) else {
            // The profile was deleted out from under this tab (e.g. from the
            // management list) — nothing sane to merge into. Let the tab
            // surface this as its own `lastError`, same as any other
            // `updateProfile` failure.
            throw ProfileStoreError.profileNotFound(id: updated.id)
        }
        let merged = Self.merging(updated, from: baseline, onto: latest)
        if Self.isContinuousAdjustment(from: baseline, to: updated) {
            try profileStore.update(merged)
        } else {
            // An explicit choice (font, weight, name, switches...): written
            // before the tab reports it as applied (#492, human decision
            // 2026-10-12). A failure rolls the store back and reaches the tab.
            try profileStore.updateAndWait(merged)
        }
        baseline = updated
    }

    /// Whether the only changes from `baseline` to `updated` are slider, drag
    /// or color-picker values, which arrive many times a second and are
    /// written after a debounce (#464). Everything else is an explicit choice.
    static func isContinuousAdjustment(from baseline: CameraProfile, to updated: CameraProfile) -> Bool {
        var probe = baseline
        probe.style.sizeScale = updated.style.sizeScale
        probe.style.strokeWidth = updated.style.strokeWidth
        probe.style.boxPadding = updated.style.boxPadding
        probe.style.shadowOffsetX = updated.style.shadowOffsetX
        probe.style.shadowOffsetY = updated.style.shadowOffsetY
        probe.style.shadowBlur = updated.style.shadowBlur
        probe.style.autoOutlineOpacity = updated.style.autoOutlineOpacity
        probe.style.textColor = updated.style.textColor
        probe.style.outlineColor = updated.style.outlineColor
        probe.style.shadowColor = updated.style.shadowColor
        // The first drag event from "follow the text color" also flips the
        // source to custom; going back to following the text is a tap.
        if updated.style.shadowColorSource == .custom {
            probe.style.shadowColorSource = .custom
        }
        if case .custom = updated.position { probe.position = updated.position }
        probe.updatedAt = updated.updatedAt
        return probe == updated
    }

    /// Advances `baseline` to the store's current record when the tab's own
    /// model took that record over (`applyExternalChanges`, TASK-109): the
    /// next write then diffs against what the tab now shows, so a field it
    /// changes back to the baseline's old value is still seen as changed.
    func adopt(_ latest: CameraProfile) {
        guard latest.id == baseline.id else { return }
        baseline = latest
    }

    /// `latest` with every field that differs between `baseline` and
    /// `updated` replaced by `updated`'s value — i.e. only the fields the
    /// tab that produced `updated` actually touched since its own last
    /// write, leaving everything else exactly as `profileStore` currently
    /// has it. `id`/`createdAt`/`updatedAt` are deliberately left out:
    /// `id` never changes, and `profileStore.update` already stamps
    /// `createdAt`/`updatedAt` itself.
    private static func merging(_ updated: CameraProfile, from baseline: CameraProfile, onto latest: CameraProfile) -> CameraProfile {
        var merged = latest
        if updated.name != baseline.name { merged.name = updated.name }
        if updated.startDate != baseline.startDate { merged.startDate = updated.startDate }
        if updated.countingRule != baseline.countingRule { merged.countingRule = updated.countingRule }
        if updated.showDayCount != baseline.showDayCount { merged.showDayCount = updated.showDayCount }
        if updated.showDate != baseline.showDate { merged.showDate = updated.showDate }
        if updated.showName != baseline.showName { merged.showName = updated.showName }
        if updated.displayUnits != baseline.displayUnits { merged.displayUnits = updated.displayUnits }
        if updated.useAgeWording != baseline.useAgeWording { merged.useAgeWording = updated.useAgeWording }
        if updated.position != baseline.position { merged.position = updated.position }
        if updated.style != baseline.style { merged.style = updated.style }
        return merged
    }
}


// MARK: - Capture flight (issue #148)

/// One captured photo's trip from the viewfinder to the thumbnail button.
struct CaptureFlight: Identifiable {
    enum Status: Equatable {
        /// Still being written to the library.
        case saving
        case saved
        case failed
    }

    let id: UUID
    /// ~600px copy used for the animation.
    let image: UIImage
    /// 88px copy that becomes `latestThumbnailImage` once the flight lands.
    let thumbnail: UIImage
    fileprivate(set) var status: Status = .saving
    fileprivate(set) var hasLanded = false

    init(id: UUID = UUID(), image: UIImage, thumbnail: UIImage) {
        self.id = id
        self.image = image
        self.thumbnail = thumbnail
    }
}

extension CameraScreenModel {
    /// The view reports the flight reached the thumbnail button. The
    /// thumbnail is only replaced once the photo is also saved; until then
    /// the flight waits at its landing spot.
    func flightDidLand(id: UUID) {
        guard let index = captureFlights.firstIndex(where: { $0.id == id }) else { return }
        captureFlights[index].hasLanded = true
        commitFlightIfFinished(at: index)
    }

    /// Drops a flight once its (failure) fade-out is done.
    func removeCaptureFlight(id: UUID) {
        captureFlights.removeAll { $0.id == id }
    }

    fileprivate func markFlightSaved(id: UUID) {
        guard let index = captureFlights.firstIndex(where: { $0.id == id }) else { return }
        captureFlights[index].status = .saved
        commitFlightIfFinished(at: index)
    }

    fileprivate func markFlightFailed(id: UUID) {
        guard let index = captureFlights.firstIndex(where: { $0.id == id }) else { return }
        captureFlights[index].status = .failed
    }

    /// Saved and landed: the new photo becomes the thumbnail and the flight
    /// is done.
    private func commitFlightIfFinished(at index: Int) {
        let flight = captureFlights[index]
        guard flight.status == .saved, flight.hasLanded else { return }
        latestThumbnailImage = flight.thumbnail
        thumbnailLandingCount += 1
        captureFlights.remove(at: index)
    }
}
