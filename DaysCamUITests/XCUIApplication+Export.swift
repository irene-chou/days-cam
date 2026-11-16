import XCTest

extension XCUIApplication {
    /// Launches straight onto the export page (#620), where the overlay panel
    /// lives since #621 took it off the camera: five photos, the newest one's
    /// export page opened. Set `launchEnvironment` (e.g. `DAYSCAM_FAKE_TODAY`)
    /// before calling. Returns whether the page appeared.
    ///
    /// The panel opens on the layer list (#718); `entersOverlayDetail` pushes
    /// 疊字 so the 樣式｜內容 tabs are up, which is where most tests start.
    /// A fresh test record has 疊字 on (`-UITestOverlayOff` gives the real
    /// default, off).
    @discardableResult
    func launchOnExportPage(profiles: String = UUID().uuidString,
                            extraArguments: [String] = [],
                            entersOverlayDetail: Bool = true,
                            timeout: TimeInterval = 15) -> Bool {
        launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                            "-UITestRecordPhotos", "5", "-UITestOpenExport"] + extraArguments
        launch()
        guard waitForExportPage(timeout: timeout) else { return false }
        return !entersOverlayDetail || openLayer("layerRowOverlay", expecting: buttons["樣式"])
    }

    /// Pushes a layer page from the layer list: taps `row` (an identifier
    /// such as `layerRowOverlay`) and waits for `marker` to appear.
    @discardableResult
    func openLayer(_ row: String, expecting marker: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let button = buttons[row]
        guard button.waitForExistence(timeout: timeout) else { return false }
        button.tap()
        return marker.waitForExistence(timeout: timeout)
    }

    /// Goes back from a layer page to the layer list.
    @discardableResult
    func backToLayerList(timeout: TimeInterval = 5) -> Bool {
        let back = buttons["panelBackButton"]
        guard back.waitForExistence(timeout: timeout) else { return false }
        back.tap()
        return buttons["layerRowOverlay"].waitForExistence(timeout: timeout)
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

    /// Height of what sits under the panel body on the export page: only the
    /// 34pt home-indicator area on a screen with one, which swallows taps.
    /// The 34pt note under the panel is gone (D8, FR-18.4), so a 4.7-inch
    /// screen has no band at all.
    var panelBottomBand: CGFloat {
        frame.height >= 812 ? 34 : 0
    }
}

extension XCUIApplication {
    /// Launches on the 紀錄 list and opens the first record's editor through
    /// its swipe action (#617): the shared rules form (name, start date,
    /// counting rule, units) that replaced the camera's profile sheet in #621.
    /// Returns whether the editor appeared.
    @discardableResult
    func launchOnRecordEditor(profiles: String = UUID().uuidString,
                              extraArguments: [String] = [], timeout: TimeInterval = 15) -> Bool {
        launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", profiles,
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
