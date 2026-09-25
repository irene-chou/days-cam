import CoreGraphics
import Foundation
import UIKit

/// The one place font size, margin and shrink-to-fit are computed.
///
/// The viewfinder overlay (`OverlayTextView`) and the baking path
/// (`OverlayRenderer`) must produce the same layout at very different pixel
/// sizes — a ~400pt preview and a 3024x4032 photo — so both call these
/// functions instead of each carrying its own copy of the percentages
/// (PRD FR-4.7, FR-4.8, FR-4.3; 0.2 FR-5.10, FR-10.2, FR-12).
enum OverlayMetrics {
    /// Base font size as a fraction of the frame's short edge (PRD FR-4.7).
    static let baseFontRatio: CGFloat = 0.055
    /// Margin as a fraction of the frame's short edge (PRD FR-4.3).
    static let marginRatio: CGFloat = 0.04
    /// Lower bound of shrink-to-fit, as a fraction of the base size (PRD FR-4.8).
    static let minimumFontScale: CGFloat = 0.6
    /// Font size the decoration constants in `OverlayTheme` are expressed at.
    ///
    /// Assumption: the PRD states shadow offsets, corner radii, insets and
    /// stroke widths as plain point values (offset 0,2; radius 8; insets 12x6),
    /// which only make sense next to body-sized text. They are scaled by
    /// `decorationScale(forFontSize:)` so a theme looks the same in a 400pt
    /// preview and a 3024pt photo.
    static let referenceFontSize: CGFloat = 17.0

    /// Base font size for a frame whose short edge is `shortEdge`, scaled by
    /// the style's `sizeScale` percent (PRD 0.2 FR-10.9: 100 is the 0.1 size).
    ///
    /// This is also the size shrink-to-fit starts from, so its 60% floor is
    /// 60% of the scaled size (PRD 0.2 FR-5.10).
    static func baseFontSize(forShortEdge shortEdge: CGFloat, sizeScale: Int = 100) -> CGFloat {
        shortEdge * baseFontRatio * CGFloat(sizeScale) / 100
    }

    /// Distance from the frame's edge to the overlay for a frame whose short
    /// edge is `shortEdge`.
    static func margin(forShortEdge shortEdge: CGFloat) -> CGFloat {
        shortEdge * marginRatio
    }

    /// Multiplier to apply to a theme's decoration constants when drawing at
    /// `fontSize`.
    static func decorationScale(forFontSize fontSize: CGFloat) -> CGFloat {
        fontSize / referenceFontSize
    }

    /// Top-left corner for an overlay block of `blockSize` placed in a frame of
    /// `frameSize` (PRD FR-4.3, 0.2 FR-12).
    ///
    /// `.anchor`: one margin in from the edges it hugs, centred on the axes it
    /// does not; a block too wide for the margins at the 60% font floor runs
    /// into them rather than being clipped (FR-4.8).
    ///
    /// `.custom`: the block's center goes at `x * width, y * height`, then the
    /// whole block is clamped inside the margin (FR-12.2, FR-12.6). On an axis
    /// where the block is larger than the space between the margins, it is
    /// centred instead. The stored `x`, `y` are never changed.
    static func origin(forBlockSize blockSize: CGSize,
                       in frameSize: CGSize,
                       placement: OverlayPlacement) -> CGPoint {
        let margin = margin(forShortEdge: min(frameSize.width, frameSize.height))
        switch placement {
        case let .anchor(position):
            return anchorOrigin(forBlockSize: blockSize, in: frameSize, margin: margin, position: position)
        case let .custom(x, y):
            return CGPoint(
                x: clampedStart(center: CGFloat(x) * frameSize.width,
                                length: blockSize.width, frameLength: frameSize.width, margin: margin),
                y: clampedStart(center: CGFloat(y) * frameSize.height,
                                length: blockSize.height, frameLength: frameSize.height, margin: margin)
            )
        }
    }

    private static func anchorOrigin(forBlockSize size: CGSize,
                                     in frameSize: CGSize,
                                     margin: CGFloat,
                                     position: OverlayPosition) -> CGPoint {
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

    /// Start coordinate of a span of `length` centred on `center`, pulled back
    /// inside `margin...frameLength - margin`.
    private static func clampedStart(center: CGFloat, length: CGFloat, frameLength: CGFloat, margin: CGFloat) -> CGFloat {
        let lowest = margin
        let highest = frameLength - margin - length
        guard highest >= lowest else { return (frameLength - length) / 2 }
        return min(max(center - length / 2, lowest), highest)
    }

    /// Shrinks `baseFontSize` just enough for `text` to fit `availableWidth`,
    /// never below `minimumFontScale` of the base size.
    ///
    /// Never wraps and never truncates: at the lower bound the text is allowed
    /// to run into the margin instead (PRD FR-4.8). `measure` is supplied by the
    /// caller — it takes the text and a font size and returns the rendered width
    /// — so this policy stays testable without a font.
    static func fittedFontSize(for text: String,
                               baseFontSize: CGFloat,
                               availableWidth: CGFloat,
                               measure: (String, CGFloat) -> CGFloat) -> CGFloat {
        guard baseFontSize > 0, availableWidth > 0, !text.isEmpty else {
            return baseFontSize
        }
        let baseWidth = measure(text, baseFontSize)
        guard baseWidth > availableWidth else { return baseFontSize }
        // Rendered width is very close to linear in font size, so one division
        // lands within a rounding error of a binary search.
        let scale = max(minimumFontScale, availableWidth / baseWidth)
        return baseFontSize * scale
    }

    /// Shrinks `baseFontSize` so `text` fits `availableWidth` when drawn in
    /// `theme`'s font.
    ///
    /// The convenience both the viewfinder and the baking path call; it
    /// measures with the same font the text will actually be drawn in.
    static func fittedFontSize(for text: String,
                               theme: OverlayTheme,
                               baseFontSize: CGFloat,
                               availableWidth: CGFloat) -> CGFloat {
        fittedFontSize(for: text, baseFontSize: baseFontSize, availableWidth: availableWidth) { candidate, size in
            textWidth(of: candidate, theme: theme, fontSize: size)
        }
    }

    /// Width `text` occupies when drawn in `theme`'s font at `fontSize`.
    static func textWidth(of text: String, theme: OverlayTheme, fontSize: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font(for: theme, size: fontSize)]
        return (text as NSString).size(withAttributes: attributes).width
    }

    /// The font `theme` draws with.
    static func font(for theme: OverlayTheme, size: CGFloat) -> UIFont {
        font(for: theme.fontID, size: size)
    }

    /// One of the ten overlay fonts at `size`, at its fixed weight
    /// (PRD 0.2 FR-10.2, FR-10.3). All ship with iOS; no font file is bundled.
    ///
    /// Chinese glyphs fall back to the system's PingFang on their own; no
    /// fallback font is specified here on purpose (FR-10.3).
    static func font(for fontID: OverlayFontID, size: CGFloat) -> UIFont {
        switch fontID {
        case .sfRounded:
            return systemFont(size: size, design: .rounded)
        case .sfPro:
            return UIFont.systemFont(ofSize: size, weight: .bold)
        case .sfMono:
            return UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        case .newYork:
            return systemFont(size: size, design: .serif)
        case .avenirNext, .futura, .georgia, .americanTypewriter, .didot, .snellRoundhand:
            // Every name is checked to exist by TASK-17 17.12. The system font
            // is only a guard against a crash, never a chosen substitute.
            guard let name = fontID.postScriptName, let named = UIFont(name: name, size: size) else {
                return UIFont.systemFont(ofSize: size, weight: .bold)
            }
            return named
        }
    }

    private static func systemFont(size: CGFloat, design: UIFontDescriptor.SystemDesign) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
