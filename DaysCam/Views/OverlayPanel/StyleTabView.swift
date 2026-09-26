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

    /// Swatch diameter for the color rows. Eight of these plus spacing must
    /// fit inside a 375pt-wide screen without horizontal scrolling
    /// (FR-10.4, acceptance 23.12); at 28pt with 8pt spacing eight items take
    /// 8*28 + 7*8 = 280pt, well inside a 343pt content width (375 - 16*2).
    private static let swatchDiameter: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            subTabRow
            content
        }
        .padding(.horizontal, 16)
        .alert("無法儲存", isPresented: Binding(get: { model.lastError != nil },
                                             set: { if !$0 { model.lastError = nil } })) {
            Button("好") { model.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
    }

    // MARK: - 第二層：五個純圖示 (FR-10.1)

    private var subTabRow: some View {
        HStack(spacing: 30) {
            ForEach(StyleTabModel.SubTab.allCases, id: \.self) { subTab in
                Button {
                    model.selectedSubTab = subTab
                } label: {
                    subTabIcon(subTab)
                        .frame(width: 24, height: 24)
                        .foregroundColor(model.selectedSubTab == subTab ? .accentColor : .secondary)
                }
                .accessibilityLabel(subTab.accessibilityLabel)
                .accessibilityAddTraits(model.selectedSubTab == subTab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func subTabIcon(_ subTab: StyleTabModel.SubTab) -> some View {
        switch subTab {
        case .font:
            // A single "A" glyph (FR-10.1) — decorative, the accessibility
            // label above is what actually names the button.
            Text("A").font(.system(size: 18, weight: .semibold)).accessibilityHidden(true)
        case .color:
            Image(systemName: "paintpalette").accessibilityHidden(true)
        case .outline:
            Image(systemName: "square.dashed").accessibilityHidden(true)
        case .shadow:
            ShadowIcon()
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .accessibilityHidden(true)
        case .size:
            Image(systemName: "textformat.size").accessibilityHidden(true)
        }
    }

    // MARK: - 陰影圖示

    /// Hand-drawn icon for the 陰影 sub-tab: a rounded square with an
    /// L-shaped shadow line trailing off its lower-right corner. SF Symbols
    /// has no equivalent, so this traces the mockup's SVG path directly
    /// (`docs/design/D3-tab-options.html`, `docs/design/icon-options.html`;
    /// viewBox 0 0 24 24, stroke width 2, no fill):
    /// `<rect x="4" y="4" width="12" height="12" rx="3"/>`
    /// `<path d="M19 8.5V17a2 2 0 0 1-2 2H8.5" stroke-linecap="round"/>`
    private struct ShadowIcon: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = min(rect.width, rect.height) / 24
            var path = Path()

            path.addRoundedRect(
                in: CGRect(x: 4 * scale, y: 4 * scale, width: 12 * scale, height: 12 * scale),
                cornerSize: CGSize(width: 3 * scale, height: 3 * scale)
            )

            // L-shaped shadow line, traced as a vertical segment, a quarter
            // circle rounding the corner, then a horizontal segment.
            let cornerCenter = CGPoint(x: 17 * scale, y: 17 * scale)
            path.move(to: CGPoint(x: 19 * scale, y: 8.5 * scale))
            path.addLine(to: CGPoint(x: 19 * scale, y: 17 * scale))
            // `clockwise: false` here — verified against a rendered sample —
            // is what SwiftUI's `Path.addArc` needs to trace this corner in
            // the intended direction; its `clockwise` flag does not follow
            // the view's y-down screen coordinates the way one might expect.
            path.addArc(center: cornerCenter, radius: 2 * scale,
                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: 8.5 * scale, y: 19 * scale))

            return path
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

    private var fontRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(model.fontOptions, id: \.self) { fontID in
                    let isSelected = model.profile.style.fontID == fontID
                    Button {
                        model.selectFont(fontID)
                    } label: {
                        Text(fontID.displayName)
                            .font(Font(OverlayMetrics.font(for: fontID, size: 17)))
                            .foregroundColor(isSelected ? .accentColor : .primary)
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
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
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
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
                            stylePreviewSwatch(previewStyle)
                                .overlay(selectionRing(isSelected))
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
            HStack(spacing: 14) {
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
                        stylePreviewSwatch(previewStyle)
                            .overlay(selectionRing(isSelected))
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
        HStack(spacing: 12) {
            Text("A").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary).accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { Double(model.profile.style.sizeScale) },
                    set: { model.setSizeScale(Int($0.rounded())) }
                ),
                in: Double(StyleTabModel.sizeScaleRange.lowerBound)...Double(StyleTabModel.sizeScaleRange.upperBound),
                step: Double(StyleTabModel.sizeScaleStep)
            )
            .accessibilityLabel("字級")
            Text("A").font(.system(size: 24, weight: .semibold)).foregroundColor(.secondary).accessibilityHidden(true)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if showAutoButton {
                    Button {
                        onSelectAuto()
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 16))
                            .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
                            .overlay(selectionRing(current == nil))
                    }
                    .accessibilityLabel("自動（黑或白）")
                    .accessibilityAddTraits(current == nil ? .isSelected : [])
                }
                ForEach(swatches, id: \.hexString) { swatch in
                    colorDot(swatch, isSelected: current == swatch) { onSelectSwatch(swatch) }
                }
                customColorPicker(current: current, onPickCustom: onPickCustom)
            }
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
                    .accessibilityLabel("最近自訂")
                if model.recentColors.isEmpty {
                    Text("用彩虹圓自訂的顏色會出現在這裡")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                .overlay(selectionRing(isSelected))
        }
        .accessibilityLabel(color.hexString)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func customColorPicker(current: OverlayColor?,
                                   onPickCustom: @escaping (OverlayColor) -> Void) -> some View {
        ColorPicker("自訂顏色", selection: Binding(
            get: { swiftUIColor(current ?? .white) },
            set: { newValue in
                if let picked = OverlayColor(newValue) {
                    onPickCustom(picked)
                }
            }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
    }

    private func selectionRing(_ isSelected: Bool) -> some View {
        Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.85 : 0), lineWidth: 2)
    }

    // MARK: - 共用：外框／陰影的 "Aa" 預覽

    /// Draws "Aa" styled by `style`'s font, text color and (resolved) outline
    /// color, layering outline then shadow (FR-10.5, FR-10.8) — a reduced,
    /// self-contained version of `OverlayTheme`'s decoration list rendering,
    /// kept local since `OverlayTextView` belongs to `ui-shell`.
    private func stylePreviewSwatch(_ style: OverlayStyle) -> some View {
        let theme = OverlayTheme(style: style)
        let fontSize: CGFloat = 15
        let scale = OverlayMetrics.decorationScale(forFontSize: fontSize)
        let font = Font(OverlayMetrics.font(for: style.fontID, size: fontSize))
        let plain = Text("Aa").font(font)
        var layered = AnyView(plain.foregroundColor(swiftUIColor(style.textColor)))

        for decoration in theme.decorations {
            switch decoration {
            case let .stroke(color, width):
                let strokeColor = swiftUIColor(color)
                let offset = width * scale * 0.5
                let base = layered
                layered = AnyView(ZStack {
                    plain.foregroundColor(strokeColor).offset(x: offset)
                    plain.foregroundColor(strokeColor).offset(x: -offset)
                    plain.foregroundColor(strokeColor).offset(y: offset)
                    plain.foregroundColor(strokeColor).offset(y: -offset)
                    base
                })
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

        return layered
            .padding(6)
            .frame(width: 46, height: 36)
    }

    private func outlineName(_ outline: OverlayOutline) -> String {
        switch outline {
        case .none: return "無"
        case .thinStroke: return "細描邊"
        case .thickStroke: return "粗描邊"
        case .translucentBox: return "半透明底框"
        case .solidBox: return "實心底框"
        }
    }

    private func shadowName(_ shadow: OverlayShadow) -> String {
        switch shadow {
        case .none: return "無"
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
