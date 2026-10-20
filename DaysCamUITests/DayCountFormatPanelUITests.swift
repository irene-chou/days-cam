import XCTest

/// #583: the 寫法 row at the bottom of the 天數單位 card on the 內容 tab.
/// With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′
/// screenshots are also written there for the PR.
final class DayCountFormatPanelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString] + extraArguments
        app.launch()
        app.buttons["疊字設定"].tap()
        let content = contentTab
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        content.tap()
        XCTAssertTrue(app.switches["天數"].waitForExistence(timeout: 5))
    }

    private var contentTab: XCUIElement { app.buttons["版面"] }
    private var row: XCUIElement { app.buttons["dayCountFormatRow"] }
    private var expanded: XCUIElement { element("dayCountFormatExpanded") }
    private var note: XCUIElement { element("dayCountFormatNote") }
    private func option(_ raw: String) -> XCUIElement { app.buttons["dayCountFormat_\(raw)"] }
    private static let raws = ["ordinal", "plain", "dayN", "dDay"]

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The viewfinder text: draggable while the panel is open on 內容 (#568).
    private var overlayText: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", ["overlayText", "overlayTextDraggable"])).firstMatch
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
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    /// Opens the row and brings its last option (and the note, if any) on screen.
    private func expand(file: StaticString = #filePath, line: UInt = #line) {
        app.revealInPanel(row, file: file, line: line)
        if row.value as? String != "已展開" { row.tap() }
        XCTAssertTrue(expanded.waitForExistence(timeout: 3), "expanded", file: file, line: line)
        app.revealInPanel(note.exists ? note : option("dDay"), file: file, line: line)
    }

    /// 583.1–583.4: the row, its options, writing back and the dimmed state.
    func testRowExpandsSelectsAndDimsWithOtherUnits() {
        launch()
        app.revealInPanel(row)
        // 583.1: last row of the card, under 「年」改成「歲」, ≥ 44pt, collapsed.
        XCTAssertEqual(row.label, "寫法，第 N 天")
        XCTAssertEqual(row.value as? String, "已收起")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        XCTAssertGreaterThan(row.frame.minY, app.switches["「年」改成「歲」"].frame.maxY, "583.1 under 歲")
        XCTAssertFalse(expanded.exists)
        shot("PR_583.1_collapsed")

        // 583.2: four options with examples, the current one selected.
        expand()
        XCTAssertEqual(row.value as? String, "已展開")
        for raw in Self.raws {
            let cell = option(raw)
            XCTAssertTrue(cell.exists, raw)
            XCTAssertGreaterThanOrEqual(cell.frame.height, 44, raw)
            XCTAssertLessThanOrEqual(cell.frame.maxY, app.frame.height, "\(raw) on screen")
        }
        XCTAssertEqual(option("dDay").label, "D-Day，D+12 ／ D-7")
        XCTAssertTrue(option("ordinal").isSelected)
        XCTAssertFalse(option("dDay").isSelected)
        XCTAssertFalse(note.exists, "583.4 no note with day only")
        shot("PR_583.2_expanded_dayOnly")

        // 583.3: a tap writes back, the viewfinder follows, the list stays open.
        option("dDay").tap()
        XCTAssertTrue(option("dDay").isSelected)
        XCTAssertEqual(row.label, "寫法，D-Day")
        XCTAssertTrue(expanded.exists, "583.3 stays open")
        // A fresh profile starts today, so either counting rule prints D-Day.
        XCTAssertEqual(overlayText.label, "D-Day", "583.3 \(overlayText.label)")

        // 583.4: with 週 checked the note appears and the wording no longer applies.
        app.revealInPanel(app.buttons["週"])
        app.buttons["週"].tap()
        expand()
        XCTAssertTrue(note.exists, "583.4 note")
        XCTAssertFalse(overlayText.label.contains("D"), "583.4 \(overlayText.label)")
        shot("PR_583.4_expanded_withWeek")
        // Still changeable.
        option("dayN").tap()
        XCTAssertEqual(row.label, "寫法，Day N")

        // 583.2: collapses on a second tap.
        app.revealInPanel(row)
        row.tap()
        XCTAssertEqual(row.value as? String, "已收起")
        XCTAssertFalse(expanded.exists)
    }

    /// 583.2: switching tabs and back shows the row collapsed again.
    func testRowIsCollapsedAfterSwitchingTabs() {
        launch()
        expand()
        app.buttons["樣式"].tap()
        contentTab.tap()
        app.revealInPanel(row)
        XCTAssertEqual(row.value as? String, "已收起")
        XCTAssertFalse(expanded.exists)
    }

    /// 583.7: at accessibility XXXL the options stay ≥ 44pt and do not overlap.
    func testLargestTextKeepsOptionsApart() {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        expand()
        var previous = row
        for raw in Self.raws {
            let cell = option(raw)
            app.revealInPanel(cell)
            XCTAssertGreaterThanOrEqual(cell.frame.height, 44, raw)
            // Re-read after the reveal: scrolling moves both.
            XCTAssertGreaterThanOrEqual(cell.frame.minY, previous.frame.maxY - 1, "\(raw) does not overlap the row above")
            XCTAssertLessThanOrEqual(cell.frame.maxX, app.frame.width, "\(raw) within the screen")
            previous = cell
            shot("PR_583.7_XXXL_\(raw)")
        }
    }
}
