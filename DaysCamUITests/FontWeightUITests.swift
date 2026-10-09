import XCTest

/// The 字型 page's weight buttons end to end (TASK-89, 89.3 and 89.7). The app
/// starts from a fresh profile via `-UITestFreshProfiles <name>`; PingFang is
/// the profile's font, and its three weights ship with iOS, so nothing needs
/// a download.
final class FontWeightUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        openFontPage()
    }

    private func openFontPage() {
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        app.buttons["樣式"].tap()
        app.buttons["字型"].tap()
    }

    private func weight(_ id: String) -> XCUIElement { app.buttons["fontWeight.\(id)"] }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 89.7: only the selected font's row is a card, with its weights.
    func testSelectedFontShowsItsWeightButtons() {
        XCTAssertTrue(weight("light").waitForExistence(timeout: 5))
        XCTAssertTrue(weight("regular").exists)
        XCTAssertTrue(weight("semibold").exists)
        XCTAssertTrue(weight("semibold").isSelected, "the default weight is selected")
        XCTAssertGreaterThanOrEqual(weight("light").frame.height, 44, "89.7 buttons are at least 44pt tall")
        XCTAssertFalse(weight("w3").exists, "another font does not expand")
        attach("font-weights-pingfang")
    }

    /// 89.3: the chosen weight is kept after leaving the page and after relaunch.
    func testChosenWeightIsKept() {
        XCTAssertTrue(weight("light").waitForExistence(timeout: 5))
        weight("light").tap()
        XCTAssertTrue(weight("light").isSelected)
        XCTAssertFalse(weight("semibold").isSelected)
        app.buttons["外框"].tap()
        app.buttons["字型"].tap()
        XCTAssertTrue(weight("light").waitForExistence(timeout: 3))
        XCTAssertTrue(weight("light").isSelected, "kept after leaving the page")
        attach("font-weights-light-selected")
        app.terminate()
        app.launch()
        openFontPage()
        XCTAssertTrue(weight("light").waitForExistence(timeout: 5))
        XCTAssertTrue(weight("light").isSelected, "89.3 kept after relaunch")
    }
}
