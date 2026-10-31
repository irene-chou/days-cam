import SwiftUI

/// Shown in place of the photo wall the first time a record is opened while
/// photo access was never asked (PRD 2.0 §7.1, D8 ⑤): explains the album sync
/// and asks the user to pick full access. Only "繼續" triggers the system
/// prompt; going back leaves without asking. `PhotoWallView` supplies the top
/// bar.
struct PhotoPermissionIntroView: View {
    /// The prompt is up: "繼續" is disabled so it asks only once.
    var isRequesting = false
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 46))
                    .foregroundColor(CameraTheme.active)
                    .accessibilityHidden(true)
                Text("讓紀錄和「照片」App 同步")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(CameraTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("每個紀錄會在「照片」App 建一本同名相簿。在那裡加入的照片會自動出現在這裡，並標出第幾天。照片本身不會被修改。")
                    .font(.system(size: 13.5))
                    .foregroundColor(CameraTheme.inkSecondary)
                    .lineSpacing(3)
                Text("接下來的系統詢問請選「允許完整存取」。只允許部分照片時，紀錄不會同步相簿。")
                    .font(.system(size: 12))
                    .foregroundColor(CameraTheme.inkTertiary)
                    .lineSpacing(2)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onContinue) {
                Text("繼續")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(CameraTheme.inkOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(CameraTheme.accent))
            }
            .buttonStyle(.plain)
            .disabled(isRequesting)
            .accessibilityIdentifier("permissionIntroContinue")
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoPermissionIntro")
    }
}

#Preview {
    PhotoPermissionIntroView {}.background(CameraTheme.background)
}
