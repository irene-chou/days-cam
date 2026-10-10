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
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        app.buttons["樣式"].tap()
        app.buttons["陰影"].tap()
    }

    private var offsetX: XCUIElement { app.sliders["X 偏移"] }
    private var offsetY: XCUIElement { app.sliders["Y 偏移"] }
    private var blur: XCUIElement { app.sliders["模糊"] }

    /// The panel is short, so a lower row may sit under its bottom edge, where
    /// it still counts as hittable although a fade hides it. Drag the page up
    /// slowly (no fling, from the left margin so a slider does not take the
    /// drag) until `element`'s middle is well above that edge.
    private func scrollToReveal(_ element: XCUIElement) {
        let screenHeight = app.windows.firstMatch.frame.height
        var tries = 0
        while (!element.isHittable || element.frame.midY > screenHeight * 0.82) && tries < 10 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.88))
                .press(forDuration: 0.1,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.76)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
            tries += 1
        }
        if !element.isHittable { attach("not-hittable") }
        XCTAssertTrue(element.isHittable, "scrolled into view")
    }

    /// Waits until `element` stops moving, so a scroll that is still settling
    /// does not carry the slider away from the finger.
    private func waitForSettled(_ element: XCUIElement) {
        var last = element.frame
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.4)
            let now = element.frame
            if now == last { return }
            last = now
        }
    }

    /// Drags `slider`'s thumb to the far right. On the SE the row sits at the
    /// panel's bottom edge, and one drag now and then missed (the value stayed
    /// put), so: reveal, let the page settle, drag from the thumb, check, and
    /// try again a few times before giving up.
    private func dragToEnd(_ slider: XCUIElement, expecting end: String) {
        for attempt in 0..<3 {
            scrollToReveal(slider)
            waitForSettled(slider)
            // The blur slider runs 0...16.
            let fraction = (Double((slider.value as? String ?? "").split(separator: " ").first ?? "") ?? 0) / 16
            let thumb = slider.coordinate(withNormalizedOffset: CGVector(dx: min(max(fraction, 0.03), 0.97), dy: 0.5))
            let target = slider.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5))
            thumb.press(forDuration: 0.2, thenDragTo: target)
            if slider.value as? String == end { return }
            if attempt == 2 { attach("slider-drag-missed") }
        }
        XCTAssertEqual(slider.value as? String, end, "dragged to the end")
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
        dragToEnd(blur, expecting: "16 點")
        XCTAssertFalse(app.buttons["硬陰影"].isSelected)
        for name in ["無陰影", "柔和", "發光"] { XCTAssertFalse(app.buttons[name].isSelected, name) }
        app.buttons["硬陰影"].tap()
        XCTAssertTrue(app.buttons["硬陰影"].isSelected)
        XCTAssertEqual(blur.value as? String, "0 點")
    }

    private var red: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'ED4956'")).firstMatch
    }

    /// 86.1 and 86.2: picking a type keeps the chosen color and opacity, and
    /// picking a color keeps the chosen type.
    func testTypeAndColorAreIndependent() {
        XCTAssertTrue(red.waitForExistence(timeout: 3))
        red.tap()
        XCTAssertTrue(red.isSelected)
        let opacity = app.sliders["陰影透明度"].value as? String
        attach("shadow-red-soft")
        for name in ["硬陰影", "發光", "柔和"] {
            app.buttons[name].tap()
            XCTAssertTrue(app.buttons[name].isSelected, name)
            XCTAssertTrue(red.isSelected, "86.1 \(name) 顏色維持")
            XCTAssertEqual(app.sliders["陰影透明度"].value as? String, opacity, "86.1 \(name) 不透明度維持")
            attach("shadow-red-\(name)")
        }
        app.buttons["發光"].tap()
        app.buttons["跟隨文字顏色"].tap()
        XCTAssertTrue(app.buttons["發光"].isSelected, "86.2 跟隨文字色")
        red.tap()
        XCTAssertTrue(app.buttons["發光"].isSelected, "86.2 色票")
        attach("shadow-glow-after-color")
    }

    /// 86.4: 無 keeps the color; the next type reuses it.
    func testNoneKeepsTheColor() {
        red.tap()
        app.buttons["無陰影"].tap()
        XCTAssertTrue(app.buttons["無陰影"].isSelected)
        XCTAssertTrue(red.isSelected, "86.4")
        app.buttons["硬陰影"].tap()
        XCTAssertTrue(red.isSelected, "86.4 再選類型沿用顏色")
    }

    /// 無 disables the parameter rows, which stay visible.
    func testNoneDisablesTheParameterRows() {
        app.buttons["無陰影"].tap()
        XCTAssertTrue(app.buttons["無陰影"].isSelected)
        XCTAssertFalse(blur.isEnabled)
        XCTAssertFalse(offsetX.isEnabled)
        XCTAssertFalse(app.sliders["陰影不透明度"].isEnabled)
        attach("shadow-none-disabled")
        app.buttons["柔和"].tap()
        XCTAssertTrue(blur.isEnabled)
    }
}
