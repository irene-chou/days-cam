import XCTest
@testable import DaysCam

/// Covers TASK-22 acceptance 22.1–22.3, 22.5, and the TASK-24 drag interface
/// this model exposes (`isOverlayDraggable`).
final class OverlayPanelModelTests: XCTestCase {

    // MARK: - Tab selection (22.1–22.3)

    func testInitialSelectedTabIsStyle() {
        // 22.1
        let model = OverlayPanelModel()
        XCTAssertEqual(model.selectedTab, .style)
    }

    func testSelectedTabSurvivesCloseThenOpenWithinTheSameInstance() {
        // 22.2
        let model = OverlayPanelModel()
        model.selectedTab = .position
        model.close()
        model.open()
        XCTAssertEqual(model.selectedTab, .position)
    }

    func testAFreshInstanceAlwaysStartsAtStyleRegardlessOfAnEarlierOne() {
        // 22.3: `selectedTab` is in-memory only (PRD 0.2 A-4) — nothing
        // persists it to disk, so a new instance (simulating a relaunch)
        // never sees an earlier one's tab.
        let earlier = OverlayPanelModel()
        earlier.selectedTab = .rules
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

    // MARK: - Bottom bar (22.5)

    func testBottomBarActionsWhenClosed() {
        let model = OverlayPanelModel()
        XCTAssertEqual(model.leftBottomBarAction, .latestPhoto)
        XCTAssertEqual(model.rightBottomBarAction, .openOverlayPanel)
    }

    func testBottomBarActionsWhenOpen() {
        let model = OverlayPanelModel()
        model.open()
        XCTAssertEqual(model.leftBottomBarAction, .manageProfiles)
        XCTAssertEqual(model.rightBottomBarAction, .collapse)
    }

    // MARK: - Overlay drag interface (TASK-24 hand-off)

    func testOverlayIsOnlyDraggableWhenOpenOnThePositionTab() {
        let model = OverlayPanelModel()
        XCTAssertFalse(model.isOverlayDraggable, "closed, any tab")

        model.selectedTab = .position
        XCTAssertFalse(model.isOverlayDraggable, "position tab but still closed")

        model.open()
        XCTAssertTrue(model.isOverlayDraggable, "open and on the position tab")

        model.selectedTab = .style
        XCTAssertFalse(model.isOverlayDraggable, "open but a different tab")
    }

    /// A fake conformer, standing in for TASK-24's position-tab model.
    private final class RecordingDragHandler: OverlayDragHandling {
        private(set) var changedCalls: [(translation: CGSize, viewfinderSize: CGSize)] = []
        private(set) var endedCalls: [(translation: CGSize, viewfinderSize: CGSize)] = []

        func overlayDragChanged(translation: CGSize, viewfinderSize: CGSize) {
            changedCalls.append((translation, viewfinderSize))
        }

        func overlayDragEnded(translation: CGSize, viewfinderSize: CGSize) {
            endedCalls.append((translation, viewfinderSize))
        }
    }

    func testOverlayDragHandlerReceivesForwardedValues() {
        let model = OverlayPanelModel()
        let handler = RecordingDragHandler()
        model.overlayDragHandler = handler

        model.overlayDragHandler?.overlayDragChanged(translation: CGSize(width: 12, height: -4),
                                                      viewfinderSize: CGSize(width: 300, height: 400))
        model.overlayDragHandler?.overlayDragEnded(translation: CGSize(width: 20, height: -10),
                                                    viewfinderSize: CGSize(width: 300, height: 400))

        XCTAssertEqual(handler.changedCalls.count, 1)
        XCTAssertEqual(handler.changedCalls.first?.translation, CGSize(width: 12, height: -4))
        XCTAssertEqual(handler.endedCalls.count, 1)
        XCTAssertEqual(handler.endedCalls.first?.translation, CGSize(width: 20, height: -10))
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
