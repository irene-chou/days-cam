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

/// The outline or background box drawn around the text (PRD 0.2 FR-10.5 as
/// amended by TASK-70). How thick or roomy it is lives in the style's
/// `strokeWidth` and `boxPadding`; how transparent, in the outline color's
/// alpha.
enum OverlayOutline: String, Codable, CaseIterable {
    case none
    /// An outline around the glyphs, `OverlayStyle.strokeWidth` wide.
    case stroke
    /// A rounded box behind the text, padded by `OverlayStyle.boxPadding`.
    case box
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

    /// Allowed `strokeWidth`, in points at a 17pt font (TASK-70).
    static let strokeWidthRange = 1.0...6.0
    /// `strokeWidth` of a new style, and of 0.5's thin stroke (TASK-70).
    static let defaultStrokeWidth = 2.0
    /// Allowed `boxPadding`, in points at a 17pt font (TASK-70).
    static let boxPaddingRange = 0.0...24.0
    /// `boxPadding` of a new style, and of 0.5's two boxes (TASK-70).
    static let defaultBoxPadding = 12.0

    var fontID: OverlayFontID
    var textColor: OverlayColor
    var outline: OverlayOutline
    /// The outline or box color; `nil` means "automatic" (FR-10.6).
    var outlineColor: OverlayColor?
    /// The alpha of the automatic outline color, used only while
    /// `outlineColor` is `nil` (TASK-70): the automatic color itself is
    /// always opaque, so a translucent box in the automatic color needs
    /// somewhere to keep its alpha. Edit it through `outlineOpacity`.
    var autoOutlineOpacity: Double
    /// Visible stroke width of `.stroke` outside the glyphs, in points at a
    /// 17pt font; `strokeWidthRange`. Kept while another outline is chosen.
    var strokeWidth: Double
    /// Horizontal padding inside `.box`, in points at a 17pt font;
    /// `boxPaddingRange`. The vertical padding follows at
    /// `OverlayTheme.boxVerticalPaddingRatio`. Kept while another outline
    /// is chosen.
    var boxPadding: Double
    var shadow: OverlayShadow
    /// Size relative to the 0.1 base size, in percent: 70...160, step 5.
    var sizeScale: Int

    /// Creates a style. The defaults equal 0.1's "classic white" (PRD 0.2
    /// §4.2), drawn in PingFang (PRD 0.3 §4.1).
    init(fontID: OverlayFontID = .pingFang,
         textColor: OverlayColor = .white,
         outline: OverlayOutline = .none,
         outlineColor: OverlayColor? = nil,
         autoOutlineOpacity: Double = 1.0,
         strokeWidth: Double = Self.defaultStrokeWidth,
         boxPadding: Double = Self.defaultBoxPadding,
         shadow: OverlayShadow = .soft,
         sizeScale: Int = 100) {
        self.fontID = fontID
        self.textColor = textColor
        self.outline = outline
        self.outlineColor = outlineColor
        self.autoOutlineOpacity = autoOutlineOpacity
        self.strokeWidth = strokeWidth
        self.boxPadding = boxPadding
        self.shadow = shadow
        self.sizeScale = sizeScale
    }

    /// The color outlines and boxes are actually drawn in: the chosen
    /// `outlineColor`, or the automatic contrast color of `textColor` at
    /// `autoOutlineOpacity`.
    var resolvedOutlineColor: OverlayColor {
        outlineColor ?? textColor.autoContrastColor.withOpacity(autoOutlineOpacity)
    }

    /// The outline's alpha, whichever color it is drawn in: reads and writes
    /// `outlineColor`'s opacity when a color is chosen, `autoOutlineOpacity`
    /// while it is automatic (TASK-70). A box's transparency is this alpha.
    var outlineOpacity: Double {
        get { outlineColor?.opacity ?? autoOutlineOpacity }
        set {
            if let outlineColor {
                self.outlineColor = outlineColor.withOpacity(newValue)
            } else {
                autoOutlineOpacity = newValue
            }
        }
    }

    /// Whether `strokeWidth` and `boxPadding` lie in their ranges (TASK-70).
    var hasValidOutlineParameters: Bool {
        Self.strokeWidthRange.contains(strokeWidth) && Self.boxPaddingRange.contains(boxPadding)
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
                      outline: .box,
                      autoOutlineOpacity: Self.legacyTranslucentBoxOpacity,
                      shadow: .none)
        case .minimalDark:
            self.init(textColor: OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E),
                      outline: .box,
                      autoOutlineOpacity: Self.legacyTranslucentBoxOpacity,
                      shadow: .none)
        case .softPink:
            self.init(textColor: OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D),
                      outline: .stroke,
                      shadow: .soft)
        }
    }
}

// MARK: - Coding, including 0.2–0.5 outlines (TASK-70)

extension OverlayStyle {
    private enum CodingKeys: String, CodingKey {
        case fontID, textColor, outline, outlineColor, autoOutlineOpacity, strokeWidth, boxPadding
        case shadow, sizeScale
    }

    /// The four outlines 0.2–0.5 stored in `outline`. Read, never written.
    private enum LegacyOutline: String {
        case thinStroke
        case thickStroke
        case translucentBox
        case solidBox
    }

    /// The box opacity 0.2–0.5 drew `translucentBox` at, on top of the
    /// outline color's own alpha.
    static let legacyTranslucentBoxOpacity = 0.5

    /// Decodes a style, converting a 0.2–0.5 outline to the outline and
    /// parameters that draw the same (TASK-70 70.2):
    ///
    /// | 0.5              | now                                        |
    /// |------------------|--------------------------------------------|
    /// | `thinStroke`     | `.stroke`, width 2                         |
    /// | `thickStroke`    | `.stroke`, width 4                         |
    /// | `translucentBox` | `.box`, padding 12, outline alpha × 0.5    |
    /// | `solidBox`       | `.box`, padding 12                         |
    ///
    /// The halved alpha goes to `outlineColor`, or to `autoOutlineOpacity`
    /// when the color is automatic, so "automatic" survives. It is raised to
    /// `OverlayColor.minimumStorableOpacity` if halving goes below it.
    /// Parameters out of range — only a hand-edited file has them — are
    /// clamped into range, so the profile is kept.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontID = try container.decode(OverlayFontID.self, forKey: .fontID)
        textColor = try container.decode(OverlayColor.self, forKey: .textColor)
        outlineColor = try container.decodeIfPresent(OverlayColor.self, forKey: .outlineColor)
        shadow = try container.decode(OverlayShadow.self, forKey: .shadow)
        sizeScale = try container.decode(Int.self, forKey: .sizeScale)

        let minimumOpacity = OverlayColor.minimumStorableOpacity
        autoOutlineOpacity = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .autoOutlineOpacity) ?? 1.0,
            to: minimumOpacity...1.0)
        strokeWidth = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? Self.defaultStrokeWidth,
            to: Self.strokeWidthRange)
        boxPadding = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .boxPadding) ?? Self.defaultBoxPadding,
            to: Self.boxPaddingRange)

        let outlineName = try container.decode(String.self, forKey: .outline)
        if let outline = OverlayOutline(rawValue: outlineName) {
            self.outline = outline
            return
        }
        // Literal values on purpose: they are what 0.5 drew, whatever the
        // defaults become.
        switch LegacyOutline(rawValue: outlineName) {
        case .thinStroke:
            outline = .stroke
            strokeWidth = 2
        case .thickStroke:
            outline = .stroke
            strokeWidth = 4
        case .translucentBox:
            outline = .box
            boxPadding = 12
            outlineOpacity = max(outlineOpacity * Self.legacyTranslucentBoxOpacity, minimumOpacity)
        case .solidBox:
            outline = .box
            boxPadding = 12
        case nil:
            throw DecodingError.dataCorruptedError(forKey: .outline, in: container,
                                                   debugDescription: "Unknown outline \(outlineName)")
        }
    }

    /// Encodes the current format; never writes a 0.2–0.5 outline name.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontID, forKey: .fontID)
        try container.encode(textColor, forKey: .textColor)
        try container.encode(outline, forKey: .outline)
        try container.encodeIfPresent(outlineColor, forKey: .outlineColor)
        try container.encode(autoOutlineOpacity, forKey: .autoOutlineOpacity)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encode(boxPadding, forKey: .boxPadding)
        try container.encode(shadow, forKey: .shadow)
        try container.encode(sizeScale, forKey: .sizeScale)
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
