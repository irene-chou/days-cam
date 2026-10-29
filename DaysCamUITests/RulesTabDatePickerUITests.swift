import XCTest

/// The start-date picker on the profile edit page end to end (TASK-94
/// #393: a future date can be picked and the overlay reads 還有 N 天). The
/// screenshots double as TASK-95's (#394) B′ evidence that the picker and
/// its calendar are in Chinese. Screenshots are attached, and also written
/// as PNGs to `DAYSCAM_UI_SHOT_DIR` when the runner's environment sets it.
final class RulesTabDatePickerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        openEditor()
    }

    private var picker: XCUIElement { app.descendants(matching: .any)["startDatePicker"] }

    private func openEditor() {
        let profiles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '設定檔：'")).firstMatch
        XCTAssertTrue(profiles.waitForExistence(timeout: 10))
        profiles.tap()
        let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '編輯'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the start-date picker is on the edit page")
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

    /// 94.1／94.4／94.8 and 95.2／95.7: open the calendar, go to next month,
    /// pick a day, and the preview reads 還有 N 天.
    func testFutureDateCanBePickedAndPreviewsCountdown() {
        attach("94.8_95.7_picker-collapsed")
        picker.tap()
        let nextMonth = app.buttons["下個月"].exists ? app.buttons["下個月"] : app.buttons["Next Month"]
        XCTAssertTrue(nextMonth.waitForExistence(timeout: 5), "the calendar opened")
        attach("95.7_picker-expanded")
        nextMonth.tap()
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS '15日' OR label CONTAINS ' 15'")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 3), "a day in next month is tappable (94.1)")
        day.tap()
        // Dismiss the popover by tapping the page title area, outside it.
        app.navigationBars.element(boundBy: max(app.navigationBars.count - 1, 0)).tap()
        let countdown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '還有'")).firstMatch
        XCTAssertTrue(countdown.waitForExistence(timeout: 5), "94.4 the preview reads 還有 N 天")
        attach("94.8_future-date-selected")
    }
}
