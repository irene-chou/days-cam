import XCTest

/// #718: the 文字樣式 panel as a layer list — 疊字 and 底片日期, each with its
/// switch, a push into its settings, and a greyed page with a 顯示 key while
/// the layer is off. With `DAYSCAM_UI_SHOT_DIR` in the test runner's
/// environment the B′ screenshots are also written there for the PR.
final class LayerListUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Launches on the export page at the layer list. `overlayOn` keeps the
    /// test record's 疊字 on; otherwise it has the real default, both layers off.
    private func launch(overlayOn: Bool) {
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(extraArguments: overlayOn ? [] : ["-UITestOverlayOff"],
                                             entersOverlayDetail: false), "the export page is up")
        XCTAssertTrue(app.buttons["layerRowOverlay"].waitForExistence(timeout: 10), "the layer list is first")
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
            let device = UIDevice.current.name.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR718_\(name)_\(device).png"))
        }
    }

    private var overlayToggle: XCUIElement { app.switches["layerToggleOverlay"] }
    private var filmToggle: XCUIElement { app.switches["layerToggleFilmDate"] }
    private var textOnPreview: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@",
                                                              ["overlayText", "overlayTextDraggable"])).firstMatch
    }
    private func drawsText() -> Bool { textOnPreview.exists && !textOnPreview.label.isEmpty }

    /// 718-1: a new record has both layers off and the preview draws neither.
    func test_718_1_newRecordHasBothLayersOff() {
        launch(overlayOn: false)
        XCTAssertEqual(overlayToggle.value as? String, "0")
        XCTAssertEqual(filmToggle.value as? String, "0")
        XCTAssertFalse(drawsText(), "no text on the preview")
        shot("root_off")
    }

    /// 718-4: both rows tall enough, with the summaries; the switches act at
    /// once on the preview and write to the record.
    func test_718_4_rowsShowSummariesAndSwitchesActAtOnce() {
        launch(overlayOn: true)
        for id in ["layerRowOverlay", "layerRowFilmDate"] {
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44, id)
        }
        XCTAssertEqual(overlayToggle.value as? String, "1")
        XCTAssertEqual(filmToggle.value as? String, "0")
        let summary = app.buttons["layerRowOverlay"].label
        XCTAssertTrue(summary.hasPrefix("疊字，"), summary)
        XCTAssertTrue(summary.contains("天數、名稱") && summary.contains("右下"), summary)
        XCTAssertEqual(app.buttons["layerRowFilmDate"].label, "底片日期，左下角")
        XCTAssertTrue(drawsText(), "text on the preview")
        XCTAssertTrue(app.staticTexts["改動直接存到這個紀錄，回檢視頁再匯出"].exists)

        filmToggle.tap()
        XCTAssertEqual(filmToggle.value as? String, "1")
        shot("root_both_on")

        overlayToggle.tap()
        XCTAssertEqual(overlayToggle.value as? String, "0")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == ''"), object: textOnPreview)
        XCTAssertTrue(!textOnPreview.exists || XCTWaiter().wait(for: [gone], timeout: 3) == .completed, "the text goes")
        XCTAssertTrue(app.buttons["layerRowOverlay"].label.contains("天數、名稱"), "the settings are kept")

        // The record keeps both: back on the export page after a relaunch.
        Thread.sleep(forTimeInterval: 1)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["layerRowOverlay"].waitForExistence(timeout: 15))
        XCTAssertEqual(overlayToggle.value as? String, "0")
        XCTAssertEqual(filmToggle.value as? String, "1")
    }

    /// 718-5: list → 疊字 (樣式｜內容) → back → 底片日期 → back.
    func test_718_5_pushAndBack() {
        launch(overlayOn: true)
        XCTAssertTrue(element("exportCancelButton").exists, "xmark on the list")
        XCTAssertTrue(app.openLayer("layerRowOverlay", expecting: app.buttons["樣式"]))
        XCTAssertTrue(app.buttons["內容"].exists)
        XCTAssertTrue(element("exportTitle").label.contains("疊字"), element("exportTitle").label)
        XCTAssertFalse(element("exportCancelButton").exists, "back replaces xmark on a pushed page")
        XCTAssertFalse(element("layerHiddenNotice").exists)
        XCTAssertTrue(app.buttons["stylePreset_classic"].waitForExistence(timeout: 3) || app.buttons["樣式"].isSelected)
        Thread.sleep(forTimeInterval: 2)
        shot("overlay_detail_style")
        app.buttons["內容"].tap()
        XCTAssertTrue(app.switches["天數"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.switches["底片日期"].exists, "the 戳記 card is not here")
        shot("overlay_detail_content")
        XCTAssertTrue(app.backToLayerList())
        XCTAssertTrue(element("exportCancelButton").exists, "xmark again")

        XCTAssertTrue(app.openLayer("layerRowFilmDate", expecting: app.buttons["filmDateCorner_bottomLeading"]))
        XCTAssertTrue(element("exportTitle").label.contains("底片日期"), element("exportTitle").label)
        XCTAssertTrue(element("stampCard").exists)
        shot("film_detail")
        XCTAssertTrue(app.backToLayerList())
    }

    /// 718-6: a hidden layer's page is grey and untouchable; 顯示 turns it on.
    func test_718_6_hiddenPagesAreGreyAndShowRestores() {
        launch(overlayOn: false)
        XCTAssertTrue(app.openLayer("layerRowOverlay", expecting: element("layerHiddenNotice")))
        XCTAssertTrue(element("layerShowButton").exists)
        XCTAssertTrue(app.staticTexts["已隱藏，設定會保留"].exists)
        XCTAssertFalse(app.buttons["內容"].isEnabled, "greyed, no taps")
        XCTAssertFalse(app.buttons["stylePreset_classic"].isEnabled)
        Thread.sleep(forTimeInterval: 1)
        shot("overlay_hidden")
        app.buttons["layerShowButton"].tap()
        XCTAssertFalse(element("layerHiddenNotice").exists, "one tap shows it")
        XCTAssertTrue(app.buttons["內容"].isEnabled)
        XCTAssertTrue(drawsText() || textOnPreview.waitForExistence(timeout: 3), "the text is back on the preview")
        XCTAssertTrue(app.backToLayerList())
        XCTAssertEqual(overlayToggle.value as? String, "1")

        XCTAssertTrue(app.openLayer("layerRowFilmDate", expecting: element("layerHiddenNotice")))
        XCTAssertFalse(app.buttons["filmDateCorner_topTrailing"].isEnabled)
        shot("film_hidden")
        app.buttons["layerShowButton"].tap()
        XCTAssertTrue(app.buttons["filmDateCorner_topTrailing"].isEnabled)
        XCTAssertTrue(app.backToLayerList())
        XCTAssertEqual(filmToggle.value as? String, "1")
    }
}
