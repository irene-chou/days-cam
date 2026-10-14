import XCTest

/// TASK-141 (#485): the content tab reads 顯示內容 → divider → 天數單位
/// → 年改成歲; with the day count off 天數單位 collapses and the switches
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
    /// The countdown note under 年改成歲 was dropped (PR #497, 2026-10-13).
    private var countdownNote: XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "倒數時寫作")).firstMatch
    }
    /// On a short screen (iPhone SE) 年改成歲 sits below the fold of the
    /// panel's scroll view; scroll it up as a finger would.
    private func revealAgeWording() {
        if !toggle("年改成歲").isHittable { app.staticTexts["顯示內容"].swipeUp(); Thread.sleep(forTimeInterval: 1) }
    }

    /// 141.1／141.2 on a past start date: order top to bottom, collapse with
    /// the day count off, switches unmoved, ticks kept.
    func testOrderAndCollapseOnAPastStartDate() {
        launch(startDay: "2023-08-05")
        let heading = app.staticTexts["顯示內容"]
        let unitsHeading = app.staticTexts["天數單位"]
        XCTAssertTrue(heading.exists && unitsHeading.exists, "141.1 headings")
        let order = [heading, toggle("天數"), divider, unitsHeading, app.buttons["天"], toggle("年改成歲")].map(\.frame.midY)
        XCTAssertEqual(order, order.sorted(), "141.1 顯示內容 → 開關 → 分隔線 → 天數單位 → 勾選框 → 年改成歲: \(order)")
        XCTAssertEqual(toggle("年改成歲").frame.maxX, toggle("名稱").frame.maxX, accuracy: 1,
                       "年改成歲 and 名稱 end on the same right edge")
        // Measured before 週 is tapped: on a short screen (iPhone SE, with
        // the 底片日期 rows #521) that tap scrolls the panel.
        let switchFrames = ["天數", "日期", "名稱"].map { toggle($0).frame }
        app.buttons["週"].tap()
        shot("141.8_past_daycount_on")

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

    /// A future start date with 歲 on: no countdown note under 年改成歲
    /// (141.5 dropped, PR #497); also takes the future-date B′ shots.
    func testNoCountdownNoteOnAFutureStartDate() {
        launch(startDay: "2027-01-16")
        revealAgeWording()
        toggle("年改成歲").coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(isOn(toggle("年改成歲")))
        app.buttons["月"].tap()
        XCTAssertFalse(countdownNote.exists, "no countdown note")
        shot("141.8_future_daycount_on")

        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(app.buttons["月"].exists, "141.2 collapsed")
        shot("141.8_future_daycount_off")
    }
}
