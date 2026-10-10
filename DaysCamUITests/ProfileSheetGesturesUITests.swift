import XCTest

/// Gestures inside the profile sheet (TASK-103 #412, TASK-104 #413): a
/// vertical drag scrolls a long list instead of pulling the sheet down, a
/// left swipe reaches the delete action, and a full swipe asks to delete
/// straight away. The app starts from a fresh profile and skips the tour.
final class ProfileSheetGesturesUITests: XCTestCase {
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
    private var list: XCUIElement { app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch }
    private var deleteDialogButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '刪除「'")).firstMatch
    }
    private var rows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS '，'"))
    }

    private func openSheet() {
        XCTAssertTrue(profileChip.waitForExistence(timeout: 10))
        profileChip.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5), "the profile sheet opened")
    }

    /// Adds `count` profiles through 新增 and returns to the list each time.
    private func addProfiles(_ count: Int) {
        for _ in 0..<count {
            let add = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '新增'")).firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
            let back = app.navigationBars.firstMatch.buttons.firstMatch
            XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5), "the new profile's edit page")
            back.tap()
            XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
        }
    }

    private func fullSwipeLeft(_ row: XCUIElement) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: -0.6, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.1)
    }

    /// 103.1／103.2: with eight profiles a vertical drag scrolls the list and
    /// the sheet stays; a drag from the indicator still closes it.
    func testVerticalDragScrollsInsteadOfDismissing() {
        openSheet()
        addProfiles(7)
        XCTAssertGreaterThanOrEqual(rows.count, 8, "eight profiles")
        let first = rows.firstMatch
        let firstY = first.frame.minY
        let middle = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -220)), withVelocity: .slow,
                     thenHoldForDuration: 0.1)
        XCTAssertTrue(sheetBar.exists, "103.1 the sheet is still open after dragging up")
        XCTAssertLessThan(first.frame.minY, firstY - 40, "103.1 the list scrolled")
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: 220)), withVelocity: .slow,
                     thenHoldForDuration: 0.1)
        XCTAssertTrue(sheetBar.exists, "103.1 a drag down mid-list scrolls back, no dismiss")
        let indicator = sheetBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.4))
        indicator.press(forDuration: 0.1, thenDragTo: indicator.withOffset(CGVector(dx: 0, dy: 600)))
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 5), "103.2 the indicator still closes the sheet")
        XCTAssertFalse(sheetBar.exists)
    }

    /// 103.3／104.1／104.2: a full left swipe asks to delete; cancel keeps
    /// the row.
    func testFullSwipeAsksToDeleteAndCancelKeepsTheRow() {
        openSheet()
        addProfiles(1)
        let countBefore = rows.count
        XCTAssertGreaterThanOrEqual(countBefore, 2)
        var reached = 0
        for _ in 0..<5 {
            fullSwipeLeft(rows.element(boundBy: 1))
            if deleteDialogButton.waitForExistence(timeout: 2) {
                reached += 1
                app.buttons["取消"].tap()
                XCTAssertFalse(deleteDialogButton.waitForExistence(timeout: 1))
            }
            XCTAssertTrue(sheetBar.exists, "103.3 the sheet never came down")
        }
        XCTAssertGreaterThanOrEqual(reached, 4, "103.3／104.1 a full swipe opens the confirmation (\(reached)/5)")
        XCTAssertEqual(rows.count, countBefore, "104.2 cancel keeps every row")
        fullSwipeLeft(rows.element(boundBy: 1))
        XCTAssertTrue(deleteDialogButton.waitForExistence(timeout: 3))
        deleteDialogButton.tap()
        XCTAssertEqual(rows.count, countBefore - 1, "104.2 confirming deletes the row")
    }

    /// 104.3: a half swipe shows the 刪除 button, and tapping it asks too.
    func testHalfSwipeShowsDeleteButton() {
        openSheet()
        addProfiles(1)
        rows.element(boundBy: 1).swipeLeft()
        let delete = app.buttons["刪除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "104.3 the 刪除 button is revealed")
        delete.tap()
        XCTAssertTrue(deleteDialogButton.waitForExistence(timeout: 3), "104.3 it asks to confirm")
        app.buttons["取消"].tap()
    }

    /// 104.4: the last remaining profile cannot be swiped away.
    func testSingleProfileHasNoDeleteSwipe() {
        openSheet()
        XCTAssertEqual(rows.count, 1)
        fullSwipeLeft(rows.firstMatch)
        XCTAssertFalse(deleteDialogButton.waitForExistence(timeout: 1.5), "104.4 no delete on the only profile")
        rows.firstMatch.swipeLeft()
        XCTAssertFalse(app.buttons["刪除"].waitForExistence(timeout: 1), "104.4 no 刪除 button either")
        XCTAssertTrue(sheetBar.exists)
    }
}
