import AVFoundation
import CoreImage
import MetalKit
import SwiftUI

/// The viewfinder seen through a color tone, live (#590): camera frames run
/// through `ColorToneRenderer.filtered` and drawn by Metal over the preview
/// layer, aspect-filled exactly like it so the two line up.
///
/// Only present while the tone is not `.standard`. It installs its frame
/// handler when it appears and removes it when it goes away, and with no
/// handler the camera produces no frames at all.
struct FilteredPreviewView: UIViewRepresentable {
    let tone: ColorTone
    /// Installs or removes the frame handler (`CameraService.setPreviewFrameHandler`).
    let setFrameHandler: (((CVPixelBuffer) -> Void)?) -> Void

    func makeUIView(context: Context) -> FilteredPreviewMetalView {
        let view = FilteredPreviewMetalView()
        view.tone = tone
        setFrameHandler { [weak view] buffer in view?.receive(buffer) }
        return view
    }

    func updateUIView(_ uiView: FilteredPreviewMetalView, context: Context) {
        uiView.tone = tone
    }

    static func dismantleUIView(_ uiView: FilteredPreviewMetalView, coordinator: ()) {
        uiView.stop()
    }
}

/// An `MTKView` that draws on demand: one draw per new camera frame, never on
/// a timer, so it costs nothing between frames.
final class FilteredPreviewMetalView: MTKView, MTKViewDelegate {
    var tone: ColorTone = .standard

    private let commandQueue: MTLCommandQueue?
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var drawPending = false
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    init() {
        let device = ColorToneRenderer.metalDevice
        commandQueue = device?.makeCommandQueue()
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = false
        // Until the first frame arrives the plain preview shows through.
        isOpaque = false
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Called on the frame queue. Keeps only the newest frame and asks for one
    /// draw on the main queue, however many frames arrive meanwhile.
    func receive(_ buffer: CVPixelBuffer) {
        lock.lock()
        latest = buffer
        let needsDraw = !drawPending
        drawPending = true
        lock.unlock()
        guard needsDraw else { return }
        DispatchQueue.main.async { [weak self] in self?.draw() }
    }

    /// Drops the held frame; the owner removes the frame handler itself.
    func stop() {
        lock.lock()
        latest = nil
        lock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock()
        let buffer = latest
        drawPending = false
        lock.unlock()
        guard let buffer, let drawable = currentDrawable, let commandBuffer = commandQueue?.makeCommandBuffer(),
              let colorSpace,
              let image = ColorToneRenderer.filtered(tone, CIImage(cvPixelBuffer: buffer)) else { return }
        FilteredPreviewMetalView.render(image, to: drawable.texture, commandBuffer: commandBuffer, colorSpace: colorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Where `size` lands, scaled to fill `target` and centered, so the crop is
    /// the one `AVCaptureVideoPreviewLayer`'s `.resizeAspectFill` makes.
    /// `target` is in Metal's top-left texture space; the result is for a
    /// bottom-left Core Image extent.
    static func aspectFillTransform(from size: CGSize, to target: CGSize) -> CGAffineTransform {
        guard size.width > 0, size.height > 0 else { return .identity }
        let scale = max(target.width / size.width, target.height / size.height)
        let dx = (target.width - size.width * scale) / 2
        let dy = (target.height - size.height * scale) / 2
        return CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: dx, y: dy))
    }

    /// Draws `image` aspect-filled into `texture`, right side up.
    static func render(_ image: CIImage, to texture: MTLTexture, commandBuffer: MTLCommandBuffer,
                       colorSpace: CGColorSpace) {
        let target = CGSize(width: texture.width, height: texture.height)
        // Core Image's origin is bottom-left, a Metal texture's top-left, so
        // the result is flipped on the way in.
        let flip = CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: target.height))
        let fitted = image
            .transformed(by: aspectFillTransform(from: image.extent.size, to: target))
            .transformed(by: flip)
        ColorToneRenderer.context.render(fitted, to: texture, commandBuffer: commandBuffer,
                                         bounds: CGRect(origin: .zero, size: target), colorSpace: colorSpace)
    }
}
