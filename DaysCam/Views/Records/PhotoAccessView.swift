import SwiftUI
import UIKit

/// Replaces the photo wall when photo access is denied or restricted
/// (PRD 2.0 §7.4, laid out like 0.2 FR-15.8: lock, title, reason, button).
/// Pure presentation; `PhotoWallView` decides when to show it and re-reads the
/// authorization when the app returns from Settings.
struct PhotoAccessView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundColor(CameraTheme.inkSecondary)
            Text("需要相簿權限")
                .font(.headline)
                .foregroundColor(CameraTheme.ink)
            Text("DaysCam 需要讀取相簿，才能顯示每張照片是第幾天")
                .font(.subheadline)
                .foregroundColor(CameraTheme.inkSecondary)
                .multilineTextAlignment(.center)
            Button("前往設定") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(CameraTheme.active)
            .padding(.top, 4)
            .accessibilityIdentifier("photoAccessSettingsButton")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoAccessDenied")
    }
}

#Preview {
    PhotoAccessView().background(CameraTheme.background)
}
