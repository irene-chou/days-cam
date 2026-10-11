import XCTest

/// The profile sheet without its checkmark key (TASK-101, #410: 101.1–101.5).
/// The app starts from a fresh profile and skips the first-launch tour.
final class ProfileSheetDismissUITests: XCTestCase {
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

    private func openSheet() {
        XCTAssertTrue(profileChip.waitForExistence(timeout: 10))
        profileChip.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5), "the profile sheet opened")
    }

    private func swipeSheetDown() {
        let start = sheetBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 600)))
    }

    private func assertSheetClosed(_ note: String) {
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 5), note)
        XCTAssertFalse(sheetBar.exists, note)
    }

    /// 101.1／101.3: no checkmark on the list page; swiping down closes.
    func testListPageHasNoCheckmarkAndSwipesDown() {
        openSheet()
        XCTAssertFalse(sheetBar.buttons["完成"].exists, "101.1 no checkmark key")
        XCTAssertFalse(app.buttons["完成"].exists, "101.1 no checkmark key anywhere")
        swipeSheetDown()
        assertSheetClosed("101.3 swiped down")
        XCTAssertTrue(profileChip.exists, "101.5 the camera screen is back with its chip")
    }

    /// 101.2／101.3: the edit page has no checkmark, its back button returns
    /// to the list, and a swipe closes the whole sheet; the edited name is
    /// kept (101.5).
    func testEditPageHasBackButtonAndNoCheckmark() {
        openSheet()
        let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '編輯'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "the edit page opened")
        XCTAssertFalse(app.buttons["完成"].exists, "101.2 no checkmark key on the edit page")
        let back = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(back.exists, "101.2 the system back button is there")
        nameField.tap()
        nameField.typeText("乙")
        back.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5), "101.2 back returns to the list")
        swipeSheetDown()
        assertSheetClosed("101.3 swiped down from the list after editing")
        XCTAssertTrue(profileChip.label.contains("乙"), "101.5 the edited name reached the camera screen: \(profileChip.label)")
    }

    /// 101.4: tapping the dimmed area above the sheet closes it.
    func testTapOutsideClosesTheSheet() {
        openSheet()
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        assertSheetClosed("101.4 tapped outside")
    }
}
