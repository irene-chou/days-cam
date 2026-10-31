import XCTest

/// #617: the 紀錄 list is the first screen (acceptance 1, 2, 3, 5, 6, 9). With
/// `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′ screenshots
/// are also written there for the PR.
final class RecordListUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one default record on 2026-01-01, then launches on 2026-01-10
    /// into the same profile directory, so the record reads "第 10 天".
    private func launch(extra: [String] = []) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", profiles] + extra
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Leaves the photo wall for the list with the system back button.
    private func backToList() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["紀錄"].waitForExistence(timeout: 5))
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
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    /// 1 and 2: the first screen is the list; without access the count is "—".
    func testColdLaunchShowsTheListWithADash() {
        launch(extra: ["-UITestRecordPhotos", "5", "-UITestPhotoAccess", "denied"])
        XCTAssertTrue(app.navigationBars["紀錄"].waitForExistence(timeout: 10), "1 the list is first")
        XCTAssertFalse(app.buttons["快門"].exists, "1 not the camera")
        let row = element("recordRow")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("今天第 10 天 · —"), "2 \(row.label)")
        XCTAssertTrue(app.buttons["新增紀錄"].exists)
        XCTAssertFalse(app.staticTexts["recordListFooter"].exists, "3 denied shows no footer")
        shot("record-list")
    }

    /// 3: with access and a bound album the count shows.
    func testBoundAlbumShowsItsCount() {
        launch(extra: ["-UITestRecordPhotos", "5", "-UITestBindAlbum"])
        let row = element("recordRow")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("今天第 10 天 · 5 張"), "3 \(row.label)")
        XCTAssertEqual(element("recordListFooter").label, "每個紀錄是「照片」App 裡的一本相簿，在那裡加入的照片會自動出現", "3")
        shot("record-list-full")
    }

    /// 5: one record cannot be deleted; with two the dialog says so.
    func testDeletionIsBlockedForTheLastRecordAndConfirmsOtherwise() {
        launch(extra: ["-UITestRecordPhotos", "0"])
        let row = element("recordRow")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        XCTAssertFalse(app.buttons["刪除"].exists, "5 no delete for the last record")
        XCTAssertTrue(app.buttons["編輯"].waitForExistence(timeout: 3))
        app.tap()

        app.buttons["新增紀錄"].tap()
        XCTAssertTrue(element("recordEditor").waitForExistence(timeout: 5))
        app.buttons["createRecordButton"].tap()
        XCTAssertTrue(element("wallEmptyState").waitForExistence(timeout: 10))
        backToList()

        let first = app.descendants(matching: .any).matching(identifier: "recordRow").element(boundBy: 0)
        first.swipeLeft()
        app.buttons["刪除"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '都會保留' OR label CONTAINS '照片會保留在'")).firstMatch
            .waitForExistence(timeout: 3), "6 the dialog names what is kept")
    }

    /// 6: add a record named 小寶, tick it, land on its photo wall.
    func testAddingARecordCreatesAndOpensIt() {
        launch(extra: ["-UITestRecordPhotos", "0"])
        XCTAssertTrue(app.buttons["新增紀錄"].waitForExistence(timeout: 10))
        app.buttons["新增紀錄"].tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("小寶")
        app.buttons["createRecordButton"].tap()
        XCTAssertTrue(element("wallEmptyState").waitForExistence(timeout: 10), "6 the new record opened")
        backToList()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '小寶'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "6 the record is listed")
    }

    /// 9: denied access disables the album row.
    func testDeniedAccessShowsNeedsPermission() {
        launch(extra: ["-UITestRecordPhotos", "0", "-UITestPhotoAccess", "denied"])
        element("recordRow").tap()
        // The wall opens; get back and edit through the swipe action.
        XCTAssertTrue(element("wallMoreButton").waitForExistence(timeout: 10))
        backToList()
        let row = element("recordRow")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["編輯"].tap()
        let albumRow = element("albumRow")
        XCTAssertTrue(albumRow.waitForExistence(timeout: 5))
        XCTAssertTrue(albumRow.label.contains("需要「照片」權限"), "5 \(albumRow.label)")
        XCTAssertFalse(element("albumPicker").exists)
        shot("record-editor-denied")
    }

    /// 7 (UI side): pick the fake album, then the create row again.
    func testPickingAnAlbumShowsTheCheckmark() {
        launch(extra: ["-UITestRecordPhotos", "3"])
        element("recordRow").tap()
        XCTAssertTrue(element("wallMoreButton").waitForExistence(timeout: 10))
        backToList()
        let row = element("recordRow")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["編輯"].tap()
        let albumRow = element("albumRow")
        XCTAssertTrue(albumRow.waitForExistence(timeout: 5))
        albumRow.tap()
        XCTAssertTrue(element("albumPicker").waitForExistence(timeout: 5))
        let options = app.descendants(matching: .any).matching(identifier: "albumOption")
        XCTAssertTrue(options.element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertTrue(options.element(boundBy: 1).label.contains("測試相簿"))
        options.element(boundBy: 1).tap()
        XCTAssertTrue(options.element(boundBy: 1).isSelected)
        shot("album-picker")
    }
}
