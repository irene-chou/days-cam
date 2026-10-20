import XCTest
import UIKit
@testable import DaysCam

/// TASK-86 independent QA, 86.5: hand-written pre-0.5 and 0.6 profile files,
/// loaded through `ProfileStore` and baked by `OverlayRenderer`, must draw the
/// shadow they drew before the shadow parameters existed.
///
/// The first version compared SHA-256 digests captured on one simulator
/// runtime; blur and blending differ between runtimes, so they only held
/// there (#535). Now the expected pixels are drawn on the running runtime by
/// a reference written here: the text without any shadow, then Core
/// Graphics' own shadow of it, with the parameters 0.5 drew (frozen below)
/// times `decorationScale`. Both sides rasterise with the same runtime, so
/// only a real change in what is drawn makes them differ.
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

    /// A shadow in points at a 17pt font, and its color with alpha.
    private struct ExpectedShadow {
        let offsetX: CGFloat
        let offsetY: CGFloat
        let blur: CGFloat
        let red8: Int
        let green8: Int
        let blue8: Int
        let alpha8: Int
    }

    private struct Fixture {
        let key: String
        let textColor: String
        let outline: String
        let shadowFields: String
        /// What the file should draw without its shadow.
        let expectedOutline: OverlayOutline
        /// What its shadow should be; nil for none.
        let expectedShadow: ExpectedShadow?
    }

    /// The three shadows 0.2–0.5 stored by name, as 0.5 drew them (TASK-71
    /// 71.2, TASK-86). Written out on purpose: a change to the presets or to
    /// the migration has to fail here.
    private static func legacyShadow(_ name: String, textColor: String) -> ExpectedShadow? {
        // Glow takes the text's RGB; `#RRGGBB` or `#RRGGBBAA`.
        let rgb = Int(textColor.dropFirst().prefix(6), radix: 16) ?? 0
        switch name {
        case "soft":
            return ExpectedShadow(offsetX: 0, offsetY: 2, blur: 4, red8: 0, green8: 0, blue8: 0, alpha8: 153)
        case "hard":
            return ExpectedShadow(offsetX: 2, offsetY: 2, blur: 0, red8: 0, green8: 0, blue8: 0, alpha8: 191)
        case "glow":
            return ExpectedShadow(offsetX: 0, offsetY: 0, blur: 8,
                                  red8: (rgb >> 16) & 0xFF, green8: (rgb >> 8) & 0xFF, blue8: rgb & 0xFF,
                                  alpha8: 230)
        default:
            return nil
        }
    }

    private let fixtures: [Fixture] = {
        var list: [Fixture] = []
        for name in ["soft", "hard", "glow", "none"] {
            for color in ["#FFFFFF", "#FF6B9D80", "#1C1C1E"] {
                list.append(Fixture(key: "pre05-\(name)-\(color)", textColor: color, outline: "none",
                                    shadowFields: "\"shadow\":\"\(name)\",",
                                    expectedOutline: .none,
                                    expectedShadow: legacyShadow(name, textColor: color)))
            }
        }
        // Old shadow together with an old outline.
        list.append(Fixture(key: "pre05-glow-thinStroke", textColor: "#FFFFFF", outline: "thinStroke",
                            shadowFields: "\"shadow\":\"glow\",",
                            expectedOutline: .stroke,
                            expectedShadow: legacyShadow("glow", textColor: "#FFFFFF")))
        list.append(Fixture(key: "pre05-hard-solidBox", textColor: "#FFFFFF", outline: "solidBox",
                            shadowFields: "\"shadow\":\"hard\",",
                            expectedOutline: .box,
                            expectedShadow: legacyShadow("hard", textColor: "#FFFFFF")))
        // New-format files store parameters verbatim and must bake unchanged.
        list.append(Fixture(key: "new-custom-green-25", textColor: "#FFFFFF", outline: "none",
                            shadowFields: "\"showsShadow\":true,\"shadowColorSource\":\"custom\",\"shadowColor\":\"#00C85040\",\"shadowOffsetX\":3,\"shadowOffsetY\":-2,\"shadowBlur\":6,",
                            expectedOutline: .none,
                            expectedShadow: ExpectedShadow(offsetX: 3, offsetY: -2, blur: 6,
                                                           red8: 0x00, green8: 0xC8, blue8: 0x50, alpha8: 0x40)))
        list.append(Fixture(key: "new-follow-text-25", textColor: "#FF6B9D", outline: "none",
                            shadowFields: "\"showsShadow\":true,\"shadowColorSource\":\"textColor\",\"shadowColor\":\"#00000040\",\"shadowOffsetX\":0,\"shadowOffsetY\":0,\"shadowBlur\":8,",
                            expectedOutline: .none,
                            expectedShadow: ExpectedShadow(offsetX: 0, offsetY: 0, blur: 8,
                                                           red8: 0xFF, green8: 0x6B, blue8: 0x9D, alpha8: 0x40)))
        list.append(Fixture(key: "new-shadow-off", textColor: "#FFFFFF", outline: "none",
                            shadowFields: "\"showsShadow\":false,\"shadowColorSource\":\"custom\",\"shadowColor\":\"#FF0000FF\",\"shadowOffsetX\":2,\"shadowOffsetY\":2,\"shadowBlur\":0,",
                            expectedOutline: .none,
                            expectedShadow: nil))
        return list
    }()

    private let text = "第 10 天"
    private let placement = OverlayPlacement.custom(x: 0.5, y: 0.5)
    private let canvas = CGSize(width: 600, height: 800)

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
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor(white: 0.85, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            UIColor(white: 0.25, alpha: 1).setFill()
            context.fill(CGRect(x: 300, y: 0, width: 300, height: 800))
        }
    }

    /// The fixture's style as `ProfileStore` loads it from the file.
    private func loadedStyle(_ fixture: Fixture) throws -> OverlayStyle {
        try Data(record(fixture).utf8).write(to: directory.appendingPathComponent(ProfileStore.fileName),
                                             options: [.atomic])
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei,
                                 now: { instant }, defaults: defaults,
                                 scheduler: ProfileStore.immediateScheduler)
        return try XCTUnwrap(store.load().first).style
    }

    private func baked(_ style: OverlayStyle, on input: UIImage) throws -> PixelGrid {
        let image = try XCTUnwrap(OverlayRenderer().bake(image: input, text: text, style: style,
                                                         placement: placement, font: .pingFang))
        return try XCTUnwrap(PixelGrid(image))
    }

    /// What the fixture should bake to, drawn without the renderer's shadow
    /// code: the text with its expected outline and no shadow, baked onto a
    /// transparent canvas, then drawn over the photo once with Core Graphics'
    /// shadow at the expected parameters times `decorationScale`, the way
    /// 0.5 cast one shadow for the whole decorated text.
    private func reference(_ fixture: Fixture, on input: UIImage) throws -> PixelGrid {
        // 0.5's thin stroke and solid box, written out (TASK-70).
        let textStyle = OverlayStyle(textColor: try XCTUnwrap(OverlayColor(hex: fixture.textColor)),
                                     outline: fixture.expectedOutline,
                                     strokeWidth: 2,
                                     boxPadding: 12,
                                     shadow: OverlayShadowPreset.none)
        let clear = UIGraphicsImageRendererFormat()
        clear.scale = 1
        clear.opaque = false
        let transparent = UIGraphicsImageRenderer(size: canvas, format: clear).image { _ in }
        let ink = try XCTUnwrap(OverlayRenderer().bake(image: transparent, text: text, style: textStyle,
                                                       placement: placement, font: .pingFang))
        let fontSize = OverlayRenderer.fittedFontSize(for: text, style: textStyle, frameSize: canvas,
                                                      font: .pingFang)
        let scale = OverlayMetrics.decorationScale(forFontSize: fontSize)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            input.draw(at: .zero)
            if let shadow = fixture.expectedShadow {
                let color = UIColor(red: CGFloat(shadow.red8) / 255, green: CGFloat(shadow.green8) / 255,
                                    blue: CGFloat(shadow.blue8) / 255, alpha: CGFloat(shadow.alpha8) / 255)
                // A positive y offset falls downward in a UIKit renderer
                // context, as the profile's offsets read.
                context.cgContext.setShadow(offset: CGSize(width: shadow.offsetX * scale,
                                                           height: shadow.offsetY * scale),
                                            blur: shadow.blur * scale, color: color.cgColor)
            }
            ink.draw(at: .zero)
        }
        return try XCTUnwrap(PixelGrid(image))
    }

    /// Largest channel difference still counted as equal. The reference
    /// draws the text through a transparent canvas, whose premultiplied
    /// 8-bit alpha can round a glyph edge by one step; measured on iOS 26.0
    /// and 27.0, shadowless fixtures differ by at most 1 and shadowed ones
    /// not at all. Half a point of shadow offset or blur moves pixels by 2
    /// or more (`test535ComparisonCatchesShadowChanges`). Since #586 `bake`
    /// draws in an 8-bit Display P3 canvas and the reference in sRGB, so the
    /// round trip adds up to 2 more.
    private let allowedChannelDifference = 3

    /// The largest difference of any RGB channel at any pixel.
    private func maxChannelDifference(_ lhs: PixelGrid, _ rhs: PixelGrid) -> Int {
        guard lhs.width == rhs.width, lhs.height == rhs.height else { return 255 }
        var result = 0
        for offset in stride(from: 0, to: lhs.bytes.count, by: 4) {
            for component in 0..<3 {
                result = max(result, abs(Int(lhs.bytes[offset + component]) - Int(rhs.bytes[offset + component])))
            }
        }
        return result
    }

    func test86BakedPixelsMatchReferenceDrawing() throws {
        let input = background()
        var failures: [String] = []
        for fixture in fixtures {
            let difference = maxChannelDifference(try baked(try loadedStyle(fixture), on: input),
                                                  try reference(fixture, on: input))
            if difference > allowedChannelDifference {
                failures.append("\(fixture.key): max channel difference \(difference)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// The comparison is not so loose that it misses a real change: moving,
    /// blurring or darkening any fixture's shadow a little must fail it.
    func test535ComparisonCatchesShadowChanges() throws {
        let input = background()
        var missed: [String] = []
        for fixture in fixtures where fixture.expectedShadow != nil {
            let style = try loadedStyle(fixture)
            let expected = try reference(fixture, on: input)
            var changes: [(String, OverlayStyle)] = []
            var changed = style
            changed.shadowBlur += 1
            changes.append(("blur +1", changed))
            changed = style
            changed.shadowOffsetX += 1
            changes.append(("offsetX +1", changed))
            changed = style
            changed.shadowOffsetY += 1
            changes.append(("offsetY +1", changed))
            changed = style
            changed.shadowOpacity += 0.05
            changes.append(("opacity +0.05", changed))
            for (label, change) in changes {
                let difference = maxChannelDifference(try baked(change, on: input), expected)
                if difference <= allowedChannelDifference {
                    missed.append("\(fixture.key) \(label): max channel difference \(difference)")
                }
            }
        }
        XCTAssertTrue(missed.isEmpty, "Changes not caught:\n" + missed.joined(separator: "\n"))
    }
}
