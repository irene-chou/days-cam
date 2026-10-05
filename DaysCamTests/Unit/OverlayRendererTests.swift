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

    /// `filmStrip` draws an opaque-ish box, so its edges can be measured. For
    /// every one of the nine positions the box must hug the edges it is
    /// anchored to at exactly one margin (4% of the short edge) and be centred
    /// on the axes it is not (PRD FR-4.3). Its insets must also be scaled up
    /// from their 17pt values — unscaled, they would be ~70px too narrow here.
    func test_everyPositionPlacesTheBoxOneMarginInAndScalesItsInsets() throws {
        let theme = OverlayTheme.theme(for: .filmStrip)
        let text = "第 10 天"
        let frameWidth = CGFloat(width)
        let frameHeight = CGFloat(height)

        let margin = OverlayMetrics.margin(forShortEdge: frameWidth)
        let fontSize = OverlayMetrics.fittedFontSize(for: text,
                                                     font: .pingFang,
                                                     baseFontSize: OverlayMetrics.baseFontSize(forShortEdge: frameWidth),
                                                     availableWidth: frameWidth - margin * 2)
        let scale = OverlayMetrics.decorationScale(forFontSize: fontSize)
        let font = ResolvedOverlayFont.pingFang.font(ofSize: fontSize)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let boxWidth = textSize.width + 2 * 12 * scale
        let boxHeight = textSize.height + 2 * 6 * scale

        let leading = margin
        let centerX = (frameWidth - boxWidth) / 2
        let trailing = frameWidth - margin - boxWidth
        let top = margin
        let centerY = (frameHeight - boxHeight) / 2
        let bottom = frameHeight - margin - boxHeight
        let expected: [OverlayPosition: CGPoint] = [
            .topLeading: CGPoint(x: leading, y: top),
            .topCenter: CGPoint(x: centerX, y: top),
            .topTrailing: CGPoint(x: trailing, y: top),
            .middleLeading: CGPoint(x: leading, y: centerY),
            .middleCenter: CGPoint(x: centerX, y: centerY),
            .middleTrailing: CGPoint(x: trailing, y: centerY),
            .bottomLeading: CGPoint(x: leading, y: bottom),
            .bottomCenter: CGPoint(x: centerX, y: bottom),
            .bottomTrailing: CGPoint(x: trailing, y: bottom)
        ]
        XCTAssertEqual(expected.count, OverlayPosition.allCases.count, "fixture sanity: all nine covered")

        for position in OverlayPosition.allCases {
            let grid = try pixels(of: bake(makeImage(), text: text, theme: theme, position: position))
            let box = try XCTUnwrap(grid.bounds(in: region(x: 0...(width - 1), y: 0...(height - 1))) {
                $0.distance(to: .white) > 30
            }, "\(position) drew nothing")
            let corner = try XCTUnwrap(expected[position])

            XCTAssertEqual(box.minX, corner.x, accuracy: 2, "\(position) left edge")
            XCTAssertEqual(box.minY, corner.y, accuracy: 2, "\(position) top edge")
            XCTAssertEqual(box.width, boxWidth, accuracy: 3, "\(position) insets scaled by \(scale)")
            XCTAssertEqual(box.height, boxHeight, accuracy: 3, "\(position) insets scaled by \(scale)")
        }
    }

    /// SwiftUI's `.shadow(y: +2)` casts downward, and so must the baked one.
    /// Core Graphics documents shadow offsets in device space (y up), so a
    /// "corrected" port that negates y casts upward instead. On mid-grey the
    /// white text and its black shadow can both be seen and compared.
    ///
    /// The margin is half the scaled offset, so a shadow with no offset at
    /// all — which would put both centroids in nearly the same place — fails
    /// too, rather than scraping through on noise.
    func test_shadowFallsBelowTheTextByItsScaledOffset() throws {
        let grey = RGB(red: 128, green: 128, blue: 128)
        let grid = try pixels(of: bake(makeImage(fill: grey), text: "第 10 天", position: .bottomTrailing))
        let area = region(x: 0...(width - 1), y: (height / 2)...(height - 1))

        let text = try XCTUnwrap(grid.centroid(in: area) { $0.red > 200 && $0.green > 200 && $0.blue > 200 })
        let shadow = try XCTUnwrap(grid.centroid(in: area) { $0.red < 100 && $0.green < 100 && $0.blue < 100 })

        let fontSize = OverlayMetrics.baseFontSize(forShortEdge: CGFloat(width))
        let scaledOffset = 2 * OverlayMetrics.decorationScale(forFontSize: fontSize)   // classicWhite: offset (0, 2)
        XCTAssertGreaterThan(shadow.y, text.y + scaledOffset * 0.5,
                             "shadow centroid \(shadow.y) vs text centroid \(text.y), scaled offset \(scaledOffset)")
    }

    /// `softPink` is the only theme with a stroke, and it is easy to lose
    /// without noticing: pink text is visible on white and on black anyway,
    /// so the legibility test cannot tell. On mid-grey the white outline is
    /// the only near-white thing in the picture.
    ///
    /// The outline must also be as wide as the preview's: 2pt at 17pt,
    /// scaled up, visible outside the glyph. A stroke drawn at the nominal
    /// width rather than double would show only half that.
    func test_softPinkStrokeIsDrawnAndAsWideAsThePreviews() throws {
        let theme = OverlayTheme.theme(for: .softPink)
        let grey = RGB(red: 128, green: 128, blue: 128)
        let grid = try pixels(of: bake(makeImage(fill: grey), text: "第 10 天", theme: theme, position: .middleCenter))
        let everywhere = region(x: 0...(width - 1), y: 0...(height - 1))

        let outline = try XCTUnwrap(grid.bounds(in: everywhere) { $0.red > 230 && $0.green > 230 && $0.blue > 230 },
                                    "no white outline at all")
        let glyphs = try XCTUnwrap(grid.bounds(in: everywhere) { $0.red > 230 && $0.green < 150 && $0.blue < 200 },
                                   "no pink fill")

        let fontSize = OverlayMetrics.fittedFontSize(for: "第 10 天",
                                                     font: .pingFang,
                                                     baseFontSize: OverlayMetrics.baseFontSize(forShortEdge: CGFloat(width)),
                                                     availableWidth: CGFloat(width) * 0.92)
        let visibleWidth = 2 * OverlayMetrics.decorationScale(forFontSize: fontSize)
        XCTAssertEqual(glyphs.minX - outline.minX, visibleWidth, accuracy: 2.5,
                       "outline visible outside the glyph on the left")
        XCTAssertEqual(outline.maxX - glyphs.maxX, visibleWidth, accuracy: 2.5,
                       "outline visible outside the glyph on the right")
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

// MARK: - TASK-18: style and placement

/// Covers TASK-18 18.4 and 18.7 ... 18.10: baking with `OverlayStyle` and
/// `OverlayPlacement` (PRD 0.2 FR-10, FR-12).
final class OverlayRendererStyleTests: XCTestCase {

    private let renderer = OverlayRenderer()
    private let text = "第 10 天"
    /// Dark text with no decoration, so ink is easy to find on white.
    private let plainDark = OverlayStyle(textColor: OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E),
                                         outline: .none, shadow: .none)

    func testUndecoratedStyleStillBakesVisibleText() throws {
        XCTAssertTrue(OverlayTheme(style: plainDark).decorations.isEmpty, "18.4")
        let grid = try bakedGrid(style: plainDark, placement: .anchor(.bottomTrailing))
        XCTAssertTrue(grid.contains(in: PixelRegion(x: 600...1190, y: 1300...1590)) { $0.distance(to: .white) > 30 },
                      "18.4: text area has ink")
    }

    /// 18.7: the "text box" is measured as the drawn box of a solid-box style,
    /// which is exactly the laid-out block. Glyph ink alone is not symmetric
    /// about the line box, so it cannot be held to ±3px.
    func testCustomCenterPlacesTheBoxCenterAtThatPoint() throws {
        let box = try solidBoxBounds(placement: .custom(x: 0.5, y: 0.5))
        XCTAssertEqual(box.midX, 1512, accuracy: 3, "18.7")
        XCTAssertEqual(box.midY, 2016, accuracy: 3, "18.7")
    }

    /// 18.8: a center at the far corner is clamped so the whole box stays one
    /// 4% margin (120.96px) inside the photo.
    func testCustomCornerIsClampedIntoTheMargin() throws {
        let box = try solidBoxBounds(placement: .custom(x: 1.0, y: 1.0))
        XCTAssertEqual(box.maxX, 3024 - 121, accuracy: 3, "18.8")
        XCTAssertEqual(box.maxY, 4032 - 121, accuracy: 3, "18.8")
    }

    func testCustomOriginClampsIntoTheMarginOnTheLeadingEdgesToo() throws {
        let box = try solidBoxBounds(placement: .custom(x: 0, y: 0))
        XCTAssertEqual(box.minX, 121, accuracy: 3)
        XCTAssertEqual(box.minY, 121, accuracy: 3)
    }

    func testEveryFontBakesVisibleText() throws {
        for fontID in OverlayFontID.allCases {
            var style = plainDark
            style.fontID = fontID
            let grid = try bakedGrid(style: style, placement: .anchor(.middleCenter))
            XCTAssertTrue(grid.contains(in: PixelRegion(x: 200...1000, y: 600...1000)) { $0.distance(to: .white) > 30 },
                          "18.9: \(fontID) drew nothing")
        }
    }

    func testEveryShadowAndOutlineCombinationBakes() throws {
        for shadow in OverlayShadow.allCases {
            for outline in OverlayOutline.allCases {
                let style = OverlayStyle(textColor: OverlayColor(red8: 0x0A, green8: 0x84, blue8: 0xFF),
                                         outline: outline, shadow: shadow)
                let grid = try bakedGrid(style: style, placement: .anchor(.middleCenter))
                XCTAssertTrue(grid.contains(in: PixelRegion(x: 200...1000, y: 600...1000)) { $0.distance(to: .white) > 30 },
                              "18.10: \(outline) + \(shadow) drew nothing")
            }
        }
    }

    func testSizeScaleEnlargesTheBakedText() throws {
        var small = plainDark
        small.sizeScale = 70
        var large = plainDark
        large.sizeScale = 160
        let smallInk = try XCTUnwrap(bakedGrid(style: small, placement: .anchor(.middleCenter))
            .bounds(in: PixelRegion(x: 0...1199, y: 0...1599)) { $0.distance(to: .white) > 30 })
        let largeInk = try XCTUnwrap(bakedGrid(style: large, placement: .anchor(.middleCenter))
            .bounds(in: PixelRegion(x: 0...1199, y: 0...1599)) { $0.distance(to: .white) > 30 })
        XCTAssertEqual(largeInk.width / smallInk.width, 160.0 / 70.0, accuracy: 0.15)
    }

    // MARK: Helpers

    /// Bakes and reads the pixels back inside an autorelease pool.
    ///
    /// Without the pool, each 3024x4032 round trip leaves ~70 MB of
    /// autoreleased image memory alive until the test method ends (measured:
    /// 94 → 164 → 234 … MB over consecutive calls; flat 24 MB with the pool).
    /// Across this class and repeated runs that grew until the simulator
    /// killed the test host (`Test crashed with signal kill`), which surfaced
    /// as an intermittent failure of whichever large-image test was running.
    private func bakedGrid(style: OverlayStyle,
                           placement: OverlayPlacement,
                           width: Int = 1200,
                           height: Int = 1600) throws -> PixelGrid {
        try autoreleasepool {
            let output = try XCTUnwrap(renderer.bake(image: try whiteImage(width: width, height: height),
                                                     text: text, style: style, placement: placement),
                                       "bake returned nil")
            return try XCTUnwrap(PixelGrid(output))
        }
    }

    /// Bounds of a black solid box baked on a 3024x4032 white photo.
    private func solidBoxBounds(placement: OverlayPlacement) throws -> CGRect {
        let style = OverlayStyle(textColor: .white, outline: .solidBox, outlineColor: .black, shadow: .none)
        let grid = try bakedGrid(style: style, placement: placement, width: 3024, height: 4032)
        return try XCTUnwrap(grid.bounds(in: PixelRegion(x: 0...3023, y: 0...4031)) { $0.distance(to: .white) > 128 })
    }

    private func whiteImage(width: Int, height: Int) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}

// MARK: - #158: renderText

/// Covers #158 D.1 ... D.3: `renderText`, the overlay drawn on its own for
/// the viewfinder and the style preview, shares `bake`'s drawing path.
final class OverlayRendererRenderTextTests: XCTestCase {

    private let renderer = OverlayRenderer()
    private let text = "第 10 天"
    private let blue = OverlayColor(red8: 0x0A, green8: 0x84, blue8: 0xFF)

    /// D.1: `renderText` at 1x, laid on a white photo where `bake` would put
    /// the block, matches what `bake` draws there.
    ///
    /// The placement puts the block on a whole pixel. At a fractional origin
    /// `bake` draws straight onto the subpixel position while the composite
    /// resamples a finished image, which blurs every edge by up to half a
    /// pixel — a difference in compositing, not in how the text is drawn.
    ///
    /// The last case stands in an "available" font that is not PingFang
    /// (Snell Roundhand, which ships with iOS, for its overhang) and passes
    /// the same resolved font to both paths, as TASK-35 will (32.7).
    func test_D1_renderTextComposedOnAPhotoMatchesBake() throws {
        let stand = OverlayMetrics.resolvedFont(state: .available, postScriptName: "SnellRoundhand-Bold")
        XCTAssertEqual(stand.postScriptName, "SnellRoundhand-Bold", "fixture sanity")
        let cases: [(OverlayStyle, ResolvedOverlayFont)] = [
            (OverlayStyle(textColor: blue, outline: .none, shadow: .none), .pingFang),
            (OverlayStyle(textColor: .white, outline: .thickStroke, outlineColor: .black, shadow: .none), .pingFang),
            (OverlayStyle(textColor: .white, outline: .solidBox, outlineColor: .black, shadow: .soft), .pingFang),
            (OverlayStyle(textColor: blue, outline: .thinStroke, shadow: .glow), .pingFang),
            (OverlayStyle(fontID: .iansui, textColor: blue, outline: .thickStroke, shadow: .hard), stand)
        ]
        let frameSize = CGSize(width: 1200, height: 1600)
        for (style, font) in cases {
            for wholePixelOrigin in [CGPoint(x: 400, y: 600), CGPoint(x: 150, y: 1300)] {
                try autoreleasepool {
                    let fontSize = OverlayRenderer.fittedFontSize(for: text, style: style, frameSize: frameSize,
                                                                  font: font)
                    let rendered = try XCTUnwrap(renderer.renderText(text, style: style, fontSize: fontSize,
                                                                     displayScale: 1, font: font))
                    let placement = OverlayPlacement.custom(
                        x: Double((wholePixelOrigin.x + rendered.blockSize.width / 2) / frameSize.width),
                        y: Double((wholePixelOrigin.y + rendered.blockSize.height / 2) / frameSize.height))
                    let baked = try XCTUnwrap(renderer.bake(image: whiteImage(frameSize), text: text,
                                                            style: style, placement: placement, font: font))
                    let origin = OverlayMetrics.origin(forBlockSize: rendered.blockSize, in: frameSize,
                                                       placement: placement)
                    let imageFrame = rendered.imageFrame(forBlockOrigin: origin)
                    let composed = composite(rendered.image, in: imageFrame, onWhite: frameSize)

                    let bakedGrid = try XCTUnwrap(PixelGrid(baked))
                    let composedGrid = try XCTUnwrap(PixelGrid(composed))
                    let area = imageFrame.intersection(CGRect(origin: .zero, size: frameSize)).integral
                    let region = PixelRegion(x: Int(area.minX)...Int(area.maxX) - 1,
                                             y: Int(area.minY)...Int(area.maxY) - 1)
                    XCTAssertTrue(bakedGrid.contains(in: region) { $0.distance(to: .white) > 30 },
                                  "D.1: \(style) baked nothing to compare")
                    let difference = meanDifference(bakedGrid, composedGrid, in: region)
                    XCTAssertEqual(origin.x, wholePixelOrigin.x, accuracy: 0.01)
                    XCTAssertLessThan(difference, 0.02, "D.1: \(style) at \(placement)")
                }
            }
        }
    }

    /// D.2: heavy decorations stay inside the image; its outermost ring of
    /// pixels is fully transparent. Swash faces that ship with iOS stand in
    /// for the downloadable fonts, which a unit test cannot fetch, for their
    /// overhang.
    func test_D2_heavyDecorationsAreNeverClipped() throws {
        var cases: [(OverlayStyle, ResolvedOverlayFont)] = [
            OverlayStyle(textColor: .white, outline: .thickStroke, outlineColor: .black, shadow: .none),
            OverlayStyle(textColor: .white, outline: .solidBox, outlineColor: .black, shadow: .none),
            OverlayStyle(textColor: .white, outline: .none, shadow: .glow),
            OverlayStyle(textColor: .white, outline: .none, shadow: .soft),
            OverlayStyle(textColor: .white, outline: .none, shadow: .hard),
            OverlayStyle(textColor: .white, outline: .solidBox, outlineColor: .black, shadow: .glow)
        ].map { ($0, .pingFang) }
        for name in ["SnellRoundhand-Bold", "Zapfino", "Didot-Bold"] {
            let font = OverlayMetrics.resolvedFont(state: .available, postScriptName: name)
            XCTAssertEqual(font.postScriptName, name, "fixture sanity")
            cases.append((OverlayStyle(textColor: .white, outline: .thickStroke, outlineColor: .black, shadow: .glow),
                          font))
        }
        for (style, font) in cases {
            for text in [text, "Day 1234 fjgy"] {
                let rendered = try XCTUnwrap(renderer.renderText(text, style: style, fontSize: 40, displayScale: 3,
                                                                 font: font))
                let alpha = try XCTUnwrap(AlphaGrid(rendered.image))
                XCTAssertTrue(alpha.hasInk, "D.2: \(style) drew nothing")
                XCTAssertEqual(alpha.maxOnBorder, 0, "D.2: \(font.postScriptName) \(style.outline) \(style.shadow) is clipped")
            }
        }
    }

    /// D.3: doubling the font size doubles the image and the stroke.
    func test_D3_doublingTheFontSizeDoublesTheImageAndTheStroke() throws {
        let plain = OverlayStyle(textColor: .white, outline: .none, shadow: .none)
        let stroked = OverlayStyle(textColor: .white, outline: .thickStroke, outlineColor: .black, shadow: .none)
        func render(_ style: OverlayStyle, _ fontSize: CGFloat) throws -> RenderedOverlayText {
            try XCTUnwrap(renderer.renderText(text, style: style, fontSize: fontSize, displayScale: 2))
        }
        let small = try render(stroked, 30)
        let large = try render(stroked, 60)
        XCTAssertEqual(large.image.size.width / small.image.size.width, 2, accuracy: 0.05, "D.3")
        XCTAssertEqual(large.image.size.height / small.image.size.height, 2, accuracy: 0.05, "D.3")
        XCTAssertEqual(large.blockSize.width / small.blockSize.width, 2, accuracy: 0.05, "D.3")

        // Stroke width read from the pixels: how much wider the inked area is
        // with the stroke than without it.
        func strokeReach(_ fontSize: CGFloat) throws -> CGFloat {
            let withStroke = try XCTUnwrap(AlphaGrid(render(stroked, fontSize).image)?.inkBounds)
            let without = try XCTUnwrap(AlphaGrid(render(plain, fontSize).image)?.inkBounds)
            return withStroke.width - without.width
        }
        let smallReach = try strokeReach(30)
        let largeReach = try strokeReach(60)
        XCTAssertGreaterThan(smallReach, 4, "D.3: no stroke measured")
        XCTAssertEqual(largeReach / smallReach, 2, accuracy: 0.25, "D.3")
    }

    func testTextInsetsLocateTheBlockInsideTheImage() throws {
        let style = OverlayStyle(textColor: .white, outline: .solidBox, outlineColor: .black, shadow: .none)
        let rendered = try XCTUnwrap(renderer.renderText(text, style: style, fontSize: 40, displayScale: 2))
        XCTAssertEqual(rendered.image.scale, 2)
        XCTAssertEqual(rendered.image.size.width,
                       rendered.textInsets.left + rendered.blockSize.width + rendered.textInsets.right, accuracy: 0.001)
        XCTAssertEqual(rendered.image.size.height,
                       rendered.textInsets.top + rendered.blockSize.height + rendered.textInsets.bottom, accuracy: 0.001)
        // The solid box is exactly the block.
        let box = try XCTUnwrap(AlphaGrid(rendered.image)?.inkBounds)
        XCTAssertEqual(box.minX / 2, rendered.textInsets.left, accuracy: 1)
        XCTAssertEqual(box.minY / 2, rendered.textInsets.top, accuracy: 1)
        XCTAssertEqual(box.width / 2, rendered.blockSize.width, accuracy: 1)
        XCTAssertEqual(box.height / 2, rendered.blockSize.height, accuracy: 1)

        let frame = rendered.imageFrame(forBlockOrigin: CGPoint(x: 100, y: 50))
        XCTAssertEqual(frame.minX, 100 - rendered.textInsets.left, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 50 - rendered.textInsets.top, accuracy: 0.001)
        XCTAssertEqual(frame.size, rendered.image.size)
    }

    func testEmptyTextOrNonPositiveSizesRenderNothing() {
        let style = OverlayStyle()
        XCTAssertNil(renderer.renderText("", style: style, fontSize: 20, displayScale: 2))
        XCTAssertNil(renderer.renderText(text, style: style, fontSize: 0, displayScale: 2))
        XCTAssertNil(renderer.renderText(text, style: style, fontSize: 20, displayScale: 0))
    }

    func testFittedFontSizeMatchesTheViewfinder() {
        for style in [OverlayStyle(), OverlayStyle(sizeScale: 160)] {
            for text in [text, String(repeating: "第 12345 天 ", count: 6)] {
                let frameSize = CGSize(width: 390, height: 520)
                XCTAssertEqual(OverlayRenderer.fittedFontSize(for: text, style: style, frameSize: frameSize),
                               OverlayTextView.fittedFontSize(for: text, style: style, frameSize: frameSize))
            }
        }
    }

    // MARK: TASK-32: one font resolution for viewfinder and photo (PRD 0.3 FR-5.14)

    /// 32.7: shrink-to-fit measures with the resolved font. A stand-in face
    /// that ships with iOS fits to exactly what measuring in that face gives,
    /// which differs from what PingFang gives.
    func test_32_7_fittingMeasuresWithTheResolvedFont() throws {
        let name = "Georgia-Bold"
        let standIn = OverlayMetrics.resolvedFont(state: .available, postScriptName: name)
        let ruler = try XCTUnwrap(UIFont(name: name, size: 10), "fixture sanity")
        let style = OverlayStyle(fontID: .songti)
        let frameSize = CGSize(width: 390, height: 520)
        let long = String(repeating: "Day 12345 ", count: 4)

        let fitted = OverlayRenderer.fittedFontSize(for: long, style: style, frameSize: frameSize, font: standIn)
        let margin = OverlayMetrics.margin(forShortEdge: 390)
        let expected = OverlayMetrics.fittedFontSize(for: long,
                                                     baseFontSize: OverlayMetrics.baseFontSize(forShortEdge: 390),
                                                     availableWidth: 390 - margin * 2) { candidate, size in
            (candidate as NSString).size(withAttributes: [.font: ruler.withSize(size)]).width
        }
        XCTAssertEqual(fitted, expected, accuracy: 0.0001, "32.7: measured in the resolved face")
        let floor = OverlayMetrics.baseFontSize(forShortEdge: 390) * OverlayMetrics.minimumFontScale
        XCTAssertGreaterThan(fitted, floor + 0.5, "fixture sanity: shrunk by measuring, not sitting on the floor")
        let inPingFang = OverlayRenderer.fittedFontSize(for: long, style: style, frameSize: frameSize, font: .pingFang)
        XCTAssertGreaterThan(abs(fitted - inPingFang), 0.1, "fixture sanity: the two faces must measure differently")
    }

    /// 32.7 / 32.7a: for the same style and availability, the viewfinder path
    /// (`fittedFontSize` + `renderText`) and the baking path (`bake`) each
    /// ask availability once for the style's font and draw exactly what the
    /// one resolved font draws.
    func test_32_7_viewfinderAndBakeUseTheSameResolution() throws {
        let style = OverlayStyle(fontID: .huninn, textColor: blue, outline: .thinStroke, shadow: .soft)
        let frameSize = CGSize(width: 600, height: 800)
        let states: [FontState] = [.available, .preparing, .failed(.other), .notDownloaded]
        for state in states {
            let spy = FontAvailabilitySpy([.huninn: state])
            let resolved = OverlayMetrics.resolvedFont(for: style.fontID, availability: spy)

            let viewfinderSize = OverlayRenderer.fittedFontSize(for: text, style: style, frameSize: frameSize,
                                                                availability: spy)
            XCTAssertEqual(viewfinderSize,
                           OverlayRenderer.fittedFontSize(for: text, style: style, frameSize: frameSize, font: resolved),
                           "32.7 \(state)")
            let viewfinder = try XCTUnwrap(renderer.renderText(text, style: style, fontSize: viewfinderSize,
                                                               displayScale: 2, availability: spy))
            let viewfinderResolved = try XCTUnwrap(renderer.renderText(text, style: style, fontSize: viewfinderSize,
                                                                       displayScale: 2, font: resolved))
            XCTAssertEqual(try XCTUnwrap(PixelGrid(viewfinder.image)).bytes,
                           try XCTUnwrap(PixelGrid(viewfinderResolved.image)).bytes, "32.7 \(state)")

            let placement = OverlayPlacement.anchor(.bottomTrailing)
            let baked = try XCTUnwrap(renderer.bake(image: whiteImage(frameSize), text: text, style: style,
                                                    placement: placement, availability: spy))
            let bakedResolved = try XCTUnwrap(renderer.bake(image: whiteImage(frameSize), text: text, style: style,
                                                            placement: placement, font: resolved))
            XCTAssertEqual(try XCTUnwrap(PixelGrid(baked)).bytes, try XCTUnwrap(PixelGrid(bakedResolved)).bytes,
                           "32.7 \(state)")
            // resolve, fit, render, bake: one question each, always about huninn.
            XCTAssertEqual(spy.asked, [.huninn, .huninn, .huninn, .huninn], "32.7 \(state)")
        }
    }

    /// 32.7a: a font reported `failed` that iOS could in fact load draws in
    /// PingFang on both paths — the same pixels as PingFang itself.
    func test_32_7a_failedButLoadableFontBakesInPingFang() throws {
        let resolved = OverlayMetrics.resolvedFont(state: .failed(.other), postScriptName: "Georgia-Bold")
        let style = OverlayStyle(fontID: .songti, textColor: blue, outline: .none, shadow: .none)
        let frameSize = CGSize(width: 600, height: 800)
        let baked = try XCTUnwrap(renderer.bake(image: whiteImage(frameSize), text: "Day 10", style: style,
                                                placement: .anchor(.middleCenter), font: resolved))
        let inPingFang = try XCTUnwrap(renderer.bake(image: whiteImage(frameSize), text: "Day 10", style: style,
                                                     placement: .anchor(.middleCenter), font: .pingFang))
        XCTAssertEqual(try XCTUnwrap(PixelGrid(baked)).bytes, try XCTUnwrap(PixelGrid(inPingFang)).bytes, "32.7a")
        XCTAssertEqual(OverlayRenderer.fittedFontSize(for: "Day 10", style: style, frameSize: frameSize, font: resolved),
                       OverlayRenderer.fittedFontSize(for: "Day 10", style: style, frameSize: frameSize,
                                                      font: .pingFang), "32.7a")
    }

    // MARK: Helpers

    private func whiteImage(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func composite(_ overlay: UIImage, in frame: CGRect, onWhite size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            overlay.draw(in: frame)
        }
    }

    /// Mean per-channel difference over `region`, 0 ... 1.
    private func meanDifference(_ first: PixelGrid, _ second: PixelGrid, in region: PixelRegion) -> Double {
        var total = 0
        var count = 0
        for y in region.y {
            for x in region.x {
                let a = first.color(x: x, y: y)
                let b = second.color(x: x, y: y)
                total += abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue)
                count += 3
            }
        }
        return count == 0 ? 0 : Double(total) / Double(count) / 255
    }
}

/// The alpha channel of an image, read back at its pixel size.
private struct AlphaGrid {
    let width: Int
    let height: Int
    let alpha: [UInt8]

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
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        self.width = width
        self.height = height
        alpha = stride(from: 3, to: buffer.count, by: 4).map { buffer[$0] }
    }

    func value(x: Int, y: Int) -> UInt8 { alpha[y * width + x] }

    var hasInk: Bool { alpha.contains { $0 > 128 } }

    /// The highest alpha on the outermost ring of pixels.
    var maxOnBorder: UInt8 {
        var highest: UInt8 = 0
        for x in 0..<width {
            highest = max(highest, value(x: x, y: 0), value(x: x, y: height - 1))
        }
        for y in 0..<height {
            highest = max(highest, value(x: 0, y: y), value(x: width - 1, y: y))
        }
        return highest
    }

    /// Bounds in pixels of every pixel more than half opaque.
    var inkBounds: CGRect? {
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for y in 0..<height {
            for x in 0..<width where value(x: x, y: y) > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
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
