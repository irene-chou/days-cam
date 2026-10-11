import XCTest
@testable import DaysCam

/// TASK-114 114.9: the tap-to-value mapping of `TapSeekSlider`.
final class TapSeekSliderTests: XCTestCase {
    private func seek(_ x: CGFloat, width: CGFloat = 300, radius: CGFloat = 14,
                      range: ClosedRange<Double> = 0...16, step: Double = 1) -> Double {
        TapSeekSlider.value(atX: x, trackWidth: width, thumbRadius: radius, range: range, step: step)
    }

    func testEndZonesGiveTheBounds() {
        XCTAssertEqual(seek(0), 0, "114.1 far left")
        XCTAssertEqual(seek(14), 0, "left end of the usable track")
        XCTAssertEqual(seek(-50), 0, "outside to the left")
        XCTAssertEqual(seek(286), 16, "right end of the usable track")
        XCTAssertEqual(seek(300), 16, "114.1 far right")
        XCTAssertEqual(seek(1_000), 16, "outside to the right")
    }

    func testMiddleMapsLinearlyBetweenTheThumbRadii() {
        XCTAssertEqual(seek(150), 8, "exact middle")
        // Three quarters of the usable 272pt: 14 + 204 = 218 → 12.
        XCTAssertEqual(seek(218), 12, "114.1 three quarters")
        XCTAssertEqual(seek(150, range: -8...8), 0)
        XCTAssertEqual(seek(14 + 68, range: -8...8), -4, "one quarter of an offset range")
    }

    func testSnapsToTheStepFromTheLowerBound() {
        XCTAssertEqual(seek(150, range: 1...6, step: 0.5), 3.5)
        XCTAssertEqual(seek(151, range: 1...6, step: 0.5), 3.5, "nearest step")
        XCTAssertEqual(seek(150, range: 50...200, step: 10), 130, "size scale 50…200 by 10")
        XCTAssertEqual(seek(14 + 272 * 0.74, range: 50...200, step: 10), 160, "rounds to the nearest 10")
    }

    func testNarrowTrackStillClampsToTheRange() {
        for x: CGFloat in [-10, 0, 5, 10, 20, 40] {
            let value = seek(x, width: 20, range: 0...16, step: 1)
            XCTAssertGreaterThanOrEqual(value, 0, "\(x)")
            XCTAssertLessThanOrEqual(value, 16, "\(x)")
        }
    }

    /// A tap on the thumb (within its radius of the centre) is not a seek,
    /// so a tap at the thumb's edge cannot push the value a step.
    func testTapsOnTheThumbAreNotSeeks() {
        let on = { (x: CGFloat, value: Double) in
            TapSeekSlider.isOnThumb(x: x, value: value, trackWidth: 300, thumbRadius: 14, range: 0...16)
        }
        XCTAssertEqual(TapSeekSlider.thumbCenterX(for: 8, trackWidth: 300, thumbRadius: 14, range: 0...16), 150)
        XCTAssertEqual(TapSeekSlider.thumbCenterX(for: 0, trackWidth: 300, thumbRadius: 14, range: 0...16), 14)
        XCTAssertEqual(TapSeekSlider.thumbCenterX(for: 16, trackWidth: 300, thumbRadius: 14, range: 0...16), 286)
        XCTAssertTrue(on(150, 8))
        XCTAssertTrue(on(136, 8), "left edge of the thumb")
        XCTAssertTrue(on(164, 8), "right edge of the thumb")
        XCTAssertFalse(on(135, 8))
        XCTAssertFalse(on(165, 8))
        XCTAssertTrue(on(0, 0), "the end zone belongs to the thumb at the bound")
        XCTAssertFalse(on(150, 0))
    }

    func testZeroStepDoesNotSnap() {
        XCTAssertEqual(seek(150, step: 0), 8, accuracy: 0.0001)
        XCTAssertEqual(seek(151, step: 0), 8 + 16.0 / 272, accuracy: 0.0001)
    }
}
