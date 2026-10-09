import XCTest
import UIKit
@testable import DaysCam

/// TASK-81 core independent QA (81.2 pixels, 81.3, 81.4): `squareBox` is the
/// rounded box with radius 0 and nothing else different, it survives the real
/// `profiles.json`, old outlines read in unchanged, and a baked photo has
/// square corners where `box` has rounded ones.
final class SquareBoxAcceptanceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private var fileURL: URL { directory.appendingPathComponent(ProfileStore.fileName) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SquareBoxAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "SquareBoxAcceptance-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeStore() throws -> ProfileStore {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        return ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant }, defaults: defaults)
    }

    private func record(index: Int, outline: String, outlineColor: String? = nil) -> String {
        let id = String(format: "00000000-0000-0000-0000-%012d", index + 800)
        let outlineField = outlineColor.map { "\"outlineColor\":\"\($0)\"," } ?? ""
        return """
        {"id":"\(id)","name":"qa-\(index)","startDate":{"year":2026,"month":1,"day":1},\
        "countingRule":"dayOne","showDayCount":true,"showDate":false,"showName":false,\
        "displayUnits":["day"],"useAgeWording":false,"position":{"x":0.5,"y":0.5},\
        "style":{"fontID":"pingFang","textColor":"#FFFFFF","outline":"\(outline)",\
        \(outlineField)"shadow":"soft","sizeScale":100},\
        "createdAt":789000000,"updatedAt":789000000}
        """
    }

    private func write(_ records: [String]) throws {
        try Data("[\(records.joined(separator: ","))]".utf8).write(to: fileURL, options: [.atomic])
    }

    private func boxDecoration(of style: OverlayStyle) -> (color: OverlayColor, opacity: Double, radius: Double, insets: OverlayInsets)? {
        for decoration in OverlayTheme(style: style).decorations {
            if case let .backgroundBox(color, opacity, radius, insets) = decoration { return (color, opacity, radius, insets) }
        }
        return nil
    }

    /// 81.3 / decoration numbers: for every padding and outline color (automatic, opaque, translucent),
    /// `squareBox` equals `box` except the radius is 0; `isBox` is true for both only.
    func testSquareBoxIsTheRoundedBoxWithRadiusZero() throws {
        XCTAssertEqual(OverlayOutline.allCases.filter(\.isBox), [.box, .squareBox])
        let colors: [OverlayColor?] = [nil, .black, OverlayColor(hex: "#0A84FF"), OverlayColor(hex: "#FF3B30F2"),
                                       OverlayColor(hex: "#12345680")]
        for padding in [0.0, 1, 12, 24] {
            for color in colors {
                for opacity in [1.0, 0.5, 0.05] {
                    var style = OverlayStyle(outline: .box, outlineColor: color, autoOutlineOpacity: opacity,
                                             boxPadding: padding, shadow: .none)
                    let rounded = try XCTUnwrap(boxDecoration(of: style))
                    style.outline = .squareBox
                    let square = try XCTUnwrap(boxDecoration(of: style))
                    XCTAssertEqual(square.radius, 0)
                    XCTAssertEqual(rounded.radius, OverlayTheme.boxCornerRadius)
                    XCTAssertEqual(square.color, rounded.color, "color \(String(describing: color)) pad \(padding)")
                    XCTAssertEqual(square.opacity, rounded.opacity)
                    XCTAssertEqual(square.insets, rounded.insets, "padding \(padding)")
                    XCTAssertEqual(square.opacity, 1)
                }
            }
        }
        for outline in [OverlayOutline.none, .stroke] {
            XCTAssertNil(boxDecoration(of: OverlayStyle(outline: outline, shadow: .none)), "\(outline)")
        }
    }

    /// 81.3: switching box <-> squareBox through the model keeps padding, color and opacity.
    @MainActor
    func testSwitchingBetweenBoxShapesKeepsParameters() throws {
        let store = try makeStore()
        store.load()
        let model = StyleTabModel(profile: try XCTUnwrap(store.profiles.first),
                                  recentColorsStore: RecentColorsStore(defaults: defaults),
                                  applyFont: { _, _ in }, allProfiles: { store.profiles },
                                  updateProfile: { try? store.update($0) })
        model.selectOutline(.box)
        model.setBoxPadding(19)
        model.selectOutlineColor(OverlayColor(hex: "#336699"))
        model.setOutlineOpacityPercent(40)
        let before = model.profile.style
        for outline in [OverlayOutline.squareBox, .box, .squareBox] {
            model.selectOutline(outline)
            let after = model.profile.style
            XCTAssertEqual(after.outline, outline)
            XCTAssertEqual(after.boxPadding, before.boxPadding)
            XCTAssertEqual(after.outlineColor, before.outlineColor)
            XCTAssertEqual(after.strokeWidth, before.strokeWidth)
        }
        let reopened = try XCTUnwrap(makeStore().load().first).style
        XCTAssertEqual(reopened.outline, .squareBox, "81.4: kept after restart")
        XCTAssertEqual(reopened.boxPadding, 19)
        XCTAssertEqual(reopened.outlineColor, before.outlineColor)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [[String: Any]])
        XCTAssertEqual((raw.first?["style"] as? [String: Any])?["outline"] as? String, "squareBox")
    }

    /// 81.4: none / stroke / box (new names) and the four 0.5 names read exactly as before, and
    /// are written back without becoming squareBox.
    func testExistingOutlinesReadUnchanged() throws {
        let cases: [(String, OverlayOutline)] = [("none", .none), ("stroke", .stroke), ("box", .box),
                                                 ("thinStroke", .stroke), ("thickStroke", .stroke),
                                                 ("translucentBox", .box), ("solidBox", .box)]
        try write(cases.enumerated().map { record(index: $0.offset, outline: $0.element.0) })
        let store = try makeStore()
        let loaded = store.load()
        XCTAssertEqual(loaded.count, cases.count)
        for (index, expected) in cases.enumerated() {
            let profile = try XCTUnwrap(loaded.first { $0.name == "qa-\(index)" })
            XCTAssertEqual(profile.style.outline, expected.1, expected.0)
            XCTAssertNotEqual(profile.style.outline, .squareBox)
            _ = try store.update(profile)
        }
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [[String: Any]])
        let written = raw.compactMap { ($0["style"] as? [String: Any])?["outline"] as? String }
        XCTAssertFalse(written.contains("squareBox"))
        XCTAssertEqual(Set(written), ["none", "stroke", "box"])
    }

    /// An unknown outline raw value is not decoded to anything: the style throws dataCorrupted and the
    /// store sets the file aside (kept on disk) and seeds a default profile, flagging recovery.
    func testUnknownOutlineMakesTheStoreSetTheFileAsideNotDropItSilently() throws {
        try write([record(index: 0, outline: "futureBox")])
        let store = try makeStore()
        let loaded = store.load()
        XCTAssertTrue(store.didRecoverFromCorruption, "user is told")
        XCTAssertEqual(loaded.count, 1, "a default profile is seeded")
        XCTAssertNotEqual(loaded.first?.name, "qa-0")
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(siblings.contains { $0 != ProfileStore.fileName }, "the unreadable file is kept aside: \(siblings)")
        XCTAssertThrowsError(try JSONDecoder().decode(OverlayOutline.self, from: Data(#""squareBoxes""#.utf8)))
        XCTAssertEqual(try JSONDecoder().decode(OverlayOutline.self, from: Data(#""squareBox""#.utf8)), .squareBox)
    }

    // MARK: - baked pixels (81.2)

    private func rgba(_ image: UIImage) throws -> (data: [UInt8], width: Int, height: Int) {
        let cg = try XCTUnwrap(image.cgImage)
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                              space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    private func gray(width: Int, height: Int) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(white: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Bakes with a solid black box and returns, per corner of the box's bounding rectangle, whether that
    /// exact corner pixel is box-colored (dark) rather than the gray photo.
    private func cornerFilled(outline: OverlayOutline, padding: Double) throws -> [Bool] {
        let style = OverlayStyle(outline: outline, outlineColor: .black, boxPadding: padding, shadow: .none)
        let baked = try XCTUnwrap(OverlayRenderer().bake(image: try gray(width: 1200, height: 1600), text: "第 10 天",
                                                         style: style, placement: .anchor(.middleCenter), font: .pingFang))
        let (data, w, h) = try rgba(baked)
        func isDark(_ x: Int, _ y: Int) -> Bool { data[(y * w + x) * 4] < 40 }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where isDark(x, y) {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThan(maxX, minX, "a box was drawn")
        return [isDark(minX, minY), isDark(maxX, minY), isDark(minX, maxY), isDark(maxX, maxY)]
    }

    /// 81.2: the four corners of a baked squareBox are filled; box leaves them open.
    func testBakedSquareBoxHasSquareCornersAndBoxDoesNot() throws {
        for padding in [6.0, 12, 24] {
            XCTAssertEqual(try cornerFilled(outline: .squareBox, padding: padding), [true, true, true, true], "square pad \(padding)")
            XCTAssertEqual(try cornerFilled(outline: .box, padding: padding), [false, false, false, false], "rounded pad \(padding)")
        }
    }
}
