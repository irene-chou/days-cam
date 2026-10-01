import SwiftUI
import UIKit

/// The 樣式 (style) tab of the overlay panel (PRD 0.2 FR-10, D-3).
///
/// Stands alone on purpose: the panel shell, its first-layer segmented
/// control (樣式｜格式｜位置｜天數規則) and the container that hosts this view
/// are `ui-shell`'s (TASK-22), which had not landed when this was written.
/// Once it does, `ui-shell` drops this view into the panel body for the
/// 樣式 segment, passing in a `StyleTabModel` built from the active profile.
///
/// The second layer here (font/color/outline/shadow/size) is five icon-only
/// buttons with no visible labels (FR-10.1) — every name lives in
/// `.accessibilityLabel` only.
struct StyleTabView: View {
    @ObservedObject var model: StyleTabModel

    /// Swatch diameter for the color rows (`.prow .dot{width:28px}`, #106 —
    /// was 26). The longest row (outline color: auto + nine swatches +
    /// rainbow = eleven items) must still fit inside a 375pt-wide screen
    /// without horizontal scrolling (FR-10.4, acceptance 23.12): at 28pt
    /// with zero gap that is already only 11*28 = 308pt, inside a 343pt
    /// content width (375 - 16*2) — the row's `space-between` layout
    /// (`colorPalette` below) only ever turns that slack into gaps, never
    /// overflow, so 23.12 holds regardless of how many swatches a given row
    /// has.
    private static let swatchDiameter: CGFloat = 28
    /// Height of a swatch's cell and diameter of its selection ring (#155).
    /// The ring used to be an overlay poking 4pt out of the 28pt swatch on
    /// every side, which the pinned sub-tab row and the panel's edge cut
    /// off. The cell is as tall as the ring so the ring lies inside it
    /// vertically; horizontally the cell keeps the swatch's 28pt pitch
    /// (eleven 36pt cells would not fit the 355pt content width, acceptance
    /// 23.12), so the ring may extend into the neighboring gap / the
    /// content padding, which nothing clips.
    private static let swatchCellHeight: CGFloat = 36
    /// Gap between items in the "recent" row, the one row that stays
    /// left-aligned with a fixed gap rather than `space-between`
    /// (`.prow:last-child{justify-content:flex-start;gap:10px}`, #106 — was
    /// 5, shared with the first row before this).
    private static let recentRowSpacing: CGFloat = 10

    var body: some View {
        // No gap of its own between `subTabRow` and `content` (#106): the
        // design's `.subA{padding:6px 4px 4px}` + `.pane{...}` (no margin)
        // puts the whole visual gap inside `subTabRow`'s own bottom padding
        // instead — see that view's `.padding(.top:.bottom:)`.
        //
        // `subTabRow` is a pinned section header (#129): this view sits
        // inside the panel's own vertical `ScrollView`, and a `LazyVStack`
        // with `pinnedViews` pins against that enclosing scroll view, so the
        // icon row stays on top while the (taller) font grid scrolls under
        // it. The header's opaque panel-colored background hides content
        // passing beneath it.
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                content
            } header: {
                subTabRow
                    .background(CameraTheme.background)
            }
        }
        // This tab's own `.tabbody` outer inset (`D3-style-tab.html`'s
        // style-tab-specific override, `.tabbody{padding:4px 10px 6px}` —
        // #106 R2, the human's 2026-09-27 call: each tab owns its own
        // `.tabbody` padding rather than a generic one shared by all four
        // — `ui-shell` is dropping the panel container's own generic inset
        // in #105 to avoid stacking both). Was a flat `.padding(.horizontal,
        // 16)` with no vertical inset at all.
        .padding(.top, 4)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .alert("無法儲存", isPresented: Binding(get: { model.lastError != nil },
                                             set: { if !$0 { model.lastError = nil } })) {
            Button("好") { model.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
    }

    // MARK: - 第二層：五個純圖示 (FR-10.1)

    private var subTabRow: some View {
        // Evenly spread across the full row width, `space-around` exactly
        // (`D3-style-tab.html`'s final `.subA{justify-content:space-around;
        // gap:0}` override for the icon-only "第 11 版" sub-tabs, #106 R3):
        // CSS `space-around` gives each item half a gap-worth of space on
        // its own edge and a full gap-worth between adjacent items — two
        // consecutive plain `Spacer`s occupy exactly double the width of a
        // lone one (`HStack` gives every flexible child an equal share of
        // the leftover space, so N spacer instances together always claim N
        // times what one does), which is exactly that 2:1 ratio; a single
        // `Spacer` at each end supplies the half-width edge gap. Each icon's
        // own tap target is 44×30 (`.subA .stab{width:44px;height:30px}`).
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Array(StyleTabModel.SubTab.allCases.enumerated()), id: \.offset) { index, subTab in
                if index > 0 {
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                }
                Button {
                    model.selectedSubTab = subTab
                } label: {
                    subTabIcon(subTab)
                        .frame(width: 24, height: 24)
                        .foregroundColor(model.selectedSubTab == subTab ? CameraTheme.active : CameraTheme.inkTertiary)
                        .frame(width: 44, height: 30)
                }
                .accessibilityLabel(subTab.accessibilityLabel)
                .accessibilityAddTraits(model.selectedSubTab == subTab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        // `.subA{padding:6px 4px 4px}` — the 4px horizontal half is folded
        // into the body's own `.tabbody` padding already.
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func subTabIcon(_ subTab: StyleTabModel.SubTab) -> some View {
        switch subTab {
        case .font:
            // Final icon set per FR-10.1 / PRD §1 icon rules: SF Symbol
            // names are the spec, not the mockup's hand-drawn SVG
            // approximations (design decision, #71).
            Image(systemName: "textformat").accessibilityHidden(true)
        case .color:
            // Two-layer palette icon (design decision, #71): the inner
            // circle previews the current text color live, the outer ring
            // follows the same selected/unselected rule as the other four
            // icons. `symbolRenderingMode(.palette)`'s `foregroundStyle`
            // colors are ordered inner-then-outer for this symbol — verified
            // by rendering it, not assumed from AppKit's palette ordering.
            Image(systemName: "circle.inset.filled")
                .symbolRenderingMode(.palette)
                .foregroundStyle(swiftUIColor(model.profile.style.textColor),
                                model.selectedSubTab == subTab ? CameraTheme.active : CameraTheme.inkTertiary)
                .accessibilityHidden(true)
        case .outline:
            Image(systemName: "square.dashed").accessibilityHidden(true)
        case .shadow:
            Image(systemName: "shadow").accessibilityHidden(true)
        case .size:
            Image(systemName: "textformat.size").accessibilityHidden(true)
        }
    }

    // MARK: - 內容 (依第二層選擇)

    @ViewBuilder
    private var content: some View {
        switch model.selectedSubTab {
        case .font: fontRow
        case .color: colorContent
        case .outline: outlineContent
        case .shadow: shadowContent
        case .size: sizeSlider
        }
    }

    // MARK: - 字型 (FR-10.2, FR-10.3)

    /// Height of one font cell; the whole cell is the tap target (#129).
    static let fontCellHeight: CGFloat = 44
    /// Font name size inside a cell (#129 — was 17 in the old chip row).
    static let fontCellTextSize: CGFloat = 15

    /// Three equal-width columns, rows in `fontOptions` order, the last row
    /// left-aligned. Scrolls vertically with the panel instead of
    /// horizontally (#129).
    private var fontRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                  alignment: .leading,
                  spacing: 8) {
            ForEach(model.fontOptions, id: \.self) { fontID in
                let isSelected = model.profile.style.fontID == fontID
                Button {
                    model.selectFont(fontID)
                } label: {
                    Text(fontID.displayName)
                        .font(Font(OverlayMetrics.font(for: fontID, size: Self.fontCellTextSize)))
                        .foregroundColor(CameraTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.fontCellHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(CameraTheme.active, lineWidth: isSelected ? 1.5 : 0)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 顏色 (FR-10.4, FR-10.7)

    private var colorContent: some View {
        colorPalette(current: model.profile.style.textColor,
                    swatches: model.textColorSwatches,
                    showAutoButton: false,
                    isDisabled: false,
                    onSelectSwatch: { model.selectTextColor($0) },
                    onPickCustom: { model.pickCustomTextColor($0) })
    }

    // MARK: - 外框、外框顏色 (FR-10.5, FR-10.6, FR-10.10)

    private var outlineContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                // `.hs{gap:6px}` (#106) — was 14.
                HStack(spacing: 6) {
                    ForEach(model.outlineOptions, id: \.self) { outline in
                        let previewStyle: OverlayStyle = {
                            var style = model.profile.style
                            style.outline = outline
                            style.shadow = .none
                            return style
                        }()
                        let isSelected = model.profile.style.outline == outline
                        Button {
                            model.selectOutline(outline)
                        } label: {
                            optionCell(isNone: outline == .none, previewStyle: previewStyle, isSelected: isSelected)
                        }
                        .accessibilityLabel(outlineName(outline))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            colorPalette(current: model.profile.style.outlineColor,
                        swatches: model.outlineColorSwatches,
                        showAutoButton: true,
                        isDisabled: model.isOutlineColorSectionDisabled,
                        onSelectSwatch: { model.selectOutlineColor($0) },
                        onSelectAuto: { model.selectOutlineColor(nil) },
                        onPickCustom: { model.pickCustomOutlineColor($0) })
        }
    }

    // MARK: - 陰影 (FR-10.8, FR-10.10)

    private var shadowContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // `.hs{gap:6px}` (#106) — was 14.
            HStack(spacing: 6) {
                ForEach(model.shadowOptions, id: \.self) { shadow in
                    // Isolates the shadow, clearing outline, mirroring
                    // `outlineContent`'s swatches (which isolate the outline
                    // by clearing shadow) so the two rows behave symmetrically.
                    let previewStyle: OverlayStyle = {
                        var style = model.profile.style
                        style.shadow = shadow
                        style.outline = .none
                        return style
                    }()
                    let isSelected = model.profile.style.shadow == shadow
                    Button {
                        model.selectShadow(shadow)
                    } label: {
                        optionCell(isNone: shadow == .none, previewStyle: previewStyle, isSelected: isSelected)
                    }
                    .accessibilityLabel(shadowName(shadow))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 字級 (FR-10.9)

    private var sizeSlider: some View {
        // `.zrow{gap:8px}` (#106) — was 12.
        HStack(spacing: 8) {
            Text("A").font(.system(size: 13, weight: .semibold)).foregroundColor(CameraTheme.inkSecondary).accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { Double(model.profile.style.sizeScale) },
                    set: { model.setSizeScale(Int($0.rounded())) }
                ),
                in: Double(StyleTabModel.sizeScaleRange.lowerBound)...Double(StyleTabModel.sizeScaleRange.upperBound),
                step: Double(StyleTabModel.sizeScaleStep)
            )
            .accessibilityLabel("字級")
            Text("A").font(.system(size: 24, weight: .semibold)).foregroundColor(CameraTheme.inkSecondary).accessibilityHidden(true)
            Text("\(model.profile.style.sizeScale)%")
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 46, alignment: .trailing)
        }
    }

    // MARK: - 共用：兩排色票 (FR-10.4, FR-10.6, FR-10.7)

    /// Renders the shared two-row color palette: a first row of swatches (plus
    /// an optional leading "automatic" button and a trailing rainbow custom
    /// picker), and a second "recent" row. Used for both text color and
    /// outline color (FR-10.4, FR-10.6) so their behavior — including sharing
    /// `RecentColorsStore` — cannot drift apart.
    private func colorPalette(current: OverlayColor?,
                              swatches: [OverlayColor],
                              showAutoButton: Bool,
                              isDisabled: Bool,
                              onSelectSwatch: @escaping (OverlayColor) -> Void,
                              onSelectAuto: @escaping () -> Void = {},
                              onPickCustom: @escaping (OverlayColor) -> Void) -> some View {
        // `.pal{gap:6px}` between the two rows (#106) — was 10.
        VStack(alignment: .leading, spacing: 6) {
            // First row fills the full content width edge-to-edge, gaps
            // sized automatically (`.prow{justify-content:space-between}`,
            // #106 — was a fixed 5pt gap): (N-1) equal flexible spacers
            // between N fixed-size swatches is `space-between`'s exact
            // SwiftUI equivalent for a known, non-scrolling item count.
            HStack(spacing: 0) {
                if showAutoButton {
                    Button {
                        onSelectAuto()
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 16))
                            .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
                            .overlay(swatchSelectionRing(current == nil))
                            .frame(width: Self.swatchDiameter, height: Self.swatchCellHeight)
                    }
                    .accessibilityLabel("自動（黑或白）")
                    .accessibilityAddTraits(current == nil ? .isSelected : [])
                    Spacer(minLength: 0)
                }
                ForEach(Array(swatches.enumerated()), id: \.element.hexString) { index, swatch in
                    if index > 0 { Spacer(minLength: 0) }
                    colorDot(swatch, isSelected: current == swatch) { onSelectSwatch(swatch) }
                }
                Spacer(minLength: 0)
                // The rainbow swatch is "selected" when `current` is a custom
                // color that does not match any preset or recent swatch —
                // those already show their own ring, so this only fires for
                // an actually custom color (R.3).
                let isCustomSelected = current != nil
                    && !swatches.contains(current!)
                    && !model.recentColors.contains(current!)
                customColorPicker(current: current, isSelected: isCustomSelected, onPickCustom: onPickCustom)
            }
            // Second ("recent") row stays left-aligned with a fixed gap
            // (`.prow:last-child{justify-content:flex-start;gap:10px}`,
            // #106) rather than `space-between` — it can have anywhere from
            // zero to seven items, so stretching it to fill the row would
            // leave huge, uneven gaps instead of a steady 10pt rhythm.
            HStack(spacing: Self.recentRowSpacing) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(CameraTheme.inkSecondary)
                    .frame(width: Self.swatchDiameter, height: Self.swatchCellHeight)
                    .accessibilityLabel("最近自訂")
                if model.recentColors.isEmpty {
                    Text("用彩虹圓自訂的顏色會出現在這裡")
                        .font(.caption)
                        .foregroundColor(CameraTheme.inkSecondary)
                } else {
                    ForEach(model.recentColors, id: \.hexString) { color in
                        colorDot(color, isSelected: current == color) { onSelectSwatch(color) }
                    }
                }
            }
        }
        .opacity(isDisabled ? 0.35 : 1)
        .disabled(isDisabled)
    }

    private func colorDot(_ color: OverlayColor, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(swiftUIColor(color))
                .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
                .overlay(swatchSelectionRing(isSelected))
                .frame(width: Self.swatchDiameter, height: Self.swatchCellHeight)
        }
        .accessibilityLabel(color.hexString)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Rainbow hues for the custom-color swatch, in standard hue-wheel order
    /// (issue #83: assumed absent a design-specified order).
    private static let rainbowHues: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 6.0)
        .map { Color(hue: $0, saturation: 1, brightness: 1) }

    /// Custom-color entry point: a solid rainbow circle, same diameter as the
    /// other swatches (issue #83) — not the system `ColorPicker`'s default
    /// ring-with-current-color-well look. The real `ColorPicker` is still
    /// there, made effectively invisible (`.opacity` low enough to read as
    /// transparent but non-zero, since SwiftUI stops forwarding taps to a
    /// fully transparent control) and stacked on top so tapping still opens
    /// the system color picker and preserves FR-10.7's "add to recent"
    /// behavior unchanged. The `ColorPicker`'s own accessibility label
    /// (its title, "自訂顏色", even with `.labelsHidden()`) is left as-is
    /// rather than combined, so VoiceOver's activation still routes to the
    /// native control exactly as before this change (R.4).
    private func customColorPicker(current: OverlayColor?,
                                   isSelected: Bool,
                                   onPickCustom: @escaping (OverlayColor) -> Void) -> some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: Self.rainbowHues, center: .center))
                .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
                .overlay(swatchSelectionRing(isSelected))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            ColorPicker("自訂顏色", selection: Binding(
                get: { swiftUIColor(current ?? .white) },
                set: { newValue in
                    if let picked = OverlayColor(newValue) {
                        onPickCustom(picked)
                    }
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .opacity(0.02)
        }
        .frame(width: Self.swatchDiameter, height: Self.swatchCellHeight)
    }

    /// Rounded-square selection frame of the outline/shadow options (corner
    /// 10, 1.5pt, like the font cells), drawn inside the cell (#155).
    private func optionSelectionFrame(_ isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(CameraTheme.active, lineWidth: isSelected ? 1.5 : 0)
    }

    /// Selection halo for the round color swatches (色票), matching the
    /// design's `.dot[aria-pressed="true"]` (`D3-tab-options.html:58`):
    /// `box-shadow: 0 0 0 2px var(--bg), 0 0 0 4px var(--act)`, i.e. a 2pt
    /// gap then a 2pt `active`-colored ring, both outside the dot's edge.
    /// The gap needs no explicit background-colored stroke of its own —
    /// leaving it unstroked already shows through to the panel behind,
    /// which is that same background.
    private func swatchSelectionRing(_ isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(CameraTheme.active, lineWidth: isSelected ? 2 : 0)
            .frame(width: Self.swatchCellHeight, height: Self.swatchCellHeight)
    }

    // MARK: - 共用：外框／陰影的 "Aa" 預覽

    /// Draws "Aa" in the fixed preview look (`StyleSwatchPreview`: dark text,
    /// gray outline/box/shadow) with `style`'s font and the outline/shadow
    /// being previewed, layering outline then shadow (FR-10.5, FR-10.8).
    /// Strokes are real glyph outlines, not offset copies (#155).
    private func stylePreviewSwatch(_ style: OverlayStyle) -> some View {
        let fixedStyle = StyleSwatchPreview.fixedStyle(from: style)
        let fontSize: CGFloat = 15
        let scale = OverlayMetrics.decorationScale(forFontSize: fontSize)
        let font = OverlayMetrics.font(for: fixedStyle.fontID, size: fontSize)
        var layered = AnyView(Text("Aa")
            .font(Font(font))
            .foregroundColor(CameraTheme.ink))

        for decoration in StyleSwatchPreview.decorations(for: fixedStyle) {
            switch decoration {
            case let .stroke(color, width):
                // Drawn at half the viewfinder's width (the preview is
                // small); the image includes the fill, so it replaces the
                // plain text rather than being layered under it.
                let image = StyleSwatchPreview.strokedText("Aa",
                                                           font: font,
                                                           fill: fixedStyle.textColor,
                                                           stroke: color,
                                                           strokeWidth: CGFloat(width) * scale * 0.5)
                let textSize = ("Aa" as NSString).size(withAttributes: [.font: font])
                layered = AnyView(Image(uiImage: image)
                    .frame(width: textSize.width, height: textSize.height))
            case let .backgroundBox(color, opacity, cornerRadius, insets):
                layered = AnyView(
                    layered
                        .padding(.horizontal, insets.horizontal * scale * 0.5)
                        .padding(.vertical, insets.vertical * scale * 0.5)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius * scale * 0.5, style: .continuous)
                                .fill(swiftUIColor(color).opacity(opacity))
                        )
                )
            case let .shadow(offset, blur, opacity, color):
                layered = AnyView(
                    layered
                        .compositingGroup()
                        .shadow(color: swiftUIColor(color).opacity(opacity),
                                radius: blur * scale * 0.6,
                                x: offset.width * scale * 0.6,
                                y: offset.height * scale * 0.6)
                )
            }
        }

        // `.och{min-width:48px;height:44px}` (#106) — was 46×36.
        return layered
            .padding(6)
            .frame(width: 48, height: 44)
    }

    /// An outline/shadow option: its preview, or the `nosign` icon for 無
    /// (#155), with the rounded-square selection frame drawn inside the cell.
    @ViewBuilder
    private func optionCell(isNone: Bool, previewStyle: OverlayStyle, isSelected: Bool) -> some View {
        Group {
            if isNone {
                Image(systemName: "nosign")
                    .font(.system(size: 20))
                    .foregroundColor(CameraTheme.inkSecondary)
                    .frame(width: 48, height: 44)
            } else {
                stylePreviewSwatch(previewStyle)
            }
        }
        .overlay(optionSelectionFrame(isSelected))
        .contentShape(Rectangle())
    }

    private func outlineName(_ outline: OverlayOutline) -> String {
        switch outline {
        case .none: return "無外框"
        case .thinStroke: return "細描邊"
        case .thickStroke: return "粗描邊"
        case .translucentBox: return "半透明底框"
        case .solidBox: return "實心底框"
        }
    }

    private func shadowName(_ shadow: OverlayShadow) -> String {
        switch shadow {
        case .none: return "無陰影"
        case .soft: return "柔和"
        case .hard: return "硬陰影"
        case .glow: return "發光"
        }
    }

    private func swiftUIColor(_ color: OverlayColor) -> Color {
        Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.opacity)
    }
}

private extension OverlayColor {
    /// Converts a `ColorPicker`-returned SwiftUI `Color` back into an
    /// `OverlayColor`, resolved in sRGB so the stored hex matches what the
    /// user actually picked (FR-10.7). `nil` only if the color's components
    /// cannot be resolved at all, which does not happen for a picker result.
    init?(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        self.init(red: Double(red), green: Double(green), blue: Double(blue), opacity: 1.0)
    }
}

// MARK: - Preview

private func previewProfile(style: OverlayStyle = OverlayStyle()) -> CameraProfile {
    CameraProfile(name: "小寶",
                 startDate: DateComponents(year: 2026, month: 1, day: 1),
                 showDayCount: true,
                 showDate: false,
                 showName: false,
                 displayUnits: [.day],
                 useAgeWording: false,
                 position: .anchor(.bottomTrailing),
                 style: style)
}

@MainActor
private func previewModel(style: OverlayStyle = OverlayStyle()) -> StyleTabModel {
    let suiteName = "StyleTabView.Preview.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    let store = RecentColorsStore(defaults: defaults)
    store.add(OverlayColor(red8: 0x7A, green8: 0x4E, blue8: 0x9C))
    store.add(OverlayColor(red8: 0x2E, green8: 0x8B, blue8: 0x57))
    return StyleTabModel(profile: previewProfile(style: style), recentColorsStore: store) { _ in }
}

#Preview("字型 · iPhone SE 寬度 (375pt)") {
    let model = previewModel()
    model.selectedSubTab = .font
    return StyleTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("顏色 · iPhone SE 寬度 (375pt)") {
    let model = previewModel()
    model.selectedSubTab = .color
    return StyleTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("外框 · iPhone SE 寬度 (375pt)") {
    var style = OverlayStyle()
    style.outline = .translucentBox
    let model = previewModel(style: style)
    model.selectedSubTab = .outline
    return StyleTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("陰影 · iPhone SE 寬度 (375pt)") {
    let model = previewModel()
    model.selectedSubTab = .shadow
    return StyleTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("字級 · iPhone SE 寬度 (375pt)") {
    let model = previewModel()
    model.selectedSubTab = .size
    return StyleTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("字型 · 面板高度 120 可捲動，圖示列固定 (375pt)") {
    let model = previewModel()
    model.selectedSubTab = .font
    return ScrollView {
        StyleTabView(model: model)
    }
    .frame(width: 375, height: 120)
    .background(CameraTheme.background)
}
