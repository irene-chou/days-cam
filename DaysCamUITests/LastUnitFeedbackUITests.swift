import XCTest

/// TASK-108 (#422), moved to the record editor by #721: the last checked unit
/// is not dimmed; tapping it bounces, shows a hint and moves nothing; the hint
/// stays until the next tap (TASK-141 #485). 天數／日期／名稱 may all be off
/// with no hint (#713), and with the day count off the 內容 tab hides the 寫法
/// row while the editor keeps its unit row.
final class LastUnitFeedbackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func openEditor() {
        XCTAssertTrue(app.launchOnRecordEditor(), "the record editor is up")
        XCTAssertTrue(unit("day").waitForExistence(timeout: 5), "the unit row is on the editor")
    }

    private func openContentTab() {
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        XCTAssertTrue(toggle("天數").waitForExistence(timeout: 5))
    }

    private func unit(_ raw: String) -> XCUIElement { app.buttons["rulesUnit_\(raw)"] }
    private var unitHint: XCUIElement { app.staticTexts["rulesUnitHint"] }
    private var ageToggle: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "rulesAgeWordingToggle").firstMatch
    }
    private func toggle(_ name: String) -> XCUIElement {
        let s = app.switches[name]
        return s.exists ? s : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }
    private func isOn(_ element: XCUIElement) -> Bool { (element.value as? String) == "1" }

    /// 721.3: 天 alone is enabled and stays checked when tapped; the hint
    /// appears on the 單位 label's line and stays until another checkbox is
    /// tapped; nothing below moves.
    func testLastUnitStaysCheckedWithAHintAndNothingMoves() {
        openEditor()
        let day = unit("day")
        XCTAssertTrue(day.isEnabled, "108.1 not disabled")
        XCTAssertTrue(day.isSelected, "108.1 checked")
        let ageOffset = ageToggle.frame.minY - unitHint.frame.minY
        XCTAssertNotEqual(unitHint.label, "至少保留一個單位", "108.1 no text beforehand")

        day.tap()
        XCTAssertTrue(day.isSelected, "108.1 still checked")
        let shown = NSPredicate(format: "label == '至少保留一個單位'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: unitHint)], timeout: 2), .completed, "721.3 the hint appeared")
        XCTAssertEqual(ageToggle.frame.minY - unitHint.frame.minY, ageOffset, accuracy: 1, "108.2 the 歲 row did not move")
        XCTAssertEqual(unitHint.frame.midY, app.staticTexts["單位"].frame.midY, accuracy: 4, "721.3 same line as 單位")
        XCTAssertGreaterThan(unitHint.frame.minX, app.staticTexts["單位"].frame.maxX, "721.3 right of 單位")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(unitHint.label, "至少保留一個單位", "141.4 still there after 3 s")

        unit("week").tap()
        let gone = NSPredicate(format: "label != '至少保留一個單位'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: unitHint)], timeout: 10), .completed, "721.3 another checkbox clears it")
        XCTAssertEqual(ageToggle.frame.minY - unitHint.frame.minY, ageOffset, accuracy: 1, "108.2 still in place after the hint")
    }

    /// 108.3: with 週 checked too, 天 can be unchecked and no hint shows.
    func testUncheckingIsAllowedOnceAnotherUnitIsChecked() {
        openEditor()
        unit("week").tap()
        XCTAssertTrue(unit("week").isSelected)
        unit("day").tap()
        XCTAssertFalse(unit("day").isSelected, "108.3 unchecked")
        XCTAssertNotEqual(unitHint.label, "至少保留一個單位", "108.3 no hint")
    }

    /// 721.4: 「年」改成「歲」 can be turned on with the year unchecked; the year cell then reads 歲.
    func testAgeWordingRenamesTheYearCell() {
        openEditor()
        XCTAssertTrue(app.buttons["rulesUnit_year"].label.contains("年"))
        ageToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(isOn(ageToggle), "721.4 on without the year checked")
        XCTAssertTrue(app.buttons["rulesUnit_year"].label.contains("歲"), "721.4 the cell reads 歲")
        XCTAssertFalse(app.buttons["rulesUnit_year"].isSelected, "still unchecked")
    }

    /// #713-4: turning off the last of 天數／日期／名稱 sticks, with no
    /// bounce-back and no hint, and the overlay on the viewfinder goes away.
    func testAllContentSwitchesTurnOffWithoutAHint() {
        openContentTab()
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

    /// 721.6: with the day count off the 寫法 row is not there; turning the
    /// day count on brings it back.
    func testFormatRowIsHiddenWhileTheDayCountIsOff() {
        openContentTab()
        XCTAssertTrue(app.buttons["dayCountFormatRow"].exists, "寫法 row while the day count is on")
        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        XCTAssertFalse(app.buttons["dayCountFormatRow"].exists, "721.6 hidden")
        XCTAssertFalse(app.buttons["週"].exists, "no unit checkboxes on the 內容 tab")
        toggle("天數").tap()
        XCTAssertTrue(app.buttons["dayCountFormatRow"].waitForExistence(timeout: 3), "back once the day count is on")
    }

    /// 721.6: the editor's unit row is there whatever the content tab says.
    func testEditorKeepsTheUnitRowWithTheDayCountOffInTheModel() {
        openEditor()
        for raw in ["year", "month", "week", "day"] {
            XCTAssertTrue(unit(raw).exists, raw)
        }
    }
}
