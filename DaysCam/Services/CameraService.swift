import AVFoundation
import Combine
import CoreMedia
import Foundation
import os
import UIKit

// MARK: - Published value types

/// Camera permission, reduced to the four cases the viewfinder cares about
/// (PRD §2.3).
enum CameraPermission: String, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    /// True when the guidance screen (PRD S-5) should cover the viewfinder and
    /// the shutter should be disabled.
    var needsGuidance: Bool {
        self == .denied || self == .restricted
    }
}

/// Why a live picture cannot be shown even though permission is in order.
enum CameraUnavailableReason: Equatable {
    /// This build cannot capture at all — the simulator (PRD §2.4). The view
    /// shows its placeholder background and marks the shutter unsupported.
    case simulator
    /// Permission is granted but no usable camera was found on this side.
    case noCaptureDevice
    /// The session could not be configured, or reported a runtime error.
    case sessionFailure
}

/// What the viewfinder area should currently display.
///
/// Permission is published separately: `permission.needsGuidance` decides
/// between the guidance screen and this status.
enum CameraStatus: Equatable {
    /// Nothing started yet, or the screen was left.
    case idle
    /// Live picture on screen; the shutter may fire.
    case running
    /// A call or another app took the camera; it comes back by itself
    /// (PRD §2.4).
    case interrupted
    case unavailable(CameraUnavailableReason)
}

/// Which camera is active. The only two the app offers (PRD FR-5.8).
enum CameraFacing: String, Equatable, CaseIterable {
    case back
    case front

    /// The side `switchCamera()` moves to.
    var opposite: CameraFacing {
        self == .back ? .front : .back
    }

    /// The AVFoundation position this maps to.
    var captureDevicePosition: AVCaptureDevice.Position {
        self == .back ? .back : .front
    }
}

/// Why the shutter could not produce an image.
enum CameraCaptureError: Error, Equatable {
    /// This build cannot capture (the simulator).
    case captureUnavailable
    /// The session is not live: no permission yet, interrupted, or stopped.
    case notRunning
    /// AVFoundation reported a failure; the string is the system description.
    case failed(String)
    /// The capture finished but produced no decodable image.
    case noImageData
}

// MARK: - Injected seams

/// The slice of `AVCaptureDevice` the permission state machine uses.
///
/// Injected so the state machine can be tested without the real prompt, which
/// cannot be driven from a unit test (PRD §8).
protocol CameraAuthorizing {
    func authorizationStatus() -> AVAuthorizationStatus
    func requestAccess(completion: @escaping (Bool) -> Void)
}

/// Looks up the capture device for a given side.
///
/// Injected for the same reason: in the simulator there is no device to hand
/// back, so tests stub this out rather than asking the discovery session.
protocol CaptureDeviceProviding {
    func device(for facing: CameraFacing) -> AVCaptureDevice?
}

/// Production authorizer, straight through to `AVCaptureDevice`.
struct SystemCameraAuthorizer: CameraAuthorizing {
    func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }
}

/// Production device lookup. The back side prefers a virtual device that
/// switches between lenses seamlessly (triple, then dual wide, then dual), and
/// falls back to the plain wide angle camera; the front side is the wide angle
/// camera (issue #279).
struct SystemCaptureDeviceProvider: CaptureDeviceProviding {
    func device(for facing: CameraFacing) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType]
        switch facing {
        case .back:
            types = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        case .front:
            types = [.builtInWideAngleCamera]
        }
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: types,
                                                       mediaType: .video,
                                                       position: facing.captureDevicePosition).devices
        // First by preference order, whatever order the session lists them in.
        for type in types {
            if let device = devices.first(where: { $0.deviceType == type }) { return device }
        }
        return nil
    }
}

/// Whether a side of the device has a flash unit at all.
///
/// A real `AVCaptureDevice` cannot be constructed in a test — there is no
/// public initializer — so `hasFlash` is asked through this seam instead of
/// reading `device(for:).hasFlash` directly. That keeps "front camera, or a
/// device with no flash" (PRD 0.2 FR-7.4) testable at the view-model layer
/// (acceptance 19.4) rather than only on a real device.
protocol FlashCapabilityProviding {
    func hasFlash(for facing: CameraFacing) -> Bool
}

/// Production capability lookup: asks whatever `CaptureDeviceProviding` this
/// service was built with.
struct SystemFlashCapabilityProvider: FlashCapabilityProviding {
    let deviceProvider: CaptureDeviceProviding

    func hasFlash(for facing: CameraFacing) -> Bool {
        deviceProvider.device(for: facing)?.hasFlash ?? false
    }
}

// MARK: - Countdown ticker

/// The slice of `AVCaptureConnection` that photo mirroring touches.
///
/// Injected so the mirroring decision can be tested without a real capture
/// connection, which only exists with a camera attached.
protocol VideoMirroringConfigurable: AnyObject {
    var isVideoMirroringSupported: Bool { get }
    var automaticallyAdjustsVideoMirroring: Bool { get set }
    var isVideoMirrored: Bool { get set }
}

extension AVCaptureConnection: VideoMirroringConfigurable {}

/// The slice of `AVCapturePhotoOutput` that low-latency capture touches.
///
/// Injected so the "only enable what is supported" rules and the prepared
/// settings can be tested without a real output attached to a camera, whose
/// `...Supported` flags only come true on a device.
protocol PhotoOutputConfiguring: AnyObject {
    var isZeroShutterLagSupported: Bool { get }
    var isZeroShutterLagEnabled: Bool { get set }
    var isResponsiveCaptureSupported: Bool { get }
    var isResponsiveCaptureEnabled: Bool { get set }
    var isFastCapturePrioritizationSupported: Bool { get }
    var isFastCapturePrioritizationEnabled: Bool { get set }
    var maxPhotoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization { get set }
    var maxPhotoDimensions: CMVideoDimensions { get }
    var supportedFlashModes: [AVCaptureDevice.FlashMode] { get }
    func setPreparedPhotoSettingsArray(_ preparedPhotoSettingsArray: [AVCapturePhotoSettings],
                                       completionHandler: ((Bool, (any Error)?) -> Void)?)
}

extension AVCapturePhotoOutput: PhotoOutputConfiguring {}

/// The slice of `AVCaptureDevice` that zooming touches.
///
/// Injected so the clamping and the lock/unlock pairing can be tested without
/// a real camera, which the simulator does not have.
protocol ZoomableCaptureDevice: AnyObject {
    var minAvailableVideoZoomFactor: CGFloat { get }
    var maxAvailableVideoZoomFactor: CGFloat { get }
    var videoZoomFactor: CGFloat { get set }
    func lockForConfiguration() throws
    func unlockForConfiguration()
    /// Which lenses make up the device; decides what 1× means (issue #279).
    var zoomLens: ZoomLens { get }
    var isRampingVideoZoom: Bool { get }
    func cancelVideoZoomRamp()
    func ramp(toVideoZoomFactor factor: CGFloat, withRate rate: Float)
}

/// Defaults for a device with a single lens that never ramps: how a test
/// double behaves unless it says otherwise.
extension ZoomableCaptureDevice {
    var zoomLens: ZoomLens { ZoomLens() }
    var isRampingVideoZoom: Bool { false }
    func cancelVideoZoomRamp() {}
    func ramp(toVideoZoomFactor factor: CGFloat, withRate rate: Float) { videoZoomFactor = factor }
}

extension AVCaptureDevice: ZoomableCaptureDevice {
    var zoomLens: ZoomLens {
        ZoomLens(hasUltraWide: constituentDevices.first?.deviceType == .builtInUltraWideCamera,
                 switchOverFactors: virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) })
    }
}

/// The slice of `AVCaptureDevice` that tap-to-focus, exposure bias and AE/AF
/// lock touch (issue #303).
///
/// Injected for the same reason as `ZoomableCaptureDevice`: the mode switches,
/// the bias clamp and the lock/unlock pairing are testable without a camera.
protocol FocusExposureCaptureDevice: AnyObject {
    var isFocusPointOfInterestSupported: Bool { get }
    var isExposurePointOfInterestSupported: Bool { get }
    func isFocusModeSupported(_ focusMode: AVCaptureDevice.FocusMode) -> Bool
    func isExposureModeSupported(_ exposureMode: AVCaptureDevice.ExposureMode) -> Bool
    var focusPointOfInterest: CGPoint { get set }
    var exposurePointOfInterest: CGPoint { get set }
    var focusMode: AVCaptureDevice.FocusMode { get set }
    var exposureMode: AVCaptureDevice.ExposureMode { get set }
    var minExposureTargetBias: Float { get }
    var maxExposureTargetBias: Float { get }
    func setExposureTargetBias(_ bias: Float, completionHandler handler: ((CMTime) -> Void)?)
    var isSubjectAreaChangeMonitoringEnabled: Bool { get set }
    func lockForConfiguration() throws
    func unlockForConfiguration()
}

extension AVCaptureDevice: FocusExposureCaptureDevice {}

/// What triggered a possible focus/exposure reset.
enum FocusExposureTrigger: Equatable {
    /// The scene changed enough that the old focus/exposure no longer fits.
    case subjectAreaChanged
    /// The other camera went into the session.
    case cameraFlipped
    /// A quick-zoom preset was chosen, possibly changing the physical lens.
    case zoomPresetSelected
    /// The app came back to the foreground.
    case enteredForeground
    /// A pinch changed the zoom factor. Never resets.
    case pinchZoomed
}

/// Decides whether a trigger resets focus and exposure to continuous auto
/// (issue #303). Pure, so the rules are testable without a device.
enum FocusExposurePolicy {
    /// True when `trigger` must reset to continuous auto with bias 0.
    static func shouldReset(on trigger: FocusExposureTrigger, isLocked: Bool) -> Bool {
        switch trigger {
        case .subjectAreaChanged: return !isLocked
        case .cameraFlipped, .zoomPresetSelected, .enteredForeground: return true
        case .pinchZoomed: return false
        }
    }
}

/// What the viewfinder's focus/exposure UI needs to know. Published through
/// `CameraService.focusExposureStatePublisher`.
struct FocusExposureState: Equatable {
    /// True after `lockFocusAndExposure(at:)` took effect on at least one of
    /// focus and exposure, until the next tap, reset or flip.
    var isLocked = false
    /// The exposure compensation in EV the device was last given; 0 after
    /// every reset. Never persisted.
    var exposureBias: Float = 0

    static let initial = FocusExposureState()
}

/// Why a focus/exposure request did nothing.
enum FocusExposureFailure: Error, Equatable {
    /// `lockForConfiguration` threw; the device was left as it was.
    case lockFailed
}

/// The zoom factors the current camera accepts, as `setZoomFactor(_:)` clamps
/// them: the device's available range, capped at `CameraService.maxZoomFactor`.
struct ZoomRange: Equatable {
    let minimum: CGFloat
    let maximum: CGFloat

    /// No zoom at all: what is published before a camera is configured.
    static let fixed = ZoomRange(minimum: 1, maximum: 1)

    /// `factor` pulled into this range.
    func clamp(_ factor: CGFloat) -> CGFloat {
        Swift.min(Swift.max(factor, minimum), maximum)
    }
}

/// Coalesces zoom requests (issue #280): a pinch asks for a new factor every
/// frame, far faster than the camera takes them. Only the newest request is
/// kept and at most one job is ever scheduled; in-between factors are dropped.
final class ZoomRequestCoalescer {
    private let lock = NSLock()
    private var pending: CGFloat?
    private var isScheduled = false

    init() {}

    /// Records `factor` as the newest request. When no job is scheduled yet,
    /// `schedule` is asked to run one; that job applies whatever request is
    /// newest by the time it runs.
    func submit(_ factor: CGFloat,
                schedule: (@escaping () -> Void) -> Void,
                apply: @escaping (CGFloat) -> Void) {
        lock.lock()
        pending = factor
        let needsJob = !isScheduled
        isScheduled = true
        lock.unlock()
        guard needsJob else { return }
        schedule { [self] in
            lock.lock()
            let newest = pending
            pending = nil
            isScheduled = false
            lock.unlock()
            if let newest { apply(newest) }
        }
    }
}

/// A tick source for the timer countdown (PRD 0.2 FR-7.6).
///
/// Injected so the countdown state machine (`CameraScreenModel`, TASK-21) can
/// be driven one tick at a time in tests instead of waiting on a real clock.
protocol CountdownTicker {
    /// Starts calling `onTick` once per second until `stop()` is called.
    /// Safe to call again before `stop()`; a fresh call replaces the pending
    /// ticks with new ones from the new call's start. Call on the main queue.
    func start(onTick: @escaping () -> Void)
    /// Stops any pending ticks. Safe to call whether or not one is running.
    func stop()
}

/// Production ticker: a repeating `Timer` on the main run loop.
final class SystemCountdownTicker: CountdownTicker {
    private var timer: Timer?

    init() {}

    func start(onTick: @escaping () -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in onTick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - CameraService

/// Owns the capture session behind the viewfinder (PRD S-1, S-5).
///
/// Responsibilities: the permission state machine, session lifecycle,
/// front/back switching, interruption handling and the shutter. It deliberately
/// does not own an `AVCaptureVideoPreviewLayer` — the view layer builds its own
/// from `session`, so this type stays free of UI.
///
/// Threading: call every method from the main thread, which is where a SwiftUI
/// view already is. Published properties only ever change on the main queue,
/// and everything that configures, starts or stops the session hops to a
/// private serial queue so it never blocks the main thread.
///
/// It never crashes where there is no camera: `isCaptureSupported` is false in
/// the simulator, and in that case the session is never configured or started.
final class CameraService: ObservableObject {

    /// The session the view attaches its preview layer to.
    ///
    /// Handing out the session rather than a layer keeps layer ownership,
    /// sizing and rotation in the view where they belong.
    let session = AVCaptureSession()

    /// Current camera permission (PRD §2.3).
    @Published private(set) var permission: CameraPermission = .notDetermined

    /// What the viewfinder area should show right now.
    @Published private(set) var status: CameraStatus = .idle

    /// The side currently in use. Only changes once a switch has succeeded.
    @Published private(set) var facing: CameraFacing = .back

    /// The current camera's zoom factor, 1 meaning unzoomed. Back to 1 on
    /// every camera switch (issue #274).
    ///
    /// Deliberately not `@Published`: a pinch changes it every frame, and a
    /// `@Published` property would make every view that observes this service
    /// (through `CameraScreenModel`) re-render each time (issue #280). Read
    /// `zoomFactorPublisher` to follow it.
    var zoomFactor: CGFloat { zoomFactorSubject.value }

    /// Emits `zoomFactor` whenever it changes; the current value on subscribe.
    var zoomFactorPublisher: AnyPublisher<CGFloat, Never> { zoomFactorSubject.eraseToAnyPublisher() }

    private let zoomFactorSubject = CurrentValueSubject<CGFloat, Never>(1)

    /// Folds the stream of pinch updates into at most one queued job on
    /// `sessionQueue`, always applying the newest factor (issue #280).
    private let zoomCoalescer = ZoomRequestCoalescer()

    /// Lock and bias of the current camera's focus/exposure. Not `@Published`
    /// for the same reason as `zoomFactor`: dragging the bias changes it every
    /// frame. Read `focusExposureStatePublisher` to follow it (issue #303).
    var focusExposureState: FocusExposureState { focusExposureSubject.value }

    /// Emits `focusExposureState` whenever it changes; current value on subscribe.
    var focusExposureStatePublisher: AnyPublisher<FocusExposureState, Never> {
        focusExposureSubject.eraseToAnyPublisher()
    }

    /// Emits when a focus/exposure request could not be applied, so the UI
    /// never shows a success the device did not take. Delivered on the main queue.
    var focusExposureFailurePublisher: AnyPublisher<FocusExposureFailure, Never> {
        focusExposureFailureSubject.eraseToAnyPublisher()
    }

    /// Emits whenever the camera went back to continuous auto (flip, lens
    /// change, scene change, foreground), even when `focusExposureState` was
    /// already at rest and so did not change. Delivered on the main queue,
    /// possibly after a newer tap: the value is the id of the latest focus or
    /// lock request the device had taken when it reset (0 for none), so the
    /// receiver can tell a reset that a newer request has already overtaken.
    var focusExposureResetPublisher: AnyPublisher<Int, Never> {
        focusExposureResetSubject.eraseToAnyPublisher()
    }

    /// Confirms a successful tap reset, even when the state was already zero.
    /// The ID identifies the applied tap; unlike an automatic reset, keep its
    /// reticle. UI callers should ignore confirmations older than their latest tap.
    var focusExposureTapResetPublisher: AnyPublisher<Int, Never> {
        focusExposureTapResetSubject.eraseToAnyPublisher()
    }

    private let focusExposureTapResetSubject = PassthroughSubject<Int, Never>()
    private let focusExposureResetSubject = PassthroughSubject<Int, Never>()
    /// Ids handed out to focus and lock requests. Main queue only.
    private var focusRequestCounter = 0
    /// The id of the latest focus or lock request run on the device. Touched
    /// on `sessionQueue` only.
    var lastAppliedFocusRequestID = 0
    private let focusExposureSubject = CurrentValueSubject<FocusExposureState, Never>(.initial)
    private let focusExposureFailureSubject = PassthroughSubject<FocusExposureFailure, Never>()
    /// The truth the subject is published from. Touched on `sessionQueue` only.
    private var focusExposureShadow = FocusExposureState.initial

    /// The most the exposure compensation moves either way, in EV.
    static let maxExposureBiasMagnitude: Float = 2

    /// The exposure compensation range the live camera accepts: ±2 EV narrowed
    /// to the device's own limits (`exposureBiasRange(of:)`). Refreshed on every
    /// focus/exposure request and camera flip; ±2 until then.
    @Published private(set) var exposureBiasRange: ClosedRange<Float> = -2...2

    /// The display factors `setZoomFactor(_:)` accepts on the current camera.
    @Published private(set) var zoomRange: ZoomRange = .fixed

    /// The quick-zoom buttons the current camera offers, ascending display
    /// factors (issue #279). Empty until a camera is configured.
    @Published private(set) var availableZoomPresets: [ZoomPreset] = []

    /// The most the viewfinder zooms in, whatever the device allows
    /// (issue #274).
    static let maxZoomFactor: CGFloat = 10

    /// False where capture is impossible, i.e. the simulator. The view uses it
    /// for the placeholder background and the disabled shutter (PRD §2.4).
    let isCaptureSupported: Bool

    /// Whether this build can capture at all.
    static var platformSupportsCapture: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    /// Whether the flash can fire right now: `false` on the front camera,
    /// and `false` for a back camera with no flash unit (PRD 0.2 FR-7.4).
    /// The toolbar disables the flash button on this, and `capturePhoto`
    /// forces `.off` regardless of what was requested.
    ///
    /// Reads a per-side cache: the toolbar asks on every SwiftUI redraw, and
    /// the lookup behind it builds a `DiscoverySession` (#471). The cache is
    /// filled on first use for each side and cleared whenever the session is
    /// (re)configured, so a lookup that ran before camera access was granted
    /// does not stick.
    var isFlashAvailable: Bool {
        let side = facing
        return CameraService.isFlashAvailable(facing: side, hasFlash: cachedHasFlash(for: side))
    }

    /// Test seam: `facing` is otherwise only set by a real camera switch.
    func setFacingForTesting(_ newValue: CameraFacing) {
        facing = newValue
    }

    /// Test seam: pretends the session was configured, so camera-dependent
    /// paths can run without a camera.
    func markConfiguredForTesting() {
        sessionQueue.sync { isConfigured = true }
    }

    /// Test seam: runs `work` after everything queued on the session queue.
    func drainSessionQueueForTesting() {
        sessionQueue.sync {}
    }

    private let flashCache = OSAllocatedUnfairLock(initialState: [CameraFacing: Bool]())

    private func cachedHasFlash(for side: CameraFacing) -> Bool {
        if let cached = flashCache.withLock({ $0[side] }) { return cached }
        let hasFlash = flashCapabilityProvider.hasFlash(for: side)
        flashCache.withLock { $0[side] = hasFlash }
        return hasFlash
    }

    private let authorizer: CameraAuthorizing
    private let deviceProvider: CaptureDeviceProviding
    private let flashCapabilityProvider: FlashCapabilityProviding
    private let sessionQueue = DispatchQueue(label: "com.irenechou.DaysCam.camera-session")
    private let photoOutput: AVCapturePhotoOutput

    /// Touched on `sessionQueue` only.
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var sessionFacing: CameraFacing = .back
    /// The flash mode the toolbar last asked for, so prepared settings match
    /// the next photo. Touched on `sessionQueue` only.
    private var requestedFlashMode: FlashMode = .off
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    /// Keeps each in-flight capture delegate alive; AVFoundation does not
    /// retain it. Touched on `sessionQueue` only.
    private var captureDelegates: [ObjectIdentifier: PhotoCaptureDelegate] = [:]

    private var observers: [NSObjectProtocol] = []

    /// True between `start()` and `stop()`: the camera screen wants a live
    /// picture. Touched on the main queue only.
    ///
    /// It exists so returning to the foreground cannot start the session
    /// behind a screen that is no longer showing a viewfinder — that would
    /// light the camera indicator and drain the battery with nothing on
    /// screen.
    private var isActive = false

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - authorizer: permission source; defaults to `AVCaptureDevice`.
    ///   - deviceProvider: device lookup; defaults to the discovery session.
    ///   - flashCapabilityProvider: flash-availability lookup; defaults to
    ///     asking `deviceProvider`. Tests inject a fake directly, since a
    ///     real `AVCaptureDevice` cannot be constructed to report `hasFlash`.
    ///   - isCaptureSupported: false disables every hardware path, which is
    ///     what the simulator gets.
    ///   - photoOutput: the output photos are taken with; tests pass a subclass
    ///     that records what the service asks of it.
    init(authorizer: CameraAuthorizing = SystemCameraAuthorizer(),
         deviceProvider: CaptureDeviceProviding = SystemCaptureDeviceProvider(),
         flashCapabilityProvider: FlashCapabilityProviding? = nil,
         isCaptureSupported: Bool = CameraService.platformSupportsCapture,
         photoOutput: AVCapturePhotoOutput = AVCapturePhotoOutput()) {
        self.photoOutput = photoOutput
        self.authorizer = authorizer
        self.deviceProvider = deviceProvider
        self.flashCapabilityProvider = flashCapabilityProvider
            ?? SystemFlashCapabilityProvider(deviceProvider: deviceProvider)
        self.isCaptureSupported = isCaptureSupported
        registerObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

// MARK: - Lifecycle

extension CameraService {

    /// Entry point for the camera screen: resolves permission, prompting the
    /// first time, and starts the session when it is granted.
    ///
    /// Safe to call repeatedly — re-entering the screen is the normal case.
    ///
    /// Call on the main queue.
    func start() {
        isActive = true
        resolvePermission()
    }

    /// Stops the session and returns to idle. Call when the camera screen goes
    /// away, and on the main queue.
    ///
    /// It also clears the active flag, so a later trip through the foreground
    /// will not bring the session back on its own. A screen that stops on
    /// backgrounding therefore has to call `start()` again on the way in.
    func stop() {
        isActive = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            // A capture that was still in flight will never hear back from
            // AVFoundation now, so answer for it rather than leaving the
            // caller's shutter disabled forever.
            let abandoned = Array(self.captureDelegates.values)
            self.captureDelegates.removeAll()
            abandoned.forEach { $0.cancel() }

            self.publish(status: .idle)
        }
    }

    /// Re-reads permission and recovers if it was granted elsewhere.
    ///
    /// PRD §2.3, last row: granting from Settings and switching back must bring
    /// the viewfinder up without a relaunch. Also wired to
    /// `willEnterForegroundNotification`.
    ///
    /// A revoked permission goes through the same path: it becomes `.denied`
    /// and the guidance screen comes back.
    ///
    /// It never starts a session that `stop()` has since shut down — only one
    /// the camera screen is still asking for. Call on the main queue.
    func refreshPermission() {
        resolvePermission()
    }

    /// Reads the current permission, prompting the first time, and publishes
    /// it. When it is granted, asks `run()` to start the session, which only
    /// does so while the camera screen is active.
    ///
    /// Where capture is unsupported (the simulator), the permission prompt
    /// never applies — there is no camera to ask about — so this reports
    /// `.authorized` without touching `authorizer` at all and lets `run()`
    /// publish the placeholder status (PRD §2.4, 0.2 issue #64). The shutter
    /// stays disabled regardless, via `isCaptureSupported`.
    private func resolvePermission() {
        guard isCaptureSupported else {
            publish(permission: .authorized)
            run()
            return
        }

        switch authorizer.authorizationStatus() {
        case .notDetermined:
            publish(permission: .notDetermined)
            authorizer.requestAccess { [weak self] granted in
                guard let self else { return }
                self.onMain {
                    self.publish(permission: granted ? .authorized : .denied)
                    if granted { self.run() }
                }
            }
        case .authorized:
            publish(permission: .authorized)
            run()
        case .denied:
            publish(permission: .denied)
        case .restricted:
            publish(permission: .restricted)
        @unknown default:
            // An unknown case is not a grant, so treat it as the safe branch:
            // show the guidance screen rather than a blank viewfinder.
            publish(permission: .denied)
        }
    }

    /// Switches to the other camera, keeping `facing` truthful: it only moves
    /// once the switch has been accepted — either the new input is in the
    /// session, or the session is not up yet and the side has been recorded
    /// for the next configure (PRD FR-5.8). Call on the main queue.
    ///
    /// A tap that lands while a switch is still reconfiguring computes the same
    /// target as the one in flight, so it is a no-op. That debounce is
    /// deliberate: alternating half-finished reconfigurations is how a rapidly
    /// tapped switch button wedges a session.
    func switchCamera() {
        guard isCaptureSupported else { return }
        let target = facing.opposite

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.deviceProvider.device(for: target) else { return }
            guard self.isConfigured else {
                // The session is not up yet; remember the side so the next
                // configure uses it.
                self.sessionFacing = target
                self.publish(facing: target)
                return
            }
            guard let input = try? AVCaptureDeviceInput(device: device) else { return }

            let previous = self.videoInput
            self.session.beginConfiguration()
            if let previous {
                self.session.removeInput(previous)
            }
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoInput = input
                self.sessionFacing = target
                // The new side has its own maximum, and it is usually smaller
                // going to the front camera.
                self.adoptNativeResolution(of: device)
                CameraService.configureLowLatencyCapture(on: self.photoOutput)
                self.session.commitConfiguration()
                // The input swap rebuilds the output's connection, so its
                // mirroring is set again for the new side (issue #272).
                self.applyPhotoMirroring()
                // Supported features and the maximum size changed with the
                // camera, so the prepared settings are redone for it.
                self.preparePhotoOutput()
                // A device keeps its zoom across input swaps, so going back to
                // a side would otherwise resume at its old factor.
                self.resetZoom(on: device)
                if FocusExposurePolicy.shouldReset(on: .cameraFlipped, isLocked: self.focusExposureShadow.isLocked) {
                    self.resetFocusExposure(on: device)
                }
                self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device,
                                                                               previewLayer: nil)
                self.publish(facing: target)
            } else if let previous, self.session.canAddInput(previous) {
                // Put the working input back rather than leaving a dead session.
                self.session.addInput(previous)
                self.adoptNativeResolution(of: previous.device)
                CameraService.configureLowLatencyCapture(on: self.photoOutput)
                self.session.commitConfiguration()
                self.applyPhotoMirroring()
                self.preparePhotoOutput()
                // Still the same side, so it keeps its zoom.
                self.publishZoom(of: previous.device)
            } else {
                // Neither side went in: the session now has no video input at
                // all. Say so, or the user gets a black viewfinder with a live
                // shutter and no way back.
                self.videoInput = nil
                self.session.commitConfiguration()
                self.publish(status: .unavailable(.sessionFailure))
            }
        }
    }
}

// MARK: - Zoom

extension CameraService {

    /// Zooms the current camera to the display factor `factor`, clamped to
    /// `zoomRange`.
    ///
    /// Optical/sensor zoom through `AVCaptureDevice.videoZoomFactor`, never a
    /// crop after capture, so the photo matches the viewfinder and keeps the
    /// resolution the system picks (issue #274). The device is locked and set
    /// on the session queue; `zoomFactor` follows on the main queue once the
    /// device has taken it. A no-op until a camera is configured. Requests are
    /// coalesced (issue #280): this is for a pinch's stream of updates.
    ///
    /// Call on the main queue.
    func setZoomFactor(_ factor: CGFloat) {
        guard isCaptureSupported else { return }
        zoomCoalescer.submit(factor,
                             schedule: { [sessionQueue] work in sessionQueue.async(execute: work) },
                             apply: { [weak self] factor in
            guard let self, let device = self.videoInput?.device else { return }
            guard CameraService.applyZoom(factor, to: device) != nil else { return }
            self.publishZoom(of: device)
        })
    }

    /// Takes the camera to the display factor `displayFactor` with a smooth
    /// ramp, for a quick-zoom button (issue #279). Only changes
    /// `videoZoomFactor`; the session and its input stay as they are.
    ///
    /// Not coalesced and not for a pinch: a ramp lags the fingers.
    ///
    /// Call on the main queue.
    func setZoom(displayFactor: CGFloat, animated: Bool) {
        guard isCaptureSupported else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            let rate: Float? = animated ? CameraService.presetRampRate : nil
            guard CameraService.applyZoom(displayFactor, to: device, rampRate: rate) != nil else { return }
            // A preset can change the physical lens, whose focus and exposure
            // the old tap no longer describes (issue #303).
            if FocusExposurePolicy.shouldReset(on: .zoomPresetSelected, isLocked: self.focusExposureShadow.isLocked) {
                self.resetFocusExposure(on: device)
            }
            self.publishZoom(of: device)
        }
    }

    /// How fast a quick-zoom ramp runs, in doublings of the factor per second.
    static let presetRampRate: Float = 4

    /// The display range a device with these available factors accepts, where
    /// display 1× is device factor `base`: its own range, with the top capped
    /// at `maxZoomFactor`.
    static func zoomRange(minAvailable: CGFloat, maxAvailable: CGFloat, base: CGFloat = 1) -> ZoomRange {
        let maximum = Swift.min(maxAvailable / base, maxZoomFactor)
        return ZoomRange(minimum: Swift.min(minAvailable / base, maximum), maximum: maximum)
    }

    /// The display range `device` accepts.
    static func zoomRange(of device: ZoomableCaptureDevice) -> ZoomRange {
        zoomRange(minAvailable: device.minAvailableVideoZoomFactor,
                  maxAvailable: device.maxAvailableVideoZoomFactor,
                  base: device.zoomLens.baseDeviceFactor)
    }

    /// Clamps the display factor `factor` to `device`'s range and sets the
    /// matching device factor under the configuration lock, ramping when
    /// `rampRate` is given. Returns the display factor set, or nil when the
    /// lock could not be taken and nothing changed.
    @discardableResult
    static func applyZoom(_ factor: CGFloat, to device: ZoomableCaptureDevice, rampRate: Float? = nil) -> CGFloat? {
        let lens = device.zoomLens
        let clamped = zoomRange(of: device).clamp(factor)
        do {
            try device.lockForConfiguration()
        } catch {
            return nil
        }
        // A pinch cuts a running ramp short rather than fighting it.
        if device.isRampingVideoZoom { device.cancelVideoZoomRamp() }
        let target = lens.deviceFactor(forDisplay: clamped)
        if let rampRate {
            device.ramp(toVideoZoomFactor: target, withRate: rampRate)
        } else {
            device.videoZoomFactor = target
        }
        device.unlockForConfiguration()
        return clamped
    }
}

// MARK: - Focus and exposure

extension CameraService {

    /// The range the exposure bias is clamped to for `device`: ±2 EV, further
    /// narrowed to what the device reports.
    static func exposureBiasRange(of device: FocusExposureCaptureDevice) -> ClosedRange<Float> {
        exposureBiasRange(minimum: device.minExposureTargetBias, maximum: device.maxExposureTargetBias)
    }

    /// The device's `minimum...maximum` cut to ±2 EV; never empty and always
    /// inside ±2, even when the device's whole range lies beyond it (it then
    /// collapses to the nearest limit). The one place both the service and the
    /// viewfinder UI take their range from.
    static func exposureBiasRange(minimum: Float, maximum: Float) -> ClosedRange<Float> {
        let limit = maxExposureBiasMagnitude
        let low = Swift.min(Swift.max(minimum, -limit), limit)
        let high = Swift.max(Swift.min(maximum, limit), low)
        return low...high
    }

    /// `point` pulled into the 0...1 device space, or nil when it is not a number.
    static func clampedDevicePoint(_ point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return CGPoint(x: Swift.min(Swift.max(point.x, 0), 1), y: Swift.min(Swift.max(point.y, 0), 1))
    }

    /// Which of focus and exposure a request took effect on.
    struct FocusExposureOutcome: Equatable {
        var focus = false
        var exposure = false
        var tookEffect: Bool { focus || exposure }
    }

    /// Points focus and metering at `point` (0...1 device space) under the
    /// configuration lock, each only if the device supports it, and turns on
    /// subject-area monitoring. Both modes are single-shot `.autoFocus` /
    /// `.autoExpose`: the device settles once and then holds (its mode becomes
    /// `.locked`) until `resetFocusExposure` — which is what an AE/AF lock is.
    /// Resets bias in the same lock unless this is a long-press lock request.
    /// Returns nil when the lock could not be taken and nothing changed.
    static func applyFocusAndExpose(at point: CGPoint,
                                    to device: FocusExposureCaptureDevice,
                                    resetBias: Bool = true) -> FocusExposureOutcome? {
        guard let point = clampedDevicePoint(point) else { return FocusExposureOutcome() }
        do {
            try device.lockForConfiguration()
        } catch {
            return nil
        }
        defer { device.unlockForConfiguration() }
        if resetBias { device.setExposureTargetBias(0, completionHandler: nil) }
        var outcome = FocusExposureOutcome()
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
            outcome.focus = true
        }
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
            device.exposurePointOfInterest = point
            device.exposureMode = .autoExpose
            outcome.exposure = true
        }
        if outcome.tookEffect { device.isSubjectAreaChangeMonitoringEnabled = true }
        return outcome
    }

    /// Sets the exposure bias to `ev` clamped to `exposureBiasRange(of:)` under
    /// the configuration lock. Returns the bias set, or nil when the lock could
    /// not be taken and nothing changed.
    static func applyExposureBias(_ ev: Float, to device: FocusExposureCaptureDevice) -> Float? {
        guard ev.isFinite else { return nil }
        let range = exposureBiasRange(of: device)
        let clamped = Swift.min(Swift.max(ev, range.lowerBound), range.upperBound)
        do {
            try device.lockForConfiguration()
        } catch {
            return nil
        }
        device.setExposureTargetBias(clamped, completionHandler: nil)
        device.unlockForConfiguration()
        return clamped
    }

    /// Back to continuous auto focus and exposure, metering at the centre,
    /// bias 0, monitoring off. Unsupported modes are left alone. Returns false
    /// when the lock could not be taken and nothing changed.
    @discardableResult
    static func applyContinuousAuto(to device: FocusExposureCaptureDevice) -> Bool {
        do {
            try device.lockForConfiguration()
        } catch {
            return false
        }
        let centre = CGPoint(x: 0.5, y: 0.5)
        if device.isFocusModeSupported(.continuousAutoFocus) {
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = centre }
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = centre }
            device.exposureMode = .continuousAutoExposure
        }
        device.setExposureTargetBias(0, completionHandler: nil)
        device.isSubjectAreaChangeMonitoringEnabled = false
        device.unlockForConfiguration()
        return true
    }

    /// Focuses and meters at `devicePoint` (0...1, top-left origin in the
    /// unrotated sensor space; get it from
    /// `AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)`).
    /// Clears a previous lock and resets bias to zero. Call on the main queue.
    /// The state publisher confirms the reset; the UI must clear pending bias
    /// and display zero immediately when submitting a new tap.
    /// Returns the request's id (0 where there is no camera).
    @discardableResult
    func focusAndExpose(at devicePoint: CGPoint) -> Int {
        applyOnDevice(focusRequest: true) { device in
            self.applyTap(at: devicePoint, to: device)
        }
    }

    /// Like `focusAndExpose(at:)`, then holds focus and exposure fixed. The
    /// state only reads locked when the device took at least one of the two.
    /// Call on the main queue. Returns the request's id (0 where there is no camera).
    @discardableResult
    func lockFocusAndExposure(at devicePoint: CGPoint) -> Int {
        applyOnDevice(focusRequest: true) { device in
            guard let outcome = CameraService.applyFocusAndExpose(at: devicePoint, to: device, resetBias: false) else {
                return self.reportFocusExposureFailure()
            }
            self.updateFocusExposure { $0.isLocked = outcome.tookEffect }
        }
    }

    /// Applies a tap and publishes the zero bias/unlocked state together.
    /// Runs on the session queue; invalid points and failed locks change nothing.
    func applyTap(at point: CGPoint, to device: FocusExposureCaptureDevice) {
        guard CameraService.clampedDevicePoint(point) != nil else { return }
        guard let outcome = CameraService.applyFocusAndExpose(at: point, to: device) else {
            return reportFocusExposureFailure()
        }
        guard outcome.tookEffect else {
            // Bias was reset under the lock, but unsupported modes remain unchanged.
            updateFocusExposure {
                $0.exposureBias = 0
                $0.isLocked = device.focusMode == .locked || device.exposureMode == .locked
            }
            return
        }
        updateFocusExposure { $0 = .initial }
        let applied = lastAppliedFocusRequestID
        onMain { [weak self] in self?.focusExposureTapResetSubject.send(applied) }
    }

    /// Sets compensation for the originating focus request, clamped to the
    /// device range. Call on main. Omit the ID for a synchronous current-touch
    /// update; delayed callers must retain and pass the originating request ID.
    func setExposureBias(_ ev: Float, forFocusRequestID requestID: Int? = nil) {
        let origin = requestID ?? focusRequestCounter
        applyOnDevice { device in
            self.applyBias(ev, forFocusRequestID: origin, to: device)
        }
    }

    /// Rejects stale compensation before touching the device or publishing.
    /// Runs on the session queue, ordered with tap and lock requests.
    func applyBias(_ ev: Float, forFocusRequestID requestID: Int, to device: FocusExposureCaptureDevice) {
        guard requestID == lastAppliedFocusRequestID else { return }
        guard let applied = CameraService.applyExposureBias(ev, to: device) else {
            return reportFocusExposureFailure()
        }
        updateFocusExposure { $0.exposureBias = applied }
    }

    /// Back to continuous auto focus/exposure with bias 0 and no lock.
    /// Call on the main queue.
    func resetToContinuousAuto() {
        applyOnDevice { self.resetFocusExposure(on: $0) }
    }

    /// Foreground return: resets as the policy says. Call on the main queue.
    func resetForForeground() {
        guard FocusExposurePolicy.shouldReset(on: .enteredForeground, isLocked: false) else { return }
        resetToContinuousAuto()
    }

    /// Runs `work` with the live device on the session queue; a no-op where
    /// there is no camera. A `focusRequest` is numbered: returns its id, and
    /// the id counts as taken once its turn on the queue comes, device or not.
    @discardableResult
    private func applyOnDevice(focusRequest: Bool = false, _ work: @escaping (AVCaptureDevice) -> Void) -> Int {
        guard isCaptureSupported else { return 0 }
        var id = 0
        if focusRequest {
            focusRequestCounter += 1
            id = focusRequestCounter
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if id > 0 { self.lastAppliedFocusRequestID = id }
            guard let device = self.videoInput?.device else { return }
            self.publishExposureBiasRange(of: device)
            work(device)
        }
        return id
    }

    /// Publishes `exposureBiasRange(of: device)`. Runs on `sessionQueue`.
    private func publishExposureBiasRange(of device: FocusExposureCaptureDevice) {
        let range = CameraService.exposureBiasRange(of: device)
        onMain { [weak self] in
            guard let self, self.exposureBiasRange != range else { return }
            self.exposureBiasRange = range
        }
    }

    /// Resets `device` and the published state. Runs on `sessionQueue`.
    func resetFocusExposure(on device: FocusExposureCaptureDevice) {
        publishExposureBiasRange(of: device)
        guard CameraService.applyContinuousAuto(to: device) else {
            return reportFocusExposureFailure()
        }
        updateFocusExposure { $0 = .initial }
        let applied = lastAppliedFocusRequestID
        onMain { [weak self] in self?.focusExposureResetSubject.send(applied) }
    }

    /// Device-level "scene changed" handler. Runs the reset only for the live
    /// device and only while not locked (issue #303).
    private func subjectAreaDidChange(from source: AnyObject?) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device, source === device else { return }
            guard FocusExposurePolicy.shouldReset(on: .subjectAreaChanged,
                                                  isLocked: self.focusExposureShadow.isLocked) else { return }
            self.resetFocusExposure(on: device)
        }
    }

    private func updateFocusExposure(_ change: (inout FocusExposureState) -> Void) {
        change(&focusExposureShadow)
        let value = focusExposureShadow
        onMain { [weak self] in
            guard let self, self.focusExposureSubject.value != value else { return }
            self.focusExposureSubject.send(value)
        }
    }

    private func reportFocusExposureFailure() {
        onMain { [weak self] in self?.focusExposureFailureSubject.send(.lockFailed) }
    }
}

// MARK: - Capture

extension CameraService {

    /// Takes one photo.
    ///
    /// The completion is always called exactly once, on the main queue.
    ///
    /// The returned image is handed back exactly as AVFoundation produced it,
    /// so its `imageOrientation` may be `.right` or `.down` rather than `.up`.
    /// Normalising is `OverlayRenderer.bake`'s job (TASK-09), which has to
    /// redraw the pixels anyway — doing it twice would mean two full-resolution
    /// redraws per shutter press.
    ///
    /// Nothing here knows about dates, profiles or overlay text: the shutter
    /// hands the image on, and the caller decides what to print on it
    /// (PRD §6.5.4).
    ///
    /// Call on the main queue. The guards reject synchronously, so a rejected
    /// call runs `completion` *before* this method returns — set any
    /// "capture in flight" flag before calling, not after (PRD FR-5.5).
    ///
    /// - Parameter flashMode: what was requested from the toolbar. Forced to
    ///   `.off` internally whenever `isFlashAvailable` is false, regardless
    ///   of what is passed (PRD 0.2 FR-5.12, FR-7.4) — see
    ///   `effectiveFlashMode(requested:isFlashAvailable:)`. Defaults to
    ///   `.off` so an existing caller that has not yet been wired to
    ///   `CaptureSettingsStore` (TASK-21) keeps compiling and behaving as
    ///   before.
    func capturePhoto(flashMode: FlashMode = .off,
                      completion: @escaping (Result<UIImage, CameraCaptureError>) -> Void) {
        guard isCaptureSupported else {
            onMain { completion(.failure(.captureUnavailable)) }
            return
        }
        guard status == .running else {
            onMain { completion(.failure(.notRunning)) }
            return
        }

        // Read on the calling (main) thread, per this type's own threading
        // contract — `facing` only changes there, and `effectiveFlashMode`
        // is the pure decision the acceptance criteria test directly.
        let resolvedFlashMode = CameraService.effectiveFlashMode(requested: flashMode,
                                                                  isFlashAvailable: isFlashAvailable)

        // The shutter-lag clock starts here, on the press, not once the
        // session queue gets round to it: focus, zoom or a configuration
        // queued ahead of this capture is part of the lag (TASK-145 #501).
        CameraService.schedule(on: sessionQueue) { [weak self] shutterPressedAt in
            guard let self else { return }
            guard self.isConfigured, self.session.isRunning else {
                self.onMain { completion(.failure(.notRunning)) }
                return
            }

            if let connection = self.photoOutput.connection(with: .video),
               let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
               connection.isVideoRotationAngleSupported(angle) {
                // Rotate at capture time so the picture comes out the way the
                // phone was held, rather than the way the sensor is mounted.
                connection.videoRotationAngle = angle
            }

            let delegate = PhotoCaptureDelegate { [weak self] result, delegate in
                // The answer does not depend on the service still being
                // around, so it is delivered first and unconditionally; only
                // the bookkeeping is skipped when the service has gone.
                DispatchQueue.main.async { completion(result) }
                self?.sessionQueue.async {
                    self?.captureDelegates.removeValue(forKey: ObjectIdentifier(delegate))
                }
            }
            self.captureDelegates[ObjectIdentifier(delegate)] = delegate
            let settings = CameraService.makePhotoSettings(for: self.photoOutput, flashMode: resolvedFlashMode)
            CaptureTiming.begin(id: delegate.timingID, at: shutterPressedAt)
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    /// Reads the clock now, on the caller's thread, then runs `work` on
    /// `queue` with that moment: what `capturePhoto` times from (TASK-145).
    static func schedule(on queue: DispatchQueue,
                         now: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent,
                         _ work: @escaping (CFAbsoluteTime) -> Void) {
        let scheduledAt = now()
        queue.async { work(scheduledAt) }
    }
}

// MARK: - Prepared settings

extension CameraService {

    /// Prepares the photo output for `flashMode`; call when the flash mode
    /// changes (and the camera switch does it by itself with the last value).
    /// A no-op until a camera is configured; the mode is remembered for then.
    ///
    /// Call on the main queue.
    func prepareCapture(flashMode: FlashMode) {
        guard isCaptureSupported else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.requestedFlashMode = flashMode
            guard self.isConfigured else { return }
            self.preparePhotoOutput()
        }
    }

    /// The settings every photo is taken with, and the ones prepared ahead of
    /// time: they must match, or the preparation does not help.
    static func makePhotoSettings(for output: PhotoOutputConfiguring,
                                  flashMode: AVCaptureDevice.FlashMode) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        // Ask for the full sensor resolution the output was configured
        // for (10.18). Taken from the output rather than the device so it
        // can never exceed what the output allows, which would raise an
        // uncatchable exception.
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        // Never above the output's `maxPhotoQualityPrioritization`, which is
        // also `.balanced`; `.speed` is a quality trade-off left to a human.
        settings.photoQualityPrioritization = .balanced
        // Only ever a mode the output actually reports supporting —
        // assigning an unsupported one is silently ignored by
        // AVFoundation, but checking here keeps the intent explicit
        // (PRD 0.2 FR-5.12).
        if output.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        }
        return settings
    }

    /// Turns on the low-latency capture features the current session
    /// configuration supports, and nothing it does not: assigning `true` to an
    /// unsupported one raises an Objective-C exception.
    ///
    /// Call inside `beginConfiguration`/`commitConfiguration` once the input
    /// and output are in the session, and again after every input swap: what
    /// is supported depends on the camera and format, and a feature that
    /// became unsupported reverts to off by itself.
    static func configureLowLatencyCapture(on output: PhotoOutputConfiguring) {
        output.maxPhotoQualityPrioritization = .balanced
        // Responsive capture needs zero shutter lag, which is on by default
        // when supported; make sure of it rather than assume.
        if output.isZeroShutterLagSupported, !output.isZeroShutterLagEnabled {
            output.isZeroShutterLagEnabled = true
        }
        let responsive = output.isResponsiveCaptureSupported
        if output.isResponsiveCaptureEnabled != responsive {
            output.isResponsiveCaptureEnabled = responsive
        }
        // Fast capture follows its own support flag only (TASK-143 #499): a
        // format can support it without zero shutter lag, so without
        // responsive capture. Still set after responsive capture, since the
        // output may only report support once that one is decided.
        let fast = output.isFastCapturePrioritizationSupported
        if output.isFastCapturePrioritizationEnabled != fast {
            output.isFastCapturePrioritizationEnabled = fast
        }
    }

    /// Tells the output which settings the next photo will use, so the first
    /// shutter press does not allocate buffers just in time.
    static func preparePhotoSettings(on output: PhotoOutputConfiguring, flashMode: AVCaptureDevice.FlashMode) {
        let settings = makePhotoSettings(for: output, flashMode: flashMode)
        output.setPreparedPhotoSettingsArray([settings], completionHandler: nil)
    }

    /// Re-prepares the photo settings for the camera now in the session. Runs on `sessionQueue`, after the
    /// configuration is committed.
    func preparePhotoOutput() {
        let hasFlash = cachedHasFlash(for: sessionFacing)
        let available = CameraService.isFlashAvailable(facing: sessionFacing, hasFlash: hasFlash)
        let flash = CameraService.effectiveFlashMode(requested: requestedFlashMode, isFlashAvailable: available)
        CameraService.preparePhotoSettings(on: photoOutput, flashMode: flash)
    }
}

// MARK: - Session configuration

private extension CameraService {

    /// Configures the session if needed and starts it, all off the main thread.
    func run() {
        // The foreground observer refreshes permission on every return to the
        // app, so without this a session stopped by `stop()` would come back
        // behind a screen that is no longer showing a viewfinder.
        guard isActive else { return }

        guard isCaptureSupported else {
            publish(status: .unavailable(.simulator))
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                guard self.configureSession() else { return }
                self.isConfigured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            self.publish(status: self.session.isRunning ? .running : .unavailable(.sessionFailure))
        }
    }

    /// Builds the session. Runs on `sessionQueue`.
    ///
    /// Publishes the reason and returns false on any failure, so the caller can
    /// simply stop.
    func configureSession() -> Bool {
        flashCache.withLock { $0.removeAll() }
        guard let device = deviceProvider.device(for: sessionFacing) else {
            publish(status: .unavailable(.noCaptureDevice))
            return false
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            publish(status: .unavailable(.sessionFailure))
            return false
        }

        session.beginConfiguration()
        // `.photo` is the sensor's native 4:3, which is the only ratio the app
        // offers (PRD FR-5.7). The viewfinder matches it (FR-6.3).
        session.sessionPreset = .photo

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            publish(status: .unavailable(.sessionFailure))
            return false
        }
        session.addInput(input)
        videoInput = input

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            publish(status: .unavailable(.sessionFailure))
            return false
        }
        session.addOutput(photoOutput)
        adoptNativeResolution(of: device)
        CameraService.configureLowLatencyCapture(on: photoOutput)
        session.commitConfiguration()
        applyPhotoMirroring()
        preparePhotoOutput()
        resetZoom(on: device)
        resetFocusExposure(on: device)

        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        return true
    }

    /// Asks the output for this device's full sensor resolution instead of the
    /// smaller default (acceptance 10.18).
    ///
    /// Must be redone whenever the input changes: the front camera's maximum
    /// is smaller than the back one's, and asking a capture for more than the
    /// output currently allows raises an Objective-C exception that Swift
    /// cannot catch — the app would die on the shutter press.
    func adoptNativeResolution(of device: AVCaptureDevice) {
        guard let largest = CameraService.largestPhotoDimensions(
            from: device.activeFormat.supportedMaxPhotoDimensions
        ) else { return }
        photoOutput.maxPhotoDimensions = largest
    }

    /// Mirrors the photo output for the side now in the session, so a front
    /// camera photo matches its (mirrored) preview (issue #272).
    ///
    /// Must be redone after every input change, once the new input is in:
    /// the output's connection is rebuilt with it. Mirroring happens in the
    /// capture pipeline, before the overlay is baked onto the delivered
    /// image, so the overlay text itself is never mirrored.
    func applyPhotoMirroring() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        CameraService.configureMirroring(of: connection, for: sessionFacing)
    }

    /// Puts `device` back to 1× (the main camera, or the nearest allowed
    /// factor) and publishes its range and presets, for a camera that has just
    /// gone into the session.
    func resetZoom(on device: ZoomableCaptureDevice) {
        CameraService.applyZoom(1, to: device)
        publishZoom(of: device)
    }

    /// Publishes `device`'s current display factor, range and presets. Runs on
    /// `sessionQueue`.
    func publishZoom(of device: ZoomableCaptureDevice) {
        let lens = device.zoomLens
        let plan = ZoomPlan.make(lens: lens,
                                 minAvailable: device.minAvailableVideoZoomFactor,
                                 maxAvailable: device.maxAvailableVideoZoomFactor,
                                 offersCropPresets: sessionFacing == .back)
        let range = plan.range
        let factor = lens.displayFactor(forDevice: device.videoZoomFactor)
        onMain { [weak self] in
            guard let self else { return }
            if self.availableZoomPresets != plan.presets { self.availableZoomPresets = plan.presets }
            if self.zoomRange != range { self.zoomRange = range }
            if self.zoomFactorSubject.value != factor { self.zoomFactorSubject.send(factor) }
        }
    }
}

// MARK: - Notifications

private extension CameraService {

    func registerObservers() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                                            object: session,
                                            queue: .main) { [weak self] _ in
            self?.publish(status: .interrupted)
        })

        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                                            object: session,
                                            queue: .main) { [weak self] _ in
            // The system resumes the session itself; re-running settles the
            // published status back to whatever is actually true now.
            self?.run()
        })

        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                            object: session,
                                            queue: .main) { [weak self] _ in
            self?.publish(status: .unavailable(.sessionFailure))
        })

        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            self?.refreshPermission()
            self?.resetForForeground()
        })

        // Posted by the device itself; the current device changes on a flip,
        // so listen to all and let the handler check it is the live one.
        observers.append(center.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification,
                                            object: nil,
                                            queue: nil) { [weak self] notification in
            self?.subjectAreaDidChange(from: notification.object as AnyObject?)
        })
    }
}

// MARK: - Publishing

private extension CameraService {

    /// Runs `work` on the main queue, synchronously when already there so a
    /// caller on the main thread sees the new value immediately.
    func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func publish(permission newValue: CameraPermission) {
        onMain { [weak self] in
            guard let self, self.permission != newValue else { return }
            self.permission = newValue
        }
    }

    func publish(status newValue: CameraStatus) {
        onMain { [weak self] in
            guard let self, self.status != newValue else { return }
            self.status = newValue
        }
    }

    func publish(facing newValue: CameraFacing) {
        onMain { [weak self] in
            guard let self, self.facing != newValue else { return }
            self.facing = newValue
        }
    }
}

// MARK: - Photo delegate

/// One-shot delegate for a single `capturePhoto` call.
///
/// AVFoundation does not retain the delegate, so `CameraService` holds it until
/// the callback fires and then drops it, using the delegate handed back here.
///
/// Internal rather than private only so the "answers exactly once" guard can be
/// tested directly — that guarantee is what keeps the shutter from staying
/// disabled forever (PRD FR-5.5). Nothing outside this file constructs one.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private let finish: (Result<UIImage, CameraCaptureError>, PhotoCaptureDelegate) -> Void
    /// Tells this capture's timing apart from any other in flight (DEBUG log).
    let timingID = UUID()
    private let hasFinished = OSAllocatedUnfairLock(initialState: false)

    /// - Parameter finish: called at most once, with the result and this
    ///   delegate so the caller can release it.
    init(finish: @escaping (Result<UIImage, CameraCaptureError>, PhotoCaptureDelegate) -> Void) {
        self.finish = finish
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            deliver(.failure(.failed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            deliver(.failure(.noImageData))
            return
        }
        CaptureTiming.markProcessed(id: timingID, image: image)
        deliver(.success(image))
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // The exposure is starting: the shutter lag the user feels (TASK-143).
        CaptureTiming.markWillCapture(id: timingID)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        CaptureTiming.logCaptureFinished(id: timingID)
        // This is the last callback of a capture, so it is where the completion
        // is guaranteed to have run exactly once: `deliver` ignores the second
        // call when processing already answered, and answers here when it
        // never did. Without this the shutter could stay disabled forever.
        if let error {
            deliver(.failure(.failed(error.localizedDescription)))
        } else {
            deliver(.failure(.noImageData))
        }
    }

    /// Answers for a capture that will never come back, e.g. because the
    /// session was stopped underneath it. Ignored once a real answer has been
    /// delivered.
    func cancel() {
        deliver(.failure(.notRunning))
    }

    private func deliver(_ result: Result<UIImage, CameraCaptureError>) {
        // `didFinishProcessingPhoto` and `didFinishCaptureFor` both fire for a
        // successful capture, and `cancel` can race either of them. Without
        // this guard a success is immediately followed by a `.noImageData`
        // failure, and TASK-10's shutter acts on the wrong one.
        // Check-and-set is one atomic step: `cancel` runs on the session queue
        // while the callbacks run on AVFoundation's queue (#465). `finish`
        // is called outside the lock.
        let isFirst = hasFinished.withLock { finished -> Bool in
            if finished { return false }
            finished = true
            return true
        }
        guard isFirst else { return }
        if case .failure = result { CaptureTiming.discard(id: timingID) }
        finish(result, self)
    }
}

// MARK: - Photo resolution

extension CameraService {
    /// Pixel budget for a captured photo: 5712x4284, the 24MP size Apple's
    /// own camera defaults to. Newer phones also offer 48MP, which makes the
    /// capture, crop, bake and save all about twice as heavy (#154).
    static let maxPhotoPixelCount = 5712 * 4284

    /// The dimensions with the most pixels that still fit within
    /// `maxPhotoPixelCount` (acceptance 10.18, issue #154). When every
    /// candidate is over the budget, the smallest one is used instead.
    ///
    /// Picking by width alone would choose a wide, short format over a larger
    /// one. Internal rather than private so the choice can be unit tested;
    /// applying it needs a real camera, so that part is verified on a device.
    static func largestPhotoDimensions(from candidates: [CMVideoDimensions]) -> CMVideoDimensions? {
        func pixelCount(_ dimensions: CMVideoDimensions) -> Int {
            Int(dimensions.width) * Int(dimensions.height)
        }
        let withinBudget = candidates.filter { pixelCount($0) <= maxPhotoPixelCount }
        if withinBudget.isEmpty {
            return candidates.min { pixelCount($0) < pixelCount($1) }
        }
        return withinBudget.max { pixelCount($0) < pixelCount($1) }
    }

    /// The flash mode actually sent to `AVCapturePhotoSettings`, given what
    /// was requested and whether the flash is currently available.
    ///
    /// Forces `.off` whenever `isFlashAvailable` is false — the front camera,
    /// or a back camera with no flash unit — regardless of what was
    /// requested (PRD 0.2 FR-5.12, FR-7.4, acceptance 19.4).
    ///
    /// Internal rather than private, and a pure function of its two
    /// arguments, so this decision is testable without a real capture
    /// device: `isFlashAvailable` itself needs one (there is no public
    /// `AVCaptureDevice` initializer to fake `hasFlash` with), but this
    /// function does not.
    static func effectiveFlashMode(requested: FlashMode, isFlashAvailable: Bool) -> AVCaptureDevice.FlashMode {
        guard isFlashAvailable else { return .off }
        switch requested {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }

    /// Whether the flash can fire on `facing`, given whether that side
    /// reports a flash unit: never on the front camera, regardless of
    /// `hasFlash` (PRD 0.2 FR-7.4, acceptance 19.4).
    ///
    /// A free function of its two arguments — unlike the instance property
    /// `isFlashAvailable`, this needs no real `CameraFacing` switch to have
    /// actually succeeded (which `CameraServiceTests`' `EmptyDeviceProvider`
    /// cannot make happen, by design: a switch to a device that does not
    /// exist must not lie about which side is active). Tests exercise the
    /// front-camera and no-flash-device branches by calling this directly.
    static func isFlashAvailable(facing: CameraFacing, hasFlash: Bool) -> Bool {
        facing == .back && hasFlash
    }

    /// Whether a photo taken on `facing` is mirrored: the front camera's is,
    /// like its preview and like the system Camera with 鏡像前置相機 on; the
    /// back camera's never is (issue #272). Fixed, not a setting, in 0.5.
    static func isPhotoMirrored(facing: CameraFacing) -> Bool {
        facing == .front
    }

    /// Sets `connection`'s mirroring for `facing`.
    ///
    /// Automatic adjustment is turned off first: assigning `isVideoMirrored`
    /// while it is on raises an exception, as does assigning it on a
    /// connection that does not support mirroring, which is left alone.
    /// Internal so the decision is testable against a fake connection.
    static func configureMirroring(of connection: VideoMirroringConfigurable, for facing: CameraFacing) {
        guard connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isPhotoMirrored(facing: facing)
    }
}


// MARK: - Capture timing

/// The timing of each in-flight capture, keyed so overlapping captures keep
/// their own marks (TASK-151, #529; the pipeline now holds up to two photos).
/// Pure, with the clock passed in, so it is testable in any build.
final class CaptureTimingRecorder {
    enum Stage: Int, CaseIterable {
        case processed, baked, saved
    }

    private struct Record {
        var start: CFAbsoluteTime
        var willCapture: CFAbsoluteTime?
        var marks: [Stage: CFAbsoluteTime] = [:]
        var size: CGSize = .zero
    }

    private struct State {
        var records: [UUID: Record] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Starts timing capture `id` from `start`, the moment the shutter was
    /// pressed (TASK-145 #501).
    func begin(id: UUID, at start: CFAbsoluteTime) {
        state.withLock { $0.records[id] = Record(start: start) }
    }

    /// Records `willCapturePhotoFor`, the start of the exposure.
    func markWillCapture(id: UUID, at now: CFAbsoluteTime) {
        state.withLock { $0.records[id]?.willCapture = now }
    }

    /// The `logCaptureFinished` line for capture `id`, or `nil` when it is
    /// not being timed.
    func finishedLine(id: UUID, at now: CFAbsoluteTime) -> String? {
        state.withLock { state in
            state.records[id].map {
                CaptureTiming.captureFinishedLine(start: $0.start, willCapture: $0.willCapture, finished: now)
            }
        }
    }

    /// Records that capture `id` produced its photo, of `size` pixels.
    func markProcessed(id: UUID, size: CGSize, at now: CFAbsoluteTime) {
        state.withLock { state in
            guard state.records[id] != nil else { return }
            state.records[id]?.marks[.processed] = now
            state.records[id]?.size = size
        }
    }

    /// Records that `stage` of capture `id` finished at `now`. Returns the
    /// one-line summary when `.saved` completes the capture, and forgets it.
    func mark(_ stage: Stage, id: UUID, at now: CFAbsoluteTime) -> String? {
        state.withLock { state in
            guard var record = state.records[id] else { return nil }
            record.marks[stage] = now
            guard stage == .saved else {
                state.records[id] = record
                return nil
            }
            state.records[id] = nil
            var previous = record.start
            var parts: [String] = []
            for stage in Stage.allCases {
                guard let time = record.marks[stage] else { continue }
                parts.append("\(stage)=\(Int((time - previous) * 1000))ms")
                previous = time
            }
            let toBaked = record.marks[.baked].map { Int(($0 - record.start) * 1000) }
            let total = Int((now - record.start) * 1000)
            return "\(parts.joined(separator: " ")) shutterToBaked=\(toBaked.map(String.init) ?? "n/a")ms total=\(total)ms size=\(Int(record.size.width))x\(Int(record.size.height))"
        }
    }

    /// Forgets a capture that will not reach `.saved` (failed, timed out or
    /// never produced a photo).
    func discard(id: UUID) {
        state.withLock { $0.records[id] = nil }
    }
}

/// Per-stage timing of each capture, logged as one line per photo (category
/// `capture-timing`, DEBUG builds only; issue #154). Captures are told apart
/// by an ID the camera assigns, then by the photo they produced, so two
/// photos in flight at once each log their own begin → baked → saved.
enum CaptureTiming {
    typealias Stage = CaptureTimingRecorder.Stage

    private static let recorder = CaptureTimingRecorder()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DaysCam",
                                       category: "capture-timing")

    /// Starts timing capture `id` from `start` (DEBUG only).
    static func begin(id: UUID, at start: CFAbsoluteTime) {
        #if DEBUG
        recorder.begin(id: id, at: start)
        #endif
    }

    /// DEBUG only: records `willCapturePhotoFor`, the start of the exposure.
    static func markWillCapture(id: UUID) {
        #if DEBUG
        recorder.markWillCapture(id: id, at: CFAbsoluteTimeGetCurrent())
        #endif
    }

    /// DEBUG only: logs the shutter lag (press → `willCapturePhotoFor`, the
    /// number to compare before and after low-latency capture; TASK-143
    /// #499) and, as a separate stage, press → `didFinishCapture`, which
    /// also includes the image processing (TASK-130).
    static func logCaptureFinished(id: UUID) {
        #if DEBUG
        guard let line = recorder.finishedLine(id: id, at: CFAbsoluteTimeGetCurrent()) else { return }
        logger.debug("\(line, privacy: .public)")
        #endif
    }

    /// The `logCaptureFinished` line; `n/a` when `willCapturePhotoFor` never
    /// came.
    static func captureFinishedLine(start: CFAbsoluteTime,
                                    willCapture: CFAbsoluteTime?,
                                    finished: CFAbsoluteTime) -> String {
        func milliseconds(_ end: CFAbsoluteTime) -> String { "\(Int(((end - start) * 1000).rounded()))ms" }
        return "shutterToWillCapture=\(willCapture.map(milliseconds) ?? "n/a") shutterToDidFinishCapture=\(milliseconds(finished))"
    }

    /// The key `timingID(of:)` reads the capture ID back with.
    private static let timingIDKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    /// DEBUG only: capture `id` produced `image`. The ID travels on the image
    /// itself (not on its memory address, which a later photo may reuse), so
    /// the bake and save stages can find their capture again.
    static func markProcessed(id: UUID, image: UIImage) {
        #if DEBUG
        objc_setAssociatedObject(image, timingIDKey, id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        recorder.markProcessed(id: id,
                               size: CGSize(width: image.size.width * image.scale,
                                            height: image.size.height * image.scale),
                               at: CFAbsoluteTimeGetCurrent())
        #endif
    }

    /// The capture ID `markProcessed(id:image:)` attached to `image`; nil in
    /// release builds and for images the camera did not capture.
    static func timingID(of image: UIImage) -> UUID? {
        objc_getAssociatedObject(image, timingIDKey) as? UUID
    }

    /// DEBUG only: `stage` of capture `id` finished now. Logs once `.saved`
    /// is marked.
    static func mark(_ stage: Stage, id: UUID?) {
        #if DEBUG
        guard let id, let line = recorder.mark(stage, id: id, at: CFAbsoluteTimeGetCurrent()) else { return }
        logger.debug("\(line, privacy: .public)")
        #endif
    }

    /// DEBUG only: capture `id` will not reach `.saved`.
    static func discard(id: UUID?) {
        #if DEBUG
        if let id { recorder.discard(id: id) }
        #endif
    }
}
