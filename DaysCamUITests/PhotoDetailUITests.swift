import XCTest

/// #619: the photo viewer (acceptance 1, 5, 8). With `DAYSCAM_UI_SHOT_DIR` in
/// the test runner's environment the B′ screenshots are also written there.
final class PhotoDetailUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seeds one record starting 2026-01-01, then launches on 2026-01-10 with
    /// five photos, one per day ending that day, and opens the record.
    private func launchWall(mixedAspects: Bool = false) {
        let profiles = UUID().uuidString
        let seeding = XCUIApplication()
        seeding.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles]
        seeding.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-01"
        seeding.launch()
        XCTAssertTrue(seeding.openCamera())
        seeding.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestOpenFirstRecord", "-UITestFreshProfiles", profiles,
                                "-UITestRecordPhotos", "5", "-UITestBindAlbum"]
        if mixedAspects { app.launchArguments.append("-UITestMixedAspects") }
        app.launchEnvironment["DAYSCAM_FAKE_TODAY"] = "2026-01-10"
        app.launch()
        XCTAssertTrue(cell(4).waitForExistence(timeout: 10))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func cell(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "photoCell").element(boundBy: index)
    }

    private func openViewer(cell index: Int) {
        cell(index).tap()
        XCTAssertTrue(element("photoDetail").waitForExistence(timeout: 5))
        XCTAssertTrue(element("photoDetailImage").waitForExistence(timeout: 5))
    }

    private var title: String { element("photoDetailTitle").label }

    private func waitForTitle(containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element("photoDetailTitle"))
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
                       "title was \(title)", file: file, line: line)
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

    /// 1: the newest photo opens as 第 10 天 with its own date and time.
    func testNewestPhotoShowsDayAndDate() {
        launchWall()
        openViewer(cell: 4)
        waitForTitle(containing: "第 10 天")
        let date = NSPredicate(format: "label MATCHES %@", ".*2026/1/10 [0-9]{2}:[0-9]{2}.*")
        XCTAssertTrue(date.evaluate(with: element("photoDetailTitle")), "1 \(title)")
        XCTAssertTrue(app.staticTexts["疊字只是預覽，照片本身沒有改動"].exists)
    }

    /// 5: swiping left goes to the next, newer photo, the wall's order.
    func testSwipingFollowsTheWallOrder() {
        launchWall()
        openViewer(cell: 0)
        waitForTitle(containing: "第 6 天")
        element("photoDetail").swipeLeft()
        waitForTitle(containing: "第 7 天")
        element("photoDetail").swipeLeft()
        waitForTitle(containing: "第 8 天")
        element("photoDetail").swipeRight()
        waitForTitle(containing: "第 7 天")
    }

    /// Removing the last photo from the record returns to a wall without it.
    func testRemovingTheLastPhotoReturnsToTheWall() {
        launchWall()
        openViewer(cell: 4)
        element("photoDetailMoreButton").tap()
        XCTAssertTrue(app.buttons["removeFromRecordButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["deletePhotoButton"].exists)
        app.buttons["removeFromRecordButton"].tap()
        XCTAssertTrue(element("photoWall").waitForExistence(timeout: 5))
        XCTAssertFalse(element("photoDetail").exists)
        XCTAssertFalse(cell(4).exists)
        XCTAssertTrue(cell(3).exists)
    }

    /// 8: a portrait and a landscape photo, for the B′ comparison with D-7.
    func testScreenshotsPortraitAndLandscape() {
        launchWall(mixedAspects: true)
        openViewer(cell: 4)
        waitForTitle(containing: "第 10 天")
        XCTAssertTrue(element("photoDetailCaption").isHittable)
        let image = element("photoDetailImage")
        XCTAssertTrue(image.frame.height > image.frame.width, "portrait photo")
        XCTAssertTrue(app.frame.contains(image.frame))
        shot("photo-detail-portrait")
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(cell(3).waitForExistence(timeout: 5))
        openViewer(cell: 3)
        waitForTitle(containing: "第 9 天")
        let landscape = element("photoDetailImage")
        XCTAssertTrue(landscape.frame.width > landscape.frame.height, "landscape photo")
        XCTAssertTrue(app.frame.contains(landscape.frame))
        shot("photo-detail-landscape")
    }
}
