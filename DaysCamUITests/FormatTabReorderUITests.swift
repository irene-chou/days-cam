import XCTest

/// TASK-141 (#485): the content tab reads 照片上寫什麼 → divider → 天數寫法
/// → 年改成歲; with the day count off 天數寫法 collapses and the switches
/// above stay put. With `DAYSCAM_UI_SHOT_DIR` in the test runner's
/// environment the B′ screenshots are also written there for the PR.
final class FormatTabReorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds the default profile with `startDay` as its start date, then
    /// relaunches on 2026-10-12 into the same profile directory and opens
    /// the content tab.
    private func launch(startDay: String) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = startDay
        seeding.launch()
        XCTAssertTrue(seeding.buttons["疊字設定"].waitForExistence(timeout: 10))
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", profiles]
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-10-12"
        app.launch()
        app.buttons["疊字設定"].tap()
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        XCTAssertTrue(app.buttons["天"].waitForExistence(timeout: 5))
    }

    private func shot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["DAYSCAM_UI_SHOT_DIR"], !path.isEmpty {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let device = UIDevice.current.name.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR_\(name)_\(device).png"))
        }
    }

    private func toggle(_ name: String) -> XCUIElement {
        let s = app.switches[name]
        return s.exists ? s : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }
    private func isOn(_ element: XCUIElement) -> Bool { (element.value as? String) == "1" }
    private var divider: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "formatDivider").firstMatch
    }
    private var countdownNote: XCUIElement {
        app.staticTexts["countdownAgeNote"]
    }
    /// On a short screen (iPhone SE) 年改成歲 sits below the fold of the
    /// panel's scroll view; scroll it up as a finger would.
    private func revealAgeWording() {
        if !toggle("年改成歲").isHittable { app.buttons["天"].swipeUp() }
    }

    /// 141.1／141.2 on a past start date: order top to bottom, collapse with
    /// the day count off, switches unmoved, ticks kept.
    func testOrderAndCollapseOnAPastStartDate() {
        launch(startDay: "2023-08-05")
        let heading = app.staticTexts["照片上寫什麼"]
        let unitsHeading = app.staticTexts["天數寫法"]
        XCTAssertTrue(heading.exists && unitsHeading.exists, "141.1 headings")
        XCTAssertFalse(app.staticTexts["顯示內容"].exists || app.staticTexts["天數單位"].exists, "141.1 old headings gone")
        let order = [heading, toggle("天數"), divider, unitsHeading, app.buttons["天"], toggle("年改成歲")].map(\.frame.midY)
        XCTAssertEqual(order, order.sorted(), "141.1 照片上寫什麼 → 開關 → 分隔線 → 天數寫法 → 勾選框 → 年改成歲: \(order)")
        app.buttons["週"].tap()
        XCTAssertFalse(countdownNote.exists, "141.5 no note for a past date")
        shot("141.8_past_daycount_on")

        let switchFrames = ["天數", "日期", "名稱"].map { toggle($0).frame }
        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        XCTAssertFalse(unitsHeading.exists, "141.2 collapsed")
        XCTAssertFalse(app.buttons["週"].exists, "141.2 collapsed")
        XCTAssertFalse(divider.exists, "141.2 collapsed")
        // Sub-point x jitter from re-layout is not a move; compare to 1pt.
        for (name, before) in zip(["天數", "日期", "名稱"], switchFrames) {
            let after = toggle(name).frame
            XCTAssertEqual(after.minY, before.minY, accuracy: 1, "141.2 \(name) did not move")
            XCTAssertEqual(after.minX, before.minX, accuracy: 1, "141.2 \(name) did not move")
        }
        shot("141.8_past_daycount_off")

        toggle("天數").tap()
        XCTAssertTrue(app.buttons["週"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["週"].isSelected && app.buttons["天"].isSelected, "141.2 ticks kept")
    }

    /// 141.5 on a future start date with 歲 on: the note shows under
    /// 年改成歲, and goes with 歲 off.
    func testCountdownNoteOnAFutureStartDate() {
        launch(startDay: "2027-01-16")
        XCTAssertFalse(countdownNote.exists, "141.5 歲 off")
        revealAgeWording()
        toggle("年改成歲").coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(isOn(toggle("年改成歲")))
        app.buttons["月"].tap()
        XCTAssertTrue(countdownNote.waitForExistence(timeout: 3), "141.5 note")
        XCTAssertEqual(countdownNote.label, "倒數時寫作「年」，到了那天之後才寫「歲」")
        XCTAssertGreaterThan(countdownNote.frame.minY, toggle("年改成歲").frame.minY, "141.5 under the switch")
        shot("141.8_future_daycount_on")

        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(countdownNote.exists, "collapsed with the rest")
        shot("141.8_future_daycount_off")

        toggle("天數").tap()
        XCTAssertTrue(countdownNote.waitForExistence(timeout: 3))
        revealAgeWording()
        toggle("年改成歲").coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertFalse(countdownNote.exists, "141.5 歲 off")
    }
}
