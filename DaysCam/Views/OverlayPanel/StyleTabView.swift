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
    /// Content-area height the panel gives this tab (`OverlayPanelView`'s
    /// `contentHeight`, 212pt in the regular layout). Pages that are shorter
    /// than this are centered vertically (TASK-49 A).
    var availableHeight: CGFloat = 212
    /// Swatch diameter for the color rows, every device (TASK-49 B; was 34).
    static let swatchDiameter: CGFloat = 30
    /// Both color rows share this many columns (TASK-39 B).
    static let colorColumnCount = 9
    /// Height of a color row and diameter of the selection ring: the ring is
    /// drawn 4pt outside the swatch (#155), so the row is as tall as the ring.
    static let swatchCellHeight: CGFloat = swatchDiameter + 8

    /// Gap between neighboring columns when the nine columns fill
    /// `contentWidth` edge to edge (`space-between`). Never negative.
    static func columnSpacing(forContentWidth contentWidth: CGFloat) -> CGFloat {
        max(0, (contentWidth - CGFloat(colorColumnCount) * swatchDiameter) / CGFloat(colorColumnCount - 1))
    }

    /// Center x of each of the nine columns, shared by both color rows so the
    /// second row's n-th swatch sits right under the first row's n-th.
    static func columnCenters(forContentWidth contentWidth: CGFloat) -> [CGFloat] {
        let pitch = swatchDiameter + columnSpacing(forContentWidth: contentWidth)
        return (0..<colorColumnCount).map { swatchDiameter / 2 + CGFloat($0) * pitch }
    }

    /// Left/right inset of a page's scroll content (TASK-84): 14 puts sliders
    /// and swatches 16pt from the panel edge. The font list keeps 10 because
    /// its rows carry their own inset (#309).
    static func contentHorizontalInset(for subTab: StyleTabModel.SubTab) -> CGFloat {
        subTab == .font ? 10 : 14
    }

    /// Top inset of the whole tab (`.tabbody` padding).
    static let tabTopInset: CGFloat = 4
    /// Height of the pinned sub-tab row: 6 + 36 + 4.
    static let subTabRowHeight: CGFloat = 46
    /// Space kept under a vertically centered page (TASK-49 A).
    static let centeredBottomInset: CGFloat = 10

    /// Minimum height of a centered page so that it fills what is left of
    /// `availableHeight` below the sub-tab row and above the bottom inset.
    static func centeredContentMinHeight(availableHeight: CGFloat) -> CGFloat {
        max(0, availableHeight - tabTopInset - subTabRowHeight - centeredBottomInset)
    }

    var body: some View {
        // The sub-tab row is fixed above the tab's own `ScrollView` (TASK-66):
        // it used to be a pinned `LazyVStack` header inside the panel's outer
        // scroll view, which let the row drift with the 4pt top inset, left
        // a gap under it for the edge fade, and could push it out of view
        // when a shorter page kept the old scroll offset.
        //
        // No gap of its own between `subTabRow` and `content` (#106): the
        // design's `.subA{padding:6px 4px 4px}` + `.pane{...}` (no margin)
        // puts the whole visual gap inside `subTabRow`'s own bottom padding
        // instead — see that view's `.padding(.top:.bottom:)`.
        //
        // This tab's own `.tabbody` outer inset (`D3-style-tab.html`'s
        // style-tab-specific override, `.tabbody{padding:4px 10px 6px}` —
        // #106 R2) is split between the row (top, sides) and the scroll
        // content (sides, bottom).
        VStack(alignment: .leading, spacing: 0) {
            subTabRow
                .padding(.top, Self.tabTopInset)
                .padding(.horizontal, 10)
                // The font list's messages sit over the fixed row, so they
                // never cover the cells being tapped.
                .overlay(alignment: .center) {
                    FontToastView(model: model.fontList)
                }
            ScrollView {
                Group {
                    if model.selectedSubTab.isCentered {
                        // Short pages sit in the middle of the space below
                        // the sub-tab row; taller content just grows and
                        // scrolls.
                        content
                            .frame(maxWidth: .infinity,
                                   minHeight: Self.centeredContentMinHeight(availableHeight: availableHeight),
                                   alignment: .center)
                    } else {
                        content
                    }
                }
                .padding(.horizontal, Self.contentHorizontalInset(for: model.selectedSubTab))
                .padding(.bottom, model.selectedSubTab.isCentered ? Self.centeredBottomInset : 6)
            }
            // Fades at the scroll edges and one indicator flash per sub-tab
            // (TASK-58b); the row is outside the scroll view, so no top inset.
            .scrollEdgeHint(flashTrigger: model.selectedSubTab)
            // A new identity per sub-tab starts every page at the top, with
            // no animated clamp of the old offset (TASK-66).
            .id(model.selectedSubTab)
        }
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
        // own tap target is 52×36 (TASK-57, enlarged from the design's 44×30).
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
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 28, height: 28)
                        .foregroundColor(model.selectedSubTab == subTab ? CameraTheme.active : CameraTheme.inkTertiary)
                        .frame(width: 52, height: 36)
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
            Image(systemName: "t.square").accessibilityHidden(true)
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
            Image(systemName: "character.square.fill").accessibilityHidden(true)
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
        case .font: fontContent
        case .color: colorContent
        case .outline: outlineContent
        case .shadow: shadowContent
        case .size: sizeSlider
        }
    }

    // MARK: - 字型 (PRD 0.3 FR-16, TASK-56)

    /// The whole font list, scrolling with the panel; the pinned sub-tab row
    /// stays on top.
    private var fontContent: some View {
        FontListView(model: model.fontList)
    }

    // MARK: - 顏色 (FR-10.4, FR-10.7)

    private var colorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            opacitySlider(label: "文字不透明度",
                          percent: model.textOpacityPercent,
                          isDisabled: false,
                          onChange: { model.setTextOpacityPercent($0) })
            textColorPalette
        }
    }

    private var textColorPalette: some View {
        colorPalette(current: model.profile.style.textColor,
                    swatches: model.textColorSwatches,
                    showAutoButton: false,
                    isDisabled: false,
                    onSelectSwatch: { model.selectTextColor($0) },
                    onApplyCustom: { model.applyCustomTextColor($0) },
                    onCommitCustom: { model.commitCustomColor($0) })
    }

    // MARK: - 外框、外框顏色 (FR-10.5, FR-10.6, FR-10.10)

    private var outlineContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Transparent boxes, left-aligned on the swatch's left edge
            // (TASK-49 C); no horizontal scrolling.
            optionRow {
                ForEach(model.outlineOptions, id: \.self) { outline in
                    let previewStyle: OverlayStyle = {
                        var style = model.profile.style
                        style.outline = outline
                        style.applyShadowPreset(.none)
                        // The option icons keep a fixed look whatever the
                        // sliders are set to (TASK-70).
                        style.strokeWidth = OverlayStyle.defaultStrokeWidth
                        style.boxPadding = OverlayStyle.defaultBoxPadding
                        return style
                    }()
                    let isSelected = model.profile.style.outline == outline
                    Button {
                        model.selectOutline(outline)
                    } label: {
                        optionCell(isNone: outline == .none, previewStyle: previewStyle,
                                   isSelected: isSelected, side: Self.optionSide)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(outlineName(outline))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            outlineParameterSlider
            opacitySlider(label: "外框不透明度",
                          percent: model.outlineOpacityPercent,
                          isDisabled: model.isOutlineColorSectionDisabled,
                          onChange: { model.setOutlineOpacityPercent($0) })
            colorPalette(current: model.profile.style.outlineColor,
                        swatches: model.outlineColorSwatches,
                        showAutoButton: true,
                        isDisabled: model.isOutlineColorSectionDisabled,
                        onSelectSwatch: { model.selectOutlineColor($0) },
                        onSelectAuto: { model.selectOutlineColor(nil) },
                        onApplyCustom: { model.applyCustomOutlineColor($0) },
                        onCommitCustom: { model.commitCustomColor($0) })
        }
    }

    /// The slider of the chosen outline (TASK-70): 粗細 for 描邊, 留白 for
    /// 底框, nothing for 無, both marked by the "distance" icon. Same row
    /// layout and spacing as `opacitySlider`.
    @ViewBuilder
    private var outlineParameterSlider: some View {
        switch model.profile.style.outline {
        case .none:
            EmptyView()
        case .stroke:
            parameterSlider(iconName: "arrow.left.and.right", accessibilityName: "描邊粗細",
                            identifier: "outlineStrokeWidthSlider",
                            value: model.profile.style.strokeWidth,
                            range: OverlayStyle.strokeWidthRange,
                            step: StyleTabModel.strokeWidthStep,
                            onChange: { model.setStrokeWidth($0) })
        case .box, .squareBox:
            parameterSlider(iconName: "arrow.left.and.right", accessibilityName: "底框留白",
                            identifier: "outlineBoxPaddingSlider",
                            value: model.profile.style.boxPadding,
                            range: OverlayStyle.boxPaddingRange,
                            step: StyleTabModel.boxPaddingStep,
                            onChange: { model.setBoxPadding($0) })
        }
    }

    private func parameterSlider(label: String? = nil, iconName: String? = nil,
                                 accessibilityName: String, identifier: String, value: Double,
                                 range: ClosedRange<Double>, step: Double,
                                 isDisabled: Bool = false,
                                 onChange: @escaping (Double) -> Void) -> some View {
        let valueText = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return HStack(spacing: 10) {
            // The row's mark sits where the opacity row has its 24pt chip, so
            // every slider starts at the same x: an icon, or a short text
            // label whose characters may spill into the gap.
            Group {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(CameraTheme.ink)
                } else if let label {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(CameraTheme.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: 24, height: 24, alignment: iconName == nil ? .leading : .center)
            .accessibilityHidden(true)
            Slider(value: Binding(get: { value }, set: onChange), in: range, step: step)
                .tint(CameraTheme.accentControl)
                .accessibilityLabel(accessibilityName)
                .accessibilityValue("\(valueText) 點")
                .accessibilityIdentifier(identifier)
            Text(valueText)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundColor(CameraTheme.ink)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .opacity(isDisabled ? 0.35 : 1)
        .disabled(isDisabled)
    }

    // MARK: - 陰影 (FR-10.8, FR-10.10)

    private var shadowContent: some View {
        let style = model.profile.style
        let isDisabled = model.isShadowParametersDisabled
        return VStack(alignment: .leading, spacing: 12) {
            // Four quick presets: tapping one fills in the parameters below
            // (TASK-71); none stays selected once a parameter is changed.
            optionRow {
                ForEach(model.shadowOptions, id: \.self) { shadow in
                    // Isolates the shadow, clearing outline, mirroring
                    // `outlineContent`'s options (which isolate the outline
                    // by clearing shadow) so the two pages behave symmetrically.
                    let previewStyle: OverlayStyle = {
                        var style = model.profile.style
                        style.applyShadowPreset(shadow)
                        style.outline = .none
                        return style
                    }()
                    let isSelected = style.shadowPreset == shadow
                    Button {
                        model.selectShadow(shadow)
                    } label: {
                        optionCell(isNone: shadow == .none, previewStyle: previewStyle,
                                   isSelected: isSelected, side: Self.optionSide)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(shadowName(shadow))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            colorPalette(current: style.shadowColorSource == .textColor ? nil : style.shadowColor,
                        swatches: model.outlineColorSwatches,
                        showAutoButton: true,
                        autoLabel: "跟隨文字顏色",
                        isDisabled: isDisabled,
                        onSelectSwatch: { model.selectShadowColor($0) },
                        onSelectAuto: { model.selectShadowColor(nil) },
                        onApplyCustom: { model.applyCustomShadowColor($0) },
                        onCommitCustom: { model.commitCustomColor($0) })
            opacitySlider(label: "陰影不透明度",
                          percent: model.shadowOpacityPercent,
                          isDisabled: isDisabled,
                          onChange: { model.setShadowOpacityPercent($0) })
            parameterSlider(iconName: "arrow.left.and.right", accessibilityName: "X 偏移", identifier: "shadowOffsetXSlider",
                            value: style.shadowOffsetX, range: OverlayStyle.shadowOffsetRange,
                            step: StyleTabModel.shadowStep, isDisabled: isDisabled,
                            onChange: { model.setShadowOffsetX($0) })
            parameterSlider(iconName: "arrow.up.and.down", accessibilityName: "Y 偏移", identifier: "shadowOffsetYSlider",
                            value: style.shadowOffsetY, range: OverlayStyle.shadowOffsetRange,
                            step: StyleTabModel.shadowStep, isDisabled: isDisabled,
                            onChange: { model.setShadowOffsetY($0) })
            parameterSlider(iconName: "drop.halffull", accessibilityName: "模糊", identifier: "shadowBlurSlider",
                            value: style.shadowBlur, range: OverlayStyle.shadowBlurRange,
                            step: StyleTabModel.shadowStep, isDisabled: isDisabled,
                            onChange: { model.setShadowBlur($0) })
        }
    }

    // MARK: - 字級 (FR-10.9)

    private var sizeSlider: some View {
        // Three lines, `spacing` 12 (TASK-49 E): the live percentage, the
        // slider row, a hint. Double-tapping the percentage or the slider row
        // resets to the default size.
        VStack(spacing: 12) {
            Text("\(model.profile.style.sizeScale)%")
                .font(.system(size: 28, weight: .bold).monospacedDigit())
                .foregroundColor(CameraTheme.ink)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.resetSizeScale() }
                .accessibilityLabel("字級 \(model.profile.style.sizeScale)%")
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
                .tint(CameraTheme.accentControl)
                .accessibilityLabel("字級")
                .accessibilityAction(named: "回到預設大小") { model.resetSizeScale() }
                Text("A").font(.system(size: 24, weight: .semibold)).foregroundColor(CameraTheme.inkSecondary).accessibilityHidden(true)
            }
            // Simultaneous, so the slider's own drag still works.
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetSizeScale() })
            Text("拖曳調整，點兩下回到預設大小")
                .font(.system(size: 12))
                .foregroundColor(CameraTheme.inkSecondary)
                .frame(maxWidth: .infinity)
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
                              autoLabel: String = "自動（黑或白）",
                              isDisabled: Bool,
                              onSelectSwatch: @escaping (OverlayColor) -> Void,
                              onSelectAuto: @escaping () -> Void = {},
                              onApplyCustom: @escaping (OverlayColor) -> Void,
                              onCommitCustom: @escaping (OverlayColor) -> Void) -> some View {
        // `.pal{gap:6px}` between the two rows (#106).
        VStack(alignment: .leading, spacing: 6) {
            // First row: nine swatches filling the content width, equal gaps.
            paletteRow {
                ForEach(swatches, id: \.hexString) { swatch in
                    colorDot(swatch, isSelected: isSame(current, swatch)) { onSelectSwatch(swatch) }
                }
            }
            // Second row: (auto,) rainbow, then recent custom colors, each in
            // the same column as the first row's swatch above it, left-aligned.
            paletteRow {
                if showAutoButton {
                    autoColorButton(current: current, label: autoLabel, onSelectAuto: onSelectAuto)
                }
                // The rainbow swatch is "selected" when `current` is a custom
                // color that does not match any preset or recent swatch —
                // those already show their own ring, so this only fires for
                // an actually custom color (R.3).
                let isCustomSelected = current != nil
                    && !swatches.contains { isSame(current, $0) }
                    && !model.recentColors.contains { isSame(current, $0) }
                customColorPicker(current: current, isSelected: isCustomSelected,
                                  onApply: onApplyCustom, onCommit: onCommitCustom)
                ForEach(model.recentColors, id: \.hexString) { color in
                    colorDot(color, isSelected: isSame(current, color), labelPrefix: "最近自訂 ") {
                        onSelectSwatch(color)
                    }
                }
            }
        }
        .opacity(isDisabled ? 0.35 : 1)
        .disabled(isDisabled)
    }

    /// One color row: items laid out on the shared nine-column grid.
    private func paletteRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let built = content()
        return GeometryReader { proxy in
            HStack(spacing: Self.columnSpacing(forContentWidth: proxy.size.width)) {
                built
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: Self.swatchCellHeight)
    }

    /// The 外框顏色 "auto" button: one grid column wide like every swatch.
    func autoColorButton(current: OverlayColor?, label: String = "自動（黑或白）",
                         onSelectAuto: @escaping () -> Void) -> some View {
        Button {
            onSelectAuto()
        } label: {
            // Left half gray (the preview "A" color), right half white (TASK-49,
            // human's follow-up). Drawn, not a symbol, so no system tint.
            ZStack {
                Circle().fill(Color.white)
                Circle().trim(from: 0.25, to: 0.75).fill(swiftUIColor(StyleSwatchPreview.textColor))
            }
            .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
            .overlay(swatchEdge)
            .overlay(swatchSelectionRing(current == nil))
            .frame(width: Self.swatchDiameter, height: Self.swatchCellHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(current == nil ? .isSelected : [])
    }

    func colorDot(_ color: OverlayColor, isSelected: Bool,
                          labelPrefix: String = "",
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(swiftUIColor(color))
                // Only a translucent color needs the checkerboard; under an
                // opaque swatch it showed through the disabled (dimmed)
                // palette of outline 無 (#310 QA, TASK-70).
                .background {
                    if color.opacity < 1 { CheckerboardView().clipShape(Circle()) }
                }
                .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
                .overlay(swatchEdge)
                .overlay(swatchSelectionRing(isSelected))
                .frame(width: Self.swatchDiameter, height: Self.swatchCellHeight)
        }
        .accessibilityLabel(labelPrefix + color.hexString)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Rainbow hues for the custom-color swatch, in standard hue-wheel order
    /// (issue #83: assumed absent a design-specified order).
    private static let rainbowHues: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 6.0)
        .map { Color(hue: $0, saturation: 1, brightness: 1) }

    /// Custom-color entry point: a solid rainbow circle, same diameter as the
    /// other swatches (issue #83). Tapping it presents the system color picker
    /// (`UIColorPickerViewController`, with alpha). Dragging calls `onApply`
    /// continuously for the live preview; `onCommit` runs once when the picker
    /// closes, and only if the final color differs from the one it opened
    /// with, so the recent list gets one entry per pick (TASK-53).
    func customColorPicker(current: OverlayColor?,
                           isSelected: Bool,
                           onApply: @escaping (OverlayColor) -> Void,
                           onCommit: @escaping (OverlayColor) -> Void) -> some View {
        CustomColorPickerButton(current: current ?? .white, onApply: onApply, onCommit: onCommit) {
            Circle()
                .fill(AngularGradient(colors: Self.rainbowHues, center: .center))
                .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
                .overlay(swatchEdge)
                .overlay(swatchSelectionRing(isSelected))
        }
        .frame(width: Self.swatchDiameter, height: Self.swatchCellHeight)
    }

    /// Whether `color` is `swatch` ignoring opacity (a swatch stays selected
    /// at any opacity, TASK-69).
    private func isSame(_ color: OverlayColor?, _ swatch: OverlayColor) -> Bool {
        guard let color else { return false }
        return StyleTabModel.hasSameRGB(color, swatch)
    }

    /// The opacity row of the color, outline and shadow pages (TASK-69, TASK-83):
    /// a fixed legend (transparent checkerboard half, solid half), the slider,
    /// and the percentage. The legend does not follow the selected color.
    private func opacitySlider(label: String, percent: Int,
                               isDisabled: Bool, onChange: @escaping (Int) -> Void) -> some View {
        let range = StyleTabModel.opacityPercentRange
        return HStack(spacing: 10) {
            opacityLegend
            Slider(
                value: Binding(get: { Double(percent) }, set: { onChange(Int($0.rounded())) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(CameraTheme.accentControl)
            .accessibilityLabel(label)
            .accessibilityValue("\(percent)%")
            Text("\(percent)%")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundColor(CameraTheme.ink)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .opacity(isDisabled ? 0.35 : 1)
        .disabled(isDisabled)
    }

    /// Fixed opacity legend of the three opacity rows (TASK-83): a plain gray
    /// and white checkerboard circle in the same 24pt column as the other
    /// slider icons, so it never follows the selected color.
    private var opacityLegend: some View {
        CheckerboardView()
            .frame(width: 24, height: 24)
            .clipShape(Circle())
            .overlay(swatchEdge)
            .accessibilityHidden(true)
    }

    /// Shared option-row metrics for the outline and shadow pages (TASK-87):
    /// 48pt boxes, 8pt apart, 4pt above the row.
    static let optionSide: CGFloat = 48
    static let optionSpacing: CGFloat = 8
    static let optionRowTopPadding: CGFloat = 4

    /// The option row both pages share, left-aligned on the swatch edge.
    private func optionRow<Options: View>(@ViewBuilder _ options: () -> Options) -> some View {
        HStack(spacing: Self.optionSpacing) { options() }
            .padding(.top, Self.optionRowTopPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The 1pt inner edge of every swatch (`ink` at 16%), so light colors
    /// stay visible on the panel background (TASK-49 B).
    private var swatchEdge: some View {
        Circle().strokeBorder(CameraTheme.ink.opacity(0.16), lineWidth: 1)
    }

    /// Selection frame of the outline/shadow options: a 2pt `active` rounded
    /// frame (corner 12) inside the box; unselected boxes have no frame or
    /// fill at all (TASK-49 C).
    private func optionSelectionFrame(_ isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(CameraTheme.active, lineWidth: isSelected ? 2 : 0)
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

    // MARK: - 共用：外框／陰影的 "A" 預覽

    /// Draws a single "A" in the fixed preview look (`StyleSwatchPreview`:
    /// gray text in SF Rounded Semibold, gray outline/box/shadow, never the
    /// current font) with the outline/shadow being previewed, layering outline
    /// then shadow (FR-10.5, FR-10.8). Strokes are real glyph outlines (#155).
    /// The glyph is about half the box side.
    private func stylePreviewSwatch(_ style: OverlayStyle, side: CGFloat) -> some View {
        let fixedStyle = StyleSwatchPreview.fixedStyle(from: style)
        let fontSize = (side * 0.52).rounded()
        let scale = OverlayMetrics.decorationScale(forFontSize: fontSize)
        let font = StyleSwatchPreview.previewFont(ofSize: fontSize)
        let textSize = ("A" as NSString).size(withAttributes: [.font: font])
        var layered = AnyView(Text("A")
            .font(Font(font))
            .foregroundColor(swiftUIColor(fixedStyle.textColor)))

        for decoration in StyleSwatchPreview.decorations(for: fixedStyle) {
            switch decoration {
            case let .stroke(color, width):
                // Half the viewfinder's width; the image includes the fill,
                // so it replaces the plain text rather than being layered.
                let image = StyleSwatchPreview.strokedText("A",
                                                           font: font,
                                                           fill: fixedStyle.textColor,
                                                           stroke: color,
                                                           strokeWidth: CGFloat(width) * scale * 0.5)
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

        return layered.frame(width: side, height: side)
    }

    /// An outline/shadow option: a transparent `side`-square box holding its
    /// preview, or the `nosign` icon for 無, with the selection frame inside
    /// the box (TASK-49 C). The name is the accessibility label only.
    @ViewBuilder
    private func optionCell(isNone: Bool, previewStyle: OverlayStyle,
                            isSelected: Bool, side: CGFloat) -> some View {
        Group {
            if isNone {
                Image(systemName: "nosign")
                    .font(.system(size: 24))
                    .foregroundColor(CameraTheme.inkSecondary)
                    .frame(width: side, height: side)
            } else {
                stylePreviewSwatch(previewStyle, side: side)
            }
        }
        .overlay(optionSelectionFrame(isSelected))
        .contentShape(Rectangle())
    }

    private func outlineName(_ outline: OverlayOutline) -> String {
        switch outline {
        case .none: return "無外框"
        case .stroke: return "描邊"
        case .box: return "底框"
        case .squareBox: return "直角底框"
        }
    }

    private func shadowName(_ shadow: OverlayShadowPreset) -> String {
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

extension StyleTabModel.SubTab {
    /// Short pages (color, size) are centered vertically; the outline, shadow
    /// and font pages start from the top (TASK-49 A; the shadow page grew
    /// parameter rows in TASK-71).
    var isCentered: Bool {
        switch self {
        case .color, .size: return true
        case .font, .outline, .shadow: return false
        }
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
        self.init(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
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
private func previewModel(style: OverlayStyle = OverlayStyle(),
                          fontStates: [OverlayFontID: FontState] = [:]) -> StyleTabModel {
    let suiteName = "StyleTabView.Preview.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    let store = RecentColorsStore(defaults: defaults)
    store.add(OverlayColor(red8: 0x7A, green8: 0x4E, blue8: 0x9C))
    store.add(OverlayColor(red8: 0x2E, green8: 0x8B, blue8: 0x57))
    return StyleTabModel(profile: previewProfile(style: style),
                         recentColorsStore: store,
                         fontLibrary: StaticFontLibrary(states: fontStates),
                         applyFont: { _, _ in },
                         allProfiles: { [] }) { _ in }
}

#Preview("字型格子 · 只有蘋方 (375pt)") {
    let model = previewModel()
    model.selectedSubTab = .font
    return StyleTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("字型格子 · 已下載 3 套 (375pt)") {
    let model = previewModel(style: OverlayStyle(fontID: .huninn),
                             fontStates: [.huninn: .available, .notoSerifTC: .available, .iansui: .available])
    model.selectedSubTab = .font
    return StyleTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("字型格子 · 目前字型需重新下載 (375pt)") {
    let model = previewModel(style: OverlayStyle(fontID: .xingkai),
                             fontStates: [.huninn: .available, .xingkai: .notDownloaded])
    model.selectedSubTab = .font
    return StyleTabView(model: model)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("字型格子 · 目前字型下載中 38% / 準備中 (375pt)") {
    let downloading = previewModel(style: OverlayStyle(fontID: .xingkai),
                                   fontStates: [.xingkai: .downloading(progress: 0.38)])
    let preparing = previewModel(style: OverlayStyle(fontID: .songti),
                                 fontStates: [.songti: .preparing])
    downloading.selectedSubTab = .font
    preparing.selectedSubTab = .font
    return VStack {
        StyleTabView(model: downloading)
        StyleTabView(model: preparing)
    }
    .frame(width: 375)
    .padding(.vertical, 12)
    .background(Color(.systemBackground))
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
    style.outline = .box
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

#Preview("外框 · 內容區 120pt，捲到底，色票選定圈要完整 (375pt)") {
    var style = OverlayStyle()
    style.outline = .stroke
    let model = previewModel(style: style)
    model.selectedSubTab = .outline
    return ScrollView {
        StyleTabView(model: model)
    }
    .frame(width: 375, height: 120)
    .background(CameraTheme.background)
    .defaultScrollAnchor(.bottom)
}

#Preview("外框 · 內容區 160pt (375pt)") {
    var style = OverlayStyle()
    style.outline = .stroke
    let model = previewModel(style: style)
    model.selectedSubTab = .outline
    return ScrollView {
        StyleTabView(model: model)
    }
    .frame(width: 375, height: 160)
    .background(CameraTheme.background)
    .defaultScrollAnchor(.bottom)
}

#Preview("顏色 · 內容區 120pt (375pt)") {
    let model = previewModel()
    model.selectedSubTab = .color
    return ScrollView {
        StyleTabView(model: model)
    }
    .frame(width: 375, height: 120)
    .background(CameraTheme.background)
    .defaultScrollAnchor(.bottom)
}

/// Button that presents `UIColorPickerViewController` and reports live
/// selections (`onApply`) separately from the single close-time result
/// (`onCommit`, only when the color changed since opening).
private struct CustomColorPickerButton<Label: View>: View {
    let current: OverlayColor
    let onApply: (OverlayColor) -> Void
    let onCommit: (OverlayColor) -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: { label() }
            .buttonStyle(.plain)
            .accessibilityLabel("自訂顏色")
            .background(
                ColorPickerPresenter(isPresented: $isPresented, initial: current,
                                     onApply: onApply, onCommit: onCommit)
                    .frame(width: 0, height: 0)
            )
    }
}

/// Hosts the modal presentation of a `UIColorPickerViewController`.
private struct ColorPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let initial: OverlayColor
    let onApply: (OverlayColor) -> Void
    let onCommit: (OverlayColor) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = true
        picker.selectedColor = UIColor(red: initial.red, green: initial.green,
                                       blue: initial.blue, alpha: initial.opacity)
        picker.delegate = coordinator
        coordinator.startColor = initial
        coordinator.latestColor = initial
        host.present(picker, animated: true)
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: ColorPickerPresenter?
        var startColor: OverlayColor?
        var latestColor: OverlayColor?

        func colorPickerViewController(_ viewController: UIColorPickerViewController,
                                       didSelect color: UIColor, continuously: Bool) {
            guard let picked = OverlayColor(Color(uiColor: color)) else { return }
            latestColor = picked
            parent?.onApply(picked)
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            if let final = latestColor, final != startColor {
                parent?.onCommit(final)
            }
            parent?.isPresented = false
        }
    }
}

/// A light gray checkerboard, drawn behind translucent colors so their
/// opacity can be seen (TASK-69). Fills whatever frame it is given.
private struct CheckerboardView: View {
    private let cell: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let columns = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color(white: 0.78)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
