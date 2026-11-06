import XCTest
@testable import DaysCam

final class ToastTimingTests: XCTestCase {
    func testDefaultDurationIsUnchangedWithoutTheFlag() {
        XCTAssertEqual(ToastTiming.duration(1.6, arguments: ["-UITestSkipOnboarding"]), 1.6)
        XCTAssertEqual(ToastTiming.duration(1.5, arguments: []), 1.5)
    }

    func testFlagExtendsTheDuration() {
        XCTAssertEqual(ToastTiming.duration(1.6, arguments: ["-UITestLongToast"]), ToastTiming.uiTestDuration)
        XCTAssertGreaterThan(ToastTiming.uiTestDuration, 1.6)
    }

    func testToastDurationConstantsAreUnchanged() {
        XCTAssertEqual(PhotoDetailModel.toastDuration, 1.6)
        XCTAssertEqual(PhotoWallModel.toastDuration, 1.6)
    }
}
