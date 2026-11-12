import XCTest

/// #724: the camera's day HUD in the viewfinder's bottom-left corner
/// (acceptance 1, 6), no overlay, 文字樣式 key, hint or style sheet (2), and
/// a tap anywhere on the viewfinder is focus (3). With `DAYSCAM_UI_SHOT_DIR`
/// in the test runner's environment the B′ screenshots (6) are also written
/// there for the PR.
final class CameraHUDUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record 「我的紀錄」 starting 2026-01-01, then launches on
    /// 2026-01-10 with the overlay and film date on, and opens its camera.
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

    private var hud: XCUIElement { element("cameraDayHUD") }
    private var viewfinder: XCUIElement { element("cameraViewfinder") }
    private var ratioButton: XCUIElement { element("cameraRatioButton") }
    private var switcher: XCUIElement { element("cameraRecordSwitcher") }

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
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR724_\(name)_\(device).png"))
        }
    }

    private func assertOnScreen(_ item: XCUIElement, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.waitForExistence(timeout: 5), message, file: file, line: line)
        XCTAssertTrue(app.frame.contains(item.frame), "\(message): \(item.frame) in \(app.frame)", file: file, line: line)
    }

    /// Waits until the ratio key reads `label`.
    private func waitForRatio(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let reads = NSPredicate(format: "label == %@", "比例：\(label)")
        let expectation = XCTNSPredicateExpectation(predicate: reads, object: ratioButton)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "ratio reads \(label), got \(ratioButton.label)", file: file, line: line)
    }

    /// Waits until the HUD reads `label`.
    private func waitForHUD(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let reads = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: reads, object: hud)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "HUD reads \(label), got \(hud.label)", file: file, line: line)
    }

    /// The HUD sits 12pt in from the picture's bottom-left corner while the
    /// phone is held upright; where the picture runs behind the bottom bar
    /// (9:16) it sits 12pt above 「返回圖庫」 instead.
    private func assertHUDInBottomLeft(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let picture = viewfinder.frame
        let frame = hud.frame
        let thumbnail = element("cameraLatestThumbnail").frame
        XCTAssertTrue(picture.contains(frame), "\(message): \(frame) in \(picture)", file: file, line: line)
        XCTAssertEqual(frame.minX - picture.minX, 12, accuracy: 2, "\(message) 12pt from the left", file: file, line: line)
        let floor = min(picture.maxY, thumbnail.minY)
        XCTAssertEqual(floor - frame.maxY, 12, accuracy: 2, "\(message) 12pt above \(floor)", file: file, line: line)
        XCTAssertFalse(frame.intersects(thumbnail), "\(message) clear of 返回圖庫", file: file, line: line)
    }

    // MARK: - 1: the HUD

    /// 1: 「第 10 天」 over the record's name in the viewfinder's bottom-left
    /// corner, one VoiceOver element; no overlay text, no film date.
    func test_724_1_hudShowsTheDayAndTheRecord() {
        launchCamera()
        assertOnScreen(hud, "724-1 the HUD is drawn")
        XCTAssertEqual(hud.label, "第 10 天，我的紀錄", "724-1")
        assertHUDInBottomLeft("724-1")
        XCTAssertFalse(element("overlayText").exists, "724-1 no overlay text")
        XCTAssertFalse(element("overlayTextDraggable").exists, "724-1 no overlay text")
        XCTAssertFalse(element("filmDateStamp").exists, "724-1 no film date")
    }

    /// 1 (FR-20.8): switching records swaps the HUD's name at once.
    func test_724_1_switchingRecordsSwapsTheHUD() {
        launchCamera(extra: ["-UITestSecondRecord", "小寶"])
        assertOnScreen(hud, "the HUD is drawn")
        XCTAssertEqual(hud.label, "第 10 天，我的紀錄")
        switcher.tap()
        XCTAssertTrue(element("cameraRecordMenu").waitForExistence(timeout: 5))
        let rows = app.descendants(matching: .any).matching(identifier: "cameraRecordMenuRow")
        let other = rows.allElementsBoundByIndex.first { !$0.isSelected }
        XCTAssertNotNil(other, "the other record is in the menu")
        other?.tap()
        waitForHUD("第 10 天，小寶")
    }

    // MARK: - 2: nothing of the overlay is left

    /// 2: no 文字樣式 key, no hint, no style sheet; the bottom row is 「返回圖庫」 and the centered shutter only.
    func test_724_2_noStyleKeyHintOrSheet() {
        launchCamera()
        assertOnScreen(hud, "the HUD is drawn")
        let shutter = app.buttons["快門"]
        assertOnScreen(shutter, "the shutter")
        XCTAssertEqual(shutter.frame.midX, app.frame.midX, accuracy: 2, "724-2 the shutter stays centered")
        XCTAssertFalse(element("cameraStyleButton").exists, "724-2 no 文字樣式 key")
        XCTAssertFalse(app.buttons["文字樣式"].exists, "724-2 no 文字樣式 key")
        XCTAssertFalse(element("overlayTip").exists, "724-2 no hint")
        XCTAssertFalse(element("stylePanel").exists, "724-2 no sheet")

        hud.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(element("stylePanel").waitForExistence(timeout: 2), "724-2 the HUD opens nothing")
    }

    // MARK: - 3: focus everywhere

    /// 3: a tap is focus wherever it lands — on the HUD, where the overlay
    /// text used to be (bottom right) and in the middle — and opens nothing.
    func test_724_3_everyTapOnTheViewfinderFocuses() {
        launchCamera()
        assertOnScreen(hud, "the HUD is drawn")
        let reticle = element("focusReticle")
        let picture = viewfinder.frame
        let points: [(String, CGPoint)] = [
            ("the HUD", CGPoint(x: hud.frame.midX, y: hud.frame.midY)),
            ("the old text corner", CGPoint(x: picture.maxX - 60, y: picture.maxY - 40)),
            ("the middle", CGPoint(x: picture.midX, y: picture.midY)),
        ]
        for (name, point) in points {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
            XCTAssertTrue(reticle.waitForExistence(timeout: 3), "724-3 \(name) focuses")
            let moved = NSPredicate { _, _ in
                abs(reticle.frame.midX - point.x) < 30 && abs(reticle.frame.midY - point.y) < 30
            }
            let expectation = XCTNSPredicateExpectation(predicate: moved, object: nil)
            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 3), .completed,
                           "724-3 the reticle is at \(name): \(reticle.frame) vs \(point)")
            XCTAssertFalse(element("stylePanel").exists, "724-3 \(name) opens no sheet")
        }
    }

    // MARK: - 6: each ratio, and held sideways

    /// 6: the HUD hugs the bottom-left corner of the 3:4, 1:1 and 9:16
    /// pictures; one screenshot each.
    func test_724_6_hudFollowsEachRatio() {
        launchCamera()
        for (index, label) in ["3:4", "1:1", "9:16"].enumerated() {
            if index > 0 { ratioButton.tap() }
            waitForRatio(label)
            Thread.sleep(forTimeInterval: 1)
            assertOnScreen(hud, "724-6 \(label) the HUD is drawn")
            assertHUDInBottomLeft("724-6 \(label)")
            shot("hud_\(label.replacingOccurrences(of: ":", with: "x"))")
        }
    }

    /// #724 review: with the quick-zoom control in the same corner, the HUD
    /// stays clear of it at every ratio, closed, and open at 3:4 and 1:1; one
    /// screenshot of each at 3:4.
    func test_724_6_hudClearsTheZoomControl() {
        launchCamera(extra: ["-UITestZoomPresets"])
        let round = element("zoomRoundButton")
        let presets = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'zoomPreset-'"))
        for (index, label) in ["3:4", "1:1", "9:16"].enumerated() {
            if index > 0 { ratioButton.tap() }
            waitForRatio(label)
            Thread.sleep(forTimeInterval: 1)
            assertOnScreen(hud, "\(label) the HUD is drawn")
            assertOnScreen(round, "\(label) the zoom control is drawn")
            XCTAssertTrue(viewfinder.frame.contains(hud.frame), "\(label) HUD \(hud.frame) in \(viewfinder.frame)")
            XCTAssertFalse(hud.frame.intersects(round.frame), "\(label) HUD \(hud.frame) clear of \(round.frame)")
            XCTAssertLessThanOrEqual(hud.frame.maxY, round.frame.minY, "\(label) HUD above the zoom control")
            if index == 0 { shot("hud_3x4_zoom") }
            // At 9:16 the bottom bar lies over the control (as before #724);
            // the open capsule there is covered by the metrics test.
            guard label != "9:16" else { continue }

            round.tap()
            XCTAssertTrue(presets.firstMatch.waitForExistence(timeout: 3), "\(label) the capsule opens")
            Thread.sleep(forTimeInterval: 0.6)
            for preset in presets.allElementsBoundByIndex {
                XCTAssertFalse(hud.frame.intersects(preset.frame),
                               "\(label) open: HUD \(hud.frame) clear of \(preset.identifier) \(preset.frame)")
            }
            XCTAssertTrue(viewfinder.frame.contains(hud.frame), "\(label) open: HUD in the picture")
            if index == 0 { shot("hud_3x4_zoom_open") }
            // A tap on the picture closes the capsule (#541).
            viewfinder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            XCTAssertTrue(round.waitForExistence(timeout: 3), "\(label) the capsule closes")
        }
    }

    /// 6: held sideways, the HUD turns with the picture (#571, #572): it
    /// stays inside the picture and is drawn on its own side, not upright.
    func test_724_6_hudTurnsWhenHeldSideways() {
        launchCamera(extra: ["-UITestCaptureRotationAngle", "0"])
        assertOnScreen(hud, "724-6 the HUD is drawn")
        let picture = viewfinder.frame
        XCTAssertTrue(picture.contains(hud.frame), "724-6 \(hud.frame) in \(picture)")
        XCTAssertGreaterThan(hud.frame.height, hud.frame.width, "724-6 the text runs along the long side")
        Thread.sleep(forTimeInterval: 1)
        shot("hud_landscape")
    }
}
