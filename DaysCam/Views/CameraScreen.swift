import SwiftUI

/// The app's only launch destination (PRD S-1).
///
/// Composes the viewfinder, the live overlay text, the permission guidance
/// screen, the display-settings entry, the profile switcher, the shutter,
/// the save-confirmation toast and the data-recovery alert (PRD §7.3). All
/// state and decisions live in `CameraScreenModel`; this view only lays it
/// out.
struct CameraScreen: View {
    @ObservedObject var model: CameraScreenModel

    var body: some View {
        VStack(spacing: 0) {
            viewfinder
                // Sensor-native 4:3 ratio (PRD FR-5.7, FR-6.3), independent of
                // the device's actual screen ratio.
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .top) { topBar }

            shutterBar
        }
        .background(Color.black)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
        .sheet(isPresented: displaySettingsBinding) {
            // `model.displaySettingsModel` is the instance cached when the
            // sheet opened, not rebuilt on every access — see its own doc
            // comment for why that matters.
            if let displaySettingsModel = model.displaySettingsModel {
                DisplaySettingsSheet(model: displaySettingsModel)
            }
        }
        .sheet(isPresented: $model.isProfileListPresented) {
            NavigationStack {
                ProfileListView(model: model.profileListModel)
            }
        }
        .overlay(alignment: .bottomLeading) { toastOverlay }
        .alert("設定檔讀取失敗，已重設。", isPresented: corruptionAlertBinding) {
            Button("好") { model.dismissCorruptionRecoveredAlert() }
        }
        .alert("無法完成拍照", isPresented: captureErrorBinding, presenting: model.captureError) { error in
            if error.showsSettingsAction {
                Button("前往設定") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            Button("好", role: .cancel) { model.dismissCaptureError() }
        } message: { error in
            Text(error.message)
        }
    }

    /// "已儲存" confirmation (PRD FR-5.4). Positioned above the shutter bar
    /// rather than inside the viewfinder, so it never competes with the
    /// overlay text for the same bottom-leading corner.
    @ViewBuilder
    private var toastOverlay: some View {
        if let toastState = model.toastState {
            ToastView(state: toastState)
                .padding(.leading, 16)
                .padding(.bottom, 96)
                .transition(.opacity)
                .animation(.easeInOut, value: toastState.id)
        }
    }

    /// `model.showsCorruptionRecoveredAlert` as a `Binding` for `.alert`, same
    /// dismiss-clears-model-state pattern as `displaySettingsBinding`.
    private var corruptionAlertBinding: Binding<Bool> {
        Binding(get: { model.showsCorruptionRecoveredAlert },
                set: { isPresented in if !isPresented { model.dismissCorruptionRecoveredAlert() } })
    }

    /// `model.captureError` as a `Binding<Bool>` for `.alert(isPresented:presenting:)`.
    private var captureErrorBinding: Binding<Bool> {
        Binding(get: { model.captureError != nil },
                set: { isPresented in if !isPresented { model.dismissCaptureError() } })
    }

    /// Profile switcher (leading, PRD FR-1.4, TASK-13) and settings-gear
    /// entry point (trailing, PRD S-1 → S-4, TASK-11's acceptance 11.1).
    private var topBar: some View {
        HStack {
            profileSwitcher
            Spacer()
            Button {
                model.presentDisplaySettings()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Lists every profile plus a "管理設定檔" entry (PRD FR-1.4). Tapping a
    /// profile switches to it without leaving the camera screen; the overlay
    /// updates from the same `model.overlayText` the viewfinder already reads.
    private var profileSwitcher: some View {
        Menu {
            ForEach(model.profiles) { profile in
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
            Divider()
            Button("管理設定檔") {
                model.presentProfileManagement()
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.currentProfileName)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.4), in: Capsule())
        }
    }

    /// `model.isDisplaySettingsPresented` as a `Binding` for `.sheet`:
    /// dismissing the sheet (swipe-down, tapping outside) must also clear the
    /// model's state, not just the SwiftUI-owned presentation flag — same
    /// pattern as `ProfileListView.editorBinding`.
    private var displaySettingsBinding: Binding<Bool> {
        Binding(get: { model.isDisplaySettingsPresented },
                set: { isPresented in if !isPresented { model.dismissDisplaySettings() } })
    }

    @ViewBuilder
    private var viewfinder: some View {
        GeometryReader { proxy in
            ZStack {
                if model.showsPlaceholder {
                    placeholderBackground
                } else {
                    // Deliberately not `.ignoresSafeArea()`: the container is
                    // already sized to exactly the 4:3 viewfinder rectangle,
                    // and letting the preview layer grow into the safe area
                    // would make it taller than the `GeometryReader` frame
                    // `OverlayTextView` below measures — the overlay would
                    // sit against a boundary the picture doesn't actually
                    // end at (code review finding, PRD FR-6.1/6.3).
                    CameraPreviewView(session: model.cameraService.session)
                }

                // Overlay text tracks the viewfinder's own size (not the
                // screen's), matching FR-6.1's requirement that the preview
                // and the eventual baked photo agree.
                OverlayTextView(text: model.overlayText,
                                theme: model.overlayTheme,
                                position: model.overlayPosition,
                                frameSize: proxy.size)

                if let statusMessage = model.statusMessage {
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                }

                if model.needsPermissionGuidance {
                    PermissionGuidanceView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The simulator/placeholder background (PRD §2.4): a solid color plus a
    /// label so it is unmistakably not a live picture.
    private var placeholderBackground: some View {
        ZStack {
            Color(white: 0.15)
            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                Text(CameraScreenModel.simulatorPlaceholderText)
                    .font(.subheadline)
            }
            .foregroundColor(.white.opacity(0.8))
        }
    }

    /// Centers the shutter regardless of `switchCameraButton`'s width, by
    /// layering rather than sharing one `HStack` with it (PRD FR-5.8).
    private var shutterBar: some View {
        ZStack {
            HStack {
                Spacer()
                Button {
                    model.capturePhoto()
                } label: {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 72, height: 72)
                }
                .disabled(model.isShutterDisabled)
                .opacity(model.isShutterDisabled ? 0.4 : 1)
                Spacer()
            }
            HStack {
                Spacer()
                switchCameraButton
                    .padding(.trailing, 24)
            }
        }
        .padding(.vertical, 24)
    }

    /// Front/back camera toggle (PRD FR-5.8, TASK-07's acceptance 7.10/7.11).
    private var switchCameraButton: some View {
        Button {
            model.switchCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(14)
                .background(.black.opacity(0.4), in: Circle())
        }
        .disabled(model.isCaptureUnsupported)
        .opacity(model.isCaptureUnsupported ? 0.4 : 1)
    }
}

#Preview {
    let store = ProfileStore()
    store.load()
    return CameraScreen(model: CameraScreenModel(cameraService: CameraService(), profileStore: store))
}
