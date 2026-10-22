import CoreImage
import Metal
import XCTest
@testable import DaysCam

/// The live-tone viewfinder (#590): the preview path and the photo path run
/// the same filters, `.standard` is never processed, and the Metal draw lands
/// right side up and aspect-filled.
final class FilteredPreviewViewTests: XCTestCase {
    private func solidImage(_ color: CIColor, size: CGSize) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
    }

    private func makeCGImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.5, green: 0.45, blue: 0.4, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        return try XCTUnwrap(context.makeImage())
    }

    private func bytes(of image: CGImage) -> Data? {
        image.dataProvider?.data as Data?
    }

    func testStandardIsNeverProcessed() {
        let image = solidImage(CIColor(red: 0.3, green: 0.3, blue: 0.3), size: CGSize(width: 8, height: 8))
        XCTAssertTrue(ColorToneRenderer.filtered(.standard, image) === image)
    }

    func testPreviewAndPhotoPathsGiveTheSamePixelsForEveryTone() throws {
        let source = try makeCGImage(width: 64, height: 48)
        let input = CIImage(cgImage: source)
        let colorSpace = try XCTUnwrap(source.colorSpace)
        for tone in ColorTone.allCases where tone != .standard {
            let photo = try XCTUnwrap(ColorToneRenderer.apply(tone, to: source), "\(tone)")
            let filtered = try XCTUnwrap(ColorToneRenderer.filtered(tone, input))
            let preview = try XCTUnwrap(ColorToneRenderer.context.createCGImage(
                filtered, from: input.extent, format: .RGBA8, colorSpace: colorSpace))
            XCTAssertEqual(bytes(of: photo), bytes(of: preview), "590 \(tone): same pixels either path")
            XCTAssertNotEqual(bytes(of: photo), bytes(of: source), "\(tone) changed something")
        }
    }

    func testAspectFillCentersAndCrops() {
        let wide = FilteredPreviewMetalView.aspectFillTransform(from: CGSize(width: 100, height: 50),
                                                                to: CGSize(width: 50, height: 50))
        XCTAssertEqual(wide.a, 1, accuracy: 0.001)
        XCTAssertEqual(wide.tx, -25, accuracy: 0.001, "sides cropped equally")
        let tall = FilteredPreviewMetalView.aspectFillTransform(from: CGSize(width: 30, height: 60),
                                                                to: CGSize(width: 60, height: 60))
        XCTAssertEqual(tall.a, 2, accuracy: 0.001)
        XCTAssertEqual(tall.ty, -30, accuracy: 0.001, "top and bottom cropped equally")
    }

    /// Red on the top half of the picture must land on the texture's first
    /// rows (Metal's origin is top-left, Core Image's bottom-left).
    func testDrawLandsRightSideUp() throws {
        let device = try XCTUnwrap(ColorToneRenderer.metalDevice, "no Metal device")
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 40, height: 80,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let red = solidImage(CIColor(red: 1, green: 0, blue: 0), size: CGSize(width: 40, height: 40))
            .transformed(by: CGAffineTransform(translationX: 0, y: 40))
        let blue = solidImage(CIColor(red: 0, green: 0, blue: 1), size: CGSize(width: 40, height: 40))
        let image = red.composited(over: blue)
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        FilteredPreviewMetalView.render(image, to: texture, commandBuffer: commandBuffer,
                                        colorSpace: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(20, 5, 1, 1), mipmapLevel: 0)
        XCTAssertGreaterThan(pixel[2], 200, "top of the texture is red: \(pixel)")
        texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(20, 75, 1, 1), mipmapLevel: 0)
        XCTAssertGreaterThan(pixel[0], 200, "bottom of the texture is blue: \(pixel)")
    }
}
