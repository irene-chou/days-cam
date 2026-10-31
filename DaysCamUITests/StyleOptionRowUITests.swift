import XCTest

/// The outline and shadow pages share one option row layout (TASK-87,
/// 87.1 to 87.4): 48pt boxes, 8pt apart, first box on the same left edge and
/// the same top, so switching pages does not shift the row.
final class StyleOptionRowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
        app.buttons["樣式"].tap()
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func frames(of names: [String]) -> [CGRect] {
        names.map { app.buttons[$0].frame }
    }

    func testOutlineAndShadowOptionRowsShareLayout() {
        app.buttons["外框"].tap()
        let outlineNames = ["無外框", "描邊", "底框"]
        XCTAssertTrue(app.buttons[outlineNames[0]].waitForExistence(timeout: 5))
        let outline = frames(of: outlineNames)
        attach("outline-page")

        app.buttons["陰影"].tap()
        let shadowNames = ["無陰影", "柔和", "硬陰影", "發光"]
        XCTAssertTrue(app.buttons[shadowNames[0]].waitForExistence(timeout: 5))
        let shadow = frames(of: shadowNames)
        attach("shadow-page")

        for frame in outline + shadow {
            XCTAssertEqual(frame.width, 48, accuracy: 0.5, "87.1")
            XCTAssertEqual(frame.height, 48, accuracy: 0.5, "87.1")
        }
        for row in [outline, shadow] {
            for index in 1..<row.count {
                XCTAssertEqual(row[index].minX - row[index - 1].maxX, 8, accuracy: 0.5, "87.2")
            }
        }
        XCTAssertEqual(shadow[0].minX, outline[0].minX, accuracy: 0.5, "87.3")
        XCTAssertEqual(shadow[0].minY, outline[0].minY, accuracy: 0.5, "87.4")
    }
}
