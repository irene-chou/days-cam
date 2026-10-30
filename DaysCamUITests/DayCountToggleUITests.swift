import XCTest

/// TASK-107 (#426): the content tab's 天數 switch is back; a date-only
/// profile prints only the date, the last of 天數／日期 springs back, the
/// units collapse (TASK-141). The profile list's 只顯示日期 subtitle (107.5)
/// went with the camera's profile sheet in #621.
final class DayCountToggleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
    }

    private func toggle(_ name: String) -> XCUIElement {
        let switches = app.switches[name]
        return switches.exists ? switches : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }
    /// The overlay on the export preview (the title above it also says 第 N 天).
    private var overlayText: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", ["overlayText", "overlayTextDraggable"])).firstMatch
    }
    private var units: XCUIElement { app.descendants(matching: .any).matching(identifier: "dayCountUnits").firstMatch }

    private func isOn(_ element: XCUIElement) -> Bool {
        (element.value as? String) == "1" || (element.value as? Int) == 1
    }

    private func openContentTab() {
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        XCTAssertTrue(toggle("天數").waitForExistence(timeout: 5), "107.1 the 天數 switch is there")
    }

    /// 107.1／107.2／107.4: three switches, default 天數 on; turning the date
    /// on and the day count off leaves only the date on the preview and
    /// collapses the units (TASK-141); name on adds the name after the date.
    func testDateOnlyProfilePrintsOnlyTheDate() {
        openContentTab()
        XCTAssertTrue(toggle("日期").exists && toggle("名稱").exists, "107.1 three switches")
        XCTAssertTrue(isOn(toggle("天數")), "107.1 day count on by default")
        XCTAssertFalse(isOn(toggle("日期")), "107.1 date off by default")
        XCTAssertTrue(isOn(toggle("名稱")), "107.1 name on by default (TASK-119)")
        app.revealInPanel(app.buttons["週"])
        XCTAssertTrue(app.buttons["週"].isEnabled, "units are live while the day count is on")
        app.revealInPanel(toggle("天數"))

        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")), "107.2 day count off")
        let text = overlayText
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        XCTAssertTrue(text.label.range(of: #"^\d{4}\.\d{2}\.\d{2} 我的紀錄$"#, options: .regularExpression) != nil, "107.2 date then the default name: \(text.label)")
        toggle("名稱").tap()
        XCTAssertTrue(overlayText.label.range(of: #"^\d{4}\.\d{2}\.\d{2}$"#, options: .regularExpression) != nil, "107.2 date only: \(overlayText.label)")
        // TASK-141 (#485): the units are collapsed, not inert-but-visible.
        XCTAssertFalse(app.buttons["週"].exists, "107.4 → 141.2 the units are collapsed")

        toggle("名稱").tap()
        XCTAssertTrue(overlayText.label.range(of: #"^\d{4}\.\d{2}\.\d{2} 我的紀錄$"#, options: .regularExpression) != nil, "107.2 date then name: \(overlayText.label)")

        toggle("天數").tap()
        XCTAssertTrue(isOn(toggle("天數")), "107.4 back on")
        Thread.sleep(forTimeInterval: 0.5)
        app.revealInPanel(app.buttons["天"])
        XCTAssertTrue(app.buttons["天"].isSelected, "107.4 the earlier tick is still there")
        app.buttons["週"].tap()
        XCTAssertTrue(app.buttons["週"].isSelected, "107.4 the units are live again")
    }

    /// 107.3: the last of 天數／日期 springs back, both ways.
    func testTheLastOfDayCountAndDateSpringsBack() {
        openContentTab()
        toggle("天數").tap()
        XCTAssertTrue(isOn(toggle("天數")), "107.3 the day count stays on while the date is off")
        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        toggle("日期").tap()
        XCTAssertTrue(isOn(toggle("日期")), "107.3 the date stays on while the day count is off")
    }
}
