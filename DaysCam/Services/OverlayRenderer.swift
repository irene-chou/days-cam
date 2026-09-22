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
    /// Returns nil only when the image has no pixels to draw into; the caller
    /// treats nil as a baking failure and does not save the photo.
    func bake(image: UIImage, text: String, theme: OverlayTheme, position: OverlayPosition) -> UIImage? {
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }

        // Already upright, already one point per pixel, nothing to print: the
        // input already is the answer, and handing it back is the only way to
        // guarantee every pixel is untouched.
        if text.isEmpty, image.imageOrientation == .up, image.scale == 1 {
            return image
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)

        return renderer.image { rendererContext in
            // `UIImage.draw` honors `imageOrientation`, so this single call is
            // the normalisation to `.up`.
            image.draw(in: CGRect(origin: .zero, size: pixelSize))

            guard !text.isEmpty else { return }
            let layout = OverlayLayout(text: text, theme: theme, frameSize: pixelSize)
            let block = layout.decoratedText()
            let origin = layout.origin(for: block.size, at: position)
            block.draw(rendererContext.cgContext, origin)
        }
    }
}

// MARK: - Layout

/// Sizes and positions for one overlay, mirroring `OverlayTextView.body`
/// step for step.
private struct OverlayLayout {
    let text: String
    let theme: OverlayTheme
    let frameSize: CGSize
    let margin: CGFloat
    let fontSize: CGFloat
    /// Multiplier for the theme's decoration constants, which are written for
    /// 17pt text (PRD FR-4.7). About 3.9 on a 1200-pixel-wide photo.
    let decorationScale: CGFloat
    let font: UIFont

    init(text: String, theme: OverlayTheme, frameSize: CGSize) {
        self.text = text
        self.theme = theme
        self.frameSize = frameSize

        let shortEdge = min(frameSize.width, frameSize.height)
        margin = OverlayMetrics.margin(forShortEdge: shortEdge)
        let baseFontSize = OverlayMetrics.baseFontSize(forShortEdge: shortEdge)
        // Same as the viewfinder: the fit is against the text alone, not the
        // text plus any background box insets.
        let availableWidth = max(0, frameSize.width - margin * 2)
        fontSize = OverlayMetrics.fittedFontSize(for: text,
                                                 theme: theme,
                                                 baseFontSize: baseFontSize,
                                                 availableWidth: availableWidth)
        decorationScale = OverlayMetrics.decorationScale(forFontSize: fontSize)
        font = OverlayMetrics.font(for: theme, size: fontSize)
    }

    /// Top-left corner for a block of `size` at one of the nine anchor
    /// points: one margin in from the edges it hugs, centred on the axes it
    /// does not (PRD FR-4.3). A block too wide for the margins at the 60% font
    /// floor runs into them rather than being clipped (FR-4.8).
    func origin(for size: CGSize, at position: OverlayPosition) -> CGPoint {
        let leading = margin
        let centerX = (frameSize.width - size.width) / 2
        let trailing = frameSize.width - margin - size.width
        let top = margin
        let centerY = (frameSize.height - size.height) / 2
        let bottom = frameSize.height - margin - size.height

        switch position {
        case .topLeading: return CGPoint(x: leading, y: top)
        case .topCenter: return CGPoint(x: centerX, y: top)
        case .topTrailing: return CGPoint(x: trailing, y: top)
        case .middleLeading: return CGPoint(x: leading, y: centerY)
        case .middleCenter: return CGPoint(x: centerX, y: centerY)
        case .middleTrailing: return CGPoint(x: trailing, y: centerY)
        case .bottomLeading: return CGPoint(x: leading, y: bottom)
        case .bottomCenter: return CGPoint(x: centerX, y: bottom)
        case .bottomTrailing: return CGPoint(x: trailing, y: bottom)
        }
    }

    /// The text with every one of the theme's decorations wrapped around it,
    /// in array order — the same nesting `OverlayTextView.decoratedText`
    /// builds, so `softPink`'s shadow is cast by the stroked text as a whole.
    func decoratedText() -> DrawingBlock {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let fill: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: uiColor(theme.textColor)]
        let text = self.text
        var block = DrawingBlock(size: textSize) { _, origin in
            (text as NSString).draw(at: origin, withAttributes: fill)
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

    // MARK: Decorations

    /// An outline around the glyphs, drawn under `inner`.
    ///
    /// The viewfinder fakes a stroke with copies of the text nudged `width`
    /// points out in eight directions. Here Core Graphics strokes the real
    /// glyph outline instead; a stroke is centred on the outline, so it is
    /// drawn twice as wide and the fill covers the inner half, leaving the
    /// same `width` visible outside the glyph.
    private func stroked(_ inner: DrawingBlock, textSize: CGSize, color: OverlayColor, width: Double) -> DrawingBlock {
        let lineWidth = CGFloat(width) * decorationScale * 2
        guard lineWidth > 0, fontSize > 0 else { return inner }
        // `.strokeWidth` is a percentage of the font size; positive means
        // outline only, no fill.
        let outline: [NSAttributedString.Key: Any] = [
            .font: font,
            .strokeColor: uiColor(color),
            .strokeWidth: lineWidth / fontSize * 100
        ]
        let text = self.text
        return DrawingBlock(size: inner.size) { context, origin in
            // Centred in the block, as the viewfinder's ZStack does.
            let textOrigin = CGPoint(x: origin.x + (inner.size.width - textSize.width) / 2,
                                     y: origin.y + (inner.size.height - textSize.height) / 2)
            context.saveGState()
            // Round joins: at photo size the stroke is ~20 pixels wide, and
            // mitred corners would spike out of every sharp glyph.
            context.setLineJoin(.round)
            (text as NSString).draw(at: textOrigin, withAttributes: outline)
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
        return DrawingBlock(size: size) { context, origin in
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
        return DrawingBlock(size: inner.size) { context, origin in
            context.saveGState()
            context.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor)
            // Flatten `inner` into one layer first, so a stroked text casts
            // one shadow rather than one per stroke and fill pass — what
            // `.compositingGroup()` does in the viewfinder.
            //
            // The layer is bounded to the block: an unbounded one allocates a
            // second full-photo bitmap and blurs all of it, which made the
            // shadow themes three times slower on a 12-megapixel photo.
            let bounds = CGRect(origin: origin, size: inner.size).insetBy(dx: -spill, dy: -spill)
            context.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
            inner.draw(context, origin)
            context.endTransparencyLayer()
            context.restoreGState()
        }
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
    let draw: (CGContext, CGPoint) -> Void
}
