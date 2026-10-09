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
        app.launchArguments += ["-UITestFreshProfiles", profileName]
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
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

    /// 70.1: three options, and no slider while 無 is selected.
    func testOnlyThreeOptionsAndNoSliderForNone() {
        XCTAssertTrue(app.buttons["無外框"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["描邊"].exists)
        XCTAssertTrue(app.buttons["底框"].exists)
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

    /// 70.3 / 70.4: dragging writes through, and the value survives a relaunch
    /// of the panel page (switching away and back).
    func testDraggingChangesTheValueAndItIsKept() {
        app.buttons["描邊"].tap()
        XCTAssertTrue(strokeSlider.waitForExistence(timeout: 3))
        strokeSlider.adjust(toNormalizedSliderPosition: 1)
        // The drag can stop one step short of the end (5.5 of 6).
        let dragged = points(strokeSlider)
        XCTAssertGreaterThanOrEqual(dragged, 5.5)
        app.buttons["底框"].tap()
        app.buttons["描邊"].tap()
        XCTAssertEqual(points(strokeSlider), dragged)
        app.terminate()
        app.launch()
        app.buttons["疊字設定"].tap()
        app.buttons["樣式"].tap()
        app.buttons["外框"].tap()
        XCTAssertTrue(strokeSlider.waitForExistence(timeout: 3), "relaunch finds the same profile")
        XCTAssertEqual(points(strokeSlider), dragged, "70.4")
    }

    /// The disabled opacity row (outline 無) is audited for the plain chip.
    func testDisabledOpacityRowShowsForNone() {
        XCTAssertTrue(app.sliders["外框透明度"].waitForExistence(timeout: 3))
        attach("outline-none-disabled-chip")
    }
}
