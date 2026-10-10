import XCTest

/// Taps outside the open panel collapse it (TASK-97, #401: 97.1–97.5, 97.8,
/// 97.9). The app starts from a fresh profile via `-UITestFreshProfiles` and
/// skips the first-launch tour.
///
/// Screenshots are attached to the result; with `DAYSCAM_UI_SHOT_DIR` in
/// the test runner's environment they are also written there as PNGs.
final class PanelOutsideTapUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
    }

    private var panelButton: XCUIElement { app.buttons["疊字設定"] }
    private var styleTab: XCUIElement { app.buttons["樣式"] }
    private var grabber: XCUIElement { app.descendants(matching: .any)["panelGrabber"] }
    private var profileChip: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '設定檔：'")).firstMatch
    }
    private var ratioButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '比例：'")).firstMatch
    }

    private func openPanel() {
        XCTAssertTrue(panelButton.waitForExistence(timeout: 10))
        panelButton.tap()
        XCTAssertTrue(styleTab.waitForExistence(timeout: 5), "the panel opened")
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))
    }

    private func assertPanelOpen(_ note: String) {
        XCTAssertTrue(styleTab.waitForExistence(timeout: 2), note)
        XCTAssertTrue(grabber.exists, note)
    }

    private func assertPanelClosed(_ note: String) {
        XCTAssertTrue(app.buttons["快門"].waitForExistence(timeout: 3), note)
        XCTAssertFalse(styleTab.exists, note)
        XCTAssertFalse(grabber.exists, note)
    }

    private func tap(x: CGFloat, y: CGFloat) {
        let window = app.windows.firstMatch
        let origin = window.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: x, dy: y)).tap()
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

    /// 97.2: the blank space left of the (3:4, narrowed) viewfinder.
    func testTapBesideTheViewfinderCollapses() {
        openPanel()
        attach("97.2_panel-open")
        let headerBottom = profileChip.frame.maxY
        let panelTop = grabber.frame.minY
        tap(x: 3, y: (headerBottom + panelTop) / 2)
        assertPanelClosed("97.2 a tap beside the viewfinder collapses the panel")
    }

    /// 97.3: the gap between the viewfinder's bottom and the panel's top.
    func testTapInTheGapAboveThePanelCollapses() {
        openPanel()
        tap(x: app.windows.firstMatch.frame.midX, y: grabber.frame.minY - 3)
        assertPanelClosed("97.3 a tap in the gap collapses the panel")
    }

    /// 97.4: blank toolbar space between the profile chip and the ratio button.
    func testTapBetweenToolbarButtonsCollapses() {
        openPanel()
        let chip = profileChip.frame
        let ratio = ratioButton.frame
        tap(x: (chip.maxX + ratio.minX) / 2, y: chip.midY)
        assertPanelClosed("97.4 a tap between toolbar buttons collapses the panel")
    }

    /// 97.5: the toolbar's buttons keep working and leave the panel open.
    func testToolbarButtonsLeaveThePanelOpen() {
        openPanel()
        let before = ratioButton.label
        ratioButton.tap()
        assertPanelOpen("97.5 the panel stays open after the ratio button")
        XCTAssertNotEqual(ratioButton.label, before, "97.5 the ratio still cycled")
        // The simulator has no camera, so flip is disabled there and a tap on
        // a disabled button falls through to the tap layer; only a live
        // flip button is part of 97.5.
        if app.buttons["翻轉鏡頭"].isEnabled {
            app.buttons["翻轉鏡頭"].tap()
            assertPanelOpen("97.5 flip leaves the panel open")
        }
        app.buttons["相機設定"].tap()
        XCTAssertTrue(app.buttons["閃光燈"].waitForExistence(timeout: 3), "97.5 the tools capsule opened")
        assertPanelOpen("97.5 the tools toggle leaves the panel open")
        attach("97.5_capsule-over-open-panel")
        // 97.6: with the capsule up, a tap outside closes only the capsule.
        tap(x: 3, y: (profileChip.frame.maxY + grabber.frame.minY) / 2)
        XCTAssertFalse(app.buttons["閃光燈"].waitForExistence(timeout: 1), "97.6 the capsule closed")
        assertPanelOpen("97.6 the panel is still open after the first tap")
        tap(x: 3, y: (profileChip.frame.maxY + grabber.frame.minY) / 2)
        assertPanelClosed("97.6 the second tap closes the panel")
        profileChip.tap()
        XCTAssertTrue(app.navigationBars["設定檔"].waitForExistence(timeout: 5), "97.5 the profile chip still opens the sheet")
    }

    /// 97.8: taps inside the panel never collapse it; the grabber strip does
    /// (TASK-92 — the whole 24pt strip at the top is the handle, so "beside
    /// the bar" within that strip is the grabber, not blank panel space).
    func testTapsInsideThePanelKeepItOpen() {
        openPanel()
        let tabs = styleTab.frame
        let width = app.windows.firstMatch.frame.width
        tap(x: width / 2, y: tabs.maxY + 40)
        assertPanelOpen("97.8 inside the content area")
        tap(x: 12, y: tabs.maxY + 90)
        assertPanelOpen("97.8 the content area's left margin")
        tap(x: width - 12, y: app.windows.firstMatch.frame.maxY - 4)
        assertPanelOpen("97.8 the panel's home-indicator band")
        attach("97.8_panel-still-open")
        grabber.tap()
        assertPanelClosed("97.8 the grabber still collapses")
    }

    /// 97.9: with the panel closed there is no tap layer — the blank space
    /// beside the viewfinder does nothing.
    func testBlankSpaceDoesNothingWhileClosed() {
        XCTAssertTrue(panelButton.waitForExistence(timeout: 10))
        tap(x: 3, y: app.windows.firstMatch.frame.midY)
        XCTAssertTrue(panelButton.exists, "97.9 still the closed footer")
        XCTAssertFalse(styleTab.exists, "97.9 nothing opened")
    }
}
