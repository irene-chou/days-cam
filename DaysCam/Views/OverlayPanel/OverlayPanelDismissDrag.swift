import CoreGraphics

/// The numbers behind pulling the overlay panel down by its grabber to
/// collapse it (TASK-92), kept apart from the view so they can be tested —
/// the same split `GalleryDismissDrag` makes for the gallery (TASK-60).
enum OverlayPanelDismissDrag {
    /// Fraction of the panel's height the panel must have travelled down
    /// for a release to collapse it (92.4).
    static let closeFraction: CGFloat = 1 / 3

    /// Downward release speed (points per second) that collapses the panel
    /// even on a short pull — a flick (92.4).
    static let closeVelocity: CGFloat = 800

    /// How far the panel follows the finger: downward travel one to one;
    /// upward travel not at all — the panel never grows past its resting
    /// height (92.5).
    static func offset(forTranslation translation: CGFloat) -> CGFloat {
        max(0, translation)
    }

    /// Whether releasing at `offset` (from `offset(forTranslation:)`) with
    /// the finger moving at `velocity` points per second (positive = down)
    /// collapses the panel: past a third of `panelHeight`, or a downward
    /// flick faster than `closeVelocity` that has moved the panel at all.
    /// Otherwise the panel springs back.
    static func shouldClose(offset: CGFloat, velocity: CGFloat, panelHeight: CGFloat) -> Bool {
        offset > panelHeight * closeFraction || (offset > 0 && velocity > closeVelocity)
    }
}
