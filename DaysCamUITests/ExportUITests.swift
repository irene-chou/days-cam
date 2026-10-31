import XCTest

/// #620: the export page (acceptance 6, 8, 11). Launched with
/// `-UITestOpenExport`, the app opens the newest of five photos straight on
/// its export page. With `DAYSCAM_UI_SHOT_DIR` in the test runner's
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
    private func launch(opensExport: Bool = true, portrait: Bool = false) {
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
        if opensExport { app.launchArguments.append("-UITestOpenExport") }
        // The newest photo is then 3:4 portrait, as on D-7 screen 4.
        if portrait { app.launchArguments.append("-UITestMixedAspects") }
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
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR643_\(name)_\(device).png"))
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
        XCTAssertTrue(title.label.contains("編輯文字樣式"), title.label)
        XCTAssertTrue(title.label.contains("第 10 天"), title.label)
        let preview = element("exportPreview")
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(draggableText.waitForExistence(timeout: 5), "the overlay is drawn and draggable")
        XCTAssertTrue(preview.frame.contains(draggableText.frame), "the overlay sits on the preview")
        XCTAssertEqual(preview.frame.width / app.frame.width, 0.52, accuracy: 0.02, "about 52% of the width")
        XCTAssertEqual(preview.frame.height / preview.frame.width, 4.0 / 3.0, accuracy: 0.03, "the photo's 3:4")
        XCTAssertTrue(app.staticTexts["存成新照片到「最近項目」，原圖不動"].exists)
        XCTAssertTrue(element("exportConfirmButton").isEnabled)
        XCTAssertEqual(element("exportConfirmButton").label, "匯出", "2 the top right is the 匯出 text button")
        XCTAssertFalse(app.buttons["panelCollapseButton"].exists, "the panel stays open here")

        // 樣式, after the open-time dashed frame (#599) has faded.
        XCTAssertTrue(app.buttons["樣式"].isSelected)
        Thread.sleep(forTimeInterval: 2)
        assertOnScreen(preview, "preview in view")
        assertOnScreen(element("exportConfirmButton"), "匯出 in view")
        assertOnScreen(app.buttons["內容"], "segmented row in view")
        shot("style")

        app.buttons["內容"].tap()
        XCTAssertTrue(app.buttons["內容"].isSelected)
        Thread.sleep(forTimeInterval: 1)
        assertOnScreen(preview, "preview in view")
        assertOnScreen(app.staticTexts["存成新照片到「最近項目」，原圖不動"], "note in view")
        shot("content")
    }

    /// 6: the 匯出 button exports and the viewer is back, with no error alert.
    /// The 0.9-second toast is shorter than XCUITest's ~1s polling, so its
    /// text and the announcement are checked by `ExportModelTests` instead.
    func testExportReturnsToViewer() {
        launch()
        let confirm = element("exportConfirmButton")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5), "back on the viewer")
        XCTAssertFalse(app.alerts["無法匯出"].exists, "no failure")
        let gone = NSPredicate(format: "exists == false")
        let closed = XCTNSPredicateExpectation(predicate: gone, object: element("exportView"))
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "the export page closed")
        XCTAssertTrue(element("exportButton").isEnabled)
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

        // xmark does not roll back (FR-19.4); reopened, the text is still there.
        element("exportCancelButton").tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5))
        let exportButton = element("exportButton")
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()
        XCTAssertTrue(element("exportView").waitForExistence(timeout: 5))
        XCTAssertTrue(draggableText.waitForExistence(timeout: 5))
        XCTAssertEqual(draggableText.frame.midX, moved.midX, accuracy: 3, "position kept")
        XCTAssertEqual(draggableText.frame.midY, moved.midY, accuracy: 3, "position kept")
    }

    /// FR-18.5: the viewer's 編輯文字樣式 button opens the page of the photo on screen,
    /// and `xmark` closes it.
    func testViewerExportButtonOpensThePage() {
        launch(opensExport: false)
        let cell = app.descendants(matching: .any).matching(identifier: "photoCell").element(boundBy: 3)
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        let exportButton = element("exportButton")
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertTrue(exportButton.isEnabled)
        XCTAssertTrue(exportButton.label.contains("編輯文字樣式"), "1 \(exportButton.label)")
        assertOnScreen(exportButton, "1 button in view")
        shot("viewer")
        exportButton.tap()
        let title = element("exportTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("第 9 天"), title.label)
        element("exportCancelButton").tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5))
    }
    // MARK: - Panel scrolling (116.5, 116.8 from the camera's panel, #621)

    /// 116.5: dragging down on the font list scrolls it and leaves the page
    /// and the panel as they were.
    func testSwipeDownOnTheFontListKeepsThePanel() {
        launch()
        app.buttons["樣式"].tap()
        app.buttons["字型"].tap()
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.swipeUp()
        list.swipeDown()
        list.swipeDown()
        XCTAssertTrue(element("exportView").exists, "116.5 still on the export page")
        XCTAssertTrue(app.buttons["樣式"].exists, "116.5 the panel is still there")
    }

    /// 116.8: scrolled all the way down, the font list's last row ends above
    /// the note under the panel and can be tapped.
    func testFontListLastRowScrollsAboveTheNote() {
        launch()
        app.buttons["樣式"].tap()
        app.buttons["字型"].tap()
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        let rows = list.buttons.allElementsBoundByIndex
        XCTAssertFalse(rows.isEmpty, "116.8 the font list has rows")
        guard let last = rows.last else { return }
        let note = app.staticTexts["存成新照片到「最近項目」，原圖不動"]
        XCTAssertTrue(note.exists)
        let bottom = note.frame.minY
        let top = app.buttons["樣式"].frame.maxY + 70
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<10 {
            let from = origin.withOffset(CGVector(dx: app.frame.midX, dy: bottom - 20))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: top - (bottom - 20))),
                       withVelocity: .fast, thenHoldForDuration: 0.2)
        }
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertLessThanOrEqual(last.frame.maxY, bottom + 1,
                                 "116.8 the last row ends above the note — last \(last.frame) note \(bottom)")
        last.tap()
        XCTAssertTrue(element("exportView").exists, "116.8 the last row can be operated without leaving the page")
        XCTAssertTrue(app.buttons["樣式"].exists)
    }
}
