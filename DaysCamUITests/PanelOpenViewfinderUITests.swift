import XCTest

/// Screenshots for TASK-98's B′ comparison (98.8, #402): the panel open on
/// each ratio. Attached to the result; with `DAYSCAM_UI_SHOT_DIR` in the
/// test runner's environment they are also written there as PNGs, named by
/// the ratio button's label at the time.
final class PanelOpenViewfinderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        app.openCamera()
    }

    private var ratioButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '比例：'")).firstMatch
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

    /// 98.8: open the panel, then cycle through the three ratios, shooting
    /// each; the panel stays open throughout (the ratio button is on the
    /// toolbar, outside the panel).
    func testPanelOpenOnEveryRatio() {
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5), "the panel opened")
        XCTAssertTrue(ratioButton.waitForExistence(timeout: 3))
        var seen: [String] = []
        for _ in 0..<3 {
            let label = ratioButton.label.replacingOccurrences(of: "比例：", with: "").replacingOccurrences(of: ":", with: "x")
            XCTAssertFalse(seen.contains(label), "each ratio once")
            seen.append(label)
            attach("98.8_panel-open_\(label)")
            // The overlay text is still above the panel on every ratio (98.6).
            let text = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '第 '")).firstMatch
            XCTAssertTrue(text.exists, "\(label): the day-count text is on screen")
            XCTAssertLessThan(text.frame.maxY, app.buttons["樣式"].frame.minY, "\(label): 98.6 the text is above the panel")
            ratioButton.tap()
            XCTAssertTrue(app.buttons["樣式"].exists, "\(label): the panel stayed open")
        }
        XCTAssertEqual(seen.count, 3)
    }
}
