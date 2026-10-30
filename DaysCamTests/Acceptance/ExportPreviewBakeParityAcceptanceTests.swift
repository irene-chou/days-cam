import SwiftUI
import XCTest
@testable import DaysCam

/// #620 independent QA (B′ 620-11, Lead's ruling on assumption 1): the export
/// page's preview draws the overlay with `OverlayTextView`＋`FilmDateStampView`
/// at the preview's size, while the exported photo is `OverlayRenderer.bake`
/// on the full-size original with `cropRect: nil`. Both must put the overlay
/// at the same place and size relative to the photo.
@MainActor
final class ExportPreviewBakeParityAcceptanceTests: XCTestCase {
    private struct Pixels {
        let data: [UInt8], width: Int, height: Int
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
    }

    /// A bounding box in 0...1 of the image's width and height.
    private struct Box {
        var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0
        var isEmpty: Bool { maxX < minX }
    }

    /// The 3:4 photo on a 6.1-inch phone: 52% of 390pt wide (FR-19.2).
    private let previewSize = CGSize(width: 203, height: 271)
    /// A full-size original at a different scale from the preview.
    private let originalSize = CGSize(width: 1512, height: 2016)
    private let text = "小寶 第 10 天"
    private let stamp = FilmDateStamp(text: "'26 01 10", corner: .topTrailing)

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

    /// Bounding box of the pixels `matches` picks, normalized.
    private func box(_ p: Pixels, where matches: ((Int, Int, Int)) -> Bool) -> Box {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<p.height {
            for x in 0..<p.width where matches(p.rgb(x, y)) {
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return Box() }
        let w = Double(p.width), h = Double(p.height)
        return Box(minX: Double(minX) / w, minY: Double(minY) / h, maxX: Double(maxX + 1) / w, maxY: Double(maxY + 1) / h)
    }

    /// The black overlay box.
    private static func isOverlay(_ c: (Int, Int, Int)) -> Bool { c.0 < 40 && c.1 < 40 && c.2 < 40 }
    /// The orange film date's body (red well above blue).
    private static func isFilmDate(_ c: (Int, Int, Int)) -> Bool { c.0 - c.2 > 90 }

    /// The export page's preview composition (`ExportView.preview`).
    private func preview(placement: OverlayPlacement, style: OverlayStyle) throws -> Pixels {
        let content = ZStack {
            Image(uiImage: gray(originalSize)).resizable().scaledToFill()
                .frame(width: previewSize.width, height: previewSize.height).clipped()
            OverlayTextView(text: text, style: style, placement: placement, frameSize: previewSize, font: .pingFang)
            FilmDateStampView(stamp: stamp, frameSize: previewSize)
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .environment(\.displayScale, 3)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return try pixels(try XCTUnwrap(renderer.uiImage))
    }

    /// The export's bake (`ExportModel.export`): full-size original, no crop,
    /// standard tone.
    private func baked(placement: OverlayPlacement, style: OverlayStyle) throws -> Pixels {
        let image = try XCTUnwrap(OverlayRenderer().bake(image: gray(originalSize), text: text, style: style,
                                                         placement: placement, font: .pingFang, cropRect: nil,
                                                         filmDate: stamp, tone: .standard))
        XCTAssertEqual(image.size.width * image.scale, originalSize.width, "the export keeps the original's size")
        return try pixels(image)
    }

    private func assertSameBox(_ live: Box, _ photo: Box, tolerance: Double, _ label: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(live.isEmpty, "preview drew \(label)", file: file, line: line)
        XCTAssertFalse(photo.isEmpty, "photo drew \(label)", file: file, line: line)
        let pairs = [("minX", live.minX, photo.minX), ("maxX", live.maxX, photo.maxX),
                     ("minY", live.minY, photo.minY), ("maxY", live.maxY, photo.maxY)]
        for (edge, a, b) in pairs {
            XCTAssertEqual(a, b, accuracy: tolerance, "\(label) \(edge): preview \(a) vs photo \(b)", file: file, line: line)
        }
    }

    /// 620-11: overlay box position and size, and the film date, agree
    /// between the preview and the exported photo for anchors, a dragged
    /// (custom) position and a larger size.
    func testPreviewOverlayMatchesTheExportedPhoto() throws {
        let cases: [(String, OverlayPlacement, OverlayStyle)] = [
            ("bottomTrailing", .anchor(.bottomTrailing), OverlayStyle(outline: .box, outlineColor: .black, shadow: .none)),
            ("bottomLeading", .anchor(.bottomLeading), OverlayStyle(outline: .box, outlineColor: .black, shadow: .none)),
            ("custom drag", .custom(x: 0.3, y: 0.62), OverlayStyle(outline: .box, outlineColor: .black, shadow: .none)),
            ("custom large", .custom(x: 0.5, y: 0.4),
             OverlayStyle(outline: .box, outlineColor: .black, shadow: .none, sizeScale: 160))
        ]
        for (label, placement, style) in cases {
            let live = try preview(placement: placement, style: style)
            let photo = try baked(placement: placement, style: style)
            // 1% of the photo: about 2pt on the preview.
            assertSameBox(box(live, where: Self.isOverlay), box(photo, where: Self.isOverlay), tolerance: 0.01,
                          "overlay \(label)")
            assertSameBox(box(live, where: Self.isFilmDate), box(photo, where: Self.isFilmDate), tolerance: 0.01,
                          "film date \(label)")
        }
    }
}
