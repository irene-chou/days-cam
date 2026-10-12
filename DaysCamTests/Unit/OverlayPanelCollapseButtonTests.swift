import SwiftUI
import XCTest
@testable import DaysCam

/// The collapse chevron's constants, the swipe-to-collapse rule and the room
/// every tab leaves under its last row (TASK-116, #447: 116.2–116.4, 116.8,
/// 116.9, 116.12).
final class OverlayPanelCollapseButtonTests: XCTestCase {
    /// 116.2: the chevron's tap target is at least 44pt.
    func testTapTargetIsAtLeast44() {
        XCTAssertGreaterThanOrEqual(OverlayPanelView.collapseButtonTapSide, 44)
        XCTAssertEqual(OverlayPanelView.collapseButtonGap, 4)
    }

    /// 116.3: down 30pt, or a flick predicted to travel 80pt, collapses.
    func testDownwardSwipeCollapses() {
        XCTAssertTrue(OverlayPanelView.shouldCollapse(translation: CGSize(width: 0, height: 30),
                                                      predictedEndTranslation: CGSize(width: 0, height: 30)))
        XCTAssertTrue(OverlayPanelView.shouldCollapse(translation: CGSize(width: 5, height: 60),
                                                      predictedEndTranslation: CGSize(width: 5, height: 60)))
        XCTAssertTrue(OverlayPanelView.shouldCollapse(translation: CGSize(width: 0, height: 15),
                                                      predictedEndTranslation: CGSize(width: 0, height: 80)),
                      "a short, fast flick")
    }

    /// 116.4: short, upward, sideways or diagonal-sideways drags do nothing.
    func testOtherDragsDoNothing() {
        XCTAssertFalse(OverlayPanelView.shouldCollapse(translation: CGSize(width: 0, height: 29),
                                                       predictedEndTranslation: CGSize(width: 0, height: 79)))
        XCTAssertFalse(OverlayPanelView.shouldCollapse(translation: CGSize(width: 0, height: -60),
                                                       predictedEndTranslation: CGSize(width: 0, height: -120)), "up")
        XCTAssertFalse(OverlayPanelView.shouldCollapse(translation: CGSize(width: 80, height: 0),
                                                       predictedEndTranslation: CGSize(width: 160, height: 0)), "sideways")
        XCTAssertFalse(OverlayPanelView.shouldCollapse(translation: CGSize(width: 60, height: 40),
                                                       predictedEndTranslation: CGSize(width: 120, height: 90)),
                       "more horizontal than vertical")
        XCTAssertFalse(OverlayPanelView.shouldCollapse(translation: .zero, predictedEndTranslation: .zero))
    }

    /// 116.8: the band plus 8pt, nothing for a floating button any more.
    func testBottomContentInset() {
        XCTAssertEqual(OverlayPanelView.bottomContentInset(bottomSafeAreaInset: 34), 34 + 8)
        XCTAssertEqual(OverlayPanelView.bottomContentInset(bottomSafeAreaInset: 0), 8, "4.7-inch: no band")
    }

    /// 116.9: the panel is top padding, tab bar and content, so `panelTop`
    /// is unchanged (PR #455 moved 8pt from the content to the padding).
    func testPanelHeightUnchanged() {
        let metrics = CameraScreenLayoutMetrics(screenSize: CGSize(width: 393, height: 852),
                                                safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
        XCTAssertEqual(metrics.panelHeight, CameraScreenLayoutMetrics.panelTopPadding + metrics.panelTabBarHeight + metrics.panelContentHeight)
        XCTAssertEqual(CameraScreenLayoutMetrics.panelTopPadding, 8)
        XCTAssertEqual(metrics.panelHeight, 300, accuracy: 0.01)
    }
}
