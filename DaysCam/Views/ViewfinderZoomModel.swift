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

    private let currentFactor: () -> CGFloat
    private let applyFactor: (CGFloat) -> Void
    private let scheduleHide: (@escaping () -> Void) -> Void
    /// The zoom when the current pinch began; `nil` between pinches.
    private var pinchStartFactor: CGFloat?
    /// Bumped on every pinch change so an older pending hide does nothing.
    private var hideToken = 0

    init(currentFactor: @escaping () -> CGFloat,
         applyFactor: @escaping (CGFloat) -> Void,
         scheduleHide: @escaping (@escaping () -> Void) -> Void = { work in
             DispatchQueue.main.asyncAfter(deadline: .now() + ViewfinderZoomModel.indicatorLingerSeconds, execute: work)
         }) {
        self.currentFactor = currentFactor
        self.applyFactor = applyFactor
        self.scheduleHide = scheduleHide
    }

    /// One update of a pinch; `magnification` is the gesture's scale relative
    /// to where it began (1 = fingers unmoved). The requested zoom is the
    /// zoom at the pinch's start times that scale.
    func pinchChanged(magnification: CGFloat) {
        let start = pinchStartFactor ?? currentFactor()
        pinchStartFactor = start
        hideToken += 1
        isPinching = true
        isIndicatorVisible = true
        applyFactor(start * magnification)
    }

    /// The fingers lifted: the capsule fades out after `indicatorLingerSeconds`.
    func pinchEnded() {
        pinchStartFactor = nil
        isPinching = false
        hideToken += 1
        let token = hideToken
        scheduleHide { [weak self] in
            guard let self, self.hideToken == token else { return }
            self.isIndicatorVisible = false
        }
    }

    /// The capsule's text for a zoom factor, e.g. "2.3×".
    static func indicatorText(for factor: CGFloat) -> String {
        String(format: "%.1f×", Double(factor))
    }
}
