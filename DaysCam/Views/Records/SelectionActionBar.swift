import SwiftUI

/// The bottom bar of icon-over-title actions (PRD 2.0 FR-17.13, D8): the
/// wall's selection bar and the viewer's 匯出｜刪除 (#679), so both look the
/// same. Each action takes an equal share of the width.
struct SelectionActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .overlay(alignment: .top) {
                Rectangle().fill(CameraTheme.ink.opacity(0.08)).frame(height: 1)
            }
    }
}

/// One action of a `SelectionActionBar`: a 19pt symbol over an 11.5pt bold
/// title, dimmed while pressed or disabled.
struct SelectionActionButton: View {
    /// D8's #D2422C for 刪除.
    static let destructive = Color(red: 0xD2 / 255, green: 0x42 / 255, blue: 0x2C / 255)

    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 19))
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(SelectionActionStyle())
    }
}

/// Dims a selection-bar action while pressed or disabled.
private struct SelectionActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.35)
    }
}
