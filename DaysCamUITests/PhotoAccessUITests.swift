import XCTest

/// #622: limited and denied photo access (acceptance 1, 3, 4, 6), and #651:
/// the permission intro and the empty state by access (11, 12, 15). With
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
        XCTAssertTrue(app.staticTexts["到「設定」允許 DaysCam 取用照片，才能看到這個紀錄的照片和天數。"].exists, "3")
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

    /// #651-11, 12, 15: undecided, the record opens on the intro without
    /// asking; back and in again shows it again; "繼續" asks and, granted
    /// full access, lands on the empty wall with the full-access line.
    func testUndecidedShowsTheIntroUntilContinue() {
        launchWall(access: "notDetermined", photos: 0)
        let intro = element("photoPermissionIntro")
        XCTAssertTrue(intro.waitForExistence(timeout: 10), "11")
        XCTAssertTrue(app.staticTexts["讓紀錄和「照片」App 同步"].exists, "12 title")
        XCTAssertTrue(app.staticTexts["每個紀錄會在「照片」App 建一本同名相簿。在那裡加入的照片會自動出現在這裡，並標出第幾天。照片本身不會被修改。"].exists, "12 body")
        XCTAssertTrue(app.staticTexts["接下來的系統詢問請選「允許完整存取」。只允許部分照片時，紀錄不會同步相簿。"].exists, "12 note")
        let continueButton = element("permissionIntroContinue")
        XCTAssertTrue(continueButton.exists, "12")
        XCTAssertEqual(continueButton.label, "繼續", "12")
        XCTAssertTrue(element("wallTitle").exists, "12 top bar like the wall")
        XCTAssertFalse(element("wallMoreButton").exists)
        XCTAssertFalse(element("addPhotosButton").exists)
        XCTAssertTrue(app.frame.contains(continueButton.frame), "in frame")
        shot("651_16_permission-intro")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["紀錄"].waitForExistence(timeout: 5))
        element("recordRow").tap()
        XCTAssertTrue(intro.waitForExistence(timeout: 5), "11 the intro again")

        continueButton.tap()
        XCTAssertTrue(element("wallEmptyState").waitForExistence(timeout: 5), "13")
        XCTAssertFalse(intro.exists)
        XCTAssertTrue(app.staticTexts["用相機拍一張，或在「照片」App 把照片加入「我的紀錄」相簿，會自動出現在這裡"].exists, "15 full")
        XCTAssertTrue(element("addPhotosButton").exists)
        shot("651_16_empty-full")
    }

    /// #651-15: the empty state under limited access.
    func testLimitedEmptyStateSaysToAddFromTheCorner() {
        launchWall(access: "limited", photos: 0)
        XCTAssertTrue(element("wallEmptyState").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["用相機拍一張，或按左下角加入照片"].exists, "15 limited")
        shot("651_16_empty-limited")
    }
}
