import XCTest

/// #583 → #747: the 寫法 row on the record editor, between 單位 and 「年」改成「歲」
/// (it left the 文字內容 card). With `DAYSCAM_UI_SHOT_DIR` in the test runner's
/// environment the B′ screenshots are also written there for the PR.
final class DayCountFormatPanelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// `withWeek` first checks 週 on the editor, so the note shows.
    private func launch(extraArguments: [String] = [], withWeek: Bool = false) {
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnRecordEditor(extraArguments: extraArguments), "the record editor is up")
        XCTAssertTrue(app.buttons["rulesUnit_day"].waitForExistence(timeout: 5))
        if withWeek {
            let week = app.buttons["rulesUnit_week"]
            week.tap()
            XCTAssertTrue(week.isSelected)
        }
    }

    private var row: XCUIElement { app.buttons["dayCountFormatRow"] }
    private var expanded: XCUIElement { element("dayCountFormatExpanded") }
    private var note: XCUIElement { element("dayCountFormatNote") }
    private func option(_ raw: String) -> XCUIElement { app.buttons["dayCountFormat_\(raw)"] }
    private static let raws = ["ordinal", "plain", "dayN", "dDay"]

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The 天數預覽 block's spoken text (today's row included).
    private var previewLabel: String { element("rulesDayPreview").label }

    /// Drags the editor's form until `target` sits fully on screen.
    private func reveal(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let limit = app.frame.height - 60
        for _ in 0..<8 where !(target.exists && target.frame.minY > 60 && target.frame.maxY < limit) {
            let up = !target.exists || target.frame.maxY >= limit
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width * 0.08, dy: app.frame.height * (up ? 0.7 : 0.35)))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -120 : 120)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(target.exists && target.frame.maxY < limit, "\(target) on screen: \(target.frame)", file: file, line: line)
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
    private func expand(revealingLast: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        reveal(row, file: file, line: line)
        if row.value as? String != "已展開" { row.tap() }
        XCTAssertTrue(expanded.waitForExistence(timeout: 3), "expanded", file: file, line: line)
        if revealingLast {
            reveal(note.exists ? note : option("dDay"), file: file, line: line)
        }
        // A tap right after a drag only stops the scroll's momentum.
        Thread.sleep(forTimeInterval: 1)
    }

    /// Brings `cell`'s top edge on screen: at the largest text size an
    /// option on iPhone SE can be taller than what is left of the screen, so
    /// `reveal` (whole element on screen) cannot succeed.
    private func revealTop(_ cell: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let limit = app.frame.height - 120
        for _ in 0..<10 where !(cell.exists && cell.frame.minY > 60 && cell.frame.minY < limit) {
            let up = !cell.exists || cell.frame.minY >= limit
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width * 0.08, dy: app.frame.height * (up ? 0.7 : 0.35)))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -60 : 60)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(cell.exists && cell.frame.minY > 60, "\(cell) top on screen: \(cell.frame)", file: file, line: line)
    }

    /// 583.1–583.3: the row, its options and writing back.
    func testRowExpandsAndSelects() {
        launch()
        reveal(row)
        // 747.1: between 單位 and 「年」改成「歲」, ≥ 44pt, collapsed.
        XCTAssertEqual(row.label, "寫法，第 N 天")
        XCTAssertEqual(row.value as? String, "已收起")
        XCTAssertGreaterThanOrEqual(row.frame.height, 43.5)
        XCTAssertGreaterThan(row.frame.minY, element("rulesUnitRow").frame.maxY - 1, "747.1 under 單位")
        XCTAssertLessThan(row.frame.maxY, element("rulesAgeWordingToggle").frame.minY + 1, "747.1 above 歲")
        XCTAssertFalse(expanded.exists)
        shot("PR_747.6_collapsed")

        // 583.2: four options with examples, the current one selected.
        expand()
        XCTAssertEqual(row.value as? String, "已展開")
        for raw in Self.raws {
            let cell = option(raw)
            XCTAssertTrue(cell.exists, raw)
            XCTAssertGreaterThanOrEqual(cell.frame.height, 43.5, raw)
            XCTAssertLessThanOrEqual(cell.frame.maxY, app.frame.height, "\(raw) on screen")
        }
        XCTAssertEqual(option("dDay").label, "D-Day，D+12 ／ D-7")
        XCTAssertTrue(option("ordinal").isSelected)
        XCTAssertFalse(option("dDay").isSelected)
        XCTAssertFalse(note.exists, "583.4 no note with day only")
        shot("PR_747.6_expanded_dayOnly")

        // 747.2: a tap writes back, the 天數預覽 follows, the list stays open.
        option("dDay").tap()
        XCTAssertTrue(option("dDay").isSelected, "583.3")
        XCTAssertEqual(row.label, "寫法，D-Day")
        XCTAssertTrue(expanded.exists, "583.3 stays open")
        // A fresh profile starts today, so either counting rule prints D-Day.
        reveal(element("rulesDayPreview"))
        XCTAssertTrue(previewLabel.contains("D-Day"), "747.2 \(previewLabel)")

        // 583.2: collapses on a second tap.
        reveal(row)
        row.tap()
        XCTAssertEqual(row.value as? String, "已收起")
        XCTAssertFalse(expanded.exists)
    }

    /// 583.4: with 週 checked (on the record editor, #721) the note appears
    /// and the wording no longer applies; the wording is still changeable.
    func testNoteAppearsWithOtherUnitsAndWordingStaysChangeable() {
        launch(withWeek: true)
        expand()
        XCTAssertTrue(note.exists, "583.4 note")
        XCTAssertTrue(app.buttons["rulesUnit_week"].isSelected)
        shot("PR_747.6_expanded_withWeek")
        option("dayN").tap()
        XCTAssertEqual(row.label, "寫法，Day N")
    }

    /// 747.4: the 文字內容 card on the export page no longer has the row.
    func testContentCardHasNoFormatRow() {
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        content.tap()
        XCTAssertTrue(app.switches["天數"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["positionRow"].exists, "the card is there")
        XCTAssertFalse(row.exists, "747.4 no 寫法 row")
        XCTAssertFalse(element("dayCountFormatNote").exists)
        shot("PR_747.4_content_card")
    }

    /// 747.5: at accessibility XXXL the options stay ≥ 44pt and do not overlap.
    func testLargestTextKeepsOptionsApart() {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        expand(revealingLast: false)
        var previous = row
        for raw in Self.raws {
            let cell = option(raw)
            revealTop(cell)
            XCTAssertGreaterThanOrEqual(cell.frame.height, 43.5, raw)
            // Re-read after the reveal: scrolling moves both.
            XCTAssertGreaterThanOrEqual(cell.frame.minY, previous.frame.maxY - 1, "\(raw) does not overlap the row above")
            XCTAssertLessThanOrEqual(cell.frame.maxX, app.frame.width, "\(raw) within the screen")
            XCTAssertGreaterThanOrEqual(cell.frame.minX, 0, "\(raw) within the screen")
            previous = cell
            shot("PR_747.5_XXXL_\(raw)")
        }
    }
}
