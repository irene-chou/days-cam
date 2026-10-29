import XCTest

/// TASK-137 (#483) as reshaped by TASK-155 (#537): a future date adds the
/// day-before／day-of／day-after rows to the 天數預覽 block. Screenshots are attached and
/// also written to `DAYSCAM_UI_SHOT_DIR` when the runner's environment sets it.
final class DateTimelineUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        app.openCamera()
        openEditor()
    }

    private var picker: XCUIElement { app.descendants(matching: .any)["startDatePicker"] }
    private var timeline: XCUIElement { app.descendants(matching: .any)["rulesDayPreview"] }

    private func openEditor() {
        let profiles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '設定檔：'")).firstMatch
        XCTAssertTrue(profiles.waitForExistence(timeout: 10))
        profiles.tap()
        let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '編輯'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
    }

    /// Drags the edit page's content up from the middle of the form.
    private func scrollForm() {
        let start = picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -300)))
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

    func testTimelineRowsOnlyForFutureDate() {
        XCTAssertTrue(timeline.exists, "155.7 the preview is always there")
        XCTAssertFalse(timeline.label.contains("當天"), "137.4 today has no timeline rows")
        attach("137.1_137.4_date-today-explanation-only")

        picker.tap()
        let nextMonth = app.buttons["下個月"].exists ? app.buttons["下個月"] : app.buttons["Next Month"]
        XCTAssertTrue(nextMonth.waitForExistence(timeout: 5))
        nextMonth.tap()
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS '15日' OR label CONTAINS ' 15'")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 3))
        day.tap()
        // The calendar stays open after a pick; UIKit's invisible region behind a
        // popover closes it (and leaves the sheet underneath alone).
        let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
        if dismiss.waitForExistence(timeout: 3) { dismiss.tap() }

        XCTAssertTrue(timeline.waitForExistence(timeout: 5), "137.2 a future date shows the timeline")
        XCTAssertTrue(timeline.label.hasPrefix("天數預覽，今天"), timeline.label)
        XCTAssertTrue(timeline.label.contains("當天"), timeline.label)
        // Scroll the edit page up from the middle of the form (137.8).
        scrollForm()
        attach("137.2_137.8_date-future-timeline")

        app.buttons["第 0 天"].tap()
        XCTAssertTrue(timeline.label.contains("第 0 天"), "137.3 \(timeline.label)")
        attach("137.3_date-future-day-zero")
        scrollForm()
        attach("137.8_date-future-scrolled-to-delete")
    }
}
