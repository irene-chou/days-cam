import XCTest

/// TASK-114: tapping the size slider's track seeks to that point (114.1,
/// 114.4, 114.5; the stroke-width slider of 114.2 / 114.6 left with #678). With `DAYSCAM_UI_SHOT_DIR` in the runner's
/// environment the screenshots are also written there.
final class TapSeekSliderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        XCTAssertTrue(app.launchOnExportPage(), "the export page is up")
        openStyleTab()
    }

    private func openStyleTab() {
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
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

    /// Taps `slider`'s track at `fraction` of its width.
    private func tapTrack(_ slider: XCUIElement, at fraction: CGFloat) {
        slider.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)).tap()
    }

    private var sizePercent: String {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '字級 '")).firstMatch.label
    }

    /// Waits for `element`, then scrolls the page (slowly, from the left
    /// margin) just far enough that the row's middle sits well above the
    /// panel's bottom edge, where a fade hides it although it still counts
    /// as hittable. Does nothing when the row is already clear of the edge.
    private func settle(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        let screenHeight = app.windows.firstMatch.frame.height
        var tries = 0
        while (!element.isHittable || element.frame.midY > screenHeight * 0.85), tries < 4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.88))
                .press(forDuration: 0.1,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.76)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
            tries += 1
        }
        XCTAssertTrue(element.isHittable, "row revealed above the panel's bottom edge")
    }

    /// 114.1 / 114.4: the size slider seeks on a tap, its ends give the
    /// bounds, the hint names tapping, and a double tap still resets.
    func testSizeSliderSeeksAndDoubleTapStillResets() {
        let slider = app.sliders["字級"]
        settle(slider)
        XCTAssertEqual(sizePercent, "字級 100%")
        XCTAssertTrue(app.staticTexts["點或拖曳調整，點兩下回到預設大小"].exists, "114.4 hint")

        tapTrack(slider, at: 0.75)
        let after = sizePercent
        XCTAssertNotEqual(after, "字級 100%", "114.1 the tap seeks")
        let percent = Int(after.replacingOccurrences(of: "字級 ", with: "").replacingOccurrences(of: "%", with: "")) ?? 0
        // 70…160 by 5: three quarters of the track is about 135–145.
        XCTAssertTrue((130...150).contains(percent), "114.1 about three quarters: \(after)")
        attach("114.1_size-seek")

        tapTrack(slider, at: 0.02)
        XCTAssertEqual(sizePercent, "字級 70%", "114.1 left end is the minimum")
        tapTrack(slider, at: 0.98)
        XCTAssertEqual(sizePercent, "字級 160%", "114.1 right end is the maximum")

        slider.doubleTap()
        XCTAssertEqual(sizePercent, "字級 100%", "114.4 double tap resets")
    }

    /// Where the size slider's thumb centre sits for `percent`, as a share of
    /// the slider's width (70…160 over the track inside a 14pt thumb radius
    /// at each end, as `TapSeekSlider` maps it).
    private func thumbFraction(of slider: XCUIElement, percent: Int) -> CGFloat {
        let width = slider.frame.width
        let radius: CGFloat = 14
        guard width > 2 * radius else { return 0.5 }
        let share = CGFloat(percent - 70) / 90
        return (radius + share * (width - 2 * radius)) / width
    }

    /// #551: pressing the thumb and dragging moves the value continuously
    /// (the tap gesture must not take over the slider's own drag).
    func testDraggingTheThumbChangesTheValue() {
        let slider = app.sliders["字級"]
        settle(slider)
        XCTAssertEqual(sizePercent, "字級 100%")

        // Each drag starts on the thumb's centre for the current value: a
        // press beside the centre keeps that offset for the whole drag, so a
        // drag to the end would stop a step or two short of it.
        let thumb = slider.coordinate(withNormalizedOffset: CGVector(dx: thumbFraction(of: slider, percent: 100), dy: 0.5))
        let middle = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        thumb.press(forDuration: 0.2, thenDragTo: middle)
        let first = Int(sizePercent.replacingOccurrences(of: "字級 ", with: "").replacingOccurrences(of: "%", with: "")) ?? 0
        XCTAssertGreaterThan(first, 120, "551 dragging right raises the value: \(sizePercent)")

        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5))
        let thumbNow = slider.coordinate(withNormalizedOffset: CGVector(dx: thumbFraction(of: slider, percent: first), dy: 0.5))
        thumbNow.press(forDuration: 0.2, thenDragTo: end)
        XCTAssertEqual(sizePercent, "字級 160%", "551 dragging to the end gives the maximum")
        attach("551_size-drag")
    }
}
