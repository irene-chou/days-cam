import XCTest
@testable import DaysCam

/// Covers the camera toolbar's button size. The ratio and tone controls and
/// their tests went with the features (#621).
final class CameraToolbarTests: XCTestCase {
    func testToolbarButtonsAre44() {
        XCTAssertEqual(CameraToolbar.buttonSize, 44)
    }
}
