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

/// Production device lookup: the built-in wide angle camera on each side.
struct SystemCaptureDeviceProvider: CaptureDeviceProviding {
    func device(for facing: CameraFacing) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                         mediaType: .video,
                                         position: facing.captureDevicePosition)
            .devices
            .first
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
    var isFlashAvailable: Bool {
        CameraService.isFlashAvailable(facing: facing, hasFlash: flashCapabilityProvider.hasFlash(for: facing))
    }

    private let authorizer: CameraAuthorizing
    private let deviceProvider: CaptureDeviceProviding
    private let flashCapabilityProvider: FlashCapabilityProviding
    private let sessionQueue = DispatchQueue(label: "com.irenechou.DaysCam.camera-session")
    private let photoOutput = AVCapturePhotoOutput()

    /// Touched on `sessionQueue` only.
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var sessionFacing: CameraFacing = .back
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
    init(authorizer: CameraAuthorizing = SystemCameraAuthorizer(),
         deviceProvider: CaptureDeviceProviding = SystemCaptureDeviceProvider(),
         flashCapabilityProvider: FlashCapabilityProviding? = nil,
         isCaptureSupported: Bool = CameraService.platformSupportsCapture) {
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
                self.session.commitConfiguration()
                // The input swap rebuilds the output's connection, so its
                // mirroring is set again for the new side (issue #272).
                self.applyPhotoMirroring()
                self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device,
                                                                               previewLayer: nil)
                self.publish(facing: target)
            } else if let previous, self.session.canAddInput(previous) {
                // Put the working input back rather than leaving a dead session.
                self.session.addInput(previous)
                self.adoptNativeResolution(of: previous.device)
                self.session.commitConfiguration()
                self.applyPhotoMirroring()
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

        sessionQueue.async { [weak self] in
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
            let settings = AVCapturePhotoSettings()
            // Ask for the full sensor resolution the output was configured
            // for (10.18). Taken from the output rather than the device so it
            // can never exceed what the output allows, which would raise an
            // uncatchable exception.
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            // Only ever a mode the output actually reports supporting —
            // assigning an unsupported one is silently ignored by
            // AVFoundation, but checking here keeps the intent explicit
            // (PRD 0.2 FR-5.12).
            if self.photoOutput.supportedFlashModes.contains(resolvedFlashMode) {
                settings.flashMode = resolvedFlashMode
            }
            CaptureTiming.begin()
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
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
        session.commitConfiguration()
        applyPhotoMirroring()

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
    private var hasFinished = false

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
        CaptureTiming.mark(.processed, size: CGSize(width: image.size.width * image.scale,
                                                    height: image.size.height * image.scale))
        deliver(.success(image))
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
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
        guard hasFinished == false else { return }
        hasFinished = true
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

/// Per-stage timing of one capture, logged as a single line per photo
/// (category `capture-timing`, DEBUG builds only; issue #154).
///
/// A static recorder rather than a value threaded through the pipeline: the
/// shutter is disabled while a capture is in flight, so at most one is timed
/// at a time, and this keeps the instrumentation out of the control flow.
enum CaptureTiming {
    enum Stage: Int, CaseIterable {
        case processed, cropped, baked, saved
    }

    private struct State {
        var start: CFAbsoluteTime?
        var marks: [Stage: CFAbsoluteTime] = [:]
        var size: CGSize = .zero
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DaysCam",
                                       category: "capture-timing")

    /// Starts timing a new capture, at the moment the shutter fires.
    static func begin() {
        #if DEBUG
        state.withLock { $0 = State(start: CFAbsoluteTimeGetCurrent()) }
        #endif
    }

    /// Records that `stage` finished now. `size` is the photo's pixel size,
    /// kept from the stage that knows it. Logs once `.saved` is marked.
    static func mark(_ stage: Stage, size: CGSize? = nil) {
        #if DEBUG
        let now = CFAbsoluteTimeGetCurrent()
        let line: String? = state.withLock { state in
            guard let start = state.start else { return nil }
            state.marks[stage] = now
            if let size { state.size = size }
            guard stage == .saved else { return nil }
            var previous = start
            var parts: [String] = []
            for stage in Stage.allCases {
                guard let time = state.marks[stage] else { continue }
                parts.append("\(stage)=\(Int((time - previous) * 1000))ms")
                previous = time
            }
            let toBaked = state.marks[.baked].map { Int(($0 - start) * 1000) }
            let total = Int((now - start) * 1000)
            state.start = nil
            return "\(parts.joined(separator: " ")) shutterToBaked=\(toBaked.map(String.init) ?? "n/a")ms total=\(total)ms size=\(Int(state.size.width))x\(Int(state.size.height))"
        }
        if let line { logger.debug("\(line, privacy: .public)") }
        #endif
    }
}
