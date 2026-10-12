import CoreGraphics
import Foundation
import UIKit

/// The center-crop of a captured 4:3 photo to a `CaptureAspectRatio` (PRD
/// 0.2 FR-5.7′: "先裁再烘焙"). Only the window is computed here;
/// `OverlayRenderer.bake(..., cropRect:)` applies it in the same single
/// draw as the overlay (TASK-128; `crop(_:to:)` was removed in TASK-144
/// #498 so there is one crop path only).
///
/// Only ever crops, never upscales or pads: whichever side of the original
/// already fits the target ratio is left untouched, and the other side is
/// trimmed evenly from both edges. An image already at the target ratio
/// gets the full rect.
///
/// Agnostic about orientation: the crop is computed from pixel dimensions
/// alone, so it works the same whether the input is the sensor's native
/// landscape buffer or an already-rotated portrait image.
struct ImageCropper {
    init() {}

    /// The centered crop window for an image of `pixelSize` at `ratio`.
    ///
    /// Coordinates are in orientation-normalized pixels (the upright image,
    /// origin at the top-left), the same space `bake(..., cropRect:)` draws in. The
    /// rect is `croppedSize(from:to:)` centered in `pixelSize`; an image
    /// already at the target ratio yields the full `pixelSize` rect.
    static func cropRect(forPixelSize pixelSize: CGSize, ratio aspectRatio: CaptureAspectRatio) -> CGRect {
        let size = croppedSize(from: pixelSize, to: aspectRatio)
        return CGRect(x: (pixelSize.width - size.width) / 2,
                      y: (pixelSize.height - size.height) / 2,
                      width: size.width,
                      height: size.height)
    }

    /// The pixel size `pixelSize` becomes once cropped to `aspectRatio`.
    ///
    /// Exactly one side ever shrinks: if `aspectRatio` is squarer than the
    /// input, the long side is trimmed down to `shortSide / ratio`; if it is
    /// narrower, the short side is trimmed down to `longSide * ratio`. Equal
    /// ratios return `pixelSize` unchanged.
    ///
    /// Internal rather than private so the crop math can be unit tested
    /// directly, without rendering an actual bitmap.
    static func croppedSize(from pixelSize: CGSize, to aspectRatio: CaptureAspectRatio) -> CGSize {
        let shortSide = min(pixelSize.width, pixelSize.height)
        let longSide = max(pixelSize.width, pixelSize.height)
        guard shortSide > 0, longSide > 0 else { return pixelSize }

        let ratio = aspectRatio.shortToLongRatio
        // Never upscale: each candidate is only adopted when it is a
        // reduction of the corresponding original side.
        let newShortSide = min(shortSide, longSide * ratio)
        let newLongSide = min(longSide, shortSide / ratio)

        let isLandscape = pixelSize.width > pixelSize.height
        return isLandscape
            ? CGSize(width: newLongSide, height: newShortSide)
            : CGSize(width: newShortSide, height: newLongSide)
    }
}
