import SwiftUI

/// Pinch-to-zoom state of the viewfinder (TASK-61, #274): the zoom a pinch
/// asks for and whether a pinch is under way (the overlay text must not follow
/// the fingers meanwhile).
///
/// Reads and sets the real zoom through closures, so `CameraService` stays the
/// only thing that clamps and applies it; tests inject fakes.
@MainActor
final class ViewfinderZoomModel: ObservableObject {
    /// True from the first change of a pinch until it ends.
    @Published private(set) var isPinching = false
    /// The zoom the latest pinch asked for, clamped to the camera's range.
    /// Next pinch starts from it rather than from the camera's own factor,
    /// which only follows asynchronously (issue #280). Only the preset bar
    /// observes this model for it; `CameraScreen` does not.
    @Published private(set) var requestedFactor: CGFloat

    private let zoomRange: () -> ZoomRange
    private let applyFactor: (CGFloat) -> Void
    private let applyPreset: (CGFloat) -> Void
    /// The zoom when the current pinch began; `nil` between pinches.
    private var pinchStartFactor: CGFloat?

    init(initialFactor: CGFloat = 1,
         zoomRange: @escaping () -> ZoomRange,
         applyFactor: @escaping (CGFloat) -> Void,
         applyPreset: @escaping (CGFloat) -> Void = { _ in }) {
        self.requestedFactor = initialFactor
        self.zoomRange = zoomRange
        self.applyFactor = applyFactor
        self.applyPreset = applyPreset
    }

    /// One update of a pinch; `magnification` is the gesture's scale relative
    /// to where it began (1 = fingers unmoved). The requested zoom is the
    /// zoom at the pinch's start times that scale.
    func pinchChanged(magnification: CGFloat) {
        let start = pinchStartFactor ?? requestedFactor
        pinchStartFactor = start
        // Assign only on a real change: `@Published` publishes on every
        // assignment, and a pinch calls this every frame (issue #280).
        if !isPinching { isPinching = true }
        let requested = start * magnification
        let clamped = zoomRange().clamp(requested)
        if requestedFactor != clamped { requestedFactor = clamped }
        applyFactor(requested)
    }

    /// The fingers lifted.
    func pinchEnded() {
        pinchStartFactor = nil
        if isPinching { isPinching = false }
    }

    /// A quick-zoom button was tapped (issue #279): the camera ramps to the
    /// preset, and the next pinch starts from it. All display factors.
    func selectPreset(_ preset: ZoomPreset) {
        let clamped = zoomRange().clamp(preset.displayFactor)
        if requestedFactor != clamped { requestedFactor = clamped }
        applyPreset(clamped)
    }

    /// The camera went back to 1× on its own (a front/back switch), so the
    /// next pinch must start there.
    func resetRequestedFactor() {
        if requestedFactor != 1 { requestedFactor = 1 }
    }

    /// The zoom text for a zoom factor, e.g. "2.3×".
    nonisolated static func indicatorText(for factor: CGFloat) -> String {
        String(format: "%.1f×", Double(factor))
    }
}
