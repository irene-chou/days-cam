import XCTest

/// The panel's floating collapse button end to end (TASK-99, #404: 99.1,
/// 99.3–99.6, 99.9). The app starts from a fresh profile via
/// `-UITestFreshProfiles <name>` and skips the first-launch tour.
///
/// Screenshots for the B′ comparison (99.12) are attached to the result;
/// with `DAYSCAM_UI_SHOT_DIR` in the test runner's environment they are
/// also written there as PNGs.
final class PanelCollapseButtonUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        openPanel()
    }

    private var collapseButton: XCUIElement { app.buttons["panelCollapseButton"] }
    private var styleTab: XCUIElement { app.buttons["樣式"] }

    private func openPanel() {
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        XCTAssertTrue(styleTab.waitForExistence(timeout: 5), "the panel opened")
        XCTAssertTrue(collapseButton.waitForExistence(timeout: 5), "99.3 the collapse button is there while the panel is open")
    }

    private func assertPanelClosed(_ message: String) {
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 3), message)
        XCTAssertFalse(styleTab.exists, message)
        XCTAssertFalse(collapseButton.exists, message)
    }

    private func attach(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["DAYSCAM_UI_SHOT_DIR"], !path.isEmpty {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    /// 99.3／99.4: the button sits 12pt in from the right edge and 12pt above
    /// the home indicator (44×44 target, so its frame reaches 10pt from
    /// each), and a tap collapses the panel.
    func testButtonPositionAndTapCollapses() {
        let window = app.windows.firstMatch.frame
        let frame = collapseButton.frame
        XCTAssertEqual(frame.width, 44, accuracy: 1, "99.3 tap target")
        XCTAssertEqual(frame.height, 44, accuracy: 1, "99.3 tap target")
        XCTAssertEqual(window.maxX - frame.maxX, 12 - 2, accuracy: 1.5, "99.3 12pt from the right edge (disc), 10pt (target)")
        // The band below the usable area is the bottom safe-area inset: 34
        // on a home-indicator phone, 0 on a 4.7-inch one.
        let bottomInset = window.height >= 700 ? 34.0 : 0.0
        XCTAssertEqual(window.maxY - frame.maxY, bottomInset + 12 - 2, accuracy: 1.5, "99.3／99.10 12pt above footerBase")
        attach("99.12_panel-open_style")
        collapseButton.tap()
        assertPanelClosed("99.4 the button collapses the panel")
        XCTAssertTrue(app.buttons["疊字設定"].exists, "the closed footer is back")
    }

    /// 99.1: there is no grabber, and pulling down from the panel's top edge
    /// neither moves nor collapses it.
    func testNoGrabberAndPullingDoesNothing() {
        XCTAssertFalse(app.descendants(matching: .any)["panelGrabber"].exists, "99.1／99.11 no grabber")
        let tabs = styleTab.frame
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.windows.firstMatch.frame.midX, dy: tabs.minY - 2))
        let restingY = tabs.minY
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 200)), withVelocity: .slow,
                    thenHoldForDuration: 0.3)
        XCTAssertTrue(styleTab.waitForExistence(timeout: 2), "99.1 still open after a pull")
        XCTAssertEqual(styleTab.frame.minY, restingY, accuracy: 2, "99.1 the panel did not move")
    }

    /// 99.5: the button stays put across tabs, sub-tabs and scrolling.
    func testButtonStaysPutAcrossTabsAndScrolling() {
        let resting = collapseButton.frame
        for tab in ["內容", "位置", "樣式"] {
            app.buttons[tab].tap()
            XCTAssertEqual(collapseButton.frame, resting, "99.5 same place on \(tab)")
        }
        app.buttons["字型"].tap()
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.swipeUp()
        list.swipeUp()
        XCTAssertEqual(collapseButton.frame, resting, "99.5 same place after scrolling")
        attach("99.12_font-list-scrolled-to-bottom")
        app.buttons["外框"].tap()
        XCTAssertEqual(collapseButton.frame, resting, "99.5 same place on a sub-tab")
    }

    /// 99.6: the font list's last row scrolls up above the button and can be
    /// tapped — it is not stuck under the disc.
    func testLastRowScrollsAboveTheButton() {
        app.buttons["字型"].tap()
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        for _ in 0..<4 { list.swipeUp() }
        let rows = list.buttons.allElementsBoundByIndex.filter { $0.isHittable }
        let last = rows.max { $0.frame.maxY < $1.frame.maxY }
        XCTAssertNotNil(last, "99.6 a last row is visible")
        if let last {
            XCTAssertLessThanOrEqual(last.frame.maxY, collapseButton.frame.minY + 1,
                                     "99.6 the last row scrolls up above the button")
            XCTAssertTrue(last.isHittable, "99.6 and can be operated")
        }
    }

    /// 99.9: a tap on the viewfinder still collapses the panel (FR-8.7).
    func testViewfinderTapStillCollapses() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        assertPanelClosed("99.9 viewfinder tap collapses")
    }
}
