import XCTest

/// The corner zoom round button end to end (TASK-72, #302). The simulator has
/// no camera, so the app gets a fixed zoom plan from `-UITestZoomPresets`.
final class ZoomPresetBarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestZoomPresets", "-captureAspectRatio", "threeByFour"]
        app.launch()
    }

    private var roundButton: XCUIElement { app.buttons["zoomRoundButton"] }

    /// 72.1 / 72.6: only the round button shows, with the zoom as its label.
    func testStartsAsRoundButtonWithLabel() {
        XCTAssertTrue(roundButton.waitForExistence(timeout: 10))
        XCTAssertEqual(roundButton.label, "焦段，目前 1 倍")
        XCTAssertFalse(app.buttons["zoomPreset-焦段 2 倍"].exists)
    }

    /// 72.2 / 72.6: tapping opens the presets; picking one applies and closes.
    func testTapExpandsAndPickingCollapses() {
        XCTAssertTrue(roundButton.waitForExistence(timeout: 10))
        roundButton.tap()
        let two = app.buttons["zoomPreset-焦段 2 倍"]
        XCTAssertTrue(two.waitForExistence(timeout: 3))
        // Tap at once: on a slow runner one more query can outlast the
        // 3-second auto-collapse. `testAutoCollapses` checks the 0.5 preset.
        two.tap()
        XCTAssertTrue(roundButton.waitForExistence(timeout: 3))
        XCTAssertEqual(roundButton.label, "焦段，目前 2 倍")
        XCTAssertFalse(two.exists)
    }

    /// 72.3: auto-collapse after about 3 seconds.
    func testAutoCollapses() {
        XCTAssertTrue(roundButton.waitForExistence(timeout: 10))
        roundButton.tap()
        let two = app.buttons["zoomPreset-焦段 2 倍"]
        XCTAssertTrue(two.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["zoomPreset-焦段 0.5 倍"].exists)
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: two)
        waitForExpectations(timeout: 6)
        XCTAssertTrue(roundButton.exists)
    }

    /// 72.3: a tap on the viewfinder collapses.
    func testTapOnViewfinderCollapses() {
        XCTAssertTrue(roundButton.waitForExistence(timeout: 10))
        roundButton.tap()
        let two = app.buttons["zoomPreset-焦段 2 倍"]
        XCTAssertTrue(two.waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: two)
        waitForExpectations(timeout: 2)
    }

    /// 72.5: opening the panel hides the control.
    func testHiddenWhilePanelIsOpen() {
        XCTAssertTrue(roundButton.waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: roundButton)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["zoomPreset-焦段 2 倍"].exists)
    }

    /// 72.6: the accessibility audit finds nothing on the control's states.
    func testAccessibilityAudit() throws {
        XCTAssertTrue(roundButton.waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
        roundButton.tap()
        XCTAssertTrue(app.buttons["zoomPreset-焦段 2 倍"].waitForExistence(timeout: 3))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
    }
}
