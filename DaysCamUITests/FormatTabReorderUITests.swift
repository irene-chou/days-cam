import XCTest

/// #558: the content tab is three cards, 文字內容 → 天數單位 → 戳記, every
/// row words-left, control-right; with the day count off 天數單位 collapses
/// and the switches above stay put (TASK-141 #485). With
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
        XCTAssertTrue(seeding.buttons["疊字設定"].waitForExistence(timeout: 10))
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-10-12"
        app.launch()
        app.buttons["疊字設定"].tap()
        let content = app.buttons["內容"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        XCTAssertTrue(app.buttons["天"].waitForExistence(timeout: 5))
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
    private let ageWording = "「年」改成「歲」"
    /// The countdown note under the age-wording switch was dropped (PR #497).
    private var countdownNote: XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "倒數時寫作")).firstMatch
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
        let bottomBand: CGFloat = app.frame.height >= 812 ? 50 : 8
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

    /// #558.1／.2／.5／.6／.10: card order top to bottom, every switch on the
    /// same right edge, the corners in one row, nothing named 位置 but the
    /// 位置 row, the stamp note always there; with the B′ shot (a).
    func testCardsReadTopToBottomWithOneRightEdge() {
        launch(startDay: "2023-08-05")
        XCTAssertFalse(element("formatDivider").exists, "#558.6 no divider")
        // 年 checked too, for shot (a); the tap may scroll a short screen.
        app.buttons["年"].tap()
        scrollToTop()
        let rightEdge = toggle("名稱").frame.maxX
        for name in ["天數", "日期"] {
            XCTAssertEqual(toggle(name).frame.maxX, rightEdge, accuracy: 1, "#558.2 \(name)")
        }
        XCTAssertLessThan(app.staticTexts["文字內容"].frame.maxX, app.frame.width / 2, "#558.2 heading on the left")
        assertTopToBottom(pairs: [app.staticTexts["文字內容"], toggle("天數"), toggle("日期"), toggle("名稱"),
                                  app.buttons["positionRow"], app.staticTexts["天數單位"], app.buttons["天"], toggle(ageWording),
                                  app.staticTexts["戳記"], toggle("底片日期")], "#558.1")
        for name in [ageWording, "底片日期"] {
            XCTAssertEqual(toggle(name).frame.maxX, rightEdge, accuracy: 1, "#558.2 \(name)")
        }
        let note = app.staticTexts["底片日期的字樣固定，不受「樣式」分頁和文字位置影響。"]
        XCTAssertTrue(note.exists, "#558.10 note while off")

        set("底片日期", on: true)
        let corners = ["topLeading", "topTrailing", "bottomLeading", "bottomTrailing"].map { app.buttons["filmDateCorner_\($0)"] }
        // The row opens below the panel's edge on a taller screen.
        scrollTo(corners[0])
        assertTopToBottom(pairs: [toggle("底片日期"), corners[0], note], "#558.1 lower part")
        let xs = corners.map(\.frame.minX)
        XCTAssertEqual(xs, xs.sorted(), "#558.5 左上、右上、左下、右下 left to right")
        for corner in corners {
            XCTAssertEqual(corner.frame.midY, corners[0].frame.midY, accuracy: 1, "#558.5 one row")
            XCTAssertGreaterThanOrEqual(corner.frame.width, 44, "#558.5 44pt wide")
            XCTAssertGreaterThanOrEqual(corner.frame.height, 44, "#558.5 44pt tall")
        }
        XCTAssertTrue(corners[2].isSelected, "#558.5 左下 by default")
        XCTAssertEqual(corners[2].label, "底片日期位置，左下")
        // #568: the 位置 tab is gone, so the 位置 row is the only thing named so.
        let places = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "位置")).allElementsBoundByIndex
        // A hair of slack: the row's frame can come back a few ulps right
        // of its own label's (26.000000000000057 vs 26.0 on iPhone 16).
        let positionRow = app.buttons["positionRow"].frame.insetBy(dx: -0.5, dy: -0.5)
        XCTAssertTrue(places.allSatisfy { positionRow.contains($0.frame) },
                      "#558.6 位置 only on the 位置 row: \(places.map { "\($0.label) \($0.frame)" })")
    }

    /// B′ shot (a): everything on, 左下, in as many screens as it takes.
    func testAllOnShots() {
        launch(startDay: "2023-08-05")
        toggle("日期").tap()
        app.buttons["年"].tap()
        scrollToTop()
        XCTAssertTrue(isOn(toggle("天數")) && isOn(toggle("日期")) && isOn(toggle("名稱")), "all text on")
        shot("558.12a_all_on_1_text")
        scrollTo(toggle(ageWording))
        XCTAssertTrue(isOnScreen(app.buttons["年"]), "units card in the shot")
        shot("558.12a_all_on_2_units")
        scrollTo(toggle("底片日期"))
        set("底片日期", on: true)
        let note = app.staticTexts["底片日期的字樣固定，不受「樣式」分頁和文字位置影響。"]
        scrollTo(app.buttons["filmDateCorner_bottomLeading"])
        scrollTo(note)
        XCTAssertTrue(isOnScreen(toggle("底片日期")) && isOnScreen(app.buttons["filmDateCorner_bottomLeading"]), "stamp card in the shot")
        shot("558.12a_all_on_3_stamp")
    }

    /// #558.4: the corner row collapses while off and the corner is kept.
    func testCornerRowCollapsesAndKeepsTheCorner() {
        launch(startDay: "2023-08-05")
        scrollTo(toggle("底片日期"))
        XCTAssertFalse(element("filmDateCorners").exists, "#558.4 no corner row while off")
        set("底片日期", on: true)
        let topTrailing = app.buttons["filmDateCorner_topTrailing"]
        scrollTo(topTrailing)
        topTrailing.tap()
        XCTAssertTrue(topTrailing.isSelected)
        set("底片日期", on: false)
        XCTAssertFalse(topTrailing.exists, "#558.4 collapsed")
        set("底片日期", on: true)
        scrollTo(topTrailing)
        XCTAssertTrue(topTrailing.isSelected, "#558.4 右上 kept")
    }

    /// #558.3 on a past start date: with the day count off the 天數單位 card
    /// and heading go, the switches stay put, ticks are kept; B′ shot (b).
    func testOrderAndCollapseOnAPastStartDate() {
        launch(startDay: "2023-08-05")
        scrollTo(app.buttons["週"])
        app.buttons["週"].tap()
        // A tap low on a short screen scrolls the panel, and collapsing a
        // scrolled panel pulls everything down as it clamps; measure from
        // the top, where a collapse below cannot move the switches.
        scrollToTop()
        let framesAfterTap = ["天數", "日期", "名稱"].map { toggle($0).frame }

        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        XCTAssertFalse(app.staticTexts["天數單位"].exists, "#558.3 heading collapsed")
        XCTAssertFalse(element("dayCountUnitsCard").exists, "#558.3 card collapsed")
        XCTAssertFalse(app.buttons["週"].exists, "#558.3 collapsed")
        // Sub-point x jitter from re-layout is not a move; compare to 1pt.
        for (name, before) in zip(["天數", "日期", "名稱"], framesAfterTap) {
            let after = toggle(name).frame
            XCTAssertEqual(after.minY, before.minY, accuracy: 1, "#558.3 \(name) did not move")
            XCTAssertEqual(after.minX, before.minX, accuracy: 1, "#558.3 \(name) did not move")
        }
        shot("558.12b_daycount_and_film_off_1_text")
        let note = app.staticTexts["底片日期的字樣固定，不受「樣式」分頁和文字位置影響。"]
        scrollTo(note)
        XCTAssertTrue(isOnScreen(toggle("底片日期")), "stamp card in the shot")
        shot("558.12b_daycount_and_film_off_2_stamp")
        scrollToTop()

        toggle("天數").tap()
        Thread.sleep(forTimeInterval: 0.5)
        scrollTo(app.buttons["週"])
        XCTAssertTrue(app.buttons["週"].isSelected && app.buttons["天"].isSelected, "#558.3 ticks kept")
    }

    /// The (c) shot: the 文字內容 hint on its heading line.
    func testContentHintShot() {
        launch(startDay: "2023-08-05")
        toggle("日期").tap()
        toggle("天數").tap()
        XCTAssertFalse(isOn(toggle("天數")))
        toggle("日期").tap()
        XCTAssertTrue(isOn(toggle("日期")), "springs back")
        let hint = app.staticTexts["contentSwitchHint"]
        let shown = NSPredicate(format: "label == '至少顯示天數或日期'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shown, object: hint)], timeout: 2), .completed)
        shot("558.12c_content_hint")
    }

    /// A future start date with 歲 on: no countdown note under the
    /// age-wording switch (141.5 dropped, PR #497).
    func testNoCountdownNoteOnAFutureStartDate() {
        launch(startDay: "2027-01-16")
        scrollTo(toggle(ageWording))
        toggle(ageWording).tap()
        XCTAssertTrue(isOn(toggle(ageWording)))
        XCTAssertTrue(app.buttons["歲"].exists, "#558.9 the year reads 歲")
        app.buttons["月"].tap()
        XCTAssertFalse(countdownNote.exists, "no countdown note")
    }
}
