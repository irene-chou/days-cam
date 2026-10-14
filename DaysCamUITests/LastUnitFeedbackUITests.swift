import XCTest

/// TASK-108 (#422): the last checked unit is not dimmed; tapping it bounces,
/// shows a hint and moves nothing; the last of 天數／日期 gets the same
/// treatment. TASK-141 (#485): the hint stays until the next tap.
final class LastUnitFeedbackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        app.buttons["疊字設定"].tap()
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        XCTAssertTrue(app.buttons["天"].waitForExistence(timeout: 5))
    }

    private var unitHint: XCUIElement { app.staticTexts["unitHint"] }
    private var contentHint: XCUIElement { app.staticTexts["contentSwitchHint"] }
    private func toggle(_ name: String) -> XCUIElement {
        let s = app.switches[name]
        return s.exists ? s : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }
    private func isOn(_ element: XCUIElement) -> Bool { (element.value as? String) == "1" }

    /// 108.1／108.2: 天 alone is enabled and stays checked when tapped; the
    /// hint appears and stays until another checkbox is tapped (141.4);
    /// 年改成歲 and 顯示內容 do not move.
    func testLastUnitStaysCheckedWithAHintAndNothingMoves() {
        let day = app.buttons["天"]
        XCTAssertTrue(day.isEnabled, "108.1 not disabled")
        XCTAssertTrue(day.isSelected, "108.1 checked")
        // Distances, not absolute frames: on a short screen (iPhone SE) the
        // panel scrolls when a row is tapped, shifting everything together.
        func ageRowOffset() -> CGFloat { app.staticTexts["年改成歲"].frame.minY - unitHint.frame.minY }
        let ageRowBefore = ageRowOffset()
        let contentHeadingBefore = app.staticTexts["顯示內容"].frame.minY - unitHint.frame.minY
        // The hint line is always laid out (108.2); it carries the text only
        // while showing, so the checks read its label.
        XCTAssertNotEqual(unitHint.label, "至少保留一個單位", "108.1 no text beforehand")

        day.tap()
        XCTAssertTrue(day.isSelected, "108.1 still checked")
        let shown = NSPredicate(format: "label == '至少保留一個單位'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: unitHint)], timeout: 2), .completed, "108.1 the hint appeared")
        XCTAssertEqual(ageRowOffset(), ageRowBefore, "108.2 the age-wording row did not move")
        XCTAssertEqual(app.staticTexts["顯示內容"].frame.minY - unitHint.frame.minY, contentHeadingBefore, "108.2 the content heading did not move")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(unitHint.label, "至少保留一個單位", "141.4 still there after 3 s")
        // Let the scroll from the earlier tap settle before the next one.
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["週"].isHittable, "週 reachable")
        app.buttons["週"].tap()
        let gone = NSPredicate(format: "label != '至少保留一個單位'")
        let wait = XCTNSPredicateExpectation(predicate: gone, object: unitHint)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 2), .completed, "141.4 a checkbox tap clears it")
        XCTAssertEqual(ageRowOffset(), ageRowBefore, "108.2 still in place after the hint")
    }

    /// 108.3: with 週 checked too, 天 can be unchecked and no hint shows.
    func testUncheckingIsAllowedOnceAnotherUnitIsChecked() {
        app.buttons["週"].tap()
        XCTAssertTrue(app.buttons["週"].isSelected)
        app.buttons["天"].tap()
        XCTAssertFalse(app.buttons["天"].isSelected, "108.3 unchecked")
        XCTAssertNotEqual(unitHint.label, "至少保留一個單位", "108.3 no hint")
    }

    /// 108.4: turning off the only one of 天數／日期 springs back with its
    /// own hint, both ways.
    func testLastContentSwitchSpringsBackWithAHint() {
        toggle("天數").tap()
        XCTAssertTrue(isOn(toggle("天數")), "108.4 springs back")
        let shown = NSPredicate(format: "label == '至少顯示天數或日期'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: contentHint)], timeout: 2), .completed, "108.4 the hint appeared")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(contentHint.label, "至少顯示天數或日期", "141.3 still there after 3 s")
        toggle("名稱").tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != '至少顯示天數或日期'"), object: contentHint)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 2), .completed, "141.3 the 名稱 switch clears it")

        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        toggle("日期").tap()
        XCTAssertTrue(isOn(toggle("日期")), "108.4 the date springs back")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: contentHint)], timeout: 2), .completed, "108.4 the same hint")
    }

    /// 108.8 → TASK-141 (#485): with the day count off the 天數單位 section
    /// is not there to tap; turning the day count on brings it back.
    func testUnitSectionIsCollapsedWhileTheDayCountIsOff() {
        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        XCTAssertFalse(app.buttons["週"].exists, "141.2 collapsed")
        XCTAssertFalse(toggle("年改成歲").exists, "141.2 collapsed")
        toggle("天數").tap()
        XCTAssertTrue(app.buttons["週"].waitForExistence(timeout: 3))
        app.buttons["週"].tap()
        XCTAssertTrue(app.buttons["週"].isSelected, "works once the day count is on")
    }
}
