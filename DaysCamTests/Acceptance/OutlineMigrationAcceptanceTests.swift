import XCTest
@testable import DaysCam

/// TASK-70 independent QA (70.2, 70.4), end to end through the real
/// `profiles.json`: a 0.2–0.5 file with the four old outlines, what each
/// migrates to and draws, what is written back, and the range rules on both
/// the write and the read side.
final class OutlineMigrationAcceptanceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    private var fileURL: URL { directory.appendingPathComponent(ProfileStore.fileName) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OutlineMigrationAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "OutlineMigrationAcceptance-\(UUID().uuidString)"
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

    private func record(index: Int, outline: String, outlineColor: String?, extraStyle: String = "") -> String {
        let id = String(format: "00000000-0000-0000-0000-%012d", index + 700)
        let outlineField = outlineColor.map { "\"outlineColor\":\"\($0)\"," } ?? ""
        return """
        {"id":"\(id)","name":"qa-\(index)","startDate":{"year":2026,"month":1,"day":1},\
        "countingRule":"dayOne","showDayCount":true,"showDate":false,"showName":false,\
        "displayUnits":["day"],"useAgeWording":false,\
        "position":{"x":0.5,"y":0.5},\
        "style":{"fontID":"pingFang","textColor":"#FFFFFF","outline":"\(outline)",\
        \(outlineField)\(extraStyle)"shadow":"soft","sizeScale":100},\
        "createdAt":789000000,"updatedAt":789000000}
        """
    }

    private func write(_ records: [String]) throws {
        try Data("[\(records.joined(separator: ","))]".utf8).write(to: fileURL, options: [.atomic])
    }

    private func onDiskStyles() throws -> [[String: Any]] {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [[String: Any]])
        return try json.map { try XCTUnwrap($0["style"] as? [String: Any]) }
    }

    /// What 0.5 drew for each old outline, per the card's table: the stroke
    /// width, or the box's alpha (color alpha times the box opacity) and padding.
    private struct LegacyDrawing {
        let outline: OverlayOutline
        let strokeWidth: Double?
        let boxAlphaFactor: Double?
    }

    private let legacy: [(name: String, drawing: LegacyDrawing)] = [
        ("thinStroke", LegacyDrawing(outline: .stroke, strokeWidth: 2, boxAlphaFactor: nil)),
        ("thickStroke", LegacyDrawing(outline: .stroke, strokeWidth: 4, boxAlphaFactor: nil)),
        ("translucentBox", LegacyDrawing(outline: .box, strokeWidth: nil, boxAlphaFactor: 0.5)),
        ("solidBox", LegacyDrawing(outline: .box, strokeWidth: nil, boxAlphaFactor: 1.0))
    ]

    /// 70.2: all four old values, with an automatic outline color and with
    /// opaque and translucent chosen colors, load with every profile and
    /// resolve to the same stroke width / box alpha / padding / insets 0.5 drew.
    func testFourLegacyOutlinesMigrateToTheDrawingTheyHad() throws {
        let colors: [String?] = [nil, "#0A84FF", "#0A84FF80", "#FF3B30F2"]
        var records: [String] = []
        for (oi, old) in legacy.enumerated() {
            for (ci, color) in colors.enumerated() {
                records.append(record(index: oi * 10 + ci, outline: old.name, outlineColor: color))
            }
        }
        try write(records)

        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, records.count, "70.2: no profile dropped")

        for (oi, old) in legacy.enumerated() {
            for (ci, color) in colors.enumerated() {
                let label = "\(old.name) color=\(color ?? "auto")"
                let profile = try XCTUnwrap(loaded.first { $0.name == "qa-\(oi * 10 + ci)" }, label)
                let style = profile.style
                XCTAssertEqual(style.outline, old.drawing.outline, label)
                XCTAssertEqual(style.textColor, .white, label)
                XCTAssertEqual(style.shadowPreset, .soft, label)
                XCTAssertEqual(style.sizeScale, 100, label)
                let expectedColor = color.flatMap(OverlayColor.init(hex:))
                XCTAssertEqual(style.outlineColor?.red, expectedColor?.red, "70.2: \(label): RGB untouched")
                XCTAssertEqual(style.outlineColor?.green, expectedColor?.green, "70.2: \(label): RGB untouched")
                XCTAssertEqual(style.outlineColor?.blue, expectedColor?.blue, "70.2: \(label): RGB untouched")
                XCTAssertEqual(style.outlineColor == nil, color == nil, "70.2: \(label): automatic stays automatic")

                let theme = OverlayTheme(style: style)
                let decoration = try XCTUnwrap(theme.decorations.first { decoration in
                    switch decoration {
                    case .stroke, .backgroundBox: return true
                    case .shadow: return false
                    }
                }, label)
                let oldColorAlpha = color.flatMap(OverlayColor.init(hex:))?.opacity ?? 1.0
                switch decoration {
                case let .stroke(strokeColor, width):
                    XCTAssertEqual(width, old.drawing.strokeWidth, "70.2: \(label): stroke width")
                    XCTAssertEqual(strokeColor.opacity, oldColorAlpha, accuracy: 0.0001, "70.2: \(label): stroke alpha")
                case let .backgroundBox(boxColor, opacity, cornerRadius, insets):
                    let drawnAlpha = boxColor.opacity * opacity
                    let expected = oldColorAlpha * (old.drawing.boxAlphaFactor ?? 1)
                    // Loading quantizes alpha to 8 bits (PRD 4.1): 50% is 128/255.
                    XCTAssertEqual(drawnAlpha, expected, accuracy: 1.0 / 255, "70.2: \(label): box alpha drawn")
                    XCTAssertEqual(cornerRadius, 8, "70.2: \(label): corner radius")
                    XCTAssertEqual(insets, OverlayInsets(horizontal: 12, vertical: 6), "70.2: \(label): padding 12 x 6")
                case .shadow:
                    XCTFail(label)
                }
            }
        }
    }

    /// 70.2: an old file stays loadable after the app writes it back; the old
    /// names are gone from disk, the new fields are there, and a fresh store
    /// reads back exactly what was saved.
    func testLegacyFileIsRewrittenInTheNewFormatAndRoundTrips() throws {
        try write(legacy.enumerated().map { record(index: $0.offset, outline: $0.element.name, outlineColor: $0.offset % 2 == 0 ? nil : "#0A84FF") })
        let store = try makeStore()
        var stored: [CameraProfile] = []
        for profile in store.load() { stored.append(try store.update(profile)) }

        let styles = try onDiskStyles()
        XCTAssertEqual(styles.count, 4, "70.2: no profile dropped")
        for style in styles {
            let outline = try XCTUnwrap(style["outline"] as? String)
            XCTAssertTrue(["none", "stroke", "box"].contains(outline), "70.1/70.2: old name \(outline) must not be written back")
            XCTAssertNotNil(style["strokeWidth"] as? Double, "70.4: strokeWidth written")
            XCTAssertNotNil(style["boxPadding"] as? Double, "70.4: boxPadding written")
        }

        let reopened = try makeStore().load()
        XCTAssertEqual(reopened.count, 4)
        for profile in stored {
            XCTAssertEqual(reopened.first { $0.id == profile.id }?.style, profile.style, "70.4: \(profile.name) round-trips")
        }
    }

    /// 70.2: a translucent box in the automatic color keeps being automatic
    /// when the text color changes, and keeps its alpha.
    func testTranslucentAutomaticBoxStaysAutomaticAfterAnEdit() throws {
        try write([record(index: 0, outline: "translucentBox", outlineColor: nil)])
        let store = try makeStore()
        var profile = try XCTUnwrap(store.load().first)
        XCTAssertNil(profile.style.outlineColor)
        profile.style.textColor = .black
        let stored = try store.update(profile)
        let resolved = stored.style.resolvedOutlineColor
        XCTAssertEqual(resolved.opacity, 128.0 / 255.0, accuracy: 0.0001, "alpha 50% kept, in 8-bit steps")
        XCTAssertEqual(resolved.red, OverlayColor.black.autoContrastColor.red, "contrast color follows the text color")
        XCTAssertNil(try makeStore().load().first?.style.outlineColor, "still automatic after a restart")
    }

    /// 70.2: a faint translucent box (color alpha below 10%) would halve below
    /// the 5% floor; the profile is kept with the alpha raised to the floor.
    func testFaintTranslucentBoxIsKeptAtTheFloor() throws {
        try write([record(index: 0, outline: "translucentBox", outlineColor: "#0A84FF14"),
                   record(index: 1, outline: "translucentBox", outlineColor: "#0A84FF0D")])
        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 2, "no profile dropped")
        for profile in loaded {
            XCTAssertTrue(try XCTUnwrap(profile.style.outlineColor).isStorable, profile.name)
            XCTAssertGreaterThanOrEqual(profile.style.outlineOpacity, OverlayColor.minimumStorableOpacity, profile.name)
        }
    }

    /// 70.4 (write side): stroke width and padding outside their ranges, and
    /// non-finite values, are refused and the file is left untouched; the
    /// edges themselves are accepted and survive a restart.
    func testOutOfRangeParametersAreRefusedAndNothingIsWritten() throws {
        let store = try makeStore()
        store.load()
        let base = try XCTUnwrap(store.profiles.first)
        let onDisk = try Data(contentsOf: fileURL)

        let bad: [(String, (inout OverlayStyle) -> Void)] = [
            ("strokeWidth 0.99", { $0.strokeWidth = 0.99 }),
            ("strokeWidth 0", { $0.strokeWidth = 0 }),
            ("strokeWidth 6.01", { $0.strokeWidth = 6.01 }),
            ("strokeWidth -1", { $0.strokeWidth = -1 }),
            ("strokeWidth NaN", { $0.strokeWidth = .nan }),
            ("strokeWidth inf", { $0.strokeWidth = .infinity }),
            ("boxPadding -0.01", { $0.boxPadding = -0.01 }),
            ("boxPadding 24.01", { $0.boxPadding = 24.01 }),
            ("boxPadding NaN", { $0.boxPadding = .nan }),
            ("boxPadding -inf", { $0.boxPadding = -.infinity }),
            ("autoOutlineOpacity 0.04", { $0.autoOutlineOpacity = 0.04 }),
            ("autoOutlineOpacity 1.01", { $0.autoOutlineOpacity = 1.01 }),
            ("autoOutlineOpacity NaN", { $0.autoOutlineOpacity = .nan })
        ]
        for outline in [OverlayOutline.none, .stroke, .box] {
            for (label, change) in bad {
                var candidate = base
                candidate.style.outline = outline
                change(&candidate.style)
                XCTAssertThrowsError(try store.update(candidate), "70.4: \(label) with \(outline) must be refused")
                XCTAssertThrowsError(try store.add(candidate), "70.4: add \(label) with \(outline) must be refused")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), onDisk, "70.4: refused values never reach the file")
        XCTAssertEqual(store.profiles.count, 1)

        for (stroke, padding) in [(1.0, 0.0), (6.0, 24.0), (3.5, 7.25)] {
            var candidate = base
            candidate.style.outline = .stroke
            candidate.style.strokeWidth = stroke
            candidate.style.boxPadding = padding
            XCTAssertNoThrow(try store.update(candidate), "70.4: \(stroke)/\(padding) is allowed")
            let reopened = try makeStore().load()
            XCTAssertEqual(reopened.first?.style.strokeWidth, stroke, "70.4: stroke survives a restart")
            XCTAssertEqual(reopened.first?.style.boxPadding, padding, "70.4: padding survives a restart")
        }
    }

    /// 70.4: parameters of the chosen-away outline are kept (switching from
    /// stroke to box and back does not reset the width) across a restart.
    func testParametersOfTheOtherOutlineSurviveSwitchingAndRestart() throws {
        let store = try makeStore()
        store.load()
        var profile = try XCTUnwrap(store.profiles.first)
        profile.style.outline = .stroke
        profile.style.strokeWidth = 5
        profile.style.boxPadding = 20
        _ = try store.update(profile)
        profile.style.outline = .box
        _ = try store.update(profile)
        let reopened = try XCTUnwrap(try makeStore().load().first)
        XCTAssertEqual(reopened.style.outline, .box)
        XCTAssertEqual(reopened.style.strokeWidth, 5)
        XCTAssertEqual(reopened.style.boxPadding, 20)
    }

    /// 70.4 (read side): a hand-edited out-of-range value never costs the user
    /// the profile; it is clamped into range and everything else is untouched.
    func testHandEditedOutOfRangeParametersAreClampedNotDropped() throws {
        try write([
            record(index: 0, outline: "stroke", outlineColor: nil, extraStyle: "\"strokeWidth\":99,\"boxPadding\":-5,"),
            record(index: 1, outline: "box", outlineColor: "#0A84FF", extraStyle: "\"strokeWidth\":0,\"boxPadding\":1000,\"autoOutlineOpacity\":0,"),
            record(index: 2, outline: "box", outlineColor: nil, extraStyle: "\"strokeWidth\":3,\"boxPadding\":8,\"autoOutlineOpacity\":0.4,")
        ])
        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 3, "70.4: no profile dropped")
        let first = try XCTUnwrap(loaded.first { $0.name == "qa-0" })
        XCTAssertEqual(first.style.strokeWidth, OverlayStyle.strokeWidthRange.upperBound)
        XCTAssertEqual(first.style.boxPadding, OverlayStyle.boxPaddingRange.lowerBound)
        let second = try XCTUnwrap(loaded.first { $0.name == "qa-1" })
        XCTAssertEqual(second.style.strokeWidth, OverlayStyle.strokeWidthRange.lowerBound)
        XCTAssertEqual(second.style.boxPadding, OverlayStyle.boxPaddingRange.upperBound)
        XCTAssertEqual(second.style.autoOutlineOpacity, OverlayColor.minimumStorableOpacity, accuracy: 1.0 / 255, "raised to the 13/255 floor")
        XCTAssertEqual(second.style.outlineColor, OverlayColor(hex: "#0A84FF"))
        let third = try XCTUnwrap(loaded.first { $0.name == "qa-2" })
        XCTAssertEqual(third.style.strokeWidth, 3)
        XCTAssertEqual(third.style.boxPadding, 8)
        XCTAssertEqual(third.style.autoOutlineOpacity, 0.4, accuracy: 0.005)
        for profile in loaded { XCTAssertTrue(profile.style.hasValidOutlineParameters, profile.name) }
    }

    /// 70.1: the outline has exactly three cases, and decoding no longer
    /// invents a fourth one from the current format.
    func testOutlineHasOnlyNoneStrokeBox() {
        XCTAssertEqual(OverlayOutline.allCases.map(\.rawValue), ["none", "stroke", "box"])
    }

    /// A current-format file with a 0.5 name still decodes (the two formats
    /// can meet in one file after a downgrade/upgrade), and a style missing the
    /// new keys gets the defaults.
    func testMissingNewKeysGetDefaults() throws {
        try write([record(index: 0, outline: "stroke", outlineColor: nil), record(index: 1, outline: "box", outlineColor: nil)])
        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 2)
        for profile in loaded {
            XCTAssertEqual(profile.style.strokeWidth, 2)
            XCTAssertEqual(profile.style.boxPadding, 12)
            XCTAssertEqual(profile.style.autoOutlineOpacity, 1)
        }
    }
}
