import XCTest

/// TASK-119: a fresh install starts with the profile 我的紀錄 and the name on
/// the photo. With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the
/// B′ screenshots are also written there for the PR.
final class DefaultProfileNameUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
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

    /// The overlay on the export preview (the title above it also says 第 N 天).
    private var overlayText: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", ["overlayText", "overlayTextDraggable"])).firstMatch
    }

    /// 119.1／119.3: a fresh record's preview leads with the default name, and
    /// the 內容 tab's 名稱 switch (on by default) turns it off. The camera's
    /// top bar chip and the profile edit page (119.2) left in #621.
    func testFreshInstallShowsTheDefaultNameAndCanTurnItOff() {
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))
        XCTAssertTrue(overlayText.label.hasPrefix("我的紀錄 第 "), "119.1 preview: \(overlayText.label)")
        shot("PR_119.1_iPhone16_preview")

        // 155.1／119.2: the 內容 tab's 名稱 switch is on by default and turns off.
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        let nameSwitch = app.switches["名稱"]
        XCTAssertTrue(nameSwitch.waitForExistence(timeout: 5))
        XCTAssertEqual(nameSwitch.value as? String, "1", "119.2 on")
        nameSwitch.tap()
        XCTAssertEqual(nameSwitch.value as? String, "0")
        XCTAssertTrue(overlayText.waitForExistence(timeout: 3))
        XCTAssertTrue(overlayText.label.hasPrefix("第 "), "119.3 back to day count only: \(overlayText.label)")
        shot("PR_119.3_iPhone16_nameoff")
    }
}
