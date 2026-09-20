import AVFoundation
import Combine
import Foundation
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

    private let authorizer: CameraAuthorizing
    private let deviceProvider: CaptureDeviceProviding
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

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - authorizer: permission source; defaults to `AVCaptureDevice`.
    ///   - deviceProvider: device lookup; defaults to the discovery session.
    ///   - isCaptureSupported: false disables every hardware path, which is
    ///     what the simulator gets.
    init(authorizer: CameraAuthorizing = SystemCameraAuthorizer(),
         deviceProvider: CaptureDeviceProviding = SystemCaptureDeviceProvider(),
         isCaptureSupported: Bool = CameraService.platformSupportsCapture) {
        self.authorizer = authorizer
        self.deviceProvider = deviceProvider
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
    func start() {
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

    /// Stops the session and returns to idle. Called when the camera screen
    /// goes away or the app leaves the foreground.
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
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
    func refreshPermission() {
        start()
    }

    /// Switches to the other camera, keeping `facing` truthful: it only moves
    /// once the new input is actually in the session (PRD FR-5.8).
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
                self.session.commitConfiguration()
                self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device,
                                                                               previewLayer: nil)
                self.publish(facing: target)
            } else {
                // Put the working input back rather than leaving a dead session.
                if let previous, self.session.canAddInput(previous) {
                    self.session.addInput(previous)
                }
                self.session.commitConfiguration()
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
    func capturePhoto(completion: @escaping (Result<UIImage, CameraCaptureError>) -> Void) {
        guard isCaptureSupported else {
            onMain { completion(.failure(.captureUnavailable)) }
            return
        }
        guard status == .running else {
            onMain { completion(.failure(.notRunning)) }
            return
        }

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
                guard let self else { return }
                self.sessionQueue.async {
                    self.captureDelegates.removeValue(forKey: ObjectIdentifier(delegate))
                }
                self.onMain { completion(result) }
            }
            self.captureDelegates[ObjectIdentifier(delegate)] = delegate
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }
    }
}

// MARK: - Session configuration

private extension CameraService {

    /// Configures the session if needed and starts it, all off the main thread.
    func run() {
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
        session.commitConfiguration()

        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        return true
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
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private let finish: (Result<UIImage, CameraCaptureError>, PhotoCaptureDelegate) -> Void
    private var hasFinished = false

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

    private func deliver(_ result: Result<UIImage, CameraCaptureError>) {
        guard !hasFinished else { return }
        hasFinished = true
        finish(result, self)
    }
}
