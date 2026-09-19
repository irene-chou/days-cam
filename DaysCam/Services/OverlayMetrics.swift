import CoreGraphics
import Foundation
import UIKit

/// The one place font size, margin and shrink-to-fit are computed.
///
/// The viewfinder overlay (`OverlayTextView`) and the baking path
/// (`OverlayRenderer`) must produce the same layout at very different pixel
/// sizes — a ~400pt preview and a 3024x4032 photo — so both call these
/// functions instead of each carrying its own copy of the percentages
/// (PRD FR-4.7, FR-4.8, FR-4.3).
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

    /// Base font size for a frame whose short edge is `shortEdge`.
    static func baseFontSize(forShortEdge shortEdge: CGFloat) -> CGFloat {
        shortEdge * baseFontRatio
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

    /// The system font a theme draws with. No font file is bundled, so this only
    /// ever returns a system face (PRD FR-4.10).
    static func font(for theme: OverlayTheme, size: CGFloat) -> UIFont {
        let weight = uiFontWeight(for: theme.fontWeight)
        switch theme.fontDesign {
        case .system:
            return UIFont.systemFont(ofSize: size, weight: weight)
        case .monospaced:
            return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded:
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }
    }

    private static func uiFontWeight(for weight: OverlayFontWeight) -> UIFont.Weight {
        switch weight {
        case .regular:
            return .regular
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }
}
