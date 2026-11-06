import SwiftUI
import UIKit

/// The 樣式 (style) tab of the overlay panel (D-10 plan B, #678), one page
/// top to bottom: the row of ten looks, the text color with the box button,
/// and the size. `OverlayPanelView` (ui-shell) hosts it for the 樣式 segment,
/// passing in a `StyleTabModel` built from the active profile.
struct StyleTabView: View {
    @ObservedObject var model: StyleTabModel
    /// Content-area height the panel gives this tab (`OverlayPanelView`'s
    /// `contentHeight`, 244pt in the regular layout). Taller content scrolls.
    var availableHeight: CGFloat = 244
    /// Extra room kept under the scroll content (TASK-92): the panel's scroll
    /// views run on under the home indicator, so this is that band's height,
    /// letting the last row scroll up above it.
    var bottomContentInset: CGFloat = 0
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

    /// Center x of each of the nine columns, shared by every color row so the
    /// second row's n-th swatch sits right under the first row's n-th.
    static func columnCenters(forContentWidth contentWidth: CGFloat) -> [CGFloat] {
        let pitch = swatchDiameter + columnSpacing(forContentWidth: contentWidth)
        return (0..<colorColumnCount).map { swatchDiameter / 2 + CGFloat($0) * pitch }
    }

    /// Left/right inset of the page (TASK-84, +4 by TASK-117): 18 puts
    /// sliders and swatches 20pt from the panel edge. The row of looks
    /// scrolls past it to the panel edge, starting at the same inset.
    static let contentHorizontalInset: CGFloat = 18
    /// Space between the page's three parts (D-10).
    static let sectionSpacing: CGFloat = 12
    /// Space above and below each slider row (TASK-117), on top of the page's
    /// 12pt stack spacing. Kept on the row, outside the slider itself.
    static let sliderVerticalPadding: CGFloat = 4
    /// Top inset of the whole tab.
    static let tabTopInset: CGFloat = 4

    /// Capsule metrics of the row of looks (#678-2).
    static let presetSpacing: CGFloat = 8
    static let presetHeight: CGFloat = 34
    static let presetHorizontalPadding: CGFloat = 14
    static let presetVerticalPadding: CGFloat = 7
    /// The selection ring: 2pt `active`, 1pt outside the capsule.
    static let presetRingWidth: CGFloat = 2
    static let presetRingOffset: CGFloat = 1
    /// Diameter of the download badge at a capsule's top-right corner.
    static let presetBadgeSize: CGFloat = 14
    /// Side of the box button (#678-5).
    static let boxButtonSide: CGFloat = 28

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                presetRow
                    // The row scrolls edge to edge of the tab; its own
                    // content keeps the page's inset.
                    .padding(.horizontal, -Self.contentHorizontalInset)
                textColorPalette
                sizeSlider
            }
            .padding(.horizontal, Self.contentHorizontalInset)
            .padding(.top, Self.tabTopInset)
            .padding(.bottom, 6 + bottomContentInset)
        }
        .scrollEdgeHint(flashTrigger: 0)
        .alert("無法儲存", isPresented: Binding(get: { model.lastError != nil },
                                             set: { if !$0 { model.lastError = nil } })) {
            Button("好") { model.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
    }

    // MARK: - 樣式列 (#678-2, #678-4)

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.presetSpacing) {
                ForEach(model.presets, id: \.self) { preset in
                    PresetCapsule(preset: preset,
                                  nameFont: { model.nameFont(for: preset, ofSize: $0) },
                                  fontState: model.fontState(for: preset),
                                  isSelected: model.selectedPreset == preset) {
                        model.selectPreset(preset)
                    }
                }
                if model.selectedPreset == nil {
                    CustomPresetCapsule()
                }
            }
            .padding(.horizontal, Self.contentHorizontalInset)
            // Room for the selection ring and the badge, which sit outside
            // the capsule.
            .padding(.vertical, Self.presetBadgeSize / 2)
        }
    }

    // MARK: - 顏色 (FR-10.4, FR-10.7) 與底框鈕 (#678-5)

    private var textColorPalette: some View {
        let current = model.profile.style.textColor
        let swatches = model.textColorSwatches
        let presets = swatches + model.textColorLightSwatches
        // `.pal{gap:6px}` between the rows (#106).
        return VStack(alignment: .leading, spacing: 6) {
            paletteRow {
                ForEach(swatches, id: \.hexString) { swatch in
                    colorDot(swatch, isSelected: isSame(current, swatch)) { model.selectTextColor(swatch) }
                }
            }
            // Light tints, each under its swatch (TASK-149).
            paletteRow {
                ForEach(model.textColorLightSwatches, id: \.hexString) { swatch in
                    colorDot(swatch, isSelected: isSame(current, swatch)) { model.selectTextColor(swatch) }
                }
            }
            // Rainbow, then recent custom colors on the grid, left-aligned;
            // the box button at the right end, in the ninth column the seven
            // recent colors never reach.
            paletteRow {
                // The rainbow is "selected" for a color that matches no
                // preset or recent swatch, which show their own ring (R.3).
                let isCustomSelected = !presets.contains { isSame(current, $0) }
                    && !model.recentColors.contains { isSame(current, $0) }
                customColorPicker(current: current, isSelected: isCustomSelected,
                                  onApply: { model.applyCustomTextColor($0) },
                                  onCommit: { model.commitCustomColor($0) })
                ForEach(model.recentColors, id: \.hexString) { color in
                    colorDot(color, isSelected: isSame(current, color), labelPrefix: "最近自訂 ") {
                        model.selectTextColor(color)
                    }
                }
                Spacer(minLength: 0)
                boxButton
            }
        }
    }

    /// The box button (#678-5): outline, solid or translucent "A" for the
    /// three states; disabled for a custom style.
    var boxButton: some View {
        let state = model.boxState
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Button {
            model.cycleBoxState()
        } label: {
            Text("A")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(state == nil ? CameraTheme.inkTertiary
                                    : state == .base ? CameraTheme.ink : .white)
                .frame(width: Self.boxButtonSide, height: Self.boxButtonSide)
                .background {
                    switch state {
                    case .solid: shape.fill(CameraTheme.ink)
                    case .translucent: shape.fill(CameraTheme.ink.opacity(0.45))
                    case .base: shape.strokeBorder(CameraTheme.ink, lineWidth: 1.5)
                    case nil: shape.strokeBorder(CameraTheme.inkTertiary, lineWidth: 1.5)
                    }
                }
                .frame(width: Self.swatchDiameter, height: Self.swatchCellHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state == nil)
        .accessibilityLabel("底框")
        .accessibilityValue(Self.boxStateName(state))
        .accessibilityIdentifier("boxStateButton")
    }

    /// The box button's VoiceOver value.
    static func boxStateName(_ state: OverlayBoxState?) -> String {
        switch state {
        case .base: return "原本"
        case .solid: return "實心"
        case .translucent: return "半透明"
        case nil: return "自訂"
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
                // Tapping the track seeks (TASK-114); the double tap below
                // still resets, so the first tap of a double tap seeks first.
                TapSeekSlider(
                    value: Double(model.profile.style.sizeScale),
                    range: Double(StyleTabModel.sizeScaleRange.lowerBound)...Double(StyleTabModel.sizeScaleRange.upperBound),
                    step: Double(StyleTabModel.sizeScaleStep),
                    onChange: { model.setSizeScale(Int($0.rounded())) }
                )
                .tint(CameraTheme.accentControl)
                .accessibilityLabel("字級")
                .accessibilityAction(named: "回到預設大小") { model.resetSizeScale() }
                Text("A").font(.system(size: 24, weight: .semibold)).foregroundColor(CameraTheme.inkSecondary).accessibilityHidden(true)
            }
            // Simultaneous, so the slider's own drag still works.
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetSizeScale() })
            .padding(.vertical, Self.sliderVerticalPadding)
            Text("點或拖曳調整，點兩下回到預設大小")
                .font(.system(size: 12))
                .foregroundColor(CameraTheme.inkSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 共用：色票

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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Whether `color` is `swatch` ignoring opacity (a swatch stays selected
    /// at any opacity, TASK-69).
    private func isSame(_ color: OverlayColor?, _ swatch: OverlayColor) -> Bool {
        guard let color else { return false }
        return StyleTabModel.hasSameRGB(color, swatch)
    }

    /// The 1pt inner edge of every swatch (`ink` at 16%), so light colors
    /// stay visible on the panel background (TASK-49 B).
    private var swatchEdge: some View {
        Circle().strokeBorder(CameraTheme.ink.opacity(0.16), lineWidth: 1)
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

    private func swiftUIColor(_ color: OverlayColor) -> Color {
        Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.opacity)
    }
}

// MARK: - 樣式膠囊 (#678-2)

/// One look in the row: its name in its own face on the look's capsule
/// colors (#678-2), the selection ring and the download badge (#678-4).
private struct PresetCapsule: View {
    let preset: OverlayStylePreset
    let nameFont: (CGFloat) -> UIFont
    let fontState: FontState
    let isSelected: Bool
    let action: () -> Void

    /// `.subheadline`, following Dynamic Type.
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 15

    private static let ink = OverlayColor(CameraTheme.ink) ?? OverlayColor(red8: 0x2A, green8: 0x26, blue8: 0x22)
    private static let noteInk = OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E)

    var body: some View {
        Button(action: action) {
            name
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, StyleTabView.presetHorizontalPadding)
                .padding(.vertical, StyleTabView.presetVerticalPadding)
                .frame(minHeight: StyleTabView.presetHeight)
                .background(background)
                .overlay {
                    Capsule()
                        .strokeBorder(CameraTheme.active, lineWidth: isSelected ? StyleTabView.presetRingWidth : 0)
                        .padding(-(StyleTabView.presetRingWidth + StyleTabView.presetRingOffset))
                }
                .overlay(alignment: .topTrailing) {
                    badge.offset(x: 3, y: -3)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("stylePreset_\(preset.rawValue)")
    }

    @ViewBuilder
    private var name: some View {
        let font = nameFont(nameSize)
        switch preset {
        case .outline:
            // Ink text in a 1pt white stroke, the renderer's real glyph outline.
            Image(uiImage: StyleSwatchPreview.strokedText(preset.displayName, font: font,
                                                          fill: Self.ink, stroke: .white, strokeWidth: 1))
        case .neon, .retro:
            let color = color(preset.defaultTextColor)
            Text(preset.displayName).font(Font(font)).foregroundColor(color)
                .shadow(color: color, radius: 4)
        case .cute:
            Text(preset.displayName).font(Font(font)).foregroundColor(color(preset.defaultTextColor))
        case .note:
            Text(preset.displayName).font(Font(font)).foregroundColor(color(Self.noteInk))
        case .classic, .caption, .poster, .magazine, .handwriting:
            Text(preset.displayName).font(Font(font)).foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch preset {
        case .caption: Capsule().fill(CameraTheme.ink.opacity(0.45))
        case .note:
            Capsule().fill(Color.white)
                .overlay(Capsule().strokeBorder(CameraTheme.ink.opacity(0.15), lineWidth: 1))
        default: Capsule().fill(CameraTheme.ink)
        }
    }

    @ViewBuilder
    private var badge: some View {
        let side = StyleTabView.presetBadgeSize
        switch fontState {
        case .available:
            EmptyView()
        case .notDownloaded, .preparing:
            Image(systemName: "arrow.down.circle.fill")
                .resizable()
                .foregroundStyle(CameraTheme.inkTertiary)
                .background(Circle().fill(Color.white))
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        case let .downloading(progress):
            FontProgressRing(progress: progress, diameter: side)
                .background(Circle().fill(Color.white))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .resizable()
                .foregroundStyle(CameraTheme.active)
                .background(Circle().fill(Color.white))
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }

    private func color(_ color: OverlayColor) -> Color {
        Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.opacity)
    }
}

/// The 自訂 capsule at the row's end while the style matches no look: always
/// selected, does nothing when tapped (#678-2, #678-7).
private struct CustomPresetCapsule: View {
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 15

    var body: some View {
        Button {} label: {
            Text("自訂")
                .font(.system(size: nameSize))
                .foregroundColor(CameraTheme.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, StyleTabView.presetHorizontalPadding)
                .padding(.vertical, StyleTabView.presetVerticalPadding)
                .frame(minHeight: StyleTabView.presetHeight)
                .background(Capsule().fill(CameraTheme.fill))
                .overlay {
                    Capsule()
                        .strokeBorder(CameraTheme.active, lineWidth: StyleTabView.presetRingWidth)
                        .padding(-(StyleTabView.presetRingWidth + StyleTabView.presetRingOffset))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("自訂")
        .accessibilityAddTraits(.isSelected)
        .accessibilityIdentifier("stylePreset_custom")
    }
}

private extension OverlayColor {
    /// Converts a SwiftUI `Color` back into an `OverlayColor`, resolved in
    /// sRGB so the stored hex matches what the user actually picked
    /// (FR-10.7). `nil` only if the color's components cannot be resolved at
    /// all, which does not happen for a picker result.
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

#Preview("預設 · 經典 (375pt)") {
    StyleTabView(model: previewModel())
        .frame(width: 375, height: 244)
        .background(CameraTheme.background)
}

#Preview("海報 · 手寫下載中 · 霓虹失敗 (375pt)") {
    let model = previewModel(fontStates: [.chenyuluoyan: .downloading(progress: 0.4), .huninn: .failed(.other)])
    model.selectPreset(.poster)
    return StyleTabView(model: model)
        .frame(width: 375, height: 244)
        .background(CameraTheme.background)
}

#Preview("自訂 (375pt)") {
    StyleTabView(model: previewModel(style: OverlayStyle(strokeWidth: 4)))
        .frame(width: 375, height: 244)
        .background(CameraTheme.background)
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
