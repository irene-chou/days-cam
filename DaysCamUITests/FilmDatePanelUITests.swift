import XCTest

/// #521 (TASK-152): the 底片日期 switch and its 位置 corner picker on the
/// 內容 tab. With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the
/// B′ screenshots are also written there for the PR.
final class FilmDatePanelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        app.buttons["疊字設定"].tap()
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        content.tap()
        XCTAssertTrue(app.switches["底片日期"].waitForExistence(timeout: 5))
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

    private var filmSwitch: XCUIElement { app.switches["底片日期"] }
    private func cornerButton(_ raw: String) -> XCUIElement { app.buttons["filmDateCorner_\(raw)"] }

    /// Drags the panel content up so the corner picker is in view for the
    /// B′ shots: on iPhone SE it sits below the panel's bottom edge.
    private func revealCornerPicker() {
        let start = app.staticTexts["顯示內容"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)))
        Thread.sleep(forTimeInterval: 1)
    }

    func testSwitchRowLayoutCornersAndCollapse() {
        // 152.1 below the 天數｜日期｜名稱 row, right edge under 名稱's, off by default.
        let name = app.switches["名稱"]
        XCTAssertGreaterThan(filmSwitch.frame.minY, name.frame.maxY - 1)
        XCTAssertEqual(filmSwitch.frame.maxX, name.frame.maxX, accuracy: 1)
        XCTAssertEqual(filmSwitch.value as? String, "0")
        XCTAssertFalse(cornerButton("bottomLeading").exists)
        shot("PR_152.9_iPhoneSE_off")

        // 152.2 on: 位置 appears, bottom-left selected.
        filmSwitch.tap()
        XCTAssertTrue(cornerButton("bottomLeading").waitForExistence(timeout: 3))
        XCTAssertTrue(cornerButton("bottomLeading").isSelected)
        XCTAssertFalse(cornerButton("topTrailing").isSelected)
        for raw in ["topLeading", "topTrailing", "bottomLeading", "bottomTrailing"] {
            let frame = cornerButton(raw).frame
            XCTAssertGreaterThanOrEqual(frame.width, 44)
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            XCTAssertLessThanOrEqual(frame.maxX, app.frame.width, "no horizontal scroll needed")
        }
        revealCornerPicker()
        shot("PR_152.9_iPhoneSE_on_bottomLeading")

        // 152.3 picking a corner, and it is kept across off/on.
        cornerButton("topTrailing").tap()
        XCTAssertTrue(cornerButton("topTrailing").isSelected)
        XCTAssertEqual(cornerButton("topTrailing").label, "底片日期位置，右上")
        revealCornerPicker()
        shot("PR_152.9_iPhoneSE_on_topTrailing")
        filmSwitch.tap()
        XCTAssertFalse(cornerButton("topTrailing").exists, "collapsed when off")
        filmSwitch.tap()
        XCTAssertTrue(cornerButton("topTrailing").waitForExistence(timeout: 3))
        XCTAssertTrue(cornerButton("topTrailing").isSelected)

        // 152.6 day count off collapses the units, not the film date rows.
        XCTAssertTrue(app.switches["日期"].exists)
        app.switches["日期"].tap()
        app.switches["天數"].coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertFalse(app.otherElements["dayCountUnits"].exists)
        XCTAssertTrue(filmSwitch.exists)
    }
}
