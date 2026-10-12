import CoreGraphics
import UIKit
import XCTest
@testable import DaysCam

/// Covers TASK-19 acceptance 19.5, 19.6, 19.7 (center-crop math, PRD 0.2
/// FR-5.7′) and 19.11 (margin computed from the *cropped* short edge,
/// PRD 0.2 FR-5.9) — the latter only needs `ImageCropper`'s output size fed
/// into `OverlayMetrics`, which already takes the frame size it is given
/// (`OverlayRenderer`/`OverlayMetrics` themselves are core-style's files and
/// are not touched here).
final class ImageCropperTests: XCTestCase {

    private let cropper = ImageCropper()

    /// A solid-color image at an exact pixel size, scale 1 — the same
    /// construction `OverlayRendererTests` uses, so no real camera decode is
    /// needed.
    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pixelSize(of image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    // MARK: - 19.5: 4032x3024 landscape cropped to 1:1

    func test_landscape4032x3024_croppedToOneByOne_is3024Square_horizontallyCentered() {
        let size = ImageCropper.croppedSize(from: CGSize(width: 4032, height: 3024), to: .oneByOne)
        XCTAssertEqual(size, CGSize(width: 3024, height: 3024))

        let image = makeImage(width: 4032, height: 3024)
        let cropped = cropper.crop(image, to: .oneByOne)
        XCTAssertEqual(pixelSize(of: cropped), CGSize(width: 3024, height: 3024))
    }

    // MARK: - 19.6: 3024x4032 portrait cropped to 9:16

    func test_portrait3024x4032_croppedToNineBySixteen_is2268x4032() {
        let size = ImageCropper.croppedSize(from: CGSize(width: 3024, height: 4032), to: .nineBySixteen)
        XCTAssertEqual(size, CGSize(width: 2268, height: 4032))

        let image = makeImage(width: 3024, height: 4032)
        let cropped = cropper.crop(image, to: .nineBySixteen)
        XCTAssertEqual(pixelSize(of: cropped), CGSize(width: 2268, height: 4032))
    }

    // MARK: - 19.7: 3024x4032 cropped to 3:4 is unchanged

    func test_portrait3024x4032_croppedToThreeByFour_isUnchanged() {
        let size = ImageCropper.croppedSize(from: CGSize(width: 3024, height: 4032), to: .threeByFour)
        XCTAssertEqual(size, CGSize(width: 3024, height: 4032))

        let image = makeImage(width: 3024, height: 4032)
        let cropped = cropper.crop(image, to: .threeByFour)
        XCTAssertEqual(pixelSize(of: cropped), CGSize(width: 3024, height: 4032))
    }

    // MARK: - 19.11: margin/font size follow the cropped short edge

    /// 1:1 crop's short edge (3024) is the same short edge as the native
    /// 3:4 image, so the margin must be identical.
    func test_oneByOneCrop_marginMatchesThreeByFourShortEdge() {
        let oneByOneSize = ImageCropper.croppedSize(from: CGSize(width: 4032, height: 3024), to: .oneByOne)
        let threeByFourSize = ImageCropper.croppedSize(from: CGSize(width: 3024, height: 4032), to: .threeByFour)

        let oneByOneMargin = OverlayMetrics.margin(forShortEdge: min(oneByOneSize.width, oneByOneSize.height))
        let threeByFourMargin = OverlayMetrics.margin(forShortEdge: min(threeByFourSize.width, threeByFourSize.height))

        XCTAssertEqual(oneByOneMargin, threeByFourMargin, accuracy: 0.001)
    }

    /// 9:16 crop's short edge is 2268, giving a margin of 90.72 (PRD 0.2
    /// acceptance 19.11).
    func test_nineBySixteenCrop_marginIs90Point72() {
        let size = ImageCropper.croppedSize(from: CGSize(width: 3024, height: 4032), to: .nineBySixteen)
        let shortEdge = min(size.width, size.height)
        XCTAssertEqual(shortEdge, 2268)

        let margin = OverlayMetrics.margin(forShortEdge: shortEdge)
        XCTAssertEqual(margin, 90.72, accuracy: 0.001)
    }

    // MARK: - No upscaling, ever

    func test_squareCrop_neverExceedsTheOriginalPixelCount() {
        for ratio in CaptureAspectRatio.allCases {
            let size = ImageCropper.croppedSize(from: CGSize(width: 4032, height: 3024), to: ratio)
            XCTAssertLessThanOrEqual(size.width, 4032)
            XCTAssertLessThanOrEqual(size.height, 3024)
        }
    }

    // MARK: - 126.1: cropRect is centered with the right aspect ratio

    func test_cropRect_isCenteredWithCorrectRatio_forEveryRatioAndOrientation() {
        let sizes = [CGSize(width: 4032, height: 3024), CGSize(width: 3024, height: 4032)]
        for pixelSize in sizes {
            for ratio in CaptureAspectRatio.allCases {
                let rect = ImageCropper.cropRect(forPixelSize: pixelSize, ratio: ratio)
                let message = "\(ratio) on \(pixelSize)"
                XCTAssertEqual(rect.midX, pixelSize.width / 2, accuracy: 0.001, message)
                XCTAssertEqual(rect.midY, pixelSize.height / 2, accuracy: 0.001, message)
                XCTAssertGreaterThanOrEqual(rect.minX, 0, message)
                XCTAssertGreaterThanOrEqual(rect.minY, 0, message)
                XCTAssertLessThanOrEqual(rect.maxX, pixelSize.width + 0.001, message)
                XCTAssertLessThanOrEqual(rect.maxY, pixelSize.height + 0.001, message)

                let shortToLong = min(rect.width, rect.height) / max(rect.width, rect.height)
                let expected = ratio.shortToLongRatio
                XCTAssertEqual(shortToLong, expected, accuracy: 0.0001, message)
                // Orientation follows the input.
                XCTAssertEqual(rect.width > rect.height, pixelSize.width > pixelSize.height && ratio != .oneByOne, message)
            }
        }
    }

    // MARK: - 126.2: crop output matches the rect, pixel for pixel

    func test_crop_outputSizeMatchesCropRect() {
        for ratio in CaptureAspectRatio.allCases {
            let image = makeImage(width: 400, height: 300)
            let rect = ImageCropper.cropRect(forPixelSize: CGSize(width: 400, height: 300), ratio: ratio)
            XCTAssertEqual(pixelSize(of: cropper.crop(image, to: ratio)), rect.size)
        }
    }
}
