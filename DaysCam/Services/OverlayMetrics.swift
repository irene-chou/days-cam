import CoreGraphics
import Foundation
import UIKit

/// The one place font size, margin and shrink-to-fit are computed.
///
/// The viewfinder overlay (`OverlayTextView`) and the baking path
/// (`OverlayRenderer`) must produce the same layout at very different pixel
/// sizes — a ~400pt preview and a 3024x4032 photo — so both call these
/// functions instead of each carrying its own copy of the percentages
/// (PRD FR-4.7, FR-4.8, FR-4.3; 0.2 FR-5.10, FR-12). It is also where a
/// style's font is resolved to the face actually drawn (0.3 FR-5.14).
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
    /// `font`.
    ///
    /// The convenience both the viewfinder and the baking path call; it
    /// measures with the very font the text will be drawn in (PRD 0.3 FR-5.14).
    static func fittedFontSize(for text: String,
                               font: ResolvedOverlayFont,
                               baseFontSize: CGFloat,
                               availableWidth: CGFloat) -> CGFloat {
        fittedFontSize(for: text, baseFontSize: baseFontSize, availableWidth: availableWidth) { candidate, size in
            textWidth(of: candidate, font: font, fontSize: size)
        }
    }

    /// Width `text` occupies when drawn in `font` at `fontSize`.
    static func textWidth(of text: String, font: ResolvedOverlayFont, fontSize: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font.font(ofSize: fontSize)]
        return (text as NSString).size(withAttributes: attributes).width
    }

    // MARK: - Font resolution (PRD 0.3 FR-5.14)

    /// The one function that turns a style's `fontID` into the face actually
    /// drawn, for the viewfinder and the photo alike (PRD 0.3 FR-5.14).
    ///
    /// The font itself when `availability` says `.available` and it loads;
    /// PingFang otherwise (FR-16.14). PingFang never asks `availability`.
    /// No fallback list is given for missing glyphs: the system fills them in
    /// on its own (FR-10.3′).
    ///
    /// Main actor only: resolve once there, then hand the `Sendable` result
    /// to the viewfinder and to the background baking work.
    @MainActor
    static func resolvedFont(for fontID: OverlayFontID,
                             weightID: String? = nil,
                             availability: any FontAvailabilityProviding) -> ResolvedOverlayFont {
        let entry = FontCatalog.entry(for: fontID)
        let weight = entry.weight(for: weightID)
        return resolvedFont(state: entry.source == .builtIn ? .available : availability.state(for: fontID, weightID: weight.id),
                            postScriptName: weight.postScriptName)
    }

    /// Resolves a profile's font and weight together before measuring or baking.
    @MainActor
    static func resolvedFont(for style: OverlayStyle,
                             availability: any FontAvailabilityProviding) -> ResolvedOverlayFont {
        resolvedFont(for: style.fontID, weightID: style.fontWeight, availability: availability)
    }

    /// The rule behind `resolvedFont(for:availability:)`, with the state and
    /// name passed in so tests can stand in a font that ships with iOS.
    ///
    /// A font that is not `.available` resolves to PingFang even if iOS could
    /// load it — a match that finished after its timeout must not change the
    /// photo (TASK-32 32.7a). A font reported `.available` that still fails to
    /// load also resolves to PingFang, never to some other face.
    static func resolvedFont(state: FontState, postScriptName: String) -> ResolvedOverlayFont {
        guard state.isAvailable,
              postScriptName != FontCatalog.pingFangPostScriptName,
              UIFont(name: postScriptName, size: referenceFontSize) != nil else {
            return .pingFang
        }
        return ResolvedOverlayFont(postScriptName: postScriptName)
    }

    /// `fontID` at `size` and its fixed weight, resolved against
    /// `availability` (PRD 0.3 §4.1, FR-5.14). For UI that draws a font by
    /// itself, such as the style grid; overlay text goes through
    /// `resolvedFont(for:availability:)` and the renderer's `font:` forms.
    @MainActor
    static func font(for fontID: OverlayFontID, weightID: String? = nil, size: CGFloat, availability: any FontAvailabilityProviding) -> UIFont {
        resolvedFont(for: fontID, weightID: weightID, availability: availability).font(ofSize: size)
    }
}

/// The face overlay text is actually drawn in, after
/// `OverlayMetrics.resolvedFont(for:availability:)` (PRD 0.3 FR-5.14).
///
/// A value, so it can be captured on the main actor at shutter time and
/// carried to the background baking work, and used in a viewfinder cache key:
/// two equal values draw identical glyphs. Only `OverlayMetrics` creates one,
/// so every instance has been through resolution.
struct ResolvedOverlayFont: Hashable, Sendable {
    /// PingFang, which always ships with iOS (PRD 0.3 A-6, 32.8).
    static let pingFang = ResolvedOverlayFont(postScriptName: FontCatalog.pingFangPostScriptName)

    /// The PostScript name of the face drawn.
    let postScriptName: String

    fileprivate init(postScriptName: String) {
        self.postScriptName = postScriptName
    }

    /// The face at `size` points.
    ///
    /// Resolution has already checked the name loads. Should iOS drop the
    /// font in between, PingFang is drawn, as for any unavailable font; the
    /// system font only guards against a crash. Measuring and drawing both
    /// call this, so they still agree.
    func font(ofSize size: CGFloat) -> UIFont {
        UIFont(name: postScriptName, size: size)
            ?? UIFont(name: FontCatalog.pingFangPostScriptName, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .semibold)
    }
}
