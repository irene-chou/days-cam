import XCTest

/// #656: the camera's 疊字預覽 switch (acceptance 1, 2), the style sheet
/// opened from the text (6, 7), tap-to-focus next to it (8) and the first-run
/// hint (9). With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the
/// B′ screenshots (D9 ①②③) are also written there for the PR.
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
                                "-UITestFilmDate", "topLeading"] + extra
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        XCTAssertTrue(app.openCamera())
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var toggle: XCUIElement { element("overlayPreviewToggle") }
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
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR656_\(name)_\(device).png"))
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

    // MARK: - 1: the switch

    /// 1: on at first (value 開), a tap turns it off and says so, another
    /// tap turns it on; the text follows.
    func test_656_1_switchTogglesWithToast() {
        launchCamera()
        assertOnScreen(toggle, "656-1 the switch is on screen")
        XCTAssertEqual(toggle.value as? String, "開", "656-1 on by default")
        XCTAssertEqual(toggle.label, "疊字預覽")
        assertOnScreen(overlayText, "656-1 the text is drawn")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "關")
        let offToast = element("overlayPreviewToast")
        XCTAssertTrue(offToast.waitForExistence(timeout: 3), "656-1 toast")
        XCTAssertEqual(offToast.label, "疊字預覽 關閉")
        waitForGone(overlayText, "656-1 no text with the preview off")
        shot("1_off")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "開")
        XCTAssertTrue(element("overlayPreviewToast").waitForExistence(timeout: 3))
        XCTAssertEqual(element("overlayPreviewToast").label, "疊字預覽 開啟")
        assertOnScreen(overlayText, "656-1 the text is back")
    }

    // MARK: - 2: remembered

    /// 2: off stays off after the app is relaunched.
    func test_656_2_switchSurvivesARelaunch() {
        launchCamera()
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "關")
        app.terminate()

        launchCamera(extra: ["-UITestKeepOverlayPreview"], reusingProfiles: true)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "關", "656-2 still off")
        XCTAssertFalse(overlayText.exists)
    }

    // MARK: - 6, 7, 9: the sheet

    /// 6／7／9: the hint shows, a tap on the text opens the sheet (title, note,
    /// bottom bar gone), a drag saves a custom position, the checkmark closes
    /// it and the hint never returns.
    func test_656_6_tapOnTextOpensSheetAndDragSavesPosition() {
        launchCamera(extra: ["-UITestShowTips"])
        assertOnScreen(overlayText, "656-6 the text is drawn")
        XCTAssertTrue(element("overlayTip").waitForExistence(timeout: 5), "656-9 the hint shows first")
        XCTAssertEqual(element("overlayTip").label, "點畫面上的字可以改樣式")
        shot("2_on_tip")

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
        shot("3_sheet")

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

    /// 8: with the preview off a tap on the viewfinder is focus and opens
    /// no sheet; with it on, a tap off the text is focus too.
    func test_656_8_tapsAreFocusExceptOnTheText() {
        launchCamera()
        let reticle = element("focusReticle")
        let viewfinderTop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))

        viewfinderTop.tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3), "656-8 a tap off the text focuses")
        XCTAssertFalse(panel.exists, "656-8 and opens no sheet")

        toggle.tap()
        waitForGone(overlayText, "656-8 preview off")
        viewfinderTop.tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3), "656-8 off: a tap focuses")
        XCTAssertFalse(panel.exists, "656-8 off: no sheet entry")
    }
}
