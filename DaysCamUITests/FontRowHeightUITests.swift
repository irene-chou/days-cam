import XCTest

/// TASK-123 (#462): selecting a font never changes its row height or moves the
/// rows below it. Needs `notoSerifTC.otf` (Bold) in the app's Application
/// Support/Fonts so a second multi-weight font can be selected without a
/// download, and `TEST_RUNNER_DAYSCAM_UI_NOTO_SEEDED=1`; otherwise it skips.
/// Screenshots are attached and, with `DAYSCAM_UI_SHOT_DIR` in the runner's
/// environment, also written there as PNGs.
final class FontRowHeightUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DAYSCAM_UI_NOTO_SEEDED"] == "1",
                          "seed notoSerifTC.otf and set DAYSCAM_UI_NOTO_SEEDED=1")
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        app.openCamera()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        if !app.buttons["樣式"].exists { app.buttons["疊字設定"].tap() }
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
        app.buttons["字型"].tap()
    }

    // The row holds an inner button with the same label, so take the first (outer) match.
    private var pingFang: XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH '蘋方'")).firstMatch }
    private var noto: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '思源宋體'")).firstMatch
    }
    private var heading: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == '開源字型'")).firstMatch
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

    private struct Layout: Equatable {
        let pingFangY: CGFloat
        let pingFangHeight: CGFloat
        let notoY: CGFloat
        let notoHeight: CGFloat
        let headingY: CGFloat
    }

    private func layout() -> Layout {
        Layout(pingFangY: pingFang.frame.minY, pingFangHeight: pingFang.frame.height,
               notoY: noto.frame.minY, notoHeight: noto.frame.height,
               headingY: heading.frame.minY)
    }

    /// Taps the name area, left of the chevron.
    private func tapName(of row: XCUIElement) {
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
    }

    /// 123.2／123.3／123.7: selecting 思源宋體 and then 蘋方 again changes no
    /// row height and moves no row (the heading below both stays put).
    func testSelectingAMultiWeightFontKeepsEveryRowInPlace() {
        XCTAssertTrue(pingFang.waitForExistence(timeout: 5))
        XCTAssertTrue(noto.waitForExistence(timeout: 5))
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(pingFang.isSelected)
        let before = layout()
        attach("123.8_before-select")

        tapName(of: noto)
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: noto)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(pingFang.isSelected)
        let afterNoto = layout()
        XCTAssertEqual(afterNoto.pingFangHeight, before.pingFangHeight, accuracy: 0.5, "123.3 蘋方高度")
        XCTAssertEqual(afterNoto.notoHeight, before.notoHeight, accuracy: 0.5, "123.2 思源宋體選中後高度相同")
        XCTAssertEqual(afterNoto.pingFangY, before.pingFangY, accuracy: 0.5, "123.3")
        XCTAssertEqual(afterNoto.notoY, before.notoY, accuracy: 0.5, "123.3")
        XCTAssertEqual(afterNoto.headingY, before.headingY, accuracy: 0.5, "123.2／123.7 下方列的位置不變")
        attach("123.8_after-select")

        tapName(of: pingFang)
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: pingFang)
        waitForExpectations(timeout: 10)
        let back = layout()
        XCTAssertEqual(back.pingFangHeight, before.pingFangHeight, accuracy: 0.5, "123.3")
        XCTAssertEqual(back.notoHeight, before.notoHeight, accuracy: 0.5, "123.3")
        XCTAssertEqual(back.headingY, before.headingY, accuracy: 0.5, "123.3 改選回去，下方列位置不變")
    }
}
