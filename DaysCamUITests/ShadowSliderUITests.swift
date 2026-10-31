import XCTest

/// The shadow sub-tab's presets and colors end to end (TASK-71 / TASK-118). The app starts from a fresh profile via
/// `-UITestFreshProfiles <name>`.
final class ShadowSliderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
        app.buttons["樣式"].tap()
        app.buttons["陰影"].tap()
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

    /// 71.3 / 118.1 / 118.2: the four presets are all there, and the page has
    /// no offset or blur sliders (TASK-118).
    func testPresetsAreTheOnlyShapeControls() {
        for name in ["無陰影", "柔和", "硬陰影", "發光"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3), name)
        }
        XCTAssertTrue(app.buttons["柔和"].isSelected, "預設 soft")
        for name in ["X 偏移", "Y 偏移", "模糊"] {
            XCTAssertFalse(app.sliders[name].exists, "118.1 \(name)")
        }
        attach("118.1_shadow-soft")

        app.buttons["硬陰影"].tap()
        XCTAssertTrue(app.buttons["硬陰影"].isSelected, "118.2")
        XCTAssertFalse(app.buttons["柔和"].isSelected)
        attach("118.2_shadow-hard")

        app.buttons["發光"].tap()
        XCTAssertTrue(app.buttons["發光"].isSelected, "118.2")
        attach("118.2_shadow-glow")
    }

    private var red: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'ED4956'")).firstMatch
    }

    /// 86.1 and 86.2: picking a type keeps the chosen color, and picking a
    /// color keeps the chosen type. The opacity row is gone (TASK-113, 113.1);
    /// the opacity itself is covered by `StyleTabModelTests`.
    func testTypeAndColorAreIndependent() {
        XCTAssertTrue(red.waitForExistence(timeout: 3))
        red.tap()
        XCTAssertTrue(red.isSelected)
        XCTAssertFalse(app.sliders["陰影不透明度"].exists, "113.1")
        attach("shadow-red-soft")
        for name in ["硬陰影", "發光", "柔和"] {
            app.buttons[name].tap()
            XCTAssertTrue(app.buttons[name].isSelected, name)
            XCTAssertTrue(red.isSelected, "86.1 \(name) 顏色維持")
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

    /// 118.3: 無 disables the color swatches, and another preset enables them.
    func testNoneDisablesTheColorSection() {
        app.buttons["無陰影"].tap()
        XCTAssertTrue(app.buttons["無陰影"].isSelected)
        XCTAssertFalse(red.isEnabled)
        attach("118.3_shadow-none-disabled")
        app.buttons["柔和"].tap()
        XCTAssertTrue(red.isEnabled)
        attach("118.3_shadow-soft-enabled")
    }
}
