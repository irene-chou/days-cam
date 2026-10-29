import XCTest

/// TASK-149 (#518): the text-color page adds a light row (the dark row and
/// film colors were dropped, PR #527); the outline and shadow pages do not. With `DAYSCAM_UI_SHOT_DIR` in
/// the test runner's environment the B′ screenshots are also written there.
final class ColorPresetRowsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString]
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

    /// 149.5／149.6: the swatches, the light row, then rainbow and 最近, on
    /// nine aligned columns within the width; a light swatch picked with the
    /// ring on it alone. No dark row or film colors (PR #527, 2026-10-13).
    func testTextColorRowsAreOrderedAlignedAndSelectable() {
        let firstColumn = ["#FFFFFF", "#E5E5EA"].map { app.buttons[$0] }
        let order = [firstColumn[0], firstColumn[1], rainbow].map(\.frame.midY)
        XCTAssertEqual(order, order.sorted(), "149.5 原色 → 淺色 → 彩虹: \(order)")
        XCTAssertEqual(firstColumn[1].frame.midX, firstColumn[0].frame.midX, accuracy: 1, "149.5 first column aligned")
        XCTAssertEqual(rainbow.frame.midX, firstColumn[0].frame.midX, accuracy: 1, "149.5 rainbow on the grid")
        let lastColumn = ["#A307BA", "#CC77D9"].map { app.buttons[$0] }
        XCTAssertEqual(lastColumn[1].frame.midX, lastColumn[0].frame.midX, accuracy: 1, "149.5 last column aligned")
        XCTAssertLessThanOrEqual(lastColumn[0].frame.maxX, app.windows.firstMatch.frame.maxX, "149.5 no horizontal scrolling")
        for dropped in ["#AEAEB2", "#24629C", "底片橘"] {
            XCTAssertFalse(app.buttons[dropped].exists, "dropped: \(dropped)")
        }
        XCTAssertFalse(app.staticTexts["底片日期色"].exists, "no film heading")
        shot("149.11_color")

        let recentBefore = recentCount
        app.buttons["#FEC08E"].tap()
        XCTAssertTrue(app.buttons["#FEC08E"].isSelected, "149.6 ring on the light swatch")
        XCTAssertFalse(app.buttons["#FFFFFF"].isSelected, "149.6 only one ring")
        XCTAssertFalse(rainbow.isSelected, "149.6 no ring on the rainbow")
        XCTAssertEqual(recentCount, recentBefore, "149.6 最近 unchanged")
        XCTAssertTrue(rainbow.isHittable, "149.9 the last row is in view")
        shot("149.11_color_light_selected")
    }

    /// 149.8: outline and shadow keep their one swatch row.
    func testOutlineAndShadowPagesHaveNoNewRows() {
        app.buttons["外框"].tap()
        XCTAssertTrue(app.buttons["描邊"].waitForExistence(timeout: 3))
        app.buttons["描邊"].tap()
        XCTAssertTrue(app.buttons["#3897F0"].waitForExistence(timeout: 3), "outline palette shows")
        for label in ["#E5E5EA", "#92C6F7", "#CC77D9"] {
            XCTAssertFalse(app.buttons[label].exists, "149.8 outline: \(label)")
        }
        shot("149.8_outline")

        app.buttons["陰影"].tap()
        XCTAssertTrue(app.buttons["柔和"].waitForExistence(timeout: 3))
        app.buttons["柔和"].tap()
        XCTAssertTrue(app.buttons["#3897F0"].waitForExistence(timeout: 3), "shadow palette shows")
        for label in ["#E5E5EA", "#92C6F7", "#CC77D9"] {
            XCTAssertFalse(app.buttons[label].exists, "149.8 shadow: \(label)")
        }
        shot("149.8_shadow")
    }
}
