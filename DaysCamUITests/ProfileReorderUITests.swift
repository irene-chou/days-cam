import XCTest

/// Reorder-by-drag in the profile list (TASK-102, #411): drags B above A and
/// samples B's frame right after release, so a fly-away (B overshooting its
/// final slot and coming back) shows up in the log as a non-monotonic
/// sequence of y positions. Also re-checks the order is kept (102.5).
final class ProfileReorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        app.openCamera()
    }

    private var profileChip: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '設定檔：'")).firstMatch
    }
    private var sheetBar: XCUIElement { app.navigationBars["設定檔"] }
    private var rows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "profileRow") }

    /// Appends a line to `reorder.log` under `DAYSCAM_UI_SHOT_DIR` (xcodebuild
    /// does not surface `print` from the test runner).
    private func log(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["DAYSCAM_UI_SHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("reorder.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write((line + "\n").data(using: .utf8)!); try? handle.close()
        } else {
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func openSheet() {
        XCTAssertTrue(profileChip.waitForExistence(timeout: 10))
        profileChip.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
    }

    private func addProfile() {
        let add = app.buttons["新增設定檔"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        // An untouched new profile is not kept (TASK-106): give it a name.
        nameField.tap()
        nameField.typeText("甲")
        app.navigationBars.element(boundBy: max(app.navigationBars.count - 1, 0)).buttons.firstMatch.tap()
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5))
    }

    private func rowNames() -> [String] {
        rows.allElementsBoundByIndex.map { String($0.label.split(separator: "，").first ?? "") }
    }

    /// Drags the row at `from` so it lands at `to`, then samples the dragged
    /// row's minY for ~0.6s. Returns the samples.
    private func drag(from: Int, to: Int, velocity: XCUIGestureVelocity) -> (name: String, samples: [CGFloat], finalY: CGFloat) {
        let all = rows.allElementsBoundByIndex
        let source = all[from]
        let name = String(source.label.split(separator: "，").first ?? "")
        let pitch = all[1].frame.minY - all[0].frame.minY
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: CGFloat(to - from) * pitch))
        start.press(forDuration: 0.6, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: 0.2)
        let moved = rows.matching(NSPredicate(format: "label BEGINSWITH %@", name + "，")).firstMatch
        var samples: [CGFloat] = []
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            samples.append(moved.frame.minY)
        }
        Thread.sleep(forTimeInterval: 0.4)
        return (name, samples, moved.frame.minY)
    }

    /// 102.1／102.2: with two profiles, B above A and A below B, repeated;
    /// the sampled path must never cross beyond the final slot.
    func testTwoProfilesDragBothWays() {
        openSheet()
        addProfile()
        XCTAssertEqual(rows.count, 2)
        var overshoots = 0
        for round in 0..<6 {
            let names = rowNames()
            let (from, to) = round % 2 == 0 ? (1, 0) : (0, 1)
            let result = drag(from: from, to: to, velocity: round < 3 ? .slow : .fast)
            let after = rowNames()
            XCTAssertEqual(after[to], result.name, "round \(round): \(names) → \(after)")
            let overshoot = result.samples.filter { to < from ? $0 < result.finalY - 3 : $0 > result.finalY + 3 }
            if !overshoot.isEmpty { overshoots += 1 }
            log("TASK102 two round \(round) from \(from) to \(to) final \(Int(result.finalY)) overshoot=\(!overshoot.isEmpty) samples \(result.samples.map { Int($0) })")
        }
        XCTAssertEqual(overshoots, 0, "102.1／102.2 the dragged row never flies past its slot")
        app.terminate()
        app.launchArguments = app.launchArguments.filter { $0 != "-UITestResetOnboarding" }
        app.launch()
        app.openCamera()
        openSheet()
        XCTAssertEqual(rows.count, 2, "102.5 the order survives a relaunch")
    }

    /// 102.3: four profiles, first↔last, to the middle, and back to where it
    /// started.
    func testFourProfilesLongDrags() {
        openSheet()
        for _ in 0..<3 { addProfile() }
        XCTAssertEqual(rows.count, 4)
        var overshoots = 0
        for (from, to) in [(0, 3), (3, 0), (0, 2), (2, 2)] {
            let result = drag(from: from, to: to, velocity: .slow)
            if from != to {
                XCTAssertEqual(rowNames()[to], result.name, "102.3 \(from)→\(to)")
            }
            let overshoot = result.samples.filter { to < from ? $0 < result.finalY - 3 : (to > from ? $0 > result.finalY + 3 : abs($0 - result.finalY) > 3) }
            if !overshoot.isEmpty { overshoots += 1 }
            log("TASK102 four \(from)→\(to) final \(Int(result.finalY)) overshoot=\(!overshoot.isEmpty) samples \(result.samples.map { Int($0) })")
        }
        XCTAssertEqual(overshoots, 0, "102.3 no fly-away")
    }
}
