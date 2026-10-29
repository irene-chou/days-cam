import XCTest

/// The panel's collapse chevron and swipe end to end (TASK-116, #447:
/// 116.1–116.8, 116.10). The app starts from a fresh profile via
/// `-UITestFreshProfiles <name>` and skips the first-launch tour.
///
/// Screenshots for the B′ comparison (116.13) are attached to the result;
/// with `DAYSCAM_UI_SHOT_DIR` in the test runner's environment they are
/// also written there as PNGs.
final class PanelCollapseButtonUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        openPanel()
    }

    private var collapseButton: XCUIElement { app.buttons["panelCollapseButton"] }
    private var styleTab: XCUIElement { app.buttons["樣式"] }

    private func openPanel() {
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        XCTAssertTrue(styleTab.waitForExistence(timeout: 5), "the panel opened")
        XCTAssertTrue(collapseButton.waitForExistence(timeout: 5), "116.1 the collapse chevron is there while the panel is open")
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

    private var bottomInset: CGFloat { app.windows.firstMatch.frame.height >= 700 ? 34 : 0 }

    private func drag(from start: CGPoint, dy: CGFloat, dx: CGFloat = 0, velocity: XCUIGestureVelocity = .slow) {
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let from = window.withOffset(CGVector(dx: start.x, dy: start.y))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: dx, dy: dy)), withVelocity: velocity,
                   thenHoldForDuration: 0.2)
    }

    /// 116.1／116.2: the chevron shares the segmented row, sits the same
    /// distance from the right edge as the track does from the left, is at
    /// least 44pt square, and a tap collapses the panel.
    func testChevronPositionAndTapCollapses() {
        let window = app.windows.firstMatch.frame
        let frame = collapseButton.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44 - 0.5, "116.2 tap target")
        XCTAssertGreaterThanOrEqual(frame.height, 44 - 0.5, "116.2 tap target")
        let row = styleTab.frame
        XCTAssertEqual(frame.midY, row.midY, accuracy: 3, "116.1 same row as the segments")
        XCTAssertGreaterThan(frame.minX, app.buttons["內容"].frame.maxX, "116.2 does not overlap the last segment")
        XCTAssertEqual(window.maxX - frame.maxX, row.minX - window.minX - 2, accuracy: 2,
                       "116.1 right margin mirrors the track's left margin")
        XCTAssertFalse(app.descendants(matching: .any)["panelGrabber"].exists)
        attach("116.13_panel-open_style")
        collapseButton.tap()
        assertPanelClosed("116.2 the chevron collapses the panel")
        XCTAssertTrue(app.buttons["疊字設定"].exists, "the closed footer is back")
    }

    /// 116.2: tapping the last segment does not hit the chevron.
    func testTappingLastSegmentDoesNotCollapse() {
        app.buttons["內容"].tap()
        XCTAssertTrue(collapseButton.exists, "116.2 still open")
        XCTAssertTrue(app.buttons["內容"].isSelected, "and the segment switched")
    }

    /// 116.3: a downward swipe on the segmented row collapses on release.
    func testSwipeDownOnSegmentedRowCollapses() {
        let row = app.buttons["內容"].frame
        drag(from: CGPoint(x: row.midX, y: row.midY), dy: 70)
        assertPanelClosed("116.3 swipe down on the segmented row")
    }

    func testSwipeDownOnChevronCollapses() {
        let frame = collapseButton.frame
        drag(from: CGPoint(x: frame.midX, y: frame.midY), dy: 70)
        assertPanelClosed("116.3 swipe down starting on the chevron")
    }

    /// 116.4: up, sideways and short drags leave the panel alone.
    func testOtherSwipesOnSegmentedRowDoNothing() {
        let row = app.buttons["內容"].frame
        let start = CGPoint(x: row.midX, y: row.midY)
        drag(from: start, dy: -60)
        XCTAssertTrue(collapseButton.exists, "116.4 up")
        drag(from: start, dy: 0, dx: 80)
        XCTAssertTrue(collapseButton.exists, "116.4 sideways")
        drag(from: start, dy: 15)
        XCTAssertTrue(collapseButton.exists, "116.4 short")
    }

    /// 116.5: dragging down on the list scrolls it and does not collapse.
    func testSwipeDownOnListDoesNotCollapse() {
        app.buttons["字型"].tap()
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.swipeUp()
        list.swipeDown()
        list.swipeDown()
        XCTAssertTrue(collapseButton.exists, "116.5 list swipes never collapse the panel")
    }

    /// 116.7: the chevron stays put across tabs, sub-tabs and scrolling.
    func testChevronStaysPutAcrossTabsAndScrolling() {
        let resting = collapseButton.frame
        for tab in ["內容", "樣式"] {
            app.buttons[tab].tap()
            XCTAssertEqual(collapseButton.frame, resting, "116.7 same place on \(tab)")
        }
        app.buttons["字型"].tap()
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.swipeUp()
        list.swipeUp()
        XCTAssertEqual(collapseButton.frame, resting, "116.7 same place after scrolling")
        app.buttons["外框"].tap()
        XCTAssertEqual(collapseButton.frame, resting, "116.7 same place on a sub-tab")
    }

    /// 116.8: scrolled all the way down, the font list's last row sits above
    /// the home-indicator fade band.
    func testLastRowScrollsAboveTheFadeBand() {
        app.buttons["字型"].tap()
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        let rows = list.buttons.allElementsBoundByIndex
        XCTAssertFalse(rows.isEmpty, "116.8 the font list has rows")
        guard let last = rows.last else { return }
        let window = app.windows.firstMatch
        let fadeTop = window.frame.maxY - bottomInset
        for _ in 0..<10 {
            drag(from: CGPoint(x: window.frame.midX, y: fadeTop - 20),
                 dy: (styleTab.frame.maxY + 70) - (fadeTop - 20), velocity: .fast)
        }
        Thread.sleep(forTimeInterval: 0.8)
        attach("116.13_font-list-last-row")
        XCTAssertLessThanOrEqual(last.frame.maxY, fadeTop + 1,
                                 "116.8 the last row ends above the fade band — last \(last.frame) fadeTop \(fadeTop)")
        last.tap()
        XCTAssertTrue(styleTab.exists, "116.8 the last row can be operated without leaving the panel")
    }

    /// 116.10: a tap on the viewfinder still collapses the panel (FR-8.7).
    func testViewfinderTapStillCollapses() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        assertPanelClosed("116.10 viewfinder tap collapses")
    }
}
