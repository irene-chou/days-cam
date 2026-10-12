import XCTest

/// TASK-115 (#446): every multi-weight font row ends in a chevron that expands
/// its weights without selecting the font. The chevron is folded into the row
/// for VoiceOver (a custom action), so the tests tap the row's trailing edge,
/// where the 44pt chevron sits. Screenshots are attached and, with
/// `DAYSCAM_UI_SHOT_DIR` in the runner's environment, also written as PNGs.
final class FontRowChevronUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        openFontPage()
    }

    private func openFontPage() {
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        if !app.buttons["樣式"].exists { app.buttons["疊字設定"].tap() }
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
        app.buttons["字型"].tap()
    }

    /// A font gets a chevron only once it is on the device, so these tests need
    /// `notoSerifTC-regular.otf` copied into the app's Application Support/Fonts
    /// (a download needs the network) and `TEST_RUNNER_DAYSCAM_UI_NOTO_SEEDED=1`.
    private func requireSeededNoto() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DAYSCAM_UI_NOTO_SEEDED"] == "1",
                          "seed notoSerifTC-regular.otf and set DAYSCAM_UI_NOTO_SEEDED=1")
    }

    private var pingFang: XCUIElement { app.buttons["蘋方-繁"] }
    /// 思源宋體 sits first in the 可下載 section; its label carries the state.
    private var noto: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Noto Serif TC'")).firstMatch
    }
    private func weight(_ id: String) -> XCUIElement { app.buttons["fontWeight.\(id)"] }

    /// Where the list starts on screen (the selected font's row at the top).
    /// The camera takes the rest, so the strip is short on an iPhone SE.
    private lazy var listTop: CGFloat = {
        _ = pingFang.waitForExistence(timeout: 5)
        return pingFang.frame.minY
    }()
    /// Where a drag starts: above the home indicator on a tall screen.
    private var listBottom: CGFloat {
        let height = app.windows.firstMatch.frame.height
        return height - (height > 800 ? 50 : 20)
    }

    /// Drags the list until `element` sits at the top of the list strip.
    private func scroll(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let maxStep = (listBottom - listTop) * 0.75
        for _ in 0..<25 {
            let delta = element.frame.minY - listTop
            if abs(delta) < 30 { return }
            // Already on screen, clear of the floating collapse button.
            if element.frame.minY >= listTop, element.frame.maxY <= listBottom - 70 { return }
            let step = min(abs(delta), maxStep)
            let startY = delta > 0 ? listBottom : listTop + 6
            let endY = delta > 0 ? startY - step : startY + step
            origin.withOffset(CGVector(dx: 60, dy: startY))
                .press(forDuration: 0.1,
                       thenDragTo: origin.withOffset(CGVector(dx: 60, dy: endY)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        XCTFail("could not scroll \(element) into view")
    }

    /// Drags the list back to its top, where the selected font sits.
    private func scrollToTop() {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<12 {
            origin.withOffset(CGVector(dx: 60, dy: listTop + 6))
                .press(forDuration: 0.1,
                       thenDragTo: origin.withOffset(CGVector(dx: 60, dy: listBottom)),
                       withVelocity: .fast, thenHoldForDuration: 0.2)
        }
    }

    /// The chevron: the trailing 44pt of the row.
    private func tapChevron(of row: XCUIElement) {
        scroll(row)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: row.frame.width - 22, dy: 0)).tap()
    }

    private func attach(_ name: String) {
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

    /// 115.2／115.8: the chevron of an unselected row expands it, shows every
    /// weight unframed, and leaves the selected font alone.
    func testChevronExpandsAnUnselectedRowWithoutApplying() throws {
        try requireSeededNoto()
        tapChevron(of: noto)
        XCTAssertTrue(weight("regular").waitForExistence(timeout: 3), "115.2 expanded")
        XCTAssertTrue(weight("bold").exists && weight("black").exists)
        XCTAssertFalse(weight("regular").isSelected || weight("bold").isSelected || weight("black").isSelected,
                       "115.2 no yellow frame")
        XCTAssertTrue(noto.label.contains("未下載"), "115.8 the chevron did not start applying/downloading the font")
        tapChevron(of: noto)
        XCTAssertFalse(weight("regular").waitForExistence(timeout: 2), "the chevron collapses it again")
        scrollToTop()
        XCTAssertTrue(pingFang.waitForExistence(timeout: 5))
        XCTAssertTrue(pingFang.isSelected, "115.2 the selected font is unchanged")
        XCTAssertEqual(pingFang.value as? String, "粗")
    }

    /// 115.4: expanding another row collapses the open one.
    func testOnlyOneRowStaysExpanded() throws {
        try requireSeededNoto()
        tapChevron(of: noto)
        XCTAssertTrue(weight("regular").waitForExistence(timeout: 3))
        scrollToTop()
        tapChevron(of: pingFang)
        XCTAssertTrue(weight("light").waitForExistence(timeout: 3), "PingFang expanded")
        XCTAssertFalse(weight("black").exists, "115.4 思源宋體 collapsed")
        XCTAssertTrue(pingFang.isSelected)
    }

    /// 115.3 end to end, with the B′ shots: choosing a usable weight of an
    /// unselected font applies font and weight together, keeps the card open
    /// and frames that weight (needs the seeded face, see `requireSeededNoto`).
    func testChoosingAWeightOfAnotherFontAppliesBoth() throws {
        try requireSeededNoto()
        XCTAssertTrue(pingFang.waitForExistence(timeout: 5))
        attach("115.1_font-page-initial")
        tapChevron(of: noto)
        XCTAssertTrue(weight("regular").waitForExistence(timeout: 3))
        scroll(noto)
        attach("115.2_unselected-row-expanded")
        scroll(weight("regular"))
        weight("regular").tap()
        let applied = NSPredicate(format: "isSelected == true")
        expectation(for: applied, evaluatedWith: weight("regular"))
        waitForExpectations(timeout: 20)
        XCTAssertTrue(weight("bold").exists, "115.3 stays expanded")
        XCTAssertFalse(weight("bold").isSelected)
        scroll(noto)
        attach("115.3_weight-applied")
        app.terminate()
        app.launch()
        openFontPage()
        XCTAssertTrue(noto.waitForExistence(timeout: 5))
        XCTAssertTrue(noto.isSelected, "115.3 still selected after relaunch")
        XCTAssertEqual(noto.value as? String, "標準", "115.3 the weight is kept")
    }
}
