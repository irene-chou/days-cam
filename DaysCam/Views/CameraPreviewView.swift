import AVFoundation
import SwiftUI

/// Wraps an `AVCaptureVideoPreviewLayer` bound to `session` (PRD S-1).
///
/// `CameraService` deliberately does not own a preview layer — layer sizing
/// and rotation belong to the view, tied to its own layout lifecycle rather
/// than the service's (see `CameraService`'s doc comment). This is the one
/// place that builds one.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Gets the preview layer, for converting touch points (issue #303).
    var bridge: PreviewLayerBridge?
    /// Called when a hardware capture button (volume keys, Action button,
    /// Camera Control) is released (#686).
    var onCaptureEvent: () -> Void = {}
    /// False while the camera screen is not the active foreground screen, so
    /// the volume keys go back to adjusting volume (#686).
    var isCaptureEventEnabled = true

    func makeUIView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView(onCaptureEvent: onCaptureEvent)
        view.isCaptureEventEnabled = isCaptureEventEnabled
        view.videoPreviewLayer.session = session
        bridge?.layer = view.videoPreviewLayer
        // `.resizeAspectFill` (changed from `.resizeAspect` in TASK-21):
        // `CameraScreen` now sizes this view's container to the *selected*
        // `CaptureAspectRatio` (3:4, 1:1 or 9:16), not always the sensor's
        // native 4:3 — so what's on screen must be center-cropped to that
        // container exactly the way `ImageCropper` center-crops the saved
        // photo (PRD 0.2 FR-5.11), the same "so you see what you get"
        // reasoning TASK-07's acceptance 7.2 already established for the
        // 4:3 case. At 3:4 the container still matches the sensor exactly,
        // so this is a no-op there.
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewContainerView, context: Context) {
        // `session` is fixed for this view's lifetime; only the hardware
        // shutter hookup can change.
        uiView.onCaptureEvent = onCaptureEvent
        uiView.isCaptureEventEnabled = isCaptureEventEnabled
    }
}

/// A plain `UIView` holding an `AVCaptureVideoPreviewLayer` as a sublayer,
/// keeping the layer's frame in sync with the view's bounds. It also carries
/// the `AVCaptureEventInteraction` that turns hardware capture buttons into
/// a shutter press (#686).
final class CameraPreviewContainerView: UIView {
    let videoPreviewLayer = AVCaptureVideoPreviewLayer()

    /// What a completed hardware button press does.
    var onCaptureEvent: () -> Void

    /// Mirrors the interaction's `isEnabled`; when false the system gives the
    /// buttons back to volume / its own handling.
    var isCaptureEventEnabled: Bool {
        get { captureEventInteraction?.isEnabled ?? false }
        set { captureEventInteraction?.isEnabled = newValue }
    }

    private(set) var captureEventInteraction: AVCaptureEventInteraction?

    init(onCaptureEvent: @escaping () -> Void = {}) {
        self.onCaptureEvent = onCaptureEvent
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        self.onCaptureEvent = {}
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        layer.addSublayer(videoPreviewLayer)
        let handler: (AVCaptureEvent) -> Void = { [weak self] event in
            self?.handle(phase: event.phase)
        }
        let interaction = AVCaptureEventInteraction(primary: handler, secondary: handler)
        addInteraction(interaction)
        captureEventInteraction = interaction
    }

    /// Fires `onCaptureEvent` once per completed press: only on `.ended`, so
    /// holding the button never repeats and `.began`/`.cancelled` do nothing.
    func handle(phase: AVCaptureEventPhase) {
        guard phase == .ended else { return }
        DispatchQueue.main.async { [weak self] in self?.onCaptureEvent() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }
}
