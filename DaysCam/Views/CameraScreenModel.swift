import Foundation

/// Drives PRD S-1, the camera screen.
///
/// Starts out (TASK-07) owning just the camera lifecycle and how to read
/// `CameraService`'s published state; TASK-08 onward extend it with the
/// profile-driven overlay, the display-settings sheet and the profile
/// switcher. `CameraScreen` only lays out whatever this model currently says
/// — see `docs/TASKS.md`'s note on why UI-level acceptance criteria live
/// here rather than in the view.
@MainActor
final class CameraScreenModel: ObservableObject {
    let cameraService: CameraService

    init(cameraService: CameraService) {
        self.cameraService = cameraService
    }

    /// Called when the screen appears. Permission is requested here, not at
    /// app launch (PRD §2.2).
    func onAppear() {
        cameraService.start()
    }

    /// Called when the screen disappears. Pairs with `onAppear` — per
    /// `CameraService.stop()`'s own doc comment, a screen that stops on
    /// backgrounding must call `onAppear` again on the way back.
    func onDisappear() {
        cameraService.stop()
    }

    func switchCamera() {
        cameraService.switchCamera()
    }

    /// The label the placeholder viewfinder shows in the simulator (PRD §2.4).
    static let simulatorPlaceholderText = "模擬器不支援拍照"

    /// Whether the viewfinder should show the simulator/placeholder
    /// background instead of a live preview (PRD §2.4).
    var showsPlaceholder: Bool {
        !cameraService.isCaptureSupported
    }

    /// Whether the shutter should be disabled right now.
    ///
    /// True whenever a live picture is not actually on screen: no capture
    /// support (simulator), permission not granted, or the session is not
    /// `.running`. TASK-10 wires the shutter's action itself; this only
    /// decides whether it may be tapped at all.
    var isShutterDisabled: Bool {
        !cameraService.isCaptureSupported
            || cameraService.permission.needsGuidance
            || cameraService.status != .running
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
