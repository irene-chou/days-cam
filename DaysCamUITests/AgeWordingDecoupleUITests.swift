import XCTest

/// TASK-139 (#486), moved to the record editor by #721: 年改成歲 is always
/// usable and renames the year checkbox to 歲; the checkbox and the switch
/// never change each other. The 天數預覽's short text shows the result. With
/// `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′ screenshots
/// are also written there for the PR.
final class AgeWordingDecoupleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // Seed the default profile on 2023-08-05 (奶茶's birthday), then
        // relaunch on 2026-10-12 into the same profile directory.
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2023-08-05"
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-10-12"
        XCTAssertTrue(app.launchOnRecordEditor(profiles: profiles), "the record editor is up")
        XCTAssertTrue(app.buttons["rulesUnit_day"].waitForExistence(timeout: 5))
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

    private var ageWording: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "rulesAgeWordingToggle").firstMatch
    }
    private var yearCell: XCUIElement { app.buttons["rulesUnit_year"] }
    /// The day count beside the start-date picker, e.g. 「3 歲 68 天」.
    private var shortText: XCUIElement { app.staticTexts["rulesDateShortText"] }
    private var isAgeWordingOn: Bool { (ageWording.value as? String) == "1" }
    /// Tap near the switch's trailing end, as a finger would.
    private func tapAgeWording() {
        ageWording.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
    }

    /// 139.1–139.4 in one pass, with a screenshot at each step.
    func testAgeWordingRenamesTheYearCheckboxAndStaysIndependent() {
        XCTAssertTrue(yearCell.label.contains("年"), "the year reads 年 to start with")
        XCTAssertTrue(ageWording.isEnabled, "139.1 usable without the year")
        XCTAssertFalse(isAgeWordingOn)
        shot("PR_139.0_iPhone16Pro_initial")

        tapAgeWording()
        XCTAssertTrue(isAgeWordingOn, "139.1 turns on")
        XCTAssertTrue(yearCell.label.contains("歲"), "139.1 the checkbox reads 歲")
        XCTAssertFalse(yearCell.isSelected, "139.1 still unchecked")
        XCTAssertEqual(shortText.label, "第 1165 天", "139.1 overlay unchanged")
        shot("PR_139.1_iPhone16Pro_switch_on_year_unchecked")

        yearCell.tap()
        XCTAssertTrue(yearCell.isSelected)
        XCTAssertEqual(shortText.label, "3 歲 68 天", "139.2")
        shot("PR_139.2_iPhone16Pro_year_checked_sui")

        yearCell.tap()
        XCTAssertFalse(yearCell.isSelected)
        XCTAssertTrue(isAgeWordingOn, "139.3 unchecking keeps the switch on")
        yearCell.tap()
        XCTAssertTrue(isAgeWordingOn, "139.3 re-checking keeps the switch on")
        XCTAssertEqual(shortText.label, "3 歲 68 天", "139.3")

        tapAgeWording()
        XCTAssertFalse(isAgeWordingOn)
        XCTAssertTrue(yearCell.label.contains("年"), "139.4 reads 年 again")
        XCTAssertEqual(shortText.label, "3 年 68 天", "139.4")
        shot("PR_139.4_iPhone16Pro_switch_off")
    }
}
