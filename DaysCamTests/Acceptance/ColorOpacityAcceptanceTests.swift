import XCTest
@testable import DaysCam

/// TASK-69 independent QA (69.1, 69.3, 69.4), end to end through the real
/// `profiles.json`: a pre-TASK-69 file with `#RRGGBB` colors, translucent
/// colors that survive a restart, hand-edited alphas, and out-of-range
/// colors that must not be stored.
final class ColorOpacityAcceptanceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    private var fileURL: URL { directory.appendingPathComponent(ProfileStore.fileName) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ColorOpacityAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ColorOpacityAcceptance-\(UUID().uuidString)"
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

    private func record(index: Int, textColor: String, outlineColor: String?, outline: String = "thickStroke") -> String {
        let id = String(format: "00000000-0000-0000-0000-%012d", index + 900)
        let outlineField = outlineColor.map { "\"outlineColor\":\"\($0)\"," } ?? ""
        return """
        {"id":"\(id)","name":"qa-\(index)","startDate":{"year":2026,"month":1,"day":1},\
        "countingRule":"dayOne","showDayCount":true,"showDate":false,"showName":false,\
        "displayUnits":["day"],"useAgeWording":false,\
        "position":{"x":0.\(index + 1),"y":0.5},\
        "style":{"fontID":"pingFang","textColor":"\(textColor)","outline":"\(outline)",\
        \(outlineField)"shadow":"soft","sizeScale":\(70 + index * 5)},\
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

    /// 69.1: an old `#RRGGBB` file (lower and upper case, with and without an
    /// outline color) loads with every profile, alpha 100%, and neither the
    /// load nor a later save changes any color string on disk.
    func testLegacySixDigitFileLoadsOpaqueAndNeverGainsAnAlphaSuffix() throws {
        let colors: [(text: String, outline: String?)] = [
            ("#FFFFFF", nil), ("#000000", "#000000"), ("#0a84ff", "#FFD60A"), ("#12345A", "#FF0000"), ("#FFFFFE", "#010101")
        ]
        try write(colors.enumerated().map { record(index: $0.offset, textColor: $0.element.text, outlineColor: $0.element.outline) })
        let before = try Data(contentsOf: fileURL)

        let store = try makeStore()
        let loaded = store.load()
        XCTAssertEqual(loaded.count, colors.count, "69.1: no profile dropped")
        for (index, expected) in colors.enumerated() {
            let profile = try XCTUnwrap(loaded.first { $0.name == "qa-\(index)" })
            XCTAssertEqual(profile.style.textColor.opacity, 1.0, "69.1: text alpha 100% (\(expected.text))")
            XCTAssertEqual(profile.style.textColor, OverlayColor(hex: expected.text), "69.1: text color unchanged")
            XCTAssertEqual(profile.style.outlineColor?.opacity ?? 1.0, 1.0, "69.1: outline alpha 100%")
            XCTAssertEqual(profile.style.outlineColor, expected.outline.flatMap(OverlayColor.init(hex:)), "69.1: outline color unchanged")
            XCTAssertEqual(profile.style.outline, .stroke)
            XCTAssertEqual(profile.style.strokeWidth, 4)
            XCTAssertEqual(profile.style.shadowPreset, .soft)
            XCTAssertEqual(profile.style.sizeScale, 70 + index * 5)
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), before, "69.1: load must not rewrite an untouched legacy file")

        for profile in loaded { _ = try store.update(profile) }
        let styles = try onDiskStyles()
        XCTAssertEqual(styles.count, colors.count)
        for style in styles {
            let text = try XCTUnwrap(style["textColor"] as? String)
            XCTAssertEqual(text.count, 7, "69.1: opaque text color still written as #RRGGBB, got \(text)")
            if let outline = style["outlineColor"] as? String {
                XCTAssertEqual(outline.count, 7, "69.1: opaque outline color still written as #RRGGBB, got \(outline)")
            }
        }
    }

    /// 69.3: translucent text and outline colors written through the store are
    /// stored as `#RRGGBBAA` and read back equal by a brand-new store.
    func testTranslucentColorsSurviveAFreshStoreAndAreWrittenWithAlpha() throws {
        let store = try makeStore()
        store.load()
        var profile = try XCTUnwrap(store.profiles.first)
        profile.style.textColor = OverlayColor.white.withOpacity(0.5)
        profile.style.outlineColor = OverlayColor(hex: "#0A84FF")?.withOpacity(0.25)
        let stored = try store.update(profile)

        let styles = try onDiskStyles()
        XCTAssertEqual(styles.first?["textColor"] as? String, "#FFFFFF80", "69.3")
        XCTAssertEqual(styles.first?["outlineColor"] as? String, "#0A84FF40", "69.3")

        let reopened = try makeStore()
        let loaded = reopened.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.style.textColor, stored.style.textColor, "69.3: text color round-trips exactly")
        XCTAssertEqual(loaded.first?.style.outlineColor, stored.style.outlineColor, "69.3: outline color round-trips exactly")
        XCTAssertEqual(Int(((loaded.first?.style.textColor.opacity ?? 0) * 100).rounded()), 50, "69.3: shows 50%")
        XCTAssertEqual(Int(((loaded.first?.style.outlineColor?.opacity ?? 0) * 100).rounded()), 25, "69.3: shows 25%")
    }

    /// 69.3: every one of the 256 alpha steps survives hex → color → hex, and
    /// 5% ... 100% survives a `quantized` → hex → color trip unchanged.
    func testEveryAlphaStepRoundTrips() throws {
        for alpha in 13...255 {
            let hex = alpha == 255 ? "#336699" : String(format: "#336699%02X", alpha)
            let color = try XCTUnwrap(OverlayColor(hex: hex), hex)
            XCTAssertEqual(color.hexString, hex, "hex \(hex)")
            XCTAssertEqual(try XCTUnwrap(OverlayColor(hex: color.hexString)), color, "reparse \(hex)")
            XCTAssertTrue(color.isStorable, hex)
            let data = try JSONEncoder().encode([color])
            XCTAssertEqual(try JSONDecoder().decode([OverlayColor].self, from: data), [color], "json \(hex)")
        }
        var percent = 5.0
        while percent <= 100 {
            let quantized = OverlayColor.white.withOpacity(percent / 100).quantized
            XCTAssertTrue(quantized.isStorable, "\(percent)% must be storable after quantizing")
            XCTAssertEqual(OverlayColor(hex: quantized.hexString), quantized, "\(percent)% round-trips")
            percent += 0.5
        }
    }

    /// 69.4 (read side): a hand-edited alpha below the floor never costs the
    /// user the profile; it is raised into range and the rest is untouched.
    func testHandEditedTooFaintAlphaKeepsTheProfile() throws {
        try write([
            record(index: 0, textColor: "#FFFFFF00", outlineColor: "#00000001"),
            record(index: 1, textColor: "#FFFFFF0C", outlineColor: nil),
            record(index: 2, textColor: "#FFFFFF0D", outlineColor: nil)
        ])
        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 3, "69.4: no profile dropped for a faint alpha")
        for profile in loaded {
            XCTAssertTrue(profile.style.textColor.isStorable, "69.4: \(profile.name)")
            XCTAssertGreaterThanOrEqual(profile.style.textColor.opacity, OverlayColor.minimumStorableOpacity)
            XCTAssertEqual(profile.style.sizeScale, 70 + (Int(profile.name.dropFirst(3)) ?? 0) * 5)
        }
        XCTAssertEqual(loaded.first { $0.name == "qa-0" }?.style.outlineColor?.isStorable, true)
        XCTAssertEqual(loaded.first { $0.name == "qa-2" }?.style.textColor.hexString, "#FFFFFF0D", "the floor itself is kept as is")
    }

    /// 69.4 (write side): alphas outside 5%...100%, and non-finite values, are
    /// refused for text and outline colors, and the file is left untouched.
    func testOutOfRangeColorsAreRefusedAndNothingIsWritten() throws {
        let store = try makeStore()
        store.load()
        let base = try XCTUnwrap(store.profiles.first)
        let onDisk = try Data(contentsOf: fileURL)

        let bad: [(String, OverlayColor)] = [
            ("opacity 0.04", OverlayColor(red: 1, green: 1, blue: 1, opacity: 0.04)),
            ("opacity 0.0", OverlayColor(red: 1, green: 1, blue: 1, opacity: 0)),
            ("opacity -0.5", OverlayColor(red: 1, green: 1, blue: 1, opacity: -0.5)),
            ("opacity 1.01", OverlayColor(red: 1, green: 1, blue: 1, opacity: 1.01)),
            ("opacity NaN", OverlayColor(red: 1, green: 1, blue: 1, opacity: .nan)),
            ("opacity inf", OverlayColor(red: 1, green: 1, blue: 1, opacity: .infinity)),
            ("red 1.2", OverlayColor(red: 1.2, green: 1, blue: 1, opacity: 1)),
            ("green -0.1", OverlayColor(red: 1, green: -0.1, blue: 1, opacity: 0.5))
        ]
        for (label, color) in bad {
            for target in ["text", "outline"] {
                var candidate = base
                if target == "text" { candidate.style.textColor = color } else { candidate.style.outlineColor = color }
                XCTAssertThrowsError(try store.update(candidate), "69.4: \(label) as \(target) must be refused") { error in
                    XCTAssertEqual(error as? ProfileStoreError, .invalidProfile(.colorNotStorable), "\(label) \(target)")
                }
                XCTAssertThrowsError(try store.add(candidate), "69.4: add \(label) as \(target)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), onDisk, "69.4: refused colors never reach the file")
        XCTAssertEqual(store.profiles.count, 1)

        // The floor and the ceiling themselves are accepted.
        for opacity in [OverlayColor.minimumStorableOpacity, 1.0] {
            var candidate = base
            candidate.style.textColor = OverlayColor.white.withOpacity(opacity)
            candidate.style.outlineColor = OverlayColor.black.withOpacity(opacity)
            XCTAssertNoThrow(try store.update(candidate), "69.4: opacity \(opacity) is the allowed edge")
        }
    }

    /// 69.4: malformed color strings keep failing exactly as before (not
    /// silently accepted by the longer syntax).
    func testMalformedHexStaysRejected() {
        for hex in ["", "#", "#FFF", "#FFFFF", "#FFFFFFF", "#FFFFFFFFF", "#FFFFFFFFFF", "FFFFFFFF", "#GGGGGGGG", "#FFFFFF8G", "#+FFFFFFF", "# FFFFFF"] {
            XCTAssertNil(OverlayColor(hex: hex), "should be rejected: \(hex)")
        }
    }
}
