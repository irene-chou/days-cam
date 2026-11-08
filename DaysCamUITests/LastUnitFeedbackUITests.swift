import XCTest

/// TASK-108 (#422): the last checked unit is not dimmed; tapping it bounces,
/// shows a hint and moves nothing; 天數／日期／名稱 may all be off with no
/// hint (#713). TASK-141 (#485): the hint stays until the next tap.
final class LastUnitFeedbackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        XCTAssertTrue(app.buttons["天"].waitForExistence(timeout: 5))
    }

    private var unitHint: XCUIElement { app.staticTexts["unitHint"] }
    private func toggle(_ name: String) -> XCUIElement {
        let s = app.switches[name]
        return s.exists ? s : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }
    private func isOn(_ element: XCUIElement) -> Bool { (element.value as? String) == "1" }
    /// #558: the hint shows on its card's heading line, after the title.
    private func assertHint(_ hint: XCUIElement, sitsOnHeading title: String, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let heading = app.staticTexts[title].frame
        XCTAssertEqual(hint.frame.midY, heading.midY, accuracy: 4, "\(message) same line as \(title)", file: file, line: line)
        XCTAssertGreaterThan(hint.frame.minX, heading.maxX, "\(message) right of \(title)", file: file, line: line)
    }

    /// 108.1／108.2: 天 alone is enabled and stays checked when tapped; the
    /// hint appears and stays until another checkbox is tapped (141.4);
    /// 「年」改成「歲」 and 文字內容 do not move.
    func testLastUnitStaysCheckedWithAHintAndNothingMoves() {
        let day = app.buttons["天"]
        app.revealInPanel(day)
        XCTAssertTrue(day.isEnabled, "108.1 not disabled")
        XCTAssertTrue(day.isSelected, "108.1 checked")
        // Distances, not absolute frames: on a short screen (iPhone SE) the
        // panel scrolls when a row is tapped, shifting everything together.
        func ageRowOffset() -> CGFloat { toggle("「年」改成「歲」").frame.minY - unitHint.frame.minY }
        let ageRowBefore = ageRowOffset()
        // The 文字內容 card's last row (#567): its heading can be scrolled off
        // by the time the units are on screen.
        let contentCardBefore = app.buttons["positionRow"].frame.minY - unitHint.frame.minY
        // The hint line is always laid out (108.2); it carries the text only
        // while showing, so the checks read its label.
        XCTAssertNotEqual(unitHint.label, "至少保留一個單位", "108.1 no text beforehand")

        day.tap()
        XCTAssertTrue(day.isSelected, "108.1 still checked")
        let shown = NSPredicate(format: "label == '至少保留一個單位'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: unitHint)], timeout: 2), .completed, "108.1 the hint appeared")
        XCTAssertEqual(ageRowOffset(), ageRowBefore, "108.2 the age-wording row did not move")
        XCTAssertEqual(app.buttons["positionRow"].frame.minY - unitHint.frame.minY, contentCardBefore, "108.2 the 文字內容 card did not move")
        assertHint(unitHint, sitsOnHeading: "天數單位", "#558.8")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(unitHint.label, "至少保留一個單位", "141.4 still there after 3 s")
        // Let the scroll from the earlier tap settle before the next one.
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["週"].isHittable, "週 reachable")
        app.buttons["週"].tap()
        let gone = NSPredicate(format: "label != '至少保留一個單位'")
        let wait = XCTNSPredicateExpectation(predicate: gone, object: unitHint)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 10), .completed, "141.4 a checkbox tap clears it")
        XCTAssertEqual(ageRowOffset(), ageRowBefore, "108.2 still in place after the hint")
    }

    /// 108.3: with 週 checked too, 天 can be unchecked and no hint shows.
    func testUncheckingIsAllowedOnceAnotherUnitIsChecked() {
        app.revealInPanel(app.buttons["週"])
        app.buttons["週"].tap()
        XCTAssertTrue(app.buttons["週"].isSelected)
        app.buttons["天"].tap()
        XCTAssertFalse(app.buttons["天"].isSelected, "108.3 unchecked")
        XCTAssertNotEqual(unitHint.label, "至少保留一個單位", "108.3 no hint")
    }

    /// #713-4: turning off the last of 天數／日期／名稱 sticks, with no
    /// bounce-back and no hint, and the overlay on the viewfinder goes away.
    func testAllContentSwitchesTurnOffWithoutAHint() {
        let overlay = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["overlayText", "overlayTextDraggable"])).firstMatch
        XCTAssertTrue(isOn(toggle("天數")), "starts with the day count on")
        for name in ["日期", "名稱"] where isOn(toggle(name)) {
            toggle(name).tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")), "#713-4 stays off")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(isOn(toggle("天數")), "#713-4 does not spring back")
        XCTAssertFalse(app.staticTexts["contentSwitchHint"].exists, "#713-4 no hint")
        XCTAssertFalse(app.staticTexts["至少顯示天數或日期"].exists, "#713-4 no hint text")
        XCTAssertFalse(isOn(toggle("日期")))
        XCTAssertFalse(isOn(toggle("名稱")))
        XCTAssertTrue(!overlay.exists || overlay.label.isEmpty, "#713-3 nothing drawn")
    }

    /// 108.8 → TASK-141 (#485): with the day count off the 天數單位 section
    /// is not there to tap; turning the day count on brings it back.
    func testUnitSectionIsCollapsedWhileTheDayCountIsOff() {
        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        XCTAssertFalse(app.buttons["週"].exists, "141.2 collapsed")
        XCTAssertFalse(toggle("「年」改成「歲」").exists, "141.2 collapsed")
        toggle("天數").tap()
        Thread.sleep(forTimeInterval: 0.5)
        app.revealInPanel(app.buttons["週"])
        app.buttons["週"].tap()
        XCTAssertTrue(app.buttons["週"].isSelected, "works once the day count is on")
    }
}
