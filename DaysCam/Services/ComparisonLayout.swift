import UIKit
import Vision

/// Pure layout rules for the comparison image (#740): which way the two photos
/// are laid out, which one is cropped to what ratio, where the crop sits and
/// how large the tiles come out.
///
/// Sizes are oriented pixel sizes (what the viewer sees). Ratios are width over
/// height; a ratio above 1 is landscape, anything else portrait (square included).
enum ComparisonLayout {
    /// How the two tiles sit next to each other.
    enum Arrangement: Equatable {
        /// First on the left, second on the right.
        case sideBySide
        /// First on top, second below.
        case stacked
    }

    /// What to do with the two photos.
    struct Plan: Equatable {
        let arrangement: Arrangement
        /// The ratio the first photo is cropped to; `nil` keeps it whole.
        let firstCrop: CGFloat?
        /// The ratio the second photo is cropped to; `nil` keeps it whole.
        let secondCrop: CGFloat?
    }

    /// Ratios within this fraction of each other count as the same.
    static let sameRatioTolerance: CGFloat = 0.01
    /// The longest side of an exported tile row or column.
    static let exportMaxSide: CGFloat = 2160

    /// Finds the focus of a photo, as a normalized rect with a top-left origin;
    /// `nil` when there is none.
    typealias Focus = (UIImage) -> CGRect?

    /// Whether two ratios are the same within `sameRatioTolerance`.
    static func isSameRatio(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        guard lhs > 0, rhs > 0 else { return false }
        return abs(lhs / rhs - 1) <= sameRatioTolerance
    }

    /// The arrangement and crops for photos of `first` and `second` size.
    /// Both landscape: stacked, the wider one cut at the sides to the other's
    /// ratio. Both portrait: side by side, the narrower one cut top and bottom
    /// to the other's ratio. One of each: both 1:1, side by side.
    static func plan(first: CGSize, second: CGSize) -> Plan {
        let firstRatio = first.width / max(first.height, 1)
        let secondRatio = second.width / max(second.height, 1)
        let firstLandscape = firstRatio > 1
        let secondLandscape = secondRatio > 1
        if firstLandscape != secondLandscape {
            return Plan(arrangement: .sideBySide,
                        firstCrop: isSameRatio(firstRatio, 1) ? nil : 1,
                        secondCrop: isSameRatio(secondRatio, 1) ? nil : 1)
        }
        let arrangement: Arrangement = firstLandscape ? .stacked : .sideBySide
        if isSameRatio(firstRatio, secondRatio) {
            return Plan(arrangement: arrangement, firstCrop: nil, secondCrop: nil)
        }
        // Landscape crops the wider one, portrait the narrower one.
        let firstIsCropped = firstLandscape ? firstRatio > secondRatio : firstRatio < secondRatio
        return Plan(arrangement: arrangement,
                    firstCrop: firstIsCropped ? secondRatio : nil,
                    secondCrop: firstIsCropped ? nil : firstRatio)
    }

    /// The largest rect of `ratio` inside `size`, centered on `focus` (a
    /// normalized top-left rect) and clamped into the image; centered when
    /// `focus` is `nil`. Whole pixels.
    static func cropRect(size: CGSize, ratio: CGFloat, focus: CGRect?) -> CGRect {
        guard size.width >= 1, size.height >= 1, ratio > 0 else { return CGRect(origin: .zero, size: size) }
        var width = size.width
        var height = size.height
        if size.width / size.height > ratio {
            width = max(1, (size.height * ratio).rounded())
        } else {
            height = max(1, (size.width / ratio).rounded())
        }
        width = min(width, size.width)
        height = min(height, size.height)
        let centerX = focus.map { $0.midX * size.width } ?? size.width / 2
        let centerY = focus.map { $0.midY * size.height } ?? size.height / 2
        let originX = min(max(centerX - width / 2, 0), size.width - width).rounded()
        let originY = min(max(centerY - height / 2, 0), size.height - height).rounded()
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    /// The pixel size of each tile after cropping to `firstCrop` and
    /// `secondCrop`: side by side at one height, stacked at one width, that
    /// being the smaller of the two cropped sizes and at most `maxSide`.
    static func tileSizes(first: CGSize, second: CGSize, arrangement: Arrangement,
                          maxSide: CGFloat) -> (first: CGSize, second: CGSize) {
        switch arrangement {
        case .sideBySide:
            let height = min(first.height, second.height, maxSide).rounded(.down)
            return (scaled(first, height: height), scaled(second, height: height))
        case .stacked:
            let width = min(first.width, second.width, maxSide).rounded(.down)
            return (scaled(first, width: width), scaled(second, width: width))
        }
    }

    private static func scaled(_ size: CGSize, height: CGFloat) -> CGSize {
        CGSize(width: max(1, (size.width * height / size.height).rounded()), height: height)
    }

    private static func scaled(_ size: CGSize, width: CGFloat) -> CGSize {
        CGSize(width: width, height: max(1, (size.height * width / size.width).rounded()))
    }

    /// The default focus: the union of the attention-based saliency regions
    /// Vision finds, `nil` when it finds none or fails.
    static let saliencyFocus: Focus = { image in
        guard let cgImage = downscaled(image, longSide: 512)?.cgImage else { return nil }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let objects = request.results?.first?.salientObjects, !objects.isEmpty else { return nil }
        let union = objects.map(\.boundingBox).dropFirst().reduce(objects[0].boundingBox) { $0.union($1) }
        guard union.width > 0, union.height > 0 else { return nil }
        // Vision's origin is the lower left.
        return CGRect(x: union.minX, y: 1 - union.maxY, width: union.width, height: union.height)
    }

    private static func downscaled(_ image: UIImage, longSide: CGFloat) -> UIImage? {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width >= 1, height >= 1 else { return nil }
        let factor = min(1, longSide / max(width, height))
        let size = CGSize(width: max(1, (width * factor).rounded()), height: max(1, (height * factor).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
