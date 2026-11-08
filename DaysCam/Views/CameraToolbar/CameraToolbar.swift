import SwiftUI

/// The camera's top bar (#712, back to the 1.x layout): the tools toggle on
/// the left, the record switcher centered (FR-20.8), and on the right the
/// ratio key (inner) and the flip button (outermost). Flash, timer, grid and
/// level live in `CameraToolsCapsule`, which opens under the toggle.
///
/// All state and actions come from `model` (`CameraScreenModel`); this view
/// only lays it out and never touches `CaptureSettingsStore`/`CameraService`
/// directly.
struct CameraToolbar: View {
    @ObservedObject var model: CameraScreenModel

    /// Whether the viewfinder currently renders behind this toolbar (issue
    /// #121); every icon then switches to `CameraTheme.inkOnPhoto` plus a
    /// faint shadow. Defaults to `false`.
    var isOnPhoto: Bool = false

    /// Both side groups get `.frame(maxWidth: .infinity, alignment:)` rather
    /// than a `Spacer` on each side of the switcher, so the two boxes stay
    /// the same width and the switcher stays on the true horizontal midline
    /// however many buttons sit on either side (D-1).
    var body: some View {
        HStack(spacing: 0) {
            toolsToggleButton
                .frame(maxWidth: .infinity, alignment: .leading)

            RecordSwitcherCapsule(model: model, isOnPhoto: isOnPhoto)

            HStack(spacing: Self.roundKeySpacing) {
                ratioButton
                flipButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, CameraScreenLayoutMetrics.toolbarHorizontalInset)
    }

    // MARK: - Left: tools toggle

    /// Opens/closes `CameraToolsCapsule`; the chevron points the way it
    /// will move.
    private var toolsToggleButton: some View {
        Button {
            model.toggleCameraTools()
        } label: {
            Image(systemName: model.isCameraToolsExpanded ? "chevron.up.circle" : "chevron.down.circle")
                .roundKey(isOnPhoto: isOnPhoto)
                .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityLabel("相機設定")
        .accessibilityValue(model.isCameraToolsExpanded ? "已展開" : "已收起")
    }

    // MARK: - Right: ratio and flip

    /// Cycles 3:4 → 1:1 → 9:16 → 3:4 (#712, as 1.3.0). Always plain ink:
    /// the ratio is a choice, not a tool that is on.
    private var ratioButton: some View {
        let ratio = model.captureAspectRatio
        return Button(action: model.cycleAspectRatio) {
            Self.ratioIcon(for: ratio, isOnPhoto: isOnPhoto)
                .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityLabel("比例：\(ratio.displayLabel)")
        .accessibilityIdentifier("cameraRatioButton")
    }

    /// One ratio's outline with the ratio text centered inside it (1.3.0,
    /// issue #169): a stroked `RoundedRectangle` with the same width on all
    /// four sides, matching a 22pt medium symbol, in the 44pt tap target.
    /// The outline is schematic: 9:16 is taller than 3:4, capped at 32pt,
    /// and widened to fit its full-size label.
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

    /// Switches between the back and front cameras.
    private var flipButton: some View {
        Button(action: model.switchCamera) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .roundKey(isOnPhoto: isOnPhoto)
                .rotatedChrome(model.viewfinderRotation)
        }
        .disabled(model.isCaptureUnsupported)
        .opacity(model.isCaptureUnsupported ? 0.35 : 1)
        .accessibilityLabel("翻轉鏡頭")
    }

    // MARK: - Size

    /// Tap target of every toolbar button (issue #137; was 38).
    static let buttonSize: CGFloat = 44

    /// Gap between the two round keys on the right.
    static let roundKeySpacing = CameraScreenLayoutMetrics.toolbarRoundKeySpacing
}

/// The ratio key's outline geometry (issue #137, #169; restored by #712).
enum RatioIconGeometry {
    static let labelFontSize: CGFloat = 6.5
    /// Outline stroke, measured off a 22pt medium `grid` symbol (~2.17pt) so
    /// the ratio key matches its neighbors (issue #169).
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

    /// Keeps the 3:4 outline unchanged while giving 9:16 enough inner space
    /// for the unscaled label and at least 1pt clearance.
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
    /// outline's sides; the font is never shrunk to make it fit. 1:1 is
    /// 21×21, as wide as the 3:4 outline.
    static func outlineHeight(for ratio: CaptureAspectRatio) -> CGFloat {
        if ratio == .oneByOne { return squareOutlineSide }
        let needed = (labelWidth(for: ratio) * minimumLabelScale + 2 * labelInset) / ratio.shortToLongRatio
        return min(max(baseOutlineHeight, needed.rounded(.up)), maximumOutlineHeight)
    }
}

extension CaptureAspectRatio {
    /// The label inside the ratio key and in its accessibility label (#712).
    var displayLabel: String {
        switch self {
        case .threeByFour: return "3:4"
        case .oneByOne: return "1:1"
        case .nineBySixteen: return "9:16"
        }
    }
}

/// The horizontal pill that floats below the toolbar's toggle, left-aligned
/// under it (issue #135, #712; D-1's `.pop` style) holding flash, timer, grid and level (#687). Tapping a tool cycles
/// it and leaves the pill open, so several can be adjusted in a row. The pill
/// has its own white background, so icons always use `CameraTheme.ink`.
struct CameraToolsCapsule: View {
    @ObservedObject var model: CameraScreenModel

    var body: some View {
        HStack(spacing: 2) {
            flashButton
            timerButton
            gridButton
            levelButton
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

    /// The 水平儀 switch (#687): `active` while on.
    private var levelButton: some View {
        Button(action: model.toggleLevel) {
            Image(systemName: "level")
                .toolbarIcon(isActive: model.isLevelOn, isOnPhoto: false)
                .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityLabel("水平儀")
        .accessibilityValue(model.isLevelOn ? "開" : "關")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("levelToggle")
    }
}

/// One SF Symbol/text label at the toolbar's fixed 44x44 tap target, colored
/// `active` when the tool it belongs to is on, otherwise `ink`/`inkOnPhoto`
/// depending on `isOnPhoto` (PRD 0.2 FR-7.10, FR-14.2; issue #121).
private struct ToolbarIconModifier: ViewModifier {
    let isActive: Bool
    let isOnPhoto: Bool
    let width: CGFloat
    /// Overrides the icon's color.
    var ink: Color?
    /// The icon's point size; 22 for every key unless a glyph needs a visual
    /// correction.
    var glyphSize: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .font(.system(size: glyphSize, weight: .medium))
            .foregroundColor(ink ?? (isActive ? CameraTheme.active : (isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink)))
            .frame(width: width, height: CameraToolbar.buttonSize)
            .legibleOverPhoto(isOnPhoto)
    }
}

private extension View {
    func toolbarIcon(isActive: Bool, isOnPhoto: Bool, width: CGFloat = CameraToolbar.buttonSize,
                     ink: Color? = nil, glyphSize: CGFloat = 22) -> some View {
        modifier(ToolbarIconModifier(isActive: isActive, isOnPhoto: isOnPhoto, width: width, ink: ink,
                                     glyphSize: glyphSize))
    }

    /// A top-bar key: just the icon inside the 44pt tap target, no disc.
    func roundKey(isOnPhoto: Bool) -> some View {
        toolbarIcon(isActive: false, isOnPhoto: isOnPhoto)
    }
}

/// A faint shadow (black 30%, radius 3) so light, on-photo chrome
/// (`CameraTheme.inkOnPhoto`) stays legible over a bright part of the photo
/// (issue #121 assumption 1) — a no-op while `isOnPhoto` is false. Shared
/// with `CameraScreen`'s footer.
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

#Preview {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store,
                                  profileID: store.profiles.first?.id ?? UUID())
    return ZStack {
        CameraTheme.background.ignoresSafeArea()
        VStack {
            CameraToolbar(model: model)
            Spacer()
        }
    }
}
