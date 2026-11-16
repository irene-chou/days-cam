import SwiftUI

/// The accent capsule that starts an export, shared by the batch and the
/// comparison sheets; `isBusy` shows a spinner before the title.
struct ExportPrimaryButton: View {
    let title: String
    let identifier: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().tint(CameraTheme.inkOnAccent)
                }
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
            }
            .foregroundColor(CameraTheme.inkOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(CameraTheme.accent))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// The quiet capsule for 取消 and the like.
struct ExportSecondaryButton: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(CameraTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(CameraTheme.fill))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// 隱藏文字 over 調整文字樣式 (#679): plain text buttons alike. While the text
/// is hidden by the sheet the first reads 顯示文字 and the style page is off.
struct ExportTextOptions: View {
    /// The text is hidden, by the sheet or by the record.
    let hidesText: Bool
    /// The record's 疊字 is off: it reads as already hidden and cannot be switched here (#718).
    let recordHidesText: Bool
    /// The sheet hides the text, which turns 調整文字樣式 off.
    let hidesTextChoice: Bool
    let hideIdentifier: String
    let styleIdentifier: String
    let onToggle: () -> Void
    let onStyle: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            textButton(hidesText ? "顯示文字" : "隱藏文字", identifier: hideIdentifier, action: onToggle)
                .disabled(recordHidesText)
                .opacity(recordHidesText ? 0.4 : 1)
            // 調整文字樣式 stays up for a record with 疊字 off, it is the way to turn it on.
            textButton("調整文字樣式", identifier: styleIdentifier, action: onStyle)
                .disabled(hidesTextChoice)
                .opacity(hidesTextChoice ? 0.4 : 1)
        }
    }

    private func textButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(CameraTheme.active)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}
