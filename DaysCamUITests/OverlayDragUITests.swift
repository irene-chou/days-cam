import XCTest

/// #568: the overlay text can be dragged from either tab and is exposed to
/// tests as `overlayTextDraggable` (the dashed frame itself only shows while
/// pressed or briefly on open, #599). Since #621 this is the export page's
/// preview; the camera no longer draws the overlay.
/// With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′
/// screenshots are also written there.
final class OverlayDragUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private var row: XCUIElement { app.buttons["positionRow"] }

    private func openPanel() {
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5), "the panel is there")
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

    /// Drags the text up and to the left by a third of the preview.
    private func dragText(_ text: XCUIElement) {
        let preview = element("exportPreview").frame
        let start = text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -preview.width * 0.3, dy: -preview.height * 0.3)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func openPositionRowLabel() -> String {
        app.buttons["內容"].tap()
        app.revealInPanel(row)
        return row.label
    }

    /// #568-5／7: on 樣式 the text is draggable and a drag leaves 自訂位置 on the row.
    func testDragOnStyleTab() {
        openPanel()
        XCTAssertTrue(app.buttons["樣式"].isSelected)
        XCTAssertTrue(element("overlayTextDraggable").waitForExistence(timeout: 3), "568.7 draggable on 樣式")
        let text = element("overlayTextDraggable")
        let before = text.frame
        // #599-1: the open-time hint is gone after 1s, so the style tab is clean.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(text.frame.intersects(app.frame), "599.1 the text is in view")
        shot("style-tab-no-frame")
        dragText(text)
        XCTAssertLessThan(text.frame.midX, before.midX - 20, "568.5 the text followed the finger")
        XCTAssertEqual(openPositionRowLabel(), "位置，自訂位置", "568.5 saved as custom")
    }

    /// #605-2: right after release the text stays where the finger left it.
    func testReleaseDoesNotBounceBack() {
        openPanel()
        let text = element("overlayTextDraggable")
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        dragText(text)
        let released = text.frame
        for _ in 0..<5 {
            let frame = element("overlayTextDraggable").exists ? element("overlayTextDraggable").frame : element("overlayText").frame
            XCTAssertEqual(frame.midX, released.midX, accuracy: 2, "605.2 no bounce")
            XCTAssertEqual(frame.midY, released.midY, accuracy: 2, "605.2 no bounce")
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// #605 review: grabbing again right after release starts from the released point.
    func testRegrabRightAfterReleaseStartsFromReleasePoint() {
        openPanel()
        let text = element("overlayTextDraggable")
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        dragText(text)
        let released = text.frame
        let start = text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 40)), withVelocity: .slow, thenHoldForDuration: 0.2)
        let after = element("overlayTextDraggable").frame
        XCTAssertEqual(after.midX, released.midX, accuracy: 4, "605 regrab keeps x")
        XCTAssertEqual(after.midY, released.midY + 40, accuracy: 6, "605 regrab moved 40pt from the release point")
    }

    /// #568-5／7: the same on 內容.
    func testDragOnLayoutTab() {
        openPanel()
        app.buttons["內容"].tap()
        XCTAssertTrue(app.buttons["內容"].isSelected)
        XCTAssertTrue(element("overlayTextDraggable").waitForExistence(timeout: 3), "568.7 draggable on 內容")
        let text = element("overlayTextDraggable")
        let before = text.frame
        dragText(text)
        XCTAssertLessThan(text.frame.midX, before.midX - 20, "568.5 the text followed the finger")
        app.revealInPanel(row)
        XCTAssertEqual(row.label, "位置，自訂位置", "568.5 saved as custom")
    }

    /// #568: a plain tap on the text leaves 右下 alone.
    func testTapWhileOpenKeepsTheAnchor() {
        openPanel()
        let text = element("overlayTextDraggable")
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(openPositionRowLabel(), "位置，右下", "a tap is not a drag")
    }
}
