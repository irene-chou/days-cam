import XCTest
@testable import DaysCam

/// TASK-105 (#420): the overlay text's tap limit. Opening the panel from a tap
/// on the camera, and keeping focus taps off the text, went with the camera's
/// overlay (#621); the text view itself is still used by the export page.
final class OverlayTextTapTests: XCTestCase {
    /// 105.2: a touch that moves more than the tap limit is not a tap.
    func testTapLimit() {
        XCTAssertTrue(OverlayTextView.isTap(translation: .zero))
        XCTAssertTrue(OverlayTextView.isTap(translation: CGSize(width: 6, height: 8)))
        XCTAssertFalse(OverlayTextView.isTap(translation: CGSize(width: 8, height: 8)))
        XCTAssertFalse(OverlayTextView.isTap(translation: CGSize(width: 0, height: 11)))
    }
}
