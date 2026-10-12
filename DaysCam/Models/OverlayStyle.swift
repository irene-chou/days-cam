import Foundation

/// The font an overlay is drawn with (PRD 0.3 §4.1; replaces 0.2 FR-10.2's
/// ten Latin fonts).
///
/// Case order is the order the grid and the font list show them in, whatever
/// their download state. Exact weights are listed in the catalog (TASK-89). Names, sources
/// and download facts live in `FontCatalog`; turning an ID into a drawable font
/// is the rendering layer's job (`OverlayMetrics.resolvedFont`), so this type
/// stays free of UIKit.
enum OverlayFontID: String, Codable, CaseIterable {
    case pingFang
    case huninn
    case notoSerifTC
    case iansui
    case chenyuluoyan
    // TASK-142 (#494): 30 downloadable families, in type order: 黑 圓 宋 楷 手寫 可愛.
    case notoSansTC
    case taipeiSans
    case genSeki
    case chironHei
    case chocolateSans
    case glowSans
    case genSen
    case sweiGothic
    case chironGoRound
    case genWan
    case genRyu
    case sweiSpring
    case sweiSugar
    case chironSung
    case cactusSerif
    case twSung
    case thenKhung
    case lxgwWenKai
    case twKai
    case eduKai
    case arphicUKai
    case naikai
    case xiaolai
    case yozai
    case nani
    case lxgwMarker
    case kurewa
    case popGothic
    case wdxl
    case cubic11
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
    /// A square-cornered box with the same padding and color as `.box`.
    case squareBox

    /// Whether this outline draws a background box behind the text.
    var isBox: Bool {
        switch self {
        case .box, .squareBox: return true
        case .none, .stroke: return false
        }
    }
}

/// A quick preset for the shadow (TASK-71, replacing PRD 0.2 FR-10.8's four
/// fixed shadows): applying one fills in only the style's shadow geometry, and
/// `OverlayStyle.shadowPreset` names the one they still equal, if any.
///
/// The raw values are also the four shadows 0.2–0.5 stored in `shadow`, which
/// migrate to the same parameters.
enum OverlayShadowPreset: String, CaseIterable {
    /// Turns the shadow off, keeping its parameters.
    case none
    case soft
    case hard
    case glow

    /// The preset's offset and blur, in points at a 17pt font; `nil` for
    /// `.none`.
    var geometry: (offsetX: Double, offsetY: Double, blur: Double)? {
        switch self {
        case .none: return nil
        case .soft: return (0, 2, 4)
        case .hard: return (2, 2, 0)
        case .glow: return (0, 0, 8)
        }
    }
}

/// Where the shadow's color comes from (TASK-71).
enum OverlayShadowColorSource: String, Codable, CaseIterable {
    /// The text color's RGB at the shadow color's alpha, following later
    /// text color changes when explicitly selected.
    case textColor
    /// `OverlayStyle.shadowColor` as is.
    case custom
}

/// A preset color with its display name (TASK-149, #518), e.g. 底片橘.
struct NamedOverlayColor: Equatable, Hashable {
    /// Shown and read by VoiceOver in place of the hex.
    let name: String
    let color: OverlayColor
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

    /// The light tint of each `swatches` column, in the same order
    /// (TASK-149, #518): the swatch mixed 45% with white, each 8-bit
    /// component `c + (255 - c) × 0.45` rounded half up. The white and
    /// black columns use the system greys `#E5E5EA` and `#48484A` instead,
    /// since mixing would repeat white or land on a near-duplicate.
    /// Constants rather than computed, so the UI and the tests are stable.
    static let lightSwatches: [OverlayColor] = [
        OverlayColor(red8: 0xE5, green8: 0xE5, blue8: 0xEA),
        OverlayColor(red8: 0x48, green8: 0x48, blue8: 0x4A),
        OverlayColor(red8: 0x92, green8: 0xC6, blue8: 0xF7),
        OverlayColor(red8: 0xB0, green8: 0xDC, blue8: 0x9F),
        OverlayColor(red8: 0xFE, green8: 0xE2, blue8: 0xA5),
        OverlayColor(red8: 0xFE, green8: 0xC0, blue8: 0x8E),
        OverlayColor(red8: 0xF5, green8: 0x9B, blue8: 0xA2),
        OverlayColor(red8: 0xE6, green8: 0x77, blue8: 0xAD),
        OverlayColor(red8: 0xCC, green8: 0x77, blue8: 0xD9)
    ]

    /// The dark shade of each `swatches` column, in the same order
    /// (TASK-149, #518): the swatch mixed 35% with black, each component
    /// `c × 0.65` rounded half up. The white and black columns use the
    /// system greys `#AEAEB2` and `#1C1C1E` instead.
    static let darkSwatches: [OverlayColor] = [
        OverlayColor(red8: 0xAE, green8: 0xAE, blue8: 0xB2),
        OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E),
        OverlayColor(red8: 0x24, green8: 0x62, blue8: 0x9C),
        OverlayColor(red8: 0x49, green8: 0x7D, blue8: 0x34),
        OverlayColor(red8: 0xA4, green8: 0x84, blue8: 0x3C),
        OverlayColor(red8: 0xA4, green8: 0x5C, blue8: 0x21),
        OverlayColor(red8: 0x9A, green8: 0x2F, blue8: 0x38),
        OverlayColor(red8: 0x88, green8: 0x05, blue8: 0x44),
        OverlayColor(red8: 0x6A, green8: 0x05, blue8: 0x79)
    ]

    /// Classic film date-stamp colors, each with the name VoiceOver reads
    /// (TASK-149, #518).
    static let filmSwatches: [NamedOverlayColor] = [
        NamedOverlayColor(name: "底片橘", color: OverlayColor(red8: 0xFF, green8: 0x8A, blue8: 0x1E)),
        NamedOverlayColor(name: "日期紅", color: OverlayColor(red8: 0xE2, green8: 0x3B, blue8: 0x2E)),
        NamedOverlayColor(name: "琥珀黃", color: OverlayColor(red8: 0xF5, green8: 0xB7, blue8: 0x00)),
        NamedOverlayColor(name: "復古綠", color: OverlayColor(red8: 0x8D, green8: 0xB2, blue8: 0x55)),
        NamedOverlayColor(name: "褪色藍", color: OverlayColor(red8: 0x6E, green8: 0x8F, blue8: 0xB5)),
        NamedOverlayColor(name: "奶油白", color: OverlayColor(red8: 0xF4, green8: 0xEB, blue8: 0xD0))
    ]

    /// Every preset color, one tap away on the color page: `swatches`, the
    /// light and dark rows, then the film colors. No two share a hex, so a
    /// picker color matching any of them is a preset, not a custom color.
    static let allPresetColors: [OverlayColor] =
        swatches + lightSwatches + darkSwatches + filmSwatches.map(\.color)

    /// Allowed `strokeWidth`, in points at a 17pt font (TASK-70).
    static let strokeWidthRange = 1.0...6.0
    /// `strokeWidth` of a new style, and of 0.5's thin stroke (TASK-70).
    static let defaultStrokeWidth = 2.0
    /// Allowed `boxPadding`, in points at a 17pt font (TASK-70).
    static let boxPaddingRange = 0.0...24.0
    /// `boxPadding` of a new style, and of 0.5's two boxes (TASK-70).
    static let defaultBoxPadding = 12.0
    /// Allowed `shadowOffsetX` and `shadowOffsetY`, in points at a 17pt font
    /// (TASK-71).
    static let shadowOffsetRange = -8.0...8.0
    /// Allowed `shadowBlur`, in points at a 17pt font (TASK-71).
    static let shadowBlurRange = 0.0...16.0

    var fontID: OverlayFontID {
        didSet {
            if fontID != oldValue { fontWeight = FontCatalog.entry(for: fontID).defaultWeight.id }
        }
    }
    /// Optional stored face ID; absent or invalid values resolve to the default.
    var fontWeight: String?

    /// The exact face used by preview and baking.
    var resolvedFontWeight: FontWeightOption { FontCatalog.entry(for: fontID).weight(for: fontWeight) }

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
    /// Horizontal padding inside `.box` or `.squareBox`, in points at a 17pt font;
    /// `boxPaddingRange`. The vertical padding follows at
    /// `OverlayTheme.boxVerticalPaddingRatio`. Kept while another outline
    /// is chosen.
    var boxPadding: Double
    /// Whether a shadow is drawn (TASK-71). Turning it off keeps the
    /// parameters below.
    var showsShadow: Bool
    /// Where the shadow's RGB comes from (TASK-71).
    var shadowColorSource: OverlayShadowColorSource
    /// The shadow color. Its alpha is the shadow's opacity whatever
    /// `shadowColorSource` is; its RGB is used only for `.custom`, and kept
    /// while the text color is followed. Draw with `resolvedShadowColor`.
    var shadowColor: OverlayColor
    /// Horizontal shadow offset, in points at a 17pt font, positive to the
    /// right; `shadowOffsetRange`.
    var shadowOffsetX: Double
    /// Vertical shadow offset, in points at a 17pt font, positive downward;
    /// `shadowOffsetRange`.
    var shadowOffsetY: Double
    /// Shadow blur radius, in points at a 17pt font; `shadowBlurRange`.
    var shadowBlur: Double
    /// Size relative to the 0.1 base size, in percent: 70...160, step 5.
    var sizeScale: Int

    /// Creates a style. The defaults equal 0.1's "classic white" (PRD 0.2
    /// §4.2), drawn in PingFang (PRD 0.3 §4.1).
    init(fontID: OverlayFontID = .pingFang,
         fontWeight: String? = nil,
         textColor: OverlayColor = .white,
         outline: OverlayOutline = .none,
         outlineColor: OverlayColor? = nil,
         autoOutlineOpacity: Double = 1.0,
         strokeWidth: Double = Self.defaultStrokeWidth,
         boxPadding: Double = Self.defaultBoxPadding,
         shadow: OverlayShadowPreset = .soft,
         sizeScale: Int = 100) {
        self.fontID = fontID
        self.fontWeight = FontCatalog.entry(for: fontID).weight(for: fontWeight).id
        self.textColor = textColor
        self.outline = outline
        self.outlineColor = outlineColor
        self.autoOutlineOpacity = autoOutlineOpacity
        self.strokeWidth = strokeWidth
        self.boxPadding = boxPadding
        self.sizeScale = sizeScale
        showsShadow = false
        shadowColorSource = .custom
        shadowColor = OverlayColor.black.withOpacity(153.0 / 255)
        shadowOffsetX = 0
        shadowOffsetY = 0
        shadowBlur = 0
        // Soft first, so that a style created without a shadow turns on to
        // the soft one.
        applyShadowPreset(.soft)
        applyShadowPreset(shadow)
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

    /// Whether the shadow offsets and blur lie in their ranges (TASK-71).
    var hasValidShadowParameters: Bool {
        Self.shadowOffsetRange.contains(shadowOffsetX) && Self.shadowOffsetRange.contains(shadowOffsetY)
            && Self.shadowBlurRange.contains(shadowBlur)
    }

    /// Whether `sizeScale` lies in 70...160 and is a multiple of 5.
    var hasValidSizeScale: Bool {
        (Self.minimumSizeScale...Self.maximumSizeScale).contains(sizeScale)
            && sizeScale % Self.sizeScaleStep == 0
    }
}

// MARK: - Shadow (TASK-71)

extension OverlayStyle {
    /// The color the shadow is actually drawn in: `shadowColor`, or the text
    /// color's RGB at `shadowColor`'s alpha when following the text color.
    /// Opaque text or not, the alpha is the shadow's own: the text's alpha
    /// already reaches the shadow through the ink casting it (#305).
    var resolvedShadowColor: OverlayColor {
        switch shadowColorSource {
        case .textColor: return textColor.withOpacity(shadowColor.opacity)
        case .custom: return shadowColor
        }
    }

    /// The shadow's alpha, `shadowColor.opacity`, whichever color source is
    /// used.
    var shadowOpacity: Double {
        get { shadowColor.opacity }
        set { shadowColor = shadowColor.withOpacity(newValue) }
    }

    /// The preset matching only the enabled state and geometry (TASK-86).
    /// Color source, RGB and opacity do not affect selection.
    var shadowPreset: OverlayShadowPreset? {
        guard showsShadow else { return OverlayShadowPreset.none }
        return OverlayShadowPreset.allCases.first { preset in
            guard let geometry = preset.geometry else { return false }
            return geometry.offsetX == shadowOffsetX && geometry.offsetY == shadowOffsetY
                && geometry.blur == shadowBlur
        }
    }

    /// Applies geometry and enables the shadow, preserving its color and alpha.
    /// `.none` only disables it, keeping every parameter (TASK-86).
    mutating func applyShadowPreset(_ preset: OverlayShadowPreset) {
        guard let geometry = preset.geometry else {
            showsShadow = false
            return
        }
        showsShadow = true
        shadowOffsetX = geometry.offsetX
        shadowOffsetY = geometry.offsetY
        shadowBlur = geometry.blur
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

// MARK: - Coding, including 0.2–0.5 outlines (TASK-70) and shadows (TASK-71)

extension OverlayStyle {
    private enum CodingKeys: String, CodingKey {
        case fontID, fontWeight, textColor, outline, outlineColor, autoOutlineOpacity, strokeWidth, boxPadding
        case showsShadow, shadowColorSource, shadowColor, shadowOffsetX, shadowOffsetY, shadowBlur
        case sizeScale
        /// The 0.2–0.5 shadow name. Read, never written (TASK-71).
        case shadow
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
    /// A style without `showsShadow` is from 0.2–0.5: its `shadow` name
    /// becomes that preset's parameters (TASK-71 71.2), which draw the same.
    /// `none` keeps the soft parameters, so turning the shadow on gives the
    /// soft one.
    ///
    /// Parameters out of range — only a hand-edited file has them — are
    /// clamped into range, so the profile is kept.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontID = try container.decode(OverlayFontID.self, forKey: .fontID)
        let storedWeight = try? container.decode(String.self, forKey: .fontWeight)
        fontWeight = FontCatalog.entry(for: fontID).weight(for: storedWeight).id
        textColor = try container.decode(OverlayColor.self, forKey: .textColor)
        outlineColor = try container.decodeIfPresent(OverlayColor.self, forKey: .outlineColor)
        sizeScale = try container.decode(Int.self, forKey: .sizeScale)

        let showsShadow = try container.decodeIfPresent(Bool.self, forKey: .showsShadow)
        var preset = OverlayShadowPreset.soft
        if showsShadow == nil {
            let shadowName = try container.decode(String.self, forKey: .shadow)
            guard let legacyPreset = OverlayShadowPreset(rawValue: shadowName) else {
                throw DecodingError.dataCorruptedError(forKey: .shadow, in: container,
                                                       debugDescription: "Unknown shadow \(shadowName)")
            }
            preset = legacyPreset
        }
        var base = OverlayStyle(shadow: preset)
        // Preserve pre-0.5 colors independently of the geometry-only presets.
        if showsShadow == nil {
            switch preset {
            case .none, .soft: break
            case .hard: base.shadowColor = .black.withOpacity(191.0 / 255)
            case .glow:
                base.shadowColorSource = .textColor
                base.shadowColor = .black.withOpacity(230.0 / 255)
            }
        }
        self.showsShadow = showsShadow ?? base.showsShadow
        shadowColorSource = try container.decodeIfPresent(OverlayShadowColorSource.self,
                                                          forKey: .shadowColorSource) ?? base.shadowColorSource
        shadowColor = try container.decodeIfPresent(OverlayColor.self, forKey: .shadowColor) ?? base.shadowColor
        shadowOffsetX = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .shadowOffsetX) ?? base.shadowOffsetX,
            to: Self.shadowOffsetRange)
        shadowOffsetY = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .shadowOffsetY) ?? base.shadowOffsetY,
            to: Self.shadowOffsetRange)
        shadowBlur = Self.clamped(
            try container.decodeIfPresent(Double.self, forKey: .shadowBlur) ?? base.shadowBlur,
            to: Self.shadowBlurRange)

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

    /// Encodes the current format; never writes a 0.2–0.5 outline or shadow
    /// name.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontID, forKey: .fontID)
        try container.encode(resolvedFontWeight.id, forKey: .fontWeight)
        try container.encode(textColor, forKey: .textColor)
        try container.encode(outline, forKey: .outline)
        try container.encodeIfPresent(outlineColor, forKey: .outlineColor)
        try container.encode(autoOutlineOpacity, forKey: .autoOutlineOpacity)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encode(boxPadding, forKey: .boxPadding)
        try container.encode(showsShadow, forKey: .showsShadow)
        try container.encode(shadowColorSource, forKey: .shadowColorSource)
        try container.encode(shadowColor, forKey: .shadowColor)
        try container.encode(shadowOffsetX, forKey: .shadowOffsetX)
        try container.encode(shadowOffsetY, forKey: .shadowOffsetY)
        try container.encode(shadowBlur, forKey: .shadowBlur)
        try container.encode(sizeScale, forKey: .sizeScale)
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
