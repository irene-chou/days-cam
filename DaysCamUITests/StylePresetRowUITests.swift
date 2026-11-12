import XCTest

/// #678: the style tab's row of ten looks, the box button and the 自訂
/// capsule (acceptance 1, 2, 6, 7, 10, 11, 12). With `DAYSCAM_UI_SHOT_DIR`
/// in the test runner's environment the B′ screenshots are also written
/// there.
final class StylePresetRowUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let order = ["classic", "caption", "poster", "outline", "magazine",
                                "handwriting", "note", "cute", "neon", "retro"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func openStyleTab(extraArguments: [String] = []) {
        XCTAssertTrue(app.launchOnExportPage(extraArguments: extraArguments), "the export page is up")
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
        XCTAssertTrue(preset("classic").waitForExistence(timeout: 5), "the row of looks")
    }

    private func preset(_ rawValue: String) -> XCUIElement {
        app.buttons["stylePreset_\(rawValue)"]
    }

    private var boxButton: XCUIElement { app.buttons["boxStateButton"] }

    private func shot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["DAYSCAM_UI_SHOT_DIR"], !path.isEmpty {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let device = UIDevice.current.name.filter { !$0.isWhitespace && $0 != "(" && $0 != ")" }
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR\(name.hasPrefix("693") ? "693" : "678")_\(name)_\(device).png"))
        }
    }

    /// 1 / 2 / 10: no sub-tabs; the row, the colors and the size top to
    /// bottom; the ten looks in order with 經典 selected; five in the first
    /// 375pt.
    func testRowOfLooksIsInOrderAboveColorsAndSize() {
        openStyleTab()
        for gone in ["字型", "顏色", "外框", "陰影"] {
            XCTAssertFalse(app.buttons[gone].exists, "1 no sub-tab \(gone)")
        }
        let looks = Self.order.map(preset)
        for look in looks { XCTAssertTrue(look.exists, "2 \(look)") }
        let labels = ["經典", "字幕", "海報", "描邊", "雜誌", "手寫", "便條", "可愛", "霓虹", "復古"]
        XCTAssertEqual(looks.map(\.label), labels, "2 names")
        let xs = looks.map(\.frame.minX)
        XCTAssertEqual(xs, xs.sorted(), "2 in allCases order")
        XCTAssertTrue(preset("classic").isSelected, "2 a new record is 經典")
        XCTAssertEqual(looks.filter(\.isSelected).count, 1)
        XCTAssertFalse(preset("custom").exists)
        XCTAssertGreaterThanOrEqual(looks.filter { $0.frame.maxX <= 375 }.count, 5, "10 five looks in 375pt")

        let white = app.buttons["#FFFFFF"]
        let slider = app.sliders["字級"]
        XCTAssertTrue(white.exists && slider.exists)
        XCTAssertLessThan(preset("classic").frame.maxY, white.frame.minY, "1 row above the colors")
        XCTAssertLessThan(app.buttons["自訂顏色"].frame.maxY, slider.frame.minY, "1 colors above the size")
        XCTAssertEqual(boxButton.frame.midY, app.buttons["自訂顏色"].frame.midY, accuracy: 1,
                       "the box button on the rainbow's row")
        XCTAssertGreaterThan(boxButton.frame.minX, app.buttons["#A307BA"].frame.minX - 1, "at the right end")
        XCTAssertTrue(preset("classic").isHittable && boxButton.isHittable)
        XCTAssertTrue(slider.isHittable, "#691 the size row is in view without scrolling")
        XCTAssertLessThan(slider.frame.maxY, app.staticTexts["改動直接存到這個紀錄，回檢視頁再匯出"].frame.minY,
                          "#691 above the note")
        shot("12_default")
    }

    /// 2 / 12: tapping 海報 moves the ring.
    func testTappingPosterMovesTheSelection() {
        openStyleTab()
        preset("poster").tap()
        XCTAssertTrue(preset("poster").isSelected, "2 海報 selected")
        XCTAssertFalse(preset("classic").isSelected, "2 the ring left 經典")
        XCTAssertTrue(preset("poster").isHittable)
        shot("12_poster")
    }

    /// 6: the box button cycles 原本 → 實心 → 半透明 → 原本, the look kept.
    func testBoxButtonCyclesItsValue() {
        openStyleTab()
        XCTAssertEqual(boxButton.label, "底框")
        XCTAssertEqual(boxButton.value as? String, "原本")
        boxButton.tap()
        XCTAssertEqual(boxButton.value as? String, "實心，圓角", "6")
        boxButton.tap()
        XCTAssertEqual(boxButton.value as? String, "半透明，圓角", "6")
        XCTAssertTrue(preset("classic").isSelected, "#676 ruling: still 經典")
        boxButton.tap()
        XCTAssertEqual(boxButton.value as? String, "原本", "6")
    }

    /// 693-1 / 693-2: the value names the look's box shape and keeps it through the states.
    func testBoxButtonNamesTheLooksShape() {
        openStyleTab()
        // 海報's own outline is the solid box, so it cycles two states.
        let expected = [("poster", "方角", ["半透明"]), ("classic", "圓角", ["實心", "半透明"]),
                        ("cute", "膠囊", ["實心", "半透明"])]
        for (look, shape, states) in expected {
            if look == "cute" {
                app.scrollViews.containing(.button, identifier: "stylePreset_classic").element(boundBy: 1).swipeLeft()
            }
            preset(look).tap()
            XCTAssertEqual(boxButton.value as? String, "原本", "693-2 \(look)")
            for state in states {
                boxButton.tap()
                XCTAssertEqual(boxButton.value as? String, "\(state)，\(shape)", "693-1 \(look)")
                if state == states[0] { shot("693_\(look)") }
            }
            boxButton.tap()
            XCTAssertEqual(boxButton.value as? String, "原本", "693-2 \(look)")
        }
    }

    /// 7 / 12: a style matching no look shows 自訂 at the row's end,
    /// selected, with the box button off; a look ends it.
    func testCustomStyleShowsTheCustomCapsuleUntilALookIsPicked() {
        openStyleTab(extraArguments: ["-UITestCustomStyle"])
        let custom = preset("custom")
        XCTAssertTrue(custom.waitForExistence(timeout: 3), "7 自訂")
        XCTAssertTrue(custom.isSelected, "7")
        XCTAssertEqual(Self.order.map(preset).filter(\.isSelected).count, 0, "7 no look selected")
        XCTAssertFalse(boxButton.isEnabled, "7 box button disabled")
        // Scroll the row to its end to show the capsule for B′.
        let row = app.scrollViews.containing(.button, identifier: "stylePreset_classic").element(boundBy: 1)
        if row.exists { row.swipeLeft() }
        XCTAssertTrue(custom.isHittable, "7 the capsule can be scrolled to")
        XCTAssertGreaterThan(custom.frame.minX, preset("retro").frame.minX, "7 at the end")
        shot("12_custom")

        if row.exists { row.swipeRight() }
        preset("classic").tap()
        XCTAssertTrue(preset("classic").isSelected, "7")
        XCTAssertFalse(custom.exists, "7 自訂 is gone")
        XCTAssertTrue(boxButton.isEnabled)
    }

    /// 10: at the largest text size the names are whole: each capsule grows
    /// with its name and the row scrolls.
    func testLargestTextSizeKeepsWholeNames() {
        openStyleTab(extraArguments: ["-UIPreferredContentSizeCategoryName",
                                      "UICTContentSizeCategoryAccessibilityXXXL"])
        let classic = preset("classic")
        XCTAssertEqual(classic.label, "經典")
        XCTAssertGreaterThan(classic.frame.height, 34, "10 grows with the text")
        XCTAssertGreaterThan(classic.frame.width, classic.frame.height, "10 two whole characters wide")
        shot("10_largest_text")
    }

    /// 11: the viewer's 調整文字樣式 on its export sheet (#679) opens this
    /// style tab; the camera has no style sheet since #724.
    func testViewerOpensTheStyleTab() {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "5", "-UITestBindAlbum"]
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
        let element: (String) -> XCUIElement = { self.app.descendants(matching: .any).matching(identifier: $0).firstMatch }

        // The viewer's 匯出 → 調整文字樣式 (#679: no 文字樣式 key on the photo page).
        let cell = element("photoCell")
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        XCTAssertTrue(element("photoDetailExportButton").waitForExistence(timeout: 5))
        element("photoDetailExportButton").tap()
        XCTAssertTrue(element("batchExportStyleLink").waitForExistence(timeout: 5))
        element("batchExportStyleLink").tap()
        XCTAssertTrue(element("exportView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.openLayer("layerRowOverlay", expecting: app.buttons["樣式"]), "the layer list opens 疊字")
        app.buttons["樣式"].tap()
        XCTAssertTrue(preset("classic").waitForExistence(timeout: 5), "11 viewer: the row of looks")
        XCTAssertTrue(boxButton.exists, "11 viewer")
        XCTAssertTrue(app.backToLayerList(), "the back key returns to the layer list")
        element("exportCancelButton").tap()
        XCTAssertTrue(element("batchExportSheet").waitForExistence(timeout: 5))
    }
}
