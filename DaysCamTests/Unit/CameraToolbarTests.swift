import XCTest
@testable import DaysCam

/// Covers the camera toolbar's button sizes (#655 D9 top bar). The ratio and
/// tone controls and their tests went with the features (#621).
final class CameraToolbarTests: XCTestCase {
    func testToolbarButtonsAre44() {
        XCTAssertEqual(CameraToolbar.buttonSize, 44)
    }

    /// 655-1: the round keys at the top right are 8pt apart (no disc, #700).
    func test_655_1_roundKeysFitTheirTapTargets() {
        XCTAssertEqual(CameraToolbar.roundKeySpacing, 8)
    }

    /// The switcher's menu is 60% of the screen, at most 280pt.
    func testRecordMenuWidth() {
        XCTAssertEqual(RecordSwitcherMenu.width(forScreenWidth: 375), 225)
        XCTAssertEqual(RecordSwitcherMenu.width(forScreenWidth: 500), 280)
    }
}
