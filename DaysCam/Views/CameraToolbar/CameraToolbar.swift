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
            toolsToggleButton
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
        }
        .accessibilityLabel("相機設定")
        .accessibilityValue(model.isCameraToolsExpanded ? "已展開" : "已收起")
    }

    // MARK: - Center: profile switcher (PRD 0.2 FR-7.11)

    /// Lists only names, in `ProfileStore`'s order, with the current one
    /// checked — no "管理設定檔" entry (that moves out to its own entry
    /// point in TASK-26).
    ///
    /// Padding matches D-1's final borderless chip (`.chip{padding:7px 6px}`,
    /// #105) — an earlier revision of that same rule had a filled pill
    /// background (`padding:7px 14px`), superseded once PRD 0.2 FR-14.2
    /// dropped every button's background except the shutter's.
    private var profileChip: some View {
        Menu {
            ForEach(model.profileMenuItems) { profile in
                Button {
                    model.selectProfile(id: profile.id)
                } label: {
                    if profile.id == model.selectedProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
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
    }

    // MARK: - Right: ratio, flip

    /// Taps cycle straight to the next ratio (human decision 2026-09-27):
    /// no menu, since there are only three ratios and the icon itself shows
    /// which one is current. Never rendered `active`-colored — a ratio is a
    /// mode, not a toggled-on tool (PRD 0.2 FR-7.7).
    private var ratioButton: some View {
        Button(action: model.cycleAspectRatio) {
            ratioIcon
        }
        .accessibilityLabel("比例：\(model.captureSettingsStore.captureAspectRatio.displayLabel)")
    }

    private var ratioIcon: some View {
        Self.ratioIcon(for: model.captureSettingsStore.captureAspectRatio, isOnPhoto: isOnPhoto)
    }

    /// One ratio's SF Symbol outline (`rectangle.ratio.3.to.4`, `square`, or
    /// `rectangle.ratio.9.to.16` — human choice 2026-09-27, not self-drawn)
    /// with the ratio text centered inside it.
    ///
    /// The outline's height comes from `RatioIconGeometry` (28pt, grown up to
    /// 32pt only when the label would not fit, issue #137) and its width from
    /// `ratio.shortToLongRatio`; the `Text` overlay is proposed *this* frame's
    /// size, not the outer tap target's, so it sizes against the outline's
    /// true drawn width (PR #98 review).
    ///
    /// `static` and parameterized over `ratio` (rather than reading
    /// `model.captureSettingsStore` directly) purely so the `"Ratio icons"`
    /// preview below can render all three side by side without duplicating
    /// these layout numbers.
    static func ratioIcon(for ratio: CaptureAspectRatio, isOnPhoto: Bool = false) -> some View {
        let contentHeight = RatioIconGeometry.outlineHeight(for: ratio)
        let contentWidth = contentHeight * ratio.shortToLongRatio
        return Image(systemName: ratio.sfSymbolName)
            .resizable()
            // Stretched to exactly `contentWidth` × `contentHeight`, not
            // `.fit`: the symbol's own aspect is wider than a true 9:16, so
            // fitting it into the frame made the 9:16 outline 18×28 (#137, qa).
            .fontWeight(RatioIconGeometry.outlineWeight)
            .frame(width: contentWidth, height: contentHeight)
            .overlay(
                Text(ratio.displayLabel)
                    .font(.system(size: RatioIconGeometry.labelFontSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(RatioIconGeometry.minimumLabelScale)
                    .lineLimit(1)
                    .frame(width: contentWidth - 2 * RatioIconGeometry.labelInset)
            )
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
        }
        .accessibilityLabel(model.captureSettingsStore.timerSeconds == .off
                            ? "計時器：關"
                            : "計時器：\(model.captureSettingsStore.timerSeconds.rawValue) 秒")
    }

    private var gridButton: some View {
        Button(action: model.toggleGrid) {
            Image(systemName: "grid")
                .toolbarIcon(isActive: model.isGridToolActive, isOnPhoto: false)
        }
        .accessibilityLabel(model.isGridToolActive ? "格線：開" : "格線：關")
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
    /// A thin symbol weight keeps the outline's stroke near its old ~1.3pt
    /// now that the symbol is drawn larger.
    static let outlineWeight: Font.Weight = .thin
    static let baseOutlineHeight: CGFloat = 28
    static let maximumOutlineHeight: CGFloat = 32
    /// Clearance between the label and the inside of the outline: the
    /// symbol's own ~1pt stroke plus 1pt.
    static let labelInset: CGFloat = 2
    /// The label may shrink to this fraction of `labelFontSize` (issue #137);
    /// below it, the outline grows instead.
    static let minimumLabelScale: CGFloat = 0.9

    /// Width of `ratio`'s label at `labelFontSize`, bold rounded.
    static func labelWidth(for ratio: CaptureAspectRatio) -> CGFloat {
        let base = UIFont.systemFont(ofSize: labelFontSize, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: labelFontSize) } ?? base
        return (ratio.displayLabel as NSString).size(withAttributes: [.font: font]).width
    }

    /// 28pt, grown just enough (up to 32pt) for the label to clear the
    /// outline's sides; the font is never shrunk to make it fit.
    static func outlineHeight(for ratio: CaptureAspectRatio) -> CGFloat {
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

    /// The SF Symbol drawing this ratio's outline (human choice 2026-09-27,
    /// PRD 0.2 FR-7.7): an actual SF Symbol per §0.2 PRD §1, never
    /// self-drawn.
    var sfSymbolName: String {
        switch self {
        case .threeByFour: return "rectangle.ratio.3.to.4"
        case .oneByOne: return "square"
        case .nineBySixteen: return "rectangle.ratio.9.to.16"
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
