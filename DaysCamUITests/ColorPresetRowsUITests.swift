import XCTest

/// TASK-149 (#518): the text-color page adds light, dark and film date-stamp
/// rows; the outline and shadow pages do not. With `DAYSCAM_UI_SHOT_DIR` in
/// the test runner's environment the B′ screenshots are also written there.
final class ColorPresetRowsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        app.buttons["疊字設定"].tap()
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
        app.buttons["顏色"].tap()
        XCTAssertTrue(app.buttons["#FFFFFF"].waitForExistence(timeout: 5))
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
            let device = UIDevice.current.name.filter { !$0.isWhitespace && $0 != "(" && $0 != ")" }
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR_\(name)_\(device).png"))
        }
    }

    private var rainbow: XCUIElement { app.buttons["自訂顏色"] }
    private var recentCount: Int {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '最近自訂 '")).count
    }

    /// 149.5／149.6: row order, nine aligned columns within the width, and a
    /// film color picked by name with the ring on it alone.
    func testTextColorRowsAreOrderedAlignedAndSelectable() {
        let firstColumn = ["#FFFFFF", "#E5E5EA", "#AEAEB2"].map { app.buttons[$0] } + [app.buttons["底片橘"]]
        let heading = app.staticTexts["底片日期色"]
        XCTAssertTrue(heading.exists && app.buttons["底片橘"].exists, "149.5 film row")
        let order = [firstColumn[0], firstColumn[1], firstColumn[2], heading, firstColumn[3], rainbow].map(\.frame.midY)
        XCTAssertEqual(order, order.sorted(), "149.5 原色 → 淺 → 深 → 小標 → 底片 → 彩虹: \(order)")
        for element in firstColumn.dropFirst() {
            XCTAssertEqual(element.frame.midX, firstColumn[0].frame.midX, accuracy: 1, "149.5 first column aligned")
        }
        XCTAssertEqual(rainbow.frame.midX, firstColumn[0].frame.midX, accuracy: 1, "149.5 rainbow on the grid")
        let lastColumn = ["#A307BA", "#CC77D9", "#6A0579"].map { app.buttons[$0] }
        for element in lastColumn.dropFirst() {
            XCTAssertEqual(element.frame.midX, lastColumn[0].frame.midX, accuracy: 1, "149.5 last column aligned")
        }
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(lastColumn[0].frame.maxX, window.maxX, "149.5 no horizontal scrolling")
        shot("149.11_color_top")

        let recentBefore = recentCount
        app.buttons["底片橘"].tap()
        XCTAssertTrue(app.buttons["底片橘"].isSelected, "149.6 ring on 底片橘")
        XCTAssertFalse(app.buttons["#FFFFFF"].isSelected, "149.6 only one ring")
        XCTAssertFalse(rainbow.isSelected, "149.6 no ring on the rainbow")
        XCTAssertEqual(recentCount, recentBefore, "149.6 最近 unchanged")
        let overlay = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '第 '")).firstMatch
        XCTAssertTrue(overlay.exists)
        shot("149.11_color_film_selected")

        app.buttons["#24629C"].tap()
        XCTAssertTrue(app.buttons["#24629C"].isSelected, "149.6 dark row")
        XCTAssertFalse(app.buttons["底片橘"].isSelected)
        XCTAssertFalse(rainbow.isSelected)

        // 149.9: the last row scrolls fully into view.
        app.buttons["#AEAEB2"].swipeUp()
        XCTAssertTrue(rainbow.isHittable, "149.9 the last row is reachable")
        shot("149.11_color_bottom")
    }

    /// 149.8: outline and shadow keep their one swatch row.
    func testOutlineAndShadowPagesHaveNoNewRows() {
        app.buttons["外框"].tap()
        XCTAssertTrue(app.buttons["描邊"].waitForExistence(timeout: 3))
        app.buttons["描邊"].tap()
        XCTAssertTrue(app.buttons["#3897F0"].waitForExistence(timeout: 3), "outline palette shows")
        for label in ["#E5E5EA", "#AEAEB2", "#92C6F7", "底片橘"] {
            XCTAssertFalse(app.buttons[label].exists, "149.8 outline: \(label)")
        }
        XCTAssertFalse(app.staticTexts["底片日期色"].exists, "149.8 outline")
        shot("149.8_outline")

        app.buttons["陰影"].tap()
        XCTAssertTrue(app.buttons["柔和"].waitForExistence(timeout: 3))
        app.buttons["柔和"].tap()
        XCTAssertTrue(app.buttons["#3897F0"].waitForExistence(timeout: 3), "shadow palette shows")
        for label in ["#E5E5EA", "#AEAEB2", "#92C6F7", "底片橘"] {
            XCTAssertFalse(app.buttons[label].exists, "149.8 shadow: \(label)")
        }
        XCTAssertFalse(app.staticTexts["底片日期色"].exists, "149.8 shadow")
        shot("149.8_shadow")
    }
}
