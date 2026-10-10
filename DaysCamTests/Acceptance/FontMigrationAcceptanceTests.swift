import XCTest
@testable import DaysCam

/// TASK-32 independent QA (32.2, 32.3): a 0.2 `profiles.json` with one record
/// per removed font plus one unknown value is read, saved back and read again.
/// Every record must survive, every font becomes `pingFang` on disk, and no
/// other style field changes.
final class FontMigrationAcceptanceTests: XCTestCase {
    private static let removedFontIDs = ["sfRounded", "sfPro", "sfMono", "newYork", "avenirNext",
                                         "futura", "georgia", "americanTypewriter", "didot", "snellRoundhand"]
    private static let fontValues = removedFontIDs + ["不存在"]

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FontMigrationAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "FontMigrationAcceptance-\(UUID().uuidString)"
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

    private func record(index: Int, fontID: String) -> String {
        let id = String(format: "00000000-0000-0000-0000-%012d", index + 300)
        return """
        {"id":"\(id)","name":"qa-\(index)","startDate":{"year":2026,"month":1,"day":1},\
        "countingRule":"dayOne","showDayCount":true,"showDate":false,"showName":false,\
        "displayUnits":["day"],"useAgeWording":false,\
        "position":{"x":\(Double(index + 1) / 20),"y":0.5},\
        "style":{"fontID":"\(fontID)","textColor":"#12345\(index % 10)","outline":"thickStroke",\
        "outlineColor":"#0A84FF","shadow":"glow","sizeScale":\(70 + index * 5)},\
        "createdAt":789000000,"updatedAt":789000000}
        """
    }

    private func expectedStyle(index: Int) throws -> OverlayStyle {
        var style = OverlayStyle(fontID: .pingFang,
                                 textColor: try XCTUnwrap(OverlayColor(hex: "#12345\(index % 10)")),
                                 outline: .stroke,
                                 outlineColor: try XCTUnwrap(OverlayColor(hex: "#0A84FF")),
                                 strokeWidth: 4,
                                 shadow: .glow,
                                 sizeScale: 70 + index * 5)
        // #355: presets are geometry only; a 0.2 "glow" keeps its text-color source and 230/255 alpha.
        style.shadowColorSource = .textColor
        style.shadowOpacity = 230.0 / 255
        return style
    }

    /// 32.2 + 32.3 end to end, through the real file: read, save, read again.
    func testZeroPointTwoFileWithTenOldFontsAndOneUnknownSurvivesReadSaveReread() throws {
        let fileURL = directory.appendingPathComponent(ProfileStore.fileName)
        let records = Self.fontValues.enumerated().map { record(index: $0.offset, fontID: $0.element) }
        try Data("[\(records.joined(separator: ","))]".utf8).write(to: fileURL, options: [.atomic])

        let store = try makeStore()
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 11, "no record dropped on read")
        for index in Self.fontValues.indices {
            let profile = try XCTUnwrap(loaded.first { $0.name == "qa-\(index)" }, "record \(index) missing")
            XCTAssertEqual(profile.style, try expectedStyle(index: index), "style \(Self.fontValues[index])")
            XCTAssertEqual(profile.position, .custom(x: Double(index + 1) / 20, y: 0.5), "position \(index)")
        }

        // Save every record back (update persists the whole list).
        for profile in loaded { _ = try store.update(profile) }

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [[String: Any]])
        XCTAssertEqual(json.count, 11, "no record dropped on save")
        for entry in json {
            let style = try XCTUnwrap(entry["style"] as? [String: Any])
            XCTAssertEqual(style["fontID"] as? String, "pingFang", "on-disk font")
        }

        let reloaded = try makeStore().load()
        XCTAssertEqual(reloaded.count, 11, "no record dropped on reread")
        XCTAssertEqual(reloaded.map(\.id), loaded.map(\.id))
        XCTAssertEqual(reloaded.map(\.style), loaded.map(\.style))
        XCTAssertEqual(reloaded.map(\.position), loaded.map(\.position))
        XCTAssertEqual(reloaded.map(\.name), loaded.map(\.name))
    }
}
