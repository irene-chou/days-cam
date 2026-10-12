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
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
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

    private var overlayText: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '第 '")).firstMatch
    }

    /// 119.1／119.2／119.3.
    func testFreshInstallShowsTheDefaultNameAndCanTurnItOff() {
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '設定檔：'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertTrue(chip.label.contains("我的紀錄"), "119.1 top bar: \(chip.label)")
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))
        XCTAssertEqual(overlayText.label, "我的紀錄 第 1 天", "119.1 viewfinder")
        shot("PR_119.1_iPhone16_viewfinder")

        chip.tap()
        let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '編輯'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "我的紀錄", "119.2 name")
        let toggle = app.switches["寫在照片上"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1", "119.2 on")
        let preview = app.staticTexts["rulesPreviewSentence"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        XCTAssertTrue(preview.label.contains("我的紀錄 第 1 天"), "119.2 preview: \(preview.label)")
        shot("PR_119.2_iPhone16_edit")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        let bar = app.navigationBars["設定檔"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 600)))
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 5))
        XCTAssertTrue(overlayText.waitForExistence(timeout: 3))
        XCTAssertTrue(overlayText.label.hasPrefix("第 "), "119.3 back to day count only: \(overlayText.label)")
        shot("PR_119.3_iPhone16_nameoff")
    }
}
