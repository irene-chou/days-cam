import Foundation
import UIKit

/// Bakes already-rendered text into the pixels of an image.
///
/// Deliberately agnostic about where the image came from: a live capture today,
/// a file loaded from disk tomorrow. It takes an image, a finished string and a
/// style, and nothing else — it never inspects timestamps or metadata, and it
/// knows nothing about profiles or the camera (PRD §6.5.4).
struct OverlayRenderer {
    init() {}

    /// Draws `text` into `image`'s pixels and returns the result.
    ///
    /// Returns nil only when the drawing itself fails; the caller treats nil as
    /// a baking failure and does not save the photo.
    func bake(image: UIImage, text: String, theme: OverlayTheme, position: OverlayPosition) -> UIImage? {
        #warning("OverlayRenderer.bake is a stage-A placeholder; TASK-09 must replace it")
        // Returns the untouched image rather than nil on purpose: nil means
        // "baking failed" to TASK-10 and would block the whole save path, so
        // the placeholder would look like a crash instead of a missing overlay.
        return image
    }
}
