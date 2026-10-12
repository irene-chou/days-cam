import XCTest

/// The first-launch two-step spotlight end to end (TASK-96, #400: 96.1–96.6,
/// 96.13). Every launch passes `-UITestResetOnboarding`, which clears the
/// seen flag before the app reads it, so the tour shows; relaunches *without*
/// it check the flag was recorded. The simulator reports the camera
/// permission as answered at once, so the tour is up as soon as the camera
/// screen is.
///
/// Screenshots for the B′ comparison (96.14) are attached to the result;
/// with `DAYSCAM_UI_SHOT_DIR` in the test runner's environment they are also
/// written there as PNGs.
final class OnboardingSpotlightUITests: XCTestCase {
    private var app: XCUIApplication!
    private var profileName: String!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        profileName = UUID().uuidString
        app = XCUIApplication()
        launch(reset: true)
    }

    private func launch(reset: Bool) {
        app.launchArguments = ["-UITestFreshProfiles", profileName] + (reset ? ["-UITestResetOnboarding"] : [])
        app.launch()
    }

    private var spotlight: XCUIElement { app.descendants(matching: .any)["onboardingSpotlight"] }
    private var stepLabel: XCUIElement { app.staticTexts["onboardingStep"] }
    private var title: XCUIElement { app.staticTexts["onboardingTitle"] }
    private var message: XCUIElement { app.staticTexts["onboardingMessage"] }
    private var advance: XCUIElement { app.buttons["onboardingAdvance"] }
    private var target: XCUIElement { app.buttons["onboardingTarget"] }
    private var shutter: XCUIElement { app.buttons["快門"] }
    private var styleTab: XCUIElement { app.buttons["樣式"] }

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

    private func assertStepOne(_ note: String) {
        XCTAssertTrue(spotlight.waitForExistence(timeout: 10), note)
        XCTAssertEqual(stepLabel.label, "1 / 2", note)
        XCTAssertEqual(title.label, "設定日期", note)
        XCTAssertEqual(message.label, "點這裡設定要記錄的日子。寶寶生日會算第幾天，婚禮那天會倒數還有幾天。", note)
        XCTAssertEqual(advance.label, "下一步", note)
        XCTAssertTrue(target.label.hasPrefix("設定檔："), "\(note): the chip is the highlighted target")
    }

    private func assertStepTwo(_ note: String) {
        XCTAssertTrue(stepLabel.waitForExistence(timeout: 5), note)
        XCTAssertEqual(stepLabel.label, "2 / 2", note)
        XCTAssertEqual(title.label, "設定疊字樣式", note)
        XCTAssertEqual(message.label, "點這裡調整照片上的文字：字型、顏色、位置等等。", note)
        XCTAssertEqual(advance.label, "知道了", note)
        XCTAssertEqual(target.label, "疊字設定", "\(note): the panel button is the highlighted target")
        XCTAssertFalse(bubbleFrame.intersects(overlayText.frame), "\(note): 96.2 the bubble does not cover the day-count text")
        // The default profile now prints 我的紀錄 第 1 天 (TASK-119); the longer
        // text can push the bubble to the geometry's above-the-button fallback.
        XCTAssertTrue(bubbleFrame.maxX < target.frame.minX || bubbleFrame.maxY <= target.frame.minY,
                      "\(note): 96.2 the bubble is left of or above the button")
    }

    private var bubbleFrame: CGRect { app.descendants(matching: .any)["onboardingBubble"].frame }
    /// The day-count text on the viewfinder (第 1 天 on a fresh profile).
    private var overlayText: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '第 '")).firstMatch
    }

    private func assertTourGone(_ note: String) {
        XCTAssertTrue(shutter.waitForExistence(timeout: 5), note)
        XCTAssertFalse(spotlight.exists, note)
        XCTAssertFalse(stepLabel.exists, note)
    }

    /// 96.1 → 96.2 → 96.3: the two steps in order, then a relaunch without
    /// the tour.
    func testTwoStepsThenNeverAgain() {
        assertStepOne("96.1 step 1 after launch")
        XCTAssertFalse(shutter.isHittable, "96.1 the shutter is under the mask, not reachable")
        attach("96.1_step1")
        advance.tap()
        assertStepTwo("96.2 下一步 moves to step 2")
        attach("96.2_step2")
        advance.tap()
        assertTourGone("96.3 知道了 ends the tour")
        XCTAssertTrue(app.buttons["疊字設定"].exists, "96.3 the real panel button is back")
        attach("96.3_after")
        app.terminate()
        launch(reset: false)
        assertTourGone("96.3 no tour after a relaunch")
    }

    /// 96.4: tapping the highlighted chip opens the profile sheet and ends
    /// the tour — no step 2 after the sheet closes, none after a relaunch.
    func testTappingTheChipOpensProfilesAndEndsTheTour() {
        assertStepOne("96.4 start")
        target.tap()
        XCTAssertTrue(app.navigationBars["設定檔"].waitForExistence(timeout: 5), "96.4 the profile sheet opened")
        XCTAssertFalse(spotlight.exists, "96.4 the tour is gone under the sheet")
        attach("96.4_profiles-open")
        // Close the sheet by swiping it down (no checkmark key after TASK-101).
        let sheet = app.navigationBars["設定檔"]
        let start = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 500)))
        assertTourGone("96.4 no step 2 after closing the sheet")
        app.terminate()
        launch(reset: false)
        assertTourGone("96.4 not again after a relaunch")
    }

    /// 96.5: tapping the highlighted panel button on step 2 opens the panel
    /// and ends the tour.
    func testTappingThePanelButtonOpensThePanelAndEndsTheTour() {
        assertStepOne("96.5 start")
        advance.tap()
        assertStepTwo("96.5 step 2")
        target.tap()
        XCTAssertTrue(styleTab.waitForExistence(timeout: 5), "96.5 the panel opened")
        XCTAssertFalse(spotlight.exists, "96.5 the tour is gone")
        attach("96.5_panel-open")
        app.terminate()
        launch(reset: false)
        assertTourGone("96.5 not again after a relaunch")
    }

    /// 96.6: taps on the mask — the shutter's spot, the viewfinder, the
    /// tools toggle's spot — change nothing.
    func testTapsOnTheMaskDoNothing() {
        assertStepOne("96.6 start")
        let window = app.windows.firstMatch
        for (dx, dy) in [(0.5, 0.92), (0.5, 0.5), (0.08, 0.08), (0.9, 0.08)] {
            window.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        }
        XCTAssertEqual(stepLabel.label, "1 / 2", "96.6 still on step 1")
        XCTAssertFalse(styleTab.exists, "96.6 nothing opened")
        XCTAssertFalse(app.buttons["閃光燈"].exists, "96.6 the tools capsule did not open")
        XCTAssertFalse(app.navigationBars["設定檔"].exists, "96.6 no sheet")
        advance.tap()
        assertStepTwo("96.6 step 2")
        // Step 2's bubble sits left of the panel button, at the footer's
        // height, so the shutter's spot is under it; tap the viewfinder, the
        // toolbar and the thumbnail's row just above the bubble instead.
        let bubble = bubbleFrame
        let aboveBubble = (bubble.minY - 12) / window.frame.height
        for (dx, dy) in [(0.5, 0.3), (0.5, 0.55), (0.9, 0.08), (0.15, aboveBubble)] {
            window.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        }
        XCTAssertFalse(app.navigationBars["設定檔"].exists, "96.6 no sheet")
        XCTAssertEqual(stepLabel.label, "2 / 2", "96.6 still on step 2")
        XCTAssertFalse(styleTab.exists, "96.6 the panel did not open from the mask")
        XCTAssertFalse(app.otherElements["GalleryView"].exists)
    }

    /// 96.19: the lit-up day-count text is look-only — tapping it changes
    /// nothing and the tour goes on.
    func testTappingTheLitDayCountTextDoesNothing() {
        assertStepOne("96.19 start")
        advance.tap()
        assertStepTwo("96.19 step 2")
        XCTAssertTrue(overlayText.exists, "the day-count text is on screen")
        let before = overlayText.frame
        overlayText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(stepLabel.label, "2 / 2", "96.19 still on step 2")
        XCTAssertFalse(styleTab.exists, "96.19 nothing opened")
        XCTAssertEqual(overlayText.frame, before, "96.19 the text did not move")
        attach("96.19_step2-text-tapped")
    }

    /// 96.13: `-UITestSkipOnboarding` hides the tour for that launch only.
    func testSkipArgumentHidesTheTour() {
        app.terminate()
        app.launchArguments = ["-UITestFreshProfiles", profileName, "-UITestResetOnboarding", "-UITestSkipOnboarding"]
        app.launch()
        assertTourGone("96.13 skipped")
        app.terminate()
        launch(reset: false)
        assertStepOne("96.13 skipping left the pending record alone")
    }
}
