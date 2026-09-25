import SwiftUI

/// The camera screen's top bar (PRD 0.2 FR-7.2, D-1): flash and timer on the
/// left, the profile switcher centered, ratio/grid/flip on the right.
///
/// All state and actions come from `model` (`CameraScreenModel`); this view
/// only lays it out and never touches `CaptureSettingsStore`/`CameraService`
/// directly, the same separation `CameraScreen` already keeps.
struct CameraToolbar: View {
    @ObservedObject var model: CameraScreenModel

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                flashButton
                timerButton
            }
            Spacer(minLength: 12)
            profileChip
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                ratioButton
                gridButton
                flipButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Left: flash, timer

    private var flashButton: some View {
        Button(action: model.cycleFlash) {
            Image(systemName: flashIconName)
                .toolbarIcon(isActive: model.isFlashToolActive)
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
            .toolbarIcon(isActive: model.isTimerToolActive)
        }
        .accessibilityLabel(model.captureSettingsStore.timerSeconds == .off
                            ? "計時器：關"
                            : "計時器：\(model.captureSettingsStore.timerSeconds.rawValue) 秒")
    }

    // MARK: - Center: profile switcher (PRD 0.2 FR-7.11)

    /// Lists only names, in `ProfileStore`'s order, with the current one
    /// checked — no "管理設定檔" entry (that moves out to its own entry
    /// point in TASK-26).
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
            .foregroundColor(CameraTheme.ink)
        }
    }

    // MARK: - Right: ratio, grid, flip

    private var ratioButton: some View {
        Menu {
            ForEach(CaptureAspectRatio.allCases, id: \.self) { ratio in
                Button {
                    model.selectAspectRatio(ratio)
                } label: {
                    if ratio == model.captureSettingsStore.captureAspectRatio {
                        Label(ratio.displayLabel, systemImage: "checkmark")
                    } else {
                        Text(ratio.displayLabel)
                    }
                }
            }
        } label: {
            Text(model.captureSettingsStore.captureAspectRatio.displayLabel)
                .toolbarIcon(isActive: false)
        }
        .accessibilityLabel("比例")
    }

    private var gridButton: some View {
        Button(action: model.toggleGrid) {
            Image(systemName: "grid")
                .toolbarIcon(isActive: model.isGridToolActive)
        }
        .accessibilityLabel(model.isGridToolActive ? "格線：開" : "格線：關")
    }

    private var flipButton: some View {
        Button(action: model.switchCamera) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .toolbarIcon(isActive: false)
        }
        .disabled(model.isCaptureUnsupported)
        .opacity(model.isCaptureUnsupported ? 0.35 : 1)
        .accessibilityLabel("翻轉鏡頭")
    }
}

/// One SF Symbol/text label at the toolbar's fixed 38x38 tap target, colored
/// `active` when the tool it belongs to is on and `ink` otherwise (PRD 0.2
/// FR-7.10, FR-14.2 — no button background or border).
private struct ToolbarIconModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(isActive ? CameraTheme.active : CameraTheme.ink)
            .frame(width: 38, height: 38)
    }
}

private extension View {
    func toolbarIcon(isActive: Bool) -> some View {
        modifier(ToolbarIconModifier(isActive: isActive))
    }
}

private extension CaptureAspectRatio {
    /// The label the ratio button and its menu show (PRD 0.2 FR-7.7, D-1).
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
