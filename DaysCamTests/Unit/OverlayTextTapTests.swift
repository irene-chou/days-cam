import XCTest
@testable import DaysCam

/// TASK-105 (#420): a tap on the overlay text opens the panel; a viewfinder
/// touch that begins on the text never focuses.
@MainActor
final class OverlayTextTapTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private let suiteName = "OverlayTextTapTests"

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeModel() -> CameraScreenModel {
        let store = ProfileStore(directory: directory)
        store.load()
        return CameraScreenModel(cameraService: CameraService(),
                                 profileStore: store,
                                 captureSettingsStore: CaptureSettingsStore(defaults: defaults),
                                 capturedPhotoStore: CapturedPhotoStore(directory: directory.appendingPathComponent("photos", isDirectory: true)))
    }

    /// 105.1: closed → the tap opens the panel; open → a second tap leaves it open.
    func testTapOpensTheClosedPanelAndLeavesAnOpenOneAlone() {
        let model = makeModel()
        XCTAssertFalse(model.panelModel.isOpen)
        model.handleOverlayTextTap()
        XCTAssertTrue(model.panelModel.isOpen, "105.1 opened")
        model.handleOverlayTextTap()
        XCTAssertTrue(model.panelModel.isOpen, "105.1 a second tap does not collapse it")
    }

    /// 105.1: the panel reopens on whichever tab it was last on.
    func testTapKeepsTheLastTab() {
        let model = makeModel()
        model.handleOverlayTextTap()
        let tabs = OverlayPanelModel.Tab.allCases
        model.panelModel.selectedTab = tabs[tabs.count - 1]
        model.closeOverlayPanel()
        model.handleOverlayTextTap()
        XCTAssertEqual(model.panelModel.selectedTab, tabs[tabs.count - 1], "105.1 same tab as before")
    }

    /// The tap also collapses the tools capsule, like every other control.
    func testTapCollapsesTheToolsCapsule() {
        let model = makeModel()
        model.toggleCameraTools()
        model.handleOverlayTextTap()
        XCTAssertFalse(model.isCameraToolsExpanded)
        XCTAssertTrue(model.panelModel.isOpen)
    }

    /// 105.3: a touch beginning inside the text's frame is the text's own;
    /// outside it, or with no frame yet, it is the viewfinder's.
    func testTouchesInsideTheTextFrameAreNotViewfinderTouches() {
        let model = makeModel()
        XCTAssertFalse(model.viewfinderTouchStartsOnOverlayText(at: CGPoint(x: 10, y: 10)), "no frame yet")
        model.overlayTextFrame = CGRect(x: 100, y: 200, width: 80, height: 30)
        XCTAssertTrue(model.viewfinderTouchStartsOnOverlayText(at: CGPoint(x: 120, y: 210)))
        XCTAssertFalse(model.viewfinderTouchStartsOnOverlayText(at: CGPoint(x: 20, y: 20)))
        XCTAssertFalse(model.viewfinderTouchStartsOnOverlayText(at: CGPoint(x: 181, y: 210)))
    }

    /// 105.3: the focus model is wired to that answer — a touch starting on
    /// the text neither focuses nor adjusts exposure.
    func testFocusModelIgnoresTouchesStartingOnTheText() {
        let model = makeModel()
        model.overlayTextFrame = CGRect(x: 100, y: 200, width: 80, height: 30)
        XCTAssertTrue(model.focusModel.shouldIgnoreTouch(CGPoint(x: 120, y: 210)))
        XCTAssertFalse(model.focusModel.shouldIgnoreTouch(CGPoint(x: 20, y: 20)))
    }

    /// 105.2: a touch that moves more than the tap limit is not a tap.
    func testTapLimit() {
        XCTAssertTrue(OverlayTextView.isTap(translation: .zero))
        XCTAssertTrue(OverlayTextView.isTap(translation: CGSize(width: 6, height: 8)))
        XCTAssertFalse(OverlayTextView.isTap(translation: CGSize(width: 8, height: 8)))
        XCTAssertFalse(OverlayTextView.isTap(translation: CGSize(width: 0, height: 11)))
    }
}
