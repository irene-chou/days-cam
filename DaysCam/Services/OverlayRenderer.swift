import CoreGraphics
import Foundation
import UIKit

/// Bakes already-rendered text into the pixels of an image.
///
/// Deliberately agnostic about where the image came from: a live capture today,
/// a file loaded from disk tomorrow. It takes an image, a finished string and a
/// style, and nothing else — it never inspects timestamps or metadata, and it
/// knows nothing about profiles or the camera (PRD §6.5.4).
///
/// The text becomes part of the pixel data: the photo and the overlay are
/// drawn into one bitmap and only that bitmap is returned. There is no separate
/// layer and no copy without the overlay (PRD §6.2).
struct OverlayRenderer {
    init() {}

    /// Draws `text` into `image`'s pixels and returns the result.
    ///
    /// The output is always upright (`imageOrientation == .up`), at scale 1,
    /// and exactly the input's pixel size. A photo tagged `.right` — how a
    /// portrait shot comes off the sensor — is rotated into place before the
    /// text is drawn, so the text is never turned 90° with it.
    ///
    /// Layout is the viewfinder's (`OverlayTextView`), computed from the same
    /// `OverlayMetrics` functions in the same order, so the saved photo matches
    /// what was on screen (PRD FR-6.1).
    ///
    /// An empty `text` draws nothing at all, not even an empty background box.
    ///
    /// `cropRect`, when given, is the window to keep, in orientation-normalized
    /// pixels (`ImageCropper.cropRect(forPixelSize:ratio:)`). Cropping, rotating
    /// upright and printing then happen in one drawing pass: the canvas is
    /// `cropRect.size`, the photo is drawn at a negative offset, and the text is
    /// laid out in the cropped canvas, exactly as if the photo had been cropped
    /// first. `nil` keeps the whole photo.
    ///
    /// The output is rendered in the standard range (8 bits per component), so
    /// wide-gamut or HDR sources do not double the bitmap's memory.
    ///
    /// Returns nil only when the image has no pixels to draw into; the caller
    /// treats nil as a baking failure and does not save the photo.
    ///
    /// `font` must be `OverlayMetrics.resolvedFont(for: style, ...)`,
    /// resolved when the shutter is pressed — the same value the viewfinder
    /// was drawing with (PRD 0.3 FR-5.14). It is used both to fit the size and
    /// to draw, so the two cannot disagree.
    func bake(image: UIImage, text: String, style: OverlayStyle, placement: OverlayPlacement,
              font: ResolvedOverlayFont, cropRect: CGRect? = nil) -> UIImage? {
        let sourceSize = CGSize(width: image.size.width * image.scale,
                                height: image.size.height * image.scale)
        guard sourceSize.width >= 1, sourceSize.height >= 1 else { return nil }
        let window = cropRect.map { $0.intersection(CGRect(origin: .zero, size: sourceSize)) }
            ?? CGRect(origin: .zero, size: sourceSize)
        guard !window.isNull, window.width >= 1, window.height >= 1 else { return nil }
        let pixelSize = window.size

        // Already upright, already one point per pixel, nothing to print: the
        // input already is the answer, and handing it back is the only way to
        // guarantee every pixel is untouched.
        if text.isEmpty, image.imageOrientation == .up, image.scale == 1, cropRect == nil {
            return image
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)

        return renderer.image { rendererContext in
            // `UIImage.draw` honors `imageOrientation`, so this single call is
            // the normalisation to `.up`; the negative offset is the crop.
            image.draw(in: CGRect(x: -window.origin.x, y: -window.origin.y,
                                  width: sourceSize.width, height: sourceSize.height))

            guard !text.isEmpty else { return }
            let fontSize = Self.fittedFontSize(for: text, style: style, frameSize: pixelSize, font: font)
            let block = OverlayLayout(text: text, style: style, font: font, fontSize: fontSize).decoratedText()
            let origin = OverlayMetrics.origin(forBlockSize: block.size, in: pixelSize, placement: placement)
            block.draw(rendererContext.cgContext, origin)
        }
    }

    /// Draws only the overlay text — with its outline or box and its shadow —
    /// on a transparent background, at `fontSize` points.
    ///
    /// For the viewfinder and the style preview, so they show the real glyph
    /// outline instead of faking it. It goes through the same layout and
    /// decoration code as `bake`, so a preview drawn with this matches the
    /// saved photo; decorations scale with `fontSize` exactly as they do there.
    ///
    /// The image is larger than the laid-out block: it has room for the
    /// stroke, the shadow and any glyph overhang on every side, so nothing is
    /// clipped. `RenderedOverlayText.textInsets` says where the block sits in
    /// it; place the block with `OverlayMetrics.origin(forBlockSize:in:placement:)`
    /// and the image with `imageFrame(forBlockOrigin:)`.
    ///
    /// Returns nil for empty `text` or a non-positive size or scale.
    ///
    /// `font` is the resolved face, the same one `fittedFontSize` measured
    /// with (PRD 0.3 FR-5.14).
    func renderText(_ text: String, style: OverlayStyle, fontSize: CGFloat, displayScale: CGFloat,
                    font: ResolvedOverlayFont) -> RenderedOverlayText? {
        guard !text.isEmpty, fontSize > 0, displayScale > 0 else { return nil }
        let block = OverlayLayout(text: text, style: style, font: font, fontSize: fontSize).decoratedText()
        // One spare pixel past the overflow on every side keeps the outermost
        // ring transparent even where a box reaches the block's edge. The
        // leading insets are whole pixels so the block starts on the pixel
        // grid; the trailing ones absorb rounding the image up to whole pixels.
        let onePixel = 1 / displayScale
        func pixelCeiling(_ value: CGFloat) -> CGFloat { (value * displayScale).rounded(.up) / displayScale }
        let top = pixelCeiling(max(0, block.overflow.top) + onePixel)
        let left = pixelCeiling(max(0, block.overflow.left) + onePixel)
        let size = CGSize(
            width: pixelCeiling(left + block.size.width + max(0, block.overflow.right) + onePixel),
            height: pixelCeiling(top + block.size.height + max(0, block.overflow.bottom) + onePixel))
        let insets = UIEdgeInsets(top: top,
                                  left: left,
                                  bottom: size.height - top - block.size.height,
                                  right: size.width - left - block.size.width)

        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            block.draw(rendererContext.cgContext, CGPoint(x: insets.left, y: insets.top))
        }
        return RenderedOverlayText(image: image, textInsets: insets, blockSize: block.size)
    }

    /// The font size overlay text is drawn at in a frame of `frameSize`: the
    /// base size for its short edge, times `style.sizeScale`, shrunk to fit
    /// between the margins (PRD FR-4.7, FR-4.8; 0.2 FR-5.10, FR-10.9),
    /// measured in `font` (0.3 FR-5.14, FR-5.17).
    ///
    /// `bake` uses this with the photo's pixel size; the viewfinder passes its
    /// own bounds in points and hands the result to `renderText` together
    /// with the same `font`.
    static func fittedFontSize(for text: String, style: OverlayStyle, frameSize: CGSize,
                               font: ResolvedOverlayFont) -> CGFloat {
        let shortEdge = min(frameSize.width, frameSize.height)
        let margin = OverlayMetrics.margin(forShortEdge: shortEdge)
        let baseFontSize = OverlayMetrics.baseFontSize(forShortEdge: shortEdge, sizeScale: style.sizeScale)
        // The fit is against the text alone, not the text plus any background
        // box insets.
        let availableWidth = max(0, frameSize.width - margin * 2)
        return OverlayMetrics.fittedFontSize(for: text,
                                             font: font,
                                             baseFontSize: baseFontSize,
                                             availableWidth: availableWidth)
    }
}

/// Overlay text drawn on its own by `OverlayRenderer.renderText`.
struct RenderedOverlayText {
    /// The decorated text on a transparent background, in points at the
    /// requested display scale.
    let image: UIImage
    /// Distance in points from each edge of `image` to the laid-out block —
    /// the text, plus its background box if the style has one. Everything
    /// outside the block (stroke, shadow, glyph overhang) is decoration and
    /// does not count towards layout.
    let textInsets: UIEdgeInsets
    /// Size in points of the laid-out block; what
    /// `OverlayMetrics.origin(forBlockSize:in:placement:)` takes.
    let blockSize: CGSize

    /// Where to draw `image` so the block's top-left corner is at `blockOrigin`.
    func imageFrame(forBlockOrigin blockOrigin: CGPoint) -> CGRect {
        CGRect(x: blockOrigin.x - textInsets.left,
               y: blockOrigin.y - textInsets.top,
               width: image.size.width,
               height: image.size.height)
    }
}

// MARK: - Layout

/// The decorated text for one overlay at a given font size. The single
/// drawing path behind both `bake` and `renderText`.
private struct OverlayLayout {
    let text: String
    let theme: OverlayTheme
    let fontSize: CGFloat
    /// Multiplier for the theme's decoration constants, which are written for
    /// 17pt text (PRD FR-4.7). About 3.9 on a 1200-pixel-wide photo.
    let decorationScale: CGFloat
    let font: UIFont

    /// `font` is the already-resolved face (PRD 0.3 FR-5.14); the layout
    /// never looks at `style.fontID` itself.
    init(text: String, style: OverlayStyle, font: ResolvedOverlayFont, fontSize: CGFloat) {
        self.text = text
        self.theme = OverlayTheme(style: style)
        self.fontSize = fontSize
        decorationScale = OverlayMetrics.decorationScale(forFontSize: fontSize)
        self.font = font.font(ofSize: fontSize)
    }

    /// The text with every one of the theme's decorations wrapped around it,
    /// in array order — the same nesting `OverlayTextView.decoratedText`
    /// builds, so a shadow is cast by the stroked or boxed text as a whole.
    func decoratedText() -> DrawingBlock {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let textOpacity = theme.textColor.opacity
        let fill: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: uiColor(theme.textColor, opacity: 1)]
        let text = self.text
        let overflow = glyphOverflow(textSize: textSize)
        var block = DrawingBlock(size: textSize, overflow: overflow) { context, origin in
            // Translucent text is drawn opaque and faded as one layer, so
            // glyphs that overlap do not darken where they meet (TASK-69).
            Self.withOpacity(textOpacity, in: context,
                             bounds: Self.inkBounds(origin: origin, size: textSize, overflow: overflow)) {
                (text as NSString).draw(at: origin, withAttributes: fill)
            }
        }

        for decoration in theme.decorations {
            switch decoration {
            case let .stroke(color, width):
                block = stroked(block, textSize: textSize, color: color, width: width)
            case let .backgroundBox(color, opacity, cornerRadius, insets):
                block = boxed(block, color: color, opacity: opacity, cornerRadius: cornerRadius, insets: insets)
            case let .shadow(offset, blur, opacity, color):
                block = shadowed(block, offset: offset, blur: blur, opacity: opacity, color: color)
            }
        }
        return block
    }

    /// How far the glyphs' ink can reach past the text's line box: swashes
    /// and brush-stroke overhang (calligraphy faces such as 行楷), plus a
    /// margin for antialiasing.
    private func glyphOverflow(textSize: CGSize) -> UIEdgeInsets {
        let ink = (text as NSString).boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                               height: CGFloat.greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin, .usesDeviceMetrics],
                                                  attributes: [.font: font],
                                                  context: nil)
        let slack = fontSize * 0.1
        return UIEdgeInsets(top: max(0, -ink.minY) + slack,
                            left: max(0, -ink.minX) + slack,
                            bottom: max(0, ink.maxY - textSize.height) + slack,
                            right: max(0, ink.maxX - textSize.width) + slack)
    }

    // MARK: Decorations

    /// An outline around the glyphs, drawn under `inner`.
    ///
    /// The shared geometry unions filled glyphs with their round expanded
    /// outlines before drawing, so intersecting contours cannot erase ink.
    ///
    /// Translucent text would let that inner half show through, so it is
    /// cut out of the stroke first; a translucent stroke is faded as one
    /// layer so neighbouring glyphs' strokes do not double up (TASK-69).
    private func stroked(_ inner: DrawingBlock, textSize: CGSize, color: OverlayColor, width: Double) -> DrawingBlock {
        let lineWidth = CGFloat(width) * decorationScale * 2
        guard lineWidth > 0, fontSize > 0 else { return inner }
        let geometry = OverlayStrokeGeometry(text: text, font: font, width: lineWidth / 2)
        let excludesFill = theme.textColor.opacity < 1
        let strokeOpacity = color.opacity
        let visible = lineWidth / 2
        let overflow = UIEdgeInsets(top: inner.overflow.top + visible,
                                    left: inner.overflow.left + visible,
                                    bottom: inner.overflow.bottom + visible,
                                    right: inner.overflow.right + visible)
        return DrawingBlock(size: inner.size, overflow: overflow) { context, origin in
            // Centred in the block, as the viewfinder's ZStack does.
            let textOrigin = CGPoint(x: origin.x + (inner.size.width - textSize.width) / 2,
                                     y: origin.y + (inner.size.height - textSize.height) / 2)
            context.saveGState()
            // Round joins: at photo size the stroke is ~20 pixels wide, and
            // mitred corners would spike out of every sharp glyph.
            context.setLineJoin(.round)
            Self.withOpacity(strokeOpacity, in: context,
                             bounds: Self.inkBounds(origin: origin, size: inner.size, overflow: overflow)) {
                geometry.draw(in: context, at: textOrigin, color: uiColor(color, opacity: 1),
                              excludingFill: excludesFill)
            }
            context.restoreGState()
            inner.draw(context, origin)
        }
    }

    /// A rounded box behind `inner`, grown by the scaled insets.
    private func boxed(_ inner: DrawingBlock,
                       color: OverlayColor,
                       opacity: Double,
                       cornerRadius: Double,
                       insets: OverlayInsets) -> DrawingBlock {
        let padX = CGFloat(insets.horizontal) * decorationScale
        let padY = CGFloat(insets.vertical) * decorationScale
        let size = CGSize(width: inner.size.width + padX * 2, height: inner.size.height + padY * 2)
        let radius = CGFloat(cornerRadius) * decorationScale
        let boxColor = uiColor(color, opacity: color.opacity * opacity)
        // The box covers its insets; only ink reaching past them spills out.
        let overflow = UIEdgeInsets(top: max(0, inner.overflow.top - padY),
                                    left: max(0, inner.overflow.left - padX),
                                    bottom: max(0, inner.overflow.bottom - padY),
                                    right: max(0, inner.overflow.right - padX))
        return DrawingBlock(size: size, overflow: overflow) { context, origin in
            boxColor.setFill()
            UIBezierPath(roundedRect: CGRect(origin: origin, size: size), cornerRadius: radius).fill()
            inner.draw(context, CGPoint(x: origin.x + padX, y: origin.y + padY))
        }
    }

    /// A drop shadow cast once by everything in `inner` together.
    private func shadowed(_ inner: DrawingBlock,
                          offset: CGSize,
                          blur: Double,
                          opacity: Double,
                          color: OverlayColor) -> DrawingBlock {
        // In a `UIGraphicsImageRenderer` context a positive y offset casts the
        // shadow downward, the same way the theme's SwiftUI-style offsets
        // read, so they are used as is. Do not negate this: Core Graphics
        // documents shadow offsets in device space (y up), which suggests a
        // flip is needed, but measured here it puts the shadow above the text.
        // `test_shadowFallsBelowTheTextLikeThePreview` pins the direction.
        let shadowOffset = CGSize(width: offset.width * decorationScale,
                                  height: offset.height * decorationScale)
        let shadowBlur = CGFloat(blur) * decorationScale
        let shadowColor = uiColor(color, opacity: color.opacity * opacity).cgColor
        // Room around the block for everything that spills past its laid-out
        // size: the blur on every side, the offset, and a stroke or glyph
        // overhang drawn outside the text box.
        let spill = shadowBlur * 2 + max(abs(shadowOffset.width), abs(shadowOffset.height)) + fontSize * 0.25
        // The shadow is `inner`'s ink moved by the offset and spread by the
        // blur; twice the blur radius covers the visible falloff.
        let reach = shadowBlur * 2
        let overflow = UIEdgeInsets(
            top: max(inner.overflow.top, inner.overflow.top + reach - shadowOffset.height),
            left: max(inner.overflow.left, inner.overflow.left + reach - shadowOffset.width),
            bottom: max(inner.overflow.bottom, inner.overflow.bottom + reach + shadowOffset.height),
            right: max(inner.overflow.right, inner.overflow.right + reach + shadowOffset.width))
        return DrawingBlock(size: inner.size, overflow: overflow) { context, origin in
            context.saveGState()
            context.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor)
            // Flatten `inner` into one layer first, so a stroked text casts
            // one shadow rather than one per stroke and fill pass — what
            // `.compositingGroup()` does in the viewfinder.
            //
            // The layer is bounded to the block: an unbounded one allocates a
            // second full-photo bitmap and blurs all of it, which made the
            // shadow themes three times slower on a 12-megapixel photo.
            // Never smaller than what `overflow` promises, or `renderText`
            // would hand out an image with a clipped shadow.
            let blockRect = CGRect(origin: origin, size: inner.size)
            let bounds = blockRect.insetBy(dx: -spill, dy: -spill)
                .union(blockRect.inset(by: UIEdgeInsets(top: -overflow.top, left: -overflow.left,
                                                        bottom: -overflow.bottom, right: -overflow.right)))
            context.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
            inner.draw(context, origin)
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }

    /// Runs `draw` so that what it draws is faded to `opacity` as a whole.
    ///
    /// Fully opaque drawing goes straight to `context`, pixel-identical to
    /// before TASK-69, unless `isolating` asks for a layer anyway (to confine
    /// a blend mode). The layer is bounded: an unbounded one would allocate a
    /// second full-photo bitmap.
    private static func withOpacity(_ opacity: Double,
                                    isolating: Bool = false,
                                    in context: CGContext,
                                    bounds: CGRect,
                                    draw: () -> Void) {
        guard opacity < 1 || isolating else {
            draw()
            return
        }
        context.saveGState()
        context.setAlpha(CGFloat(opacity))
        context.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
        draw()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// The block at `origin` grown by everything it can draw past its size.
    private static func inkBounds(origin: CGPoint, size: CGSize, overflow: UIEdgeInsets) -> CGRect {
        CGRect(origin: origin, size: size)
            .inset(by: UIEdgeInsets(top: -overflow.top, left: -overflow.left,
                                    bottom: -overflow.bottom, right: -overflow.right))
    }

    private func uiColor(_ color: OverlayColor, opacity: Double? = nil) -> UIColor {
        UIColor(red: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: CGFloat(opacity ?? color.opacity))
    }
}

/// Something with a laid-out size that can draw itself with its top-left
/// corner at a given point. Decorations wrap one block in another, the way
/// the viewfinder wraps one view in another.
private struct DrawingBlock {
    let size: CGSize
    /// How far the drawing can reach past `size` on each side — layout
    /// ignores it, but an image of just this block has to make room for it.
    let overflow: UIEdgeInsets
    let draw: (CGContext, CGPoint) -> Void
}
