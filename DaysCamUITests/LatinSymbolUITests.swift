import XCTest

/// Screenshots for TASK-100's B′ comparison (100.6, #409): the closed
/// footer (疊字設定鈕) and the style tab's sub-tab row (字級 icon). Attached to
/// the result; with `DAYSCAM_UI_SHOT_DIR` in the test runner's environment
/// they are also written there as PNGs. The same test runs against the
/// pre-#398 build, the current main and the fix, so the three can be set
/// side by side. Also checks the VoiceOver labels are unchanged (100.5).
final class LatinSymbolUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
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

    func testFooterAndStyleSubTabIcons() {
        let panelButton = app.buttons["疊字設定"]
        XCTAssertTrue(panelButton.waitForExistence(timeout: 10), "100.5 the label is still 疊字設定")
        attach("100.1_footer-closed")
        panelButton.tap()
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
        XCTAssertTrue(app.buttons["字級"].waitForExistence(timeout: 5), "100.5 the sub-tab label is still 字級")
        XCTAssertTrue(app.buttons["字型"].exists)
        XCTAssertTrue(app.buttons["外框"].exists)
        attach("100.2_style-subtabs")
    }
}
