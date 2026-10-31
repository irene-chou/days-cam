import XCTest

/// #618: the photo wall (acceptance 1, 7, 11, 12, 13). With
/// `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the B′ screenshots
/// are also written there for the PR.
final class PhotoWallUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record starting 2026-01-01, then launches on 2026-01-10 with
    /// `photos` generated photos, one per day ending that day, all in the
    /// record's album, and opens the record.
    private func launchWall(photos: Int, startDate: String = "2026-01-01") {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = startDate
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "\(photos)", "-UITestBindAlbum"]
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func dayLabels() -> [String] {
        let labels = app.descendants(matching: .any).matching(identifier: "photoDayLabel")
        return (0..<labels.count).map { labels.element(boundBy: $0).label }
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

    /// 1, 13: five photos run 第 6 天 … 第 10 天 oldest to newest.
    func testWallMarksEachPhotoOldestToNewest() {
        launchWall(photos: 5)
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "photoCell").element(boundBy: 4).waitForExistence(timeout: 5))
        XCTAssertEqual(dayLabels(), ["第 6 天", "第 7 天", "第 8 天", "第 9 天", "第 10 天"], "1")
        XCTAssertTrue(element("addPhotosButton").exists)
        XCTAssertEqual(app.buttons["addPhotosButton"].label, "加入照片", "1")
        XCTAssertTrue(app.buttons["wallCameraButton"].label.contains("拍照"), "1")
        shot("photo-wall")
    }

    /// 7: with more photos than fit, the wall opens on the newest.
    func testWallOpensScrolledToTheNewestPhoto() {
        launchWall(photos: 60)
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 10))
        let newest = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'photoDayLabel' AND label == '第 10 天'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5), "7")
        XCTAssertTrue(newest.isHittable || newest.frame.maxY <= app.frame.maxY, "7 the newest is on screen")
        XCTAssertFalse(dayLabels().contains("前 50 天"), "7 the oldest is scrolled away")
    }

    /// 11: the menu offers the two record actions and nothing else.
    func testMenuHasOnlyEditAndDelete() {
        launchWall(photos: 3)
        XCTAssertTrue(element("wallMoreButton").waitForExistence(timeout: 10))
        element("wallMoreButton").tap()
        XCTAssertTrue(app.buttons["編輯紀錄"].waitForExistence(timeout: 5), "11")
        XCTAssertTrue(app.buttons["刪除紀錄"].exists, "11")
        XCTAssertFalse(app.buttons["匯出"].exists)
        XCTAssertFalse(app.buttons["選取"].exists)
    }

    /// 12, 13: an empty album shows the empty state and the add button.
    func testEmptyAlbumShowsTheEmptyState() {
        launchWall(photos: 0)
        XCTAssertTrue(element("wallEmptyState").waitForExistence(timeout: 10), "12")
        XCTAssertTrue(app.staticTexts["還沒有照片"].exists, "12")
        XCTAssertTrue(app.staticTexts["從相簿加入，或用相機拍一張"].exists, "12")
        XCTAssertTrue(element("addPhotosButton").exists, "12")
        shot("photo-wall-empty")
    }

    /// The camera keeps an exit back to the wall.
    func testCameraOpensFromTheWallAndClosesBack() {
        launchWall(photos: 2)
        XCTAssertTrue(app.openCamera())
        app.buttons["cameraCloseButton"].tap()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 5))
    }
}
