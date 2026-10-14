import CoreGraphics

/// Draws a `FilmDateStamp` into a Core Graphics context (TASK-151 #520).
///
/// One drawing path for the baked photo (`OverlayRenderer.bake`) and the
/// viewfinder preview, so the two cannot drift apart. Nothing here reads a
/// clock or metadata: the stamp's text is computed by the caller from the
/// capture moment.
enum FilmDateRenderer {
    /// Film orange, opaque, in sRGB.
    static var color: CGColor {
        CGColor(srgbRed: FilmDateStamp.Metrics.red, green: FilmDateStamp.Metrics.green,
                blue: FilmDateStamp.Metrics.blue, alpha: 1)
    }

    /// Draws `stamp` on a canvas of `canvasSize` whose origin is the
    /// context's current origin, y pointing down: the glow first, then the
    /// slightly blurred glyphs on top of it.
    static func draw(_ stamp: FilmDateStamp, in context: CGContext, canvasSize: CGSize) {
        let height = FilmDateStamp.glyphHeight(forCanvasSize: canvasSize)
        guard height > 0 else { return }
        let glyphs = FilmDateStamp.glyphPath(for: stamp.text, height: height).path
        guard !glyphs.isEmpty else { return }
        var transform = stamp.glyphTransform(inCanvasSize: canvasSize)
        guard let placed = glyphs.copy(using: &transform) else { return }

        // Shadow blur is in device space and ignores the CTM, so scale it by
        // the context's own scale to keep the look the same on a 1x photo
        // and a 3x screen.
        let deviceScale = abs(context.userSpaceToDeviceSpaceTransform.a)
            + abs(context.userSpaceToDeviceSpaceTransform.b)
        let glow = FilmDateStamp.Metrics.glowRadiusRatio * height * deviceScale
        let bleed = FilmDateStamp.Metrics.bleedRadiusRatio * height * deviceScale
        let orange = color

        context.saveGState()
        // The glow: the glyphs' shadow, cast in their own colour with no
        // offset, so it spreads evenly around them.
        context.setShadow(offset: .zero, blur: glow,
                          color: orange.copy(alpha: FilmDateStamp.Metrics.glowOpacity))
        context.setFillColor(orange)
        context.addPath(placed)
        context.fillPath()
        // The glyphs again with a narrow shadow, softening their edges.
        context.setShadow(offset: .zero, blur: bleed, color: orange)
        context.addPath(placed)
        context.fillPath()
        context.restoreGState()
    }
}
