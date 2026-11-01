import SwiftUI

/// The camera's top bar (PRD 2.0 FR-20.7, D9): the overlay-preview switch
/// on the left (FR-20.9), the record
/// switcher centered (FR-20.8), and on the right the tools toggle (inner)
/// and the flip button (outermost), two matching round keys. Flash, timer
/// and grid live in `CameraToolsCapsule`, which opens under the toggle.
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
            leftSlot
                .frame(maxWidth: .infinity, alignment: .leading)

            RecordSwitcherCapsule(model: model, isOnPhoto: isOnPhoto)

            HStack(spacing: Self.roundKeySpacing) {
                toolsToggleButton
                flipButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, CameraScreenLayoutMetrics.toolbarHorizontalInset)
    }

    // MARK: - Left: overlay preview (FR-20.9)

    /// The 疊字預覽 switch: on is the `accent` disc with the filled icon, off
    /// the plain disc with the outline icon. A switch to VoiceOver, with the
    /// state as its value.
    private var leftSlot: some View {
        let isOn = model.isOverlayPreviewOn
        return Button(action: model.toggleOverlayPreview) {
            Image(systemName: isOn ? "text.below.photo.fill" : "text.below.photo")
                .roundKey(isOnPhoto: isOnPhoto, isHighlighted: isOn)
                .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityLabel("疊字預覽")
        .accessibilityValue(isOn ? "開" : "關")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("overlayPreviewToggle")
    }

    // MARK: - Right: tools toggle and flip

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

    /// Diameter of the round keys' `CameraTheme.fill` disc (D9 `.round`).
    static let roundKeyDiameter: CGFloat = 40

    /// Gap between the two round keys on the right (D9).
    static let roundKeySpacing = CameraScreenLayoutMetrics.toolbarRoundKeySpacing
}

/// The horizontal pill that floats below the toolbar's toggle, right-aligned
/// under it (issue #135,
/// D-1's `.pop` style) holding flash, timer and grid. Tapping a tool cycles
/// it and leaves the pill open, so several can be adjusted in a row. The pill
/// has its own white background, so icons always use `CameraTheme.ink`.
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
}

/// One SF Symbol/text label at the toolbar's fixed 44x44 tap target, colored
/// `active` when the tool it belongs to is on, otherwise `ink`/`inkOnPhoto`
/// depending on `isOnPhoto` (PRD 0.2 FR-7.10, FR-14.2; issue #121).
private struct ToolbarIconModifier: ViewModifier {
    let isActive: Bool
    let isOnPhoto: Bool
    let width: CGFloat
    /// Overrides the icon's color (the overlay switch's icon on its accent disc).
    var ink: Color?

    func body(content: Content) -> some View {
        content
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(ink ?? (isActive ? CameraTheme.active : (isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink)))
            .frame(width: width, height: CameraToolbar.buttonSize)
            .legibleOverPhoto(isOnPhoto)
    }
}

private extension View {
    func toolbarIcon(isActive: Bool, isOnPhoto: Bool, width: CGFloat = CameraToolbar.buttonSize,
                     ink: Color? = nil) -> some View {
        modifier(ToolbarIconModifier(isActive: isActive, isOnPhoto: isOnPhoto, width: width, ink: ink))
    }

    /// A top-bar round key (D9 `.round`): the icon on a faint
    /// `CameraTheme.fill` disc inside the 44pt tap target.
    ///
    /// `isHighlighted` only swaps the disc to `CameraTheme.accent` and the
    /// icon to `inkOnAccent`; size, font and weight stay the same.
    func roundKey(isOnPhoto: Bool, isHighlighted: Bool = false) -> some View {
        toolbarIcon(isActive: false, isOnPhoto: isOnPhoto && !isHighlighted,
                    ink: isHighlighted ? CameraTheme.inkOnAccent : nil)
            .background(
                Circle()
                    .fill(isHighlighted ? CameraTheme.accent : CameraTheme.fill)
                    .frame(width: CameraToolbar.roundKeyDiameter, height: CameraToolbar.roundKeyDiameter)
            )
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
