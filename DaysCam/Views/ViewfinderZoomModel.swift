import SwiftUI

/// Pinch-to-zoom state of the viewfinder (TASK-61, #274): the zoom a pinch
/// asks for, whether a pinch is under way (the overlay text must not follow
/// the fingers meanwhile) and whether the magnification capsule is showing.
///
/// Reads and sets the real zoom through closures, so `CameraService` stays the
/// only thing that clamps and applies it; tests inject fakes.
@MainActor
final class ViewfinderZoomModel: ObservableObject {
    /// How long the capsule stays after the fingers lift.
    static let indicatorLingerSeconds: TimeInterval = 1

    /// True from the first change of a pinch until it ends.
    @Published private(set) var isPinching = false
    /// True while the capsule should show: during a pinch and shortly after.
    @Published private(set) var isIndicatorVisible = false
    /// The zoom the latest pinch asked for, clamped to the camera's range.
    /// Next pinch starts from it rather than from the camera's own factor,
    /// which only follows asynchronously (issue #280). Only the capsule
    /// observes this model for it; `CameraScreen` does not.
    @Published private(set) var requestedFactor: CGFloat

    private let zoomRange: () -> ZoomRange
    private let applyFactor: (CGFloat) -> Void
    private let scheduleHide: (@escaping () -> Void) -> Void
    /// The zoom when the current pinch began; `nil` between pinches.
    private var pinchStartFactor: CGFloat?
    /// Bumped on every pinch change so an older pending hide does nothing.
    private var hideToken = 0

    init(initialFactor: CGFloat = 1,
         zoomRange: @escaping () -> ZoomRange,
         applyFactor: @escaping (CGFloat) -> Void,
         scheduleHide: @escaping (@escaping () -> Void) -> Void = { work in
             DispatchQueue.main.asyncAfter(deadline: .now() + ViewfinderZoomModel.indicatorLingerSeconds, execute: work)
         }) {
        self.requestedFactor = initialFactor
        self.zoomRange = zoomRange
        self.applyFactor = applyFactor
        self.scheduleHide = scheduleHide
    }

    /// One update of a pinch; `magnification` is the gesture's scale relative
    /// to where it began (1 = fingers unmoved). The requested zoom is the
    /// zoom at the pinch's start times that scale.
    func pinchChanged(magnification: CGFloat) {
        let start = pinchStartFactor ?? requestedFactor
        pinchStartFactor = start
        hideToken += 1
        // Assign only on a real change: `@Published` publishes on every
        // assignment, and a pinch calls this every frame (issue #280).
        if !isPinching { isPinching = true }
        if !isIndicatorVisible { isIndicatorVisible = true }
        let requested = start * magnification
        let clamped = zoomRange().clamp(requested)
        if requestedFactor != clamped { requestedFactor = clamped }
        applyFactor(requested)
    }

    /// The fingers lifted: the capsule fades out after `indicatorLingerSeconds`.
    func pinchEnded() {
        pinchStartFactor = nil
        if isPinching { isPinching = false }
        hideToken += 1
        let token = hideToken
        scheduleHide { [weak self] in
            guard let self, self.hideToken == token else { return }
            if self.isIndicatorVisible { self.isIndicatorVisible = false }
        }
    }

    /// The camera went back to 1× on its own (a front/back switch), so the
    /// next pinch must start there.
    func resetRequestedFactor() {
        if requestedFactor != 1 { requestedFactor = 1 }
    }

    /// The capsule's text for a zoom factor, e.g. "2.3×".
    static func indicatorText(for factor: CGFloat) -> String {
        String(format: "%.1f×", Double(factor))
    }
}
