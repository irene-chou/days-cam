import XCTest

/// TASK-109 (#423): the edit page's 寫在照片上 switch is the content tab's
/// 名稱; the preview sentence shows the actual overlay.
final class NameOnPhotoToggleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
    }

    private var profileChip: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '設定檔：'")).firstMatch
    }
    private var nameOnPhoto: XCUIElement {
        let s = app.switches["寫在照片上"]
        return s.exists ? s : app.descendants(matching: .any).matching(identifier: "nameOnPhotoToggle").firstMatch
    }
    private var preview: XCUIElement { app.staticTexts["rulesPreviewSentence"] }
    private var overlayText: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '第 ' OR label CONTAINS ' 第 '")).firstMatch
    }
    private func isOn(_ element: XCUIElement) -> Bool { (element.value as? String) == "1" }

    private func openEditPage() {
        XCTAssertTrue(profileChip.waitForExistence(timeout: 10))
        profileChip.tap()
        let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '編輯'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5), "the edit page opened")
    }

    /// 109.1／109.2: the switch sits under the name, off by default; naming
    /// the profile 寶寶 and turning it on makes the preview 寶寶 第 1 天 and
    /// the viewfinder show the name.
    func testSwitchPutsTheNameOnThePreviewAndThePhoto() {
        openEditPage()
        XCTAssertTrue(nameOnPhoto.waitForExistence(timeout: 5), "109.1 the switch is there")
        XCTAssertFalse(isOn(nameOnPhoto), "109.1 follows showName (off on a fresh profile)")
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.frame.maxY <= nameOnPhoto.frame.minY + 1, "109.1 right under the name row")
        nameField.tap()
        nameField.typeText("寶寶")
        nameOnPhoto.tap()
        XCTAssertTrue(isOn(nameOnPhoto))
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        XCTAssertTrue(preview.label.contains("寶寶") && preview.label.contains("第 1 天"), "109.2 preview: \(preview.label)")
        // Back to the camera: the overlay carries the name.
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        let bar = app.navigationBars["設定檔"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 600)))
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 5))
        XCTAssertTrue(overlayText.waitForExistence(timeout: 3))
        XCTAssertTrue(overlayText.label.contains("寶寶"), "109.2 the viewfinder shows the name: \(overlayText.label)")
    }

    /// 109.3: the content tab's 名稱 switch is the same setting, both ways.
    func testContentTabNameSwitchStaysInSync() {
        openEditPage()
        XCTAssertTrue(nameOnPhoto.waitForExistence(timeout: 5))
        nameOnPhoto.tap()
        XCTAssertTrue(isOn(nameOnPhoto))
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        let bar = app.navigationBars["設定檔"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 600)))
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 5))

        app.buttons["疊字設定"].tap()
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        let nameSwitch = app.switches["名稱"].exists ? app.switches["名稱"] : app.descendants(matching: .any).matching(NSPredicate(format: "label == '名稱'")).firstMatch
        XCTAssertTrue(nameSwitch.waitForExistence(timeout: 5))
        XCTAssertTrue(isOn(nameSwitch), "109.3 the content tab shows it on")
        nameSwitch.tap()
        XCTAssertFalse(isOn(nameSwitch))
        // Close the panel and reopen the edit page: the switch is off again.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 5))
        openEditPage()
        XCTAssertTrue(nameOnPhoto.waitForExistence(timeout: 5))
        XCTAssertFalse(isOn(nameOnPhoto), "109.3 off after the content tab turned it off")
    }
}
