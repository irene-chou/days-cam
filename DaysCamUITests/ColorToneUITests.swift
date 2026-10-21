import XCTest

/// #590: the tools capsule's 色調 button, the five-step picker under it and
/// the viewfinder's approximate tint. With `DAYSCAM_UI_SHOT_DIR` in the test
/// runner's environment the screenshots are also written there.
///
/// The tone lives in the real `UserDefaults`, so each test first puts it back
/// to 標準 (and leaves it there) instead of assuming a fresh install.
final class ColorToneUITests: XCTestCase {
    private let profileName = UUID().uuidString

    private func launch(angle: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", profileName]
        if let angle { app.launchArguments += ["-UITestCaptureRotationAngle", angle] }
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openCapsule(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["相機設定"].waitForExistence(timeout: 10))
        if !app.buttons["閃光燈"].exists { app.buttons["相機設定"].tap() }
        XCTAssertTrue(app.buttons["閃光燈"].waitForExistence(timeout: 3))
    }

    private func openPicker(_ app: XCUIApplication) {
        openCapsule(app)
        if !element("tonePicker", in: app).exists { element("toneButton", in: app).tap() }
        XCTAssertTrue(element("tonePicker", in: app).waitForExistence(timeout: 3))
    }

    /// Normalizes a tone left over from an earlier run, then closes the capsule.
    private func resetToStandard(_ app: XCUIApplication) {
        openPicker(app)
        element("tone_standard", in: app).tap()
        app.buttons["相機設定"].tap()
        XCTAssertFalse(app.buttons["閃光燈"].waitForExistence(timeout: 1))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
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

    /// 590.1–590.4, 590.6: button, picker, tint, capsule close and relaunch.
    func testPickingATonePersistsAndTintsTheViewfinder() {
        continueAfterFailure = false
        var app = launch()
        resetToStandard(app)
        openCapsule(app)
        XCTAssertFalse(element("toneTint", in: app).exists, "590.4 standard has no tint")
        let toneButton = element("toneButton", in: app)
        XCTAssertEqual(toneButton.label, "色調：標準")
        attach(app, "590.1_capsule-standard")
        toneButton.tap()
        let picker = element("tonePicker", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "590.2 the picker opened")
        let screen = app.windows.firstMatch.frame
        for raw in ["cool2", "cool1", "standard", "warm1", "warm2"] {
            let dot = element("tone_\(raw)", in: app)
            XCTAssertTrue(dot.exists, raw)
            XCTAssertTrue(screen.contains(dot.frame), "590.2 \(raw) is on screen")
        }
        XCTAssertTrue(element("tone_standard", in: app).isSelected, "590.2 standard is selected")
        attach(app, "590.2_picker-standard")

        element("tone_warm2", in: app).tap()
        XCTAssertEqual(toneButton.label, "色調：暖 2", "590.3")
        XCTAssertTrue(element("tone_warm2", in: app).isSelected)
        XCTAssertTrue(picker.exists, "590.2 the picker stays open after a pick")
        XCTAssertTrue(element("toneTint", in: app).waitForExistence(timeout: 3), "590.4 warm 2 tints")
        attach(app, "590.4_picker-warm2")

        element("tone_cool1", in: app).tap()
        XCTAssertEqual(toneButton.label, "色調：冷 1")
        attach(app, "590.4_picker-cool1")
        element("tone_warm2", in: app).tap()

        app.buttons["相機設定"].tap()
        XCTAssertFalse(app.buttons["閃光燈"].waitForExistence(timeout: 1))
        openCapsule(app)
        XCTAssertFalse(element("tonePicker", in: app).exists, "590.2 the picker closed with the capsule")
        XCTAssertEqual(element("toneButton", in: app).label, "色調：暖 2")

        app.terminate()
        app = launch()
        openCapsule(app)
        XCTAssertEqual(element("toneButton", in: app).label, "色調：暖 2", "590.6 kept after relaunch")
        XCTAssertTrue(element("toneTint", in: app).exists, "590.6 the tint is back too")
        element("toneButton", in: app).tap()
        XCTAssertTrue(element("tone_warm2", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("tone_warm2", in: app).isSelected, "590.6 the picker shows the last tone")
        element("tone_standard", in: app).tap()
        XCTAssertFalse(element("toneTint", in: app).exists, "590.4 back to standard removes the tint")
    }

    /// 590.8: with the top edge pointing left (`-UITestCaptureRotationAngle 0`)
    /// the tone icon turns upright in place, which shows as different pixels
    /// than held upright (angle 90) while the tap target stays put. The
    /// picker row neither turns nor moves.
    func testIconTurnsButPickerDoesNotWhenHeldSideways() {
        continueAfterFailure = false
        var upright = launch(angle: "90")
        resetToStandard(upright)
        openPicker(upright)
        let uprightIcon = element("toneButton", in: upright)
        let uprightIconPixels = uprightIcon.screenshot().pngRepresentation
        let uprightIconFrame = uprightIcon.frame
        let uprightPickerFrame = element("tonePicker", in: upright).frame
        upright.terminate()

        upright = launch(angle: "0")
        let app = upright
        openPicker(app)
        let icon = element("toneButton", in: app)
        let picker = element("tonePicker", in: app)
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(icon.frame), "590.8 icon on screen")
        XCTAssertTrue(screen.contains(picker.frame), "590.8 picker on screen")
        XCTAssertEqual(icon.frame, uprightIconFrame, "590.8 the tap target stays put")
        XCTAssertNotEqual(icon.screenshot().pngRepresentation, uprightIconPixels, "590.8 the icon turned")
        XCTAssertEqual(picker.frame, uprightPickerFrame, "590.8 the picker did not move")
        XCTAssertGreaterThan(picker.frame.width, picker.frame.height * 3, "590.8 the picker did not turn")
        attach(app, "590.8_picker-landscape")
    }
}
