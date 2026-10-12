import XCTest

/// TASK-139 (#486): 年改成歲 is always usable and renames the year checkbox
/// to 歲; the checkbox and the switch never change each other. With
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
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2023-08-05"
        seeding.launch()
        XCTAssertTrue(seeding.buttons["疊字設定"].waitForExistence(timeout: 10))
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", profiles]
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-10-12"
        app.launch()
        app.buttons["疊字設定"].tap()
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        XCTAssertTrue(app.buttons["天"].waitForExistence(timeout: 5))
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
        let s = app.switches["年改成歲"]
        return s.exists ? s : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "年改成歲")).firstMatch
    }
    private var isAgeWordingOn: Bool { (ageWording.value as? String) == "1" }
    /// The combined row is wide; tap near its switch end, as a finger would.
    private func tapAgeWording() {
        ageWording.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
    }
    private func overlay(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// 139.1–139.4 in one pass, with a screenshot at each step.
    func testAgeWordingRenamesTheYearCheckboxAndStaysIndependent() {
        XCTAssertTrue(app.buttons["年"].exists, "the year reads 年 to start with")
        XCTAssertTrue(ageWording.isEnabled, "139.1 usable without the year")
        XCTAssertFalse(isAgeWordingOn)
        shot("PR_139.0_iPhone16Pro_initial")

        tapAgeWording()
        XCTAssertTrue(isAgeWordingOn, "139.1 turns on")
        XCTAssertTrue(app.buttons["歲"].waitForExistence(timeout: 3), "139.1 the checkbox reads 歲")
        XCTAssertFalse(app.buttons["年"].exists)
        XCTAssertFalse(app.buttons["歲"].isSelected, "139.1 still unchecked")
        XCTAssertTrue(overlay(containing: "第 1165 天").waitForExistence(timeout: 3), "139.1 overlay unchanged")
        shot("PR_139.1_iPhone16Pro_switch_on_year_unchecked")

        app.buttons["歲"].tap()
        XCTAssertTrue(overlay(containing: "3 歲 68 天").waitForExistence(timeout: 3), "139.2")
        shot("PR_139.2_iPhone16Pro_year_checked_sui")

        app.buttons["歲"].tap()
        XCTAssertFalse(app.buttons["歲"].isSelected)
        XCTAssertTrue(isAgeWordingOn, "139.3 unchecking keeps the switch on")
        app.buttons["歲"].tap()
        XCTAssertTrue(isAgeWordingOn, "139.3 re-checking keeps the switch on")
        XCTAssertTrue(overlay(containing: "3 歲 68 天").waitForExistence(timeout: 3), "139.3")

        tapAgeWording()
        XCTAssertFalse(isAgeWordingOn)
        XCTAssertTrue(app.buttons["年"].waitForExistence(timeout: 3), "139.4 reads 年 again")
        XCTAssertTrue(overlay(containing: "3 年 68 天").waitForExistence(timeout: 3), "139.4")
        shot("PR_139.4_iPhone16Pro_switch_off")
    }
}
