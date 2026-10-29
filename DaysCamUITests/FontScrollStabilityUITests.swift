import XCTest

/// TASK-150 (#519): scrolling the font page moves the list only as far as the
/// finger does. Each drag's resulting y of the 系統字型 heading and the
/// 字型授權 row is logged (`FONTSCROLL` lines) and checked: going down they
/// never move back down, going up they never move back up.
final class FontScrollStabilityUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(extraArguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString] + extraArguments
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        if !app.buttons["樣式"].exists { app.buttons["疊字設定"].tap() }
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
        app.buttons["字型"].tap()
        XCTAssertTrue(app.buttons["蘋方"].waitForExistence(timeout: 5))
    }

    private var heading: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "系統字型")).firstMatch
    }
    private var license: XCUIElement { app.buttons["字型授權"] }

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

    /// One slow drag inside the list area (below the sub-tab icons, well above
    /// the screen's bottom edge), so the gesture never starts on the camera
    /// view above, where a downward drag would collapse the panel, nor in the
    /// home-indicator strip, where iOS 26 takes the touch for itself. `up`
    /// moves the content up.
    private func drag(up: Bool) {
        let height = app.windows.firstMatch.frame.height
        let listTop = app.buttons["字型"].frame.maxY + 8
        let listBottom = height - 80
        let length = min(140, listBottom - listTop - 6)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let startY = up ? listBottom : listTop
        let endY = up ? listBottom - length : listTop + length
        origin.withOffset(CGVector(dx: 60, dy: startY))
            .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: 60, dy: endY)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// The heading can leave the accessibility tree while far off screen;
    /// then its y is reported as `-.infinity` and not compared.
    private func positions() -> (heading: CGFloat, license: CGFloat) {
        (heading.exists ? heading.frame.minY : -.infinity, license.frame.minY)
    }

    /// Scrolls to the bottom and back, asserting monotone movement.
    /// Returns the `licenseVisible` flag for the bottom.
    private func scrollDownAndUp(label: String) {
        let top = positions()
        print("FONTSCROLL \(label) start heading=\(top.heading) license=\(top.license)")
        var last = top
        var reachedBottom = false
        for step in 1...80 {
            drag(up: true)
            var now = positions()
            if abs(now.license - last.license) < 0.5 {
                // A loaded CI runner sometimes drops a drag — the first one or
                // one halfway down — so a drag that moves nothing gets one
                // more try before it means a miss or the bottom (#547).
                print("FONTSCROLL \(label) down#\(step) did not scroll, retrying")
                drag(up: true)
                now = positions()
            }
            print("FONTSCROLL \(label) down#\(step) heading=\(now.heading) license=\(now.license)")
            XCTAssertLessThanOrEqual(now.heading, last.heading + 0.5, "150.2 \(label) heading rose at down#\(step)")
            XCTAssertLessThanOrEqual(now.license, last.license + 0.5, "150.2 \(label) license rose at down#\(step)")
            if step % 6 == 0 { attach("150.9_\(label)_down\(String(format: "%02d", step))") }
            if abs(now.license - last.license) < 0.5 {
                // The list starts at the top, so a drag that moves nothing at
                // once means the gesture missed the list, not the bottom.
                XCTAssertGreaterThan(step, 1, "150.2 \(label) first drag did not scroll")
                reachedBottom = true
                break
            }
            last = now
        }
        XCTAssertTrue(reachedBottom, "150.2 \(label) reached the bottom")
        // `isHittable` is unreliable on CI runners (#547): check the frame
        // lies inside the visible list area instead.
        let visibleTop = app.buttons["字型"].frame.maxY
        let visibleBottom = app.windows.firstMatch.frame.maxY
        let licenseFrame = license.frame
        XCTAssertTrue(license.exists && licenseFrame.minY >= visibleTop && licenseFrame.maxY <= visibleBottom,
                      "150.2 \(label) 字型授權 fully visible: \(licenseFrame) in \(visibleTop)...\(visibleBottom)")
        attach("150.9_\(label)_bottom")
        last = positions()
        for step in 1...80 {
            drag(up: false)
            let now = positions()
            print("FONTSCROLL \(label) up#\(step) heading=\(now.heading) license=\(now.license)")
            XCTAssertGreaterThanOrEqual(now.heading, last.heading - 0.5, "150.4 \(label) heading fell at up#\(step)")
            XCTAssertGreaterThanOrEqual(now.license, last.license - 0.5, "150.4 \(label) license fell at up#\(step)")
            if abs(now.license - last.license) < 0.5 { break }
            last = now
        }
    }

    /// 150.1 / 150.2 / 150.4: the plain list.
    func testScrollingDownAndUpDoesNotJump() {
        launch()
        attach("150.9_top")
        scrollDownAndUp(label: "normal")
    }

    /// 150.5: the largest Dynamic Type size, names wrapping to two lines.
    func testScrollingAtTheLargestTextSizeDoesNotJump() {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        scrollDownAndUp(label: "xxxl")
    }

    /// 150.3: several downloaded fonts and one whose download progress keeps
    /// moving while the list scrolls (`UITestFontLibrary`).
    func testScrollingWithDownloadedFontsAndLiveProgressDoesNotJump() {
        launch(extraArguments: ["-UITestFontSeed", "-UITestFontProgress"])
        attach("150.9_seeded_top")
        scrollDownAndUp(label: "seeded-progress")
    }

    /// 150.5 together with downloaded rows: names that may wrap to two lines.
    func testScrollingWithDownloadedFontsAtTheLargestTextSizeDoesNotJump() {
        launch(extraArguments: ["-UITestFontSeed", "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"])
        scrollDownAndUp(label: "seeded-xxxl")
    }

    /// 150.6: the selected multi-weight font expanded (its weight buttons
    /// open) while the list scrolls down and back.
    func testScrollingWithAnExpandedFontDoesNotJump() {
        launch(extraArguments: ["-UITestFontSeed"])
        app.buttons["蘋方"].tap()
        XCTAssertTrue(app.buttons["fontWeight.light"].waitForExistence(timeout: 3), "expanded")
        scrollDownAndUp(label: "expanded")
    }
}
