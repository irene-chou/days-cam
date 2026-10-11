import XCTest

/// TASK-114: tapping a slider's track seeks to that point (114.1, 114.2,
/// 114.4, 114.5, 114.6). With `DAYSCAM_UI_SHOT_DIR` in the runner's
/// environment the screenshots are also written there.
final class TapSeekSliderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        openStyleTab()
    }

    private func openStyleTab() {
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
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

    /// Taps `slider`'s track at `fraction` of its width.
    private func tapTrack(_ slider: XCUIElement, at fraction: CGFloat) {
        slider.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)).tap()
    }

    private var sizePercent: String {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '字級 '")).firstMatch.label
    }

    private var offsetX: XCUIElement { app.sliders["shadowOffsetXSlider"] }

    /// Waits for `element`, then scrolls the page (slowly, from the left
    /// margin) until the row sits above the floating collapse button, which
    /// otherwise covers the right end of the lower shadow rows and would
    /// close the panel on a tap there.
    private func settle(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        let collapse = app.buttons["panelCollapseButton"]
        var tries = 0
        while collapse.exists, element.frame.maxY > collapse.frame.minY - 4, tries < 10 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.88))
                .press(forDuration: 0.1,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.76)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
            tries += 1
        }
        XCTAssertTrue(element.isHittable, "row revealed above the collapse button")
    }

    /// 114.1 / 114.4: the size slider seeks on a tap, its ends give the
    /// bounds, the hint names tapping, and a double tap still resets.
    func testSizeSliderSeeksAndDoubleTapStillResets() {
        app.buttons["字級"].tap()
        let slider = app.sliders["字級"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        XCTAssertEqual(sizePercent, "字級 100%")
        XCTAssertTrue(app.staticTexts["點或拖曳調整，點兩下回到預設大小"].exists, "114.4 hint")

        tapTrack(slider, at: 0.75)
        let after = sizePercent
        XCTAssertNotEqual(after, "字級 100%", "114.1 the tap seeks")
        let percent = Int(after.replacingOccurrences(of: "字級 ", with: "").replacingOccurrences(of: "%", with: "")) ?? 0
        // 70…160 by 5: three quarters of the track is about 135–145.
        XCTAssertTrue((130...150).contains(percent), "114.1 about three quarters: \(after)")
        attach("114.1_size-seek")

        tapTrack(slider, at: 0.02)
        XCTAssertEqual(sizePercent, "字級 70%", "114.1 left end is the minimum")
        tapTrack(slider, at: 0.98)
        XCTAssertEqual(sizePercent, "字級 160%", "114.1 right end is the maximum")

        slider.doubleTap()
        XCTAssertEqual(sizePercent, "字級 100%", "114.4 double tap resets")
    }

    /// 114.2 / 114.6: a parameter slider seeks and the value is saved once;
    /// a relaunch shows the tapped value.
    func testShadowOffsetSeeksAndPersists() {
        app.buttons["陰影"].tap()
        settle(offsetX)
        XCTAssertEqual(offsetX.value as? String, "0 點")

        tapTrack(offsetX, at: 0.9)
        let seeked = offsetX.value as? String
        XCTAssertTrue(["5 點", "6 點", "7 點"].contains(seeked ?? ""), "114.2 near the right end: \(seeked ?? "nil")")
        tapTrack(offsetX, at: 0.02)
        XCTAssertEqual(offsetX.value as? String, "-8 點", "114.2 left end")
        tapTrack(offsetX, at: 0.98)
        XCTAssertEqual(offsetX.value as? String, "8 點", "114.2 right end")
        tapTrack(offsetX, at: 0.25)
        let quarter = offsetX.value as? String
        XCTAssertTrue(["-5 點", "-4 點", "-3 點"].contains(quarter ?? ""), "114.2 a quarter: \(quarter ?? "nil")")
        attach("114.2_shadow-offset-seek")

        app.terminate()
        app.launch()
        openStyleTab()
        app.buttons["陰影"].tap()
        settle(offsetX)
        XCTAssertEqual(offsetX.value as? String, quarter, "114.6 the tapped value was saved")
    }

    /// 114.5: a disabled slider (shadow 無) ignores taps.
    func testDisabledSliderIgnoresTaps() {
        app.buttons["陰影"].tap()
        settle(offsetX)
        app.buttons["無陰影"].tap()
        XCTAssertTrue(app.buttons["無陰影"].isSelected)
        // Clear of the floating collapse button at the row's right end.
        offsetX.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        app.buttons["柔和"].tap()
        settle(offsetX)
        XCTAssertEqual(offsetX.value as? String, "0 點", "114.5 nothing changed while disabled")
    }
}
