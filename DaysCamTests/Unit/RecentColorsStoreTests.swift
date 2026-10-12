import XCTest
@testable import DaysCam

/// Covers TASK-17 17.13 ... 17.15 (PRD 0.2 FR-10.7).
final class RecentColorsStoreTests: XCTestCase {

    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "RecentColorsStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func hex(_ string: String) throws -> OverlayColor {
        try XCTUnwrap(OverlayColor(hex: string))
    }

    func testStartsEmpty() {
        XCTAssertEqual(RecentColorsStore(defaults: defaults).recentCustomColors, [])
    }

    func testKeepsSevenNewestFirst() throws {
        let store = RecentColorsStore(defaults: defaults)
        for digit in 1...8 {
            store.add(try hex("#" + String(repeating: String(digit), count: 6)))
        }
        XCTAssertEqual(store.recentCustomColors.count, 7, "17.13")
        XCTAssertEqual(store.recentCustomColors.first, try hex("#888888"), "17.13")
        XCTAssertFalse(store.recentCustomColors.contains(try hex("#111111")), "17.13")
    }

    func testReaddingMovesToFrontWithoutDuplicating() throws {
        let store = RecentColorsStore(defaults: defaults)
        store.add(try hex("#111111"))
        store.add(try hex("#222222"))
        XCTAssertEqual(store.recentCustomColors, [try hex("#222222"), try hex("#111111")], "17.14 setup")

        store.add(try hex("#111111"))
        XCTAssertEqual(store.recentCustomColors, [try hex("#111111"), try hex("#222222")], "17.14")
    }

    func testSwatchColorsAreNotAdded() throws {
        let store = RecentColorsStore(defaults: defaults)
        store.add(try hex("#FD8D32"))
        XCTAssertEqual(store.recentCustomColors, [], "17.15")
        for swatch in OverlayStyle.swatches {
            store.add(swatch)
        }
        XCTAssertEqual(store.recentCustomColors, [])
    }

    /// 149.3: no preset — the light row included — goes into the list.
    func testEveryPresetColorIsNotAdded() throws {
        let store = RecentColorsStore(defaults: defaults)
        for preset in OverlayStyle.allPresetColors {
            store.add(preset)
        }
        XCTAssertEqual(store.recentCustomColors, [], "149.3")
        store.add(try hex("#123456"))
        XCTAssertEqual(store.recentCustomColors, [try hex("#123456")], "a custom color still is")
    }

    /// The dark row and film colors of #523 are no longer presets (user
    /// decision 2026-10-13, PR #527): picked with the rainbow, they go into
    /// the list like any custom color.
    func testDroppedDarkAndFilmColorsAreAddedAsCustom() throws {
        let store = RecentColorsStore(defaults: defaults)
        let dropped = try ["#24629C", "#1C1C1E", "#FF8A1E", "#F4EBD0"].map { try hex($0) }
        for color in dropped { store.add(color) }
        XCTAssertEqual(store.recentCustomColors, dropped.reversed(), "149.3 no longer excluded")
    }

    /// A picker color that rounds to the same 8-bit hex is the same color.
    func testColorsAreComparedByHexValue() throws {
        let store = RecentColorsStore(defaults: defaults)
        store.add(OverlayColor(red: 0.2, green: 0.4, blue: 0.6))
        store.add(OverlayColor(red: 0.2001, green: 0.4001, blue: 0.6001))
        XCTAssertEqual(store.recentCustomColors.count, 1)
        // Near-swatch picker output is still a swatch.
        store.add(OverlayColor(red: 253.0 / 255.0, green: 141.0 / 255.0 + 0.0001, blue: 50.0 / 255.0))
        XCTAssertEqual(store.recentCustomColors.count, 1)
    }

    func testPersistsAcrossInstances() throws {
        let first = RecentColorsStore(defaults: defaults)
        first.add(try hex("#111111"))
        first.add(try hex("#222222"))

        XCTAssertEqual(defaults.stringArray(forKey: RecentColorsStore.defaultsKey), ["#222222", "#111111"])
        XCTAssertEqual(RecentColorsStore(defaults: defaults).recentCustomColors,
                       [try hex("#222222"), try hex("#111111")])
    }
}
