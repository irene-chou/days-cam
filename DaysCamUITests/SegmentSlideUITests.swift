import XCTest

/// The panel's tab chip slides between segments (TASK-154, #531: 154.2–154.5).
/// `-UITestSegmentChip` exposes the chip as `panelTabSelection`;
/// `-UITestSlowSegmentSlide` stretches the slide so a test (or a screenshot)
/// can catch it mid-way; `-UITestReduceMotion` takes the no-slide path.
/// With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the 154.8
/// screenshots are also written there as PNGs.
final class SegmentSlideUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString,
                                "-UITestSegmentChip"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        XCTAssertTrue(styleTab.waitForExistence(timeout: 5), "the panel opened")
    }

    private var styleTab: XCUIElement { app.buttons["樣式"] }
    private var contentTab: XCUIElement { app.buttons["內容"] }
    private var chips: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "panelTabSelection")
    }
    private var chip: XCUIElement { chips.firstMatch }

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

    private func waitUntil(_ note: String, timeout: TimeInterval = 8, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertTrue(condition(), note)
    }

    private func isSettled(on tab: XCUIElement) -> Bool {
        abs(chip.frame.minX - tab.frame.minX) < 6 && abs(chip.frame.width - tab.frame.width) < 6
    }

    /// 154.2: from 樣式 to 內容 the chip is between the two segments midway, and there is only one.
    func testChipSlidesBetweenTheSegments() {
        launch(extra: ["-UITestSlowSegmentSlide"])
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(isSettled(on: styleTab), "154.2 starts under 樣式")
        attach("154.8_before_style")

        contentTab.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let midway = chip.frame.minX
        XCTAssertGreaterThan(midway, styleTab.frame.minX + 6, "154.2 left the first segment")
        XCTAssertLessThan(midway, contentTab.frame.minX - 6, "154.2 not there yet")
        XCTAssertEqual(chips.count, 1, "154.2 one chip while sliding")
        attach("154.8_during_slide")

        waitUntil("154.2 arrives under 內容") { isSettled(on: contentTab) }
        XCTAssertEqual(chips.count, 1)
        attach("154.8_after_content")
    }

    /// 154.3: tapping fast ends on the last one tapped, as one chip, on a segment.
    func testRapidTapsEndOnTheLastTab() {
        launch()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        contentTab.tap()
        styleTab.tap()
        contentTab.tap()
        styleTab.tap()
        contentTab.tap()

        waitUntil("154.3 settled under 內容") { isSettled(on: contentTab) }
        XCTAssertEqual(chips.count, 1, "154.3 no second chip")
        XCTAssertTrue(contentTab.isSelected, "154.3 the last tab is selected")
        XCTAssertFalse(styleTab.isSelected)
    }

    /// 154.4: with Reduce Motion the chip is on the new segment right away.
    func testReduceMotionJumpsWithoutSliding() {
        launch(extra: ["-UITestReduceMotion", "-UITestSlowSegmentSlide"])
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        contentTab.tap()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(isSettled(on: contentTab), "154.4 already there, no slide")
        XCTAssertEqual(chips.count, 1)
    }

    /// 154.5: the body still swaps in place and the collapse chevron works.
    func testBodyAndCollapseStillWork() {
        launch()
        XCTAssertTrue(app.buttons["字型"].waitForExistence(timeout: 5), "樣式 shows its sub-tabs")
        contentTab.tap()
        waitUntil("154.5 the style sub-tabs are gone") { !app.buttons["字型"].exists }
        XCTAssertTrue(contentTab.isSelected)
        app.buttons["panelCollapseButton"].tap()
        waitUntil("154.5 the panel collapsed") { !self.contentTab.exists }
    }

    /// 154.6: at the largest text size the chip is still exactly one segment.
    func testChipMatchesTheSegmentAtTheLargestTextSize() {
        launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        contentTab.tap()
        waitUntil("154.6 settled under 內容") { isSettled(on: contentTab) }
        XCTAssertEqual(chips.count, 1)
        attach("154.6_largest_text")
    }
}
