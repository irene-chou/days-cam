import XCTest

/// #619: the photo viewer (acceptance 1, 5, 8). With `DAYSCAM_UI_SHOT_DIR` in
/// the test runner's environment the B′ screenshots are also written there.
final class PhotoDetailUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record starting 2026-01-01, then launches on 2026-01-10 with
    /// five photos, one per day ending that day, and opens the record.
    private func launchWall(mixedAspects: Bool = false, showTips: Bool = false) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "5", "-UITestBindAlbum"]
        if mixedAspects { app.launchArguments.append("-UITestMixedAspects") }
        if showTips { app.launchArguments.append("-UITestShowTips") }
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
        XCTAssertTrue(cell(4).waitForExistence(timeout: 10))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func cell(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "photoCell").element(boundBy: index)
    }

    private func openViewer(cell index: Int) {
        cell(index).tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5))
        XCTAssertTrue(element("photoDetailImage").waitForExistence(timeout: 5))
    }

    private var title: String { element("photoDetailTitle").label }

    private func waitForTitle(containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element("photoDetailTitle"))
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "title was \(title)", file: file, line: line)
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

    /// 1: the newest photo opens as 第 10 天 with its own date and time.
    func testNewestPhotoShowsDayAndDate() {
        launchWall()
        openViewer(cell: 4)
        waitForTitle(containing: "第 10 天")
        let date = NSPredicate(format: "label MATCHES %@", ".*2026/1/10 [0-9]{2}:[0-9]{2}.*")
        XCTAssertTrue(date.evaluate(with: element("photoDetailTitle")), "1 \(title)")
        XCTAssertFalse(app.staticTexts["疊字只是預覽，照片本身沒有改動"].exists, "2 the caption is gone")
        XCTAssertFalse(element("photoDetailCaption").exists)
    }

    /// 1: 文字樣式 on the left, 匯出 on the right, both enabled for a dated
    /// photo; no tip without `-UITestShowTips` (10).
    func testBottomButtonsAndNoTipsByDefault() {
        launchWall(mixedAspects: true)
        openViewer(cell: 4)
        let style = element("styleButton")
        let export = element("exportButton")
        XCTAssertTrue(style.waitForExistence(timeout: 5))
        XCTAssertTrue(export.exists)
        XCTAssertTrue(style.isEnabled)
        XCTAssertTrue(export.isEnabled)
        XCTAssertLessThan(style.frame.midX, export.frame.midX, "文字樣式 left of 匯出")
        XCTAssertTrue(app.frame.contains(style.frame) && app.frame.contains(export.frame))
        XCTAssertTrue(style.label.contains("文字樣式"), style.label)
        XCTAssertFalse(element("viewerCoach").exists, "10 no coach without -UITestShowTips")
        XCTAssertFalse(element("exportIntroSheet").exists, "10 no comparison without -UITestShowTips")
        shot("photo-detail-buttons")
    }

    /// 9: the first visit shows the bubble around the overlay; 知道了 closes
    /// it for good, even in a new viewer.
    func testCoachShowsOnceUntilAcknowledged() {
        launchWall(mixedAspects: true, showTips: true)
        openViewer(cell: 4)
        let coach = element("viewerCoach")
        XCTAssertTrue(coach.waitForExistence(timeout: 5), "9 the bubble")
        XCTAssertTrue(app.staticTexts["這是 DaysCam 加上的天數"].exists)
        XCTAssertTrue(app.staticTexts["照片本身不會改；按「匯出」才會另存一張印上這行字的新照片。想換字型、顏色或位置，按「文字樣式」。"].exists)
        XCTAssertTrue(app.frame.contains(coach.frame), "bubble in view: \(coach.frame)")
        shot("photo-detail-coach")
        app.buttons["viewerCoachOkButton"].tap()
        XCTAssertFalse(coach.waitForExistence(timeout: 1))
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(cell(3).waitForExistence(timeout: 5))
        openViewer(cell: 3)
        waitForTitle(containing: "第 9 天")
        XCTAssertFalse(element("viewerCoach").waitForExistence(timeout: 2), "9 never again")
    }

    /// 12: ⋯ has one item, 刪除…, which asks remove-or-delete with the record's name.
    func testMoreMenuOpensTheRemoveOrDeleteDialog() {
        launchWall()
        openViewer(cell: 4)
        openRemoveOrDeleteDialog()
        XCTAssertTrue(app.staticTexts["要從「我的紀錄」移除這張照片，還是從「照片」App 刪除？"].exists)
        XCTAssertTrue(app.buttons["從「我的紀錄」移除"].exists)
        XCTAssertTrue(app.buttons["刪除照片"].exists)
        XCTAssertTrue(app.buttons["取消"].exists)
        shot("photo-detail-remove-or-delete")
        app.buttons["取消"].tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5))
        XCTAssertTrue(element("photoDetailImage").exists, "cancel changes nothing")
    }

    private func openRemoveOrDeleteDialog() {
        element("photoDetailMoreButton").tap()
        let item = app.buttons["刪除…"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 5))
    }

    /// 5: swiping left goes to the next, newer photo, the wall's order.
    func testSwipingFollowsTheWallOrder() {
        launchWall()
        openViewer(cell: 0)
        waitForTitle(containing: "第 6 天")
        element("photoDetail").swipeLeft()
        waitForTitle(containing: "第 7 天")
        element("photoDetail").swipeLeft()
        waitForTitle(containing: "第 8 天")
        element("photoDetail").swipeRight()
        waitForTitle(containing: "第 7 天")
    }

    /// Removing the last photo from the record returns to a wall without it.
    func testRemovingTheLastPhotoReturnsToTheWall() {
        launchWall()
        openViewer(cell: 4)
        openRemoveOrDeleteDialog()
        app.buttons["從「我的紀錄」移除"].tap()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 5))
        XCTAssertFalse(element("photoDetail").exists)
        XCTAssertFalse(cell(4).exists)
        XCTAssertTrue(cell(3).exists)
    }

    /// 8: a portrait and a landscape photo, for the B′ comparison with D-7.
    func testScreenshotsPortraitAndLandscape() {
        launchWall(mixedAspects: true)
        openViewer(cell: 4)
        waitForTitle(containing: "第 10 天")
        let image = element("photoDetailImage")
        XCTAssertTrue(image.frame.height > image.frame.width, "portrait photo")
        XCTAssertTrue(app.frame.contains(image.frame))
        shot("photo-detail-portrait")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(cell(3).waitForExistence(timeout: 5))
        openViewer(cell: 3)
        waitForTitle(containing: "第 9 天")
        let landscape = element("photoDetailImage")
        XCTAssertTrue(landscape.frame.width > landscape.frame.height, "landscape photo")
        XCTAssertTrue(app.frame.contains(landscape.frame))
        shot("photo-detail-landscape")
    }
}
