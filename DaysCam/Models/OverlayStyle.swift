import Foundation

/// The font an overlay is drawn with (PRD 0.3 §4.1; replaces 0.2 FR-10.2's
/// ten Latin fonts).
///
/// Case order is the order the grid and the font list show them in, whatever
/// their download state. Weights are fixed per font (FR-10.3′). Names, sources
/// and download facts live in `FontCatalog`; turning an ID into a drawable font
/// is the rendering layer's job (`OverlayMetrics.resolvedFont`), so this type
/// stays free of UIKit.
enum OverlayFontID: String, Codable, CaseIterable {
    case pingFang
    case huninn
    case notoSerifTC
    case iansui
    case chenyuluoyan
    case lantinghei
    case liHei
    case hiraginoSans
    case yuanti
    case songti
    case liSong
    case kaiti
    case biauKai
    case hanziPen
    case hannotate
    case lingWai
    case xingkai
    case weibei
    case libian
    case baoli
    case wawa
    case yuppy

    /// The font every unknown or missing ID falls back to (PRD 0.3 §4.1,
    /// replacing 0.2's `sfRounded`).
    static let fallback: OverlayFontID = .pingFang

    /// Decodes an ID, falling back to `pingFang` for a value this build does
    /// not know — including the ten 0.2 fonts removed in 0.3 — so that the
    /// profile carrying it is kept rather than discarded (PRD 0.3 §4.1, §4.3).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = OverlayFontID(rawValue: rawValue) ?? Self.fallback
    }

    /// The font's Chinese name, as the grid and the list show it.
    var displayName: String { FontCatalog.entry(for: self).displayName }

    /// The PostScript name of the one face this font is drawn in (§4.1).
    var postScriptName: String { FontCatalog.entry(for: self).postScriptName }
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

    /// Creates a style. The defaults equal 0.1's "classic white" (PRD 0.2
    /// §4.2), drawn in PingFang (PRD 0.3 §4.1).
    init(fontID: OverlayFontID = .pingFang,
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
    /// The font is always PingFang: the 0.2 fonts that table named were
    /// removed in 0.3 (PRD 0.3 §4.3).
    init(legacyTheme: ThemeID) {
        switch legacyTheme {
        case .classicWhite:
            self.init()
        case .retroOrange:
            self.init(textColor: OverlayColor(red8: 0xFF, green8: 0x95, blue8: 0x00),
                      outline: .none,
                      shadow: .soft)
        case .filmStrip:
            self.init(textColor: .white,
                      outline: .translucentBox,
                      shadow: .none)
        case .minimalDark:
            self.init(textColor: OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E),
                      outline: .translucentBox,
                      shadow: .none)
        case .softPink:
            self.init(textColor: OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D),
                      outline: .thinStroke,
                      shadow: .soft)
        }
    }
}
