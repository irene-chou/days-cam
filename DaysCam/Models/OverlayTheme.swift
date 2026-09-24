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

// MARK: - Hex strings and contrast (PRD 0.2 §4.2, FR-10.6)

extension OverlayColor: Codable {
    /// Parses an opaque `#RRGGBB` string (the `#` is required, case-insensitive).
    /// Returns `nil` for anything else.
    init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit), let value = Int(digits, radix: 16) else { return nil }
        self.init(red8: (value >> 16) & 0xFF, green8: (value >> 8) & 0xFF, blue8: value & 0xFF)
    }

    /// The color as an uppercase `#RRGGBB` string, rounding each component to
    /// 8 bits and ignoring `opacity`.
    var hexString: String {
        func byte(_ component: Double) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Whether every RGB component is in 0...1 and the color is fully opaque —
    /// the only colors a profile may store (PRD 0.2 §4.1).
    var isStorable: Bool {
        let unit = 0.0...1.0
        return unit.contains(red) && unit.contains(green) && unit.contains(blue) && opacity == 1.0
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

    /// Decodes a `#RRGGBB` string.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = OverlayColor(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Expected #RRGGBB, got \(string)")
        }
        self = color
    }

    /// Encodes as a `#RRGGBB` string.
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
    /// A rounded, usually translucent box behind the text.
    case backgroundBox(color: OverlayColor, opacity: Double, cornerRadius: Double, insets: OverlayInsets)
    /// An outline around the glyphs.
    case stroke(color: OverlayColor, width: Double)
}

/// The system font family a theme draws with.
///
/// Only system fonts are used; no font file is bundled (PRD FR-4.10).
enum OverlayFontDesign: String, Codable, CaseIterable {
    case system
    case rounded
    case monospaced
}

/// The weight a theme draws its text at.
enum OverlayFontWeight: String, Codable, CaseIterable {
    case regular
    case semibold
    case bold
}

/// One of the five preset looks: a fixed font, color and decoration combination
/// that the user switches as a whole (PRD §3.4).
///
/// This type is pure data on purpose, so that the SwiftUI viewfinder overlay and
/// the `UIGraphicsImageRenderer` baking path read the same numbers instead of
/// each hard-coding their own. Anything that needs to measure text lives in
/// `OverlayMetrics`.
struct OverlayTheme: Equatable, Hashable, Identifiable {
    let id: ThemeID
    /// Name shown in the theme picker, in Traditional Chinese.
    let displayName: String
    let fontDesign: OverlayFontDesign
    let fontWeight: OverlayFontWeight
    let textColor: OverlayColor
    /// At least one entry for every theme (PRD FR-4.6).
    let decorations: [OverlayDecoration]

    /// Every theme, in the order of the PRD §3.4 table.
    static let all: [OverlayTheme] = [
        OverlayTheme(
            id: .classicWhite,
            displayName: "經典白",
            fontDesign: .rounded,
            fontWeight: .bold,
            textColor: .white,
            decorations: [
                .shadow(offset: CGSize(width: 0, height: 2), blur: 4, opacity: 0.6, color: .black)
            ]
        ),
        OverlayTheme(
            id: .retroOrange,
            displayName: "復古橘",
            fontDesign: .monospaced,
            fontWeight: .bold,
            textColor: OverlayColor(red8: 255, green8: 149, blue8: 0),
            decorations: [
                .shadow(offset: CGSize(width: 0, height: 1), blur: 3, opacity: 0.8, color: .black)
            ]
        ),
        OverlayTheme(
            id: .filmStrip,
            displayName: "底片邊條",
            fontDesign: .monospaced,
            fontWeight: .bold,
            textColor: .white,
            decorations: [
                .backgroundBox(color: .black,
                               opacity: 0.45,
                               cornerRadius: 8,
                               insets: OverlayInsets(horizontal: 12, vertical: 6))
            ]
        ),
        OverlayTheme(
            id: .minimalDark,
            displayName: "極簡黑",
            fontDesign: .system,
            fontWeight: .semibold,
            textColor: OverlayColor(red8: 28, green8: 28, blue8: 30),
            decorations: [
                .backgroundBox(color: .white,
                               opacity: 0.7,
                               cornerRadius: 8,
                               insets: OverlayInsets(horizontal: 12, vertical: 6))
            ]
        ),
        OverlayTheme(
            id: .softPink,
            displayName: "柔粉",
            fontDesign: .rounded,
            fontWeight: .bold,
            textColor: OverlayColor(red8: 255, green8: 107, blue8: 157),
            decorations: [
                .stroke(color: .white, width: 2),
                .shadow(offset: CGSize(width: 0, height: 1), blur: 2, opacity: 0.3, color: .black)
            ]
        )
    ]

    /// The theme for `id`, falling back to the default `classicWhite` so that a
    /// lookup never fails and never force-unwraps.
    static func theme(for id: ThemeID) -> OverlayTheme {
        all.first { $0.id == id } ?? all[0]
    }
}
