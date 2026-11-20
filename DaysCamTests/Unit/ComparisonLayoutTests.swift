import UIKit
import XCTest
@testable import DaysCam

/// #740 acceptance 1-6: arrangement, crops, focus and output sizes.
final class ComparisonLayoutTests: XCTestCase {
    private func size(_ ratio: CGFloat, height: CGFloat = 1000) -> CGSize {
        CGSize(width: height * ratio, height: height)
    }

    /// 1: two 3:4 portraits sit side by side, neither is cropped.
    func testSameRatioPortraitsAreNotCropped() {
        let plan = ComparisonLayout.plan(first: size(3.0 / 4), second: size(3.0 / 4, height: 4000))
        XCTAssertEqual(plan, .init(arrangement: .sideBySide, firstCrop: nil, secondCrop: nil))
    }

    /// 2: 3:4 and 9:16 sit side by side; the slimmer 9:16 is cut top and bottom to 3:4,
    /// whichever side it is on.
    func testSlimmerPortraitIsCutToTheOther() {
        let right = ComparisonLayout.plan(first: size(3.0 / 4), second: size(9.0 / 16))
        XCTAssertEqual(right, .init(arrangement: .sideBySide, firstCrop: nil, secondCrop: 3.0 / 4))
        let left = ComparisonLayout.plan(first: size(9.0 / 16), second: size(3.0 / 4))
        XCTAssertEqual(left, .init(arrangement: .sideBySide, firstCrop: 3.0 / 4, secondCrop: nil))
    }

    /// 3: two landscapes stack; the wider is cut at the sides to the other's ratio;
    /// the same landscape ratio is not cropped.
    func testLandscapesStack() {
        let wider = ComparisonLayout.plan(first: size(4.0 / 3), second: size(16.0 / 9))
        XCTAssertEqual(wider, .init(arrangement: .stacked, firstCrop: nil, secondCrop: 4.0 / 3))
        let widerFirst = ComparisonLayout.plan(first: size(16.0 / 9), second: size(4.0 / 3))
        XCTAssertEqual(widerFirst, .init(arrangement: .stacked, firstCrop: 4.0 / 3, secondCrop: nil))
        let same = ComparisonLayout.plan(first: size(4.0 / 3), second: size(4.0 / 3, height: 3000))
        XCTAssertEqual(same, .init(arrangement: .stacked, firstCrop: nil, secondCrop: nil))
    }

    /// 4: one of each is cut to 1:1 on both, side by side; a square portrait is left whole.
    func testMixedOrientationsGoSquare() {
        let plan = ComparisonLayout.plan(first: size(3.0 / 4), second: size(4.0 / 3))
        XCTAssertEqual(plan, .init(arrangement: .sideBySide, firstCrop: 1, secondCrop: 1))
        let flipped = ComparisonLayout.plan(first: size(16.0 / 9), second: size(9.0 / 16))
        XCTAssertEqual(flipped, .init(arrangement: .sideBySide, firstCrop: 1, secondCrop: 1))
        let square = ComparisonLayout.plan(first: size(1), second: size(4.0 / 3))
        XCTAssertEqual(square, .init(arrangement: .sideBySide, firstCrop: nil, secondCrop: 1))
    }

    /// 6: ratios within 1% are the same, beyond are not.
    func testOnePercentTolerance() {
        XCTAssertTrue(ComparisonLayout.isSameRatio(0.75, 0.75 * 1.009))
        XCTAssertFalse(ComparisonLayout.isSameRatio(0.75, 0.75 * 1.02))
        let near = ComparisonLayout.plan(first: size(0.75), second: size(0.75 * 1.005))
        XCTAssertNil(near.firstCrop)
        XCTAssertNil(near.secondCrop)
    }

    /// 5: the crop is as large as it can be, centered on the focus and kept inside the image.
    func testCropFollowsTheFocus() {
        let image = CGSize(width: 900, height: 1600)
        // 9:16 to 3:4: 900 wide, 1200 tall.
        let focused = ComparisonLayout.cropRect(size: image, ratio: 3.0 / 4,
                                                focus: CGRect(x: 0.4, y: 0.45, width: 0.2, height: 0.2))
        XCTAssertEqual(focused.size, CGSize(width: 900, height: 1200))
        XCTAssertEqual(focused.minY, 1600 * 0.55 - 600, accuracy: 1, "centered on the focus")
        let top = ComparisonLayout.cropRect(size: image, ratio: 3.0 / 4, focus: CGRect(x: 0, y: 0, width: 0.1, height: 0.05))
        XCTAssertEqual(top.minY, 0, "clamped at the top")
        let bottom = ComparisonLayout.cropRect(size: image, ratio: 3.0 / 4, focus: CGRect(x: 0, y: 0.95, width: 0.1, height: 0.05))
        XCTAssertEqual(bottom.maxY, 1600, "clamped at the bottom")
        let centered = ComparisonLayout.cropRect(size: image, ratio: 3.0 / 4, focus: nil)
        XCTAssertEqual(centered.minY, 200, "no focus: centered")
        // Landscape 16:9 to 4:3 cuts the sides.
        let wide = ComparisonLayout.cropRect(size: CGSize(width: 1600, height: 900), ratio: 4.0 / 3,
                                             focus: CGRect(x: 0.8, y: 0.4, width: 0.2, height: 0.2))
        XCTAssertEqual(wide.size, CGSize(width: 1200, height: 900))
        XCTAssertEqual(wide.maxX, 1600, "clamped at the right")
        // 1:1 from a landscape.
        let square = ComparisonLayout.cropRect(size: CGSize(width: 1600, height: 900), ratio: 1, focus: nil)
        XCTAssertEqual(square, CGRect(x: 350, y: 0, width: 900, height: 900))
    }

    /// 6: side by side share a height, stacked a width, at the smaller and at most the cap.
    func testTileSizes() {
        let small = ComparisonLayout.tileSizes(first: CGSize(width: 3000, height: 4000),
                                               second: CGSize(width: 600, height: 800),
                                               arrangement: .sideBySide, maxSide: 2160)
        XCTAssertEqual(small.first, CGSize(width: 600, height: 800))
        XCTAssertEqual(small.second, CGSize(width: 600, height: 800))
        let capped = ComparisonLayout.tileSizes(first: CGSize(width: 3000, height: 4000),
                                                second: CGSize(width: 3000, height: 4000),
                                                arrangement: .sideBySide, maxSide: 2160)
        XCTAssertEqual(capped.first, CGSize(width: 1620, height: 2160))
        let stacked = ComparisonLayout.tileSizes(first: CGSize(width: 4000, height: 3000),
                                                 second: CGSize(width: 1600, height: 1200),
                                                 arrangement: .stacked, maxSide: 2160)
        XCTAssertEqual(stacked.first, CGSize(width: 1600, height: 1200))
        XCTAssertEqual(stacked.second, CGSize(width: 1600, height: 1200))
    }
}
