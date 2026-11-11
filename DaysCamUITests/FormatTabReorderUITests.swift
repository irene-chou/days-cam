import XCTest

/// #558: the content tab is one card, 文字內容 (the 戳記 card moved to the
/// 底片日期 page, #718; the units moved to the record editor, #721), every row
/// words-left, control-right; with the day count off the 寫法 row goes and the
/// switches above stay put. With
/// `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′
/// screenshots are also written there for the PR.
final class FormatTabReorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds the default profile with `startDay` as its start date, then
    /// relaunches on 2026-10-12 into the same profile directory and opens
    /// the content tab.
    private func launch(startDay: String) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = startDay
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-10-12"
        XCTAssertTrue(app.launchOnExportPage(profiles: profiles), "the export page is up")
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
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
            let device = UIDevice.current.name.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR_\(name)_\(device).png"))
        }
    }

    private func toggle(_ name: String) -> XCUIElement {
        let s = app.switches[name]
        return s.exists ? s : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }
    private func isOn(_ element: XCUIElement) -> Bool { (element.value as? String) == "1" }
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    /// Taps a switch until it reads `on`: right after a drag the panel can
    /// take the first tap as the end of its scroll.
    private func set(_ name: String, on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 where isOn(toggle(name)) != on {
            toggle(name).tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertEqual(isOn(toggle(name)), on, "\(name) \(on ? "on" : "off")", file: file, line: line)
    }
    private var tabBottom: CGFloat { app.buttons["內容"].frame.maxY }

    /// Whether `element` is in the tree and wholly between the tab bar and
    /// the home-indicator band, which swallows taps by design (92.7; a
    /// 4.7-inch screen has none, 92.12); a row clipped by the panel is not
    /// in the tree at all.
    private func isOnScreen(_ element: XCUIElement) -> Bool {
        let bottomBand = app.panelBottomBand
        return element.exists && element.frame.minY >= tabBottom && element.frame.maxY <= app.frame.height - bottomBand
    }

    /// Drags the panel up a little at a time until `element` is on screen:
    /// on iPhone SE the lower cards start below the fold, and `swipeUp` /
    /// `isHittable` are unreliable there, so drag by coordinate, slowly.
    private func scrollTo(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 where !isOnScreen(element) {
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width * 0.08, dy: (tabBottom + app.frame.height) / 2))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -100)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(isOnScreen(element), "\(element) on screen: exists \(element.exists) frame \(element.frame) tab \(tabBottom) screen \(app.frame.height)", file: file, line: line)
    }

    /// Drags the panel back down until 文字內容 is on screen again.
    private func scrollToTop() {
        let top = app.staticTexts["文字內容"]
        for _ in 0..<8 where !isOnScreen(top) {
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width * 0.08, dy: tabBottom + 30))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 150)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Asserts the elements run top to bottom, checking each neighbouring
    /// pair while both are on screen: iPhone SE shows only a few rows.
    private func assertTopToBottom(pairs elements: [XCUIElement], _ message: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        for (upper, lower) in zip(elements, elements.dropFirst()) {
            scrollTo(lower, file: file, line: line)
            XCTAssertTrue(isOnScreen(upper), "\(message): \(upper) still on screen with \(lower)", file: file, line: line)
            XCTAssertLessThan(upper.frame.midY, lower.frame.midY, "\(message): \(upper) above \(lower)", file: file, line: line)
        }
    }

    /// #558.1／.2／.6: card order top to bottom, every switch on the same
    /// right edge, nothing named 位置 but the 位置 row; #718: no 戳記 card and
    /// no 底片日期 switch on this tab any more.
    func testCardsReadTopToBottomWithOneRightEdge() {
        launch(startDay: "2023-08-05")
        XCTAssertFalse(element("formatDivider").exists, "#558.6 no divider")
        scrollToTop()
        let rightEdge = toggle("名稱").frame.maxX
        for name in ["天數", "日期"] {
            XCTAssertEqual(toggle(name).frame.maxX, rightEdge, accuracy: 1, "#558.2 \(name)")
        }
        XCTAssertLessThan(app.staticTexts["文字內容"].frame.maxX, app.frame.width / 2, "#558.2 heading on the left")
        assertTopToBottom(pairs: [app.staticTexts["文字內容"], toggle("天數"), toggle("日期"), toggle("名稱"),
                                  app.buttons["positionRow"], app.buttons["dayCountFormatRow"]],
                          "#558.1 #721.6 寫法 under 位置")
        XCTAssertFalse(app.staticTexts["天數單位"].exists, "#721.6 no 天數單位 heading")
        XCTAssertFalse(app.buttons["天"].exists || app.buttons["週"].exists, "#721.6 no unit checkboxes")
        XCTAssertFalse(toggle("「年」改成「歲」").exists, "#721.6 no 歲 switch")
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@",
            ["contentCard"])).count, 1, "#721.6 one card")
        XCTAssertFalse(app.staticTexts["戳記"].exists, "#718 the 戳記 card moved to the 底片日期 page")
        XCTAssertFalse(toggle("底片日期").exists, "#718 no 底片日期 switch here")
        XCTAssertFalse(element("stampCard").exists, "#718 no stamp card here")
        // #568: the 位置 tab is gone, so the 位置 row is the only thing named so.
        let places = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "位置")).allElementsBoundByIndex
        // A hair of slack: the row's frame can come back a few ulps right
        // of its own label's (26.000000000000057 vs 26.0 on iPhone 16).
        let positionRow = app.buttons["positionRow"].frame.insetBy(dx: -0.5, dy: -0.5)
        XCTAssertTrue(places.allSatisfy { positionRow.contains($0.frame) },
                      "#558.6 位置 only on the 位置 row: \(places.map { "\($0.label) \($0.frame)" })")
    }

    /// B′ shot (a): every text switch on, in as many screens as it takes.
    func testAllOnShots() {
        launch(startDay: "2023-08-05")
        toggle("日期").tap()
        scrollToTop()
        XCTAssertTrue(isOn(toggle("天數")) && isOn(toggle("日期")) && isOn(toggle("名稱")), "all text on")
        shot("558.12a_all_on_1_text")
        scrollTo(app.buttons["dayCountFormatRow"])
        XCTAssertTrue(isOnScreen(app.buttons["dayCountFormatRow"]), "寫法 row in the shot")
        shot("558.12a_all_on_2_format")
    }

    /// #558.3, #721.6 on a past start date: with the day count off the 寫法
    /// row goes, the switches stay put; B′ shot (b).
    func testOrderAndCollapseOnAPastStartDate() {
        launch(startDay: "2023-08-05")
        XCTAssertTrue(app.buttons["dayCountFormatRow"].exists, "寫法 row while the day count is on")
        // Measure from the top, where a collapse below cannot move the switches.
        scrollToTop()
        let framesAfterTap = ["天數", "日期", "名稱"].map { toggle($0).frame }

        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        XCTAssertFalse(app.buttons["dayCountFormatRow"].exists, "#721.6 寫法 row hidden")
        // Sub-point x jitter from re-layout is not a move; compare to 1pt.
        for (name, before) in zip(["天數", "日期", "名稱"], framesAfterTap) {
            let after = toggle(name).frame
            XCTAssertEqual(after.minY, before.minY, accuracy: 1, "#558.3 \(name) did not move")
            XCTAssertEqual(after.minX, before.minX, accuracy: 1, "#558.3 \(name) did not move")
        }
        shot("558.12b_daycount_and_film_off_1_text")
        scrollToTop()

        toggle("天數").tap()
        Thread.sleep(forTimeInterval: 0.5)
        scrollTo(app.buttons["dayCountFormatRow"])
        XCTAssertTrue(app.buttons["dayCountFormatRow"].exists, "#721.6 寫法 row back")
    }

    /// #713-6 shot: 天數／日期／名稱 all off, the viewfinder prints nothing.
    func testAllContentSwitchesOffShot() {
        launch(startDay: "2023-08-05")
        let overlay = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["overlayText", "overlayTextDraggable"])).firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "the text is there before")
        set("天數", on: false)
        set("日期", on: false)
        set("名稱", on: false)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(!overlay.exists || overlay.label.isEmpty, "#713-3 viewfinder draws nothing")
        XCTAssertFalse(app.staticTexts["至少顯示天數或日期"].exists, "#713-4 no hint")
        shot("713.6_content_all_off")
    }
}
