import SwiftUI

/// The camera screen's top bar (PRD 0.2 FR-7.2, D-1): flash and timer on the
/// left, the profile switcher centered, ratio/grid/flip on the right.
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
            HStack(spacing: 0) {
                flashButton
                timerButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            profileChip

            HStack(spacing: 0) {
                ratioButton
                gridButton
                flipButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Left: flash, timer

    private var flashButton: some View {
        Button(action: model.cycleFlash) {
            Image(systemName: flashIconName)
                .toolbarIcon(isActive: model.isFlashToolActive, isOnPhoto: isOnPhoto)
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
                        .font(CameraTheme.toolFont(.footnote))
                }
            }
            .toolbarIcon(isActive: model.isTimerToolActive, isOnPhoto: isOnPhoto)
        }
        .accessibilityLabel(model.captureSettingsStore.timerSeconds == .off
                            ? "計時器：關"
                            : "計時器：\(model.captureSettingsStore.timerSeconds.rawValue) 秒")
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

    // MARK: - Right: ratio, grid, flip

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
    /// The outline's longest edge is capped to 20pt (to read at roughly the
    /// same size as the other 18pt toolbar icons) and its shorter edge is
    /// computed from `ratio.shortToLongRatio`, rather than just fitting the
    /// image into a 20x20 square: the `Text` overlay below is proposed
    /// *this* content frame's size, so it needs to match the outline's true
    /// drawn width for the text to size/truncate against, not the outer
    /// square. Overlaying against the square let the text (esp. 9:16's,
    /// whose drawn rectangle is only ~11pt wide inside that square) size
    /// itself as if it had ~20pt to fill and overflow past the actual
    /// outline (PR #98 review, qa on-device screenshot) — `lineLimit(1)`
    /// only truncates when the *proposed* width is already too small, and a
    /// too-generous proposed width means it never truncates at all.
    ///
    /// `static` and parameterized over `ratio` (rather than reading
    /// `model.captureSettingsStore` directly) purely so the `"Ratio icons"`
    /// preview below can render all three side by side without duplicating
    /// these layout numbers.
    fileprivate static func ratioIcon(for ratio: CaptureAspectRatio, isOnPhoto: Bool = false) -> some View {
        let contentHeight: CGFloat = 20
        let contentWidth = contentHeight * ratio.shortToLongRatio
        return Image(systemName: ratio.sfSymbolName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: contentWidth, height: contentHeight)
            .overlay(
                Text(ratio.displayLabel)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.25)
                    .lineLimit(1)
                    // A little inset so the text never touches the outline
                    // itself, not just avoids overflowing past it.
                    .padding(.horizontal, 1.5)
            )
            .foregroundColor(isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink)
            .frame(width: 38, height: 38)
            .legibleOverPhoto(isOnPhoto)
    }

    private var gridButton: some View {
        Button(action: model.toggleGrid) {
            Image(systemName: "grid")
                .toolbarIcon(isActive: model.isGridToolActive, isOnPhoto: isOnPhoto)
        }
        .accessibilityLabel(model.isGridToolActive ? "格線：開" : "格線：關")
    }

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

/// One SF Symbol/text label at the toolbar's fixed 38x38 tap target, colored
/// `active` when the tool it belongs to is on, otherwise `ink`/`inkOnPhoto`
/// depending on `isOnPhoto` (PRD 0.2 FR-7.10, FR-14.2 — no button
/// background or border; issue #121 for the `inkOnPhoto` half).
private struct ToolbarIconModifier: ViewModifier {
    let isActive: Bool
    let isOnPhoto: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(isActive ? CameraTheme.active : (isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink))
            .frame(width: 38, height: 38)
            .legibleOverPhoto(isOnPhoto)
    }
}

private extension View {
    func toolbarIcon(isActive: Bool, isOnPhoto: Bool) -> some View {
        modifier(ToolbarIconModifier(isActive: isActive, isOnPhoto: isOnPhoto))
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

/// Acceptance 90/B.3–B.4: all three ratio icons at their real 38x38 tap
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
