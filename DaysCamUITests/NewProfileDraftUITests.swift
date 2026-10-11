import XCTest

/// TASK-106 (#421): a new profile that is left untouched is not kept; its
/// name field starts empty with a placeholder; a named one is kept.
final class NewProfileDraftUITests: XCTestCase {
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
    private var addButton: XCUIElement { app.buttons["新增設定檔"] }
    private var nameField: XCUIElement { app.textFields.firstMatch }
    private var backButton: XCUIElement { app.navigationBars.firstMatch.buttons.firstMatch }

    private func openSheet() {
        XCTAssertTrue(profileChip.waitForExistence(timeout: 10))
        profileChip.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5), "the profile sheet opened")
    }

    private func addProfile() {
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "the edit page opened")
    }

    private func swipeSheetDown() {
        let bar = app.navigationBars.firstMatch
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 600)))
    }

    private func assertSheetClosed(_ note: String) {
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 5), note)
        XCTAssertFalse(sheetBar.exists, note)
    }

    /// 106.1／106.3: the name field is empty with the placeholder; ‹ without
    /// any change leaves one profile and the chip unchanged.
    func testUntouchedNewProfileIsNotKeptOnBack() {
        openSheet()
        let chipBefore = profileChip.label
        addProfile()
        XCTAssertEqual(nameField.placeholderValue, "新設定檔", "106.3 placeholder")
        XCTAssertEqual(nameField.value as? String, "新設定檔", "106.3 the field itself is empty (shows the placeholder)")
        backButton.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1, "106.1 no extra profile")
        swipeSheetDown()
        assertSheetClosed("back on the camera")
        XCTAssertEqual(profileChip.label, chipBefore, "106.1 the current profile is unchanged")
    }

    /// 106.2: swiping the sheet down from the untouched new profile's page
    /// has the same result.
    func testUntouchedNewProfileIsNotKeptOnSwipeDown() {
        openSheet()
        let chipBefore = profileChip.label
        addProfile()
        swipeSheetDown()
        assertSheetClosed("106.2 swiped down")
        XCTAssertEqual(profileChip.label, chipBefore, "106.2 the current profile is unchanged")
        openSheet()
        XCTAssertEqual(rows.count, 1, "106.2 no extra profile")
    }

    /// 106.2: tapping outside the sheet, likewise.
    func testUntouchedNewProfileIsNotKeptOnTapOutside() {
        openSheet()
        addProfile()
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        assertSheetClosed("106.2 tapped outside")
        openSheet()
        XCTAssertEqual(rows.count, 1, "106.2 no extra profile")
    }

    /// 106.4: typing a name keeps the profile and switches to it.
    func testNamedNewProfileIsKeptAndSelected() {
        openSheet()
        addProfile()
        nameField.tap()
        nameField.typeText("小寶")
        backButton.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2, "106.4 kept")
        let newRow = rows.element(boundBy: 1)
        XCTAssertTrue(newRow.label.hasPrefix("小寶"), "106.4 named: \(newRow.label)")
        XCTAssertTrue(newRow.isSelected, "106.4 switched to it")
        swipeSheetDown()
        assertSheetClosed("back on the camera")
        XCTAssertTrue(profileChip.label.contains("小寶"), "106.4 the chip shows it: \(profileChip.label)")
    }

    /// 106.5: changing only the counting rule keeps the profile under the
    /// automatic name.
    func testChangedRuleWithoutANameIsKeptAsNewProfile() {
        openSheet()
        addProfile()
        let dayZero = app.buttons["第 0 天"]
        XCTAssertTrue(dayZero.waitForExistence(timeout: 5))
        dayZero.tap()
        backButton.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2, "106.5 kept")
        XCTAssertTrue(rows.element(boundBy: 1).label.hasPrefix("新設定檔"), "106.5 automatic name: \(rows.element(boundBy: 1).label)")
    }
}
