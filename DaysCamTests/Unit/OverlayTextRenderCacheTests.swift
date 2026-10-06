import SwiftUI
import XCTest
@testable import DaysCam

@MainActor
final class OverlayTextRenderCacheTests: XCTestCase {
    private let frame = CGSize(width: 300, height: 400)

    func testRepeatedLayoutAndPlacementChangesReusePixels() throws {
        var calls = 0
        let cache = OverlayTextRenderCache { text, style, size, scale in
            calls += 1
            return OverlayRenderer().renderText(text, style: style, fontSize: size, displayScale: scale)
        }
        let first = try XCTUnwrap(cache.image(text: "第 10 天", style: OverlayStyle(), frameSize: frame, displayScale: 3))
        for position in OverlayPosition.allCases {
            let again = try XCTUnwrap(cache.image(text: "第 10 天", style: OverlayStyle(), frameSize: frame, displayScale: 3))
            XCTAssertTrue(first.image === again.image)
            _ = OverlayTextView.origin(forBlockSize: again.blockSize, frameSize: frame, placement: .anchor(position))
        }
        XCTAssertEqual(calls, 1)
    }

    func testEachPixelInputInvalidatesTheCache() {
        var calls = 0
        let cache = OverlayTextRenderCache { text, style, size, scale in
            calls += 1
            return OverlayRenderer().renderText(text, style: style, fontSize: size, displayScale: scale)
        }
        let style = OverlayStyle(outline: .thickStroke, shadow: .hard)
        _ = cache.image(text: "A", style: style, frameSize: frame, displayScale: 2)
        _ = cache.image(text: "B", style: style, frameSize: frame, displayScale: 2)
        _ = cache.image(text: "B", style: OverlayStyle(), frameSize: frame, displayScale: 2)
        _ = cache.image(text: "B", style: OverlayStyle(), frameSize: CGSize(width: 200, height: 300), displayScale: 2)
        let scaled = cache.image(text: "B", style: OverlayStyle(), frameSize: CGSize(width: 200, height: 300), displayScale: 3)
        XCTAssertEqual(calls, 5)
        XCTAssertEqual(scaled?.image.scale, 3)
    }

    func testInvalidInputsClearPreviousImage() {
        let cache = OverlayTextRenderCache()
        XCTAssertNotNil(cache.image(text: "A", style: OverlayStyle(), frameSize: frame, displayScale: 2))
        XCTAssertNil(cache.image(text: "", style: OverlayStyle(), frameSize: frame, displayScale: 2))
        XCTAssertNil(cache.image(text: "A", style: OverlayStyle(), frameSize: .zero, displayScale: 2))
        XCTAssertNil(cache.image(text: "A", style: OverlayStyle(), frameSize: frame, displayScale: 0))
        XCTAssertNotNil(cache.image(text: "A", style: OverlayStyle(), frameSize: frame, displayScale: 2))
    }

    func testDecorationOverflowDoesNotChangeAnchorOrDragBounds() throws {
        let cache = OverlayTextRenderCache()
        for outline in [OverlayOutline.thickStroke, .solidBox, .translucentBox] {
            let style = OverlayStyle(outline: outline, shadow: .hard)
            let rendered = try XCTUnwrap(cache.image(text: "第 10 天", style: style, frameSize: frame, displayScale: 3))
            for anchor in [OverlayPosition.topLeading, .bottomTrailing] {
                let origin = OverlayTextView.origin(forBlockSize: rendered.blockSize, frameSize: frame, placement: .anchor(anchor))
                let imageFrame = rendered.imageFrame(forBlockOrigin: origin)
                XCTAssertEqual(imageFrame.minX + rendered.textInsets.left, origin.x, accuracy: 0.001)
                XCTAssertEqual(imageFrame.minY + rendered.textInsets.top, origin.y, accuracy: 0.001)
                let center = CGPoint(x: origin.x + rendered.blockSize.width / 2, y: origin.y + rendered.blockSize.height / 2)
                let dragCenter = OverlayTextView.clampedDragCenter(start: center, translation: .zero, frameSize: frame, blockSize: rendered.blockSize)
                XCTAssertEqual(dragCenter.x, center.x, accuracy: 0.001)
                XCTAssertEqual(dragCenter.y, center.y, accuracy: 0.001)
            }
        }
    }

    /// Exercises the real SwiftUI composition, not just the layout helper.
    func testViewfinderPixelsMatchSharedRendererAtAnAnchor() throws {
        let text = "第 10 天"
        for outline in [OverlayOutline.thickStroke, .solidBox, .none] {
            let style = OverlayStyle(outline: outline, shadow: .hard)
            let preview = ImageRenderer(content: OverlayTextView(text: text, style: style,
                placement: .anchor(.bottomTrailing), frameSize: frame)
                .frame(width: frame.width, height: frame.height)
                .environment(\.displayScale, 3))
            preview.scale = 3
            let actual = try XCTUnwrap(preview.uiImage?.cgImage)
            let textImage = try XCTUnwrap(OverlayTextRenderCache().image(text: text, style: style, frameSize: frame, displayScale: 3))
            let origin = OverlayTextView.origin(forBlockSize: textImage.blockSize, frameSize: frame, placement: .anchor(.bottomTrailing))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = false
            let expected = UIGraphicsImageRenderer(size: frame, format: format).image { _ in
                textImage.image.draw(in: textImage.imageFrame(forBlockOrigin: origin))
            }
            let a = try pixels(actual)
            let b = try pixels(XCTUnwrap(expected.cgImage))
            let totalError = zip(a, b).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) }
            XCTAssertLessThan(totalError / Double(a.count) / 255, 0.005, "\(outline)")
            XCTAssertGreaterThan(a.filter { $0 > 0 }.count, 100)
        }
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &data, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }
}
