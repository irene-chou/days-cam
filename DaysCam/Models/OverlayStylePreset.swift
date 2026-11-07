import Foundation

/// One of the ten named looks of the style panel (D-10, #676): a fixed font,
/// weight, outline and shadow, Instagram-style. The text color, the box state
/// and the size stay the user's.
///
/// Case order is the order the panel shows them in. Not stored: a profile
/// keeps the plain `OverlayStyle` fields, and `OverlayStyle.preset` names the
/// look they still equal.
enum OverlayStylePreset: String, CaseIterable, Codable {
    case classic
    case caption
    case poster
    case outline
    case magazine
    case handwriting
    case note
    case cute
    case neon
    case retro

    /// The name the panel shows.
    var displayName: String {
        switch self {
        case .classic: return "經典"
        case .caption: return "字幕"
        case .poster: return "海報"
        case .outline: return "描邊"
        case .magazine: return "雜誌"
        case .handwriting: return "手寫"
        case .note: return "便條"
        case .cute: return "可愛"
        case .neon: return "霓虹"
        case .retro: return "復古"
        }
    }

    /// The text color a fresh application of this look uses.
    var defaultTextColor: OverlayColor {
        switch self {
        case .classic, .caption, .poster, .outline, .magazine, .handwriting: return .white
        case .note: return .autoContrastDark
        case .cute: return OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D)
        case .neon: return OverlayColor(red8: 0xFF, green8: 0xD1, blue8: 0xE3)
        case .retro: return OverlayColor(red8: 0xFF, green8: 0x8A, blue8: 0x1E)
        }
    }

    /// The box shape this look gives its solid and translucent box states
    /// (#692): `squareBox`, `box` (corner 8) or `capsuleBox`.
    var boxShape: OverlayOutline {
        switch self {
        case .poster, .outline, .magazine: return .squareBox
        case .classic, .caption, .note, .retro: return .box
        case .handwriting, .cute, .neon: return .capsuleBox
        }
    }

    /// The look as a style in `defaultTextColor` at size 100. Every field
    /// but `textColor` and `sizeScale` is what `OverlayStyle.apply` writes.
    var style: OverlayStyle {
        var style: OverlayStyle
        switch self {
        case .classic:
            style = OverlayStyle(shadow: .soft)
        case .caption:
            style = OverlayStyle(outline: .box, autoOutlineOpacity: 0.45, shadow: .none)
        case .poster:
            style = OverlayStyle(fontID: .notoSansTC, fontWeight: "black", outline: .squareBox, shadow: .none)
        case .outline:
            style = OverlayStyle(fontID: .notoSansTC, fontWeight: "black", outline: .stroke, strokeWidth: 3,
                                 shadow: .none)
        case .magazine:
            style = OverlayStyle(fontID: .notoSerifTC, fontWeight: "bold", shadow: .soft)
        case .handwriting:
            style = OverlayStyle(fontID: .chenyuluoyan, fontWeight: "thin", shadow: .soft)
        case .note:
            style = OverlayStyle(fontID: .iansui, fontWeight: "regular", outline: .box, autoOutlineOpacity: 0.88,
                                 shadow: .none)
        case .cute:
            style = OverlayStyle(fontID: .huninn, fontWeight: "regular", outline: .stroke, shadow: .soft)
            // 0.35, rounded to the 8-bit step a profile stores, so the look
            // survives a save.
            style.shadowColor = .black.withOpacity(89.0 / 255)
        case .neon, .retro:
            style = OverlayStyle(fontID: self == .neon ? .huninn : .pingFang,
                                 fontWeight: self == .neon ? "regular" : "semibold", shadow: .glow)
            style.shadowColorSource = .textColor
            style.shadowColor = .black.withOpacity(230.0 / 255)
        }
        style.textColor = defaultTextColor
        return style
    }
}

/// The three states of the box button (D-10, #676): the look's own outline,
/// then a solid and a translucent box in the automatic color.
enum OverlayBoxState: CaseIterable {
    /// The outline the look's table gives it.
    case base
    /// The look's `boxShape`, automatic color at full opacity, padding 12.
    case solid
    /// The look's `boxShape`, automatic color at 0.45, padding 12.
    case translucent

    /// The state one press of the button leads to.
    var next: OverlayBoxState {
        switch self {
        case .base: return .solid
        case .solid: return .translucent
        case .translucent: return .base
        }
    }

    /// The automatic box opacity of `solid` and `translucent`; `nil` for `base`.
    var boxOpacity: Double? {
        switch self {
        case .base: return nil
        case .solid: return 1.0
        case .translucent: return 0.45
        }
    }
}

// MARK: - Presets on a style (D-10, #676)

extension OverlayStyle {
    /// The look this style shows as, or `nil` for a custom style (D-10).
    ///
    /// A look matches when the font, the weight and the shadow equal its own
    /// and the outline is its own; failing every look, when the outline is
    /// instead a solid or translucent box and the stroke width the box
    /// states leave alone is still the look's — which tells `outline` (3)
    /// from `poster` (2), sharing font and shadow. Each round goes in case
    /// order, so a look's own outline wins over another's box state. The
    /// text color, the size and the shadow's RGB do not count.
    var preset: OverlayStylePreset? {
        let candidates = OverlayStylePreset.allCases.filter(hasFontAndShadow(of:))
        return candidates.first { hasOutline(of: $0.style) }
            ?? candidates.first { boxState(for: $0) != nil && strokeWidth == $0.style.strokeWidth }
    }

    /// Which box state of `preset` the outline is in, looking at the outline
    /// alone; `nil` when it is none of them. The look's own outline wins when
    /// it equals a box state, as `caption`'s translucent box does.
    func boxState(for preset: OverlayStylePreset) -> OverlayBoxState? {
        if hasOutline(of: preset.style) { return .base }
        guard outline == preset.boxShape, outlineColor == nil, boxPadding == Self.defaultBoxPadding else { return nil }
        return OverlayBoxState.allCases.first { $0.boxOpacity == autoOutlineOpacity }
    }

    /// Moves the outline to the next box state of `preset`: base, solid,
    /// translucent, base. Changes only the outline fields. Does nothing when
    /// the outline is in none of the states, as for a custom style. A state
    /// that would look the same as the current one is skipped, so `poster`,
    /// whose own outline is the solid box, cycles base, translucent, base.
    mutating func cycleBoxState(for preset: OverlayStylePreset) {
        guard let state = boxState(for: preset) else { return }
        var next = state.next
        if hasOutline(of: Self.outlineAfter(next, of: preset, from: self)) {
            next = next.next
        }
        self = Self.outlineAfter(next, of: preset, from: self)
    }

    /// `style` with its outline fields moved to `state` of `preset`.
    private static func outlineAfter(_ state: OverlayBoxState, of preset: OverlayStylePreset,
                                     from style: OverlayStyle) -> OverlayStyle {
        var result = style
        if let opacity = state.boxOpacity {
            result.outline = preset.boxShape
            result.outlineColor = nil
            result.autoOutlineOpacity = opacity
            result.boxPadding = defaultBoxPadding
        } else {
            result.copyOutline(from: preset.style)
        }
        return result
    }

    /// Applies `preset`'s font, weight, outline and shadow; keeps the size.
    /// The text color becomes `preset.defaultTextColor` only when it is still
    /// the previous look's default, so a color the user picked survives.
    mutating func apply(_ preset: OverlayStylePreset) {
        if let current = self.preset, textColor == current.defaultTextColor {
            textColor = preset.defaultTextColor
        }
        let look = preset.style
        // Font first: its didSet resets the weight, which is then overwritten.
        fontID = look.fontID
        fontWeight = look.fontWeight
        copyOutline(from: look)
        showsShadow = look.showsShadow
        shadowColorSource = look.shadowColorSource
        shadowColor = look.shadowColor
        shadowOffsetX = look.shadowOffsetX
        shadowOffsetY = look.shadowOffsetY
        shadowBlur = look.shadowBlur
    }

    private mutating func copyOutline(from look: OverlayStyle) {
        outline = look.outline
        outlineColor = look.outlineColor
        autoOutlineOpacity = look.autoOutlineOpacity
        strokeWidth = look.strokeWidth
        boxPadding = look.boxPadding
    }

    private func hasOutline(of look: OverlayStyle) -> Bool {
        outline == look.outline && outlineColor == look.outlineColor
            && autoOutlineOpacity == look.autoOutlineOpacity && strokeWidth == look.strokeWidth
            && boxPadding == look.boxPadding
    }

    private func hasFontAndShadow(of preset: OverlayStylePreset) -> Bool {
        let look = preset.style
        // Opacity compared at the 8-bit step a profile stores it in.
        return fontID == look.fontID && resolvedFontWeight.id == look.resolvedFontWeight.id
            && showsShadow == look.showsShadow && shadowColorSource == look.shadowColorSource
            && shadowColor.quantized.opacity == look.shadowColor.quantized.opacity
            && shadowOffsetX == look.shadowOffsetX && shadowOffsetY == look.shadowOffsetY
            && shadowBlur == look.shadowBlur
    }
}
