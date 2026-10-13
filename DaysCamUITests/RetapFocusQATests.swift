import XCTest

/// Independent QA probes for TASK-88 (#359, PR #370): a re-tap puts the whole
/// focus group (square, sun, bias text) at the new point at once, one group at
/// a time, and replays the entrance. Samples the accessibility frames in a
/// tight loop right after each tap.
final class RetapFocusQATests: XCTestCase {
    private var app: XCUIApplication!

    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        // The tap points assume the default 3:4 viewfinder with the panel
        // closed. The ratio lives in the standard defaults, so a test that
        // left 1:1 behind puts the overlay text under (0.8, 0.65), and that
        // tap opens the panel; pin the ratio and start from fresh profiles.
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFocus", "-UITestZoomPresets",
                                "-UITestFreshProfiles", UUID().uuidString,
                                "-captureAspectRatio", "threeByFour"]
        app.launch()
        XCTAssertTrue(app.buttons["zoomRoundButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["panelCollapseButton"].exists, "the overlay panel must start closed")
    }

    private func query(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    private var reticle: XCUIElement { query("focusReticle").firstMatch }
    private var sun: XCUIElement { query("focusSun").firstMatch }

    private func viewfinder(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["QA370_SHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }

    private struct Sample {
        let t: TimeInterval
        let groups: Int
        let center: CGPoint
        let width: CGFloat
        let sunCenter: CGPoint?
    }

    /// Samples as fast as the accessibility API allows for `duration` seconds,
    /// then keeps going until there are `minimum` samples or `timeout` seconds
    /// have passed. Each query is slower on a CI runner, so a fixed window
    /// alone can end with too few samples; later samples are judged the same.
    private func sample(for duration: TimeInterval, minimum: Int = 0, timeout: TimeInterval = 5) -> [Sample] {
        let start = Date()
        var out: [Sample] = []
        repeat {
            let count = query("focusReticle").count
            if count > 0 {
                let frame = reticle.frame
                let sunFrame = sun.exists ? sun.frame : nil
                out.append(Sample(
                    t: Date().timeIntervalSince(start), groups: count,
                    center: CGPoint(x: frame.midX, y: frame.midY), width: frame.width,
                    sunCenter: sunFrame.map { CGPoint(x: $0.midX, y: $0.midY) }))
            }
        } while Date().timeIntervalSince(start) < duration
            || (out.count < minimum && Date().timeIntervalSince(start) < timeout)
        return out
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// 88.1 / 88.2 / 88.3: after a far tap, no sample shows the group at the
    /// old point or anywhere between; the sun is level with the square.
    func testFarRetapNeverShowsAnOldOrInBetweenPosition() {
        launch()
        let a = viewfinder(0.2, 0.3)
        let b = viewfinder(0.8, 0.65)
        a.tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3))
        sleep(1)
        let pointA = reticle.frame
        let centerA = CGPoint(x: pointA.midX, y: pointA.midY)
        shot("88.1_a-before-retap")
        b.tap()
        let samples = sample(for: 0.6, minimum: 4)
        let centerB = b.screenPoint
        XCTAssertGreaterThan(samples.count, 3, "too few samples to judge")
        print("QA370 far samples: \(samples.count) first t=\(samples.first?.t ?? -1)")
        for s in samples {
            XCTAssertLessThanOrEqual(s.groups, 1, "88.3: two reticles at t=\(s.t)")
            XCTAssertLessThan(dist(s.center, centerB), 45, "88.1: at \(s.center) (old \(centerA), new \(centerB)) t=\(s.t)")
            if let sunCenter = s.sunCenter {
                XCTAssertLessThan(abs(sunCenter.y - s.center.y), 6, "88.2: sun left the square's row at t=\(s.t)")
                XCTAssertLessThan(abs(sunCenter.x - s.center.x), 90, "88.2: sun far from square at t=\(s.t)")
            }
        }
        sleep(1)
        shot("88.1_b-after-retap")
    }

    /// 88.4 (part): a same-point retap leaves exactly one group at that point.
    /// The entrance replay itself is judged from the recorded video (the
    /// accessibility frame does not follow the animated scale).
    func testSamePointRetapKeepsOneGroupAtThePoint() {
        launch()
        let p = viewfinder(0.5, 0.45)
        p.tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3))
        sleep(1)
        let settled = reticle.frame
        p.tap()
        for s in sample(for: 0.5) {
            XCTAssertLessThanOrEqual(s.groups, 1)
            XCTAssertLessThan(dist(s.center, CGPoint(x: settled.midX, y: settled.midY)), 6)
        }
        sleep(1)
        XCTAssertEqual(reticle.frame.width, settled.width, accuracy: 3)
    }

    /// Driven for the screen recording: far taps, a same-point tap, a lock.
    func testRecordedRetapSequence() {
        launch()
        let a = viewfinder(0.2, 0.3)
        let b = viewfinder(0.8, 0.65)
        sleep(2)
        a.tap(); sleep(2)
        b.tap(); sleep(2)
        b.tap(); sleep(2)
        a.tap(); sleep(2)
        b.press(forDuration: 1.0); sleep(2)
        a.tap(); sleep(2)
    }

    /// Driven for the screen recording: quick alternating taps while the old
    /// group is still on screen, so any slide or overlap shows in the frames.
    func testRecordedRapidAlternation() {
        launch()
        let a = viewfinder(0.2, 0.3)
        let b = viewfinder(0.8, 0.65)
        sleep(2)
        for _ in 0..<3 {
            a.tap(); usleep(250_000)
            b.tap(); usleep(250_000)
        }
        b.tap(); usleep(150_000)
        b.tap(); sleep(2)
    }

    /// 88.3: a burst of alternating taps never leaves two groups.
    func testRapidAlternatingTapsKeepOneGroup() {
        launch()
        let a = viewfinder(0.2, 0.3)
        let b = viewfinder(0.8, 0.65)
        var worst = 0
        for i in 0..<6 {
            (i % 2 == 0 ? a : b).tap()
            worst = max(worst, query("focusReticle").count)
            for s in sample(for: 0.15) { worst = max(worst, s.groups) }
        }
        XCTAssertLessThanOrEqual(worst, 1, "88.3: saw \(worst) groups")
        let last = b.screenPoint
        XCTAssertLessThan(dist(CGPoint(x: reticle.frame.midX, y: reticle.frame.midY), last), 45)
        shot("88.3_after-burst")
    }

    /// 88.5a: drag the bias up, tap elsewhere: the sun reads 0 at once at the
    /// new point, and stays 0.
    func testRetapZeroesTheBiasAtTheNewPoint() {
        launch()
        let a = viewfinder(0.5, 0.5)
        a.tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3))
        a.press(forDuration: 0.1, thenDragTo: viewfinder(0.5, 0.3))
        XCTAssertTrue((sun.value as? String)?.hasPrefix("+") == true, "value \(String(describing: sun.value))")
        shot("88.5a_a-bias-positive")
        viewfinder(0.25, 0.7).tap()
        let zero = NSPredicate(format: "value == '0'")
        expectation(for: zero, evaluatedWith: sun)
        waitForExpectations(timeout: 3)
        sleep(1)
        XCTAssertEqual(sun.value as? String, "0", "bias came back after the reset")
        shot("88.5a_b-bias-zero")
    }

    /// 88.5b: long press locks (label shows); a tap elsewhere removes the label
    /// and focuses the new point.
    func testRetapClearsTheLock() {
        launch()
        let a = viewfinder(0.3, 0.4)
        a.press(forDuration: 1.0)
        XCTAssertTrue(query("focusLockLabel").firstMatch.waitForExistence(timeout: 3))
        shot("88.5b_a-locked")
        let b = viewfinder(0.75, 0.6)
        b.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: query("focusLockLabel").firstMatch)
        waitForExpectations(timeout: 3)
        XCTAssertLessThan(dist(CGPoint(x: reticle.frame.midX, y: reticle.frame.midY), b.screenPoint), 45)
        sleep(1)
        XCTAssertFalse(query("focusLockLabel").firstMatch.exists)
        shot("88.5b_b-unlocked")
    }

    /// 88.5: a drag still dims/undims and adjusts after a re-tap.
    func testDragStillAdjustsAfterRetap() {
        launch()
        viewfinder(0.2, 0.3).tap()
        XCTAssertTrue(reticle.waitForExistence(timeout: 3))
        let b = viewfinder(0.6, 0.55)
        b.tap()
        sleep(1)
        b.press(forDuration: 0.1, thenDragTo: viewfinder(0.6, 0.35))
        XCTAssertTrue((sun.value as? String)?.hasPrefix("+") == true, "value \(String(describing: sun.value))")
    }
}
