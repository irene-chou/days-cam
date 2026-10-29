import XCTest

/// Tap-to-focus, exposure drag and AE/AF lock end to end (TASK-73, #303). The
/// simulator has no camera, so `-UITestFocus` swaps in a fake that answers the
/// way the camera service does, with a -2...+1 EV device range.
final class FocusExposureUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(_ extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFocus", "-UITestZoomPresets"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["zoomRoundButton"].waitForExistence(timeout: 10))
    }

    private var reticle: XCUIElement { any("focusReticle") }
    private var sun: XCUIElement { any("focusSun") }
    private var lockLabel: XCUIElement { any("focusLockLabel") }

    private func any(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func viewfinder(_ dx: CGFloat = 0.5, _ dy: CGFloat = 0.4) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 73.1: a tap shows the reticle with the sun beside it, no value at 0.
    func testTapShowsReticleAndSun() {
        launch()
        viewfinder().tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3))
        XCTAssertTrue(sun.exists)
        XCTAssertEqual(sun.value as? String, "0")
        XCTAssertFalse(lockLabel.exists)
        attachScreenshot("73.1-tap-reticle")
    }

    /// 73.1: the reticle dims after ~1.5 s and goes when nothing is behind it.
    func testReticleGoesWhenUnused() {
        launch(["-UITestFocusQuickFade"])
        viewfinder().tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3))
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: reticle)
        waitForExpectations(timeout: 8)
    }

    /// 73.2: dragging up shows the value; it stays after letting go and is
    /// held to the device range (+1 up, -2 down).
    func testDragAdjustsBiasAndStopsAtTheDeviceRange() {
        launch()
        viewfinder().tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3))
        viewfinder().press(forDuration: 0.1, thenDragTo: viewfinder(0.5, 0.3))
        sleep(1)
        XCTAssertTrue((sun.value as? String)?.hasPrefix("+") == true, "value \(String(describing: sun.value))")
        attachScreenshot("73.2-bias-positive")
        viewfinder(0.5, 0.4).press(forDuration: 0.1, thenDragTo: viewfinder(0.5, 0.0))
        XCTAssertEqual(sun.value as? String, "+1.0")
        viewfinder(0.5, 0.3).press(forDuration: 0.1, thenDragTo: viewfinder(0.5, 0.78))
        XCTAssertEqual(sun.value as? String, "-2.0")
        attachScreenshot("73.2-bias-negative-limit")
    }

    /// 73.3: holding locks and shows the label; a tap unlocks.
    func testHoldLocksAndTapUnlocks() {
        launch()
        viewfinder().press(forDuration: 2.0)
        XCTAssertTrue(lockLabel.waitForExistence(timeout: 3))
        XCTAssertTrue(reticle.exists)
        attachScreenshot("73.3-locked")
        viewfinder(0.5, 0.3).tap()
        // The label is off screen a few frames after the tap, but on a busy
        // CI simulator one accessibility snapshot alone has taken over 3 s
        // (#555); the wait returns as soon as it is gone.
        XCTAssertTrue(lockLabel.waitForNonExistence(timeout: 10), "73.3 a tap unlocks")
        XCTAssertTrue(reticle.exists)
    }

    /// #315 QA: a lock the device refuses leaves no label and no reticle.
    func testFailedLockShowsNothing() {
        launch(["-UITestFocusLockFails"])
        viewfinder().press(forDuration: 2.0)
        sleep(1)
        XCTAssertFalse(lockLabel.exists)
        XCTAssertFalse(reticle.exists)
        attachScreenshot("73.7-lock-failed")
    }

    /// #315 QA: a bias the device refuses is not left on screen.
    func testFailedBiasRevertsToZero() {
        launch(["-UITestFocusBiasFails"])
        viewfinder().tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3))
        viewfinder().press(forDuration: 0.1, thenDragTo: viewfinder(0.5, 0.25))
        sleep(1)
        // Nothing took effect, so the reticle is gone; if it is still there it shows no value.
        XCTAssertTrue(!sun.exists || (sun.value as? String) == "0", "value \(String(describing: sun.value))")
        attachScreenshot("73.7-bias-failed")
    }

    /// 88.1 / 88.3 / 88.4: each tap puts one reticle at the new point, at once.
    func testRetapPutsOneReticleAtTheNewPoint() {
        launch()
        viewfinder(0.2, 0.3).tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3))
        let far = viewfinder(0.8, 0.6)
        far.tap()
        // Sampled right after the tap: it is already at the new point, not sliding.
        let target = far.screenPoint
        let deadline = Date().addingTimeInterval(0.4)
        var worst: CGFloat = 0
        repeat {
            let frame = reticle.frame
            worst = max(worst, hypot(frame.midX - target.x, frame.midY - target.y))
        } while Date() < deadline && reticle.exists
        XCTAssertLessThan(worst, 40, "the reticle slid from the old point")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "focusReticle").count, 1)
        // Same point again: still one reticle.
        far.tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "focusReticle").count, 1)
        attachScreenshot("88.1-retap")
    }

    /// 88.5a: a tap elsewhere shows the sun at 0 again.
    func testRetapResetsTheBias() {
        launch()
        viewfinder(0.5, 0.5).tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3))
        viewfinder(0.5, 0.5).press(forDuration: 0.1, thenDragTo: viewfinder(0.5, 0.3))
        XCTAssertNotEqual(sun.value as? String, "0")
        // Inside the viewfinder at every ratio: a 1:1 box left by an earlier
        // test ends above 0.7 of the screen (#541).
        viewfinder(0.25, 0.35).tap()
        let zero = NSPredicate(format: "value == '0'")
        expectation(for: zero, evaluatedWith: sun)
        waitForExpectations(timeout: 3)
    }

    /// 73.6: the round zoom button still takes its own taps and starts no focus.
    func testZoomButtonTapDoesNotFocus() {
        launch()
        app.buttons["zoomRoundButton"].tap()
        XCTAssertTrue(app.buttons["zoomPreset-焦段 2 倍"].waitForExistence(timeout: 3))
        XCTAssertFalse(reticle.exists)
    }

    /// 73.6: a tap that closes the zoom capsule does not also focus.
    func testTapClosingTheZoomCapsuleDoesNotFocus() {
        launch()
        app.buttons["zoomRoundButton"].tap()
        let two = app.buttons["zoomPreset-焦段 2 倍"]
        XCTAssertTrue(two.waitForExistence(timeout: 3))
        viewfinder(0.5, 0.35).tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: two)
        waitForExpectations(timeout: 2)
        XCTAssertFalse(reticle.exists)
    }

    /// 73.6: with the panel open a tap on the viewfinder only closes it.
    func testNoFocusWhilePanelIsOpen() {
        launch()
        app.buttons["疊字設定"].tap()
        sleep(1)
        viewfinder(0.5, 0.2).tap()
        sleep(1)
        XCTAssertFalse(reticle.exists)
    }

    /// 73.6: a two-finger pinch starts no focus.
    func testPinchDoesNotFocus() {
        launch()
        let target = app.otherElements.firstMatch
        target.pinch(withScale: 1.5, velocity: 1)
        sleep(1)
        XCTAssertFalse(reticle.exists)
    }
}
