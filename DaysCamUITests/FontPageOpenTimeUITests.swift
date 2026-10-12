import XCTest

/// TASK-150 (#519), 150.7: the time from tapping the 字型 sub-tab to its first
/// row existing, with downloaded fonts seeded (`UITestFontLibrary`). The mean
/// of ten openings is printed as `FONTOPEN` so the numbers before and after
/// the change can be compared on the same simulator.
final class FontPageOpenTimeUITests: XCTestCase {
    func testOpeningTheFontPageTime() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString, "-UITestFontSeed"]
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        if !app.buttons["樣式"].exists { app.buttons["疊字設定"].tap() }
        XCTAssertTrue(app.buttons["樣式"].waitForExistence(timeout: 5))
        app.buttons["樣式"].tap()
        let first = app.buttons["蘋方-繁"]
        var samples: [Double] = []
        for _ in 0..<11 {
            app.buttons["顏色"].tap()
            XCTAssertTrue(app.buttons["字型"].waitForExistence(timeout: 3))
            Thread.sleep(forTimeInterval: 0.5)
            let start = Date()
            app.buttons["字型"].tap()
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            samples.append(Date().timeIntervalSince(start) * 1000)
        }
        let kept = Array(samples.dropFirst())  // the first opening warms caches
        let mean = kept.reduce(0, +) / Double(kept.count)
        print("FONTOPEN mean_ms=\(Int(mean)) min_ms=\(Int(kept.min() ?? 0)) max_ms=\(Int(kept.max() ?? 0)) samples=\(kept.map { Int($0) })")
    }
}
