import XCTest

/// #751: at the largest text size (accessibility XXXL) no row of the record
/// editor is wider than the window, and the 單位 checkboxes fall back to 2×2 when one line is too tight.
/// With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′
/// screenshots are also written there for the PR.
final class EditorLargestTextUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(largest: Bool) {
        let extra = largest ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : []
        XCTAssertTrue(app.launchOnRecordEditor(extraArguments: extra), "the record editor is up")
        XCTAssertTrue(app.buttons["rulesUnit_day"].waitForExistence(timeout: 5))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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

    private func dragUp() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -app.frame.height * 0.55)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// 751.1: every row's content sits inside the window, side to side.
    func testEveryRowFitsTheWindowAtTheLargestTextSize() {
        launch(largest: true)
        shot("PR_751_largest_top")
        let width = app.frame.width
        let ids = ["startDatePicker", "rulesDateShortText", "rulesUnitRow", "rulesUnit_year", "rulesUnit_month",
                   "rulesUnit_week", "rulesUnit_day", "dayCountFormatRow", "rulesAgeWordingToggle", "rulesDayPreview"]
        for id in ids {
            let frame = element(id).frame
            XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(id) \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, width + 0.5, "\(id) \(frame)")
        }
        for label in ["名稱", "日期", "起算", "單位"] {
            let frame = app.staticTexts[label].frame
            XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(label) \(frame)")
        }
        for label in ["當天算第 1 天", "第 0 天"] {
            let frame = app.buttons[label].frame
            XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(label) \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, width + 0.5, "\(label) \(frame)")
        }
        let name = app.textFields["名稱"].frame
        XCTAssertTrue(name.minX >= 0 && name.maxX <= width + 0.5, "名稱 field \(name)")
        dragUp()
        shot("PR_751_largest_bottom")
    }

    /// 751.2: the four checkboxes sit apart, each at least 44pt high, 2×2 when one line is too tight.
    func testUnitCheckboxesAreTwoByTwoAndTappableAtTheLargestTextSize() {
        launch(largest: true)
        let units = ["year", "month", "week", "day"].map { app.buttons["rulesUnit_\($0)"] }
        for unit in units { XCTAssertGreaterThanOrEqual(unit.frame.height, 43.5, "\(unit.frame)") }
        // One line while the four fit side by side, else 2×2 (年月／週天).
        if abs(units[0].frame.minY - units[2].frame.minY) > 1 {
            XCTAssertEqual(units[0].frame.minY, units[1].frame.minY, accuracy: 1, "年、月 on one line")
            XCTAssertEqual(units[2].frame.minY, units[3].frame.minY, accuracy: 1, "週、天 on one line")
            XCTAssertGreaterThan(units[2].frame.minY, units[0].frame.maxY - 1, "second line below the first")
        }
        for unit in units { XCTAssertTrue(unit.frame.minX >= 0 && unit.frame.maxX <= app.frame.width + 0.5, "\(unit.frame)") }
        for first in 0..<4 {
            for second in (first + 1)..<4 {
                XCTAssertFalse(units[first].frame.intersects(units[second].frame.insetBy(dx: 1, dy: 1)),
                               "\(first) and \(second) overlap")
            }
        }
        dragUp()
        let week = app.buttons["rulesUnit_week"]
        if week.isHittable { week.tap(); XCTAssertTrue(week.isSelected, "tappable") }
    }

    /// 751.3: at the default size the four checkboxes stay on one line.
    func testUnitCheckboxesStayOnOneLineAtTheDefaultTextSize() {
        launch(largest: false)
        let units = ["year", "month", "week", "day"].map { app.buttons["rulesUnit_\($0)"] }
        for unit in units { XCTAssertEqual(unit.frame.minY, units[0].frame.minY, accuracy: 1) }
        shot("PR_751_default")
    }
}
