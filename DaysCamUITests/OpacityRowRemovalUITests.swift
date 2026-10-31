import XCTest

/// TASK-113 113.1 B′ evidence: the colour, outline and shadow pages without
/// their opacity rows. With `DAYSCAM_UI_SHOT_DIR` in the test runner's
/// environment the screenshots are also written there for the PR.
final class OpacityRowRemovalUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
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

    private var opacitySliders: XCUIElementQuery {
        app.sliders.matching(NSPredicate(format: "label CONTAINS '不透明度'"))
    }

    func testNoOpacityRowOnAnyPage() {
        app.buttons["顏色"].tap()
        XCTAssertTrue(app.buttons["顏色"].waitForExistence(timeout: 3))
        XCTAssertEqual(opacitySliders.count, 0, "113.1 顏色")
        attach("113.1_color")

        app.buttons["外框"].tap()
        XCTAssertTrue(app.buttons["描邊"].waitForExistence(timeout: 3))
        app.buttons["描邊"].tap()
        XCTAssertEqual(opacitySliders.count, 0, "113.1 外框")
        attach("113.1_outline-stroke")

        app.buttons["陰影"].tap()
        XCTAssertTrue(app.buttons["柔和"].waitForExistence(timeout: 3))
        XCTAssertEqual(opacitySliders.count, 0, "113.1 陰影")
        attach("113.1_shadow")
    }
}
