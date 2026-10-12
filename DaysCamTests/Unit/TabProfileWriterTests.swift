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
        let store = ProfileStore(directory: directory, scheduler: ProfileStore.immediateScheduler)
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
        let store = ProfileStore(directory: directory, scheduler: ProfileStore.immediateScheduler)
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
        let store = ProfileStore(directory: directory, scheduler: ProfileStore.immediateScheduler)
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

    // MARK: - #492: explicit choices wait for the disk, sliders debounce

    private final class FailingWriter: @unchecked Sendable {
        private let lock = NSLock()
        private var _failing = false
        var failing: Bool { get { lock.withLock { _failing } } set { lock.withLock { _failing = newValue } } }
        func write(_ data: Data, to url: URL) throws {
            if failing { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: [.atomic])
        }
    }

    private final class HeldWork {
        var items: [DispatchWorkItem] = []
        var scheduler: ProfileStore.Scheduler { { [self] _, work in items.append(work) } }
    }

    func testContinuousAdjustmentClassification() throws {
        var base = CameraProfile(name: "寶寶", startDate: DateFixture.components(2026, 1, 1))
        func classify(_ change: (inout CameraProfile) -> Void) -> Bool {
            var updated = base
            change(&updated)
            return TabProfileWriter.isContinuousAdjustment(from: base, to: updated)
        }
        XCTAssertTrue(classify { $0.style.sizeScale = 120 })
        XCTAssertTrue(classify { $0.style.strokeWidth = 4 })
        XCTAssertTrue(classify { $0.style.boxPadding = 20 })
        XCTAssertTrue(classify { $0.style.shadowBlur = 9 })
        XCTAssertTrue(classify { $0.position = .custom(x: 0.4, y: 0.6) })
        // 147.1: the first drag event from "follow the text color" is continuous.
        base.style.shadowColorSource = .textColor
        XCTAssertTrue(classify { $0.style.shadowColorSource = .custom; $0.style.shadowColor = OverlayColor(red8: 0x7A, green8: 0x4E, blue8: 0x9C) }, "147.1")
        XCTAssertFalse(classify { $0.style.fontID = .huninn })
        XCTAssertFalse(classify { $0.style.fontWeight = "light" })
        XCTAssertFalse(classify { $0.name = "新名字" })
        XCTAssertFalse(classify { $0.showDate.toggle() })
        XCTAssertFalse(classify { $0.position = .anchor(.topLeading) })
        XCTAssertFalse(classify { $0.style.sizeScale = 120; $0.name = "混合" }, "a mixed change is explicit")
        base.style.shadowColorSource = .custom
        XCTAssertFalse(classify { $0.style.shadowColorSource = .textColor }, "147.2")
        base.style.shadowColorSource = .textColor
        base.position = .custom(x: 0.1, y: 0.1)
        XCTAssertTrue(classify { $0.position = .custom(x: 0.2, y: 0.2) })
    }

    /// The P1 of #492 round 4: a font choice must not read as applied when the
    /// save fails, and the store must not keep it either.
    func testExplicitChoiceFailsWhenTheWriteFailsAndTheStoreIsRolledBack() throws {
        let failing = FailingWriter()
        let held = HeldWork()
        let store = ProfileStore(directory: directory, scheduler: held.scheduler, dataWriter: failing.write)
        store.load()
        let original = try XCTUnwrap(store.profiles.first)
        let writer = TabProfileWriter(baseline: original, profileStore: store)
        failing.failing = true

        var chosen = original
        chosen.style.fontID = .huninn
        XCTAssertThrowsError(try writer.write(chosen))
        XCTAssertEqual(try XCTUnwrap(store.profiles.first).style.fontID, original.style.fontID, "rolled back")

        failing.failing = false
        var again = original
        again.style.fontID = .huninn
        try writer.write(again)
        XCTAssertEqual(ProfileStore(directory: directory).load().first?.style.fontID, .huninn, "written before returning")
    }

    func testSliderAdjustmentIsDebouncedNotWrittenAtOnce() throws {
        let held = HeldWork()
        let store = ProfileStore(directory: directory, scheduler: held.scheduler)
        store.load()
        let original = try XCTUnwrap(store.profiles.first)
        let writer = TabProfileWriter(baseline: original, profileStore: store)
        var slid = original
        slid.style.sizeScale = 130
        try writer.write(slid)
        XCTAssertEqual(try XCTUnwrap(store.profiles.first).style.sizeScale, 130, "memory is current")
        XCTAssertNotEqual(ProfileStore(directory: directory).load().first?.style.sizeScale, 130, "not on disk yet")
        store.flush()
        XCTAssertEqual(ProfileStore(directory: directory).load().first?.style.sizeScale, 130)
    }

    /// #492 round 4 P1: through the style tab, a weight that could not be saved
    /// is not reported as applied, and the tab and the store both go back.
    func testStyleTabWeightIsNotAppliedWhenTheWriteFails() throws {
        let failing = FailingWriter()
        let held = HeldWork()
        let store = ProfileStore(directory: directory, scheduler: held.scheduler, dataWriter: failing.write)
        store.load()
        var seeded = try XCTUnwrap(store.profiles.first)
        seeded.style.fontID = .notoSerifTC
        try store.updateAndWait(seeded)
        let writer = TabProfileWriter(baseline: seeded, profileStore: store)
        let suite = try XCTUnwrap(UserDefaults(suiteName: "TabProfileWriterTests-\(UUID().uuidString)"))
        let model = StyleTabModel(profile: seeded, recentColorsStore: RecentColorsStore(defaults: suite),
                                  applyFont: { _, _ in }, allProfiles: { store.profiles },
                                  updateProfile: writer.write)
        let before = seeded.style.resolvedFontWeight.id
        let other = try XCTUnwrap(FontCatalog.entry(for: .notoSerifTC).weights.first { $0.id != before }?.id)
        failing.failing = true

        XCTAssertFalse(model.applyFontWeight(other, for: .notoSerifTC), "not reported as applied")
        XCTAssertEqual(model.profile.style.resolvedFontWeight.id, before, "tab went back")
        XCTAssertEqual(try XCTUnwrap(store.profiles.first).style.resolvedFontWeight.id, before, "store went back")
        XCTAssertNotNil(model.lastError)

        failing.failing = false
        XCTAssertTrue(model.applyFontWeight(other, for: .notoSerifTC))
        XCTAssertEqual(ProfileStore(directory: directory).load().first?.style.resolvedFontWeight.id, other)
    }

    /// 147.1: the first picker event from "follow the text color" is debounced,
    /// not written on the main thread.
    func testFirstShadowPickerEventFromFollowTextIsDebounced() throws {
        let held = HeldWork()
        let store = ProfileStore(directory: directory, scheduler: held.scheduler)
        store.load()
        var seeded = try XCTUnwrap(store.profiles.first)
        seeded.style.shadowColorSource = .textColor
        try store.updateAndWait(seeded)
        let writer = TabProfileWriter(baseline: seeded, profileStore: store)
        let suite = try XCTUnwrap(UserDefaults(suiteName: "TabProfileWriterTests-\(UUID().uuidString)"))
        let model = StyleTabModel(profile: seeded, recentColorsStore: RecentColorsStore(defaults: suite),
                                  applyFont: { _, _ in }, allProfiles: { store.profiles },
                                  updateProfile: writer.write)
        let picked = OverlayColor(red8: 0x7A, green8: 0x4E, blue8: 0x9C)

        model.applyCustomShadowColor(picked)

        XCTAssertEqual(try XCTUnwrap(store.profiles.first).style.shadowColorSource, .custom, "memory is current")
        XCTAssertNotEqual(ProfileStore(directory: directory).load().first?.style.shadowColorSource, .custom,
                          "147.1 not written synchronously")
        XCTAssertEqual(held.items.count, 1, "debounce scheduled")
        store.flush()
        XCTAssertEqual(ProfileStore(directory: directory).load().first?.style.shadowColorSource, .custom)

        // 147.2: tapping "follow text color" writes before returning.
        model.selectShadowColor(nil)
        XCTAssertEqual(ProfileStore(directory: directory).load().first?.style.shadowColorSource, .textColor, "147.2")
    }
}
