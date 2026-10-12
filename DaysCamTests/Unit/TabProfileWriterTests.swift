import XCTest
@testable import DaysCam

/// `TabProfileWriter` merges only the fields a tab changed since its own
/// last write; `adopt` (TASK-109) lets its baseline follow a record the tab
/// took over from the store.
@MainActor
final class TabProfileWriterTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// 109.3: the edit page turns `showName` on; the content tab adopts that
    /// record and then turns it off — the off must reach the store, which it
    /// would not if the writer still diffed against its stale baseline.
    func testAdoptingTheStoreRecordLetsAFieldChangeBackToTheOldBaseline() throws {
        let store = ProfileStore(directory: directory)
        store.load()
        let original = try XCTUnwrap(store.profiles.first)
        let writer = TabProfileWriter(baseline: original, profileStore: store)

        var fromEditPage = original
        fromEditPage.showName = true
        try store.update(fromEditPage)
        let latest = try XCTUnwrap(store.profiles.first)
        XCTAssertTrue(latest.showName)

        writer.adopt(latest)
        var fromContentTab = latest
        fromContentTab.showName = false
        try writer.write(fromContentTab)

        XCTAssertFalse(try XCTUnwrap(store.profiles.first).showName, "109.3 the content tab's off reached the store")
    }

    /// Without `adopt`, the same sequence leaves the store on — the bug the
    /// hook exists for; pinned so the wiring is not dropped by accident.
    func testWithoutAdoptingTheStaleBaselineHidesTheChange() throws {
        let store = ProfileStore(directory: directory)
        store.load()
        var seeded = try XCTUnwrap(store.profiles.first)
        seeded.showName = false // these cases start from name off
        try store.update(seeded)
        let original = seeded
        let writer = TabProfileWriter(baseline: original, profileStore: store)
        var fromEditPage = original
        fromEditPage.showName = true
        try store.update(fromEditPage)

        var fromContentTab = try XCTUnwrap(store.profiles.first)
        fromContentTab.showName = false
        try writer.write(fromContentTab)

        XCTAssertTrue(try XCTUnwrap(store.profiles.first).showName, "the stale baseline sees no change in showName")
    }

    /// `adopt` ignores another profile's record.
    func testAdoptIgnoresAnotherProfile() throws {
        let store = ProfileStore(directory: directory)
        store.load()
        var seeded = try XCTUnwrap(store.profiles.first)
        seeded.showName = false // these cases start from name off
        try store.update(seeded)
        let original = seeded
        let writer = TabProfileWriter(baseline: original, profileStore: store)
        let other = try store.add(CameraProfile(name: "別人", startDate: DateFixture.components(2026, 1, 1), showName: true))
        writer.adopt(other)
        var updated = original
        updated.showDate = true
        try writer.write(updated)
        let stored = try XCTUnwrap(store.profiles.first { $0.id == original.id })
        XCTAssertTrue(stored.showDate)
        XCTAssertFalse(stored.showName, "the other profile's showName was not merged in")
    }
}
