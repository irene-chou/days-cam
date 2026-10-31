import XCTest

/// #567: the 文字內容 card's 位置 row opens the nine-point grid in place and
/// writes the position the export preview shows. With `DAYSCAM_UI_SHOT_DIR` in
/// the test runner's environment the B′ screenshots are also written there.
final class ContentPositionRowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        content.tap()
        XCTAssertTrue(app.switches["天數"].waitForExistence(timeout: 5))
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
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR_\(name)_\(device).png"))
        }
    }

    private var row: XCUIElement { app.buttons["positionRow"] }
    private var expanded: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "positionExpanded").firstMatch
    }
    private func cell(_ name: String) -> XCUIElement { expanded.buttons[name] }
    /// Brings `element` between the tab bar and the home-indicator band.
    /// `revealInPanel` drags back to the top first, so a row scrolled above
    /// the tab bar (iPhone SE, after the grid opens) comes back too.
    private func scrollTo(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        app.revealInPanel(element, file: file, line: line)
    }

    private func waitUntilGone(_ element: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: 3) == .completed
    }

    /// #567-1／2／3／6／8: the row names the position and opens closed; it
    /// opens the grid in place, a tap there moves the text and keeps the
    /// grid open, and a second tap on the row closes it.
    func testRowOpensTheGridAndPicksAPosition() {
        scrollTo(row)
        // 567.1／8: the default position, closed.
        XCTAssertEqual(row.label, "位置，右下")
        XCTAssertEqual(row.value as? String, "已收起")
        XCTAssertFalse(expanded.exists, "567.2 closed by default")
        // The last row of the 文字內容 card, under 名稱.
        XCTAssertLessThan(app.switches["名稱"].frame.midY, row.frame.midY)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        shot("567.9_collapsed")

        row.tap()
        XCTAssertTrue(expanded.waitForExistence(timeout: 3), "567.2 opens")
        XCTAssertEqual(row.value as? String, "已展開")
        scrollTo(cell("右下"))
        XCTAssertEqual(expanded.buttons.count, 9, "nine points")
        XCTAssertTrue(cell("右下").isSelected, "567.8 the current point is selected")
        // 567.6: an 88pt box less its 4pt inset is 80pt of cells.
        XCTAssertEqual(cell("右下").frame.maxX - cell("左上").frame.minX, 80, accuracy: 2)
        XCTAssertEqual(cell("右下").frame.maxY - cell("左上").frame.minY, 80, accuracy: 2)
        shot("567.9_expanded")

        // 567.3: picking 左上 renames the row and keeps the grid open.
        cell("左上").tap()
        XCTAssertEqual(row.label, "位置，左上")
        XCTAssertTrue(cell("左上").isSelected)
        XCTAssertFalse(cell("右下").isSelected)
        XCTAssertTrue(expanded.exists, "567.3 still open")

        scrollTo(row)
        row.tap()
        XCTAssertTrue(waitUntilGone(expanded), "567.2 closes")
        XCTAssertEqual(row.value as? String, "已收起")
    }

    /// #568-3: a point picked on the 內容 tab's row moves the text on the
    /// preview.
    func testPickingAPointMovesTheTextOnThePreview() {
        let text = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", ["overlayText", "overlayTextDraggable"])).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        let before = text.frame
        scrollTo(row)
        row.tap()
        XCTAssertTrue(expanded.waitForExistence(timeout: 3))
        scrollTo(cell("左上"))
        cell("左上").tap()
        XCTAssertEqual(row.label, "位置，左上")
        let deadline = Date().addingTimeInterval(3)
        while text.frame.minX >= before.minX - 40 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertLessThan(text.frame.minX, before.minX - 40, "568.3 the text moved left")
        XCTAssertLessThan(text.frame.minY, before.minY - 40, "568.3 and up")
    }
}
