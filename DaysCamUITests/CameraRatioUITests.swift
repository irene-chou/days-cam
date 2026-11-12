import XCTest

/// #712: the ratio key (acceptance 2) and the viewfinder at each ratio with
/// the day HUD inside it (4, #724). With `DAYSCAM_UI_SHOT_DIR` in the test runner's
/// environment the B′ screenshots (8) are also written there for the PR.
final class CameraRatioUITests: XCTestCase {
    private var app: XCUIApplication!
    private var profiles = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record starting 2026-01-01, then launches on 2026-01-10 with
    /// the film date on, and opens the record's camera.
    private func launchCamera(extra: [String] = [], reusingProfiles: Bool = false) {
        if !reusingProfiles {
            profiles = UUID().uuidString
            let seeding = XCUIApplication()
            seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
            seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
            seeding.launch()
            XCTAssertTrue(seeding.openCamera())
            seeding.terminate()
        }
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "5", "-UITestBindAlbum",
                                "-UITestFilmDate", "topLeading"] + extra
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        XCTAssertTrue(app.openCamera())
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var ratioButton: XCUIElement { element("cameraRatioButton") }
    private var viewfinder: XCUIElement { element("cameraViewfinder") }
    private var hud: XCUIElement { element("cameraDayHUD") }

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
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("PR712_\(name)_\(device).png"))
        }
    }

    private func assertOnScreen(_ item: XCUIElement, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(item.waitForExistence(timeout: 5), message, file: file, line: line)
        XCTAssertTrue(app.frame.contains(item.frame), "\(message): \(item.frame) in \(app.frame)", file: file, line: line)
    }

    /// Waits until the ratio key reads `label`.
    private func waitForRatio(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let reads = NSPredicate(format: "label == %@", "比例：\(label)")
        let expectation = XCTNSPredicateExpectation(predicate: reads, object: ratioButton)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "ratio reads \(label), got \(ratioButton.label)", file: file, line: line)
    }

    // MARK: - 2: the ratio key

    /// 2: 3:4 → 1:1 → 9:16 → 3:4; the choice survives a relaunch.
    func test_712_2_ratioKeyCyclesAndIsRemembered() {
        launchCamera()
        assertOnScreen(ratioButton, "712-2 the ratio key")
        waitForRatio("3:4")
        ratioButton.tap()
        waitForRatio("1:1")
        ratioButton.tap()
        waitForRatio("9:16")
        ratioButton.tap()
        waitForRatio("3:4")
        ratioButton.tap()
        waitForRatio("1:1")
        app.terminate()

        launchCamera(extra: ["-UITestKeepCaptureRatio"], reusingProfiles: true)
        waitForRatio("1:1")
    }

    // MARK: - 4, 8: the viewfinder at each ratio

    /// 4: the viewfinder has the chosen ratio's shape and the day HUD sits
    /// inside it (#724); 8: one screenshot per ratio, plus the tools capsule
    /// open.
    func test_712_4_viewfinderFollowsTheRatio() {
        launchCamera()
        let expected: [(String, CGFloat)] = [("3:4", 3.0 / 4), ("1:1", 1), ("9:16", 9.0 / 16)]
        for (index, (label, aspect)) in expected.enumerated() {
            if index > 0 { ratioButton.tap() }
            waitForRatio(label)
            XCTAssertTrue(viewfinder.waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 1)
            let frame = viewfinder.frame
            XCTAssertEqual(frame.width / frame.height, aspect, accuracy: 0.01, "712-4 \(label): \(frame)")
            XCTAssertEqual(frame.width, app.frame.width, accuracy: 1, "712-4 \(label) full width")
            assertOnScreen(hud, "724 \(label) the HUD is drawn")
            XCTAssertTrue(frame.contains(hud.frame), "724 \(label) HUD \(hud.frame) in \(frame)")
            assertOnScreen(ratioButton, "\(label) ratio key")
            assertOnScreen(app.buttons["快門"], "\(label) shutter")
            shot("ratio_\(label.replacingOccurrences(of: ":", with: "x"))")
        }

        ratioButton.tap()
        waitForRatio("3:4")
        app.buttons["相機設定"].tap()
        XCTAssertTrue(app.buttons["閃光燈"].waitForExistence(timeout: 5))
        assertOnScreen(element("levelToggle"), "the capsule's fourth key")
        Thread.sleep(forTimeInterval: 0.5)
        shot("tools_open")
    }
}
