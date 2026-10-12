import CoreGraphics
import UIKit
import XCTest
@testable import DaysCam

/// Covers TASK-127 acceptance 127.1 (cropping inside `bake` equals
/// crop-then-bake), 127.2 (8-bit standard range output) and the `nil` crop
/// path of 127.3. The crop-then-bake baseline is `referenceCrop`, which uses
/// neither `ImageCropper` nor `bake` (TASK-144 #498: `ImageCropper.crop`
/// is gone).
final class OverlayRendererCropTests: XCTestCase {

    private let renderer = OverlayRenderer()
    private let style = OverlayStyle(legacyTheme: .classicWhite)
    private let text = "第 10 天"

    /// A non-uniform photo (gradients plus a checker) so a wrong crop offset
    /// shows up in the pixels. `orientation == .right` stores it landscape and
    /// presents it portrait, like a sensor buffer.
    private func makePhoto(storedWidth: Int, storedHeight: Int,
                           orientation: UIImage.Orientation) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let stored = UIGraphicsImageRenderer(size: CGSize(width: storedWidth, height: storedHeight), format: format).image { context in
            for y in stride(from: 0, to: storedHeight, by: 10) {
                for x in stride(from: 0, to: storedWidth, by: 10) {
                    let red = CGFloat(x) / CGFloat(storedWidth)
                    let green = CGFloat(y) / CGFloat(storedHeight)
                    let blue: CGFloat = ((x / 50 + y / 50) % 2 == 0) ? 0.8 : 0.1
                    UIColor(red: red, green: green, blue: blue, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 10, height: 10))
                }
            }
        }
        let cgImage = try XCTUnwrap(stored.cgImage)
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    private func normalizedPixelSize(_ image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    /// The independent baseline: draw `image` upright at scale 1, then
    /// `CGImage.cropping(to:)`.
    private func referenceCrop(_ image: UIImage, to rect: CGRect) throws -> UIImage {
        let size = normalizedPixelSize(image)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let cropped = try XCTUnwrap(upright.cgImage?.cropping(to: rect))
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    // MARK: - 127.1

    func test_bakeWithCropRect_matchesCropThenBake() throws {
        let photos: [(name: String, image: UIImage)] = [
            ("landscape", try makePhoto(storedWidth: 800, storedHeight: 600, orientation: .up)),
            ("portrait", try makePhoto(storedWidth: 800, storedHeight: 600, orientation: .right)),
        ]
        for (name, photo) in photos {
            for ratio in CaptureAspectRatio.allCases {
                let label = "\(name) \(ratio)"
                let rect = ImageCropper.cropRect(forPixelSize: normalizedPixelSize(photo), ratio: ratio)

                let direct = try XCTUnwrap(renderer.bake(image: photo, text: text, style: style,
                                                         placement: .anchor(.bottomTrailing), font: .pingFang,
                                                         cropRect: rect), label)
                let cropped = try referenceCrop(photo, to: rect)
                let twoStep = try XCTUnwrap(renderer.bake(image: cropped, text: text, style: style,
                                                          placement: .anchor(.bottomTrailing), font: .pingFang), label)

                XCTAssertEqual(normalizedPixelSize(direct), normalizedPixelSize(twoStep), label)
                XCTAssertEqual(normalizedPixelSize(direct), rect.size, label)
                let lhs = try XCTUnwrap(PixelGrid(direct), label)
                let rhs = try XCTUnwrap(PixelGrid(twoStep), label)
                XCTAssertEqual(lhs.bytes.count, rhs.bytes.count, label)
                var maxDifference = 0
                for index in 0..<min(lhs.bytes.count, rhs.bytes.count) where index % 4 != 3 {
                    maxDifference = max(maxDifference, abs(Int(lhs.bytes[index]) - Int(rhs.bytes[index])))
                }
                XCTAssertLessThanOrEqual(maxDifference, 1, "127.1 \(label)")
            }
        }
    }

    func test_bakeWithCropRect_emptyText_matchesCrop() throws {
        let photo = try makePhoto(storedWidth: 800, storedHeight: 600, orientation: .up)
        let rect = ImageCropper.cropRect(forPixelSize: normalizedPixelSize(photo), ratio: .oneByOne)
        let direct = try XCTUnwrap(renderer.bake(image: photo, text: "", style: style,
                                                 placement: .anchor(.bottomTrailing), font: .pingFang,
                                                 cropRect: rect))
        let cropped = try referenceCrop(photo, to: rect)
        XCTAssertEqual(normalizedPixelSize(direct), CGSize(width: 600, height: 600))
        let lhs = try XCTUnwrap(PixelGrid(direct))
        let rhs = try XCTUnwrap(PixelGrid(cropped))
        XCTAssertEqual(lhs.bytes, rhs.bytes)
    }

    /// A smooth photo: red rises along x and green along y, each by at most
    /// one level per pixel, so a half-pixel shift moves a value by at most
    /// one level.
    private func makeGradient(width: Int, height: Int) throws -> UIImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                bytes[index] = UInt8(x * 255 / (width - 1))
                bytes[index + 1] = UInt8(y * 255 / (height - 1))
                bytes[index + 2] = 128
            }
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let cgImage = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                            bytesPerRow: width * 4, space: space,
                                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                            provider: provider, decode: nil, shouldInterpolate: false,
                                            intent: .defaultIntent))
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// #502 review: a 9:16 window with a half-pixel origin (400×300 → y =
    /// 37.5, the same odd trim as 5712×4284 → 535.5), landscape and
    /// portrait. `bake`'s output is exactly the rect's whole-pixel size, and
    /// its pixels are within one row's step of the whole-pixel window of
    /// that size at `floor(origin)` (see `ImageCropperTests`): here at most
    /// 1 level plus 1 for rounding.
    func test_bakeWithHalfPixelCropRect_isWithinOneRowOfTheFlooredWindow() throws {
        for (width, height) in [(400, 300), (300, 400)] {
            let photo = try makeGradient(width: width, height: height)
            let rect = ImageCropper.cropRect(forPixelSize: CGSize(width: width, height: height), ratio: .nineBySixteen)
            let label = "\(width)x\(height) \(rect)"
            XCTAssertNotEqual(rect, rect.integral, "the fixture really has a half-pixel origin: \(label)")

            let baked = try XCTUnwrap(renderer.bake(image: photo, text: "", style: style,
                                                    placement: .anchor(.bottomTrailing), font: .pingFang,
                                                    cropRect: rect), label)
            XCTAssertEqual(normalizedPixelSize(baked), rect.size, "no extra row: \(label)")

            let floored = CGRect(origin: CGPoint(x: rect.minX.rounded(.down), y: rect.minY.rounded(.down)),
                                 size: rect.size)
            let reference = try referenceCrop(photo, to: floored)
            let lhs = try XCTUnwrap(PixelGrid(baked), label)
            let rhs = try XCTUnwrap(PixelGrid(reference), label)
            XCTAssertEqual(lhs.bytes.count, rhs.bytes.count, label)
            var maxDifference = 0
            for index in 0..<min(lhs.bytes.count, rhs.bytes.count) where index % 4 != 3 {
                maxDifference = max(maxDifference, abs(Int(lhs.bytes[index]) - Int(rhs.bytes[index])))
            }
            XCTAssertLessThanOrEqual(maxDifference, 2, "within one row's step: \(label)")
        }
    }

    func test_bakeWithNilCropRect_keepsTheWholePhoto() throws {
        let photo = try makePhoto(storedWidth: 800, storedHeight: 600, orientation: .right)
        let output = try XCTUnwrap(renderer.bake(image: photo, text: text, style: style,
                                                 placement: .anchor(.bottomTrailing), font: .pingFang))
        XCTAssertEqual(normalizedPixelSize(output), CGSize(width: 600, height: 800))
    }

    func test_bakeWithCropRectOutsideTheImage_returnsNil() throws {
        let photo = try makePhoto(storedWidth: 800, storedHeight: 600, orientation: .up)
        XCTAssertNil(renderer.bake(image: photo, text: text, style: style, placement: .anchor(.bottomTrailing),
                                   font: .pingFang, cropRect: CGRect(x: 900, y: 0, width: 100, height: 100)))
    }

    // MARK: - 127.2

    /// A 16-bit Display P3 source must not be baked into a 16-bit bitmap.
    func test_bake_outputIsEightBitsPerComponent_fromWideGamutSource() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 16,
                                              bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                                                | CGBitmapInfo.byteOrder16Little.rawValue))
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        let source = UIImage(cgImage: try XCTUnwrap(context.makeImage()))
        XCTAssertEqual(source.cgImage?.bitsPerComponent, 16, "fixture is really 16-bit")

        let rect = ImageCropper.cropRect(forPixelSize: normalizedPixelSize(source), ratio: .oneByOne)
        for crop in [rect, nil] {
            let output = try XCTUnwrap(renderer.bake(image: source, text: text, style: style,
                                                     placement: .anchor(.bottomTrailing), font: .pingFang,
                                                     cropRect: crop))
            XCTAssertEqual(output.cgImage?.bitsPerComponent, 8, "127.2")
        }
    }
}
