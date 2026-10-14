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
        // The 戳記 card starts below the fold on iPhone SE (#558).
        XCTAssertTrue(app.switches["天數"].waitForExistence(timeout: 5))
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

    /// Scrolls the panel so the 底片日期 row sits just under the tab bar, then
    /// checks the switch and, when on, every corner cell are on screen: on
    /// iPhone SE they start below the panel's bottom edge, and a fixed drag
    /// over- or under-shoots, so the B′ shots missed the picker.
    private func showFilmDateBlock(file: StaticString = #filePath, line: UInt = #line) {
        let tabBottom = app.buttons["內容"].frame.maxY
        var trace: [String] = []
        for _ in 0..<3 {
            // Not in the tree yet means still below the fold.
            let gap = filmSwitch.exists ? filmSwitch.frame.minY - tabBottom : 200
            trace.append("\(Int(gap))")
            // Short drags snap unpredictably, so settle for anywhere close.
            if (4...60).contains(gap) { break }
            let offset = gap - 24
            let startY = (tabBottom + app.frame.height) / 2
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width * 0.08, dy: startY))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -offset)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertGreaterThanOrEqual(filmSwitch.frame.minY, tabBottom, "底片日期 switch under the tab bar, tab \(Int(tabBottom)) trace \(trace)", file: file, line: line)
        XCTAssertLessThanOrEqual(filmSwitch.frame.maxY, app.frame.height, file: file, line: line)
        guard filmSwitch.value as? String == "1" else { return }
        for raw in ["topLeading", "topTrailing", "bottomLeading", "bottomTrailing"] {
            let cell = cornerButton(raw)
            XCTAssertTrue(cell.exists, "\(raw) cell on screen", file: file, line: line)
            XCTAssertGreaterThanOrEqual(cell.frame.minY, tabBottom, "\(raw) cell under the tab bar", file: file, line: line)
            XCTAssertLessThanOrEqual(cell.frame.maxY, app.frame.height, "\(raw) cell above the screen edge", file: file, line: line)
        }
    }

    /// Drags the panel back down until 文字內容 is on screen again.
    private func scrollToTop() {
        let heading = app.staticTexts["文字內容"]
        for _ in 0..<8 where !(heading.exists && heading.frame.minY >= app.buttons["內容"].frame.maxY) {
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width * 0.08, dy: app.buttons["內容"].frame.maxY + 30))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 150)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    func testSwitchRowLayoutCornersAndCollapse() {
        // 152.1 in the 戳記 card below the text switches (#558 moved it;
        // the order is FormatTabReorderUITests'), right edge under 名稱's,
        // off by default.
        let nameMaxX = app.switches["名稱"].frame.maxX
        showFilmDateBlock()
        XCTAssertEqual(filmSwitch.frame.maxX, nameMaxX, accuracy: 1)
        XCTAssertEqual(filmSwitch.value as? String, "0")
        XCTAssertFalse(cornerButton("bottomLeading").exists)
        shot("PR_152.9_iPhoneSE_off")

        // 152.2 on: 位置 appears, bottom-left selected.
        filmSwitch.tap()
        // The row opens below the panel's edge on a taller screen.
        showFilmDateBlock()
        XCTAssertTrue(cornerButton("bottomLeading").exists)
        XCTAssertTrue(cornerButton("bottomLeading").isSelected)
        XCTAssertFalse(cornerButton("topTrailing").isSelected)
        for raw in ["topLeading", "topTrailing", "bottomLeading", "bottomTrailing"] {
            let frame = cornerButton(raw).frame
            XCTAssertGreaterThanOrEqual(frame.width, 44)
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            XCTAssertLessThanOrEqual(frame.maxX, app.frame.width, "no horizontal scroll needed")
        }
        showFilmDateBlock()
        shot("PR_152.9_iPhoneSE_on_bottomLeading")

        // 152.3 picking a corner, and it is kept across off/on.
        cornerButton("topTrailing").tap()
        XCTAssertTrue(cornerButton("topTrailing").isSelected)
        XCTAssertEqual(cornerButton("topTrailing").label, "底片日期位置，右上")
        showFilmDateBlock()
        shot("PR_152.9_iPhoneSE_on_topTrailing")
        filmSwitch.tap()
        XCTAssertFalse(cornerButton("topTrailing").exists, "collapsed when off")
        filmSwitch.tap()
        // The row opens below the panel's edge on a taller screen.
        showFilmDateBlock()
        XCTAssertTrue(cornerButton("topTrailing").exists)
        XCTAssertTrue(cornerButton("topTrailing").isSelected)

        // 152.6 day count off collapses the units, not the film date rows.
        scrollToTop()
        XCTAssertTrue(app.switches["日期"].exists)
        app.switches["日期"].tap()
        app.switches["天數"].coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertFalse(app.otherElements["dayCountUnits"].exists)
        showFilmDateBlock()
        XCTAssertTrue(cornerButton("topTrailing").exists, "corner row still there")
    }

    func testLargestDynamicTypeKeepsLabelsApart() {
        // 152.8 relaunch at the largest accessibility size; the shot is for
        // the truncation check, the frames for overlap.
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["疊字設定"].tap()
        app.buttons["內容"].tap()
        XCTAssertTrue(filmSwitch.waitForExistence(timeout: 5))
        showFilmDateBlock()
        filmSwitch.tap()
        // The row opens below the panel's edge on a taller screen.
        showFilmDateBlock()
        XCTAssertTrue(cornerButton("bottomLeading").exists)
        showFilmDateBlock()
        // #558: the corners sit in one row with their names under them;
        // at this size they must still not run into each other.
        let frames = ["topLeading", "topTrailing", "bottomLeading", "bottomTrailing"].map { cornerButton($0).frame }
        for (left, right) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(left.maxX, right.minX + 0.5, "corners apart")
        }
        shot("PR_152.8_iPhoneSE_largestText")
    }
}
