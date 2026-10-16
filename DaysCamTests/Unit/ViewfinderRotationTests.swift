import XCTest
@testable import DaysCam

/// #572 (1, 2, 3): the capture angle table, the layer size and the way a
/// rectangle in the turned overlay layer maps back to the viewfinder box.
final class ViewfinderRotationTests: XCTestCase {
    private let box = CGSize(width: 300, height: 400)

    /// 572.1
    func testAngleTable() {
        XCTAssertEqual(ViewfinderRotation(captureAngle: 90), .portrait)
        XCTAssertEqual(ViewfinderRotation(captureAngle: 0), .landscapeTopLeft)
        XCTAssertEqual(ViewfinderRotation(captureAngle: 180), .landscapeTopRight)
        XCTAssertEqual(ViewfinderRotation(captureAngle: 270), .upsideDown)
        XCTAssertEqual(ViewfinderRotation(captureAngle: 45), .portrait)
        XCTAssertEqual(ViewfinderRotation(captureAngle: -1), .portrait)
    }

    /// 572.1: degrees are 90 minus the capture angle (180 for 270).
    func testDegrees() {
        XCTAssertEqual(ViewfinderRotation.portrait.degrees, 0)
        XCTAssertEqual(ViewfinderRotation.landscapeTopLeft.degrees, 90)
        XCTAssertEqual(ViewfinderRotation.landscapeTopRight.degrees, -90)
        XCTAssertEqual(ViewfinderRotation.upsideDown.degrees, 180)
    }

    func testIsLandscape() {
        XCTAssertFalse(ViewfinderRotation.portrait.isLandscape)
        XCTAssertTrue(ViewfinderRotation.landscapeTopLeft.isLandscape)
        XCTAssertTrue(ViewfinderRotation.landscapeTopRight.isLandscape)
        XCTAssertFalse(ViewfinderRotation.upsideDown.isLandscape)
    }

    /// 572.2
    func testFrameSizeSwapsOnlyInLandscape() {
        XCTAssertEqual(ViewfinderRotation.portrait.frameSize(for: box), box)
        XCTAssertEqual(ViewfinderRotation.upsideDown.frameSize(for: box), box)
        XCTAssertEqual(ViewfinderRotation.landscapeTopLeft.frameSize(for: box), CGSize(width: 400, height: 300))
        XCTAssertEqual(ViewfinderRotation.landscapeTopRight.frameSize(for: box), CGSize(width: 400, height: 300))
    }

    private func assertRect(_ actual: CGRect, _ expected: CGRect, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, message, file: file, line: line)
    }

    /// 572.3: portrait is the identity, null stays null.
    func testPortraitAndNullPassThrough() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(ViewfinderRotation.portrait.boxRect(fromRotatedRect: rect, box: box), rect)
        XCTAssertTrue(ViewfinderRotation.landscapeTopLeft.boxRect(fromRotatedRect: .null, box: box).isNull)
    }

    /// 572.3: a rectangle at the layer's bottom-right corner (a 400x300 layer)
    /// lands in the box's bottom-left corner when the top edge points left.
    func testLandscapeTopLeftBottomRightGoesToBottomLeft() {
        let rect = CGRect(x: 360, y: 270, width: 40, height: 30)
        assertRect(ViewfinderRotation.landscapeTopLeft.boxRect(fromRotatedRect: rect, box: box),
                   CGRect(x: 0, y: 360, width: 30, height: 40), "bottom-left of the box")
    }

    /// 572.3: ... and in the top-right corner when the top edge points right.
    func testLandscapeTopRightBottomRightGoesToTopRight() {
        let rect = CGRect(x: 360, y: 270, width: 40, height: 30)
        assertRect(ViewfinderRotation.landscapeTopRight.boxRect(fromRotatedRect: rect, box: box),
                   CGRect(x: 270, y: 0, width: 30, height: 40), "top-right of the box")
    }

    /// 572.3: ... and in the top-left corner upside down (layer is the box's size).
    func testUpsideDownBottomRightGoesToTopLeft() {
        let rect = CGRect(x: 260, y: 360, width: 40, height: 40)
        assertRect(ViewfinderRotation.upsideDown.boxRect(fromRotatedRect: rect, box: box),
                   CGRect(x: 0, y: 0, width: 40, height: 40), "top-left of the box")
    }

    /// 572.3: the layer's centre always maps to the box's centre.
    func testCentreIsFixed() {
        for rotation in [ViewfinderRotation.landscapeTopLeft, .landscapeTopRight, .upsideDown] {
            let layer = rotation.frameSize(for: box)
            let centred = CGRect(x: layer.width / 2 - 5, y: layer.height / 2 - 5, width: 10, height: 10)
            assertRect(rotation.boxRect(fromRotatedRect: centred, box: box),
                       CGRect(x: box.width / 2 - 5, y: box.height / 2 - 5, width: 10, height: 10), "\(rotation)")
        }
    }
}
