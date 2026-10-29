import XCTest

/// #572: with the phone held sideways the overlay layer turns with it.
/// `-UITestCaptureRotationAngle <angle>` stands in for the rotation
/// coordinator, which the simulator does not have. With
/// `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the screenshots are
/// also written there.
final class LandscapeViewfinderUITests: XCTestCase {
    private func launch(angle: String?, filmDateCorner: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString]
        if let angle { app.launchArguments += ["-UITestCaptureRotationAngle", angle] }
        if let filmDateCorner { app.launchArguments += ["-UITestFilmDate", filmDateCorner] }
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
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

    /// 572.5: top edge left, the text (default corner bottom-right of the
    /// landscape photo) stands upright in the viewfinder's left half.
    func testTextStandsInTheLeftHalfWhenTheTopEdgePointsLeft() {
        let app = launch(angle: "0")
        let text = element("overlayText", in: app)
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        attach(app, "572_5_angle0")
        XCTAssertGreaterThan(text.frame.height, text.frame.width, "turned upright: \(text.frame)")
        XCTAssertLessThan(text.frame.midX, window.midX, "left of the midline: \(text.frame)")
    }

    /// 572.5: held upright the text lies flat in the right half.
    func testTextLiesFlatInTheRightHalfWhenHeldUpright() {
        let app = launch(angle: "90")
        let text = element("overlayText", in: app)
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(text.frame), "the text is in view: \(text.frame)")
        attach(app, "572_14_portrait")
        XCTAssertGreaterThan(text.frame.width, text.frame.height, "\(text.frame)")
        XCTAssertGreaterThan(text.frame.midX, window.midX, "right of the midline: \(text.frame)")
    }

    /// 572.5 (extra): top edge right, the text turns the other way, to the right half.
    func testTextStandsInTheRightHalfWhenTheTopEdgePointsRight() {
        let app = launch(angle: "180")
        let text = element("overlayText", in: app)
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        attach(app, "572_5_angle180")
        XCTAssertGreaterThan(text.frame.height, text.frame.width, "\(text.frame)")
        XCTAssertGreaterThan(text.frame.midX, window.midX, "right of the midline: \(text.frame)")
    }

    /// 572.6: the film date is still drawn when landscape.
    func testFilmDateStillExistsWhenLandscape() {
        let app = launch(angle: "0", filmDateCorner: "bottomLeading")
        XCTAssertTrue(app.otherElements["filmDateStamp"].waitForExistence(timeout: 10))
    }
}
