import SwiftUI

/// The state a `ToastView` renders: the confirmation message and an optional
/// thumbnail of the photo that was just saved (PRD FR-5.4).
///
/// Ownership of *when* a toast appears and how long it stays up belongs to the
/// screen that triggers it (a screen-level view model, e.g. `CameraScreenModel`
/// from TASK-08/10); this type only carries what to show.
struct ToastState: Equatable {
    /// The confirmation text, e.g. "已儲存".
    let message: String
    /// A small preview of the saved photo, if one is available.
    let thumbnail: UIImage?

    static func == (lhs: ToastState, rhs: ToastState) -> Bool {
        lhs.message == rhs.message && lhs.thumbnail === rhs.thumbnail
    }
}

/// A transient confirmation banner shown after a successful capture (PRD FR-5.4).
///
/// Pure presentation: it renders whatever `state` it is given and does not
/// decide when to appear, disappear, or how long to stay up — that timing
/// belongs to the screen-level view model so it stays testable without a real
/// clock. Never intercepts touches, so it never blocks the shutter underneath it.
struct ToastView: View {
    let state: ToastState

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = state.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text(state.message)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.75))
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.message)
    }
}

#Preview("With thumbnail") {
    ZStack(alignment: .bottomLeading) {
        Color.gray.opacity(0.2)
        ToastView(state: ToastState(message: "已儲存", thumbnail: nil))
            .padding()
    }
}

#Preview("Error message") {
    ZStack(alignment: .bottomLeading) {
        Color.gray.opacity(0.2)
        ToastView(state: ToastState(message: "設定檔讀取失敗，已重設。", thumbnail: nil))
            .padding()
    }
}
