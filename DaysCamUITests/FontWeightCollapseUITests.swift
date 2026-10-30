import XCTest

/// TASK-112 (#437): the selected multi-weight font's weights are collapsed
/// until its row is tapped; no check mark on the selected row.
final class FontWeightCollapseUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
        app.buttons["字型"].tap()
    }

    private var row: XCUIElement { app.buttons["蘋方"] }
    private func weight(_ id: String) -> XCUIElement { app.buttons["fontWeight.\(id)"] }

    /// 112.1／112.2／112.9: collapsed on arrival with the weight as the value;
    /// a tap expands (hint flips), another collapses; nothing is re-applied.
    func testRowTogglesTheWeightButtons() {
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(weight("light").exists, "112.1 collapsed on arrival")
        XCTAssertEqual(row.value as? String, "粗", "112.9 the value is the weight")
        XCTAssertTrue(row.isSelected)
        let heightBefore = row.frame.height
        row.tap()
        XCTAssertTrue(weight("light").waitForExistence(timeout: 3), "112.2 expanded")
        XCTAssertTrue(weight("semibold").isSelected, "112.2 the stored weight is still selected")
        XCTAssertEqual(row.frame.height, heightBefore, accuracy: 1, "the title row keeps its height")
        row.tap()
        XCTAssertFalse(weight("light").waitForExistence(timeout: 2), "112.2 collapsed again")
    }

    /// 112.3: a weight chosen while expanded is applied, the card stays open,
    /// and the collapsed row then shows that weight.
    func testChoosingAWeightUpdatesTheCollapsedRow() {
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(weight("light").waitForExistence(timeout: 3))
        weight("light").tap()
        XCTAssertTrue(weight("light").isSelected, "112.3 applied")
        XCTAssertTrue(weight("regular").exists, "112.3 stays expanded")
        row.tap()
        XCTAssertFalse(weight("light").waitForExistence(timeout: 2))
        XCTAssertEqual(row.value as? String, "細", "112.3 the row shows the chosen weight")
    }

    /// 112.5: leaving the page and coming back collapses the card.
    func testReturningToThePageCollapses() {
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(weight("light").waitForExistence(timeout: 3))
        app.buttons["外框"].tap()
        app.buttons["字型"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(weight("light").waitForExistence(timeout: 2), "112.5 collapsed on return")
    }
}
