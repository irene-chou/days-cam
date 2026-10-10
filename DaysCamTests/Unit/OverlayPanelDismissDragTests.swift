import XCTest
@testable import DaysCam

/// TASK-92 (92.4, 92.5): the grabber pull's thresholds, apart from the view.
final class OverlayPanelDismissDragTests: XCTestCase {
    private let panelHeight: CGFloat = 300

    func testPanelFollowsDownwardTravelOnly() {
        XCTAssertEqual(OverlayPanelDismissDrag.offset(forTranslation: 40), 40, "92.4 follows the finger down")
        XCTAssertEqual(OverlayPanelDismissDrag.offset(forTranslation: 0), 0)
        XCTAssertEqual(OverlayPanelDismissDrag.offset(forTranslation: -40), 0, "92.5 never grows upward")
    }

    func testReleasePastAThirdOfThePanelCloses() {
        XCTAssertTrue(OverlayPanelDismissDrag.shouldClose(offset: 101, velocity: 0, panelHeight: panelHeight), "92.4 past 1/3")
        XCTAssertFalse(OverlayPanelDismissDrag.shouldClose(offset: 100, velocity: 0, panelHeight: panelHeight),
                       "92.4 exactly 1/3, released slowly: springs back")
        XCTAssertFalse(OverlayPanelDismissDrag.shouldClose(offset: 30, velocity: 200, panelHeight: panelHeight),
                       "92.4 short and slow: springs back")
    }

    func testFastDownwardFlickClosesEvenWhenShort() {
        XCTAssertTrue(OverlayPanelDismissDrag.shouldClose(offset: 20, velocity: 801, panelHeight: panelHeight), "92.4 flick")
        XCTAssertFalse(OverlayPanelDismissDrag.shouldClose(offset: 20, velocity: 800, panelHeight: panelHeight),
                       "exactly the threshold is not a flick")
        XCTAssertFalse(OverlayPanelDismissDrag.shouldClose(offset: 0, velocity: 2000, panelHeight: panelHeight),
                       "a flick that never moved the panel down does not close it")
        XCTAssertFalse(OverlayPanelDismissDrag.shouldClose(offset: 20, velocity: -2000, panelHeight: panelHeight),
                       "92.5 an upward flick never closes")
    }
}
