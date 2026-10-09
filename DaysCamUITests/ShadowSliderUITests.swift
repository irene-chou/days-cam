import XCTest

/// The shadow sub-tab's presets and parameter rows end to end (TASK-71,
/// 71.3 and 71.4). The app starts from a fresh profile via
/// `-UITestFreshProfiles <name>`.
final class ShadowSliderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        app.buttons["樣式"].tap()
        app.buttons["陰影"].tap()
    }

    private var offsetX: XCUIElement { app.sliders["X 偏移"] }
    private var offsetY: XCUIElement { app.sliders["Y 偏移"] }
    private var blur: XCUIElement { app.sliders["模糊"] }

    /// The panel is short, so a lower row may sit under its bottom edge:
    /// drag the page up slowly (no fling, from the left margin so a slider does not take the drag) until `element` can be touched.
    private func scrollToReveal(_ element: XCUIElement) {
        var tries = 0
        while !element.isHittable && tries < 6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.90))
                .press(forDuration: 0.1,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.76)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
            tries += 1
        }
        if !element.isHittable { attach("not-hittable") }
        XCTAssertTrue(element.isHittable, "scrolled into view")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 71.3: the four presets, and the parameter rows that follow them.
    func testPresetsFillTheParameterRows() {
        for name in ["無陰影", "柔和", "硬陰影", "發光"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3), name)
        }
        XCTAssertTrue(app.buttons["柔和"].isSelected, "預設 soft")
        XCTAssertEqual(offsetX.value as? String, "0 點")
        XCTAssertEqual(offsetY.value as? String, "2 點")
        XCTAssertEqual(blur.value as? String, "4 點")
        attach("shadow-soft")

        app.buttons["硬陰影"].tap()
        XCTAssertTrue(app.buttons["硬陰影"].isSelected)
        XCTAssertEqual(offsetX.value as? String, "2 點")
        XCTAssertEqual(offsetY.value as? String, "2 點")
        XCTAssertEqual(blur.value as? String, "0 點")
        attach("shadow-hard")

        app.buttons["發光"].tap()
        XCTAssertEqual(offsetY.value as? String, "0 點")
        XCTAssertEqual(blur.value as? String, "8 點")
        attach("shadow-glow")
    }

    /// 71.3: moving a slider clears the preset's selection.
    func testAdjustingAParameterClearsThePreset() {
        app.buttons["硬陰影"].tap()
        XCTAssertTrue(app.buttons["硬陰影"].isSelected)
        scrollToReveal(blur)
        blur.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(blur.value as? String, "16 點")
        XCTAssertFalse(app.buttons["硬陰影"].isSelected)
        for name in ["無陰影", "柔和", "發光"] { XCTAssertFalse(app.buttons[name].isSelected, name) }
        app.buttons["硬陰影"].tap()
        XCTAssertTrue(app.buttons["硬陰影"].isSelected)
        XCTAssertEqual(blur.value as? String, "0 點")
    }

    /// 71.4: glow follows the text color, which the palette shows as selected.
    func testGlowFollowsTheTextColor() {
        app.buttons["發光"].tap()
        XCTAssertTrue(app.buttons["跟隨文字顏色"].isSelected)
        app.buttons["柔和"].tap()
        XCTAssertFalse(app.buttons["跟隨文字顏色"].isSelected)
    }

    /// 無 disables the parameter rows, which stay visible.
    func testNoneDisablesTheParameterRows() {
        app.buttons["無陰影"].tap()
        XCTAssertTrue(app.buttons["無陰影"].isSelected)
        XCTAssertFalse(blur.isEnabled)
        XCTAssertFalse(offsetX.isEnabled)
        XCTAssertFalse(app.sliders["陰影透明度"].isEnabled)
        attach("shadow-none-disabled")
        app.buttons["柔和"].tap()
        XCTAssertTrue(blur.isEnabled)
    }
}
