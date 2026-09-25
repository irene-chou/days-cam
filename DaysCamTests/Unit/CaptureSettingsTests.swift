import XCTest
@testable import DaysCam

/// Covers TASK-19's pure enum logic (PRD 0.2 FR-7.4, FR-7.5, FR-7.7):
/// acceptance 19.1 and 19.2.
final class CaptureSettingsTests: XCTestCase {

    // MARK: - FlashMode (19.1)

    func test_flashMode_cyclesOffAutoOnOff() {
        XCTAssertEqual(FlashMode.off.next, .auto)
        XCTAssertEqual(FlashMode.off.next.next, .on)
        XCTAssertEqual(FlashMode.off.next.next.next, .off)
    }

    // MARK: - TimerSetting (19.2)

    func test_timerSetting_cyclesOffThreeTenOff() {
        var value = TimerSetting.off
        var seen: [Int] = []
        for _ in 0..<3 {
            value = value.next
            seen.append(value.rawValue)
        }
        XCTAssertEqual(seen, [3, 10, 0])
    }

    // MARK: - CaptureAspectRatio

    func test_shortToLongRatio_matchesTheNamedFraction() {
        XCTAssertEqual(CaptureAspectRatio.threeByFour.shortToLongRatio, 0.75, accuracy: 0.0001)
        XCTAssertEqual(CaptureAspectRatio.oneByOne.shortToLongRatio, 1.0, accuracy: 0.0001)
        XCTAssertEqual(CaptureAspectRatio.nineBySixteen.shortToLongRatio, 0.5625, accuracy: 0.0001)
    }
}
