import XCTest

extension XCUIApplication {
    /// Launches straight onto the export page (#620), where the overlay panel
    /// lives since #621 took it off the camera: five photos, the newest one's
    /// export page opened. Set `launchEnvironment` (e.g. `DAYSCAM_FAKE_TODAY`)
    /// before calling. Returns whether the page appeared.
    @discardableResult
    func launchOnExportPage(profiles: String = UUID().uuidString,
                            extraArguments: [String] = [],
                            timeout: TimeInterval = 15) -> Bool {
        launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                            "-UITestRecordPhotos", "5", "-UITestOpenExport"] + extraArguments
        launch()
        return waitForExportPage(timeout: timeout)
    }

    /// Waits for the export page; also what a relaunch with the same
    /// arguments lands on.
    func waitForExportPage(timeout: TimeInterval = 15) -> Bool {
        descendants(matching: .any).matching(identifier: "exportView").firstMatch.waitForExistence(timeout: timeout)
    }

    /// Bottom edge of the panel's segmented row (the export page has no
    /// collapse button to measure from).
    var panelSegmentBottom: CGFloat {
        buttons["樣式"].frame.maxY
    }

    /// Height of what sits under the panel body on the export page: the 34pt
    /// note plus the home-indicator band, which swallows taps (a 4.7-inch
    /// screen has no indicator).
    var panelBottomBand: CGFloat {
        frame.height >= 812 ? 84 : 42
    }
}

extension XCUIApplication {
    /// Launches on the 紀錄 list and opens the first record's editor through
    /// its swipe action (#617): the shared rules form (name, start date,
    /// counting rule) that replaced the camera's profile sheet in #621.
    /// Returns whether the editor appeared.
    @discardableResult
    func launchOnRecordEditor(extraArguments: [String] = [], timeout: TimeInterval = 15) -> Bool {
        launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString,
                            "-UITestRecordPhotos", "0"] + extraArguments
        launch()
        let row = descendants(matching: .any).matching(identifier: "recordRow").firstMatch
        guard row.waitForExistence(timeout: timeout) else { return false }
        row.swipeLeft()
        let edit = buttons["編輯"]
        guard edit.waitForExistence(timeout: 5) else { return false }
        edit.tap()
        return descendants(matching: .any).matching(identifier: "recordEditor").firstMatch.waitForExistence(timeout: 5)
    }
}
