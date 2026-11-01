import XCTest

/// #621: the slimmed camera (acceptance 6, 7, 8, 11) and #655: the D9
/// layout with the record switcher and 「返回圖庫」 (acceptance 1–3, 8, 9,
/// 12, 13). With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the
/// B′ screenshots are also written there for the PR.
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
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR655_\(name)_\(device).png"))
        }
    }

    /// Asserts `item` is wholly on screen.
    private func assertOnScreen(_ item: XCUIElement, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.waitForExistence(timeout: 5), message, file: file, line: line)
        XCTAssertTrue(app.frame.contains(item.frame), "\(message): \(item.frame) in \(app.frame)", file: file, line: line)
    }

    private var switcher: XCUIElement { element("cameraRecordSwitcher") }
    private var thumbnail: XCUIElement { element("cameraLatestThumbnail") }
    private var menuRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "cameraRecordMenuRow")
    }

    /// The wall's title reads `name`.
    private func assertWall(of name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 5), "back on a wall", file: file, line: line)
        let title = element("wallTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(title.label.hasPrefix(name), "\(title.label) is \(name)'s wall", file: file, line: line)
    }

    /// Opens the switcher's menu and picks the record that is not checked;
    /// returns its name.
    @discardableResult
    private func switchToTheOtherRecord() -> String {
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        switcher.tap()
        XCTAssertTrue(element("cameraRecordMenu").waitForExistence(timeout: 5))
        let other = menuRows.allElementsBoundByIndex.first { !$0.isSelected }
        guard let other else {
            XCTFail("no unchecked record in the menu")
            return ""
        }
        let name = String(other.label.split(separator: "，").first ?? "")
        other.tap()
        return name
    }

    /// 6 (#655-1, #656): no 「第 N 天」 HUD ever; with 疊字預覽 off no overlay
    /// or film date on the viewfinder either (with it on they are drawn,
    /// `CameraOverlayPreviewUITests`).
    func test_621_6_viewfinderShowsNoOverlayOrHUD() {
        launchCamera(extra: ["-UITestOverlayPreviewOff"])
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        XCTAssertFalse(element("cameraDayHUD").exists, "655-1 no HUD")
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

    /// 8: a photo taken here is on the wall once 「返回圖庫」 closes the camera.
    func test_621_8_closeShowsTheNewPhotoOnTheWall() {
        launchCamera(extra: ["-UITestFakeCapture"])
        let shutter = app.buttons["快門"]
        XCTAssertTrue(shutter.isEnabled)
        shutter.tap()
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        sleep(2)
        thumbnail.tap()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 5), "8 back on the wall")
        let sixth = NSPredicate(format: "count == 6")
        expectation(for: sixth, evaluatedWith: photoCells)
        waitForExpectations(timeout: 10)
    }

    /// 655-1, 655-2, 655-12 (D9): an empty slot at the top left, the switcher
    /// centered, the tools toggle and flip at the top right with flip
    /// outermost; 「返回圖庫」 and the shutter along the bottom, nothing at the
    /// right; the capsule opens under the toggle.
    func test_655_1_2_12_layoutFollowsD9() {
        launchCamera()
        let tools = app.buttons["相機設定"]
        let flip = app.buttons["翻轉鏡頭"]
        let shutter = app.buttons["快門"]
        for item in [switcher, tools, flip, thumbnail, shutter] {
            XCTAssertTrue(item.waitForExistence(timeout: 5), "\(item)")
        }
        XCTAssertEqual(switcher.label, "切換紀錄")
        XCTAssertFalse(element("cameraCloseButton").exists, "655-1 no xmark")
        XCTAssertFalse(app.buttons["回到照片牆"].exists, "655-1 no xmark")
        XCTAssertFalse(element("cameraDayHUD").exists, "655-1 no HUD")

        XCTAssertEqual(switcher.frame.midX, app.frame.midX, accuracy: 2, "655-1 the switcher is centered")
        XCTAssertGreaterThan(switcher.frame.minX, 12 + 44, "655-1 the left slot stays free")
        XCTAssertGreaterThan(tools.frame.minX, switcher.frame.maxX, "655-1 tools right of the switcher")
        XCTAssertGreaterThan(flip.frame.minX, tools.frame.maxX, "655-1 flip outermost")
        XCTAssertEqual(tools.frame.midY, switcher.frame.midY, accuracy: 2, "655-1 one top row")
        XCTAssertEqual(flip.frame.midY, switcher.frame.midY, accuracy: 2, "655-1 one top row")

        XCTAssertEqual(thumbnail.label, "返回圖庫", "655-2")
        XCTAssertLessThan(thumbnail.frame.maxX, shutter.frame.minX, "655-2 thumbnail left of the shutter")
        XCTAssertGreaterThan(thumbnail.frame.midY, switcher.frame.maxY, "655-2 at the bottom")
        let rightOfShutter = app.buttons.allElementsBoundByIndex.filter {
            $0.isHittable && $0.frame.minX > shutter.frame.maxX && abs($0.frame.midY - shutter.frame.midY) < 40
        }
        XCTAssertTrue(rightOfShutter.isEmpty, "655-2 nothing right of the shutter: \(rightOfShutter)")

        tools.tap()
        let flash = app.buttons["閃光燈"]
        XCTAssertTrue(flash.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(flash.frame.minY, tools.frame.maxY, "655-12 the capsule opens below the toggle")
        let grid = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '格線'")).firstMatch
        XCTAssertEqual(grid.frame.maxX, tools.frame.maxX, accuracy: 8, "655-12 lined up under the toggle")
        shot("camera-tools-open")
    }

    /// 655-3, 655-12: the menu lists both records with today's count, the
    /// current one checked; it closes the tools capsule first; picking the
    /// other renames the switcher and says where photos go now.
    func test_655_3_switcherMenuSwitchesRecords() {
        launchCamera(extra: ["-UITestSecondRecord", "新家"])
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        let before = switcher.value as? String ?? ""
        app.buttons["相機設定"].tap()
        XCTAssertTrue(app.buttons["閃光燈"].waitForExistence(timeout: 5))

        switcher.tap()
        XCTAssertTrue(element("cameraRecordMenu").waitForExistence(timeout: 5), "655-3 the menu opens")
        XCTAssertFalse(app.buttons["閃光燈"].exists, "655-12 the capsule closed first")
        XCTAssertEqual(menuRows.count, 2, "655-3 every record")
        XCTAssertLessThan(element("cameraRecordMenu").frame.height, 44 * 3, "two rows: the card hugs them")
        for row in menuRows.allElementsBoundByIndex {
            XCTAssertTrue(row.label.hasSuffix("今天第 10 天"), "655-3 \(row.label)")
        }
        let checked = menuRows.allElementsBoundByIndex.filter(\.isSelected)
        XCTAssertEqual(checked.count, 1, "655-3 one checked")
        XCTAssertTrue(checked.first?.label.hasPrefix(before) ?? false, "655-3 the current record is checked")
        shot("record-menu-open")

        let other = menuRows.allElementsBoundByIndex.first { !$0.isSelected }
        let name = String(other?.label.split(separator: "，").first ?? "")
        other?.tap()
        let toast = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "改存到「\(name)」")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 2), "655-3 toast")
        XCTAssertEqual(switcher.value as? String, name, "655-3 the switcher reads the new record")
        XCTAssertFalse(element("cameraRecordMenu").exists, "the menu closed")
    }

    /// #659 review: with 20 records the menu stays on screen above the
    /// shutter and scrolls; the record at the far end can be picked.
    func test_655_3_menuWithTwentyRecordsScrolls() {
        launchCamera(extra: ["-UITestSecondRecord", "新家", "-UITestRecordCount", "20"])
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        switcher.tap()
        let menu = element("cameraRecordMenu")
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let shutter = app.buttons["快門"]
        XCTAssertLessThan(menu.frame.maxY, shutter.frame.minY, "the menu ends above the bottom bar")
        XCTAssertTrue(app.frame.contains(menu.frame), "the menu is on screen")
        let checked = menuRows.allElementsBoundByIndex.first(where: \.isSelected)
        XCTAssertTrue(checked?.isHittable ?? false, "the selected record is visible")
        shot("record-menu-twenty")

        let rows = menuRows.allElementsBoundByIndex
        XCTAssertEqual(rows.count, 20)
        let target = rows.first(where: \.isSelected) == rows.first ? rows.last : rows.first
        guard let target else { return XCTFail("no row") }
        for _ in 0..<6 where !target.isHittable {
            menu.swipe(direction: target == rows.last ? .up : .down)
        }
        XCTAssertTrue(target.isHittable, "the far end scrolls into view")
        let name = String(target.label.split(separator: "，").first ?? "")
        target.tap()
        XCTAssertEqual(switcher.value as? String, name)

        // Reopened, the menu opens on the record now checked.
        switcher.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        sleep(1)
        let reopened = menuRows.allElementsBoundByIndex.first(where: \.isSelected)
        XCTAssertTrue(reopened?.label.hasPrefix(name) ?? false)
        XCTAssertTrue(reopened?.isHittable ?? false, "scrolled to the selected record")
    }

    /// 655-8: without switching, 「返回圖庫」 goes back to the same wall.
    func test_655_8_backWithoutSwitchingReturnsToTheSameWall() {
        launchCamera(extra: ["-UITestSecondRecord", "新家"])
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        let name = switcher.value as? String ?? ""
        thumbnail.tap()
        assertWall(of: name)
    }

    /// 655-8: after switching, 「返回圖庫」 opens the new record's wall, and
    /// back goes to the 紀錄 list.
    func test_655_8_backAfterSwitchingOpensTheNewRecordsWall() {
        launchCamera(extra: ["-UITestSecondRecord", "新家"])
        let name = switchToTheOtherRecord()
        XCTAssertFalse(name.isEmpty)
        thumbnail.tap()
        assertWall(of: name)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["紀錄"].waitForExistence(timeout: 5), "655-8 back leads to the list")
    }

    /// 655-9: taps and a pinch on the viewfinder leave the camera up; a
    /// swipe down from the top bar closes it onto the switched record's wall.
    func test_655_9_swipeDownClosesButViewfinderGesturesDoNot() {
        launchCamera(extra: ["-UITestSecondRecord", "新家"])
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        let shutter = app.buttons["快門"]
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        middle.tap()
        middle.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        app.pinch(withScale: 2, velocity: 2)
        sleep(1)
        XCTAssertTrue(shutter.exists, "655-9 viewfinder gestures do not close the camera")

        let name = switchToTheOtherRecord()
        sleep(2)
        let top = switcher.coordinate(withNormalizedOffset: CGVector(dx: -1.5, dy: 0.5))
        top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 400)))
        assertWall(of: name)
    }

    /// 13: the camera held upright.
    func test_621_11_portraitScreenshot() {
        launchCamera()
        assertOnScreen(switcher, "switcher")
        assertOnScreen(app.buttons["相機設定"], "tools")
        assertOnScreen(app.buttons["翻轉鏡頭"], "flip")
        assertOnScreen(app.buttons["快門"], "shutter")
        assertOnScreen(thumbnail, "返回圖庫")
        sleep(1)
        shot("camera-portrait")
    }

    /// 11: the camera held sideways — the icons turn, the switcher and
    /// layout do not (#572).
    func test_621_11_landscapeScreenshot() {
        launchCamera(extra: ["-UITestCaptureRotationAngle", "0"])
        assertOnScreen(switcher, "switcher")
        assertOnScreen(app.buttons["翻轉鏡頭"], "flip")
        assertOnScreen(app.buttons["快門"], "shutter")
        assertOnScreen(thumbnail, "返回圖庫")
        sleep(1)
        shot("camera-landscape")
    }
}

private extension XCUIElement {
    enum SwipeDirection { case up, down }

    func swipe(direction: SwipeDirection) {
        direction == .up ? swipeUp() : swipeDown()
    }
}
