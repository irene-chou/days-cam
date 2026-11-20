import UIKit
import XCTest
@testable import DaysCam

/// #723 acceptance 4-6, #740 acceptance 1-7: composition of the two tiles.
final class ComparisonRendererTests: XCTestCase {
    private let renderer = ComparisonRenderer()
    private let style = OverlayStyle()

    private func solid(_ color: UIColor, _ width: Int, _ height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func tile(_ color: UIColor, _ width: Int, _ height: Int, text: String = "",
                      film: FilmDateStamp? = nil) -> ComparisonRenderer.Tile {
        .init(image: solid(color, width, height), text: text, filmDate: film)
    }

    private func compose(_ left: ComparisonRenderer.Tile, _ right: ComparisonRenderer.Tile,
                         maxSide: CGFloat = 2160,
                         focus: @escaping ComparisonLayout.Focus = { _ in nil }) throws -> UIImage {
        try XCTUnwrap(renderer.compose(left: left, right: right, style: style,
                                       placement: .anchor(.bottomTrailing), font: .pingFang,
                                       maxSide: maxSide, focus: focus))
    }

    /// #740-6: side by side share a height, stacked a width, capped at 2160;
    /// ratios within 1% are not cropped.
    func testOutputSize() throws {
        let big = try compose(tile(.red, 3000, 4000), tile(.blue, 3000, 4000))
        XCTAssertEqual(big.size, CGSize(width: 3240, height: 2160))
        XCTAssertEqual(big.scale, 1)
        let mixed = try compose(tile(.red, 600, 800), tile(.blue, 3000, 4000))
        XCTAssertEqual(mixed.size, CGSize(width: 1200, height: 800))
        let stacked = try compose(tile(.red, 4000, 3000), tile(.blue, 3200, 1800))
        XCTAssertEqual(stacked.size, CGSize(width: 2160, height: 3240), "16:9 cut to 4:3, both 2160 wide")
        let preview = try compose(tile(.red, 3000, 4000), tile(.blue, 3000, 4000), maxSide: 1080)
        XCTAssertEqual(preview.size, CGSize(width: 1620, height: 1080))
        let near = try compose(tile(.red, 3000, 4000), tile(.blue, 3000, 3990))
        XCTAssertEqual(near.size.height, 2160)
    }

    /// #740-2: 3:4 beside 9:16: the 9:16 is cut to 3:4, two tiles of 3:4.
    func testSlimmerPortraitIsCut() throws {
        let image = try compose(tile(.red, 600, 800), tile(.blue, 900, 1600))
        XCTAssertEqual(image.size, CGSize(width: 1200, height: 800))
    }

    /// #740-4: one of each: two squares side by side.
    func testMixedOrientationMakesSquares() throws {
        let image = try compose(tile(.red, 600, 800), tile(.blue, 800, 600))
        XCTAssertEqual(image.size, CGSize(width: 1200, height: 600))
    }

    /// #740-1, 3: halves come from their own photo, earlier first (left, or top).
    func testHalvesComeFromTheirOwnPhoto() throws {
        let side = try XCTUnwrap(PixelGrid(try compose(tile(.red, 600, 800), tile(.blue, 600, 800))))
        XCTAssertGreaterThan(side.color(x: 100, y: 300).red, 200)
        XCTAssertGreaterThan(side.color(x: side.width - 100, y: 300).blue, 200)
        let stacked = try XCTUnwrap(PixelGrid(try compose(tile(.red, 800, 600), tile(.blue, 800, 600))))
        XCTAssertEqual(stacked.width, 800)
        XCTAssertEqual(stacked.height, 1200, "two landscapes stack")
        XCTAssertGreaterThan(stacked.color(x: 300, y: 100).red, 200)
        XCTAssertGreaterThan(stacked.color(x: 300, y: stacked.height - 100).blue, 200)
    }

    /// Red rows 0-399, green 400-799, blue 800-1199, red from 1200: 400px bands,
    /// so a top-aligned, centered and bottom-aligned 1200px cut start in different bands.
    private func stripes(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let colors: [UIColor] = [.red, .green, .blue, .red]
            for (index, color) in colors.enumerated() {
                color.setFill()
                context.fill(CGRect(x: 0, y: index * 400, width: width, height: 400))
            }
        }
    }

    /// #740-5: the cut follows the focus handed in, asked for only on the cropped photo.
    func testCropFollowsTheFocus() throws {
        let tall = ComparisonRenderer.Tile(image: stripes(width: 900, height: 1600), text: "", filmDate: nil)
        var asked = 0
        let image = try compose(tile(.gray, 900, 1200), tall, focus: { _ in
            asked += 1
            return CGRect(x: 0, y: 0.9, width: 1, height: 0.1)
        })
        XCTAssertEqual(asked, 1, "only the 9:16 needs a cut")
        let grid = try XCTUnwrap(PixelGrid(image))
        // Focus at the bottom: the cut keeps source rows 400-1599, so the top is green.
        XCTAssertGreaterThan(grid.color(x: grid.width - 100, y: 10).green, 200)
        let centered = try XCTUnwrap(PixelGrid(try compose(tile(.gray, 900, 1200), tall)))
        // No focus: rows 200-1399, so the top is still red.
        XCTAssertGreaterThan(centered.color(x: centered.width - 100, y: 10).red, 200)
    }

    /// #740-7: an uncropped tile is baked exactly as that photo alone at that size.
    func testUncroppedTileMatchesASingleBake() throws {
        let stamp = FilmDateStamp(text: FilmDateStamp.text(for: DateComponents(year: 2026, month: 11, day: 12)),
                                  corner: .topLeading)
        let source = tile(.gray, 600, 800, text: "第 10 天", film: stamp)
        let joined = try XCTUnwrap(PixelGrid(try compose(source, tile(.gray, 600, 800, text: "第 20 天"))))
        let alone = try XCTUnwrap(OverlayRenderer().bake(image: source.image, text: "第 10 天", style: style,
                                                         placement: .anchor(.bottomTrailing), font: .pingFang,
                                                         cropRect: nil, filmDate: stamp, tone: .standard))
        let single = try XCTUnwrap(PixelGrid(alone))
        XCTAssertEqual(single.width, 600)
        // Same geometry, but glyph rasterization differs by +-1 per channel across Xcode/runner versions
        // (CI run 44685170944: only text rows, a few bytes, |diff| = 1), so allow 2 per byte.
        let tolerance = 2
        for row in 0..<800 {
            let from = row * joined.width * 4
            let start = row * single.width * 4
            let joinedRow = Array(joined.bytes[from..<(from + 600 * 4)])
            let singleRow = Array(single.bytes[start..<(start + 600 * 4)])
            let worst = zip(joinedRow, singleRow).map { abs(Int($0) - Int($1)) }.max() ?? 0
            XCTAssertLessThanOrEqual(worst, tolerance, "row \(row)")
        }
    }

    /// Text and the film date stamp change pixels.
    func testTextAndFilmDateChangePixels() throws {
        let plain = try XCTUnwrap(PixelGrid(try compose(tile(.gray, 600, 600), tile(.gray, 600, 600))))
        let texted = try XCTUnwrap(PixelGrid(try compose(tile(.gray, 600, 600, text: "第 10 天"),
                                                         tile(.gray, 600, 600))))
        XCTAssertNotEqual(plain.bytes, texted.bytes)
        let stamp = FilmDateStamp(text: FilmDateStamp.text(for: DateComponents(year: 2026, month: 11, day: 12)),
                                  corner: .topLeading)
        let stamped = try XCTUnwrap(PixelGrid(try compose(tile(.gray, 600, 600, film: stamp),
                                                          tile(.gray, 600, 600))))
        XCTAssertNotEqual(plain.bytes, stamped.bytes)
    }
}
