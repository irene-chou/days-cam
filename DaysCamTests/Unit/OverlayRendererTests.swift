import CoreGraphics
import UIKit
import XCTest
@testable import DaysCam

/// Covers the TASK-09 acceptance table (9.1 ... 9.11) plus the layout rules the
/// baked output has to share with the viewfinder (PRD FR-4.3, FR-4.6, FR-4.7).
///
/// Every assertion reads pixels back through `PixelGrid`, which redraws the
/// output into one fixed format (8-bit sRGB RGBA, top row first). That keeps
/// the tests independent of whatever bitmap format the renderer picked.
/// 9.8-9.10 are grep checks and live in the task card, not here.
final class OverlayRendererTests: XCTestCase {

    private let width = 1200
    private let height = 1600
    private let renderer = OverlayRenderer()

    private var classicWhite: OverlayTheme { .theme(for: .classicWhite) }

    // MARK: - 9.1 ... 9.3

    func test_9_1_outputKeepsTheInputPixelSize() throws {
        let output = try bake(makeImage(), text: "第 10 天")

        XCTAssertEqual(output.size, CGSize(width: width, height: height))
        XCTAssertEqual(output.scale, 1)
        XCTAssertEqual(output.imageOrientation, .up)
    }

    func test_9_2_bottomTrailingMarksTheBottomRightCorner() throws {
        let grid = try pixels(of: bake(makeImage(), text: "第 10 天", position: .bottomTrailing))

        XCTAssertTrue(grid.contains(in: region(x: 900...1150, y: 1350...1550)) { $0.distance(to: .white) > 30 },
                      "at least one pixel in the bottom-right region is visibly not white")
    }

    func test_9_3_bottomTrailingLeavesTheTopLeftUntouched() throws {
        let grid = try pixels(of: bake(makeImage(), text: "第 10 天", position: .bottomTrailing))

        XCTAssertTrue(grid.all(in: region(x: 0...100, y: 0...100)) { $0 == .white },
                      "the far corner is still pure white")
    }

    // MARK: - 9.4

    func test_9_4_topLeadingMarksTheTopLeftAndLeavesTheBottomRightWhite() throws {
        let grid = try pixels(of: bake(makeImage(), text: "第 10 天", position: .topLeading))

        XCTAssertTrue(grid.contains(in: region(x: 0...100, y: 0...100)) { $0.distance(to: .white) > 30 })
        XCTAssertTrue(grid.all(in: region(x: 900...1150, y: 1350...1550)) { $0 == .white })
    }

    // MARK: - 9.5

    /// The image is stored landscape (1600x1200 pixels) and tagged `.right`, the
    /// way a portrait shot comes off the sensor. A red block sits in the stored
    /// top-left corner; a correct 90° clockwise normalisation moves it to the
    /// displayed top-right.
    func test_9_5_rightOrientedImageIsNormalisedBeforeTheTextIsDrawn() throws {
        let stored = try makeImage(pixelWidth: height, pixelHeight: width,
                                   orientation: .right,
                                   marker: (rect: CGRect(x: 0, y: 0, width: 100, height: 100), color: .red))
        XCTAssertEqual(stored.size, CGSize(width: width, height: height), "fixture sanity: displayed portrait")

        let output = try bake(stored, text: "第 10 天", position: .bottomTrailing)
        let grid = try pixels(of: output)

        XCTAssertEqual(output.imageOrientation, .up)
        XCTAssertEqual(grid.width, width)
        XCTAssertEqual(grid.height, height)

        XCTAssertTrue(grid.all(in: region(x: width - 90...width - 10, y: 10...90)) { $0 == .red },
                      "the stored top-left marker lands top-right once rotated")
        XCTAssertTrue(grid.all(in: region(x: 10...90, y: 10...90)) { $0 == .white },
                      "and not where an unrotated copy would have put it")

        let lowerHalf = region(x: 0...(width - 1), y: (height / 2)...(height - 1))
        let mark = try XCTUnwrap(grid.bounds(in: lowerHalf) { $0.distance(to: .white) > 30 },
                                 "the text left a mark in the lower half")
        XCTAssertGreaterThan(mark.midX, CGFloat(width) / 2, "bottomTrailing lands on the right")
        XCTAssertGreaterThan(mark.midY, CGFloat(height) * 0.75, "and at the bottom")
        XCTAssertGreaterThan(mark.width, mark.height * 2,
                             "one line of horizontal text is much wider than tall; rotated 90° it would not be")
    }

    // MARK: - 9.6

    func test_9_6_emptyTextLeavesEveryPixelIdentical() throws {
        let input = try makeImage(marker: (rect: CGRect(x: 1000, y: 1400, width: 50, height: 50), color: .red))

        let output = try bake(input, text: "")

        let before = try pixels(of: input)
        let after = try pixels(of: output)
        XCTAssertEqual(after.width, before.width)
        XCTAssertEqual(after.height, before.height)
        XCTAssertTrue(after.bytes == before.bytes, "nothing drawn — not even an empty background box")
    }

    func test_9_6_emptyTextDrawsNoEmptyBoxForBoxedThemes() throws {
        for id in [ThemeID.filmStrip, .minimalDark] {
            let output = try bake(makeImage(), text: "", theme: .theme(for: id))
            let grid = try pixels(of: output)
            XCTAssertTrue(grid.all(in: region(x: 0...(width - 1), y: 0...(height - 1))) { $0 == .white },
                          "\(id) drew something for an empty string")
        }
    }

    /// The output contract is "always upright", even when there is nothing to
    /// print — the saving path relies on it.
    ///
    /// A rotated input cannot take the hand-it-back shortcut, so this is also
    /// the case that proves the drawing path itself skips an empty string —
    /// a boxed theme would otherwise leave an empty box behind.
    func test_9_6_emptyTextStillNormalisesOrientationAndDrawsNothing() throws {
        let stored = try makeImage(pixelWidth: height, pixelHeight: width, orientation: .right)

        let output = try bake(stored, text: "", theme: .theme(for: .filmStrip))

        XCTAssertEqual(output.imageOrientation, .up)
        XCTAssertEqual(output.size, CGSize(width: width, height: height))
        XCTAssertTrue((try pixels(of: output)).all(in: region(x: 0...(width - 1), y: 0...(height - 1))) {
            $0 == .white
        }, "no empty box")
    }

    // MARK: - 9.7

    func test_9_7_aHundredBakesStayUnderFiveHundredMegabytes() throws {
        let input = try makeImage()
        var peak: UInt64 = 0

        for _ in 0..<100 {
            let output = renderer.bake(image: input, text: "第 10 天", theme: classicWhite, position: .bottomTrailing)
            XCTAssertNotNil(output)
            peak = max(peak, try XCTUnwrap(physicalFootprint()))
        }

        let limit: UInt64 = 500 * 1024 * 1024
        XCTAssertLessThan(peak, limit, "peak footprint \(peak / 1024 / 1024) MB")
    }

    // MARK: - 9.11

    /// A file on disk goes through the same code path as a fresh capture; the
    /// renderer cannot tell them apart and must not try to.
    func test_9_11_imageLoadedFromAFileBakesExactlyLikeAnInMemoryOne() throws {
        let inMemory = try makeImage()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverlayRendererTests-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(inMemory.pngData()).write(to: url)
        let fromFile = try XCTUnwrap(UIImage(contentsOfFile: url.path))

        let bakedFromFile = try bake(fromFile, text: "第 10 天")
        let bakedInMemory = try bake(inMemory, text: "第 10 天")

        XCTAssertEqual(bakedFromFile.size, CGSize(width: width, height: height))
        let fileGrid = try pixels(of: bakedFromFile)
        XCTAssertTrue(fileGrid.contains(in: region(x: 900...1150, y: 1350...1550)) { $0.distance(to: .white) > 30 })
        XCTAssertTrue(fileGrid.all(in: region(x: 0...100, y: 0...100)) { $0 == .white })
        XCTAssertTrue(fileGrid.bytes == (try pixels(of: bakedInMemory)).bytes,
                      "same pixels in, same pixels out, wherever they came from")
    }

    // MARK: - Pixel size, not point size

    /// A 3x image of 400x533.33 points is 1200x1600 pixels, and the text must
    /// be sized from the pixels (PRD §6.2: draw at the original pixel size).
    func test_outputIsSizedInPixelsWhateverTheInputScale() throws {
        let pixelsOnly = try makeImage()
        let cgImage = try XCTUnwrap(pixelsOnly.cgImage)
        let retina = UIImage(cgImage: cgImage, scale: 3, orientation: .up)

        let output = try bake(retina, text: "第 10 天")

        XCTAssertEqual(output.scale, 1)
        XCTAssertEqual(output.size, CGSize(width: width, height: height))
        XCTAssertTrue((try pixels(of: output)).bytes == (try pixels(of: bake(pixelsOnly, text: "第 10 天"))).bytes,
                      "the input's scale factor must not change the layout")
    }

    // MARK: - Shared layout (PRD FR-4.3, FR-4.7)

    /// `filmStrip` draws an opaque-ish box, so its edges can be measured. The
    /// box must sit exactly one margin (4% of the short edge) in from the
    /// bottom-right corner, and its insets must be scaled up from their 17pt
    /// values — unscaled, they would be ~70px too narrow at this size.
    func test_boxSitsOneMarginFromTheCornerWithScaledInsets() throws {
        let theme = OverlayTheme.theme(for: .filmStrip)
        let text = "第 10 天"
        let grid = try pixels(of: bake(makeImage(), text: text, theme: theme, position: .bottomTrailing))

        let shortEdge = CGFloat(width)
        let margin = OverlayMetrics.margin(forShortEdge: shortEdge)
        let fontSize = OverlayMetrics.fittedFontSize(for: text,
                                                     theme: theme,
                                                     baseFontSize: OverlayMetrics.baseFontSize(forShortEdge: shortEdge),
                                                     availableWidth: CGFloat(width) - margin * 2)
        let scale = OverlayMetrics.decorationScale(forFontSize: fontSize)
        let font = OverlayMetrics.font(for: theme, size: fontSize)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let expectedWidth = textSize.width + 2 * 12 * scale
        let expectedHeight = textSize.height + 2 * 6 * scale

        let box = try XCTUnwrap(grid.bounds(in: region(x: 0...(width - 1), y: 0...(height - 1))) {
            $0.distance(to: .white) > 30
        })

        XCTAssertEqual(box.maxX, CGFloat(width) - margin, accuracy: 2, "right edge one margin in")
        XCTAssertEqual(box.maxY, CGFloat(height) - margin, accuracy: 2, "bottom edge one margin in")
        XCTAssertEqual(box.width, expectedWidth, accuracy: 3, "horizontal insets scaled by \(scale)")
        XCTAssertEqual(box.height, expectedHeight, accuracy: 3, "vertical insets scaled by \(scale)")
    }

    func test_middleCenterIsCentredBothWays() throws {
        let grid = try pixels(of: bake(makeImage(), text: "第 10 天",
                                       theme: .theme(for: .filmStrip), position: .middleCenter))

        let box = try XCTUnwrap(grid.bounds(in: region(x: 0...(width - 1), y: 0...(height - 1))) {
            $0.distance(to: .white) > 30
        })

        XCTAssertEqual(box.midX, CGFloat(width) / 2, accuracy: 2)
        XCTAssertEqual(box.midY, CGFloat(height) / 2, accuracy: 2)
    }

    /// SwiftUI's `.shadow(y: +2)` casts downward. Core Graphics shadow offsets
    /// are in device space, which is flipped relative to a UIKit context, so a
    /// naive port casts the shadow upward instead. On mid-grey the white text
    /// and its black shadow can both be seen and compared.
    func test_shadowFallsBelowTheTextLikeThePreview() throws {
        let grey = RGB(red: 128, green: 128, blue: 128)
        let grid = try pixels(of: bake(makeImage(fill: grey), text: "第 10 天", position: .bottomTrailing))
        let area = region(x: 0...(width - 1), y: (height / 2)...(height - 1))

        let text = try XCTUnwrap(grid.centroid(in: area) { $0.red > 200 && $0.green > 200 && $0.blue > 200 })
        let shadow = try XCTUnwrap(grid.centroid(in: area) { $0.red < 100 && $0.green < 100 && $0.blue < 100 })

        XCTAssertGreaterThan(shadow.y, text.y, "shadow centroid \(shadow.y) should be below text centroid \(text.y)")
    }

    // MARK: - Legibility (PRD FR-4.6)

    /// Every theme must still be visible on a pure white and a pure black photo.
    func test_everyThemeIsVisibleOnPureWhiteAndPureBlack() throws {
        for theme in OverlayTheme.all {
            for background in [RGB.white, RGB.black] {
                let grid = try pixels(of: bake(makeImage(fill: background), text: "第 10 天",
                                               theme: theme, position: .bottomTrailing))
                XCTAssertTrue(grid.contains(in: region(x: 700...1190, y: 1300...1590)) {
                    $0.distance(to: background) > 30
                }, "\(theme.id) is invisible on \(background)")
            }
        }
    }

    // MARK: - Helpers

    private func bake(_ image: UIImage,
                      text: String,
                      theme: OverlayTheme? = nil,
                      position: OverlayPosition = .bottomTrailing,
                      file: StaticString = #filePath,
                      line: UInt = #line) throws -> UIImage {
        try XCTUnwrap(renderer.bake(image: image, text: text, theme: theme ?? classicWhite, position: position),
                      "bake returned nil", file: file, line: line)
    }

    private func pixels(of image: UIImage, file: StaticString = #filePath, line: UInt = #line) throws -> PixelGrid {
        try XCTUnwrap(PixelGrid(image), "could not read pixels back", file: file, line: line)
    }

    private func region(x: ClosedRange<Int>, y: ClosedRange<Int>) -> PixelRegion {
        PixelRegion(x: x, y: y)
    }

    /// A solid image stored `pixelWidth` x `pixelHeight`, optionally with a
    /// block of another color painted at `marker.rect` in stored (top-left
    /// origin) coordinates, then tagged with `orientation`.
    private func makeImage(pixelWidth: Int? = nil,
                           pixelHeight: Int? = nil,
                           fill: RGB = .white,
                           orientation: UIImage.Orientation = .up,
                           marker: (rect: CGRect, color: RGB)? = nil) throws -> UIImage {
        let storedWidth = pixelWidth ?? width
        let storedHeight = pixelHeight ?? height
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil,
                                              width: storedWidth,
                                              height: storedHeight,
                                              bitsPerComponent: 8,
                                              bytesPerRow: 0,
                                              space: space,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(fill.cgColor(in: space))
        context.fill(CGRect(x: 0, y: 0, width: storedWidth, height: storedHeight))
        if let marker {
            // Bitmap contexts put y = 0 at the bottom; flip to top-left origin.
            let flipped = CGRect(x: marker.rect.minX,
                                 y: CGFloat(storedHeight) - marker.rect.maxY,
                                 width: marker.rect.width,
                                 height: marker.rect.height)
            context.setFillColor(marker.color.cgColor(in: space))
            context.fill(flipped)
        }
        let cgImage = try XCTUnwrap(context.makeImage())
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    /// The process's physical memory footprint — what the system counts
    /// against the app, and what Xcode's memory gauge shows.
    private func physicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }
}

// MARK: - Pixel reading

/// An 8-bit sRGB color, compared exactly.
struct RGB: Equatable, CustomStringConvertible {
    let red: Int
    let green: Int
    let blue: Int

    static let white = RGB(red: 255, green: 255, blue: 255)
    static let black = RGB(red: 0, green: 0, blue: 0)
    static let red = RGB(red: 255, green: 0, blue: 0)

    /// The largest per-channel difference.
    func distance(to other: RGB) -> Int {
        max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue))
    }

    func cgColor(in space: CGColorSpace) -> CGColor {
        let components = [CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, 1]
        return CGColor(colorSpace: space, components: components) ?? CGColor(gray: 0, alpha: 1)
    }

    var description: String { "(\(red),\(green),\(blue))" }
}

/// An inclusive pixel rectangle, top-left origin.
struct PixelRegion {
    let x: ClosedRange<Int>
    let y: ClosedRange<Int>
}

/// Pixels read back in one fixed format: 8-bit sRGB RGBA, top row first.
struct PixelGrid {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        self.width = width
        self.height = height
        self.bytes = buffer
    }

    func color(x: Int, y: Int) -> RGB {
        let offset = (y * width + x) * 4
        return RGB(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }

    func contains(in region: PixelRegion, where matches: (RGB) -> Bool) -> Bool {
        for y in clamped(region.y, to: height) {
            for x in clamped(region.x, to: width) where matches(color(x: x, y: y)) {
                return true
            }
        }
        return false
    }

    func all(in region: PixelRegion, where matches: (RGB) -> Bool) -> Bool {
        !contains(in: region) { !matches($0) }
    }

    /// The smallest rectangle holding every matching pixel, as a CGRect whose
    /// `maxX` / `maxY` are the edges just past the last matching pixel.
    func bounds(in region: PixelRegion, where matches: (RGB) -> Bool) -> CGRect? {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for y in clamped(region.y, to: height) {
            for x in clamped(region.x, to: width) where matches(color(x: x, y: y)) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    func centroid(in region: PixelRegion, where matches: (RGB) -> Bool) -> CGPoint? {
        var sumX = 0, sumY = 0, count = 0
        for y in clamped(region.y, to: height) {
            for x in clamped(region.x, to: width) where matches(color(x: x, y: y)) {
                sumX += x; sumY += y; count += 1
            }
        }
        guard count > 0 else { return nil }
        return CGPoint(x: CGFloat(sumX) / CGFloat(count), y: CGFloat(sumY) / CGFloat(count))
    }

    private func clamped(_ range: ClosedRange<Int>, to limit: Int) -> ClosedRange<Int> {
        max(0, range.lowerBound)...min(limit - 1, range.upperBound)
    }
}
