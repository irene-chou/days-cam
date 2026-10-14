import XCTest

/// TASK-153 (#522) B′: the viewfinder shows the film date in each corner, in
/// the direction the TASK-151 table gives. `-UITestFilmDate <corner>` turns it
/// on (standing in for the panel switch of TASK-152). With
/// `DAYSCAM_UI_SHOT_DIR` in the test runner's environment the screenshots are
/// also written there.
final class FilmDateViewfinderUITests: XCTestCase {
    private func launch(corner: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString,
                                "-UITestFilmDate", corner]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) -> XCUIScreenshot {
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
        return screenshot
    }

    /// The box of the film-orange pixels in `screenshot`, in points.
    private func orangeBox(in screenshot: XCUIScreenshot) -> CGRect? {
        guard let cgImage = screenshot.image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if data[i] > 230, data[i + 1] > 110, data[i + 1] < 165, data[i + 2] < 70 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        let scale = screenshot.image.scale
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    /// 153.1, 153.2, 153.5 on screen: per corner, the ink sits in that corner
    /// of the viewfinder at 4.5% of its short edge, 3.5% tall (or wide when
    /// turned), and runs the way the table says.
    func testStampSitsInEveryCornerOfTheViewfinder() {
        // (corner, isUpright, atLeft, atTop)
        let cases: [(String, Bool, Bool, Bool)] = [
            ("bottomLeading", false, true, false),
            ("topLeading", true, true, true),
            ("topTrailing", false, false, true),
            ("bottomTrailing", true, false, false),
        ]
        for (corner, upright, atLeft, atTop) in cases {
            let app = launch(corner: corner)
            let stamp = app.otherElements["filmDateStamp"]
            XCTAssertTrue(stamp.waitForExistence(timeout: 10), corner)
            let screenshot = attach(app, "153.8_viewfinder_\(corner)")
            let box = stamp.frame
            guard let ink = orangeBox(in: screenshot) else { XCTFail("no orange ink \(corner)"); continue }
            let short = min(box.width, box.height)
            let label = "\(corner) ink \(ink) viewfinder \(box)"
            let thickness = upright ? ink.height : ink.width
            let length = upright ? ink.width : ink.height
            XCTAssertEqual(thickness / short, 0.035, accuracy: 0.005, label)
            XCTAssertGreaterThan(length, thickness * 4, label)
            let marginX = atLeft ? ink.minX - box.minX : box.maxX - ink.maxX
            let marginY = atTop ? ink.minY - box.minY : box.maxY - ink.maxY
            XCTAssertEqual(marginX / short, 0.045, accuracy: 0.005, label)
            XCTAssertEqual(marginY / short, 0.045, accuracy: 0.005, label)
            app.terminate()
        }
    }

    /// 153.1: off by default, nothing orange in the viewfinder.
    func testNothingIsDrawnWhileTheFilmDateIsOff() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestSkipOnboarding", "-UITestFreshProfiles", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["疊字設定"].waitForExistence(timeout: 10))
        XCTAssertNil(orangeBox(in: attach(app, "153.1_film-date-off")))
    }
}
