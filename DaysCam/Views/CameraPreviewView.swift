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

    func makeUIView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView()
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
        // `session` is fixed for this view's lifetime; nothing to update here.
    }
}

/// A plain `UIView` holding an `AVCaptureVideoPreviewLayer` as a sublayer,
/// keeping the layer's frame in sync with the view's bounds.
final class CameraPreviewContainerView: UIView {
    let videoPreviewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(videoPreviewLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.addSublayer(videoPreviewLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }
}
