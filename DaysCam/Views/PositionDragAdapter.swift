import CoreGraphics
import Foundation

/// Bridges `OverlayPanelModel.overlayDragHandler`'s `OverlayDragHandling`
/// calls to `PositionTabModel.applyDrag(center:viewfinderSize:)` (PRD 0.2
/// FR-12, TASK-22/23/24 hand-off, #65/#68).
///
/// As of #68, `OverlayTextView` itself now tracks the finger and keeps the
/// block inside the 4% margin with local `@State` — see its own
/// `clampedDragCenter` — and reports the block's already-clamped center on
/// every callback. That leaves nothing here to convert: `center` is already
/// exactly what `applyDrag` needs. (Before #68 this type recomputed a start
/// center from `positionTabModel.profile.position` using a zero-size
/// reference block, which was wrong for `.anchor` placements — see #68's own
/// issue for the bug. `OverlayTextView` computing it from its own real
/// `blockSize` is what fixed that; nothing needed fixing on this side once
/// that landed, which is why this type shrank rather than grew.)
@MainActor
final class PositionDragAdapter: OverlayDragHandling {
    private let positionTabModel: PositionTabModel

    init(positionTabModel: PositionTabModel) {
        self.positionTabModel = positionTabModel
    }

    /// No-op: `OverlayTextView` already moves the block live on its own
    /// (#68), so nothing here needs a running update. Kept — rather than
    /// dropping this from `OverlayDragHandling` — so the protocol still
    /// mirrors a gesture's two phases, leaving a hook for the model layer if
    /// a future feature (e.g. showing the `.custom` percentage while
    /// dragging) needs one.
    func overlayDragChanged(center: CGPoint, viewfinderSize: CGSize) {}

    /// Persists `center` as the profile's new `.custom` position.
    func overlayDragEnded(center: CGPoint, viewfinderSize: CGSize) {
        positionTabModel.applyDrag(center: center, viewfinderSize: viewfinderSize)
    }
}
