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

    func makeUIView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView()
        view.videoPreviewLayer.session = session
        // `.resizeAspect` rather than `.resizeAspectFill`: the container this
        // view sits in is already fixed to the sensor's 4:3 ratio, and a fill
        // gravity would crop the edges, which is exactly what would make
        // TASK-07's acceptance 7.2 (measured aspect ratio) come out wrong.
        view.videoPreviewLayer.videoGravity = .resizeAspect
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
