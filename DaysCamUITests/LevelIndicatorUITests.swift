import XCTest

/// #687: the viewfinder level (acceptance 5, 6) and its B′ screenshots.
/// `-UITestLevelAngle <度>` stands in for the phone's tilt; with
/// `DAYSCAM_UI_SHOT_DIR` in the runner's environment the screenshots are also
/// written there for the PR.
final class LevelIndicatorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchCamera(angle: String) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "5", "-UITestBindAlbum", "-UITestFocus",
                                "-UITestFilmDate", "topLeading", "-UITestLevelAngle", angle]
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        XCTAssertTrue(app.openCamera())
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var indicator: XCUIElement { element("levelIndicator") }
    private var levelToggle: XCUIElement { element("levelToggle") }

    private func openTools() {
        app.buttons["相機設定"].tap()
        XCTAssertTrue(levelToggle.waitForExistence(timeout: 5))
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
            let device = UIDevice.current.name.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR687_\(name)_\(device).png"))
        }
    }

    // MARK: - 5: the line

    /// 5: off at first (nothing on screen), on with a 3° tilt shows the
    /// three-segment line (value 「3 度」).
    func test_687_5_tiltedShowsThreeSegments() {
        launchCamera(angle: "3")
        openTools()
        XCTAssertEqual(levelToggle.value as? String, "關", "687-5 off by default")
        XCTAssertFalse(indicator.exists, "687-5 nothing while off")

        levelToggle.tap()
        XCTAssertEqual(levelToggle.value as? String, "開")
        XCTAssertTrue(indicator.waitForExistence(timeout: 5), "687-5 the line appears")
        XCTAssertEqual(indicator.value as? String, "3 度")
        XCTAssertEqual(indicator.label, "水平儀")
        shot("1_tilted")
    }

    /// 5: a 0° tilt joins the segments into one line (value 「水平」).
    func test_687_5_levelShowsOneLine() {
        launchCamera(angle: "0")
        openTools()
        levelToggle.tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 5), "687-5 the line appears")
        XCTAssertEqual(indicator.value as? String, "水平")
        shot("2_level")
    }

    /// 5: beyond 5° nothing shows, and turning the switch off hides it.
    func test_687_5_farFromLevelShowsNothing_andOffHides() {
        launchCamera(angle: "8")
        openTools()
        levelToggle.tap()
        XCTAssertEqual(levelToggle.value as? String, "開")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(indicator.exists, "687-5 8° is beyond the limit")
    }

    // MARK: - 6: the tools capsule

    /// 6: four tools fit in the capsule on screen, and the fourth flips its value.
    func test_687_6_fourToolsFitAndLevelToggles() {
        launchCamera(angle: "3")
        openTools()
        let tools = [app.buttons["閃光燈"], app.buttons["計時器：關"], app.buttons["格線：關"], levelToggle]
        for tool in tools {
            XCTAssertTrue(tool.exists)
            XCTAssertTrue(app.frame.contains(tool.frame), "687-6 \(tool.label) inside the screen: \(tool.frame)")
        }
        levelToggle.tap()
        XCTAssertEqual(levelToggle.value as? String, "開")
        levelToggle.tap()
        XCTAssertEqual(levelToggle.value as? String, "關")
        shot("3_tools")
    }
}
