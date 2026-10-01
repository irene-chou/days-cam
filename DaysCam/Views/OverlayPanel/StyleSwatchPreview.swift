import SwiftUI
import UIKit

/// The fixed look of the outline/shadow option previews in the style tab
/// (#155): dark text, gray outline/box/shadow, whatever the current text
/// color is, so every option stays distinguishable (a white text color used
/// to make them all look alike). Only the font follows the current style.
///
/// These are the *sample overlay text's* own colors (FR-14.4's exemption for
/// overlay text colors and their conversions), not interface chrome, so they
/// are `OverlayColor` values rather than `CameraTheme` tokens.
enum StyleSwatchPreview {
    /// Sample text color, the `ink` token's value (`#2A2622`).
    static let textColor = OverlayColor(red8: 0x2A, green8: 0x26, blue8: 0x22)
    /// Outline, box and shadow color (`#A39A90`, #155's initial value).
    static let accentGray = OverlayColor(red8: 0xA3, green8: 0x9A, blue8: 0x90)

    /// `style` with the fixed preview colors applied; the font is kept.
    static func fixedStyle(from style: OverlayStyle) -> OverlayStyle {
        var fixed = style
        fixed.textColor = textColor
        fixed.outlineColor = accentGray
        return fixed
    }

    /// The decorations of `style`'s theme with every shadow recolored gray
    /// (the theme's own shadows are black, and glow follows the text color).
    static func decorations(for style: OverlayStyle) -> [OverlayDecoration] {
        OverlayTheme(style: style).decorations.map { decoration in
            if case let .shadow(offset, blur, opacity, _) = decoration {
                return .shadow(offset: offset, blur: blur, opacity: opacity, color: accentGray)
            }
            return decoration
        }
    }

    /// "Aa" drawn as one clean outline hugging the glyphs, with the fill on
    /// top. Core Graphics strokes the real glyph outline (same method as
    /// `OverlayRenderer.stroked`: `.strokeWidth` positive = outline only,
    /// round joins) instead of stacking offset copies of the text, which
    /// looked like several overlapping texts at this small size.
    ///
    /// `strokeWidth` is the visible width outside the glyph in points. The
    /// returned image's layout size is the text's own size, so it drops in
    /// where the plain `Text` was; the stroke may overhang that size.
    static func strokedText(_ text: String,
                            font: UIFont,
                            fill: OverlayColor,
                            stroke: OverlayColor,
                            strokeWidth: CGFloat) -> UIImage {
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let overhang = ceil(strokeWidth * 2)
        let canvas = CGSize(width: textSize.width + overhang * 2, height: textSize.height + overhang * 2)
        let origin = CGPoint(x: overhang, y: overhang)
        let image = UIGraphicsImageRenderer(size: canvas).image { context in
            // A centred stroke is drawn twice as wide; the fill covers the
            // inner half, leaving `strokeWidth` visible outside.
            let outline: [NSAttributedString.Key: Any] = [
                .font: font,
                .strokeColor: uiColor(stroke),
                .strokeWidth: strokeWidth * 2 / font.pointSize * 100
            ]
            context.cgContext.setLineJoin(.round)
            (text as NSString).draw(at: origin, withAttributes: outline)
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: uiColor(fill)])
        }
        return image
    }

    private static func uiColor(_ color: OverlayColor) -> UIColor {
        UIColor(red: CGFloat(color.red), green: CGFloat(color.green),
                blue: CGFloat(color.blue), alpha: CGFloat(color.opacity))
    }
}
