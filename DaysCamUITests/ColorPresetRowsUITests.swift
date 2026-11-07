import XCTest

/// The text-color rows on the style page: since the #691 ruling one row of
/// nine colors (the light row of TASK-149 is gone), then rainbow and 最近.
/// With `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′
/// screenshots are also written there.
final class ColorPresetRowsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
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

    /// #691 ruling (plan A): one row of the nine colors, then rainbow and
    /// 最近 on the same nine columns within the width; the light row is gone
    /// (light tints come from the rainbow). A swatch picked has the ring on
    /// it alone.
    func testOneColorRowAboveTheRainbowIsAlignedAndSelectable() {
        let first = app.buttons["#FFFFFF"]
        XCTAssertLessThan(first.frame.midY, rainbow.frame.midY, "colors above the rainbow")
        XCTAssertEqual(rainbow.frame.midX, first.frame.midX, accuracy: 1, "rainbow on the grid")
        let last = app.buttons["#A307BA"]
        XCTAssertEqual(last.frame.midY, first.frame.midY, accuracy: 1, "nine on one row")
        XCTAssertLessThanOrEqual(last.frame.maxX, app.windows.firstMatch.frame.maxX, "no horizontal scrolling")
        XCTAssertEqual(first.frame.width, 32, accuracy: 1, "#691 32pt swatches")
        for dropped in ["#E5E5EA", "#48484A", "#92C6F7", "#FEC08E", "#CC77D9", "#AEAEB2", "#24629C"] {
            XCTAssertFalse(app.buttons[dropped].exists, "#691 dropped: \(dropped)")
        }
        shot("691_color")

        let recentBefore = recentCount
        app.buttons["#3897F0"].tap()
        XCTAssertTrue(app.buttons["#3897F0"].isSelected, "ring on the swatch")
        XCTAssertFalse(first.isSelected, "only one ring")
        XCTAssertFalse(rainbow.isSelected, "no ring on the rainbow")
        XCTAssertEqual(recentCount, recentBefore, "最近 unchanged")
        XCTAssertTrue(rainbow.isHittable, "the last row is in view")
    }
}
