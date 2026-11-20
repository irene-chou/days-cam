import XCTest

/// #619／#679: the photo viewer (acceptance 1, 5, 8). With `DAYSCAM_UI_SHOT_DIR` in
/// the test runner's environment the B′ screenshots are also written there.
final class PhotoDetailUITests: XCTestCase {
    /// 44pt rows; the sheet reports its frames about 4% smaller (a sheet scale in the simulator).
    private static let minTapHeight: CGFloat = 42

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record starting 2026-01-01, then launches on 2026-01-10 with
    /// five photos, one per day ending that day, and opens the record.
    private func launchWall(mixedAspects: Bool = false, filmDate: Bool = false) {
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
        if filmDate { app.launchArguments += ["-UITestFilmDate", "bottomTrailing"] }
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

    /// Frames of 疊字｜匯出｜刪除 and the toggle's value.
    private func overlayToggle() -> XCUIElement { element("photoDetailOverlayToggle") }

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

    /// #679-1: 匯出 on the left, 刪除 on the right, the wall's selection bar:
    /// same size and place as there. No ⋯, no 文字樣式.
    func testBottomBarMatchesTheWallSelectionBar() {
        launchWall(mixedAspects: true)
        element("wallSelectButton").tap()
        cell(4).tap()
        let wallExport = element("wallExportButton")
        let wallDelete = element("wallDeleteButton")
        XCTAssertTrue(wallExport.waitForExistence(timeout: 5))
        XCTAssertTrue(wallExport.isEnabled)
        let wallFrames = (wallExport.frame, wallDelete.frame)
        Thread.sleep(forTimeInterval: 0.5)
        shot("wall-selection-bar")
        element("wallCancelSelectionButton").tap()
        XCTAssertTrue(element("wallSelectButton").waitForExistence(timeout: 5))

        openViewer(cell: 4)
        let export = element("photoDetailExportButton")
        let delete = element("photoDetailDeleteButton")
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(delete.exists)
        XCTAssertTrue(export.isEnabled)
        XCTAssertTrue(delete.isEnabled)
        XCTAssertTrue(export.label.contains("匯出"), export.label)
        XCTAssertTrue(delete.label.contains("刪除"), delete.label)
        XCTAssertLessThan(export.frame.midX, delete.frame.midX, "匯出 left of 刪除")
        XCTAssertTrue(app.frame.contains(export.frame) && app.frame.contains(delete.frame))
        // #738: three equal shares now (疊字｜匯出｜刪除), the wall's two are wider.
        let toggle = element("photoDetailOverlayToggle").frame
        XCTAssertEqual(export.frame.width, wallFrames.0.width * 2 / 3, accuracy: 1.5, "a third of the bar")
        XCTAssertEqual(delete.frame.width, export.frame.width, accuracy: 1, "equal shares")
        XCTAssertEqual(toggle.width, export.frame.width, accuracy: 1, "equal shares")
        for (viewer, wall) in [(export.frame, wallFrames.0), (delete.frame, wallFrames.1)] {
            XCTAssertEqual(viewer.height, wall.height, accuracy: 1, "same height as the wall's")
            XCTAssertEqual(viewer.maxY, wall.maxY, accuracy: 1, "same place as the wall's")
        }
        XCTAssertFalse(element("photoDetailMoreButton").exists, "no ⋯")
        XCTAssertFalse(element("styleButton").exists, "no 文字樣式")
        XCTAssertFalse(element("exportButton").exists)
        shot("photo-detail-buttons")
    }

    /// #679-5: under the preview, 隱藏文字 above 調整文字樣式; 隱藏文字
    /// takes the text off the preview, reads 顯示文字 and turns
    /// 調整文字樣式 off; pressed again, all is back. Shot with the film date
    /// off, then on.
    func testHideTextOnTheExportSheet() {
        assertHideText(filmDate: false)
    }

    func testHideTextOnTheExportSheetWithFilmDate() {
        assertHideText(filmDate: true)
    }

    private func assertHideText(filmDate: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let suffix = filmDate ? "-filmdate" : ""
        launchWall(mixedAspects: true, filmDate: filmDate)
        openViewer(cell: 4)
        element("photoDetailExportButton").tap()
        XCTAssertTrue(element("batchExportSheet").waitForExistence(timeout: 5), file: file, line: line)
        let hide = element("exportHideTextButton")
        let style = element("batchExportStyleLink")
        let preview = element("batchExportPreview")
        XCTAssertTrue(hide.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(hide.label, "隱藏文字", file: file, line: line)
        XCTAssertLessThan(hide.frame.midY, style.frame.midY, "隱藏文字 above 調整文字樣式", file: file, line: line)
        XCTAssertEqual(hide.frame.midX, style.frame.midX, accuracy: 1, "both centered", file: file, line: line)
        XCTAssertGreaterThanOrEqual(hide.frame.height, Self.minTapHeight, "#698-1", file: file, line: line)
        XCTAssertGreaterThanOrEqual(style.frame.height, Self.minTapHeight, "#698-1", file: file, line: line)
        XCTAssertLessThanOrEqual(hide.frame.maxY, style.frame.minY + 0.5, "#698-1 no overlap", file: file, line: line)
        XCTAssertTrue(app.frame.contains(hide.frame) && app.frame.contains(style.frame), "#698-2 in view",
                      file: file, line: line)
        XCTAssertTrue(style.isEnabled, file: file, line: line)
        waitForLabel(preview, containing: "第 10 天", file: file, line: line)
        XCTAssertTrue(app.frame.contains(element("batchExportStartButton").frame), "匯出 in view",
                      file: file, line: line)
        XCTAssertTrue(app.frame.contains(element("batchExportCancelButton").frame), "取消 in view",
                      file: file, line: line)
        Thread.sleep(forTimeInterval: 1)
        shot("export-single-shown\(suffix)")

        hide.tap()
        waitForLabel(hide, containing: "顯示文字", file: file, line: line)
        XCTAssertFalse(style.isEnabled, "調整文字樣式 is off", file: file, line: line)
        XCTAssertFalse(preview.label.contains("第"), "no text on the preview: \(preview.label)", file: file, line: line)
        Thread.sleep(forTimeInterval: 1)
        shot("export-single-hidden\(suffix)")

        hide.tap()
        waitForLabel(hide, containing: "隱藏文字", file: file, line: line)
        XCTAssertTrue(style.isEnabled, file: file, line: line)
        waitForLabel(preview, containing: "第 10 天", file: file, line: line)
    }

    private func waitForLabel(_ target: XCUIElement, containing text: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: target)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "label was \(target.label)", file: file, line: line)
    }

    /// #699-2, #699-3: the top bar still reads 第 N 天, and no pointer bubble
    /// appears.
    func testNoCoachAndHeaderStillShowsDay() {
        launchWall(mixedAspects: true)
        openViewer(cell: 4)
        waitForTitle(containing: "第 10 天")
        XCTAssertTrue(element("photoDetailImage").waitForExistence(timeout: 5))
        XCTAssertFalse(element("viewerCoach").waitForExistence(timeout: 2), "3 no bubble")
        XCTAssertFalse(app.buttons["viewerCoachOkButton"].exists, "3 no 知道了")
        shot("photo-detail-plain")
    }

    /// #679-2: 刪除 asks remove-or-delete with the record's name.
    func testDeleteOpensTheRemoveOrDeleteDialog() {
        launchWall()
        openViewer(cell: 4)
        openRemoveOrDeleteDialog()
        XCTAssertTrue(app.staticTexts["要從「我的相簿」移除這張照片，還是從「照片」App 刪除？"].exists)
        XCTAssertTrue(app.buttons["從「我的相簿」移除"].exists)
        XCTAssertTrue(app.buttons["刪除照片"].exists)
        shot("photo-detail-remove-or-delete")
        if app.buttons["取消"].exists { app.buttons["取消"].tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5))
        XCTAssertTrue(element("photoDetailImage").exists, "cancel changes nothing")
    }

    private func openRemoveOrDeleteDialog() {
        element("photoDetailDeleteButton").tap()
        XCTAssertTrue(app.buttons["刪除照片"].waitForExistence(timeout: 5))
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
        app.buttons.matching(identifier: "removeFromRecordButton").firstMatch.tap()
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

    /// #738-1, 6: the bar reads 疊字｜匯出｜刪除 left to right, and the toggle's
    /// value flips 關 → 開 → 關 with taps.
    func testOverlayToggleSitsFirstAndFlips() {
        launchWall()
        openViewer(cell: 4)
        let toggle = overlayToggle()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let export = element("photoDetailExportButton").frame
        let delete = element("photoDetailDeleteButton").frame
        XCTAssertTrue(toggle.frame.maxX <= export.minX + 1 && export.maxX <= delete.minX + 1,
                      "1 toggle \(toggle.frame) export \(export) delete \(delete)")
        XCTAssertGreaterThan(toggle.frame.width, 0, "1 visible \(toggle.frame)")
        XCTAssertEqual(toggle.value as? String, "關", "6 starts off")
        shot("pr738-overlay-off")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "開", "6 on")
        XCTAssertTrue(element("photoDetailImage").waitForExistence(timeout: 5))
        sleep(1)
        shot("pr738-overlay-on")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "關", "6 off again")
    }

    /// #738-5: leaving the viewer and coming back keeps the toggle on.
    func testOverlayToggleSurvivesLeavingTheViewer() {
        launchWall()
        openViewer(cell: 4)
        overlayToggle().tap()
        XCTAssertEqual(overlayToggle().value as? String, "開")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(cell(4).waitForExistence(timeout: 5))
        openViewer(cell: 3)
        XCTAssertEqual(overlayToggle().value as? String, "開", "5 kept after reopening")
    }

    /// #738-8: the bar on a small phone, nothing cut.
    func testOverlayBarOnSmallPhone() {
        launchWall()
        openViewer(cell: 4)
        XCTAssertTrue(overlayToggle().waitForExistence(timeout: 5))
        shot("pr738-bar")
    }
}
