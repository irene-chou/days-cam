import SwiftUI
import UIKit

/// A UIKit long-press recognizer laid over one profile row (TASK-103, #412).
///
/// SwiftUI's `LongPressGesture.sequenced(before: DragGesture)` on a `List`
/// row claimed every touch from the moment it landed, so the list's own
/// swipe actions and scrolling almost never got to run (#412). A
/// `UILongPressGestureRecognizer` behaves the way the row needs: until the
/// finger has rested for `minimumPressDuration` it stays out of the way —
/// a horizontal pan goes to the swipe action, a vertical one scrolls the
/// list, a quick lift is a tap — and once it has recognized it keeps
/// reporting the finger's position until release, which is the reorder
/// drag (TASK-58). A tap recognizer on the same view carries the row's
/// primary action; it is cancelled automatically when the long press wins.
///
/// The view is not an accessibility element: the SwiftUI row keeps its
/// label, button trait and action for VoiceOver.
struct RowLongPressDrag: UIViewRepresentable {
    /// The finger has rested long enough: the row lifts.
    var onBegan: () -> Void
    /// The finger moved while lifted; the value is its vertical travel in
    /// window points since `onBegan`.
    var onChanged: (CGFloat) -> Void
    /// The finger lifted (or the gesture was cancelled) after a lift.
    var onEnded: () -> Void
    /// A plain tap on the row.
    var onTap: () -> Void

    static let minimumPressDuration: TimeInterval = 0.3
    static let allowableMovement: CGFloat = 10

    func makeUIView(context: Context) -> RowGestureView {
        let view = RowGestureView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let longPress = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = Self.minimumPressDuration
        longPress.allowableMovement = Self.allowableMovement
        view.addGestureRecognizer(longPress)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: RowGestureView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: RowLongPressDrag
        private var startY: CGFloat = 0

        init(parent: RowLongPressDrag) { self.parent = parent }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            let y = recognizer.location(in: nil).y
            switch recognizer.state {
            case .began:
                startY = y
                parent.onBegan()
            case .changed:
                parent.onChanged(y - startY)
            case .ended, .cancelled, .failed:
                parent.onEnded()
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.onTap()
        }
    }
}

/// The transparent view the recognizers live on. It takes the touch so the
/// recognizers see it; recognizers on its superviews — the list cell's
/// swipe actions, the scroll view's pan — see the same touch, as UIKit
/// delivers touches up the whole chain.
final class RowGestureView: UIView {}
