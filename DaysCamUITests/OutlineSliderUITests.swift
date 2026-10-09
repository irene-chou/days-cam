import XCTest

/// The outline sub-tab's 描邊 / 底框 sliders end to end (TASK-70, 70.1). The
/// app starts from a fresh profile via `-UITestFreshProfiles`.
final class OutlineSliderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestFreshProfiles"]
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        app.buttons["樣式"].tap()
        app.buttons["外框"].tap()
    }

    private var strokeSlider: XCUIElement { app.sliders["outlineStrokeWidthSlider"] }
    private var paddingSlider: XCUIElement { app.sliders["outlineBoxPaddingSlider"] }

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
        XCTAssertEqual(strokeSlider.value as? String, "6 點")
        app.buttons["底框"].tap()
        app.buttons["描邊"].tap()
        XCTAssertEqual(strokeSlider.value as? String, "6 點")
    }

    /// The disabled opacity row (outline 無) is audited for the plain chip.
    func testDisabledOpacityRowShowsForNone() {
        XCTAssertTrue(app.sliders["外框透明度"].waitForExistence(timeout: 3))
        attach("outline-none-disabled-chip")
    }
}
