import SwiftUI

/// The camera screen's top bar (PRD 0.2 FR-7.2, D-1; issue #135): the tools
/// toggle on the left (flash, timer and grid live in `CameraToolsCapsule`),
/// the profile switcher centered, ratio/flip on the right.
///
/// All state and actions come from `model` (`CameraScreenModel`); this view
/// only lays it out and never touches `CaptureSettingsStore`/`CameraService`
/// directly, the same separation `CameraScreen` already keeps.
struct CameraToolbar: View {
    @ObservedObject var model: CameraScreenModel

    /// Whether the viewfinder currently renders behind this toolbar (issue
    /// #121, `CameraScreenLayoutMetrics.isViewfinderBehindHeader` decides
    /// this — `CameraScreen` computes it, not this view, since it needs the
    /// same layout metrics that already decide everything else about where
    /// this toolbar sits). Every icon/text here switches to
    /// `CameraTheme.inkOnPhoto` (plus a faint shadow to stay legible over a
    /// bright part of the photo) instead of `CameraTheme.ink` while true —
    /// a tool that is *on* still uses `CameraTheme.active` either way
    /// (PRD 0.2 FR-7.10 unaffected by this). Defaults to `false` so the
    /// previews below (and any other caller with nothing behind the
    /// toolbar) don't have to spell it out.
    var isOnPhoto: Bool = false

    /// Leaves the camera for the 紀錄 list (#617); `nil` hides the key.
    var onClose: (() -> Void)? = nil

    /// Both side groups get `.frame(maxWidth: .infinity, alignment:)` rather
    /// than a `Spacer` on each side of `profileChip`: two views with the
    /// same "infinitely flexible" width split whatever's left over the chip
    /// equally between them, so the two boxes stay the same width — and the
    /// chip stays on the true horizontal midline — no matter how many
    /// buttons sit in either box (D-1's CSS mirrors this with a
    /// `grid-template-columns: 1fr auto 1fr` top bar). A pair of `Spacer`s
    /// cannot do this: they split the *leftover* space evenly, which only
    /// centers the chip when both button groups already have equal width.
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                if let onClose { closeButton(onClose) }
                toolsToggleButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            profileChip

            HStack(spacing: 0) {
                ratioButton
                flipButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, CameraScreenLayoutMetrics.toolbarHorizontalInset)
    }

    // MARK: - Left: close (#617)

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .toolbarIcon(isActive: false, isOnPhoto: isOnPhoto)
                .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityLabel("回到紀錄")
        .accessibilityIdentifier("closeCameraButton")
    }

    // MARK: - Left: tools toggle (issue #135)

    /// Opens/closes `CameraToolsCapsule`. A faint `CameraTheme.fill` disc
    /// behind the icon marks the expanded state; nothing marks an enabled
    /// tool while collapsed (human decision 2026-09-30).
    private var toolsToggleButton: some View {
        Button {
            model.toggleCameraTools()
        } label: {
            Image(systemName: model.isCameraToolsExpanded ? "chevron.up.circle" : "chevron.down.circle")
                .toolbarIcon(isActive: false, isOnPhoto: isOnPhoto)
                .background(
                    Circle()
                        .fill(CameraTheme.fill)
                        .opacity(model.isCameraToolsExpanded ? 1 : 0)
                )
                .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityLabel("相機設定")
        .accessibilityValue(model.isCameraToolsExpanded ? "已展開" : "已收起")
    }

    // MARK: - Center: profile switcher (PRD 0.2 FR-7.11)

    /// A plain button that opens the 設定檔 sheet (#226 R-1): switching,
    /// adding and the rest all live there, so there is no menu.
    ///
    /// Padding matches D-1's final borderless chip (`.chip{padding:7px 6px}`,
    /// #105) — an earlier revision of that same rule had a filled pill
    /// background (`padding:7px 14px`), superseded once PRD 0.2 FR-14.2
    /// dropped every button's background except the shutter's.
    private var profileChip: some View {
        Button {
            model.presentProfileManagement()
        } label: {
            HStack(spacing: 4) {
                Text(model.currentProfileName)
                    .font(CameraTheme.toolFont(.subheadline))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink)
            .legibleOverPhoto(isOnPhoto)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
        }
        .accessibilityLabel("設定檔：\(model.currentProfileName)")
        // TASK-96: the first-launch tour's step 1 points here.
        .onboardingTarget(.profileChip)
    }

    // MARK: - Right: ratio, flip

    /// Taps cycle straight to the next ratio (human decision 2026-09-27):
    /// no menu, since there are only three ratios and the icon itself shows
    /// which one is current. Never rendered `active`-colored — a ratio is a
    /// mode, not a toggled-on tool (PRD 0.2 FR-7.7).
    private var ratioButton: some View {
        Button(action: model.cycleAspectRatio) {
            ratioIcon
                .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityLabel("比例：\(model.captureSettingsStore.captureAspectRatio.displayLabel)")
    }

    private var ratioIcon: some View {
        Self.ratioIcon(for: model.captureSettingsStore.captureAspectRatio, isOnPhoto: isOnPhoto)
    }

    /// One ratio's outline with the ratio text centered inside it.
    ///
    /// The outline is drawn here (issue #169, superseding #90's SF Symbol
    /// choice): stretching an SF Symbol to the right proportions made its
    /// edges uneven and forced a lighter weight, so it looked thinner than
    /// the other 22pt medium icons. A stroked `RoundedRectangle` has the
    /// same width on all four sides, set to what a 22pt medium symbol
    /// measures (`RatioIconGeometry.strokeWidth`).
    ///
    /// The outline is schematic: 9:16 is taller than 3:4, capped at 32pt,
    /// and widened to fit its full-size label (issue #169, 2026-10-02).
    /// The label is sized against the inner width, not the tap target.
    ///
    /// `static` and parameterized over `ratio` (rather than reading
    /// `model.captureSettingsStore` directly) purely so the `"Ratio icons"`
    /// preview below can render all three side by side without duplicating
    /// these layout numbers.
    static func ratioIcon(for ratio: CaptureAspectRatio, isOnPhoto: Bool = false) -> some View {
        let contentHeight = RatioIconGeometry.outlineHeight(for: ratio)
        let contentWidth = RatioIconGeometry.outlineWidth(for: ratio)
        return ZStack {
            RoundedRectangle(cornerRadius: RatioIconGeometry.cornerRadius, style: .continuous)
                .strokeBorder(lineWidth: RatioIconGeometry.strokeWidth)
                .frame(width: contentWidth, height: contentHeight)
            Text(ratio.displayLabel)
                .font(.system(size: RatioIconGeometry.labelFontSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .frame(width: contentWidth - 2 * RatioIconGeometry.labelInset)
        }
        .foregroundColor(isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink)
        .frame(width: CameraToolbar.buttonSize, height: CameraToolbar.buttonSize)
        .legibleOverPhoto(isOnPhoto)
    }

    /// Tap target of every toolbar button (issue #137; was 38).
    static let buttonSize: CGFloat = 44

    private var flipButton: some View {
        Button(action: model.switchCamera) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .toolbarIcon(isActive: false, isOnPhoto: isOnPhoto)
                .rotatedChrome(model.viewfinderRotation)
        }
        .disabled(model.isCaptureUnsupported)
        .opacity(model.isCaptureUnsupported ? 0.35 : 1)
        .accessibilityLabel("翻轉鏡頭")
    }
}

/// The horizontal pill that floats below the toolbar's toggle (issue #135,
/// D-1's `.pop` style) holding flash, timer and grid. Tapping a tool cycles
/// it and leaves the pill open, so several can be adjusted in a row. The pill
/// has its own white background, so icons always use `CameraTheme.ink`, never
/// the on-photo light color.
struct CameraToolsCapsule: View {
    @ObservedObject var model: CameraScreenModel

    var body: some View {
        HStack(spacing: 2) {
            flashButton
            timerButton
            gridButton
            toneButton
        }
        .padding(4)
        .background(
            Capsule()
                .fill(CameraTheme.popoverBackground)
                .shadow(color: CameraTheme.popoverShadow, radius: 12, x: 0, y: 8)
        )
    }

    private var flashButton: some View {
        Button(action: model.cycleFlash) {
            Image(systemName: flashIconName)
                .toolbarIcon(isActive: model.isFlashToolActive, isOnPhoto: false)
                .rotatedChrome(model.viewfinderRotation)
        }
        .disabled(model.isFlashToolDisabled)
        .opacity(model.isFlashToolDisabled ? 0.35 : 1)
        .accessibilityLabel("閃光燈")
    }

    private var flashIconName: String {
        switch model.captureSettingsStore.flashMode {
        case .off: return "bolt.slash"
        case .auto: return "bolt.badge.automatic"
        case .on: return "bolt.fill"
        }
    }

    private var timerButton: some View {
        Button(action: model.cycleTimer) {
            Group {
                if model.captureSettingsStore.timerSeconds == .off {
                    Image(systemName: "timer")
                } else {
                    Text("\(model.captureSettingsStore.timerSeconds.rawValue)s")
                        .font(CameraTheme.toolFont(.subheadline))
                }
            }
            .toolbarIcon(isActive: model.isTimerToolActive, isOnPhoto: false)
            .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityLabel(model.captureSettingsStore.timerSeconds == .off
                            ? "計時器：關"
                            : "計時器：\(model.captureSettingsStore.timerSeconds.rawValue) 秒")
    }

    private var gridButton: some View {
        Button(action: model.toggleGrid) {
            Image(systemName: "grid")
                .toolbarIcon(isActive: model.isGridToolActive, isOnPhoto: false)
                .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityLabel(model.isGridToolActive ? "格線：開" : "格線：關")
    }

    /// Display name of one color tone (#590).
    static func toneName(_ tone: ColorTone) -> String {
        switch tone {
        case .cool2: return "冷 2"
        case .cool1: return "冷 1"
        case .standard: return "標準"
        case .warm1: return "暖 1"
        case .warm2: return "暖 2"
        }
    }

    /// Opens the tone picker; never cycles the tone itself (#590).
    private var toneButton: some View {
        Button(action: model.toggleTonePicker) {
            Image(systemName: "thermometer.medium")
                .toolbarIcon(isActive: model.isToneToolActive, isOnPhoto: false)
                .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityIdentifier("toneButton")
        .accessibilityLabel("色調：\(Self.toneName(model.captureSettingsStore.colorTone))")
    }
}

/// The second capsule under `CameraToolsCapsule`: 冷 · five dots · 暖 (#590).
/// Picking a dot writes the tone straight away and leaves the row open.
struct ColorTonePicker: View {
    @ObservedObject var model: CameraScreenModel

    var body: some View {
        HStack(spacing: 0) {
            Text("冷")
                .font(.caption)
                .foregroundColor(CameraTheme.inkSecondary)
                .padding(.leading, 12)
            ForEach(ColorTone.allCases, id: \.self) { tone in
                dot(for: tone)
            }
            Text("暖")
                .font(.caption)
                .foregroundColor(CameraTheme.inkSecondary)
                .padding(.trailing, 12)
        }
        .padding(4)
        .background(
            Capsule()
                .fill(CameraTheme.popoverBackground)
                .shadow(color: CameraTheme.popoverShadow, radius: 12, x: 0, y: 8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tonePicker")
    }

    private func dot(for tone: ColorTone) -> some View {
        let isSelected = model.captureSettingsStore.colorTone == tone
        return Button {
            model.setColorTone(tone)
        } label: {
            Circle()
                .fill(isSelected ? CameraTheme.active : CameraTheme.inkTertiary)
                .frame(width: isSelected ? 16 : 10, height: isSelected ? 16 : 10)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(CameraToolsCapsule.toneName(tone))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("tone_\(tone.rawValue)")
    }
}

/// One SF Symbol/text label at the toolbar's fixed 44x44 tap target, colored
/// `active` when the tool it belongs to is on, otherwise `ink`/`inkOnPhoto`
/// depending on `isOnPhoto` (PRD 0.2 FR-7.10, FR-14.2 — no button
/// background or border; issue #121 for the `inkOnPhoto` half).
private struct ToolbarIconModifier: ViewModifier {
    let isActive: Bool
    let isOnPhoto: Bool
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(isActive ? CameraTheme.active : (isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink))
            .frame(width: width, height: CameraToolbar.buttonSize)
            .legibleOverPhoto(isOnPhoto)
    }
}

private extension View {
    func toolbarIcon(isActive: Bool, isOnPhoto: Bool, width: CGFloat = CameraToolbar.buttonSize) -> some View {
        modifier(ToolbarIconModifier(isActive: isActive, isOnPhoto: isOnPhoto, width: width))
    }
}

/// A faint shadow (black 30%, radius 3) so light, on-photo chrome
/// (`CameraTheme.inkOnPhoto`) stays legible over a bright part of the photo
/// (issue #121 assumption 1) — a no-op while `isOnPhoto` is false, so this
/// is safe to chain onto anything unconditionally. Shared with
/// `CameraScreen`'s own footer icons, which switch between the same two
/// tokens for the same reason; not `private` for that reason.
extension View {
    @ViewBuilder
    func legibleOverPhoto(_ isOnPhoto: Bool) -> some View {
        if isOnPhoto {
            shadow(color: .black.opacity(0.3), radius: 3)
        } else {
            self
        }
    }
}

/// The ratio button's outline geometry (issue #137).
enum RatioIconGeometry {
    static let labelFontSize: CGFloat = 6.5
    /// Outline stroke, measured off a 22pt medium `grid` symbol (~2.17pt) so
    /// the ratio button matches its neighbors (issue #169).
    static let strokeWidth: CGFloat = 2.15
    static let cornerRadius: CGFloat = 4
    static let baseOutlineHeight: CGFloat = 28
    /// The 1:1 outline's side: the same width as 3:4's 21×28 outline.
    static let squareOutlineSide: CGFloat = 21
    static let maximumOutlineHeight: CGFloat = 32
    /// Distance from the outline's outer edge to the label: the stroke plus
    /// 1pt of clearance.
    static let labelInset: CGFloat = strokeWidth + 1
    /// The label may shrink to this fraction of `labelFontSize` before the
    /// outline grows (issue #137).
    static let minimumLabelScale: CGFloat = 0.9
    /// Keeps the 3:4 outline unchanged while giving 9:16 enough
    /// inner space for the unscaled label and at least 1pt clearance.
    static func outlineWidth(for ratio: CaptureAspectRatio) -> CGFloat {
        let proportionalWidth = outlineHeight(for: ratio) * ratio.shortToLongRatio
        guard ratio == .nineBySixteen else { return proportionalWidth }
        return max(proportionalWidth, (labelWidth(for: ratio) + 2 * labelInset).rounded(.up))
    }

    /// Width of `ratio`'s label at `labelFontSize`, bold rounded.
    static func labelWidth(for ratio: CaptureAspectRatio) -> CGFloat {
        let base = UIFont.systemFont(ofSize: labelFontSize, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: labelFontSize) } ?? base
        return (ratio.displayLabel as NSString).size(withAttributes: [.font: font]).width
    }

    /// 28pt, grown just enough (up to 32pt) for the label to clear the
    /// outline's sides; the font is never shrunk to make it fit.
    static func outlineHeight(for ratio: CaptureAspectRatio) -> CGFloat {
        // 1:1 is as wide as the 3:4 outline (21pt), so it is 21×21 (TASK-37).
        if ratio == .oneByOne { return squareOutlineSide }
        let needed = (labelWidth(for: ratio) * minimumLabelScale + 2 * labelInset) / ratio.shortToLongRatio
        return min(max(baseOutlineHeight, needed.rounded(.up)), maximumOutlineHeight)
    }
}

private extension CaptureAspectRatio {
    /// The label shown inside the ratio button's icon (PRD 0.2 FR-7.7, D-1).
    var displayLabel: String {
        switch self {
        case .threeByFour: return "3:4"
        case .oneByOne: return "1:1"
        case .nineBySixteen: return "9:16"
        }
    }
}

#Preview {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    return ZStack {
        CameraTheme.background.ignoresSafeArea()
        VStack {
            CameraToolbar(model: model)
            Spacer()
        }
    }
}

/// Acceptance 91/B.3: a maximum-length (20-character) profile name should
/// still leave the chip centered and truncate to one line instead of
/// pushing into the side buttons.
#Preview("Long profile name") {
    let store = ProfileStore()
    store.load()
    if let longNamed = try? store.add(CameraProfile(name: "小寶的一百天紀念日超級無敵長名稱測試中",
                                                      startDate: DateComponents(year: 2026, month: 1, day: 1))) {
        store.select(id: longNamed.id)
    }
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    return ZStack {
        CameraTheme.background.ignoresSafeArea()
        VStack {
            CameraToolbar(model: model)
            Spacer()
        }
    }
}

/// Acceptance 90/B.3–B.4: all three ratio icons at their real 44x44 tap
/// target size, so a screenshot can be compared straight against the
/// outline shapes/sizes without tapping through the live button three
/// times in the simulator.
#Preview("Ratio icons") {
    ZStack {
        CameraTheme.background.ignoresSafeArea()
        HStack(spacing: 24) {
            ForEach(CaptureAspectRatio.allCases, id: \.self) { ratio in
                CameraToolbar.ratioIcon(for: ratio)
            }
        }
    }
}

/// 驗收 T.3/T.6（issue #121）：`isOnPhoto: true` over a photo-like
/// gradient, so qa can compare the light chrome + shadow against a bright
/// background without needing the live camera feed.
#Preview("isOnPhoto（T.3/T.6）") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    return ZStack {
        LinearGradient(colors: [.white, .gray], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        VStack {
            CameraToolbar(model: model, isOnPhoto: true)
            Spacer()
        }
    }
}
