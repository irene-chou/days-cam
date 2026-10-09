import CoreGraphics
import Foundation

/// An sRGB color with straight alpha, in components of 0...1.
///
/// Deliberately not `UIColor` or `SwiftUI.Color`: the overlay must look
/// identical in the viewfinder and in the baked pixels, and must not follow
/// Light/Dark Mode (PRD FR-4.11). Plain components also make assertions easy.
struct OverlayColor: Equatable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// Creates a color from 8-bit sRGB components, the form the PRD states hex
    /// colors in. `#FF9500` is `OverlayColor(red8: 255, green8: 149, blue8: 0)`.
    init(red8: Int, green8: Int, blue8: Int, opacity: Double = 1.0) {
        self.init(red: Double(red8) / 255.0,
                  green: Double(green8) / 255.0,
                  blue: Double(blue8) / 255.0,
                  opacity: opacity)
    }

    static let white = OverlayColor(red: 1.0, green: 1.0, blue: 1.0)
    static let black = OverlayColor(red: 0.0, green: 0.0, blue: 0.0)
    /// The dark automatic contrast color, `#1C1C1E` (PRD 0.2 FR-10.6).
    static let autoContrastDark = OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E)
}

// MARK: - Opacity (TASK-69, #297)

extension OverlayColor {
    /// The lowest `opacity` a profile may store (TASK-69). Fainter text would
    /// look like a missing overlay rather than a style.
    static let minimumStorableOpacity = 0.05

    /// This color with `opacity` replaced; the RGB components are kept.
    func withOpacity(_ opacity: Double) -> OverlayColor {
        OverlayColor(red: red, green: green, blue: blue, opacity: opacity)
    }

    /// This color with every component, `opacity` included, rounded to the
    /// nearest 8-bit step — exactly what `hexString` stores and reads back.
    /// Out-of-range components are rounded but not clamped, so validation
    /// still sees them.
    var quantized: OverlayColor {
        func step(_ component: Double) -> Double { (component * 255).rounded() / 255 }
        return OverlayColor(red: step(red), green: step(green), blue: step(blue), opacity: step(opacity))
    }
}

// MARK: - Hex strings and contrast (PRD 0.2 §4.2, FR-10.6; TASK-69)

extension OverlayColor: Codable {
    /// Parses `#RRGGBB` (opaque) or `#RRGGBBAA` (the `#` is required,
    /// case-insensitive). Returns `nil` for anything else.
    ///
    /// An alpha below `minimumStorableOpacity` is raised to it, so every
    /// parsed color is storable and a hand-edited file loses no profile.
    init?(hex: String) {
        guard hex.count == 7 || hex.count == 9, hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        let rgb = digits.count == 8 ? value >> 8 : value
        let alpha8 = digits.count == 8 ? Int(value & 0xFF) : 0xFF
        let minimumAlpha8 = Int((Self.minimumStorableOpacity * 255).rounded(.up))
        self.init(red8: Int((rgb >> 16) & 0xFF), green8: Int((rgb >> 8) & 0xFF), blue8: Int(rgb & 0xFF),
                  opacity: Double(max(alpha8, minimumAlpha8)) / 255.0)
    }

    /// The color as an uppercase hex string, rounding each component to 8
    /// bits: `#RRGGBB` when it rounds to fully opaque — so opaque colors are
    /// stored exactly as before TASK-69 — and `#RRGGBBAA` otherwise.
    var hexString: String {
        func byte(_ component: Double) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        let rgb = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        let alpha = byte(opacity)
        return alpha == 0xFF ? rgb : rgb + String(format: "%02X", alpha)
    }

    /// Whether every RGB component is in 0...1 and `opacity` is in
    /// `minimumStorableOpacity`...1 — the colors a profile may store
    /// (PRD 0.2 §4.1 as amended by TASK-69).
    var isStorable: Bool {
        let unit = 0.0...1.0
        return unit.contains(red) && unit.contains(green) && unit.contains(blue)
            && (Self.minimumStorableOpacity...1.0).contains(opacity)
    }

    /// WCAG relative luminance of the sRGB color, 0 (black) ... 1 (white).
    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The "automatic" outline color for text in this color: `#1C1C1E` when
    /// the luminance is above 0.55, otherwise `#FFFFFF` (PRD 0.2 FR-10.6).
    var autoContrastColor: OverlayColor {
        relativeLuminance > 0.55 ? .autoContrastDark : .white
    }

    /// Decodes a `#RRGGBB` or `#RRGGBBAA` string; see `init?(hex:)`.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = OverlayColor(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Expected #RRGGBB or #RRGGBBAA, got \(string)")
        }
        self = color
    }

    /// Encodes as `hexString`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

/// Padding inside a decoration's background box, in points.
struct OverlayInsets: Equatable, Hashable {
    let horizontal: Double
    let vertical: Double

    init(horizontal: Double, vertical: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

/// Something drawn behind or around the overlay text so that it stays legible
/// on both pure white and pure black photos (PRD FR-4.6).
///
/// A theme carries an array of these because one theme can need more than one:
/// `softPink` has both a stroke and a shadow.
enum OverlayDecoration: Equatable, Hashable {
    /// A drop shadow behind the text.
    case shadow(offset: CGSize, blur: Double, opacity: Double, color: OverlayColor)
    /// A rounded box behind the text. Drawn at `color`'s alpha times
    /// `opacity`; `OverlayTheme` always passes an `opacity` of 1 since
    /// TASK-70 and puts the transparency in the color.
    case backgroundBox(color: OverlayColor, opacity: Double, cornerRadius: Double, insets: OverlayInsets)
    /// An outline around the glyphs.
    case stroke(color: OverlayColor, width: Double)
}

/// The drawing values for one `OverlayStyle`: font, fill color and the
/// decorations wrapped around the text (PRD 0.2 FR-10).
///
/// Pure data derived from the style, so that the SwiftUI viewfinder overlay and
/// the `UIGraphicsImageRenderer` baking path read the same numbers instead of
/// each hard-coding their own. Every decoration constant lives here and nowhere
/// else (TASK-18 18.11). Constants are stated at a 17pt font and scaled by
/// `OverlayMetrics.decorationScale(forFontSize:)` when drawn. Anything that
/// needs to measure text lives in `OverlayMetrics`.
struct OverlayTheme: Equatable, Hashable {
    /// The style this theme was derived from.
    let style: OverlayStyle
    /// The font the text is drawn in.
    let fontID: OverlayFontID
    /// The fill color of the glyphs.
    let textColor: OverlayColor
    /// Outline first, then shadow, applied in array order: the shadow is cast
    /// by the outlined or boxed text as a whole. Empty when both outline and
    /// shadow are `.none` (FR-10.10).
    let decorations: [OverlayDecoration]

    /// Derives the drawing values for `style`. Outlines and boxes use
    /// `style.resolvedOutlineColor`.
    init(style: OverlayStyle) {
        self.style = style
        fontID = style.fontID
        textColor = style.textColor
        decorations = [Self.outlineDecoration(for: style), Self.shadowDecoration(for: style)].compactMap { $0 }
    }

    // MARK: Decoration constants (PRD 0.2 FR-10, at a 17pt font)

    /// Corner radius of the box.
    static let boxCornerRadius: Double = 8
    /// The box's vertical padding as a fraction of `OverlayStyle.boxPadding`,
    /// its horizontal padding: 12×6 before TASK-70.
    static let boxVerticalPaddingRatio: Double = 0.5

    /// The padding inside the box for a horizontal `padding` (TASK-70).
    static func boxInsets(padding: Double) -> OverlayInsets {
        OverlayInsets(horizontal: padding, vertical: padding * boxVerticalPaddingRatio)
    }

    /// The stroke or box for `style`, in its parameters. A box's
    /// transparency is the outline color's alpha alone (TASK-70), so its
    /// `opacity` is always 1.
    private static func outlineDecoration(for style: OverlayStyle) -> OverlayDecoration? {
        let color = style.resolvedOutlineColor
        switch style.outline {
        case .none:
            return nil
        case .stroke:
            return .stroke(color: color, width: style.strokeWidth)
        case .box:
            return .backgroundBox(color: color, opacity: 1, cornerRadius: boxCornerRadius,
                                  insets: boxInsets(padding: style.boxPadding))
        }
    }

    /// The shadow for `style`, in its parameters (TASK-71). The color goes
    /// in opaque and its alpha in `opacity`, so the shadow's alpha is applied
    /// once, as 0.5's fixed shadows did; the text's own alpha reaches the
    /// shadow through the ink casting it (#305).
    private static func shadowDecoration(for style: OverlayStyle) -> OverlayDecoration? {
        guard style.showsShadow else { return nil }
        let color = style.resolvedShadowColor
        return .shadow(offset: CGSize(width: style.shadowOffsetX, height: style.shadowOffsetY),
                       blur: style.shadowBlur, opacity: color.opacity, color: color.withOpacity(1))
    }
}
