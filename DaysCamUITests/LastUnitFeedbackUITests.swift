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
        // The hint line is always laid out (108.2); it carries the text only
        // while showing, so the checks read its label.
        XCTAssertNotEqual(unitHint.label, "至少保留一個單位", "108.1 no text beforehand")

        day.tap()
        XCTAssertTrue(day.isSelected, "108.1 still checked")
        let shown = NSPredicate(format: "label == '至少保留一個單位'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: unitHint)], timeout: 2), .completed, "108.1 the hint appeared")
        XCTAssertEqual(app.staticTexts["年改成歲"].frame, ageRowBefore, "108.2 the age-wording row did not move")
        XCTAssertEqual(app.staticTexts["顯示內容"].frame, contentHeadingBefore, "108.2 the content heading did not move")
        let gone = NSPredicate(format: "label != '至少保留一個單位'")
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
        sleep(1)
        XCTAssertNotEqual(unitHint.label, "至少保留一個單位", "108.3 no hint")
    }

    /// 108.4: turning off the only one of 天數／日期 springs back with its
    /// own hint, both ways.
    /// Samples the hint rows and the 天數 switch for a while into
    /// `hints.log` under `DAYSCAM_UI_SHOT_DIR` (diagnostics for a failed run).
    private func sample(_ name: String, seconds: Double) {
        guard let path = ProcessInfo.processInfo.environment["DAYSCAM_UI_SHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var lines: [String] = []
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            lines.append(String(format: "%@ +%.2f content='%@' unit='%@' 天數=%@", name, Date().timeIntervalSince(start),
                                contentHint.label, unitHint.label, String(describing: toggle("天數").value)))
            Thread.sleep(forTimeInterval: 0.2)
        }
        let text = lines.joined(separator: "\n") + "\n"
        let url = directory.appendingPathComponent("hints.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        try? app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }

    func testLastContentSwitchSpringsBackWithAHint() {
        toggle("天數").tap()
        sample("108.4_after-tap", seconds: 2.4)
        XCTAssertTrue(isOn(toggle("天數")), "108.4 springs back")
        let shown = NSPredicate(format: "label == '至少顯示天數或日期'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: contentHint)], timeout: 2), .completed, "108.4 the hint appeared")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != '至少顯示天數或日期'"), object: contentHint)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 4), .completed)

        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        toggle("日期").tap()
        XCTAssertTrue(isOn(toggle("日期")), "108.4 the date springs back")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: contentHint)], timeout: 2), .completed, "108.4 the same hint")
    }

    /// 108.8: with the day count off, tapping a unit changes nothing and
    /// floats 先打開天數; turning the day count on makes the tap work.
    func testUnitTapWhileTheDayCountIsOffHintsToTurnItOn() {
        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        app.buttons["週"].tap()
        XCTAssertFalse(app.buttons["週"].isSelected, "108.8 setting unchanged")
        let shown = NSPredicate(format: "label == '先打開天數'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: unitHint)], timeout: 2), .completed, "108.8 the hint appeared")
        let gone = NSPredicate(format: "label != '先打開天數'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: unitHint)], timeout: 4), .completed)
        toggle("天數").tap()
        app.buttons["週"].tap()
        XCTAssertTrue(app.buttons["週"].isSelected, "108.8 works once the day count is on")
    }
}
