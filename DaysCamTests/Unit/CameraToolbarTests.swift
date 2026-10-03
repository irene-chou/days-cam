import XCTest
@testable import DaysCam

/// Covers the ratio button's outline geometry (issue #137, I.1/I.2).
final class CameraToolbarTests: XCTestCase {
    func testOutlineHeightIsBetween28And32ForEveryRatio() {
        for ratio in CaptureAspectRatio.allCases {
            let height = RatioIconGeometry.outlineHeight(for: ratio)
            XCTAssertGreaterThanOrEqual(height, 28, "\(ratio)")
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

    func testOneByOneAndThreeByFourStayAtTheBaseHeight() {
        XCTAssertEqual(RatioIconGeometry.outlineHeight(for: .oneByOne), 28)
        XCTAssertEqual(RatioIconGeometry.outlineHeight(for: .threeByFour), 28)
    }

    func testNineBySixteenGrowsToTheMaximumHeight() {
        // 9:16's label is the widest relative to its narrow outline.
        XCTAssertEqual(RatioIconGeometry.outlineHeight(for: .nineBySixteen), 32)
    }

    func testToolbarButtonsAre44() {
        XCTAssertEqual(CameraToolbar.buttonSize, 44)
    }
}
