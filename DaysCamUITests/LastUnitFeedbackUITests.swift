import XCTest

/// TASK-108 (#422): the last checked unit is not dimmed; tapping it bounces,
/// floats a hint for about 1.5 s and moves nothing; the last of 天數／日期
/// gets the same treatment.
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
    /// hint appears and goes away; 年改成歲 and 顯示內容 do not move.
    func testLastUnitStaysCheckedWithAHintAndNothingMoves() {
        let day = app.buttons["天"]
        XCTAssertTrue(day.isEnabled, "108.1 not disabled")
        XCTAssertTrue(day.isSelected, "108.1 checked")
        let ageRowBefore = app.staticTexts["年改成歲"].frame
        let contentHeadingBefore = app.staticTexts["顯示內容"].frame
        XCTAssertFalse(unitHint.exists, "108.1 no text beforehand")

        day.tap()
        XCTAssertTrue(day.isSelected, "108.1 still checked")
        XCTAssertTrue(unitHint.waitForExistence(timeout: 2), "108.1 the hint appeared")
        XCTAssertEqual(unitHint.label, "至少保留一個單位")
        XCTAssertEqual(app.staticTexts["年改成歲"].frame, ageRowBefore, "108.2 the age-wording row did not move")
        XCTAssertEqual(app.staticTexts["顯示內容"].frame, contentHeadingBefore, "108.2 the content heading did not move")
        let gone = NSPredicate(format: "exists == false")
        let wait = XCTNSPredicateExpectation(predicate: gone, object: unitHint)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 4), .completed, "108.1 the hint went away")
        XCTAssertEqual(app.staticTexts["年改成歲"].frame, ageRowBefore, "108.2 still in place after the hint")
    }

    /// 108.3: with 週 checked too, 天 can be unchecked and no hint shows.
    func testUncheckingIsAllowedOnceAnotherUnitIsChecked() {
        app.buttons["週"].tap()
        XCTAssertTrue(app.buttons["週"].isSelected)
        app.buttons["天"].tap()
        XCTAssertFalse(app.buttons["天"].isSelected, "108.3 unchecked")
        XCTAssertFalse(unitHint.waitForExistence(timeout: 1), "108.3 no hint")
    }

    /// 108.4: turning off the only one of 天數／日期 springs back with its
    /// own hint, both ways.
    func testLastContentSwitchSpringsBackWithAHint() {
        toggle("天數").tap()
        XCTAssertTrue(isOn(toggle("天數")), "108.4 springs back")
        XCTAssertTrue(contentHint.waitForExistence(timeout: 2), "108.4 the hint appeared")
        XCTAssertEqual(contentHint.label, "至少顯示天數或日期")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: contentHint)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 4), .completed)

        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        toggle("日期").tap()
        XCTAssertTrue(isOn(toggle("日期")), "108.4 the date springs back")
        XCTAssertTrue(contentHint.waitForExistence(timeout: 2), "108.4 the same hint")
    }
}
