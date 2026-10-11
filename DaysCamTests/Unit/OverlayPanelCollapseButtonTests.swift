import SwiftUI
import XCTest
@testable import DaysCam

/// The collapse button's constants and the room every tab leaves under its
/// last row (TASK-99, #404: 99.3, 99.6, 99.11).
final class OverlayPanelCollapseButtonTests: XCTestCase {
    /// 99.3 as amended 2026-10-11: a 48pt disc that is its own tap target,
    /// centered 54pt above `footerBase` — the closed footer's button height.
    func testButtonGeometry() {
        XCTAssertEqual(OverlayPanelView.collapseButtonDiameter, 48, "99.3")
        XCTAssertEqual(OverlayPanelView.collapseButtonTapSide, 48, "99.3")
        XCTAssertEqual(OverlayPanelView.collapseButtonCenterAboveBase, 16 + 38, "99.3")
    }

    /// The button is centered exactly where the closed footer's「疊字設定」
    /// key is, so the thumb never moves between opening and closing.
    func testButtonCenterMatchesTheOpenPanelKey() {
        let metrics = CameraScreenLayoutMetrics(screenSize: CGSize(width: 393, height: 852),
                                                safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
        let center = metrics.panelCollapseButtonCenter
        XCTAssertEqual(center.x, 393 - 71.25, accuracy: 0.05)
        XCTAssertEqual(center.y, 818 - 54, accuracy: 0.05)
        XCTAssertEqual(center.y, metrics.leftFooterButtonCenter.y, accuracy: 0.05)
        XCTAssertEqual(center.x - metrics.leftFooterButtonCenter.x,
                       393 - 2 * metrics.footerSideButtonCenterInset, accuracy: 0.05, "mirrored")
    }

    /// 99.6: band + 54 + 24 + 8, so the last row clears the button.
    func testBottomContentInsetLeavesRoomForTheButton() {
        XCTAssertEqual(OverlayPanelView.bottomContentInset(bottomSafeAreaInset: 34), 34 + 54 + 24 + 8)
        XCTAssertEqual(OverlayPanelView.bottomContentInset(bottomSafeAreaInset: 0), 86, "99.10 4.7-inch: no band")
    }

    /// 99.7／99.11: the panel is tab bar plus content, nothing else.
    func testPanelHeightHasNoGrabber() {
        let metrics = CameraScreenLayoutMetrics(screenSize: CGSize(width: 393, height: 852),
                                                safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
        XCTAssertEqual(metrics.panelHeight, metrics.panelTabBarHeight + metrics.panelContentHeight)
        XCTAssertEqual(metrics.panelHeight, 300, accuracy: 0.01, "unchanged, so panelTop is unchanged")
    }
}
