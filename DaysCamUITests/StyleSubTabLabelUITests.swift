import XCTest

/// TASK-110 (#424): the five style sub-tabs carry a caption under the icon.
final class StyleSubTabLabelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        app.buttons["疊字設定"].tap()
        let styleTab = app.buttons["樣式"]
        XCTAssertTrue(styleTab.waitForExistence(timeout: 5))
        styleTab.tap()
    }

    /// 110.1／110.5: every sub-tab is one button named by its caption, and the
    /// caption itself is not a second accessibility element.
    func testEverySubTabIsOneNamedButton() {
        for name in ["字型", "顏色", "外框", "陰影", "字級"] {
            let button = app.buttons[name]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "110.1 \(name) 子分頁")
            XCTAssertEqual(button.label, name, "110.5 子分頁只念一次名稱")
        }
    }

    /// 110.3: on the narrowest phone the five items sit on one row.
    func testFiveSubTabsShareOneRow() {
        let frames = ["字型", "顏色", "外框", "陰影", "字級"].map { app.buttons[$0].frame }.sorted { $0.minX < $1.minX }
        let minY = frames.map(\.minY).min() ?? 0
        let maxY = frames.map(\.minY).max() ?? 0
        XCTAssertLessThan(maxY - minY, 1, "110.3 五個子分頁同一列")
        for (left, right) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(left.maxX, right.minX + 0.5, "110.3 不重疊")
        }
    }

    /// 110.4: the outline and shadow pages still open and expose their options
    /// below the taller sub-tab row.
    func testOutlineAndShadowPagesStillOperate() {
        app.buttons["外框"].tap()
        XCTAssertTrue(app.buttons["無外框"].waitForExistence(timeout: 5), "110.4 外框頁選項")
        app.buttons["陰影"].tap()
        XCTAssertTrue(app.buttons["無陰影"].waitForExistence(timeout: 5), "110.4 陰影頁選項")
    }
}
