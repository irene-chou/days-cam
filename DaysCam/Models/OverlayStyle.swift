import Foundation

/// The font an overlay is drawn with (PRD 0.2 FR-10.2).
///
/// Case order is the order the style panel lists them in. Weights are fixed per
/// font (FR-10.3). Resolving an ID to an actual font is the rendering layer's
/// job; this type only names it, so that it stays free of UIKit.
enum OverlayFontID: String, Codable, CaseIterable {
    case sfRounded
    case sfPro
    case sfMono
    case newYork
    case avenirNext
    case futura
    case georgia
    case americanTypewriter
    case didot
    case snellRoundhand

    /// The font every unknown or missing ID falls back to (PRD 0.2 §4.1).
    static let fallback: OverlayFontID = .sfRounded

    /// Decodes an ID, falling back to `sfRounded` for a value this build does
    /// not know — for example a font removed in a later version — so that the
    /// profile carrying it is kept rather than discarded (PRD 0.2 §4.1).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = OverlayFontID(rawValue: rawValue) ?? Self.fallback
    }

    /// The font's own English name, shown in that font in the picker.
    var displayName: String {
        switch self {
        case .sfRounded: return "SF Rounded"
        case .sfPro: return "SF Pro"
        case .sfMono: return "SF Mono"
        case .newYork: return "New York"
        case .avenirNext: return "Avenir Next"
        case .futura: return "Futura"
        case .georgia: return "Georgia"
        case .americanTypewriter: return "Typewriter"
        case .didot: return "Didot"
        case .snellRoundhand: return "Snell Roundhand"
        }
    }

    /// The PostScript name to load with `UIFont(name:size:)`, or `nil` for the
    /// four system fonts, which are built from `UIFont.systemFont` and a design.
    var postScriptName: String? {
        switch self {
        case .sfRounded, .sfPro, .sfMono, .newYork: return nil
        case .avenirNext: return "AvenirNext-Bold"
        case .futura: return "Futura-Bold"
        case .georgia: return "Georgia-Bold"
        case .americanTypewriter: return "AmericanTypewriter-Semibold"
        case .didot: return "Didot-Bold"
        case .snellRoundhand: return "SnellRoundhand-Bold"
        }
    }
}

/// The outline or background box drawn around the text (PRD 0.2 FR-10.5).
enum OverlayOutline: String, Codable, CaseIterable {
    case none
    case thinStroke
    case thickStroke
    case translucentBox
    case solidBox
}

/// The shadow drawn behind the text (PRD 0.2 FR-10.8).
enum OverlayShadow: String, Codable, CaseIterable {
    case none
    case soft
    case hard
    case glow
}

/// How an overlay looks: font, colors, outline, shadow and size
/// (PRD 0.2 §4.2). Replaces the five fixed themes of 0.1.
///
/// Pure data on purpose — no UIKit or SwiftUI — so that the viewfinder and the
/// baking path derive their drawing values from the same source.
struct OverlayStyle: Equatable, Hashable, Codable {
    /// Smallest allowed `sizeScale`, in percent (FR-10.9).
    static let minimumSizeScale = 70
    /// Largest allowed `sizeScale`, in percent (FR-10.9).
    static let maximumSizeScale = 160
    /// `sizeScale` must be a multiple of this (FR-10.9).
    static let sizeScaleStep = 5

    /// The nine preset colors of the first color row, in order (FR-10.4):
    /// Instagram's text palette — white, black, blue, green, yellow, orange,
    /// red, magenta, purple.
    static let swatches: [OverlayColor] = [
        OverlayColor(red8: 0xFF, green8: 0xFF, blue8: 0xFF),
        OverlayColor(red8: 0x00, green8: 0x00, blue8: 0x00),
        OverlayColor(red8: 0x38, green8: 0x97, blue8: 0xF0),
        OverlayColor(red8: 0x70, green8: 0xC0, blue8: 0x50),
        OverlayColor(red8: 0xFD, green8: 0xCB, blue8: 0x5C),
        OverlayColor(red8: 0xFD, green8: 0x8D, blue8: 0x32),
        OverlayColor(red8: 0xED, green8: 0x49, blue8: 0x56),
        OverlayColor(red8: 0xD1, green8: 0x08, blue8: 0x69),
        OverlayColor(red8: 0xA3, green8: 0x07, blue8: 0xBA)
    ]

    var fontID: OverlayFontID
    var textColor: OverlayColor
    var outline: OverlayOutline
    /// The outline or box color; `nil` means "automatic" (FR-10.6).
    var outlineColor: OverlayColor?
    var shadow: OverlayShadow
    /// Size relative to the 0.1 base size, in percent: 70...160, step 5.
    var sizeScale: Int

    /// Creates a style. The defaults equal 0.1's "classic white" (PRD 0.2 §4.2).
    init(fontID: OverlayFontID = .sfRounded,
         textColor: OverlayColor = .white,
         outline: OverlayOutline = .none,
         outlineColor: OverlayColor? = nil,
         shadow: OverlayShadow = .soft,
         sizeScale: Int = 100) {
        self.fontID = fontID
        self.textColor = textColor
        self.outline = outline
        self.outlineColor = outlineColor
        self.shadow = shadow
        self.sizeScale = sizeScale
    }

    /// The color outlines and boxes are actually drawn in: the chosen
    /// `outlineColor`, or the automatic contrast color of `textColor`.
    var resolvedOutlineColor: OverlayColor {
        outlineColor ?? textColor.autoContrastColor
    }

    /// Whether `sizeScale` lies in 70...160 and is a multiple of 5.
    var hasValidSizeScale: Bool {
        (Self.minimumSizeScale...Self.maximumSizeScale).contains(sizeScale)
            && sizeScale % Self.sizeScaleStep == 0
    }
}

// MARK: - 0.1 migration

extension OverlayStyle {
    /// The closest new style for one of the five 0.1 themes (PRD 0.2 §4.3).
    ///
    /// Not pixel-identical: shadow and box opacities differ slightly (A-2).
    init(legacyTheme: ThemeID) {
        switch legacyTheme {
        case .classicWhite:
            self.init()
        case .retroOrange:
            self.init(fontID: .sfMono,
                      textColor: OverlayColor(red8: 0xFF, green8: 0x95, blue8: 0x00),
                      outline: .none,
                      shadow: .soft)
        case .filmStrip:
            self.init(fontID: .sfMono,
                      textColor: .white,
                      outline: .translucentBox,
                      shadow: .none)
        case .minimalDark:
            self.init(fontID: .sfPro,
                      textColor: OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E),
                      outline: .translucentBox,
                      shadow: .none)
        case .softPink:
            self.init(fontID: .sfRounded,
                      textColor: OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D),
                      outline: .thinStroke,
                      shadow: .soft)
        }
    }
}
