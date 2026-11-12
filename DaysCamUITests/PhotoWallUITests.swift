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
        XCTAssertFalse(element("comparisonBannerOpen").exists, "#725-1 four days apart, no card")
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
        XCTAssertTrue(app.staticTexts["用相機拍一張，或在「照片」App 把照片加入「我的紀錄」相簿，會自動出現在這裡"].exists,
                      "12, #651-15")
        XCTAssertTrue(element("addPhotosButton").exists, "12")
        XCTAssertTrue(element("wallSelectButton").exists, "#648-12")
        shot("photo-wall-empty")
        element("wallSelectButton").tap()
        XCTAssertFalse(element("wallCancelSelectionButton").waitForExistence(timeout: 2), "#648-12 選取 is off")
    }

    /// The camera keeps an exit back to the wall.
    func testCameraOpensFromTheWallAndClosesBack() {
        launchWall(photos: 2)
        XCTAssertTrue(app.openCamera())
        app.buttons["cameraLatestThumbnail"].tap()
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

    /// #681-2: a slide that starts in the 2pt gap between cells still selects,
    /// from the nearest cell.
    func testSlideStartingInAGapTicks() {
        launchWall(photos: 6)
        enterSelection()
        let gap = cell(0).coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: 1, dy: 0))
        let end = cell(2).coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        gap.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        waitForTitle(containing: "已選")
        XCTAssertTrue(cell(2).label.contains("已選取"))
    }

    /// #681-5: while selecting, a vertical drag still scrolls and ticks nothing.
    func testVerticalDragScrollsWhileSelecting() {
        launchWall(photos: 60)
        enterSelection()
        let newest = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'photoDayLabel' AND label == '第 10 天'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        let before = newest.frame.minY
        let wall = element("photoWall")
        let top = wall.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let bottom = wall.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        top.press(forDuration: 0.05, thenDragTo: bottom, withVelocity: .default, thenHoldForDuration: 0.1)
        XCTAssertTrue(!newest.exists || newest.frame.minY > before + 50, "scrolled toward older photos")
        waitForTitle(containing: "選取照片")
    }

    /// 7, 8: two ticked → the dialog names 2; cancel keeps everything;
    /// 從「…」移除 removes both without asking, toasts and leaves selection.
    func testDeleteDialogThenRemoveTwo() {
        // The toast stays long enough for the wait to see it.
        launchWall(photos: 5, arguments: ["-UITestLongToast"])
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
        let remove = app.buttons.matching(identifier: "removeFromRecordButton").firstMatch
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
        let cancel = app.sheets.firstMatch.buttons["取消"]
        if cancel.exists {
            cancel.tap()
        } else {
            // A popover-style dialog has no 取消; a tap outside dismisses it.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        }
        XCTAssertFalse(app.buttons["從「我的紀錄」移除"].waitForExistence(timeout: 1))
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

    /// #680-1, 3, 9: three photos held only by the record show the notice
    /// over the wall; 加進相簿 toasts and the notice goes, the wall unchanged.
    func testAlbumSyncNoticeAddsTheFallbackPhotos() {
        launchWall(photos: 5, arguments: ["-UITestFallbackPhotos", "3", "-UITestLongToast"])
        let notice = element("wallAlbumSyncNotice")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "1")
        XCTAssertTrue(app.staticTexts["3 張照片還不在「我的紀錄」相簿"].exists, "1")
        XCTAssertTrue(app.staticTexts["開放完整權限前拍的"].exists, "1")
        let button = element("wallAlbumSyncButton")
        XCTAssertTrue(button.isHittable, "9")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(notice.frame), "9")
        shot("album-sync-notice")

        button.tap()
        let toast = element("wallToast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "3")
        XCTAssertEqual(toast.label, "已加進「我的紀錄」相簿 3 張", "3")
        shot("album-sync-done")
        XCTAssertTrue(notice.waitForNonExistence(timeout: 5), "3")
        XCTAssertEqual(dayLabels().count, 5, "#680-8")
    }

    // MARK: - #722 unit text on the wall

    private func newestDayLabel() -> XCUIElement {
        let labels = app.descendants(matching: .any).matching(identifier: "photoDayLabel")
        return labels.element(boundBy: labels.count - 1)
    }

    /// #722-5, 7: month + day record, start 2025-10-05, newest photo 2026-01-10:
    /// the cell prints the full "N 個月又 M 天" and VoiceOver reads it whole,
    /// with "，已選取" while selecting.
    func testWallPrintsMonthsAndDays() {
        launchWall(photos: 5, startDate: "2025-10-05", arguments: ["-UITestDisplayUnits", "month,day"])
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        let label = dayLabels().last ?? ""
        XCTAssertTrue(label.contains("3 個月又"), "5 \(label)")
        shot("wall-months-days")
        enterSelection()
        cell(4).tap()
        XCTAssertEqual(cell(4).label, "\(label)，已選取", "7")
        shot("wall-months-days-selecting")
    }

    /// #722-6: year, month, week, day on near day 400 steps down to a shorter text.
    func testWallShortensDayFourHundred() {
        launchWall(photos: 5, startDate: "2024-12-02",
                   arguments: ["-UITestDisplayUnits", "year,month,week,day"])
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        let label = dayLabels().last ?? ""
        XCTAssertTrue(label.hasPrefix("1 年"), "6 \(label)")
        shot("wall-day-400")
    }

    // MARK: - #725 comparison card

    /// The card starts expanded whatever an earlier test left in the app's defaults.
    private func launchComparisonWall(arguments: [String] = []) {
        launchWall(photos: 10, arguments: ["-dayscam.comparison.collapsed", "NO"] + arguments)
    }

    private var comparisonOpen: XCUIElement { element("comparisonBannerOpen") }

    /// #725-1, 2: ten photos nine days apart show 第 1 天 → 第 10 天 over the
    /// wall; selection hides the card and 取消 brings it back.
    func testComparisonCardShowsAndHidesWhileSelecting() {
        launchComparisonWall()
        XCTAssertTrue(comparisonOpen.waitForExistence(timeout: 10), "1")
        XCTAssertEqual(comparisonOpen.label, "對比圖，第 1 天 → 第 10 天，對比圖已準備好，點開預覽與匯出", "1")
        XCTAssertEqual(dayLabels().count, 10, "the card's thumbnails are not wall cells")
        XCTAssertLessThan(comparisonOpen.frame.maxY, cell(0).frame.minY, "over the wall")

        // A hidden element can still be queried by XCUITest, so check
        // behavior: while selecting, a tap where the card was opens nothing.
        let cardCenter = comparisonOpen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        enterSelection()
        cardCenter.tap()
        XCTAssertFalse(element("comparisonSheet").waitForExistence(timeout: 2), "2 hidden while selecting")
        waitForTitle(containing: "選取照片")
        element("wallCancelSelectionButton").tap()
        XCTAssertTrue(element("wallSelectButton").waitForExistence(timeout: 5))
        comparisonOpen.tap()
        XCTAssertTrue(element("comparisonSheet").waitForExistence(timeout: 5), "2 back after 取消")
    }

    /// #725-6: the left half opens the picker; choosing 第 4 天 brings it back
    /// to the preview; closing and reopening returns to 第 1 天.
    func testComparisonSwapsALeftPhotoUntilClosed() {
        launchComparisonWall()
        XCTAssertTrue(comparisonOpen.waitForExistence(timeout: 10))
        comparisonOpen.tap()
        let left = element("comparisonLeftTile")
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        XCTAssertEqual(left.label, "左邊照片，第 1 天，點兩下換照片")
        XCTAssertEqual(element("comparisonRightTile").label, "右邊照片，第 10 天，點兩下換照片")
        left.tap()

        let picker = element("comparisonPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "6")
        let fourth = picker.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'photoCell' AND label == '第 4 天'")).firstMatch
        XCTAssertTrue(fourth.waitForExistence(timeout: 5), "6")
        let current = picker.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'photoCell' AND label == '第 1 天，已選取'")).firstMatch
        XCTAssertTrue(current.exists, "6 the current photo is ticked")
        fourth.tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5), "6 back to the preview")
        let swapped = NSPredicate(format: "label == '左邊照片，第 4 天，點兩下換照片'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: swapped, object: left)], timeout: 5),
                       .completed, "6 \(left.label)")

        element("comparisonCancelButton").tap()
        XCTAssertTrue(element("comparisonSheet").waitForNonExistence(timeout: 5))
        comparisonOpen.tap()
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        XCTAssertEqual(left.label, "左邊照片，第 1 天，點兩下換照片", "6 back to the default pair")
    }

    /// #725-4 B′: expanded, the sheet, collapsed; then limited access with
    /// the notice above the card.
    func testComparisonScreens() {
        launchComparisonWall()
        let banner = comparisonOpen
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(banner.frame))
        XCTAssertTrue(cell(9).waitForExistence(timeout: 5))
        shot("comparison-expanded")

        comparisonOpen.tap()
        let preview = element("comparisonPreview")
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(element("comparisonExportButton").isHittable)
        XCTAssertTrue(element("comparisonCancelButton").isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(preview.frame))
        // The preview is composed off the main thread; wait for its spinner to go.
        XCTAssertTrue(app.activityIndicators["對比圖產生中"].waitForNonExistence(timeout: 10))
        shot("comparison-sheet")
        element("comparisonCancelButton").tap()
        XCTAssertTrue(element("comparisonSheet").waitForNonExistence(timeout: 5))

        let toggle = element("comparisonBannerToggle")
        XCTAssertEqual(toggle.label, "收合對比圖")
        toggle.tap()
        let expand = NSPredicate(format: "label == '展開對比圖'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expand, object: toggle)], timeout: 5),
                       .completed, "3")
        XCTAssertLessThanOrEqual(toggle.frame.height, 41, "collapsed to 40pt")
        shot("comparison-collapsed")
        toggle.tap()
        app.terminate()

        launchComparisonWall(arguments: ["-UITestPhotoAccess", "limited"])
        let notice = element("limitedAccessBanner")
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(notice.frame.maxY, banner.frame.minY + 1, "4 the notice above the card")
        shot("comparison-limited")
    }
}
