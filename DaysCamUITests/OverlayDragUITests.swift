import XCTest

/// #568: with the panel open, the overlay text can be dragged from either tab
/// and shows a dashed frame (exposed to tests as the `overlayTextDraggable`
/// identifier); with it closed the text neither drags nor shows the frame.
/// With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′
/// screenshots are also written there.
final class OverlayDragUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFocus", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
    }

    private var overlayText: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '第 '")).firstMatch
    }
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private var row: XCUIElement { app.buttons["positionRow"] }

    private func openPanel() {
        app.buttons["疊字設定"].tap()
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5), "the panel opened")
    }

    private func shot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["DAYSCAM_UI_SHOT_DIR"], !path.isEmpty {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let device = UIDevice.current.name.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR568_\(name)_\(device).png"))
        }
    }

    /// Drags the text up and to the left by about a quarter of the screen.
    private func dragText(_ text: XCUIElement) {
        let start = text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -app.frame.width * 0.25, dy: -app.frame.height * 0.12)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func openPositionRowLabel() -> String {
        app.buttons["版面"].tap()
        app.revealInPanel(row)
        return row.label
    }

    /// #568-5／7: on 樣式 the frame shows and a drag leaves 自訂位置 on the row.
    func testDragOnStyleTab() {
        openPanel()
        XCTAssertTrue(app.buttons["樣式"].isSelected)
        XCTAssertTrue(element("overlayTextDraggable").waitForExistence(timeout: 3), "568.7 dashed frame on 樣式")
        let text = element("overlayTextDraggable")
        let before = text.frame
        shot("style-tab-dashed-frame")
        dragText(text)
        XCTAssertLessThan(text.frame.midX, before.midX - 20, "568.5 the text followed the finger")
        XCTAssertEqual(openPositionRowLabel(), "位置，自訂位置", "568.5 saved as custom")
    }

    /// #568-5／7: the same on 版面.
    func testDragOnLayoutTab() {
        openPanel()
        app.buttons["版面"].tap()
        XCTAssertTrue(app.buttons["版面"].isSelected)
        XCTAssertTrue(element("overlayTextDraggable").waitForExistence(timeout: 3), "568.7 dashed frame on 版面")
        let text = element("overlayTextDraggable")
        let before = text.frame
        dragText(text)
        XCTAssertLessThan(text.frame.midX, before.midX - 20, "568.5 the text followed the finger")
        app.revealInPanel(row)
        XCTAssertEqual(row.label, "位置，自訂位置", "568.5 saved as custom")
    }

    /// #568-6／7: closed, no frame, a drag does not move the text, a tap opens the panel.
    func testClosedPanelDoesNotDrag() {
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))
        XCTAssertFalse(element("overlayTextDraggable").exists, "568.7 no frame while closed")
        let before = overlayText.frame
        dragText(overlayText)
        XCTAssertEqual(overlayText.frame.midX, before.midX, accuracy: 2, "568.6 did not move")
        XCTAssertEqual(overlayText.frame.midY, before.midY, accuracy: 2)
        XCTAssertFalse(app.buttons["樣式"].exists, "568.6 a drag does not open the panel")
        overlayText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5), "568.6 a tap opens it")
    }
}
