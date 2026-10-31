import XCTest

/// #621: the slimmed camera (acceptance 6, 7, 8, 11). With
/// `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′ screenshots
/// are also written there for the PR.
final class CameraUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record starting 2026-01-01, then launches on 2026-01-10 with
    /// five photos in the record's album (第 6 天 … 第 10 天), the film date
    /// on, and opens the record's camera.
    private func launchCamera(extra: [String] = []) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "5", "-UITestBindAlbum",
                                "-UITestFilmDate", "bottomTrailing"] + extra
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        XCTAssertTrue(app.openCamera())
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var photoCells: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "photoCell")
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
            let device = UIDevice.current.name.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR621_\(name)_\(device).png"))
        }
    }

    /// Asserts `item` is wholly on screen.
    private func assertOnScreen(_ item: XCUIElement, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.waitForExistence(timeout: 5), message, file: file, line: line)
        XCTAssertTrue(app.frame.contains(item.frame), "\(message): \(item.frame) in \(app.frame)", file: file, line: line)
    }

    /// 6: no overlay or film date on the viewfinder, even with the film date
    /// on; the HUD reads the record's day.
    func test_621_6_viewfinderShowsOnlyTheDayHUD() {
        launchCamera()
        let hud = element("cameraDayHUD")
        XCTAssertTrue(hud.waitForExistence(timeout: 5))
        XCTAssertEqual(hud.label, "第 10 天", "6")
        XCTAssertFalse(element("overlayText").exists, "6 no overlay")
        XCTAssertFalse(element("overlayTextDraggable").exists, "6 no overlay")
        XCTAssertFalse(element("filmDateStamp").exists, "6 no film date")
    }

    /// 7: no ratio, tone, profile menu or panel entry, in the bar or the
    /// tools capsule.
    func test_621_7_cameraHasNoRatioToneProfileOrPanel() {
        launchCamera()
        XCTAssertFalse(app.buttons["疊字設定"].exists, "7 panel entry")
        XCTAssertFalse(element("panelCollapseButton").exists, "7 panel")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '比例'")).firstMatch.exists, "7 ratio")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '設定檔'")).firstMatch.exists, "7 profile menu")
        app.buttons["相機設定"].tap()
        XCTAssertTrue(app.buttons["閃光燈"].waitForExistence(timeout: 5), "7 the capsule is still there")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '計時器'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '格線'")).firstMatch.exists)
        XCTAssertFalse(element("toneButton").exists, "7 tone")
        XCTAssertFalse(element("tonePicker").exists, "7 tone")
        XCTAssertTrue(app.buttons["翻轉鏡頭"].exists, "flip stays")
    }

    /// 8: a photo taken here is on the wall once `xmark` closes the camera.
    func test_621_8_closeShowsTheNewPhotoOnTheWall() {
        launchCamera(extra: ["-UITestFakeCapture"])
        let shutter = app.buttons["快門"]
        XCTAssertTrue(shutter.isEnabled)
        shutter.tap()
        // The corner button shows the new photo once it has landed.
        let thumbnail = element("cameraLatestThumbnail")
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        sleep(2)
        element("cameraCloseButton").tap()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 5), "8 back on the wall")
        let sixth = NSPredicate(format: "count == 6")
        expectation(for: sixth, evaluatedWith: photoCells)
        waitForExpectations(timeout: 10)
    }

    /// FR-20.5: the newest-photo button goes back to the wall too.
    func testLatestThumbnailGoesBackToTheWall() {
        launchCamera()
        let thumbnail = element("cameraLatestThumbnail")
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        thumbnail.tap()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 5))
    }

    /// FR-20.7 (human decision 2026-10-31): xmark alone at the top left, HUD
    /// in the middle, the tools toggle at the top right with its capsule
    /// opening under it; newest photo, shutter, flip along the bottom.
    func testLayoutPutsToolsTopRightAndFlipBesideTheShutter() {
        launchCamera()
        let close = element("cameraCloseButton")
        let hud = element("cameraDayHUD")
        let tools = app.buttons["相機設定"]
        let thumbnail = element("cameraLatestThumbnail")
        let shutter = app.buttons["快門"]
        let flip = app.buttons["翻轉鏡頭"]
        for item in [close, hud, tools, thumbnail, shutter, flip] {
            XCTAssertTrue(item.waitForExistence(timeout: 5), "\(item)")
        }
        XCTAssertLessThan(close.frame.midX, hud.frame.minX, "xmark left of the HUD")
        XCTAssertGreaterThan(tools.frame.midX, hud.frame.maxX, "tools toggle right of the HUD")
        XCTAssertEqual(tools.frame.midY, close.frame.midY, accuracy: 2, "one top row")
        XCTAssertGreaterThan(tools.frame.midX, app.frame.width * 0.75, "the toggle sits at the top right")
        XCTAssertLessThan(close.frame.midX, app.frame.width * 0.25, "xmark sits at the top left")

        XCTAssertLessThan(thumbnail.frame.maxX, shutter.frame.minX, "newest photo left of the shutter")
        XCTAssertGreaterThan(flip.frame.minX, shutter.frame.maxX, "flip right of the shutter")
        XCTAssertEqual(flip.frame.midY, shutter.frame.midY, accuracy: 2, "one bottom row")
        XCTAssertEqual(thumbnail.frame.midY, shutter.frame.midY, accuracy: 2, "one bottom row")
        XCTAssertEqual(app.frame.width - flip.frame.midX, thumbnail.frame.midX, accuracy: 2, "mirrored side keys")

        tools.tap()
        let flash = app.buttons["閃光燈"]
        XCTAssertTrue(flash.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(flash.frame.minY, tools.frame.maxY, "the capsule opens below the toggle")
        let grid = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '格線'")).firstMatch
        XCTAssertEqual(grid.frame.maxX, tools.frame.maxX, accuracy: 8, "the capsule lines up at the right")
        shot("camera-tools-open")
    }

    /// 11: the camera held upright.
    func test_621_11_portraitScreenshot() {
        launchCamera()
        assertOnScreen(element("cameraDayHUD"), "HUD")
        assertOnScreen(element("cameraCloseButton"), "xmark")
        assertOnScreen(app.buttons["快門"], "shutter")
        assertOnScreen(element("cameraLatestThumbnail"), "newest photo")
        assertOnScreen(app.buttons["翻轉鏡頭"], "flip")
        sleep(1)
        shot("camera-portrait")
    }

    /// 11: the camera held sideways — the icons turn, the HUD and layout
    /// do not (#572).
    func test_621_11_landscapeScreenshot() {
        launchCamera(extra: ["-UITestCaptureRotationAngle", "0"])
        assertOnScreen(element("cameraDayHUD"), "HUD")
        assertOnScreen(element("cameraCloseButton"), "xmark")
        assertOnScreen(app.buttons["快門"], "shutter")
        assertOnScreen(element("cameraLatestThumbnail"), "newest photo")
        sleep(1)
        shot("camera-landscape")
    }
}
