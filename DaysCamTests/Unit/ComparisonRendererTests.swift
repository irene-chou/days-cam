import UIKit
import XCTest
@testable import DaysCam

/// #723 acceptance 4-6: side-by-side composition.
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

    private func compose(_ left: ComparisonRenderer.Tile, _ right: ComparisonRenderer.Tile) throws -> UIImage {
        try XCTUnwrap(renderer.compose(left: left, right: right, style: style,
                                       placement: .anchor(.bottomTrailing), font: .pingFang))
    }

    /// #723-4
    func testOutputSize() throws {
        let big = try compose(tile(.red, 3000, 4000), tile(.blue, 3000, 4000))
        XCTAssertEqual(big.size, CGSize(width: 2160, height: 1080))
        XCTAssertEqual(big.scale, 1)
        let mixed = try compose(tile(.red, 600, 800), tile(.blue, 3000, 4000))
        XCTAssertEqual(mixed.size, CGSize(width: 1200, height: 600))
    }

    /// #723-5
    func testHalvesComeFromTheirOwnPhoto() throws {
        let image = try compose(tile(.red, 800, 600), tile(.blue, 600, 800))
        let grid = try XCTUnwrap(PixelGrid(image))
        let left = grid.color(x: 100, y: 300)
        let right = grid.color(x: grid.width - 100, y: 300)
        XCTAssertGreaterThan(left.red, 200)
        XCTAssertLessThan(left.blue, 50)
        XCTAssertGreaterThan(right.blue, 200)
        XCTAssertLessThan(right.red, 50)
    }

    /// #723-6
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
