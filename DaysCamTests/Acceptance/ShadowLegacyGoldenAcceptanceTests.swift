import XCTest
import UIKit
import CryptoKit
@testable import DaysCam

/// TASK-86 independent QA, 86.5. Compiles against both origin/main (fca680c)
/// and the TASK-86 branch. `golden` holds SHA-256 digests of the baked pixels
/// that origin/main itself produced for hand-written pre-0.5 and 0.6 profile
/// files, loaded through `ProfileStore` and baked by `OverlayRenderer`. The
/// branch must reproduce every digest.
final class ShadowLegacyGoldenAcceptanceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ShadowLegacyGolden-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ShadowLegacyGolden-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private struct Fixture {
        let key: String
        let textColor: String
        let outline: String
        let shadowFields: String
    }

    private let fixtures: [Fixture] = {
        var list: [Fixture] = []
        for name in ["soft", "hard", "glow", "none"] {
            for color in ["#FFFFFF", "#FF6B9D80", "#1C1C1E"] {
                list.append(Fixture(key: "pre05-\(name)-\(color)", textColor: color, outline: "none",
                                    shadowFields: "\"shadow\":\"\(name)\","))
            }
        }
        // Old shadow together with an old outline.
        list.append(Fixture(key: "pre05-glow-thinStroke", textColor: "#FFFFFF", outline: "thinStroke",
                            shadowFields: "\"shadow\":\"glow\","))
        list.append(Fixture(key: "pre05-hard-solidBox", textColor: "#FFFFFF", outline: "solidBox",
                            shadowFields: "\"shadow\":\"hard\","))
        // New-format files store parameters verbatim and must bake unchanged.
        list.append(Fixture(key: "new-custom-green-25", textColor: "#FFFFFF", outline: "none",
                            shadowFields: "\"showsShadow\":true,\"shadowColorSource\":\"custom\",\"shadowColor\":\"#00C85040\",\"shadowOffsetX\":3,\"shadowOffsetY\":-2,\"shadowBlur\":6,"))
        list.append(Fixture(key: "new-follow-text-25", textColor: "#FF6B9D", outline: "none",
                            shadowFields: "\"showsShadow\":true,\"shadowColorSource\":\"textColor\",\"shadowColor\":\"#00000040\",\"shadowOffsetX\":0,\"shadowOffsetY\":0,\"shadowBlur\":8,"))
        list.append(Fixture(key: "new-shadow-off", textColor: "#FFFFFF", outline: "none",
                            shadowFields: "\"showsShadow\":false,\"shadowColorSource\":\"custom\",\"shadowColor\":\"#FF0000FF\",\"shadowOffsetX\":2,\"shadowOffsetY\":2,\"shadowBlur\":0,"))
        return list
    }()

    /// Digests produced by origin/main fca680c.
    private let golden: [String: String] = [:]

    private func record(_ fixture: Fixture) -> String {
        """
        [{"id":"00000000-0000-0000-0000-000000000955","name":"qa","startDate":{"year":2026,"month":1,"day":1},\
        "countingRule":"dayOne","showDayCount":true,"showDate":false,"showName":false,\
        "displayUnits":["day"],"useAgeWording":false,"position":{"x":0.5,"y":0.5},\
        "style":{"fontID":"pingFang","textColor":"\(fixture.textColor)","outline":"\(fixture.outline)",\
        \(fixture.shadowFields)"sizeScale":100},\
        "createdAt":789000000,"updatedAt":789000000}]
        """
    }

    private func background() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800), format: format).image { context in
            UIColor(white: 0.85, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            UIColor(white: 0.25, alpha: 1).setFill()
            context.fill(CGRect(x: 300, y: 0, width: 300, height: 800))
        }
    }

    func test86BakedPixelsMatchOriginMainDigests() throws {
        let input = background()
        let renderer = OverlayRenderer()
        var failures: [String] = []
        for fixture in fixtures {
            try Data(record(fixture).utf8).write(to: directory.appendingPathComponent(ProfileStore.fileName),
                                                 options: [.atomic])
            let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
            let store = ProfileStore(directory: directory, calendar: DateFixture.taipei,
                                     now: { instant }, defaults: defaults)
            let style = try XCTUnwrap(store.load().first).style
            let baked = try XCTUnwrap(renderer.bake(image: input, text: "第 10 天", style: style,
                                                    placement: .custom(x: 0.5, y: 0.5), font: .pingFang))
            let grid = try XCTUnwrap(PixelGrid(baked))
            let digest = SHA256.hash(data: Data(grid.bytes)).map { String(format: "%02x", $0) }.joined()
            if golden[fixture.key] != digest {
                failures.append("\"\(fixture.key)\": \"\(digest)\",")
            }
        }
        XCTAssertTrue(failures.isEmpty, "DIGESTS\n" + failures.joined(separator: "\n"))
    }
}
