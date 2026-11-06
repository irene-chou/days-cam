import XCTest

/// #677: the 字型授權 entry at the bottom of the 紀錄 list (acceptance 1, 2, 4).
/// With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′
/// screenshot is also written there for the PR.
final class FontLicenseEntryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(access: String) {
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString,
                                "-UITestRecordPhotos", "5", "-UITestPhotoAccess", access]
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
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

    /// 1 and 4: the entry is there under every access state, below the footer.
    func testEntryShowsBelowTheFooterUnderEveryAccessState() {
        for access in ["authorized", "limited", "notDetermined", "denied"] {
            launch(access: access)
            XCTAssertTrue(app.navigationBars["紀錄"].waitForExistence(timeout: 10), access)
            let entry = element("fontLicenseButton")
            XCTAssertTrue(entry.waitForExistence(timeout: 5), "1 entry shown: \(access)")
            XCTAssertEqual(entry.label, "字型授權")
            let footer = element("recordListFooter")
            if footer.exists {
                XCTAssertGreaterThan(entry.frame.minY, footer.frame.maxY - 1, "1 below the footer: \(access)")
            }
            if access == "authorized" { shot("677_4_record-list-license-entry") }
            app.terminate()
        }
    }

    /// 2: the entry pushes the license page; back returns to the list.
    func testEntryOpensTheLicensePageAndBackReturns() {
        launch(access: "authorized")
        XCTAssertTrue(app.navigationBars["紀錄"].waitForExistence(timeout: 10))
        element("fontLicenseButton").tap()
        XCTAssertTrue(app.staticTexts["字型授權"].waitForExistence(timeout: 5), "2 license page title")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'SIL Open Font License'"))
            .firstMatch.waitForExistence(timeout: 5), "2 lists the license texts")
        app.buttons["返回"].tap()
        XCTAssertTrue(app.navigationBars["紀錄"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("recordRow").exists, "the list is as before")
    }
}
