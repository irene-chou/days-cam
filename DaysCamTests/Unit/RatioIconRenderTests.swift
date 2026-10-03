import SwiftUI
import XCTest
@testable import DaysCam

/// Renders the ratio button for real and measures the pixels (issue #137,
/// I.1/I.2): outline size, stroke thickness, and the clearance between the
/// label and the inside of the outline.
@MainActor
final class RatioIconRenderTests: XCTestCase {
    struct Measurement {
        var outline: CGRect      // points
        var stroke: CGFloat      // points
        var clearanceLeft: CGFloat
        var clearanceRight: CGFloat
        /// Edge thickness on each side (issue #169).
        var strokeLeft: CGFloat
        var strokeRight: CGFloat
        var strokeTop: CGFloat
        var strokeBottom: CGFloat
    }

    static let scale: CGFloat = 6

    func measure(_ ratio: CaptureAspectRatio) throws -> Measurement {
        let view = CameraToolbar.ratioIcon(for: ratio)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func opaque(_ x: Int, _ y: Int) -> Bool { pixels[(y * width + x) * 4 + 3] > 128 }

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height { for x in 0..<width where opaque(x, y) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        // Stroke: opaque run from each side on a row a quarter down.
        let probeY = minY + (maxY - minY) / 4
        var run = 0
        while minX + run <= maxX && opaque(minX + run, probeY) { run += 1 }
        var rightRun = 0
        while maxX - rightRun >= minX && opaque(maxX - rightRun, probeY) { rightRun += 1 }
        // Label: opaque pixels strictly inside the stroke ring.
        let innerMinX = minX + run, innerMaxX = maxX - rightRun
        // Central band only: the rounded corners poke into the ring's corners.
        let bandMargin = (maxY - minY) / 4
        let innerMinY = minY + bandMargin, innerMaxY = maxY - bandMargin
        var textMinX = Int.max, textMaxX = -1
        for y in innerMinY...innerMaxY { for x in innerMinX...innerMaxX where opaque(x, y) {
            textMinX = min(textMinX, x); textMaxX = max(textMaxX, x)
        } }
        let s = Self.scale
        // Top/bottom edges: opaque run down/up a column just inside the corner radius.
        let probeX = minX + Int(5 * s)
        var top = 0
        while minY + top <= maxY && opaque(min(probeX, maxX), minY + top) { top += 1 }
        var bottom = 0
        while maxY - bottom >= minY && opaque(min(probeX, maxX), maxY - bottom) { bottom += 1 }
        return Measurement(
            outline: CGRect(x: CGFloat(minX) / s, y: CGFloat(minY) / s,
                            width: CGFloat(maxX - minX + 1) / s, height: CGFloat(maxY - minY + 1) / s),
            stroke: CGFloat(run) / s,
            clearanceLeft: CGFloat(textMinX - innerMinX) / s,
            clearanceRight: CGFloat(innerMaxX - textMaxX) / s,
            strokeLeft: CGFloat(run) / s, strokeRight: CGFloat(rightRun) / s,
            strokeTop: CGFloat(top) / s, strokeBottom: CGFloat(bottom) / s)
    }

    /// W.1: all four edges of the outline are the same thickness.
    func testOutlineEdgesAreEquallyThick() throws {
        for ratio in CaptureAspectRatio.allCases {
            let m = try measure(ratio)
            let edges = [m.strokeLeft, m.strokeRight, m.strokeTop, m.strokeBottom]
            XCTAssertLessThanOrEqual((edges.max() ?? 0) - (edges.min() ?? 0), 0.25, "\(ratio): \(edges)")
        }
    }

    /// W.2: the outline is as thick as a neighboring 22pt medium icon (`grid`).
    func testOutlineMatchesTheGridIconStroke() throws {
        let grid = Image(systemName: "grid").font(.system(size: 22, weight: .medium)).foregroundColor(.black)
        let renderer = ImageRenderer(content: grid)
        renderer.scale = Self.scale
        let gridWidth = try gridStroke(try XCTUnwrap(renderer.uiImage?.cgImage))
        for ratio in CaptureAspectRatio.allCases {
            let m = try measure(ratio)
            XCTAssertEqual(m.strokeLeft, gridWidth, accuracy: 0.25, "\(ratio) vs grid \(gridWidth)")
            XCTAssertEqual(m.strokeTop, gridWidth, accuracy: 0.25, "\(ratio) vs grid \(gridWidth)")
        }
    }

    func gridStroke(_ image: CGImage) throws -> CGFloat {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func opaque(_ x: Int, _ y: Int) -> Bool { pixels[(y * width + x) * 4 + 3] > 128 }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height { for x in 0..<width where opaque(x, y) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        // Median left-edge run over the central rows (skips gaps and corners).
        var runs: [Int] = []
        for y in (minY + (maxY - minY) / 4)...(maxY - (maxY - minY) / 4) {
            guard let first = (minX...maxX).first(where: { opaque($0, y) }) else { continue }
            var run = 0
            while first + run <= maxX && opaque(first + run, y) { run += 1 }
            runs.append(run)
        }
        runs.sort()
        return CGFloat(runs[runs.count / 2]) / Self.scale
    }

    func testLabelClearsTheOutlineByAtLeastOnePointForEveryRatio() throws {
        for ratio in CaptureAspectRatio.allCases {
            let m = try measure(ratio)
            XCTAssertGreaterThanOrEqual(m.clearanceLeft, 1, "\(ratio) left")
            XCTAssertGreaterThanOrEqual(m.clearanceRight, 1, "\(ratio) right")
        }
    }

    func testSchematicOutlineRespectsTheHeightLimit() throws {
        for ratio in CaptureAspectRatio.allCases {
            let m = try measure(ratio)
            XCTAssertLessThanOrEqual(m.outline.height, 32, "\(ratio)")
        }
        let tall = try measure(.nineBySixteen).outline
        let standard = try measure(.threeByFour).outline
        XCTAssertGreaterThan(tall.height, standard.height)
        XCTAssertGreaterThan(tall.width, 18)
        XCTAssertGreaterThanOrEqual(tall.width - 2 * RatioIconGeometry.labelInset,
                                    RatioIconGeometry.labelWidth(for: .nineBySixteen))
    }

    /// W.3: 3:4 and square keep #137 sizes; 9:16 uses a legible schematic outline.
    func testStandardOutlineSizesMatchIssue137() throws {
        let expected: [CaptureAspectRatio: CGSize] = [.threeByFour: CGSize(width: 21, height: 28),
                                                      .oneByOne: CGSize(width: 28, height: 28)]
        for (ratio, size) in expected {
            let m = try measure(ratio)
            XCTAssertEqual(m.outline.width, size.width, accuracy: 0.5, "\(ratio)")
            XCTAssertEqual(m.outline.height, size.height, accuracy: 0.5, "\(ratio)")
        }
    }
}
