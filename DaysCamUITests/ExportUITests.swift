import XCTest

/// #620／#647／#679: the 文字樣式 page and the viewer's 匯出. Launched with
/// `-UITestOpenExport`, the app opens the newest of five photos straight on
/// its 文字樣式 page (formerly the export page). With `DAYSCAM_UI_SHOT_DIR` in the test runner's
/// environment the B′ screenshots are also written there.
final class ExportUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record starting 2026-01-01, then launches on 2026-01-10 with
    /// five photos, one per day ending that day; with `opensExport` the newest
    /// one's export page is up at launch.
    private func launch(opensExport: Bool = true, portrait: Bool = false, showTips: Bool = false) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "5", "-UITestBindAlbum", "-UITestLongToast"]
        if opensExport { app.launchArguments.append("-UITestOpenExport") }
        // The newest photo is then 3:4 portrait, as on D-7 screen 4.
        if portrait { app.launchArguments.append("-UITestMixedAspects") }
        if showTips { app.launchArguments.append("-UITestShowTips") }
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
        if opensExport {
            XCTAssertTrue(element("exportView").waitForExistence(timeout: 10), "-UITestOpenExport opened the page")
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var draggableText: XCUIElement { element("overlayTextDraggable") }

    private func shot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["DAYSCAM_UI_SHOT_DIR"], !path.isEmpty {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let device = UIDevice.current.name.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR647_\(name)_\(device).png"))
        }
    }

    /// Asserts `item` is wholly on screen.
    private func assertOnScreen(_ item: XCUIElement, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.exists, message, file: file, line: line)
        XCTAssertTrue(app.frame.contains(item.frame), "\(message): \(item.frame) in \(app.frame)", file: file, line: line)
    }

    /// 11: the page's parts are where D-7 screen 4 has them, on 樣式 and 內容.
    func testLayoutMatchesTheDesign() {
        launch(portrait: true)
        let title = element("exportTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("文字樣式"), title.label)
        XCTAssertTrue(title.label.contains("套用到所有照片"), title.label)
        let preview = element("exportPreview")
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(draggableText.waitForExistence(timeout: 5), "the overlay is drawn and draggable")
        XCTAssertTrue(preview.frame.contains(draggableText.frame), "the overlay sits on the preview")
        XCTAssertEqual(preview.frame.width / app.frame.width, 0.52, accuracy: 0.02, "about 52% of the width")
        XCTAssertEqual(preview.frame.height / preview.frame.width, 4.0 / 3.0, accuracy: 0.03, "the photo's 3:4")
        XCTAssertTrue(app.staticTexts["改動直接存到這個紀錄，回檢視頁再匯出"].exists)
        XCTAssertTrue(element("exportConfirmButton").isEnabled)
        XCTAssertFalse(app.buttons["panelCollapseButton"].exists, "the panel stays open here")

        // 樣式, after the open-time dashed frame (#599) has faded.
        XCTAssertTrue(app.buttons["樣式"].isSelected)
        Thread.sleep(forTimeInterval: 2)
        assertOnScreen(preview, "preview in view")
        assertOnScreen(element("exportConfirmButton"), "checkmark in view")
        assertOnScreen(app.buttons["內容"], "segmented row in view")
        shot("style")

        app.buttons["內容"].tap()
        XCTAssertTrue(app.buttons["內容"].isSelected)
        Thread.sleep(forTimeInterval: 1)
        assertOnScreen(preview, "preview in view")
        assertOnScreen(app.staticTexts["改動直接存到這個紀錄，回檢視頁再匯出"], "note in view")
        shot("content")
    }

    /// 11: the checkmark is done: the viewer is back, nothing was exported
    /// (no toast, no alert).
    func testCheckmarkReturnsToViewerWithoutExporting() {
        launch()
        let confirm = element("exportConfirmButton")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5), "back on the viewer")
        XCTAssertFalse(app.alerts["無法匯出"].exists, "no failure")
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTNSPredicateExpectation(predicate: gone, object: element("exportView"))
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "the style page closed")
        XCTAssertFalse(element("exportToast").exists, "nothing was exported")
        XCTAssertTrue(element("photoDetailExportButton").isEnabled)
    }

    /// #679-3, 4: 匯出 opens the export sheet for this one photo; its 匯出
    /// closes it, toasts 已匯出 and stays on the same photo.
    func testViewerExportStaysOnThePhoto() {
        launch(opensExport: false)
        let cell = app.descendants(matching: .any).matching(identifier: "photoCell").element(boundBy: 3)
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5))
        let exportButton = element("photoDetailExportButton")
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()
        XCTAssertTrue(element("batchExportSheet").waitForExistence(timeout: 5), "3 the export sheet")
        XCTAssertEqual(element("batchExportTitle").label, "匯出這張照片")
        XCTAssertTrue(app.staticTexts["另存一張新照片，原圖不動。"].exists)
        XCTAssertFalse(element("batchExportPosition").exists, "3 no ‹ i／M ›")
        XCTAssertFalse(element("batchExportPrevious").exists)
        XCTAssertFalse(element("batchExportNext").exists)
        let start = element("batchExportStartButton")
        XCTAssertEqual(start.label, "匯出")
        start.tap()
        XCTAssertTrue(toastAppears(), "4 已匯出 toast")
        XCTAssertTrue(app.staticTexts["已匯出"].exists)
        XCTAssertFalse(element("batchExportSheet").exists, "4 the sheet closed")
        XCTAssertFalse(element("exportView").exists, "no page change")
        XCTAssertTrue(element("photoDetailTitle").label.contains("第 9 天"), element("photoDetailTitle").label)
    }

    /// #679-10: even on a first run, 匯出 goes straight to the export sheet;
    /// the old comparison sheet is gone.
    func testFirstExportHasNoComparison() {
        launch(opensExport: false, portrait: true, showTips: true)
        openNewestViewer()
        dismissCoachIfShown()
        element("photoDetailExportButton").tap()
        XCTAssertTrue(element("batchExportSheet").waitForExistence(timeout: 5))
        XCTAssertFalse(element("exportIntroSheet").exists)
        XCTAssertFalse(app.staticTexts["匯出會另存一張新照片"].exists)
        element("batchExportStartButton").tap()
        XCTAssertTrue(toastAppears(), "it exported")
    }

    private func openNewestViewer() {
        let cell = app.descendants(matching: .any).matching(identifier: "photoCell").element(boundBy: 4)
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5))
        XCTAssertTrue(element("photoDetailImage").waitForExistence(timeout: 5))
    }

    private func dismissCoachIfShown() {
        let ok = app.buttons["viewerCoachOkButton"]
        // Every caller launches with -UITestShowTips, so the bubble always comes
        // once the image has loaded; a short wait let slow CI tap 匯出 under it.
        if ok.waitForExistence(timeout: 10) {
            ok.tap()
            waitUntilGone(ok)
        }
    }

    /// The 已匯出 toast stays only 1.6 s, shorter than a `waitForExistence` poll
    /// interval plus the idle wait after a tap, so that call can miss it. Poll
    /// `exists` back to back instead; a slow export still has the full timeout.
    private func toastAppears(timeout: TimeInterval = 20) -> Bool {
        let toast = element("exportToast")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if toast.exists { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return false
    }

    private func waitUntilGone(_ item: XCUIElement, timeout: TimeInterval = 8,
                               file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "still there", file: file, line: line)
    }

    /// 8: dragging the text on the preview moves it there, and the record keeps
    /// it: a reopened page shows the text where it was left.
    func testDragOnPreviewMovesAndKeepsThePosition() {
        launch()
        XCTAssertTrue(draggableText.waitForExistence(timeout: 5))
        let preview = element("exportPreview").frame
        let before = draggableText.frame
        let start = draggableText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1,
                    thenDragTo: start.withOffset(CGVector(dx: -preview.width * 0.3, dy: -preview.height * 0.4)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        let moved = draggableText.frame
        XCTAssertLessThan(moved.midX, before.midX - 15, "followed the finger")
        XCTAssertLessThan(moved.midY, before.midY - 15, "followed the finger")

        // xmark does not roll back (FR-19.4); reopened from the export sheet,
        // the text is still there.
        element("exportCancelButton").tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5))
        openStylePageFromTheExportSheet()
        XCTAssertTrue(draggableText.waitForExistence(timeout: 5))
        XCTAssertEqual(draggableText.frame.midX, moved.midX, accuracy: 3, "position kept")
        XCTAssertEqual(draggableText.frame.midY, moved.midY, accuracy: 3, "position kept")
    }

    /// Opens the viewer's export sheet, then its 調整文字樣式.
    private func openStylePageFromTheExportSheet() {
        let exportButton = element("photoDetailExportButton")
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()
        XCTAssertTrue(element("batchExportSheet").waitForExistence(timeout: 5))
        let link = element("batchExportStyleLink")
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.isEnabled)
        link.tap()
        XCTAssertTrue(element("exportView").waitForExistence(timeout: 5))
    }

    /// #679: the viewer has no 文字樣式 button; the page opens from the
    /// export sheet's 調整文字樣式, and `xmark` comes back to the sheet.
    func testStylePageOpensFromTheExportSheet() {
        launch(opensExport: false)
        let cell = app.descendants(matching: .any).matching(identifier: "photoCell").element(boundBy: 3)
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5))
        XCTAssertFalse(element("styleButton").exists)
        openStylePageFromTheExportSheet()
        let title = element("exportTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("文字樣式"), title.label)
        element("exportCancelButton").tap()
        XCTAssertTrue(element("batchExportSheet").waitForExistence(timeout: 5), "back on the sheet")
    }

    // MARK: - Panel scrolling (116.5, 116.8 from the camera's panel, #621)

    /// 116.5: dragging down on the style page scrolls it and leaves the page
    /// and the panel as they were (the font list left the panel in #678).
    func testSwipeDownOnTheStylePageKeepsThePanel() {
        launch()
        app.buttons["樣式"].tap()
        XCTAssertTrue(app.buttons["stylePreset_classic"].waitForExistence(timeout: 3))
        let page = app.scrollViews.containing(.button, identifier: "boxStateButton").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        page.swipeUp()
        page.swipeDown()
        page.swipeDown()
        XCTAssertTrue(element("exportView").exists, "116.5 still on the export page")
        XCTAssertTrue(app.buttons["樣式"].exists, "116.5 the panel is still there")
    }

    /// 116.8: scrolled all the way down, the style page's last control (the
    /// size slider) ends above the note under the panel and can be used.
    func testStylePageLastRowScrollsAboveTheNote() {
        launch()
        app.buttons["樣式"].tap()
        let last = app.sliders["字級"]
        XCTAssertTrue(last.waitForExistence(timeout: 3), "116.8 the page has the size slider")
        let note = app.staticTexts["改動直接存到這個紀錄，回檢視頁再匯出"]
        XCTAssertTrue(note.exists)
        let bottom = note.frame.minY
        let top = app.buttons["樣式"].frame.maxY + 70
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<4 {
            let from = origin.withOffset(CGVector(dx: 8, dy: bottom - 20))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: top - (bottom - 20))),
                       withVelocity: .fast, thenHoldForDuration: 0.2)
        }
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertLessThanOrEqual(last.frame.maxY, bottom + 1,
                                 "116.8 the last row ends above the note — last \(last.frame) note \(bottom)")
        last.doubleTap()
        XCTAssertTrue(element("exportView").exists, "116.8 the last row can be operated without leaving the page")
        XCTAssertTrue(app.buttons["樣式"].exists)
    }
}
