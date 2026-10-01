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
        return Measurement(
            outline: CGRect(x: CGFloat(minX) / s, y: CGFloat(minY) / s,
                            width: CGFloat(maxX - minX + 1) / s, height: CGFloat(maxY - minY + 1) / s),
            stroke: CGFloat(run) / s,
            clearanceLeft: CGFloat(textMinX - innerMinX) / s,
            clearanceRight: CGFloat(innerMaxX - textMaxX) / s)
    }

    func testLabelClearsTheOutlineByAtLeastOnePointForEveryRatio() throws {
        for ratio in CaptureAspectRatio.allCases {
            let m = try measure(ratio)
            XCTAssertGreaterThanOrEqual(m.clearanceLeft, 1, "\(ratio) left")
            XCTAssertGreaterThanOrEqual(m.clearanceRight, 1, "\(ratio) right")
        }
    }

    func testOutlineKeepsItsRatioAndTheHeightLimit() throws {
        for ratio in CaptureAspectRatio.allCases {
            let m = try measure(ratio)
            XCTAssertLessThanOrEqual(m.outline.height, 32, "\(ratio)")
            XCTAssertEqual(m.outline.width / m.outline.height, ratio.shortToLongRatio, accuracy: 0.04, "\(ratio)")
        }
        XCTAssertEqual(try measure(.nineBySixteen).outline.height, 32, accuracy: 0.7)
    }

    func testStrokeStaysNearTheOldThickness() throws {
        for ratio in CaptureAspectRatio.allCases {
            XCTAssertLessThanOrEqual(try measure(ratio).stroke, 1.4, "\(ratio)")
        }
    }
}
