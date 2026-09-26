import CoreGraphics
import Foundation

/// Adapts `CameraScreen`'s translation-based `OverlayDragHandling` calls to
/// `PositionTabModel.applyDrag(center:viewfinderSize:)`'s absolute-center
/// interface (PRD 0.2 FR-12, TASK-22/23/24 hand-off, #65).
///
/// `PositionTabModel` was written (TASK-24) knowing only a center point —
/// see its own doc comment — while `OverlayTextView`'s `DragGesture` (which
/// `CameraScreen`, `ui-shell`'s own territory, attaches) only ever reports a
/// *translation* from wherever the touch started (`DragGesture.Value
/// .translation`, unchanged and cumulative across every `onChanged` call of
/// one continuous gesture). This type is the one place that gap gets
/// bridged, so neither side has to know about the other's coordinate space.
///
/// `startCenter` is why this can't just be a pure function: the overlay's
/// on-screen center *before the current gesture began* has to be captured
/// once — from whatever `PositionTabModel.profile.position` already is — and
/// then reused for every subsequent callback of that same gesture. Re-deriving
/// it from `profile.position` on every call would double-count the
/// translation once a drag has already written back a `.custom` position via
/// `overlayDragChanged`.
///
/// This is my assumption for this card: `overlayDragChanged` only computes
/// and discards a center (a hook for a future live-preview, not wired to
/// anything today), and `overlayDragEnded` is the only call that actually
/// persists via `PositionTabModel.applyDrag` — `applyDrag` itself always
/// writes through immediately (no separate "preview" state), so persisting
/// on every `changed` call as well would spam `ProfileStore` on every pixel
/// of a drag and would still need this same start-center caching to stay
/// correct call to call. If `PositionTabModel` grows an actual preview-vs-
/// commit split later, this is the type to update.
@MainActor
final class PositionDragAdapter: OverlayDragHandling {
    private let positionTabModel: PositionTabModel

    /// The overlay's center, in viewfinder points, at the moment the current
    /// gesture started. `nil` between gestures (and briefly at the very
    /// start of one, before the first callback establishes it).
    private var startCenter: CGPoint?

    init(positionTabModel: PositionTabModel) {
        self.positionTabModel = positionTabModel
    }

    func overlayDragChanged(translation: CGSize, viewfinderSize: CGSize) {
        // See this type's own doc comment: not persisted, only computed so
        // `startCenter` gets established as early as the real gesture does.
        _ = center(translation: translation, viewfinderSize: viewfinderSize)
    }

    func overlayDragEnded(translation: CGSize, viewfinderSize: CGSize) {
        let resolvedCenter = center(translation: translation, viewfinderSize: viewfinderSize)
        positionTabModel.applyDrag(center: resolvedCenter, viewfinderSize: viewfinderSize)
        // Ready for the next, unrelated gesture to establish its own start
        // point from the position `applyDrag` just persisted.
        startCenter = nil
    }

    /// `startCenter + translation`, capturing `startCenter` from the
    /// overlay's current placement the first time this runs in a gesture.
    private func center(translation: CGSize, viewfinderSize: CGSize) -> CGPoint {
        let base = startCenter ?? currentCenter(viewfinderSize: viewfinderSize)
        startCenter = base
        return CGPoint(x: base.x + translation.width, y: base.y + translation.height)
    }

    /// The overlay's on-screen center for `positionTabModel.profile.position`
    /// at `viewfinderSize`, via the same `OverlayMetrics.origin` the render
    /// layer and `OverlayTextView` both call — so this always agrees with
    /// what is actually on screen.
    ///
    /// Passes `.zero` for the block size: this adapter only needs a
    /// reference *point*, and the real block's size is `OverlayTextView`'s
    /// private `@State`, not available here. `OverlayMetrics.origin` with a
    /// zero-size block collapses to exactly that reference point for every
    /// placement (an anchor's own margin point, or a `.custom` position's own
    /// unclamped fraction point), so this stays correct without needing it.
    private func currentCenter(viewfinderSize: CGSize) -> CGPoint {
        OverlayMetrics.origin(forBlockSize: .zero, in: viewfinderSize, placement: positionTabModel.profile.position)
    }
}
