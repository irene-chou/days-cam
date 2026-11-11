import XCTest

/// #521 (TASK-152), #718: the 底片日期 layer — its switch on the layer list and
/// its 位置 corner picker on its own page. With `DAYSCAM_UI_SHOT_DIR` in the
/// test runner's environment the B′ screenshots are also written there for
/// the PR.
final class FilmDatePanelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(entersOverlayDetail: false), "the export page is up")
        XCTAssertTrue(app.buttons["layerRowFilmDate"].waitForExistence(timeout: 10))
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

    private var filmSwitch: XCUIElement { app.switches["layerToggleFilmDate"] }
    private func cornerButton(_ raw: String) -> XCUIElement { app.buttons["filmDateCorner_\(raw)"] }
    private var corners: [String] { ["topLeading", "topTrailing", "bottomLeading", "bottomTrailing"] }

    private func openFilmDatePage() {
        XCTAssertTrue(app.openLayer("layerRowFilmDate", expecting: app.buttons["filmDateCorner_bottomLeading"]),
                      "底片日期 pushes its corner picker")
    }

    /// 152.1／152.2／152.3: off by default on the list; the corner picker is
    /// on its own page, 左下 selected, every cell 44pt and on screen.
    func testSwitchOnTheListAndCornersOnThePage() {
        XCTAssertEqual(filmSwitch.value as? String, "0", "off by default")
        filmSwitch.tap()
        XCTAssertEqual(filmSwitch.value as? String, "1")

        openFilmDatePage()
        XCTAssertTrue(cornerButton("bottomLeading").isSelected)
        XCTAssertFalse(cornerButton("topTrailing").isSelected)
        let bar = app.buttons["panelBackButton"].frame.maxY
        for raw in corners {
            let frame = cornerButton(raw).frame
            XCTAssertGreaterThanOrEqual(frame.width, 44)
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            XCTAssertLessThanOrEqual(frame.maxX, app.frame.width, "no horizontal scroll needed")
            XCTAssertGreaterThanOrEqual(frame.minY, bar, "\(raw) under the top row")
            XCTAssertLessThanOrEqual(frame.maxY, app.frame.height, "\(raw) above the screen edge")
        }
        XCTAssertTrue(app.staticTexts["底片日期的字樣固定，不受「樣式」分頁和文字位置影響。"].exists)
        XCTAssertFalse(app.switches["底片日期"].exists, "the switch is only on the list")
        shot("PR718_filmdate_on_bottomLeading")

        cornerButton("topTrailing").tap()
        XCTAssertTrue(cornerButton("topTrailing").isSelected)
        XCTAssertEqual(cornerButton("topTrailing").label, "底片日期位置，右上")
        XCTAssertTrue(app.backToLayerList())
        let summary = app.buttons["layerRowFilmDate"].label
        XCTAssertTrue(summary.contains("右上角"), summary)
    }

    /// 152.3／718-6: the page is greyed and untouchable while the layer is off,
    /// the corner is kept, and 顯示 turns the layer on.
    func testOffPageIsGreyAndShowKeyRestoresIt() {
        filmSwitch.tap()
        openFilmDatePage()
        cornerButton("topLeading").tap()
        XCTAssertTrue(app.backToLayerList())
        filmSwitch.tap()
        XCTAssertEqual(filmSwitch.value as? String, "0")

        openFilmDatePage()
        XCTAssertTrue(app.descendants(matching: .any)["layerHiddenNotice"].exists)
        XCTAssertFalse(cornerButton("topLeading").isEnabled, "greyed, no taps")
        XCTAssertTrue(cornerButton("topLeading").isSelected, "the corner is kept")
        shot("PR718_filmdate_hidden")
        app.buttons["layerShowButton"].tap()
        XCTAssertTrue(cornerButton("topLeading").isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["layerHiddenNotice"].exists)
        XCTAssertTrue(app.backToLayerList())
        XCTAssertEqual(filmSwitch.value as? String, "1")
    }

    func testLargestDynamicTypeKeepsLabelsApart() {
        // 152.8 relaunch at the largest accessibility size; the shot is for
        // the truncation check, the frames for overlap.
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.waitForExportPage(), "the export page is up")
        XCTAssertTrue(app.buttons["layerRowFilmDate"].waitForExistence(timeout: 5))
        if filmSwitch.value as? String != "1" { filmSwitch.tap() }
        shot("PR718_152.8_largestText_list")
        openFilmDatePage()
        // #558: the corners sit in one row with their names under them;
        // at this size they must still not run into each other.
        let frames = corners.map { cornerButton($0).frame }
        for (left, right) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(left.maxX, right.minX + 0.5, "corners apart")
        }
        shot("PR718_152.8_largestText")
    }
}
