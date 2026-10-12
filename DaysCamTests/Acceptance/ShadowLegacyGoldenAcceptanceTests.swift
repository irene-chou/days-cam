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

    /// Digests produced by origin/main fca680c (one stroked fixture re-captured, see below).
    private let golden: [String: String] = [
        "new-custom-green-25": "86f26ada5031d90caa01ef5e08dcf654379565af0201b8324a3ee1ff36a5e254",
        "new-follow-text-25": "f5b00b53b35658907c07c4fded38bf18c32097a0c0bbedf33df6d21397528b4f",
        "new-shadow-off": "8910e79bbf784de02184c082abc9437b044207127332cd18fd1390d4d942af4d",
        "pre05-glow-#1C1C1E": "da7ebbcdab4c801921d5c4bcef97a72793eb4a06ebf9d5df6359e1a98f804a4a",
        "pre05-glow-#FF6B9D80": "c26b760f730dd31018b3b1e5c7629d9939c5a567c06bdb02b82b3dbbdd3520bf",
        "pre05-glow-#FFFFFF": "1c63628bcbc5ccd807a3d4ce0a35140d1f710eb16a184ea3d3192f6823b4fdde",
        // Re-captured on main after TASK-80's segmented stroke geometry
        // (ab6fae6, PR #367) landed on top of fca680c: it changes every
        // stroked pixel, not the shadow; the other digests still match fca680c.
        "pre05-glow-thinStroke": "5817d384ecee1bbc6080bcd53c4b86aea483beaebe608d575b29d90c714e1f14",
        "pre05-hard-#1C1C1E": "dd7ef8c3f3fd3685bf6718df9b8e5d52151d254474251b3d56545cd47b0fa2b6",
        "pre05-hard-#FF6B9D80": "a91bdf98cd12cc485361c2dca3bcdd49c9da5d6c35661a69491773ab87fc5d93",
        "pre05-hard-#FFFFFF": "4a3dc762c2a4df42888aed79d769a21173406d3b28093e1e92bd964c0ef3c2d7",
        "pre05-hard-solidBox": "1da2858115a3503e0f9c4c9df492aa3bc41cc6d06d51db036dec94710940009f",
        "pre05-none-#1C1C1E": "3c47677728762e7642f2d612ae5ec1e9e9af56ed094c9bf9321a72cc340bb312",
        "pre05-none-#FF6B9D80": "d7a65e5af9ac853b340ff6a56adc7c6cc87e54eee7bcdc5c7043c16539da67bf",
        "pre05-none-#FFFFFF": "8910e79bbf784de02184c082abc9437b044207127332cd18fd1390d4d942af4d",
        "pre05-soft-#1C1C1E": "d6bb0376248c14b03e16e5d30b3eca66ba45a3e8375162a47fe5ca0b49261e14",
        "pre05-soft-#FF6B9D80": "206c54182d62888f5734b90311a6a76430e3acb3c58de58ce590c625c026ccef",
        "pre05-soft-#FFFFFF": "5ab3fbdce017487daef097dfd7553d6116d80fd7c5dcaefe6945efcea0f9e15f"
    ]

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
                                     now: { instant }, defaults: defaults,
                                     scheduler: ProfileStore.immediateScheduler)
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
