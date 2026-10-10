import XCTest

/// The gallery settings sheet's album switch under each permission outcome
/// (TASK-79, #329). `-UITestPhotoAccess` fakes the album permission; the
/// simulator must have Photos pre-granted before the run, or opening the
/// gallery shows a system prompt that blocks every test here:
/// `xcrun simctl privacy <udid> grant photos com.irenechou.DaysCam`
/// (the app must already be installed). The "前往設定" checks use the sheet's
/// own identifier, since the page behind it has a button of the same name.
final class AlbumAccessUITests: XCTestCase {
    private func launch(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestPhotoAccess", mode]
        app.launch()
        return app
    }

    private func openSettingsSheet(_ app: XCUIApplication) {
        let thumbnail = app.buttons["查看已拍照片"]
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 10))
        thumbnail.tap()
        let gear = app.buttons["圖庫設定"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()
        let toggle = app.switches["自動加入 DaysCam 相簿"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        // Let the sheet finish rising; a tap during the animation misses.
        let settled = NSPredicate(format: "isHittable == true")
        expectation(for: settled, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Taps the switch knob at the row's trailing edge; the centre of the row
    /// is its label, which does not flip it on every device size.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// 79.1 / 79.2: limited access turns the switch on with no notice and
    /// shows the same-name caveat under it.
    func testLimitedTurnsOnWithCaveat() {
        let app = launch("limited")
        openSettingsSheet(app)
        let toggle = app.switches["自動加入 DaysCam 相簿"]
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.staticTexts["limitedAccessNote"].exists)
        flip(toggle)
        XCTAssertTrue(app.staticTexts["limitedAccessNote"].waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertFalse(app.staticTexts["無法自動加入相簿"].exists)
        XCTAssertFalse(app.buttons["settingsSheetGoToSettings"].exists)
        attach(app, "79.1-limited")
    }

    /// Full access: switch on, no notice, no caveat.
    func testFullHasNoCaveat() {
        let app = launch("full")
        openSettingsSheet(app)
        let toggle = app.switches["自動加入 DaysCam 相簿"]
        flip(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertFalse(app.staticTexts["limitedAccessNote"].exists)
        XCTAssertFalse(app.staticTexts["無法自動加入相簿"].exists)
    }

    /// 79.4: a refusal keeps the switch off and points to Settings.
    func testDeniedShowsGoToSettings() {
        let app = launch("denied")
        openSettingsSheet(app)
        let toggle = app.switches["自動加入 DaysCam 相簿"]
        flip(toggle)
        XCTAssertTrue(app.staticTexts["無法自動加入相簿"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settingsSheetGoToSettings"].exists)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.staticTexts["limitedAccessNote"].exists)
        attach(app, "79.4-denied")
    }

    /// 79.5: access withdrawn since the switch was on closes it with the
    /// withdrawn notice.
    func testWithdrawnShowsNotice() {
        let app = launch("withdrawn")
        let thumbnail = app.buttons["查看已拍照片"]
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 10))
        thumbnail.tap()
        XCTAssertTrue(app.alerts["已關閉自動加入相簿"].waitForExistence(timeout: 10))
        attach(app, "79.5-withdrawn")
    }
}
