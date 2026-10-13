import XCTest

/// TASK-155 (#537): the profile edit page — no 寫在照片上 switch, labels above
/// values, a 天數預覽 block, the 起算 segmented control. Screenshots are
/// attached and also written to `DAYSCAM_UI_SHOT_DIR` when the runner's
/// environment sets it.
final class RulesEditorLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        openEditor()
    }

    private var picker: XCUIElement { app.descendants(matching: .any)["startDatePicker"] }
    private var preview: XCUIElement { app.descendants(matching: .any)["rulesDayPreview"] }
    private var shortText: XCUIElement { app.staticTexts["rulesDateShortText"] }

    private func openEditor() {
        let profiles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '設定檔：'")).firstMatch
        XCTAssertTrue(profiles.waitForExistence(timeout: 10))
        profiles.tap()
        let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '編輯'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
    }

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

    /// 155.1／155.3: the switch and the two old text blocks are gone.
    func testOldSwitchAndExplanationTextAreGone() {
        XCTAssertFalse(app.switches["寫在照片上"].exists, "155.1")
        XCTAssertFalse(app.staticTexts["寫在照片上"].exists, "155.1")
        XCTAssertFalse(app.staticTexts["過去的日子算第幾天，未來的日子倒數還有幾天"].exists, "155.3")
        XCTAssertFalse(app.staticTexts["到了那天之後"].exists, "155.3")
        XCTAssertFalse(app.staticTexts["今天會顯示為"].exists, "155.3")
    }

    /// 155.2／155.7／155.10: labels sit above values; the short text has the
    /// day count only; a start date of today gives a single 今天 row; the
    /// preview is one element that opens with 「天數預覽」.
    func testLabelsAboveValuesAndPastDatePreview() {
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let nameLabel = app.staticTexts["名稱"]
        let dateLabel = app.staticTexts["日期"]
        let ruleLabel = app.staticTexts["起算"]
        XCTAssertTrue(nameLabel.exists && dateLabel.exists && ruleLabel.exists)
        XCTAssertLessThanOrEqual(nameLabel.frame.maxY, nameField.frame.minY + 1, "155.2 名稱")
        XCTAssertLessThanOrEqual(dateLabel.frame.maxY, picker.frame.minY + 1, "155.2 日期")
        XCTAssertLessThanOrEqual(ruleLabel.frame.maxY, app.buttons["第 0 天"].frame.minY + 1, "155.2 起算")
        XCTAssertGreaterThan(shortText.frame.minX, picker.frame.maxX - 1, "155.2 short text right of the picker")
        XCTAssertEqual(shortText.label, "第 1 天", "155.2 days only, no name")

        XCTAssertTrue(preview.exists)
        XCTAssertTrue(preview.label.hasPrefix("天數預覽，今天"), "155.10 \(preview.label)")
        XCTAssertTrue(preview.label.contains("我的紀錄 第 1 天"), "155.7 \(preview.label)")
        XCTAssertFalse(preview.label.contains("當天"), "155.7 a past date has only the 今天 row")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "rulesDayPreview").count, 1, "155.10")
        attach("155.12_edit-past-date")
    }

    /// 155.2／155.7: a future date shows 還有 N 天 beside the picker and four
    /// preview rows; switching 起算 updates both (155.9, view side).
    func testFutureDateShortTextAndFourRows() {
        picker.tap()
        let nextMonth = app.buttons["下個月"].exists ? app.buttons["下個月"] : app.buttons["Next Month"]
        XCTAssertTrue(nextMonth.waitForExistence(timeout: 5))
        nextMonth.tap()
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS '15日' OR label CONTAINS ' 15'")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 3))
        day.tap()
        let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
        if dismiss.waitForExistence(timeout: 3) { dismiss.tap() }
        // The calendar must be gone before the page underneath is touched.
        if nextMonth.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        }
        XCTAssertTrue(nextMonth.waitForNonExistence(timeout: 5), "calendar closed")

        XCTAssertTrue(shortText.waitForExistence(timeout: 3))
        XCTAssertTrue(shortText.label.hasPrefix("還有 "), "155.2 \(shortText.label)")
        XCTAssertFalse(shortText.label.contains("我的紀錄"), "155.2")
        XCTAssertTrue(preview.label.hasPrefix("天數預覽，今天 我的紀錄 還有 "), "155.7 \(preview.label)")
        XCTAssertTrue(preview.label.contains("當天"), "155.7 \(preview.label)")
        XCTAssertEqual(preview.label.components(separatedBy: "，").count, 5, "155.7 title + 今天 + three rows: \(preview.label)")
        attach("155.12_edit-future-date")

        app.buttons["第 0 天"].tap()
        let updated = NSPredicate(format: "label CONTAINS '我的紀錄 第 0 天'")
        let deadline = Date().addingTimeInterval(5)
        while !updated.evaluate(with: preview), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
        XCTAssertTrue(preview.label.contains("我的紀錄 第 0 天"), "155.9 \(preview.label)")
    }

    /// 155.5: both 起算 cells show in full on one line (run on iPhone SE).
    func testCountingRuleCellsAreNotClipped() {
        let windowWidth = app.windows.firstMatch.frame.width
        for label in ["當天算第 1 天", "第 0 天"] {
            let cell = app.buttons[label]
            XCTAssertTrue(cell.waitForExistence(timeout: 3), label)
            XCTAssertTrue(cell.isHittable, "155.5 \(label)")
            XCTAssertGreaterThanOrEqual(cell.frame.minX, 0, "155.5 \(label)")
            XCTAssertLessThanOrEqual(cell.frame.maxX, windowWidth, "155.5 \(label)")
            XCTAssertLessThan(cell.frame.height, 50, "155.5 one line: \(label)")
        }
        attach("155.5_edit-counting-rule-\(Int(windowWidth))pt")
    }
}
