import SwiftUI
import XCTest
@testable import DaysCam

/// TASK-81 UI independent QA (81.2): with the same parameters the viewfinder
/// (`OverlayTextView`) and the baked photo (`OverlayRenderer.bake`) draw the same
/// box geometry, and `squareBox` has square corners in both while `box` does not.
@MainActor
final class SquareBoxViewfinderParityAcceptanceTests: XCTestCase {
    private struct Pixels {
        let data: [UInt8], width: Int, height: Int
        func isDark(_ x: Int, _ y: Int) -> Bool { data[(y * width + x) * 4] < 40 }
    }

    private func pixels(_ image: UIImage) throws -> Pixels {
        let cg = try XCTUnwrap(image.cgImage)
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Pixels(data: data, width: w, height: h)
    }

    private func gray(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.5, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private struct Box { var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1; var corners = [Bool]() }

    private func box(_ p: Pixels) -> Box {
        var b = Box()
        for y in 0..<p.height {
            for x in 0..<p.width where p.isDark(x, y) {
                b.minX = min(b.minX, x); b.minY = min(b.minY, y); b.maxX = max(b.maxX, x); b.maxY = max(b.maxY, y)
            }
        }
        if b.maxX >= 0 {
            b.corners = [p.isDark(b.minX, b.minY), p.isDark(b.maxX, b.minY), p.isDark(b.minX, b.maxY), p.isDark(b.maxX, b.maxY)]
        }
        return b
    }

    private func viewfinder(style: OverlayStyle, text: String) throws -> Pixels {
        let frame = CGSize(width: 300, height: 400)
        let content = ZStack {
            Image(uiImage: gray(frame)).resizable()
            OverlayTextView(text: text, style: style, placement: .anchor(.middleCenter), frameSize: frame)
        }.frame(width: frame.width, height: frame.height).environment(\.displayScale, 3)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return try pixels(try XCTUnwrap(renderer.uiImage))
    }

    private func baked(style: OverlayStyle, text: String) throws -> Pixels {
        let image = try XCTUnwrap(OverlayRenderer().bake(image: gray(CGSize(width: 900, height: 1200)), text: text,
                                                         style: style, placement: .anchor(.middleCenter), font: .pingFang))
        return try pixels(image)
    }

    /// 81.2: viewfinder and photo agree on box rectangle (within 2px at 3x) and on corner shape.
    func testViewfinderAndBakedSquareBoxShareGeometry() throws {
        for padding in [6.0, 12, 24] {
            for (outline, expectedCorner) in [(OverlayOutline.squareBox, true), (.box, false)] {
                let style = OverlayStyle(outline: outline, outlineColor: .black, boxPadding: padding, shadow: .none)
                let live = box(try viewfinder(style: style, text: "第 10 天"))
                let photo = box(try baked(style: style, text: "第 10 天"))
                let label = "\(outline) pad \(padding)"
                XCTAssertGreaterThan(live.maxX, live.minX, "viewfinder drew a box \(label)")
                XCTAssertGreaterThan(photo.maxX, photo.minX, "photo drew a box \(label)")
                for (a, b) in [(live.minX, photo.minX), (live.maxX, photo.maxX), (live.minY, photo.minY), (live.maxY, photo.maxY)] {
                    XCTAssertLessThanOrEqual(abs(a - b), 2, "edge mismatch \(label): \(a) vs \(b)")
                }
                XCTAssertEqual(live.corners, Array(repeating: expectedCorner, count: 4), "viewfinder corners \(label)")
                XCTAssertEqual(photo.corners, Array(repeating: expectedCorner, count: 4), "photo corners \(label)")
            }
        }
    }
}
