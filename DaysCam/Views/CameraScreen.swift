import SwiftUI

/// The app's only launch destination (PRD S-1).
///
/// Composes the viewfinder, the overlay text, the shutter, the profile
/// switcher and the display-settings entry point. Currently a placeholder;
/// TASK-07 onwards fill it in.
///
/// Ownership: this file is the single composition point for TASK-08, 10, 11,
/// 12, 13 and 14. Only the camera-line developer edits it.
struct CameraScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
            Text("Days Cam")
                .font(.title)
        }
        .padding()
    }
}

#Preview {
    CameraScreen()
}
