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
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2023-08-05"
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-10-12"
        XCTAssertTrue(app.launchOnExportPage(profiles: profiles), "the export page is up")
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
        let s = app.switches["「年」改成「歲」"]
        return s.exists ? s : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "「年」改成「歲」")).firstMatch
    }
    private var isAgeWordingOn: Bool { (ageWording.value as? String) == "1" }
    /// Tap near the switch's trailing end, as a finger would. With the cards
    /// of #558 the switch can sit in the home-indicator band, which swallows
    /// taps by design (92.7), so drag it up into reach first.
    private func tapAgeWording() {
        let reach = app.frame.height - (app.frame.height >= 812 ? 60 : 16)
        if ageWording.frame.maxY > reach {
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width * 0.08, dy: app.frame.height - 140))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -(ageWording.frame.maxY - reach + 40))),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.5)
        }
        ageWording.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
    }
    private func overlay(containing text: String) -> XCUIElement {
        // Only the preview's overlay: the page title also says 第 N 天.
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@ AND label CONTAINS %@", ["overlayText", "overlayTextDraggable"], text)).firstMatch
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
