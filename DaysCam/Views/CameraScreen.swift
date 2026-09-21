import SwiftUI

/// The app's only launch destination (PRD S-1).
///
/// Composes the viewfinder, the permission guidance screen and the shutter.
/// TASK-08 onward add the overlay text, the display-settings entry and the
/// profile switcher on top of this. All state and decisions live in
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

            shutterBar
        }
        .background(Color.black)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    @ViewBuilder
    private var viewfinder: some View {
        ZStack {
            if model.showsPlaceholder {
                placeholderBackground
            } else {
                CameraPreviewView(session: model.cameraService.session)
                    .ignoresSafeArea()
            }

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
    CameraScreen(model: CameraScreenModel(cameraService: CameraService()))
}
