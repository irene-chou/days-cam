import SwiftUI

/// Draws the film date stamp over the viewfinder (TASK-153 #522).
///
/// `frameSize` is the viewfinder's crop box, treated as the finished photo:
/// size, margins and direction all come from `FilmDateStamp` and are drawn by
/// `FilmDateRenderer`, the same code that bakes the photo, so nothing here
/// has a number of its own. Never takes touches.
struct FilmDateStampView: View {
    /// The stamp to draw, or `nil` for nothing.
    let stamp: FilmDateStamp?
    /// The size of the box the stamp is placed in, standing in for the photo.
    let frameSize: CGSize

    var body: some View {
        Canvas { context, size in
            guard let stamp else { return }
            context.withCGContext { cgContext in
                FilmDateRenderer.draw(stamp, in: cgContext, canvasSize: size)
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .allowsHitTesting(false)
        // A decorative drawing, but UI tests need its frame (the viewfinder box).
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(stamp == nil)
        .accessibilityIdentifier("filmDateStamp")
    }
}
