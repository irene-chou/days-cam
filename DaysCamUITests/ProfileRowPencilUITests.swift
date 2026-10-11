import XCTest

/// TASK-105 (#420): the profile list's row-end pencil edits without
/// switching; tapping the current row edits it; tapping another row switches.
final class ProfileRowPencilUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
    }

    private var profileChip: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '設定檔：'")).firstMatch
    }
    private var sheetBar: XCUIElement { app.navigationBars["設定檔"] }
    private var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "profileRow")
    }
    private var pencils: XCUIElementQuery {
        app.buttons.matching(identifier: "profileEditButton")
    }
    private var backButton: XCUIElement { app.navigationBars.firstMatch.buttons.firstMatch }
    private var nameField: XCUIElement { app.textFields.firstMatch }

    private func openSheet() {
        XCTAssertTrue(profileChip.waitForExistence(timeout: 10))
        profileChip.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5), "the profile sheet opened")
    }

    /// Adds a second profile named `name` and returns to the list; the new
    /// one is the current profile afterwards (FR-9.8).
    private func addProfile(named name: String) {
        let add = app.buttons["新增設定檔"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        backButton.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
    }

    private func assertSheetClosed(_ note: String) {
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 5), note)
        XCTAssertFalse(sheetBar.exists, note)
    }

    /// 105.4／105.7: every row ends in a pencil labelled 編輯〈名稱〉; tapping
    /// the pencil of a non-current profile edits it while the camera's
    /// current profile stays put.
    func testPencilEditsWithoutSwitching() {
        openSheet()
        addProfile(named: "乙")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(pencils.count, 2, "105.4 a pencil on every row")
        let chipBefore = profileChip.label
        XCTAssertTrue(chipBefore.contains("乙"), "the new profile is current: \(chipBefore)")
        let firstRow = rows.element(boundBy: 0)
        XCTAssertFalse(firstRow.isSelected, "the first row is not the current one")
        let firstName = String(firstRow.label.split(separator: "，").first ?? "")
        let pencil = app.buttons["編輯\(firstName)"]
        XCTAssertTrue(pencil.exists, "105.7 the pencil reads 編輯〈名稱〉: \(firstName)")
        pencil.tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "105.4 the edit page opened")
        XCTAssertEqual(nameField.value as? String, firstName, "105.4 editing the first profile, not the current one")
        backButton.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5), "105.6 ‹ returns to the list")
        XCTAssertEqual(profileChip.label, chipBefore, "105.4 the current profile did not change")
    }

    /// 105.5: tapping another row switches to it and closes the sheet.
    func testTappingAnotherRowSwitchesAndCloses() {
        openSheet()
        addProfile(named: "乙")
        let firstRow = rows.element(boundBy: 0)
        XCTAssertFalse(firstRow.isSelected)
        firstRow.tap()
        assertSheetClosed("105.5 switched and closed")
        XCTAssertFalse(profileChip.label.contains("乙"), "105.5 the first profile is current now: \(profileChip.label)")
    }

    /// 105.6: tapping the current row opens its edit page; ‹ goes back to the list.
    func testTappingTheCurrentRowEdits() {
        openSheet()
        let row = rows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isSelected, "the only profile is current")
        let name = String(row.label.split(separator: "，").first ?? "")
        row.tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "105.6 the edit page opened")
        XCTAssertEqual(nameField.value as? String, name)
        backButton.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5), "105.6 ‹ returns to the list")
        XCTAssertTrue(sheetBar.exists)
    }

    /// 105.7: VoiceOver reads the row as 〈名稱〉，〈副標〉.
    func testRowLabelIsNameAndSubtitle() {
        openSheet()
        let row = rows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let parts = row.label.split(separator: "，")
        XCTAssertEqual(parts.count, 2, "105.7 名稱，副標: \(row.label)")
        XCTAssertTrue(parts[1].contains("起"), "105.7 the subtitle is the start date line: \(row.label)")
    }
}
