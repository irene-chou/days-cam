import XCTest

/// #622: limited and denied photo access (acceptance 1, 3, 4, 6). With
/// `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′ screenshots
/// are also written there for the PR.
final class PhotoAccessUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record, then launches on its photo wall with `access`.
    private func launchWall(access: String, photos: Int = 5) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "\(photos)", "-UITestPhotoAccess", access,
                                "-limitedNoticeDismissed", "NO"]
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func shot(_ name: String) {
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

    /// 1, 6: limited access keeps the wall and adds the notice on top.
    func testLimitedAccessShowsTheNoticeAboveTheWall() {
        launchWall(access: "limited")
        let banner = element("limitedAccessBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "1")
        XCTAssertTrue(app.buttons["limitedAccessBannerSettings"].label.replacingOccurrences(of: "\u{2060}", with: "") == "目前沒有開放完整權限，照片不會和原生相簿同步。前往設定 ›", "1")
        XCTAssertTrue(app.buttons["關閉提示"].exists, "1 xmark")
        XCTAssertGreaterThanOrEqual(app.buttons["關閉提示"].frame.height, 44, "1 44pt")
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 5))
        XCTAssertTrue(element("addPhotosButton").exists)
        XCTAssertTrue(banner.frame.maxY <= element("photoWall").frame.minY + 1, "1 the notice is on top")
        XCTAssertTrue(app.frame.contains(banner.frame), "6 in frame")
        shot("limited-banner")
    }

    /// 2: the xmark hides the notice.
    func testDismissingTheNoticeHidesIt() {
        launchWall(access: "limited")
        XCTAssertTrue(element("limitedAccessBanner").waitForExistence(timeout: 10))
        app.buttons["關閉提示"].tap()
        XCTAssertFalse(element("limitedAccessBanner").waitForExistence(timeout: 1), "2")
        XCTAssertTrue(element("photoWall").exists)
    }

    /// 3: the ⋯ menu has the settings item only under limited access.
    func testMoreMenuHasAllowAllPhotosOnlyWhenLimited() {
        launchWall(access: "limited")
        XCTAssertTrue(element("wallMoreButton").waitForExistence(timeout: 10))
        element("wallMoreButton").tap()
        XCTAssertTrue(app.buttons["設定照片權限"].waitForExistence(timeout: 5), "3")
        XCTAssertTrue(app.buttons["編輯紀錄"].exists)
        shot("limited-more-menu")
        app.terminate()
        launchWall(access: "authorized")
        XCTAssertTrue(element("wallMoreButton").waitForExistence(timeout: 10))
        element("wallMoreButton").tap()
        XCTAssertTrue(app.buttons["編輯紀錄"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["設定照片權限"].exists, "3")
    }

    /// 3, 6: denied access replaces the wall with the permission page.
    func testDeniedAccessShowsThePermissionPage() {
        launchWall(access: "denied")
        XCTAssertTrue(element("photoAccessDenied").waitForExistence(timeout: 10), "3")
        XCTAssertTrue(element("photoAccessSettingsButton").exists, "3")
        XCTAssertTrue(app.buttons["前往設定"].exists, "3")
        XCTAssertTrue(app.staticTexts["DaysCam 需要讀取相簿，才能顯示每張照片是第幾天"].exists, "3")
        XCTAssertFalse(element("photoWall").exists, "3 the wall is gone")
        XCTAssertFalse(element("limitedAccessBanner").exists)
        XCTAssertTrue(app.frame.contains(element("photoAccessSettingsButton").frame), "6 in frame")
        shot("photo-access-denied")
    }

    /// 4: with access denied the record can still be edited from the wall.
    func testDeniedAccessStillAllowsEditingTheRecord() {
        launchWall(access: "denied")
        XCTAssertTrue(element("wallMoreButton").waitForExistence(timeout: 10))
        element("wallMoreButton").tap()
        app.buttons["編輯紀錄"].tap()
        XCTAssertTrue(element("recordEditor").waitForExistence(timeout: 5), "4")
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "4 the name is editable")
        let before = nameField.value as? String ?? ""
        nameField.tap()
        nameField.typeText("新")
        XCTAssertNotEqual(nameField.value as? String, before, "4")
        XCTAssertTrue(element("startDatePicker").exists, "4 the start date is editable")
    }
}
