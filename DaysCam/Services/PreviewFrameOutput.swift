import AVFoundation
import os

/// The slice of `AVCaptureConnection` the live-tone frame feed touches.
///
/// Injected so the orientation, mirroring and on/off rules can be tested
/// without a real capture connection, which only exists with a camera.
protocol FrameConnectionConfigurable: VideoMirroringConfigurable {
    var isEnabled: Bool { get set }
    var videoRotationAngle: CGFloat { get set }
    func isVideoRotationAngleSupported(_ videoRotationAngle: CGFloat) -> Bool
}

extension AVCaptureConnection: FrameConnectionConfigurable {}

/// A BGRA video-frame feed beside the photo output, used only to show the
/// viewfinder through a color tone live (#590). Photos never go through it.
///
/// The feed costs nothing while no handler is set: the connection is switched
/// off, so no frame is produced, copied or processed (`.standard` tone).
/// Frames come in upright (portrait, like the preview layer) and mirrored on
/// the front camera, so the filtered picture lines up with the preview layer
/// underneath it.
final class PreviewFrameOutput: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// The output to add to the session.
    let output = AVCaptureVideoDataOutput()

    private let queue = DispatchQueue(label: "com.irenechou.DaysCam.preview-frames", qos: .userInteractive)
    private let handler = OSAllocatedUnfairLock<((CVPixelBuffer) -> Void)?>(initialState: nil)

    /// Whether a handler is installed, i.e. whether frames should flow.
    var isActive: Bool { handler.withLock { $0 != nil } }

    override init() {
        super.init()
        PreviewFrameOutput.configure(output)
        output.setSampleBufferDelegate(self, queue: queue)
    }

    /// Installs (or, with nil, removes) the frame handler. It runs on the
    /// frame queue, not the main queue.
    func setHandler(_ newHandler: ((CVPixelBuffer) -> Void)?) {
        handler.withLock { $0 = newHandler }
    }

    /// BGRA, and late frames dropped rather than queued so the live picture
    /// never falls behind.
    static func configure(_ output: AVCaptureVideoDataOutput) {
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
    }

    /// Upright portrait, mirrored like the preview for `facing`, and on only
    /// while `isActive`. Mirroring is left alone on a connection that cannot
    /// do it.
    static func configure(_ connection: FrameConnectionConfigurable, facing: CameraFacing, isActive: Bool) {
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        CameraService.configureMirroring(of: connection, for: facing)
        connection.isEnabled = isActive
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let handler = handler.withLock({ $0 }),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        handler(pixelBuffer)
    }
}
