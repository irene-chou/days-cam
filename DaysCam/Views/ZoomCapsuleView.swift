import SwiftUI

/// The magnification capsule (TASK-61, #274): centered near the bottom of the
/// picture, shown while pinching and for a second after. Never takes touches.
///
/// Observes `ViewfinderZoomModel` on its own so the per-frame zoom changes
/// redraw this small view only, never `CameraScreen` (issue #280).
struct ZoomCapsuleView: View {
    @ObservedObject var zoom: ViewfinderZoomModel
    /// The picture's rectangle in screen coordinates.
    let pictureFrame: CGRect

    var body: some View {
        let visible = zoom.isIndicatorVisible
        ZStack {
            if visible {
                Text(ViewfinderZoomModel.indicatorText(for: zoom.requestedFactor))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .position(x: pictureFrame.midX, y: pictureFrame.maxY - 24)
                    .accessibilityIdentifier("zoomCapsule")
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: visible ? 0.1 : 0.3), value: visible)
        .allowsHitTesting(false)
    }
}
