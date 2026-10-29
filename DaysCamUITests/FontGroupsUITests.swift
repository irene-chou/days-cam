import XCTest

/// TASK-120 (#453): the font list has only the 開源字型 and 系統字型 headings.
/// Screenshots are attached and, with `DAYSCAM_UI_SHOT_DIR` in the runner's
/// environment, also written there as PNGs.
final class FontGroupsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        if !app.buttons["樣式"].exists { app.buttons["疊字設定"].tap() }
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
        app.buttons["字型"].tap()
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

    private func heading(_ title: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Drags the list until `element` is `target` points below the list top.
    private func scroll(_ element: XCUIElement, listTop: CGFloat) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let height = app.windows.firstMatch.frame.height
        let bottom = height - (height > 800 ? 50 : 20)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<40 {
            let delta = element.frame.minY - listTop
            if abs(delta) < 30 { return }
            let step = min(abs(delta), (bottom - listTop) * 0.75)
            let startY = delta > 0 ? bottom : listTop + 6
            let endY = delta > 0 ? startY - step : startY + step
            origin.withOffset(CGVector(dx: 60, dy: startY))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: 60, dy: endY)),
                       withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        XCTFail("could not scroll \(element) into view")
    }

    /// 120.1: the two headings exist, the old ones do not, and the fresh list
    /// starts with 蘋方 then 開源字型.
    func testOnlyTheTwoSourceHeadingsExist() {
        let pingFang = app.buttons["蘋方"]
        XCTAssertTrue(pingFang.waitForExistence(timeout: 5))
        let listTop = pingFang.frame.minY
        XCTAssertTrue(heading("開源字型").waitForExistence(timeout: 5), "120.1")
        attach("120.1_font-list-top")
        scroll(heading("系統字型"), listTop: listTop)
        attach("120.1_font-list-system-heading")
        for old in ["可下載", "黑", "圓", "宋", "楷", "手寫", "書法", "可愛", "開源"] {
            XCTAssertFalse(heading(old).exists, "120.1 no \(old) heading")
        }
    }
}
