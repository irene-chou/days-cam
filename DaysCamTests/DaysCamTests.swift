import XCTest
@testable import DaysCam

/// Placeholder so the test target has a source file before TASK-02 lands.
final class DaysCamTests: XCTestCase {
    func testSharedEnumsHaveExpectedCaseCounts() {
        XCTAssertEqual(CountingRule.allCases.count, 2)
        XCTAssertEqual(DisplayUnit.allCases.count, 4)
        XCTAssertEqual(OverlayPosition.allCases.count, 9)
        XCTAssertEqual(ThemeID.allCases.count, 5)
    }
}
