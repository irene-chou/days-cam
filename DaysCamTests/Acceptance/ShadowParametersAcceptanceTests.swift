import XCTest
@testable import DaysCam

/// TASK-71 independent QA (71.2, 71.4, 71.5), end to end through the real
/// `profiles.json`: a 0.2–0.5 file with the four old shadows, what each
/// migrates to and draws against the literal 0.5 constants, how old and new
/// formats are told apart, what is written back, and the range rules on both
/// the write and the read side.
final class ShadowParametersAcceptanceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    private var fileURL: URL { directory.appendingPathComponent(ProfileStore.fileName) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ShadowParametersAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ShadowParametersAcceptance-\(UUID().uuidString)"
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

    /// `shadowFields` is inserted verbatim in front of `"sizeScale"`, so a
    /// record can carry the old `shadow`, the new keys, both, or neither.
    private func record(index: Int, textColor: String = "#FFFFFF", shadowFields: String) -> String {
        let id = String(format: "00000000-0000-0000-0000-%012d", index + 900)
        return """
        {"id":"\(id)","name":"qa-\(index)","startDate":{"year":2026,"month":1,"day":1},\
        "countingRule":"dayOne","showDayCount":true,"showDate":false,"showName":false,\
        "displayUnits":["day"],"useAgeWording":false,\
        "position":{"x":0.5,"y":0.5},\
        "style":{"fontID":"pingFang","textColor":"\(textColor)","outline":"none",\
        \(shadowFields)"sizeScale":100},\
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

    private func shadowDecoration(_ style: OverlayStyle) -> (offset: CGSize, blur: Double, opacity: Double, color: OverlayColor)? {
        for decoration in OverlayTheme(style: style).decorations {
            if case let .shadow(offset, blur, opacity, color) = decoration { return (offset, blur, opacity, color) }
        }
        return nil
    }

    /// What 0.5 hard-coded in `OverlayTheme.shadowDecoration` (read from
    /// origin/main, not from the new model): offset, blur, opacity, and
    /// whether the color is black or the text color.
    private let legacy: [(name: String, offset: CGSize, blur: Double, opacity: Double, followsText: Bool)] = [
        ("soft", CGSize(width: 0, height: 2), 4, 0.6, false),
        ("hard", CGSize(width: 2, height: 2), 0, 0.75, false),
        ("glow", CGSize(width: 0, height: 0), 8, 0.9, true)
    ]

    // MARK: 71.2

    /// 71.2: every old shadow, with opaque, translucent and dark text, loads
    /// with every profile and resolves to the decoration 0.5 drew, within the
    /// 8-bit step; `none` draws no shadow. The file is not rewritten by load.
    func testLegacyShadowsLoadAndDrawWhat05Drew() throws {
        let names = ["none"] + legacy.map(\.name)
        let textColors = ["#FFFFFF", "#FF6B9D80", "#1C1C1E"]
        var records: [String] = []
        for (si, name) in names.enumerated() {
            for (ci, color) in textColors.enumerated() {
                records.append(record(index: si * 10 + ci, textColor: color, shadowFields: "\"shadow\":\"\(name)\","))
            }
        }
        try write(records)
        let before = try Data(contentsOf: fileURL)

        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, records.count, "71.2: no profile dropped")
        XCTAssertEqual(try Data(contentsOf: fileURL), before, "71.2: loading an untouched legacy file must not rewrite it")

        for (si, name) in names.enumerated() {
            for (ci, color) in textColors.enumerated() {
                let label = "\(name) text=\(color)"
                let profile = try XCTUnwrap(loaded.first { $0.name == "qa-\(si * 10 + ci)" }, label)
                let style = profile.style
                XCTAssertEqual(style.textColor, OverlayColor(hex: color), "\(label): text color untouched")
                guard let old = legacy.first(where: { $0.name == name }) else {
                    XCTAssertFalse(style.showsShadow, label)
                    XCTAssertEqual(style.shadowPreset, OverlayShadowPreset.none, label)
                    XCTAssertNil(shadowDecoration(style), "71.2: none draws no shadow")
                    // none keeps the soft parameters, so turning it on gives soft.
                    var turnedOn = style
                    turnedOn.showsShadow = true
                    XCTAssertEqual(turnedOn.shadowPreset, .soft, "\(label): none -> on is soft")
                    continue
                }
                XCTAssertEqual(style.shadowPreset, OverlayShadowPreset(rawValue: name), label)
                let drawn = try XCTUnwrap(shadowDecoration(style), label)
                XCTAssertEqual(drawn.offset, old.offset, "71.2: \(label): offset")
                XCTAssertEqual(drawn.blur, old.blur, "71.2: \(label): blur")
                XCTAssertEqual(drawn.opacity, old.opacity, accuracy: 1.0 / 255, "71.2: \(label): opacity")
                XCTAssertEqual(drawn.color.opacity, 1, "71.2: \(label): color goes in opaque, alpha applied once")
                let expectedRGB = old.followsText ? try XCTUnwrap(OverlayColor(hex: color)) : OverlayColor.black
                XCTAssertEqual(drawn.color.red, expectedRGB.red, accuracy: 0.0001, "71.2: \(label): red")
                XCTAssertEqual(drawn.color.green, expectedRGB.green, accuracy: 0.0001, "71.2: \(label): green")
                XCTAssertEqual(drawn.color.blue, expectedRGB.blue, accuracy: 0.0001, "71.2: \(label): blue")
            }
        }
    }

    /// 71.2: after the app writes an old file back, the old key is gone, the
    /// six new keys are there, and a fresh store reads back what was saved.
    func testLegacyFileIsRewrittenInTheNewFormatAndRoundTrips() throws {
        try write(["none", "soft", "hard", "glow"].enumerated().map {
            record(index: $0.offset, textColor: "#FF6B9D80", shadowFields: "\"shadow\":\"\($0.element)\",")
        })
        let store = try makeStore()
        var stored: [CameraProfile] = []
        for profile in store.load() { stored.append(try store.update(profile)) }

        let styles = try onDiskStyles()
        XCTAssertEqual(styles.count, 4)
        for style in styles {
            XCTAssertNil(style["shadow"], "71.2: old shadow key must not be written back")
            for key in ["showsShadow", "shadowColorSource", "shadowColor", "shadowOffsetX", "shadowOffsetY", "shadowBlur"] {
                XCTAssertNotNil(style[key], "71.5: \(key) written")
            }
        }
        let reopened = try makeStore().load()
        XCTAssertEqual(reopened.count, 4)
        for profile in stored {
            XCTAssertEqual(reopened.first { $0.id == profile.id }?.style, profile.style, "71.5: \(profile.name) round-trips")
        }
        let presets = stored.map(\.style.shadowPreset)
        XCTAssertEqual(presets, [OverlayShadowPreset.none, .soft, .hard, .glow], "71.2/71.3: presets survive writing")
    }

    // MARK: old / new format detection

    /// The new format is recognised by `showsShadow` alone; every edge of that.
    func testFormatDetectionEdges() throws {
        let cases: [(label: String, fields: String, check: (OverlayStyle) -> Void)] = [
            ("new keys beat a stale legacy shadow (off)",
             "\"shadow\":\"glow\",\"showsShadow\":false,\"shadowColorSource\":\"custom\",\"shadowColor\":\"#00000099\",\"shadowOffsetX\":0,\"shadowOffsetY\":2,\"shadowBlur\":4,",
             { XCTAssertFalse($0.showsShadow); XCTAssertEqual($0.shadowColorSource, .custom); XCTAssertEqual($0.shadowBlur, 4) }),
            ("new keys beat a stale legacy shadow (on)",
             "\"shadow\":\"none\",\"showsShadow\":true,\"shadowColorSource\":\"custom\",\"shadowColor\":\"#FF0000CC\",\"shadowOffsetX\":-3,\"shadowOffsetY\":5,\"shadowBlur\":7,",
             { XCTAssertTrue($0.showsShadow); XCTAssertEqual($0.shadowOffsetX, -3); XCTAssertEqual($0.shadowOffsetY, 5)
               XCTAssertEqual($0.shadowBlur, 7); XCTAssertEqual($0.shadowColor, OverlayColor(hex: "#FF0000CC")) }),
            ("showsShadow alone fills the soft parameters",
             "\"showsShadow\":true,",
             { XCTAssertEqual($0.shadowPreset, .soft) }),
            ("showsShadow false alone fills the soft parameters, off",
             "\"showsShadow\":false,",
             { XCTAssertFalse($0.showsShadow); var on = $0; on.showsShadow = true; XCTAssertEqual(on.shadowPreset, .soft) }),
            ("showsShadow alone ignores a stale legacy hard",
             "\"shadow\":\"hard\",\"showsShadow\":true,",
             { XCTAssertEqual($0.shadowPreset, .soft, "new format is not mixed with the old name") }),
            ("showsShadow null reads as the old format",
             "\"showsShadow\":null,\"shadow\":\"hard\",",
             { XCTAssertEqual($0.shadowPreset, .hard) })
        ]
        for (index, entry) in cases.enumerated() {
            try write([record(index: index, shadowFields: entry.fields)])
            let loaded = try makeStore().load()
            XCTAssertEqual(loaded.count, 1, "\(entry.label): profile kept")
            if let style = loaded.first?.style { entry.check(style) }
        }
    }

    /// Records that cannot be decoded as either format fail to decode exactly
    /// as before the change, rather than being half-read.
    func testUndecodableShadowFormatsStillFailToDecode() throws {
        let decoder = JSONDecoder()
        func decode(_ fields: String) throws -> CameraProfile {
            try decoder.decode(CameraProfile.self, from: Data(record(index: 0, shadowFields: fields).utf8))
        }
        XCTAssertThrowsError(try decode("\"shadow\":\"rainbow\","), "unknown old shadow name")
        XCTAssertThrowsError(try decode(""), "neither shadow nor showsShadow")
        XCTAssertThrowsError(try decode("\"showsShadow\":\"yes\","), "showsShadow of the wrong type")
        XCTAssertThrowsError(try decode("\"showsShadow\":true,\"shadowColorSource\":\"rainbow\","), "unknown color source")
        XCTAssertNoThrow(try decode("\"showsShadow\":true,\"shadow\":\"rainbow\","), "old name is ignored once the new format is present")
    }

    // MARK: 71.5 write side

    /// 71.5: offsets and blur outside their ranges, non-finite values, and
    /// unstorable shadow colors are refused whether or not the shadow is on,
    /// and the file is left untouched; the edges are accepted and round-trip
    /// bit for bit, as do values that are not on any slider step.
    func testOutOfRangeParametersAreRefusedAndNothingIsWritten() throws {
        let store = try makeStore()
        store.load()
        let base = try XCTUnwrap(store.profiles.first)
        let onDisk = try Data(contentsOf: fileURL)

        let bad: [(String, (inout OverlayStyle) -> Void)] = [
            ("offsetX -8.01", { $0.shadowOffsetX = -8.01 }),
            ("offsetX 8.01", { $0.shadowOffsetX = 8.01 }),
            ("offsetX NaN", { $0.shadowOffsetX = .nan }),
            ("offsetX inf", { $0.shadowOffsetX = .infinity }),
            ("offsetY -9", { $0.shadowOffsetY = -9 }),
            ("offsetY 8.5", { $0.shadowOffsetY = 8.5 }),
            ("offsetY -inf", { $0.shadowOffsetY = -.infinity }),
            ("blur -0.01", { $0.shadowBlur = -0.01 }),
            ("blur 16.01", { $0.shadowBlur = 16.01 }),
            ("blur 30", { $0.shadowBlur = 30 }),
            ("blur NaN", { $0.shadowBlur = .nan }),
            ("color alpha 0.04", { $0.shadowColor = $0.shadowColor.withOpacity(0.04) }),
            ("color alpha 1.01", { $0.shadowColor = $0.shadowColor.withOpacity(1.01) }),
            ("color red 1.2", { $0.shadowColor = OverlayColor(red: 1.2, green: 0, blue: 0, opacity: 0.5) }),
            ("color green -0.1", { $0.shadowColor = OverlayColor(red: 0, green: -0.1, blue: 0, opacity: 0.5) })
        ]
        for showsShadow in [true, false] {
            for source in OverlayShadowColorSource.allCases {
                for (label, change) in bad {
                    var candidate = base
                    candidate.style.showsShadow = showsShadow
                    candidate.style.shadowColorSource = source
                    change(&candidate.style)
                    XCTAssertThrowsError(try store.update(candidate), "71.5: \(label) shows=\(showsShadow) \(source) must be refused")
                    XCTAssertThrowsError(try store.add(candidate), "71.5: add \(label) shows=\(showsShadow) \(source) must be refused")
                }
            }
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), onDisk, "71.5: refused values never reach the file")
        XCTAssertEqual(store.profiles.count, 1)

        let accepted: [(Double, Double, Double)] = [(-8, -8, 0), (8, 8, 16), (0, 0, 8), (3.37, -2.91, 11.13), (0.1, -0.1, 0.3)]
        for (x, y, blur) in accepted {
            var candidate = base
            candidate.style.showsShadow = true
            candidate.style.shadowOffsetX = x
            candidate.style.shadowOffsetY = y
            candidate.style.shadowBlur = blur
            XCTAssertNoThrow(try store.update(candidate), "71.5: \(x)/\(y)/\(blur) is allowed")
            let style = try XCTUnwrap(try makeStore().load().first).style
            XCTAssertEqual(style.shadowOffsetX, x, "71.5: X survives a restart exactly")
            XCTAssertEqual(style.shadowOffsetY, y, "71.5: Y survives a restart exactly")
            XCTAssertEqual(style.shadowBlur, blur, "71.5: blur survives a restart exactly")
        }
    }

    /// 71.5 / 71.4: custom and text-following colors, translucent shadow
    /// colors and a switched-off shadow keep every parameter across a restart;
    /// the RGB is kept while the text color is followed; alpha lands on an
    /// 8-bit step.
    func testEveryShadowStateSurvivesARestart() throws {
        let store = try makeStore()
        store.load()
        let base = try XCTUnwrap(store.profiles.first)
        let states: [(String, (inout OverlayStyle) -> Void)] = [
            ("custom red 30%", { $0.showsShadow = true; $0.shadowColorSource = .custom
                $0.shadowColor = OverlayColor(red: 1, green: 0, blue: 0, opacity: 0.3) }),
            ("follows text, rgb kept", { $0.showsShadow = true; $0.shadowColorSource = .textColor
                $0.textColor = OverlayColor(red: 0.2, green: 0.4, blue: 0.9, opacity: 0.8)
                $0.shadowColor = OverlayColor(red: 0.5, green: 0.6, blue: 0.7, opacity: 0.45) }),
            ("off with parameters kept", { $0.showsShadow = false; $0.shadowColorSource = .custom
                $0.shadowColor = OverlayColor(red: 0, green: 1, blue: 0, opacity: 1); $0.shadowOffsetX = -5; $0.shadowBlur = 12 }),
            ("minimum alpha", { $0.showsShadow = true; $0.shadowColor = $0.shadowColor.withOpacity(OverlayColor.minimumStorableOpacity) })
        ]
        for (label, change) in states {
            var candidate = base
            change(&candidate.style)
            let stored = try store.update(candidate)
            let reopened = try XCTUnwrap(try makeStore().load().first)
            XCTAssertEqual(reopened.style, stored.style, "71.5: \(label) round-trips")
            XCTAssertEqual(reopened.style.shadowColor.opacity * 255, (reopened.style.shadowColor.opacity * 255).rounded(), accuracy: 1e-9,
                           "71.5: \(label): alpha on an 8-bit step")
            XCTAssertEqual(reopened.style.showsShadow, candidate.style.showsShadow, label)
            XCTAssertEqual(reopened.style.shadowColorSource, candidate.style.shadowColorSource, label)
        }
    }

    /// 71.4: a glow follows later text color changes through the store, and
    /// draws the shadow's own alpha once.
    func testGlowFollowsTheTextColorAfterARestart() throws {
        let store = try makeStore()
        store.load()
        var profile = try XCTUnwrap(store.profiles.first)
        profile.style.applyShadowPreset(.glow)
        profile.style.textColor = OverlayColor(hex: "#0A84FF") ?? .white
        _ = try store.update(profile)
        var reopened = try XCTUnwrap(try makeStore().load().first)
        XCTAssertEqual(reopened.style.shadowPreset, .glow)
        XCTAssertEqual(shadowDecoration(reopened.style)?.color, OverlayColor(hex: "#0A84FF"))
        reopened.style.textColor = OverlayColor(hex: "#FF3B30") ?? .white
        XCTAssertEqual(shadowDecoration(reopened.style)?.color, OverlayColor(hex: "#FF3B30"), "71.4: follows the new text color")
        XCTAssertEqual(shadowDecoration(reopened.style)?.opacity ?? 0, 230.0 / 255, accuracy: 1e-9)
    }

    // MARK: 71.5 read side

    /// 71.5 (read side): a hand-edited out-of-range value never costs the user
    /// the profile; it is clamped into range and everything else is untouched.
    func testHandEditedOutOfRangeParametersAreClampedNotDropped() throws {
        func fields(_ x: Double, _ y: Double, _ blur: Double, color: String = "#000000FF", shows: Bool = true) -> String {
            "\"showsShadow\":\(shows),\"shadowColorSource\":\"custom\",\"shadowColor\":\"\(color)\",\"shadowOffsetX\":\(x),\"shadowOffsetY\":\(y),\"shadowBlur\":\(blur),"
        }
        try write([
            record(index: 0, shadowFields: fields(99, -99, 500)),
            record(index: 1, shadowFields: fields(-8.5, 8.5, -3, color: "#FF000001", shows: false)),
            record(index: 2, shadowFields: fields(2.5, -1.25, 9.75))
        ])
        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 3, "71.5: no profile dropped")
        let first = try XCTUnwrap(loaded.first { $0.name == "qa-0" }).style
        XCTAssertEqual(first.shadowOffsetX, OverlayStyle.shadowOffsetRange.upperBound)
        XCTAssertEqual(first.shadowOffsetY, OverlayStyle.shadowOffsetRange.lowerBound)
        XCTAssertEqual(first.shadowBlur, OverlayStyle.shadowBlurRange.upperBound)
        let second = try XCTUnwrap(loaded.first { $0.name == "qa-1" }).style
        XCTAssertEqual(second.shadowOffsetX, OverlayStyle.shadowOffsetRange.lowerBound)
        XCTAssertEqual(second.shadowOffsetY, OverlayStyle.shadowOffsetRange.upperBound)
        XCTAssertEqual(second.shadowBlur, OverlayStyle.shadowBlurRange.lowerBound)
        XCTAssertFalse(second.showsShadow)
        XCTAssertTrue(second.shadowColor.isStorable, "alpha 1/255 raised to the storable floor")
        XCTAssertGreaterThanOrEqual(second.shadowOpacity, OverlayColor.minimumStorableOpacity)
        let third = try XCTUnwrap(loaded.first { $0.name == "qa-2" }).style
        XCTAssertEqual(third.shadowOffsetX, 2.5)
        XCTAssertEqual(third.shadowOffsetY, -1.25)
        XCTAssertEqual(third.shadowBlur, 9.75)
        for profile in loaded { XCTAssertTrue(profile.style.hasValidShadowParameters, profile.name) }
        // The clamped profiles can then be saved (they would be refused if the clamp were skipped).
        let store = try makeStore()
        for profile in store.load() { XCTAssertNoThrow(try store.update(profile), profile.name) }
    }
}
