import XCTest

/// The overlay panel's grabber end to end (TASK-92: 92.3–92.6, 92.9). The
/// app starts from a fresh profile via `-UITestFreshProfiles <name>`.
///
/// Screenshots for the B′ comparison (92.13) are attached to the result;
/// with `TASK92_SHOT_DIR` set in the test runner's environment they are
/// also written there as PNGs, and `pulling.marker` is created in that
/// directory while `testPullIsHeldForAScreenshot` holds the panel part way
/// down, so a shell loop can grab the simulator's screen mid-pull.
final class PanelGrabberUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        openPanel()
    }

    private var grabber: XCUIElement { app.descendants(matching: .any)["panelGrabber"] }
    private var styleTab: XCUIElement { app.buttons["樣式"] }

    private func openPanel() {
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        if !styleTab.exists { app.buttons["疊字設定"].tap() }
        XCTAssertTrue(styleTab.waitForExistence(timeout: 5))
        XCTAssertTrue(grabber.waitForExistence(timeout: 5), "92.3 the grabber is there while the panel is open")
    }

    private func assertPanelClosed(_ message: String) {
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 3), message)
        XCTAssertFalse(styleTab.exists, message)
        XCTAssertFalse(grabber.exists, message)
    }

    private func shotDirectory() -> URL? {
        guard let path = ProcessInfo.processInfo.environment["TASK92_SHOT_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func attach(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = shotDirectory() {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    private func pull(by distance: CGFloat, velocity: XCUIGestureVelocity = .default, holdFor: TimeInterval = 0) {
        let start = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: distance))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: holdFor)
    }

    /// 92.3: a tap on the grabber collapses the panel.
    func testTapOnGrabberCollapses() {
        attach("92.1_panel-open-style")
        grabber.tap()
        assertPanelClosed("92.3 tap collapses")
        XCTAssertTrue(app.buttons["疊字設定"].exists, "92.11 the closed footer is back")
    }

    /// 92.4: a pull past a third of the panel's height collapses it.
    func testLongPullCollapses() {
        pull(by: grabber.frame.height * 10, velocity: .slow)
        assertPanelClosed("92.4 long pull collapses")
    }

    /// 92.4: a short pull, released slowly (the finger rests before lifting,
    /// so there is no release velocity), springs the panel back to where it
    /// was.
    func testShortPullSpringsBack() {
        let restingY = grabber.frame.minY
        pull(by: 40, velocity: .slow, holdFor: 0.5)
        XCTAssertTrue(styleTab.waitForExistence(timeout: 2), "92.4 still open")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in abs(self.grabber.frame.minY - restingY) < 2 }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 3), .completed, "92.4 sprang back to rest")
    }

    /// 92.5: pulling up does not move the panel.
    func testUpwardPullDoesNotMovePanel() {
        let restingY = grabber.frame.minY
        pull(by: -80, velocity: .slow, holdFor: 0.5)
        XCTAssertTrue(styleTab.exists, "92.5 still open")
        XCTAssertEqual(grabber.frame.minY, restingY, accuracy: 2, "92.5 did not move")
    }

    /// 92.6: a swipe down inside a scrolled list only scrolls the list.
    func testSwipeDownInScrolledListDoesNotPullPanel() {
        styleTab.tap()
        app.buttons["字型"].tap()
        let restingY = grabber.frame.minY
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.swipeUp()
        list.swipeUp()
        attach("92.8_font-list-scrolled-to-bottom")
        list.swipeDown()
        XCTAssertTrue(styleTab.exists, "92.6 still open after a swipe down in the list")
        XCTAssertEqual(grabber.frame.minY, restingY, accuracy: 2, "92.6 the panel did not move")
    }

    /// 92.9: a tap on the viewfinder still collapses the panel (FR-8.7).
    func testViewfinderTapStillCollapses() {
        let viewfinderPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        viewfinderPoint.tap()
        assertPanelClosed("92.9 viewfinder tap collapses")
    }

    /// 92.13 (B′ mid-pull): holds the panel 60pt down for several seconds so
    /// the simulator's screen can be captured from outside; writes
    /// `pulling.marker` in `TASK92_SHOT_DIR` just before the hold.
    func testPullIsHeldForAScreenshot() {
        if let directory = shotDirectory() {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: directory.appendingPathComponent("pulling.marker").path, contents: nil)
        }
        pull(by: 60, velocity: .slow, holdFor: 8)
        XCTAssertTrue(styleTab.waitForExistence(timeout: 2), "still open after a 60pt pull")
    }
}
