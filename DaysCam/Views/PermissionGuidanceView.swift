import SwiftUI
import UIKit

/// PRD S-5: covers the viewfinder area when camera permission is denied or
/// restricted (PRD §2.3). Pure presentation — `CameraScreen` decides when to
/// show it, based on `CameraService.permission.needsGuidance`.
struct PermissionGuidanceView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 32))
                .foregroundColor(CameraTheme.permissionInkSecondary)
            Text("需要相機權限")
                .font(.headline)
            Text("DaysCam 需要相機權限才能拍照並疊上天數。")
                .font(.subheadline)
                .foregroundColor(CameraTheme.permissionInkSecondary)
                .multilineTextAlignment(.center)
            Button("前往設定") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(CameraTheme.active)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CameraTheme.permissionBackground)
        .foregroundColor(CameraTheme.permissionInk)
    }
}

#Preview("Light") {
    ZStack {
        Color.gray
        PermissionGuidanceView()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    ZStack {
        Color.gray
        PermissionGuidanceView()
    }
    .preferredColorScheme(.dark)
}
