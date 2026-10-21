import XCTest
@testable import DaysCam

/// Covers the ratio button's outline geometry (issue #137, I.1/I.2).
final class CameraToolbarTests: XCTestCase {
    func testOutlineHeightIsBetween21And32ForEveryRatio() {
        for ratio in CaptureAspectRatio.allCases {
            let height = RatioIconGeometry.outlineHeight(for: ratio)
            XCTAssertGreaterThanOrEqual(height, 21, "\(ratio)")
            XCTAssertLessThanOrEqual(height, 32, "\(ratio)")
        }
    }

    func testLabelFitsInsideTheOutlineWithClearanceForEveryRatio() {
        for ratio in CaptureAspectRatio.allCases {
            let height = RatioIconGeometry.outlineHeight(for: ratio)
            let width = RatioIconGeometry.outlineWidth(for: ratio)
            let labelWidth = RatioIconGeometry.labelWidth(for: ratio)
            XCTAssertLessThanOrEqual(labelWidth + 2 * RatioIconGeometry.labelInset, width + 0.01,
                                     "\(ratio): label \(labelWidth) in outline \(width)")
        }
    }

    func testThreeByFourStaysAtTheBaseHeightAndOneByOneIs21Square() {
        XCTAssertEqual(RatioIconGeometry.outlineHeight(for: .threeByFour), 28)
        XCTAssertEqual(RatioIconGeometry.outlineHeight(for: .oneByOne), 21, "37.5")
        XCTAssertEqual(RatioIconGeometry.outlineWidth(for: .oneByOne), 21, "37.5")
        XCTAssertEqual(RatioIconGeometry.outlineWidth(for: .oneByOne),
                       RatioIconGeometry.outlineWidth(for: .threeByFour), "37.5: same width as 3:4")
    }

    func testNineBySixteenGrowsToTheMaximumHeight() {
        // 9:16's label is the widest relative to its narrow outline.
        XCTAssertEqual(RatioIconGeometry.outlineHeight(for: .nineBySixteen), 32)
    }

    func testToolbarButtonsAre44() {
        XCTAssertEqual(CameraToolbar.buttonSize, 44)
    }

    func testToneNamesMatchTheCard() {
        let names = ColorTone.allCases.map(CameraToolsCapsule.toneName)
        XCTAssertEqual(names, ["冷 2", "冷 1", "標準", "暖 1", "暖 2"], "590.3")
    }

    func testTintExistsForEveryToneButStandard() {
        XCTAssertNil(ColorToneTint.tint(for: .standard), "590.4")
        for tone in ColorTone.allCases where tone != .standard {
            XCTAssertNotNil(ColorToneTint.tint(for: tone), "\(tone)")
        }
        XCTAssertEqual(ColorToneTint.tint(for: .warm2)?.opacity, 1.0)
        XCTAssertEqual(ColorToneTint.tint(for: .cool1)?.opacity, 0.5)
    }
}
