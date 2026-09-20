import SwiftUI

/// The state a `ToastView` renders: the confirmation message and an optional
/// thumbnail of the photo that was just saved (PRD FR-5.4).
///
/// Scoped to the save-confirmation toast only. The other PRD §7.3 error
/// messages need a dismiss button or must stay up until the user acts, so
/// they belong on SwiftUI's native `.alert`, not this transient banner.
///
/// `id` exists purely so a caller can re-trigger the appear animation for two
/// back-to-back toasts with identical text (e.g. two saves in a row before a
/// thumbnail is ready): give each occurrence a fresh `id` and drive
/// `.animation(value:)` off it, since `message`/`thumbnail` alone could
/// compare equal.
///
/// Ownership of *when* a toast appears and how long it stays up belongs to the
/// screen that triggers it (a screen-level view model, e.g. `CameraScreenModel`
/// from TASK-08/10); this type only carries what to show.
struct ToastState: Identifiable, Equatable {
    let id: UUID
    /// The confirmation text, e.g. "已儲存".
    let message: String
    /// A small preview of the saved photo, if one is available.
    let thumbnail: UIImage?

    init(message: String, thumbnail: UIImage? = nil, id: UUID = UUID()) {
        self.id = id
        self.message = message
        self.thumbnail = thumbnail
    }

    static func == (lhs: ToastState, rhs: ToastState) -> Bool {
        lhs.id == rhs.id
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

#Preview("Text only") {
    ZStack(alignment: .bottomLeading) {
        Color.gray.opacity(0.2)
        ToastView(state: ToastState(message: "已儲存"))
            .padding()
    }
}

#Preview("With thumbnail") {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 88, height: 88))
    let swatch = renderer.image { context in
        UIColor.systemOrange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 88, height: 88))
    }
    return ZStack(alignment: .bottomLeading) {
        Color.gray.opacity(0.2)
        ToastView(state: ToastState(message: "已儲存", thumbnail: swatch))
            .padding()
    }
}
