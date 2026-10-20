import XCTest
@testable import DaysCam

/// Covers TASK-22 acceptance 22.1–22.3, 22.5, and the TASK-24 drag interface
/// this model exposes (`isOverlayDraggable`).
final class OverlayPanelModelTests: XCTestCase {

    // MARK: - Tab selection (22.1–22.3)

    func testFirstLayerIsTwoTabsStyleLayout() {
        // #568-1
        XCTAssertEqual(OverlayPanelModel.Tab.allCases, [.style, .content])
        XCTAssertEqual(OverlayPanelModel.Tab.allCases.map(\.title), ["樣式", "內容"])
    }

    func testInitialSelectedTabIsStyle() {
        // 22.1
        let model = OverlayPanelModel()
        XCTAssertEqual(model.selectedTab, .style)
    }

    func testSelectedTabSurvivesCloseThenOpenWithinTheSameInstance() {
        // 22.2
        let model = OverlayPanelModel()
        model.selectedTab = .content
        model.close()
        model.open()
        XCTAssertEqual(model.selectedTab, .content)
    }

    func testAFreshInstanceAlwaysStartsAtStyleRegardlessOfAnEarlierOne() {
        // 22.3: `selectedTab` is in-memory only (PRD 0.2 A-4) — nothing
        // persists it to disk, so a new instance (simulating a relaunch)
        // never sees an earlier one's tab.
        let earlier = OverlayPanelModel()
        earlier.selectedTab = .content
        earlier.open()

        let rebuilt = OverlayPanelModel()
        XCTAssertEqual(rebuilt.selectedTab, .style)
    }

    // MARK: - Open/close

    func testStartsClosed() {
        XCTAssertFalse(OverlayPanelModel().isOpen)
    }

    func testOpenThenClose() {
        let model = OverlayPanelModel()
        model.open()
        XCTAssertTrue(model.isOpen)
        model.close()
        XCTAssertFalse(model.isOpen)
    }

    // MARK: - Overlay drag interface (TASK-24 hand-off)

    func testOverlayIsDraggableWheneverThePanelIsOpenOnEitherTab() {
        // #568-4
        let model = OverlayPanelModel()
        XCTAssertFalse(model.isOverlayDraggable, "closed, style tab")

        model.selectedTab = .content
        XCTAssertFalse(model.isOverlayDraggable, "content tab but still closed")

        model.open()
        XCTAssertTrue(model.isOverlayDraggable, "open on the content tab")

        model.selectedTab = .style
        XCTAssertTrue(model.isOverlayDraggable, "open on the style tab")

        model.close()
        XCTAssertFalse(model.isOverlayDraggable, "closed again")
    }

    /// A fake conformer, standing in for TASK-24's position-tab model.
    private final class RecordingDragHandler: OverlayDragHandling {
        private(set) var changedCalls: [(center: CGPoint, viewfinderSize: CGSize)] = []
        private(set) var endedCalls: [(center: CGPoint, viewfinderSize: CGSize)] = []

        func overlayDragChanged(center: CGPoint, viewfinderSize: CGSize) {
            changedCalls.append((center, viewfinderSize))
        }

        func overlayDragEnded(center: CGPoint, viewfinderSize: CGSize) {
            endedCalls.append((center, viewfinderSize))
        }
    }

    func testOverlayDragHandlerReceivesForwardedValues() {
        let model = OverlayPanelModel()
        let handler = RecordingDragHandler()
        model.overlayDragHandler = handler

        model.overlayDragHandler?.overlayDragChanged(center: CGPoint(x: 112, y: 186),
                                                      viewfinderSize: CGSize(width: 300, height: 400))
        model.overlayDragHandler?.overlayDragEnded(center: CGPoint(x: 120, y: 180),
                                                    viewfinderSize: CGSize(width: 300, height: 400))

        XCTAssertEqual(handler.changedCalls.count, 1)
        XCTAssertEqual(handler.changedCalls.first?.center, CGPoint(x: 112, y: 186))
        XCTAssertEqual(handler.endedCalls.count, 1)
        XCTAssertEqual(handler.endedCalls.first?.center, CGPoint(x: 120, y: 180))
    }

    func testOverlayDragHandlerIsHeldWeakly() {
        // Nothing but `CameraScreen`'s own view code should keep the
        // position tab's model alive — `OverlayPanelModel` itself must not
        // extend its lifetime, or it would outlive the tab that owns it.
        let model = OverlayPanelModel()
        var handler: RecordingDragHandler? = RecordingDragHandler()
        model.overlayDragHandler = handler
        XCTAssertNotNil(model.overlayDragHandler)

        handler = nil

        XCTAssertNil(model.overlayDragHandler)
    }
}
