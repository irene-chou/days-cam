import CoreGraphics

/// Draws a `FilmDateStamp` into a Core Graphics context (TASK-151 #520,
/// three-layer look #578).
///
/// One drawing path for the baked photo (`OverlayRenderer.bake`) and the
/// viewfinder preview, so the two cannot drift apart. Nothing here reads a
/// clock or metadata: the stamp's text is computed by the caller from the
/// capture moment.
enum FilmDateRenderer {
    /// Film orange, opaque, in sRGB: the body layer.
    static var color: CGColor {
        CGColor(srgbRed: FilmDateStamp.Metrics.red, green: FilmDateStamp.Metrics.green,
                blue: FilmDateStamp.Metrics.blue, alpha: 1)
    }

    /// The halo layer's orange-red, opaque, in sRGB.
    static var haloColor: CGColor {
        CGColor(srgbRed: FilmDateStamp.Metrics.haloRed, green: FilmDateStamp.Metrics.haloGreen,
                blue: FilmDateStamp.Metrics.haloBlue, alpha: 1)
    }

    /// The core layer's yellow-white, opaque, in sRGB.
    static var coreColor: CGColor {
        CGColor(srgbRed: FilmDateStamp.Metrics.coreRed, green: FilmDateStamp.Metrics.coreGreen,
                blue: FilmDateStamp.Metrics.coreBlue, alpha: 1)
    }

    /// Draws `stamp` on a canvas of `canvasSize` whose origin is the
    /// context's current origin, y pointing down.
    ///
    /// Three layers, bottom to top, each a blurred image of the glyphs with
    /// no sharp fill anywhere: the wide halo, the film-orange body, and the
    /// thin yellow-white core. All three are composited normally; nothing
    /// reads the photo under them.
    static func draw(_ stamp: FilmDateStamp, in context: CGContext, canvasSize: CGSize) {
        let height = FilmDateStamp.glyphHeight(forCanvasSize: canvasSize)
        guard height > 0 else { return }
        let metrics = FilmDateStamp.Metrics.self
        let body = FilmDateStamp.glyphPath(for: stamp.text, height: height).path
        guard !body.isEmpty else { return }
        let core = FilmDateStamp.glyphPath(for: stamp.text, height: height,
                                           thicknessRatio: metrics.segmentThicknessRatio
                                               * metrics.coreThicknessFraction).path

        // Each layer is drawn as a shadow only: the path itself is filled far
        // off the canvas, and its shadow, offset back by the same distance,
        // is all that lands on it. That leaves a pure blur with no sharp
        // edge underneath.
        let parking = canvasSize.width + canvasSize.height + height * 4
        var transform = stamp.glyphTransform(inCanvasSize: canvasSize)
            .concatenating(CGAffineTransform(translationX: -parking, y: 0))
        guard let parkedBody = body.copy(using: &transform),
              let parkedCore = core.copy(using: &transform) else { return }
        // Shadow offset and blur are in user space: measured the same on a
        // 1x photo and a 3x screen, in UIKit and SwiftUI Canvas contexts
        // alike, so neither is scaled here.
        let offset = CGSize(width: parking, height: 0)

        context.saveGState()
        func layer(_ path: CGPath, blurRatio: CGFloat, color: CGColor, opacity: CGFloat) {
            context.setShadow(offset: offset, blur: blurRatio * height,
                              color: color.copy(alpha: opacity))
            context.setFillColor(color)
            context.addPath(path)
            context.fillPath()
        }
        layer(parkedBody, blurRatio: metrics.haloRadiusRatio, color: haloColor, opacity: metrics.haloOpacity)
        layer(parkedBody, blurRatio: metrics.bodyBlurRatio, color: color, opacity: 1)
        layer(parkedCore, blurRatio: metrics.coreBlurRatio, color: coreColor, opacity: metrics.coreOpacity)
        context.restoreGState()
    }
}
