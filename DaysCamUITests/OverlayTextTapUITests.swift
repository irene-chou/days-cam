import XCTest

/// TASK-105 (#420): tapping the overlay text on the viewfinder opens the
/// overlay panel; it never focuses and never collapses an open panel.
final class OverlayTextTapUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // `-UITestFocus` swaps in the fake focus backend the simulator needs
        // for the reticle to appear at all (see `FocusExposureUITests`).
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFocus", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
    }

    /// The day-count text on the viewfinder (第 1 天 on a fresh profile).
    private var overlayText: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '第 '")).firstMatch
    }
    private var styleTab: XCUIElement { app.buttons["樣式"] }
    private var focusReticle: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "focusReticle")
    }

    private func tapOverlayText() {
        overlayText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// 105.1／105.3: with the panel closed, a tap on the text opens the panel
    /// and shows no focus reticle; a second tap leaves the panel open.
    func testTapOpensThePanelWithoutFocusingAndKeepsItOpen() {
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 10))
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5), "the day-count text is on screen")
        XCTAssertFalse(styleTab.exists, "the panel starts closed")
        tapOverlayText()
        XCTAssertTrue(styleTab.waitForExistence(timeout: 5), "105.1 the panel opened")
        XCTAssertEqual(focusReticle.count, 0, "105.3 no focus reticle from the tap")
        tapOverlayText()
        XCTAssertTrue(styleTab.waitForExistence(timeout: 2), "105.1 a second tap keeps the panel open")
        XCTAssertTrue(styleTab.exists)
    }

    /// 105.1: the panel reopens on the tab it was last on.
    func testTapReopensOnTheLastTab() {
        XCTAssertTrue(overlayText.waitForExistence(timeout: 10))
        tapOverlayText()
        XCTAssertTrue(styleTab.waitForExistence(timeout: 5))
        let contentTab = app.buttons["內容"]
        XCTAssertTrue(contentTab.exists)
        contentTab.tap()
        XCTAssertTrue(contentTab.isSelected)
        // Close the panel by tapping the viewfinder beside the text (FR-8.7).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 5))
        XCTAssertFalse(styleTab.waitForExistence(timeout: 2), "the panel is closed again")
        tapOverlayText()
        XCTAssertTrue(contentTab.waitForExistence(timeout: 5), "105.1 reopened")
        XCTAssertTrue(contentTab.isSelected, "105.1 on the tab it was last on")
    }

    /// 105.3: a tap beside the text still focuses (the reticle appears), so
    /// the exemption is only the text's own frame.
    func testTapBesideTheTextStillFocuses() {
        XCTAssertTrue(overlayText.waitForExistence(timeout: 10))
        let textFrame = overlayText.frame
        let point = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        XCTAssertFalse(textFrame.contains(point.screenPoint), "the probe point is beside the text")
        point.tap()
        XCTAssertTrue(focusReticle.firstMatch.waitForExistence(timeout: 3), "a tap on the picture beside the text focuses")
        XCTAssertFalse(styleTab.exists, "105.3 and does not open the panel")
    }
}
