import XCTest

/// #656, #712: the style sheet opened from the text or the 文字樣式 key
/// (656-6, 656-7, 712-5), tap-to-focus next to the text (656-8) and the
/// first-run hint on the key (656-9). There is no 疊字預覽 switch any more
/// (712-6). With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the
/// B′ screenshots are also written there for the PR.
final class CameraOverlayPreviewUITests: XCTestCase {
    private var app: XCUIApplication!
    private var profiles = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record starting 2026-01-01, then launches on 2026-01-10 with
    /// the film date on, and opens the record's camera.
    private func launchCamera(extra: [String] = [], reusingProfiles: Bool = false) {
        if !reusingProfiles {
            profiles = UUID().uuidString
            let seeding = XCUIApplication()
            seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
            seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
            seeding.launch()
            XCTAssertTrue(seeding.openCamera())
            seeding.terminate()
        }
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "5", "-UITestBindAlbum", "-UITestFocus",
                                "-UITestFilmDate", "topLeading", "-UITestLongToast"] + extra
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        XCTAssertTrue(app.openCamera())
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var styleButton: XCUIElement { element("cameraStyleButton") }
    private var overlayText: XCUIElement { element("overlayText") }
    private var draggableText: XCUIElement { element("overlayTextDraggable") }
    private var panel: XCUIElement { element("stylePanel") }

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
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR712_\(name)_\(device).png"))
        }
    }

    private func assertOnScreen(_ item: XCUIElement, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.waitForExistence(timeout: 5), message, file: file, line: line)
        XCTAssertTrue(app.frame.contains(item.frame), "\(message): \(item.frame) in \(app.frame)", file: file, line: line)
    }

    private func waitForGone(_ item: XCUIElement, _ message: String, timeout: TimeInterval = 5,
                             file: StaticString = #filePath, line: UInt = #line) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: item)
        wait(for: [gone], timeout: timeout)
        XCTAssertFalse(item.exists, message, file: file, line: line)
    }

    // MARK: - 712-5: the 文字樣式 key

    /// 712-5／712-6: the key sits at the bottom right, right of the shutter
    /// and level with it; a tap opens the sheet. No 疊字預覽 switch, and the
    /// text is drawn from the start.
    func test_712_5_styleKeyOpensTheSheet() {
        launchCamera()
        assertOnScreen(styleButton, "712-5 the key is on screen")
        XCTAssertEqual(styleButton.label, "文字樣式")
        let shutter = app.buttons["快門"]
        XCTAssertGreaterThan(styleButton.frame.minX, shutter.frame.maxX, "712-5 right of the shutter")
        XCTAssertEqual(styleButton.frame.midY, shutter.frame.midY, accuracy: 2, "712-5 one bottom row")
        XCTAssertEqual(styleButton.frame.width, 44, accuracy: 1, "712-5 44pt")
        XCTAssertFalse(element("overlayPreviewToggle").exists, "712-6 no switch")
        assertOnScreen(overlayText, "712-6 the text is drawn")

        styleButton.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "712-5 the key opens the sheet")
        XCTAssertEqual(element("stylePanelTitle").label, "文字樣式")
        Thread.sleep(forTimeInterval: 1.5)
        shot("panel_open")
        app.buttons["stylePanelDoneButton"].tap()
        waitForGone(panel, "the checkmark closes it")
    }

    /// 712-6: the text stays after a relaunch; nothing can turn it off.
    func test_712_6_textIsAlwaysDrawn() {
        launchCamera()
        assertOnScreen(overlayText, "712-6 the text is drawn")
        XCTAssertTrue(element("filmDateStamp").exists, "712-6 the film date too")
        app.terminate()
        launchCamera(reusingProfiles: true)
        assertOnScreen(overlayText, "712-6 still drawn after a relaunch")
    }

    // MARK: - 6, 7, 9: the sheet

    /// 6／7／9: the hint shows over the 文字樣式 key (712), a tap on the text
    /// opens the sheet (title, note, bottom bar gone), a drag saves a custom
    /// position, the checkmark closes it and the hint never returns.
    func test_656_6_tapOnTextOpensSheetAndDragSavesPosition() {
        launchCamera(extra: ["-UITestShowTips"])
        assertOnScreen(overlayText, "656-6 the text is drawn")
        let tip = element("overlayTip")
        XCTAssertTrue(tip.waitForExistence(timeout: 5), "656-9 the hint shows first")
        XCTAssertEqual(tip.label, "點這裡的文字可以改樣式")
        assertOnScreen(tip, "712 the hint is on screen")
        XCTAssertLessThan(tip.frame.maxY, styleButton.frame.minY, "712 the hint sits above the key")
        XCTAssertEqual(tip.frame.maxX, styleButton.frame.maxX, accuracy: 8, "712 the hint hangs over the key")
        shot("tip")

        overlayText.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "656-6 the sheet opens")
        XCTAssertEqual(element("stylePanelTitle").label, "文字樣式")
        XCTAssertTrue(element("stylePanelNote").label.hasPrefix("改動存到「"), element("stylePanelNote").label)
        XCTAssertTrue(element("stylePanelNote").label.hasSuffix("拍的照片仍是原圖，匯出時才印上"))
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 3), "656-6 the shared panel")
        XCTAssertFalse(app.buttons["快門"].isHittable, "656-6 the bottom bar is hidden")
        XCTAssertFalse(element("overlayTip").exists, "656-9 no hint while the sheet is open")
        XCTAssertTrue(draggableText.waitForExistence(timeout: 3), "656-7 draggable with the sheet open")
        Thread.sleep(forTimeInterval: 1.5)

        let before = draggableText.frame
        let start = draggableText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1,
                    thenDragTo: start.withOffset(CGVector(dx: -before.width * 0.6, dy: -60)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertLessThan(draggableText.frame.midX, before.midX - 10, "656-7 the text followed the finger")
        app.buttons["內容"].tap()
        let row = app.buttons["positionRow"]
        app.revealInPanel(row)
        XCTAssertEqual(row.label, "位置，自訂位置", "656-7 saved to the record as a custom position")

        app.buttons["stylePanelDoneButton"].tap()
        waitForGone(panel, "656-6 the checkmark closes the sheet")
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 3))
        XCTAssertFalse(element("overlayTip").exists, "656-9 the hint is gone once the sheet was opened")

        // Close the camera and open it again: still no hint.
        element("cameraLatestThumbnail").tap()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 5))
        XCTAssertTrue(app.openCamera())
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))
        XCTAssertFalse(element("overlayTip").exists, "656-9 not again after reopening")
    }

    /// 9: without `-UITestShowTips` the hint does not show.
    func test_656_9_noHintWithoutShowTips() {
        launchCamera()
        assertOnScreen(overlayText, "656-9 the text is drawn")
        XCTAssertFalse(element("overlayTip").exists)
    }

    // MARK: - 8: focus next to the text

    /// 8: a tap on the viewfinder off the text is focus and opens no sheet.
    func test_656_8_tapsAreFocusExceptOnTheText() {
        launchCamera()
        let reticle = element("focusReticle")
        let viewfinderTop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))

        viewfinderTop.tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3), "656-8 a tap off the text focuses")
        XCTAssertFalse(panel.exists, "656-8 and opens no sheet")
    }
}
