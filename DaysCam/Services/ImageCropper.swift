import CoreGraphics
import Foundation
import UIKit

/// Center-crops a captured 4:3 photo down to a `CaptureAspectRatio`, before
/// the overlay is baked in (PRD 0.2 FR-5.7′: "先裁再烘焙").
///
/// Only ever crops, never upscales or pads: whichever side of the original
/// already fits the target ratio is left untouched, and the other side is
/// trimmed evenly from both edges. An image already at the target ratio is
/// handed back unchanged.
///
/// Agnostic about orientation: the crop is computed from pixel dimensions
/// alone, so it works the same whether the input is the sensor's native
/// landscape buffer or an already-rotated portrait image.
struct ImageCropper {
    init() {}

    /// Crops `image` to `aspectRatio`, centered.
    ///
    /// The result is always upright (`imageOrientation == .up`) and at
    /// scale 1, the same normalisation `OverlayRenderer.bake` performs, so
    /// feeding this straight into `bake` draws the image exactly once.
    func crop(_ image: UIImage, to aspectRatio: CaptureAspectRatio) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return image }

        let cropSize = Self.croppedSize(from: pixelSize, to: aspectRatio)
        guard cropSize.width < pixelSize.width || cropSize.height < pixelSize.height else {
            // Already the target ratio (19.7): nothing to draw, hand the
            // original back untouched.
            return image
        }

        let origin = CGPoint(x: (pixelSize.width - cropSize.width) / 2,
                             y: (pixelSize.height - cropSize.height) / 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: cropSize, format: format)
        return renderer.image { _ in
            // Draw the whole image at its normalized pixel size, shifted so
            // the crop window lands at the context's origin — the same
            // "draw into a pixel-sized rect" idiom `OverlayRenderer.bake`
            // uses to normalize orientation and scale in one call.
            image.draw(in: CGRect(x: -origin.x, y: -origin.y,
                                  width: pixelSize.width, height: pixelSize.height))
        }
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
