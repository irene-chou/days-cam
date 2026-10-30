import XCTest

/// The outline sub-tab's 描邊 / 底框 sliders end to end (TASK-70, 70.1). The
/// app starts from a fresh profile via `-UITestFreshProfiles <name>`; the
/// name is per test case, so a relaunch inside one test finds its profile.
final class OutlineSliderUITests: XCTestCase {
    private var app: XCUIApplication!
    private var profileName = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        profileName = UUID().uuidString
        XCTAssertTrue(app.launchOnExportPage(profiles: profileName), "the export page is up")
        app.buttons["樣式"].tap()
        app.buttons["外框"].tap()
    }

    private var strokeSlider: XCUIElement { app.sliders["描邊粗細"] }
    private var paddingSlider: XCUIElement { app.sliders["底框留白"] }

    /// The slider's value as a number: its accessibility value reads "5.5 點".
    private func points(_ slider: XCUIElement) -> Double {
        Double((slider.value as? String ?? "").split(separator: " ").first ?? "") ?? -1
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 70.1 / 81.1: four options, and no slider while 無 is selected.
    func testFourOptionsAndNoSliderForNone() {
        XCTAssertTrue(app.buttons["無外框"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["描邊"].exists)
        XCTAssertTrue(app.buttons["底框"].exists)
        XCTAssertTrue(app.buttons["直角底框"].exists)
        XCTAssertFalse(strokeSlider.exists)
        XCTAssertFalse(paddingSlider.exists)
        attach("outline-none")
    }

    /// 70.1 / 70.3: 描邊 shows 粗細, 底框 shows 留白, and switching swaps them.
    func testSlidersAppearAndSwitchWithTheOutline() {
        app.buttons["描邊"].tap()
        XCTAssertTrue(strokeSlider.waitForExistence(timeout: 3))
        XCTAssertFalse(paddingSlider.exists)
        XCTAssertEqual(strokeSlider.value as? String, "2 點")
        attach("outline-stroke")

        app.buttons["底框"].tap()
        XCTAssertTrue(paddingSlider.waitForExistence(timeout: 3))
        XCTAssertFalse(strokeSlider.exists)
        XCTAssertEqual(paddingSlider.value as? String, "12 點")
        attach("outline-box")

        app.buttons["無外框"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: paddingSlider)
        waitForExpectations(timeout: 3)
    }

    /// 81.1 / 81.3: 直角底框 is the fourth option, shows the same 留白 slider and
    /// keeps its value when switching with 底框.
    func testSquareBoxOptionSharesThePaddingSlider() {
        XCTAssertTrue(app.buttons["直角底框"].waitForExistence(timeout: 3))
        app.buttons["底框"].tap()
        XCTAssertTrue(paddingSlider.waitForExistence(timeout: 3))
        paddingSlider.adjust(toNormalizedSliderPosition: 1)
        let dragged = points(paddingSlider)
        XCTAssertGreaterThanOrEqual(dragged, 23, "dragged toward the end of 0...24")
        app.buttons["直角底框"].tap()
        XCTAssertTrue(app.buttons["直角底框"].isSelected)
        XCTAssertTrue(paddingSlider.exists, "same slider for the square box")
        XCTAssertEqual(points(paddingSlider), dragged, "81.3")
        attach("outline-square-box")
        app.buttons["底框"].tap()
        XCTAssertEqual(points(paddingSlider), dragged, "81.3")
    }

    /// 70.3 / 70.4: dragging writes through, and the value survives a relaunch
    /// of the panel page (switching away and back).
    func testDraggingChangesTheValueAndItIsKept() {
        app.buttons["描邊"].tap()
        XCTAssertTrue(strokeSlider.waitForExistence(timeout: 3))
        strokeSlider.adjust(toNormalizedSliderPosition: 1)
        // On a slow CI runner the synthesized drag can stop well short; drag
        // once more before checking. It can still stop one step short (5.5 of 6).
        if points(strokeSlider) < 5.5 { strokeSlider.adjust(toNormalizedSliderPosition: 1) }
        let dragged = points(strokeSlider)
        XCTAssertGreaterThanOrEqual(dragged, 5.5)
        app.buttons["底框"].tap()
        app.buttons["描邊"].tap()
        XCTAssertEqual(points(strokeSlider), dragged)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.waitForExportPage(), "the export page is up")
        app.buttons["樣式"].tap()
        app.buttons["外框"].tap()
        XCTAssertTrue(strokeSlider.waitForExistence(timeout: 3), "relaunch finds the same profile")
        XCTAssertEqual(points(strokeSlider), dragged, "70.4")
    }

    /// 113.1: the outline page has no opacity row any more; opacity lives in
    /// the color picker only (TASK-113).
    func testOutlinePageHasNoOpacityRow() {
        XCTAssertTrue(app.buttons["描邊"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.sliders["外框不透明度"].exists, "113.1")
        attach("outline-none-no-opacity-row")
    }
}
