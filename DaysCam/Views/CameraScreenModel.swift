import Combine
import Foundation
import UIKit

/// Drives the camera of one record (PRD 2.0 FR-20): camera lifecycle,
/// permission/status interpretation, the 「第 N 天」 HUD, the tools capsule,
/// the shutter's capture state machine and saving the clean original into
/// the record's album. `CameraScreen` only lays out whatever this model
/// currently says, so UI-level acceptance criteria are tested here rather
/// than in the view.
///
/// Built each time the camera opens, for the record whose photo wall opened
/// it (#621). The photo is never cropped, toned or baked: the overlay is
/// added only by the export page (§6.3).
@MainActor
final class CameraScreenModel: ObservableObject {
    /// Saves one photo for a record: into its album (full access, creating
    /// one titled `albumTitle` when `albumIdentifier` is `nil` or gone) or
    /// into 「最近項目」 only (limited access). The completion runs once, on
    /// the main queue.
    typealias Save = (_ image: UIImage,
                      _ albumIdentifier: String?,
                      _ albumTitle: String,
                      _ completion: @escaping (Result<RecordSaveOutcome, PhotoSaveError>) -> Void) -> Void

    let cameraService: CameraService
    /// Pinch-to-zoom state of the viewfinder (TASK-61). Only `isPinching` is
    /// forwarded to this object's changes; the rest changes every frame of a
    /// pinch and is observed by the capsule alone (issue #280).
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
    /// The camera tools' state: flash, timer and grid (PRD 0.2 §4.4). The
    /// ratio and tone fields stay in the file unread (PRD 2.0 §4.2).
    let captureSettingsStore: CaptureSettingsStore
    private let profileStore: ProfileStore
    /// The record this camera saves into: the one whose photo wall opened it.
    let profileID: UUID
    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer
    /// Drives the timer countdown (PRD 0.2 FR-7.6). Injectable so tests can
    /// advance the countdown one tick at a time.
    private let countdownTicker: CountdownTicker

    /// The record as the store has it now; `nil` once it was deleted.
    @Published private(set) var profile: CameraProfile?

    /// Whether the flash／timer／grid capsule below the toolbar is showing
    /// (issue #135). Never persisted.
    @Published private(set) var isCameraToolsExpanded = false

    /// How the phone is held, for the icons (#572). Follows
    /// `CameraService.viewfinderRotationAngle` unless a fixed angle was
    /// passed to `init`.
    @Published private(set) var viewfinderRotation: ViewfinderRotation = .portrait
    private let captureRotationAngleOverride: CGFloat?

    /// True from the moment the shutter fires until AVFoundation hands back
    /// the photo (or fails). Only this span keeps the shutter from firing
    /// again (PRD 0.2 FR-5.5, #469); saving is counted by `inFlightSaveCount`.
    @Published private(set) var isCapturing = false

    /// The app's camera saves, shared with every other camera model: the
    /// in-flight count and the one-at-a-time save queue (#636 review).
    let saveCoordinator: CaptureSaveCoordinator

    /// How many captured photos are still being prepared or saved, by this
    /// camera or one closed before it. Goes up when a photo arrives from the
    /// camera and down when that photo fails or its save calls back (or
    /// times out), success or failure.
    var inFlightSaveCount: Int { saveCoordinator.inFlightCount }

    /// The most photos prepared or saved at once, across cameras.
    static let maxInFlightSaves = CaptureSaveCoordinator.maxInFlightSaves

    /// Whether a capture or a full pipeline keeps the shutter disabled.
    var isShutterBusy: Bool {
        isCapturing || saveCoordinator.isAtLimit
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

    /// Prepares one photo at a time, in capture order.
    private let pipelineQueue = DispatchQueue(label: "dayscam.capture-pipeline", qos: .userInitiated)

    /// The pending capture-time failure alert, if any (PRD 0.1 §7.3).
    @Published private(set) var captureError: CaptureAlertError?

    /// Photos that failed since the failure alert was last dismissed.
    private var unacknowledgedFailureCount = 0

    /// The remaining whole seconds of an in-progress timer countdown (PRD 0.2
    /// FR-7.6); `nil` when no countdown is running.
    @Published private(set) var countdownRemaining: Int?

    /// The record's newest photo for the 44pt corner button (FR-20.5): read
    /// from the library when the camera opens (`loadLatestThumbnail()`),
    /// then replaced by each photo taken here once it has landed.
    @Published private(set) var latestThumbnailImage: UIImage?

    /// Photos currently flying from the viewfinder into the thumbnail
    /// button, one entry per capture (issue #148).
    @Published private(set) var captureFlights: [CaptureFlight] = []

    /// Bumped the instant the shutter really fires — no timer: when the
    /// button is pressed; with a timer: when the countdown reaches zero. The
    /// view flashes the viewfinder and plays the light haptic off this.
    @Published private(set) var captureTriggerCount = 0

    /// Speaks `message` to VoiceOver (a no-op when it is off). Replaceable so
    /// tests can observe the call without posting a real notification.
    var announce: (String) -> Void = { message in
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// Bumped each time a landed flight replaces `latestThumbnailImage`, so
    /// the thumbnail button can play its small bounce.
    @Published private(set) var thumbnailLandingCount = 0

    /// Saves a photo for the record. Defaults to
    /// `PhotoSaver.saveToRecordAlbum`. Injectable for tests.
    private let save: Save

    /// Fires the actual shutter. Defaults to `cameraService.capturePhoto`.
    /// Injectable so tests can drive a capture without real hardware.
    private let captureImage: (FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void

    /// Tells the camera which flash mode the next photo will use (TASK-130).
    private let prepareCapture: (FlashMode) -> Void

    /// Reads the record's newest photo for the thumbnail button; `nil` when
    /// it has none or access is missing.
    private let loadLatestPhoto: @MainActor () async -> UIImage?
    private var didLoadLatestThumbnail = false

    /// Where a failure goes once the camera has closed, so a photo that did
    /// not save is never left unreported (0.2 FR-5.5): the alert the user has
    /// not dismissed yet when the camera closes, and every failure of a save
    /// still running after that. The count is how many photos it stands for.
    /// The app hands it to the 紀錄 list (`RecordListModel`).
    private let reportFailureAfterClose: @MainActor (CaptureAlertError, Int) -> Void
    /// Where a failed write of the record (its album or fallback ids) goes.
    private let reportRecordWriteFailure: @MainActor (Error) -> Void
    /// Set by `onDisappear`; from then on failures go to
    /// `reportFailureAfterClose` instead of `captureError`.
    private(set) var isClosed = false

    /// Bumped whenever the calendar day changes or the app returns to the
    /// foreground (TASK-14), so the HUD re-reads the clock (PRD 0.1 §6.4).
    /// Nothing reads this value; its only job is to be `@Published`.
    @Published private(set) var refreshTick = 0

    /// The pending toast (only "已取消" now), if any.
    @Published private(set) var toastState: ToastState?

    /// How `showToast` schedules the toast's own auto-dismiss. Injected so
    /// tests don't have to wait a real 1.5 seconds.
    private let scheduleToastDismiss: (@escaping () -> Void) -> Void

    private var cancellables = Set<AnyCancellable>()

    /// - Parameter calendar: Defaults to `.autoupdatingCurrent`, so the HUD
    ///   follows the device's current time zone (PRD 0.1 §6.3).
    init(cameraService: CameraService,
         profileStore: ProfileStore,
         profileID: UUID,
         captureSettingsStore: CaptureSettingsStore = CaptureSettingsStore(),
         calendar: Calendar = .autoupdatingCurrent,
         calculator: DayCountCalculator = DayCountCalculator(),
         renderer: TemplateRenderer = TemplateRenderer(),
         countdownTicker: CountdownTicker = SystemCountdownTicker(),
         saveCoordinator: CaptureSaveCoordinator? = nil,
         save: @escaping Save = { image, albumIdentifier, albumTitle, completion in
             PhotoSaver().saveToRecordAlbum(image, albumIdentifier: albumIdentifier,
                                            albumTitle: albumTitle, completion: completion)
         },
         captureImage: ((FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void)? = nil,
         prepareCapture: ((FlashMode) -> Void)? = nil,
         loadLatestPhoto: @escaping @MainActor () async -> UIImage? = { nil },
         reportFailureAfterClose: @escaping @MainActor (CaptureAlertError, Int) -> Void = { _, _ in },
         reportRecordWriteFailure: @escaping @MainActor (Error) -> Void = { _ in },
         scheduleToastDismiss: @escaping (@escaping () -> Void) -> Void = { work in
             DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
         },
         saveTimeout: TimeInterval = CameraScreenModel.defaultSaveTimeout,
         captureRotationAngleOverride: CGFloat? = nil) {
        self.captureRotationAngleOverride = captureRotationAngleOverride
        self.saveTimeout = saveTimeout
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
        self.profileStore = profileStore
        self.profileID = profileID
        self.calendar = calendar
        self.calculator = calculator
        self.renderer = renderer
        self.countdownTicker = countdownTicker
        self.saveCoordinator = saveCoordinator ?? CaptureSaveCoordinator()
        self.save = save
        self.captureImage = captureImage ?? { [cameraService] flashMode, completion in
            cameraService.capturePhoto(flashMode: flashMode, completion: completion)
        }
        self.prepareCapture = prepareCapture ?? { [cameraService] flashMode in
            cameraService.prepareCapture(flashMode: flashMode)
        }
        self.loadLatestPhoto = loadLatestPhoto
        self.reportFailureAfterClose = reportFailureAfterClose
        self.reportRecordWriteFailure = reportRecordWriteFailure
        self.scheduleToastDismiss = scheduleToastDismiss
        self.profile = profileStore.profiles.first { $0.id == profileID }
        bindToProfileStore()
        bindToSaveCoordinator()
        bindToCameraService()
        bindToZoomModel()
        bindToFocusModel()
        bindToCaptureSettingsStore()
        bindToFlashMode()
        bindToClockNotifications()
    }

    private func bindToProfileStore() {
        profileStore.$profiles
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profiles in
                guard let self else { return }
                self.profile = profiles.first { $0.id == self.profileID }
            }
            .store(in: &cancellables)
    }

    /// The shutter and the count follow saves of other cameras too.
    private func bindToSaveCoordinator() {
        saveCoordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Forwards `cameraService`'s own change notifications to this object's.
    ///
    /// `CameraScreen` only observes *this* model, and SwiftUI has no idea a
    /// view depends on a second object nested inside the first: without
    /// this, a permission or status change never re-renders the guidance
    /// screen or the shutter.
    private func bindToCameraService() {
        cameraService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // #572: a fixed angle (UI tests) wins over the service's.
        if let captureRotationAngleOverride {
            viewfinderRotation = ViewfinderRotation(captureAngle: captureRotationAngleOverride)
        } else {
            cameraService.$viewfinderRotationAngle
                .map { ViewfinderRotation(captureAngle: $0) }
                .removeDuplicates()
                .sink { [weak self] rotation in self?.viewfinderRotation = rotation }
                .store(in: &cancellables)
        }
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

    /// The simulator cannot capture; UI tests pass `-UITestFakeCapture` to
    /// get an enabled shutter whose photo is generated (#621). Debug builds
    /// only.
    static var usesUITestCapture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITestFakeCapture")
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
            guard !isCameraToolsExpanded, !zoomExpansion.isExpanded else { return false }
            #if DEBUG
            if fakeFocusBackend != nil { return true }
            #endif
            return !isCaptureUnsupported && !needsPermissionGuidance && !isSessionNotRunning
        }
        focusModel.isPinching = { [weak self] in self?.zoomModel.isPinching ?? false }
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
    /// nested `ObservableObject` and `CameraToolbar` only observes this model.
    private func bindToCaptureSettingsStore() {
        captureSettingsStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Prepares the photo output for the flash mode now selected and for each
    /// later change (TASK-130).
    private func bindToFlashMode() {
        captureSettingsStore.$flashMode
            .removeDuplicates()
            .sink { [weak self] flashMode in self?.prepareCapture(flashMode) }
            .store(in: &cancellables)
    }

    /// Re-reads the clock for the HUD when the calendar day rolls over while
    /// the camera is up, and when the app returns to the foreground (PRD 0.1
    /// §6.4, TASK-14).
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

    /// Forces the HUD to re-render against the current moment.
    func refreshOverlay() {
        refreshTick += 1
    }

    /// Called when the camera appears. Permission is requested here, not at
    /// app launch (PRD 0.1 §2.2).
    func onAppear() {
        prepareCapture(captureSettingsStore.flashMode)
        cameraService.start()
    }

    /// Called when the camera goes away: stops the session (#621-9). A
    /// countdown in progress stops without a photo; a photo still saving
    /// finishes on its own and is still recorded. A failure alert not yet
    /// dismissed is handed on (`reportFailureAfterClose`), and so is any
    /// later failure.
    func onDisappear() {
        if countdownRemaining != nil {
            countdownTicker.stop()
            countdownRemaining = nil
        }
        cameraService.stop()
        isClosed = true
        if let captureError {
            reportFailureAfterClose(captureError, unacknowledgedFailureCount)
            dismissCaptureError()
        }
    }

    func switchCamera() {
        collapseCameraTools()
        cameraService.switchCamera()
    }

    /// The label the placeholder viewfinder shows in the simulator (PRD §2.4).
    static let simulatorPlaceholderText = "模擬器不支援拍照"

    /// Whether this build cannot capture at all (the simulator, PRD §2.4).
    var isCaptureUnsupported: Bool {
        !cameraService.isCaptureSupported
    }

    /// Whether the app currently lacks camera permission — the guidance
    /// screen (PRD S-5) should cover the viewfinder in this state.
    var needsPermissionGuidance: Bool {
        cameraService.permission.needsGuidance
    }

    /// Whether the session is not actually showing a live picture right now.
    var isSessionNotRunning: Bool {
        cameraService.status != .running
    }

    /// Whether the viewfinder should show the simulator/placeholder
    /// background instead of a live preview (PRD §2.4).
    var showsPlaceholder: Bool {
        isCaptureUnsupported
    }

    /// Whether the shutter should be disabled right now: no live picture on
    /// screen, or a capture or the saves already at their limit (PRD 0.2
    /// FR-5.5). Single source of truth for the button and `capturePhoto()`.
    var isShutterDisabled: Bool {
        if Self.usesUITestCapture { return isShutterBusy }
        return isCaptureUnsupported || needsPermissionGuidance || isSessionNotRunning || isShutterBusy
    }

    /// A transient reason the viewfinder cannot show a live picture even
    /// though permission is fine (PRD §2.4). `nil` when nothing needs to be
    /// said.
    var statusMessage: String? {
        switch cameraService.status {
        case .interrupted, .unavailable(.sessionFailure), .unavailable(.noCaptureDevice):
            return "相機暫時無法使用"
        case .idle, .running, .unavailable(.simulator):
            return nil
        }
    }
}

// MARK: - Day HUD (FR-20.2)

extension CameraScreenModel {
    /// 「第 N 天」 for the record as of right now (FR-20.2): the elapsed days
    /// alone, by the record's counting rule, whatever units, wording or other
    /// parts the record prints; 「還有 N 天」 while the start date is still
    /// ahead. Read afresh on every access; `refreshTick` redraws it.
    var dayHUDText: String {
        guard var elapsedOnly = profile else { return "" }
        elapsedOnly.showDayCount = true
        elapsedOnly.showDate = false
        elapsedOnly.showName = false
        elapsedOnly.displayUnits = [.day]
        elapsedOnly.dayCountFormat = .ordinal
        return renderer.render(profile: elapsedOnly, capturedAt: calculator.now(),
                               calendar: calendar, moment: .today)
    }
}

// MARK: - Camera tools (PRD 0.2 FR-7, TASK-21; FR-20.3)

extension CameraScreenModel {
    /// Whether the flash button should be disabled: the front camera, or a
    /// back camera with no flash unit (PRD 0.2 FR-7.4).
    var isFlashToolDisabled: Bool {
        !cameraService.isFlashAvailable
    }

    /// Whether the flash icon renders in the `active` color (FR-7.10).
    var isFlashToolActive: Bool {
        captureSettingsStore.flashMode != .off
    }

    /// Whether the timer icon renders in the `active` color (FR-7.10).
    var isTimerToolActive: Bool {
        captureSettingsStore.timerSeconds != .off
    }

    /// Whether the grid icon renders in the `active` color (FR-7.10).
    var isGridToolActive: Bool {
        captureSettingsStore.showsGrid
    }

    /// Cycles the flash button (PRD 0.2 FR-7.4).
    func cycleFlash() {
        captureSettingsStore.cycleFlash()
    }

    /// Cycles the timer button 關 → 3 秒 → 10 秒 → 關 (PRD 0.2 FR-7.5).
    func cycleTimer() {
        captureSettingsStore.cycleTimer()
    }

    /// Flips the grid overlay (PRD 0.2 FR-7.9).
    func toggleGrid() {
        captureSettingsStore.toggleGrid()
    }

    /// Opens or closes the tools capsule (issue #135).
    func toggleCameraTools() {
        isCameraToolsExpanded.toggle()
    }

    /// Closes the tools capsule; a no-op when it is already closed.
    func collapseCameraTools() {
        if isCameraToolsExpanded {
            isCameraToolsExpanded = false
        }
    }

    /// A tap on the viewfinder closes the zoom and tools capsules; a tap
    /// that closes something does not also focus (73.6, #541).
    func handleViewfinderTap() {
        let closesSomething = isCameraToolsExpanded || zoomExpansion.isExpanded
        zoomExpansion.collapse()
        collapseCameraTools()
        if closesSomething { focusModel.ignoreTouchConsumedByTap() }
    }
}

// MARK: - Shutter (TASK-10, FR-20.4)

extension CameraScreenModel {
    /// Where a photo goes, fixed when the shutter fires: the record, and the
    /// title a new album for it gets. The album itself is read when the save
    /// starts, so a photo taken right after the first one of a record without
    /// an album lands in the album the first one created.
    struct CaptureDestination: Equatable {
        let profileID: UUID
        let albumTitle: String
    }

    /// Triggers a capture, or cancels an in-progress timer countdown (PRD 0.2
    /// FR-7.6).
    ///
    /// While `countdownRemaining != nil` this always cancels, regardless of
    /// `isShutterDisabled` (acceptance 19.9). Otherwise a no-op while
    /// `isShutterDisabled` (the FR-5.5 debounce) or once the record is gone.
    func capturePhoto() {
        collapseCameraTools()
        guard countdownRemaining == nil else {
            cancelCountdown()
            return
        }
        guard !isShutterDisabled, profile != nil else { return }
        beginCapture()
    }

    /// Starts a capture: immediately without a timer, otherwise once the
    /// countdown reaches zero (PRD 0.2 FR-7.6). Not `private` so tests can
    /// drive it without a running session.
    func beginCapture() {
        let seconds = captureSettingsStore.timerSeconds.rawValue
        guard seconds > 0 else {
            performCapture()
            return
        }
        countdownRemaining = seconds
        countdownTicker.start { [weak self] in
            self?.tickCountdown()
        }
    }

    /// One second of an in-progress countdown (acceptance 19.8): on the tick
    /// that reaches zero it stops the ticker and captures.
    private func tickCountdown() {
        guard let remaining = countdownRemaining else { return }
        let next = remaining - 1
        guard next > 0 else {
            countdownTicker.stop()
            countdownRemaining = nil
            performCapture()
            return
        }
        countdownRemaining = next
    }

    /// Cancels an in-progress countdown without capturing (acceptance 19.9).
    private func cancelCountdown() {
        countdownTicker.stop()
        countdownRemaining = nil
        showToast(message: "已取消")
    }

    /// Actually fires the shutter. The destination is the record as it is at
    /// this instant. The shutter time is used by nothing but the HUD
    /// (FR-20.6), so no moment travels with the photo.
    private func performCapture() {
        guard let profile else { return }
        isCapturing = true
        captureTriggerCount += 1
        let destination = CaptureDestination(profileID: profile.id, albumTitle: profile.name)
        let flashMode = captureSettingsStore.flashMode
        let capture: (FlashMode, @escaping (Result<UIImage, CameraCaptureError>) -> Void) -> Void =
            Self.usesUITestCapture ? Self.uiTestCaptureImage : captureImage

        // Held strongly until the photo comes back: the camera may close
        // (and its view drop this model) between the shutter and the
        // callback, and a photo that was taken must still be saved, or its
        // failure reported (#636 review). The callback runs exactly once, so
        // nothing is kept beyond it.
        capture(flashMode) { result in
            switch result {
            case let .success(image):
                // Counted as in flight before the capture span ends, so the
                // shutter never flickers enabled in between.
                self.processCapturedImage(image, destination: destination)
                self.isCapturing = false
            case .failure:
                // A capture-level failure: nothing reached the pipeline, the
                // shutter simply becomes tappable again.
                self.isCapturing = false
            }
        }
    }

    /// The photo `-UITestFakeCapture` takes: a 3:4 grey picture.
    private static func uiTestCaptureImage(_ flashMode: FlashMode,
                                           completion: @escaping (Result<UIImage, CameraCaptureError>) -> Void) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        DispatchQueue.main.async { completion(.success(image)) }
    }

    /// Saves `image` as taken (FR-20.4): orientation normalized off the main
    /// thread, then saved for the record — never cropped, toned or baked.
    ///
    /// On success the record learns where the photo went (`record(_:...)`).
    /// Failure and timeout raise the alert and never count as saved (0.2
    /// FR-5.5, FR-15.11).
    ///
    /// The pipeline holds this model until the photo's save has answered, so
    /// a photo still saving when the camera closes is still saved and
    /// recorded.
    ///
    /// Not `private`: reaching it from a real `capturePhoto()` needs a
    /// running session, unavailable without capture hardware.
    func processCapturedImage(_ image: UIImage, destination: CaptureDestination) {
        // Counted here, synchronously on the main actor, so a test calling
        // this directly goes through the same `+1` → `-1` transition as the
        // real flow.
        saveCoordinator.photoDidArrive()
        // Only the capture's ID is kept for the timing log, so a pending save
        // timeout does not hold the full-resolution photo in memory.
        let timingID = CaptureTiming.timingID(of: image)
        pipelineQueue.async {
            // A 12MP wide-gamut redraw can be ~100MB; release it between
            // rapid presses (PRD 0.1 acceptance 10.22).
            let upright = autoreleasepool { Self.uprightImage(image) }
            guard let upright else {
                CaptureTiming.discard(id: timingID)
                DispatchQueue.main.async {
                    self.reportPhotoFailure(message: "照片處理失敗，請再試一次。", showsSettingsAction: false)
                    self.saveCoordinator.photoDidFinish()
                }
                return
            }
            // Downscaled here, off the main thread: a 12MP image is not
            // something the thumbnail or the flight should hold on to.
            let thumbnail = Self.thumbnail(of: upright)
            CaptureTiming.mark(.baked, id: timingID)
            let flightImage = Self.thumbnail(of: upright, maxDimension: Self.flightImageMaxDimension)
            let flightID = UUID()

            // The flight starts as soon as the photo is ready, in parallel
            // with the library write (issue #148).
            DispatchQueue.main.async {
                self.captureFlights.append(CaptureFlight(id: flightID, image: flightImage, thumbnail: thumbnail))
                self.saveCoordinator.enqueueSave { finished in
                    self.startSave(upright, destination: destination, flightID: flightID,
                                   timingID: timingID, finished: finished)
                }
            }
        }
    }

    /// Saves one prepared photo, with its timeout (TASK-151).
    private func startSave(_ image: UIImage, destination: CaptureDestination, flightID: UUID,
                           timingID: UUID?, finished: @escaping () -> Void) {
        let store = profileStore
        let coordinator = saveCoordinator
        // The album as the record has it now: an earlier photo may just have
        // created it.
        let albumIdentifier = store.profiles.first { $0.id == destination.profileID }?.albumIdentifier
        let slot = SaveSlot()
        let timeout = DispatchWorkItem { [weak self] in
            guard !slot.isSettled else { return }
            // The save never called back: give the place up and say so,
            // rather than report a save nobody confirmed.
            slot.settle()
            CaptureTiming.discard(id: timingID)
            self?.markFlightFailed(id: flightID)
            self?.reportPhotoFailure(message: "照片儲存逾時，這張可能沒有存進相簿。請再試一次。",
                                     showsSettingsAction: false)
            coordinator.photoDidFinish()
            finished()
        }
        slot.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + saveTimeout, execute: timeout)
        save(image, albumIdentifier, destination.albumTitle) { result in
            // A photo that reached the library is recorded even when the
            // timeout already reported it.
            if case let .success(outcome) = result {
                Self.record(outcome, savedFor: destination, albumAtSave: albumIdentifier, in: store,
                            reportWriteFailure: self.reportRecordWriteFailure)
            }
            guard !slot.isSettled else { return }
            slot.settle()
            switch result {
            case .success:
                CaptureTiming.mark(.saved, id: timingID)
                self.markFlightSaved(id: flightID)
                // Nothing is shown on screen for a save, so VoiceOver users
                // hear it instead (issue #148).
                self.announce("已儲存")
            case let .failure(error):
                CaptureTiming.discard(id: timingID)
                self.markFlightFailed(id: flightID)
                self.reportPhotoFailure(message: error.displayMessage,
                                        showsSettingsAction: error.showsSettingsAction)
            }
            self.saveCoordinator.photoDidFinish()
            finished()
        }
    }

    /// Tells the record where a saved photo went (FR-20.4).
    ///
    /// - Full access (`albumID` set): the album becomes the record's when it
    ///   differs — the first photo of a record without an album, or an album
    ///   deleted in the 「照片」 App and created again. If the record was
    ///   bound to another album while this save ran, the photo's ID is kept
    ///   in `fallbackAssetIDs` instead, so it still shows on the wall.
    /// - Limited access (`albumID` nil): the asset ID joins
    ///   `fallbackAssetIDs`; no album is created (§7.3).
    ///
    /// A record deleted in the meantime is skipped; the photo stays in the
    /// library either way. The write waits for the disk, and a failure goes
    /// to `reportWriteFailure`: without it a limited-access photo would not
    /// show on the wall.
    static func record(_ outcome: RecordSaveOutcome, savedFor destination: CaptureDestination,
                       albumAtSave: String?, in store: ProfileStore,
                       reportWriteFailure: (Error) -> Void) {
        guard var latest = store.profiles.first(where: { $0.id == destination.profileID }) else { return }
        if let albumID = outcome.albumID {
            guard latest.albumIdentifier != albumID else { return }
            if latest.albumIdentifier == albumAtSave {
                latest.albumIdentifier = albumID
            } else {
                guard !latest.fallbackAssetIDs.contains(outcome.assetID) else { return }
                latest.fallbackAssetIDs.append(outcome.assetID)
            }
        } else {
            guard !latest.fallbackAssetIDs.contains(outcome.assetID) else { return }
            latest.fallbackAssetIDs.append(outcome.assetID)
        }
        do {
            try store.updateAndWait(latest)
        } catch {
            reportWriteFailure(error)
        }
    }

    /// `image` redrawn so its pixels stand upright (`imageOrientation ==
    /// .up`), at the same size, scale and color range; `image` itself when
    /// it already is. `nil` when the redraw produced no bitmap.
    nonisolated static func uprightImage(_ image: UIImage) -> UIImage? {
        guard image.imageOrientation != .up else { return image }
        let drawn = UIGraphicsImageRenderer(size: image.size, format: image.imageRendererFormat).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return drawn.cgImage == nil ? nil : drawn
    }

    /// Longest side of the picture used for the flight animation, in points.
    static let flightImageMaxDimension: CGFloat = 300

    /// Longest side of the corner thumbnail, in points. The tile is 44pt and
    /// aspect-fills, so 88pt keeps the short side at 44pt or more down to a
    /// 1:2 photo.
    static let thumbnailMaxDimension: CGFloat = 88

    /// A small copy of `image` — never the full-resolution photo.
    ///
    /// `maxDimension` is in points; the bitmap is `maxDimension * scale`
    /// pixels on its longest side and the returned image carries that
    /// `scale`, so it displays sharp at `maxDimension` points (#468).
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

// MARK: - Latest photo (FR-20.5)

extension CameraScreenModel {
    /// Fills the corner button with the record's newest photo, once per
    /// camera. A photo taken here before the read finishes wins.
    func loadLatestThumbnail() async {
        guard !didLoadLatestThumbnail else { return }
        didLoadLatestThumbnail = true
        let landings = thumbnailLandingCount
        let image = await loadLatestPhoto()
        guard landings == thumbnailLandingCount, let image else { return }
        latestThumbnailImage = image
    }
}

// MARK: - Error handling & toast (TASK-15)

extension CameraScreenModel {
    /// Dismisses a capture-time failure alert (PRD 0.1 §7.3).
    func dismissCaptureError() {
        captureError = nil
        unacknowledgedFailureCount = 0
    }

    /// Shows the failure alert for one photo that was not saved. Failures that
    /// arrive before the alert is dismissed are counted, so two failed photos
    /// read "2 張照片未儲存" instead of the second alert hiding the first
    /// (TASK-129, #469); a single failure keeps its own message.
    func reportPhotoFailure(message: String, showsSettingsAction: Bool) {
        guard !isClosed else {
            reportFailureAfterClose(CaptureAlertError(message: message, showsSettingsAction: showsSettingsAction), 1)
            return
        }
        let previous = unacknowledgedFailureCount > 0 ? captureError : nil
        unacknowledgedFailureCount += 1
        guard unacknowledgedFailureCount > 1 else {
            captureError = CaptureAlertError(message: message, showsSettingsAction: showsSettingsAction)
            return
        }
        captureError = CaptureAlertError(message: "\(unacknowledgedFailureCount) 張照片未儲存",
                                         showsSettingsAction: showsSettingsAction || (previous?.showsSettingsAction ?? false))
    }

    /// Shows a transient toast and schedules it to fade out after 1.5
    /// seconds ("已取消", 0.2 FR-7.6). Each call gets a fresh `ToastState.id`
    /// and the dismiss guards on it, so an older timer firing late cannot cut
    /// a newer toast short.
    func showToast(message: String, thumbnail: UIImage? = nil) {
        let state = ToastState(message: message, thumbnail: thumbnail)
        toastState = state
        scheduleToastDismiss { [weak self] in
            guard self?.toastState?.id == state.id else { return }
            self?.toastState = nil
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
/// `PositionTabModel`, `RulesTabModel`) always calls its `updateProfile`
/// closure with its *entire* working copy on every change, even though a
/// single mutation only ever touches the handful of fields that tab owns.
/// Diffing that copy against `baseline` — this tab's own copy immediately
/// before the mutation that just happened — recovers which fields actually
/// changed without needing any of those types to expose that themselves.
///
/// Assumes only one tab writes at a time — not built to reconcile two
/// genuinely concurrent writes to the same profile.
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
            // The profile was deleted out from under this tab — nothing sane
            // to merge into. Let the tab surface this as its own `lastError`.
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
        if updated.showFilmDate != baseline.showFilmDate { merged.showFilmDate = updated.showFilmDate }
        if updated.filmDateCorner != baseline.filmDateCorner { merged.filmDateCorner = updated.filmDateCorner }
        if updated.dayCountFormat != baseline.dayCountFormat { merged.dayCountFormat = updated.dayCountFormat }
        if updated.albumIdentifier != baseline.albumIdentifier { merged.albumIdentifier = updated.albumIdentifier }
        if updated.fallbackAssetIDs != baseline.fallbackAssetIDs { merged.fallbackAssetIDs = updated.fallbackAssetIDs }
        if updated.exportFormat != baseline.exportFormat { merged.exportFormat = updated.exportFormat }
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
