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
        app.descendants(matching: .any).matching(identifier: "profileRow")
    }

    /// Screenshot plus a line in `gestures.log` under `DAYSCAM_UI_SHOT_DIR`
    /// (diagnostics for the B′ comparison and for reading a failed run).
    private func snap(_ name: String, note: String = "") {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let path = ProcessInfo.processInfo.environment["DAYSCAM_UI_SHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        let line = "\(name): sheet=\(sheetBar.exists) rows=\(rows.count) dialog=\(deleteDialogButton.exists) delete=\(app.buttons["刪除"].exists) \(note)\n"
        if let handle = try? FileHandle(forWritingTo: directory.appendingPathComponent("gestures.log")) {
            handle.seekToEndOfFile(); handle.write(line.data(using: .utf8)!); try? handle.close()
        } else {
            try? line.write(to: directory.appendingPathComponent("gestures.log"), atomically: true, encoding: .utf8)
        }
    }

    /// Dismisses the delete confirmation without deleting: its cancel button,
    /// or a tap outside the action sheet when the button is not exposed.
    private func cancelDeleteDialog() {
        let cancel = app.buttons.matching(NSPredicate(format: "label == '取消' OR label == 'Cancel'")).firstMatch
        if cancel.waitForExistence(timeout: 2) {
            cancel.tap()
        } else {
            let labels = app.buttons.allElementsBoundByIndex.map(\.label).joined(separator: "|")
            snap("dialog-buttons", note: labels)
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        }
        XCTAssertFalse(deleteDialogButton.waitForExistence(timeout: 1.5), "the confirmation closed")
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
        // A lazy list only reports the rendered rows; with eight profiles
        // in a 0.68 sheet that is still more than fit, i.e. it must scroll.
        XCTAssertGreaterThanOrEqual(rows.count, 5, "eight profiles, several on screen")
        snap("103.1_eight-profiles")
        let first = rows.firstMatch
        let firstY = first.frame.minY
        let middle = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -220)), withVelocity: .slow,
                     thenHoldForDuration: 0.1)
        snap("103.1_after-drag-up")
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
        for attempt in 0..<5 {
            fullSwipeLeft(rows.element(boundBy: 1))
            snap("104.1_after-full-swipe-\(attempt)")
            if deleteDialogButton.waitForExistence(timeout: 3) {
                reached += 1
                cancelDeleteDialog()
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
        // A short, slow drag: XCUITest's `swipeLeft` is long enough to count
        // as a full swipe now that full swipes delete.
        let row = rows.element(boundBy: 1)
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        snap("104.3_after-half-swipe")
        let delete = app.buttons["刪除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "104.3 the 刪除 button is revealed")
        delete.tap()
        XCTAssertTrue(deleteDialogButton.waitForExistence(timeout: 3), "104.3 it asks to confirm")
        cancelDeleteDialog()
    }

    /// 104.4: the last remaining profile cannot be swiped away.
    func testSingleProfileHasNoDeleteSwipe() {
        openSheet()
        XCTAssertEqual(rows.count, 1)
        fullSwipeLeft(rows.firstMatch)
        snap("104.4_after-full-swipe-single")
        XCTAssertFalse(deleteDialogButton.waitForExistence(timeout: 1.5), "104.4 no delete on the only profile")
        let only = rows.firstMatch
        only.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: only.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertFalse(app.buttons["刪除"].waitForExistence(timeout: 1), "104.4 no 刪除 button either")
        XCTAssertTrue(sheetBar.exists)
    }
}
