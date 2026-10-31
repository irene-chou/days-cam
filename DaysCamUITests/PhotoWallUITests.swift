import XCTest

/// #618: the photo wall (acceptance 1, 7, 11, 12, 13); #648: selection
/// mode (acceptance 1–3, 5, 7, 8, 11, 12, 13). With
/// `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′ screenshots
/// are also written there for the PR.
final class PhotoWallUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record starting 2026-01-01, then launches on 2026-01-10 with
    /// `photos` generated photos, one per day ending that day, all in the
    /// record's album, and opens the record.
    private func launchWall(photos: Int, startDate: String = "2026-01-01", arguments: [String] = []) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = startDate
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "\(photos)", "-UITestBindAlbum"] + arguments
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func dayLabels() -> [String] {
        let labels = app.descendants(matching: .any).matching(identifier: "photoDayLabel")
        return (0..<labels.count).map { labels.element(boundBy: $0).label }
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

    /// 1, 13: five photos run 第 6 天 … 第 10 天 oldest to newest.
    func testWallMarksEachPhotoOldestToNewest() {
        launchWall(photos: 5)
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "photoCell").element(boundBy: 4).waitForExistence(timeout: 5))
        XCTAssertEqual(dayLabels(), ["第 6 天", "第 7 天", "第 8 天", "第 9 天", "第 10 天"], "1")
        XCTAssertTrue(element("addPhotosButton").exists)
        XCTAssertEqual(app.buttons["addPhotosButton"].label, "加入照片", "1")
        XCTAssertTrue(app.buttons["wallCameraButton"].label.contains("拍照"), "1")
        shot("photo-wall")
    }

    /// 7: with more photos than fit, the wall opens on the newest.
    func testWallOpensScrolledToTheNewestPhoto() {
        launchWall(photos: 60)
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        let newest = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'photoDayLabel' AND label == '第 10 天'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5), "7")
        XCTAssertTrue(newest.isHittable || newest.frame.maxY <= app.frame.maxY, "7 the newest is on screen")
        XCTAssertFalse(dayLabels().contains("前 50 天"), "7 the oldest is scrolled away")
    }

    /// 11: the menu offers the two record actions and nothing else.
    func testMenuHasOnlyEditAndDelete() {
        launchWall(photos: 3)
        XCTAssertTrue(element("wallMoreButton").waitForExistence(timeout: 10))
        element("wallMoreButton").tap()
        XCTAssertTrue(app.buttons["編輯紀錄"].waitForExistence(timeout: 5), "11")
        XCTAssertTrue(app.buttons["刪除紀錄"].exists, "11")
        XCTAssertFalse(app.buttons["匯出"].exists)
    }

    /// 12, 13: an empty album shows the empty state and the add button.
    func testEmptyAlbumShowsTheEmptyState() {
        launchWall(photos: 0)
        XCTAssertTrue(element("wallEmptyState").waitForExistence(timeout: 10), "12")
        XCTAssertTrue(app.staticTexts["還沒有照片"].exists, "12")
        XCTAssertTrue(app.staticTexts["從相簿加入，或用相機拍一張"].exists, "12")
        XCTAssertTrue(element("addPhotosButton").exists, "12")
        XCTAssertTrue(element("wallSelectButton").exists, "#648-12")
        XCTAssertFalse(element("wallSelectButton").isEnabled, "#648-12 選取 is off")
        shot("photo-wall-empty")
    }

    /// The camera keeps an exit back to the wall.
    func testCameraOpensFromTheWallAndClosesBack() {
        launchWall(photos: 2)
        XCTAssertTrue(app.openCamera())
        app.buttons["cameraCloseButton"].tap()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 5))
    }

    // MARK: - Selection (#648)

    private func cell(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "photoCell").element(boundBy: index)
    }

    private var wallTitle: XCUIElement { element("wallTitle") }

    private func waitForTitle(containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: wallTitle)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "title has \(text), was \(wallTitle.label)", file: file, line: line)
    }

    private func enterSelection() {
        XCTAssertTrue(element("wallSelectButton").waitForExistence(timeout: 10))
        XCTAssertTrue(cell(0).waitForExistence(timeout: 5))
        element("wallSelectButton").tap()
        XCTAssertTrue(element("wallCancelSelectionButton").waitForExistence(timeout: 5))
    }

    /// 1–3: 選取 sits left of ⋯; selection shows 全選・選取照片・取消 over a
    /// disabled 匯出｜刪除; a tap ticks without opening the viewer; 全選 and
    /// 取消 work.
    func testSelectionModeTicksAndClears() {
        launchWall(photos: 5)
        XCTAssertTrue(element("wallSelectButton").waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(element("wallSelectButton").frame.maxX, element("wallMoreButton").frame.minX, "1")
        shot("photo-wall-select-button")
        enterSelection()
        XCTAssertTrue(element("wallSelectAllButton").exists, "1")
        XCTAssertEqual(element("wallSelectAllButton").label, "全選")
        waitForTitle(containing: "選取照片")
        XCTAssertFalse(element("wallMoreButton").exists, "1 no ⋯ while selecting")
        XCTAssertFalse(element("wallExportButton").isEnabled, "1")
        XCTAssertFalse(element("wallDeleteButton").isEnabled, "1")

        cell(1).tap()
        waitForTitle(containing: "已選 1 張")
        XCTAssertTrue(cell(1).label.contains("已選取"), "2 \(cell(1).label)")
        XCTAssertFalse(element("photoDetail").exists, "2 no viewer")
        cell(3).tap()
        waitForTitle(containing: "已選 2 張")
        XCTAssertTrue(element("wallExportButton").isEnabled)
        XCTAssertTrue(element("wallDeleteButton").isEnabled)
        shot("photo-wall-selecting")

        element("wallSelectAllButton").tap()
        waitForTitle(containing: "已選 5 張")
        XCTAssertEqual(element("wallSelectAllButton").label, "取消全選", "3")
        element("wallSelectAllButton").tap()
        waitForTitle(containing: "選取照片")

        cell(0).tap()
        element("wallCancelSelectionButton").tap()
        XCTAssertTrue(element("wallSelectButton").waitForExistence(timeout: 5), "3")
        XCTAssertTrue(element("wallMoreButton").exists)
        XCTAssertFalse(cell(0).label.contains("已選取"))
    }

    /// 5: sliding sideways across a row ticks the whole row.
    func testSlidingAcrossARowTicksIt() {
        launchWall(photos: 6)
        enterSelection()
        let start = cell(0).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = cell(2).coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        waitForTitle(containing: "已選 3 張")
        XCTAssertTrue(cell(0).label.contains("已選取"))
        XCTAssertTrue(cell(2).label.contains("已選取"))
        XCTAssertFalse(cell(3).label.contains("已選取"))
    }

    /// 7, 8: two ticked → the dialog names 2; cancel keeps everything;
    /// 從「…」移除 removes both without asking, toasts and leaves selection.
    func testDeleteDialogThenRemoveTwo() {
        launchWall(photos: 5)
        enterSelection()
        cell(0).tap()
        waitForTitle(containing: "已選 1 張")
        element("wallDeleteButton").tap()
        XCTAssertTrue(app.buttons["刪除照片"].waitForExistence(timeout: 5), "7 one photo")
        XCTAssertTrue(app.staticTexts["要從「我的紀錄」移除這張照片，還是從「照片」App 刪除？"].exists, "7")
        dismissDialog()

        cell(1).tap()
        waitForTitle(containing: "已選 2 張")
        element("wallDeleteButton").tap()
        XCTAssertTrue(app.buttons["刪除 2 張照片"].waitForExistence(timeout: 5), "7")
        XCTAssertTrue(app.staticTexts["要從「我的紀錄」移除這 2 張照片，還是從「照片」App 刪除？"].exists, "7")
        XCTAssertTrue(app.buttons["從「我的紀錄」移除"].exists, "7")
        shot("photo-wall-remove-or-delete")
        dismissDialog()
        waitForTitle(containing: "已選 2 張")
        XCTAssertTrue(cell(4).exists, "8 cancel changes nothing")

        element("wallDeleteButton").tap()
        let remove = app.buttons["從「我的紀錄」移除"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        let toast = element("wallToast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "8")
        XCTAssertTrue(app.staticTexts["已從紀錄移除 2 張"].exists, "8")
        XCTAssertTrue(element("wallSelectButton").waitForExistence(timeout: 5), "8 selection ended")
        XCTAssertFalse(cell(3).exists, "8 two fewer")
        XCTAssertTrue(cell(2).exists)
    }

    private func dismissDialog() {
        if app.buttons["取消"].firstMatch.exists, app.sheets.firstMatch.exists {
            app.sheets.firstMatch.buttons["取消"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        }
        XCTAssertTrue(element("wallCancelSelectionButton").waitForExistence(timeout: 5))
    }

    /// 11: under limited access the notice stays while selecting.
    func testLimitedNoticeStaysWhileSelecting() {
        launchWall(photos: 5, arguments: ["-UITestPhotoAccess", "limited"])
        XCTAssertTrue(element("limitedAccessBanner").waitForExistence(timeout: 10))
        enterSelection()
        cell(0).tap()
        waitForTitle(containing: "已選 1 張")
        XCTAssertTrue(element("limitedAccessBanner").exists, "11")
        shot("photo-wall-selecting-limited")
    }
}
