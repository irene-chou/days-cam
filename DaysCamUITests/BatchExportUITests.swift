import XCTest

/// #650／#679: the batch export sheet (acceptance 1, 4, 6, 14; #679-8). With
/// `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′ screenshots
/// are also written there for the PR.
final class BatchExportUITests: XCTestCase {
    /// 44pt rows; the sheet reports its frames about 4% smaller (a sheet scale in the simulator).
    private static let minTapHeight: CGFloat = 42

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record starting 2026-01-01, then launches on 2026-01-10 with
    /// `photos` generated photos in the record's album and opens the record.
    private func launchWall(photos: Int, arguments: [String] = []) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
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

    private func waitForLabel(_ identifier: String, containing text: String, timeout: TimeInterval = 5,
                              file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "\(identifier) has \(text), was \(target.label)", file: file, line: line)
    }

    /// Ticks every photo and presses 匯出.
    private func openPreviewOfAll() {
        let photo = app.descendants(matching: .any).matching(identifier: "photoCell").firstMatch
        XCTAssertTrue(element("wallSelectButton").waitForExistence(timeout: 10))
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        element("wallSelectButton").tap()
        XCTAssertTrue(element("wallSelectAllButton").waitForExistence(timeout: 5))
        element("wallSelectAllButton").tap()
        element("wallExportButton").tap()
        XCTAssertTrue(element("batchExportSheet").waitForExistence(timeout: 5))
    }

    /// 1, 4, 14: five ticked with one 日期不明: 匯出 4 張新照片 and the skip
    /// line; the carousel steps; 調整文字樣式 opens the style page whose
    /// checkmark comes back to the sheet; 取消 keeps the selection.
    func testPreviewStepsThroughPhotosAndRoundTripsTheStylePage() {
        launchWall(photos: 5, arguments: ["-UITestUndatedPhotos", "1"])
        openPreviewOfAll()

        waitForLabel("batchExportTitle", containing: "匯出 4 張新照片")
        XCTAssertTrue(app.staticTexts["原圖不動，每張另存一張印上天數的新照片到「最近項目」。"].exists, "1")
        XCTAssertEqual(element("batchExportSkipped").label, "其中 1 張日期不明，無法標天數，會略過。", "2")
        XCTAssertEqual(element("batchExportPosition").label, "1／4")
        waitForLabel("batchExportPreview", containing: "第 7 天")
        element("batchExportNext").tap()
        waitForLabel("batchExportPosition", containing: "2／4")
        waitForLabel("batchExportPreview", containing: "第 8 天")
        XCTAssertTrue(element("batchExportStartButton").label.contains("匯出 4 張"))
        let hide = element("exportHideTextButton")
        XCTAssertEqual(hide.label, "隱藏文字", "#679-8 the sheet opens showing the text")
        XCTAssertLessThan(hide.frame.midY, element("batchExportStyleLink").frame.midY)
        let style = element("batchExportStyleLink")
        XCTAssertGreaterThanOrEqual(hide.frame.height, Self.minTapHeight, "#698-1 隱藏文字 hit area")
        XCTAssertGreaterThanOrEqual(style.frame.height, Self.minTapHeight, "#698-1 調整文字樣式 hit area")
        XCTAssertLessThanOrEqual(hide.frame.maxY, style.frame.minY + 0.5, "#698-1 no overlap")
        sleep(1)
        // #679: the whole preview fits, on an iPhone SE too.
        let sheet = element("batchExportSheet").frame
        for id in ["batchExportTitle", "exportHideTextButton", "batchExportStyleLink", "batchExportStartButton", "batchExportCancelButton"] {
            XCTAssertTrue(sheet.contains(element(id).frame), "\(id) \(element(id).frame) in \(sheet)")
        }
        XCTAssertGreaterThan(element("batchExportTitle").frame.minY, sheet.minY + 10, "below the grabber")
        shot("batch-export-preview")

        // #679-8: 隱藏文字 on the batch sheet too.
        hide.tap()
        waitForLabel("exportHideTextButton", containing: "顯示文字")
        XCTAssertFalse(element("batchExportStyleLink").isEnabled)
        XCTAssertFalse(element("batchExportPreview").label.contains("第"), element("batchExportPreview").label)
        XCTAssertTrue(element("batchExportStartButton").label.contains("匯出 4 張"), "the count is unchanged")
        sleep(1)
        shot("batch-export-hidden")
        hide.tap()
        waitForLabel("exportHideTextButton", containing: "隱藏文字")
        waitForLabel("batchExportPreview", containing: "第 8 天")

        element("batchExportStyleLink").tap()
        XCTAssertTrue(element("exportView").waitForExistence(timeout: 5), "4")
        element("stylePanelDoneButton").tap()
        XCTAssertTrue(element("batchExportSheet").waitForExistence(timeout: 5), "4 back on the sheet")
        waitForLabel("batchExportTitle", containing: "匯出 4 張新照片")

        element("batchExportCancelButton").tap()
        XCTAssertFalse(element("batchExportSheet").waitForExistence(timeout: 2), "3")
        waitForLabel("wallTitle", containing: "已選 5 張")
    }

    /// 6, 9, 14: 匯出中 counts up and cannot be swiped away; with the 2nd
    /// and 4th saves failing, the sheet reads 已匯出 3 張，2 張失敗 and 好
    /// leaves just those two ticked.
    func testProgressThenPartialFailureKeepsTheFailedTicked() {
        launchWall(photos: 5, arguments: ["-UITestExportDelay", "2.5", "-UITestExportFailures", "2,4"])
        openPreviewOfAll()
        element("batchExportStartButton").tap()

        XCTAssertTrue(element("batchExportProgressTitle").waitForExistence(timeout: 5), "6")
        // The text is redrawn per photo; wait for it to be there before reading it.
        XCTAssertTrue(element("batchExportProgressText").waitForExistence(timeout: 5), "6")
        XCTAssertTrue(element("batchExportProgressText").label.contains("／5"), element("batchExportProgressText").label)
        XCTAssertTrue(element("batchExportStopButton").exists)
        shot("batch-export-progress")
        element("batchExportProgressTitle").swipeDown()
        XCTAssertTrue(element("batchExportProgressTitle").exists, "6 cannot be swiped away")

        waitForLabel("batchExportFailureTitle", containing: "已匯出 3 張，2 張失敗", timeout: 30)
        XCTAssertEqual(element("batchExportFailureMessage").label, "失敗的照片可能還在從 iCloud 下載，或儲存空間不足。")
        XCTAssertTrue(element("batchExportRetryButton").exists)
        shot("batch-export-failed")

        element("batchExportDoneButton").tap()
        XCTAssertFalse(element("batchExportSheet").waitForExistence(timeout: 2))
        waitForLabel("wallTitle", containing: "已選 2 張")
        XCTAssertFalse(element("wallToast").exists, "9 no success toast")
    }

    /// #718-8: a record whose 疊字 is off reads as 隱藏文字 already on and cannot
    /// be tapped, while 調整文字樣式 stays up to turn it back on.
    func testRecordWithOverlayOffShowsHideTextOnAndLocked() {
        launchWall(photos: 5)
        openPreviewOfAll()
        let hide = element("exportHideTextButton")
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        XCTAssertEqual(hide.label, "隱藏文字")
        XCTAssertTrue(hide.isEnabled)

        element("batchExportStyleLink").tap()
        XCTAssertTrue(element("exportView").waitForExistence(timeout: 5))
        let toggle = app.switches["layerToggleOverlay"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        element("stylePanelDoneButton").tap()
        XCTAssertTrue(element("batchExportSheet").waitForExistence(timeout: 5), "back on the sheet")

        waitForLabel("exportHideTextButton", containing: "顯示文字")
        XCTAssertFalse(hide.isEnabled, "the record hides the text; not tappable")
        XCTAssertTrue(element("batchExportStyleLink").isEnabled, "調整文字樣式 is the way back")
        XCTAssertFalse(element("batchExportPreview").label.contains("第"), element("batchExportPreview").label)
        shot("PR718_batch_export_overlay_off")

        element("batchExportStyleLink").tap()
        XCTAssertTrue(element("exportView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["layerToggleOverlay"].waitForExistence(timeout: 5))
        app.switches["layerToggleOverlay"].tap()
        element("stylePanelDoneButton").tap()
        XCTAssertTrue(element("batchExportSheet").waitForExistence(timeout: 5))
        waitForLabel("exportHideTextButton", containing: "隱藏文字")
        XCTAssertTrue(element("exportHideTextButton").isEnabled)
    }
}
