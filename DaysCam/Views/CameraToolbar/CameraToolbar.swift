import SwiftUI

/// The camera's top bar (PRD 2.0 FR-20.1–FR-20.3): `xmark` and the tools
/// toggle on the left (flash, timer and grid live in `CameraToolsCapsule`),
/// the 「第 N 天」 HUD centered, flip on the right. No ratio, tone or profile
/// menu any more (#621).
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

    /// Back to the photo wall (FR-20.1).
    var onClose: () -> Void

    /// Both side groups get `.frame(maxWidth: .infinity, alignment:)` rather
    /// than a `Spacer` on each side of the HUD, so the two boxes stay the
    /// same width and the HUD stays on the true horizontal midline however
    /// many buttons sit on either side (D-1).
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                closeButton
                toolsToggleButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            dayHUD

            HStack(spacing: 0) {
                flipButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, CameraScreenLayoutMetrics.toolbarHorizontalInset)
    }

    // MARK: - Left: close (FR-20.1)

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .toolbarIcon(isActive: false, isOnPhoto: isOnPhoto)
                .rotatedChrome(model.viewfinderRotation)
        }
        .accessibilityLabel("回到照片牆")
        .accessibilityIdentifier("cameraCloseButton")
    }

    // MARK: - Left: tools toggle (issue #135)

    /// Opens/closes `CameraToolsCapsule`. A faint `CameraTheme.fill` disc
    /// behind the icon marks the expanded state.
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

    // MARK: - Center: day HUD (FR-20.2)

    /// Plain text, the day this photo will be (`CameraScreenModel.dayHUDText`).
    /// Not a button; it does not turn with the phone, like the profile chip
    /// it replaces.
    private var dayHUD: some View {
        Text(model.dayHUDText)
            .font(CameraTheme.toolFont(.subheadline).monospacedDigit())
            .lineLimit(1)
            .foregroundColor(isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink)
            .legibleOverPhoto(isOnPhoto)
            .padding(.horizontal, 6)
            .accessibilityIdentifier("cameraDayHUD")
    }

    // MARK: - Right: flip

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
            CameraToolbar(model: model, onClose: {})
            Spacer()
        }
    }
}
