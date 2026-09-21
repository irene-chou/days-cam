import SwiftUI

/// The app's only launch destination (PRD S-1).
///
/// Composes the viewfinder, the live overlay text, the permission guidance
/// screen, the display-settings entry and the shutter. The profile switcher
/// is layered on in a later task. All state and decisions live in
/// `CameraScreenModel`; this view only lays it out.
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
    }

    /// Settings-gear entry point (PRD S-1 → S-4, TASK-11's acceptance 11.1).
    /// The leading side is reserved for TASK-13's profile switcher.
    private var topBar: some View {
        HStack {
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
                    CameraPreviewView(session: model.cameraService.session)
                        .ignoresSafeArea()
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

                if model.cameraService.permission.needsGuidance {
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

    private var shutterBar: some View {
        HStack {
            Spacer()
            Button {
                // TASK-10 wires the actual capture action.
            } label: {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
            }
            .disabled(model.isShutterDisabled)
            .opacity(model.isShutterDisabled ? 0.4 : 1)
            Spacer()
        }
        .padding(.vertical, 24)
    }
}

#Preview {
    let store = ProfileStore()
    store.load()
    return CameraScreen(model: CameraScreenModel(cameraService: CameraService(), profileStore: store))
}
