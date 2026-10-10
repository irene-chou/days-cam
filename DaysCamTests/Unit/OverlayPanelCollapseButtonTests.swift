import XCTest
@testable import DaysCam

/// The collapse button's constants and the room every tab leaves under its
/// last row (TASK-99, #404: 99.3, 99.6, 99.11).
final class OverlayPanelCollapseButtonTests: XCTestCase {
    func testButtonGeometry() {
        XCTAssertEqual(OverlayPanelView.collapseButtonDiameter, 40, "99.3")
        XCTAssertEqual(OverlayPanelView.collapseButtonTapSide, 44, "99.3")
        XCTAssertEqual(OverlayPanelView.collapseButtonInset, 12, "99.3")
    }

    /// 99.6: band + 12 + 44 + 8, so the last row clears the button.
    func testBottomContentInsetLeavesRoomForTheButton() {
        XCTAssertEqual(OverlayPanelView.bottomContentInset(bottomSafeAreaInset: 34), 34 + 12 + 44 + 8)
        XCTAssertEqual(OverlayPanelView.bottomContentInset(bottomSafeAreaInset: 0), 64, "99.10 4.7-inch: no band")
    }

    /// 99.7／99.11: the panel is tab bar plus content, nothing else.
    func testPanelHeightHasNoGrabber() {
        let metrics = CameraScreenLayoutMetrics(screenSize: CGSize(width: 393, height: 852),
                                                safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
        XCTAssertEqual(metrics.panelHeight, metrics.panelTabBarHeight + metrics.panelContentHeight)
        XCTAssertEqual(metrics.panelHeight, 300, accuracy: 0.01, "unchanged, so panelTop is unchanged")
    }
}
