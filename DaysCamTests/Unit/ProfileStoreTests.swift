import XCTest
@testable import DaysCam

/// Covers the TASK-03 acceptance table (3.1 ... 3.32).
///
/// Every test gets its own temporary directory and its own `UserDefaults`
/// suite, and injects both the clock and the calendar, so nothing here touches
/// the real Application Support directory or the real time.
final class ProfileStoreTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProfileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ProfileStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeStore(now: @escaping () -> Date,
                           calendar: Calendar = DateFixture.taipei) -> ProfileStore {
        ProfileStore(directory: directory, calendar: calendar, now: now, defaults: defaults)
    }

    private func makeStore(at instant: Date, calendar: Calendar = DateFixture.taipei) -> ProfileStore {
        makeStore(now: { instant }, calendar: calendar)
    }

    private var fileURL: URL {
        directory.appendingPathComponent(ProfileStore.fileName)
    }

    /// Writes records straight to disk, bypassing every check the store makes,
    /// which is how the read-path rows are set up.
    private func writeRawProfiles(_ raw: [CameraProfile]) throws {
        let data = try JSONEncoder().encode(raw)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func profile(name: String = "小寶",
                         start: DateComponents = DateFixture.components(2025, 1, 15),
                         rule: CountingRule = .dayOne) -> CameraProfile {
        CameraProfile(name: name, startDate: start, countingRule: rule)
    }

    private func expectAddFailure(_ subject: CameraProfile,
                                  _ expected: CameraProfileValidationError,
                                  store: ProfileStore,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        XCTAssertThrowsError(try store.add(subject), file: file, line: line) { error in
            XCTAssertEqual(error as? ProfileStoreError, .invalidProfile(expected), file: file, line: line)
        }
    }

    // MARK: - A-1 (3.1 ... 3.4) first-launch seeding

    func testFirstLaunchSeedsExactlyOneProfile() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let loaded = makeStore(at: instant).load()
        XCTAssertEqual(loaded.count, 1, "3.1")
    }

    func testSeededProfileMatchesTheSpecifiedDefaults() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let seeded = try XCTUnwrap(makeStore(at: instant).load().first)

        XCTAssertEqual(seeded.name, "預設", "3.2")
        XCTAssertEqual(seeded.startDate, DateFixture.components(2026, 1, 10), "3.2")
        XCTAssertEqual(seeded.countingRule, .dayOne, "3.2")
        XCTAssertTrue(seeded.showDayCount, "3.2")
        XCTAssertFalse(seeded.showDate, "3.2")
        XCTAssertFalse(seeded.showName, "3.2")
        XCTAssertEqual(seeded.largestUnit, .day, "3.2")
        XCTAssertEqual(seeded.smallestUnit, .day, "3.2")
        XCTAssertFalse(seeded.useAgeWording, "3.2")
        XCTAssertEqual(seeded.position, .bottomTrailing, "3.2")
        XCTAssertEqual(seeded.themeID, .classicWhite, "3.2")
    }

    /// The seeded profile must print 第 1 天 on its first day, which is the
    /// whole point of seeding it (PRD G-1).
    func testSeededProfileRendersDayOneOnTheDayItWasSeeded() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let seeded = try XCTUnwrap(makeStore(at: instant).load().first)
        let rendered = TemplateRenderer().render(profile: seeded,
                                                 capturedAt: instant,
                                                 calendar: DateFixture.taipei)
        XCTAssertEqual(rendered, "第 1 天")
    }

    func testLastUsedProfileIdentifierPointsAtTheSeededProfile() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        let seeded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(store.lastUsedProfileID, seeded.id, "3.3")
        XCTAssertEqual(store.selectedProfileID, seeded.id, "3.3")
    }

    /// Seeding happens only when the file is absent, so a later launch must not
    /// move the start date forward.
    func testSecondLaunchDoesNotReseed() throws {
        let first = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let original = try XCTUnwrap(makeStore(at: first).load().first)

        let later = try XCTUnwrap(DateFixture.date(2026, 2, 20, hour: 10))
        let reloaded = makeStore(at: later).load()

        XCTAssertEqual(reloaded.count, 1, "3.4")
        XCTAssertEqual(reloaded.first?.id, original.id, "3.4")
        XCTAssertEqual(reloaded.first?.startDate, DateFixture.components(2026, 1, 10), "3.4")
    }

    // MARK: - A-2 (3.5 ... 3.10) CRUD

    func testAddedProfileSurvivesAReloadUnchanged() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let stored = try store.add(profile())

        let reloaded = makeStore(at: instant).load()
        XCTAssertEqual(reloaded.count, 2, "3.5")
        let found = try XCTUnwrap(reloaded.first { $0.id == stored.id }, "3.5")
        XCTAssertEqual(found, stored, "3.5 every field round-trips")
        XCTAssertEqual(found.name, "小寶", "3.5")
        XCTAssertEqual(found.startDate, DateFixture.components(2025, 1, 15), "3.5")
        XCTAssertEqual(found.countingRule, .dayOne, "3.5")
    }

    func testUpdateChangesTheNameAndStampsUpdatedAt() throws {
        var clock = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(now: { clock })
        store.load()
        var stored = try store.add(profile())

        clock = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 10))
        stored.name = "小寶貝"
        let updated = try store.update(stored)

        let reloaded = makeStore(now: { clock }).load()
        let found = try XCTUnwrap(reloaded.first { $0.id == stored.id }, "3.6")
        XCTAssertEqual(found.name, "小寶貝", "3.6")
        XCTAssertEqual(found.id, updated.id, "3.6 id is unchanged")
        XCTAssertGreaterThan(found.updatedAt, found.createdAt, "3.6")
    }

    func testDeleteRemovesOnlyTheNamedProfile() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let keep = try store.add(profile(name: "留著"))
        let remove = try store.add(profile(name: "刪掉"))

        try store.delete(id: remove.id)

        let reloaded = makeStore(at: instant).load()
        XCTAssertEqual(reloaded.count, 2, "3.7 seeded plus the kept one")
        XCTAssertFalse(reloaded.contains { $0.id == remove.id }, "3.7")
        XCTAssertTrue(reloaded.contains { $0.id == keep.id }, "3.7 the rest are untouched")
    }

    func testProfilesCanGrowToTheLimitButNoFurther() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()

        // One is already seeded, so 19 more reaches the limit of 20.
        for index in 1...19 {
            XCTAssertNoThrow(try store.add(profile(name: "設定檔 \(index)")), "3.8")
        }
        XCTAssertEqual(store.profiles.count, ProfileStore.profileLimit, "3.8")

        XCTAssertThrowsError(try store.add(profile(name: "第 21 個")), "3.9") { error in
            XCTAssertEqual(error as? ProfileStoreError, .limitReached(limit: 20), "3.9")
        }
        XCTAssertEqual(makeStore(at: instant).load().count, 20, "3.9 nothing was written")
    }

    func testTheLastRemainingProfileCannotBeDeleted() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let extra = try store.add(profile())
        try store.delete(id: extra.id)

        let survivor = try XCTUnwrap(store.profiles.first, "3.10")
        XCTAssertThrowsError(try store.delete(id: survivor.id), "3.10") { error in
            XCTAssertEqual(error as? ProfileStoreError, .lastProfile, "3.10")
        }
        XCTAssertEqual(makeStore(at: instant).load().count, 1, "3.10 still there")
    }

    // MARK: - A-3 (3.13 ... 3.16) invariant 1, the name

    func testNamesAreRejectedWhenEmptyOrTooLong() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()

        expectAddFailure(profile(name: ""), .nameEmpty, store: store)
        expectAddFailure(profile(name: "   "), .nameEmpty, store: store)
        expectAddFailure(profile(name: String(repeating: "一", count: 21)),
                         .nameTooLong(length: 21), store: store)
        XCTAssertNoThrow(try store.add(profile(name: String(repeating: "一", count: 20))), "3.16")
        XCTAssertEqual(store.profiles.count, 2, "3.13 ... 3.15 wrote nothing")
    }

    // MARK: - A-4 (3.17 ... 3.22) invariant 2 on the write path

    func testStrippableStartDateComponentsAreRemovedOnWrite() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()

        var polluted = DateFixture.components(2026, 1, 15)
        polluted.hour = 13
        polluted.minute = 30
        polluted.second = 45
        polluted.timeZone = TimeZone(identifier: "Asia/Taipei")
        polluted.calendar = Calendar(identifier: .buddhist)
        let stored = try store.add(profile(start: polluted))

        let reloaded = makeStore(at: instant).load()
        let found = try XCTUnwrap(reloaded.first { $0.id == stored.id })
        XCTAssertEqual(found.startDate.year, 2026, "3.17 ... 3.19")
        XCTAssertEqual(found.startDate.month, 1, "3.17 ... 3.19")
        XCTAssertEqual(found.startDate.day, 15, "3.17 ... 3.19")
        XCTAssertNil(found.startDate.hour, "3.17")
        XCTAssertNil(found.startDate.minute, "3.17")
        XCTAssertNil(found.startDate.second, "3.17")
        XCTAssertNil(found.startDate.timeZone, "3.18")
        XCTAssertNil(found.startDate.calendar, "3.19")
    }

    func testStartDatesThatNameNoRealDayAreRejectedOnWrite() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()

        expectAddFailure(profile(start: DateFixture.components(2026, 13, 1)),
                         .startDateNotARealDate, store: store)
        expectAddFailure(profile(start: DateFixture.components(2026, 2, 30)),
                         .startDateNotARealDate, store: store)

        var missingDay = DateComponents()
        missingDay.year = 2026
        missingDay.month = 2
        expectAddFailure(profile(start: missingDay), .startDateMissingComponents, store: store)

        XCTAssertEqual(makeStore(at: instant).load().count, 1, "3.20 ... 3.22 wrote nothing")
    }

    // MARK: - A-5 (3.23 ... 3.27) invariant 2 on the read path

    func testReadPathStripsTimeOfDayAndKeepsTheRecord() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 20, hour: 10))
        var polluted = DateFixture.components(2026, 1, 15)
        polluted.hour = 13
        polluted.minute = 30
        try writeRawProfiles([profile(start: polluted)])

        let loaded = makeStore(at: instant).load()
        XCTAssertEqual(loaded.count, 1, "3.23")
        XCTAssertEqual(loaded.first?.startDate, DateFixture.components(2026, 1, 15), "3.23")
    }

    func testReadPathDropsRecordsThatCannotBeRepaired() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 20, hour: 10))
        let good = profile(name: "好的")
        try writeRawProfiles([
            good,
            profile(name: ""),
            profile(name: "月份非法", start: DateFixture.components(2026, 13, 1))
        ])

        let loaded = makeStore(at: instant).load()
        XCTAssertEqual(loaded.count, 1, "3.24 / 3.25 the bad records are dropped")
        XCTAssertEqual(loaded.first?.id, good.id, "3.24 / 3.25 the good one survives")
    }

    /// A Buddhist calendar riding along in the components shifts the date by
    /// 543 years if anything ever reads `DateComponents.date`. After stripping,
    /// the polluted record must count identically to a clean one.
    func testReadPathStripsACalendarAndCountsIdentically() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 20, hour: 12))
        var polluted = DateFixture.components(2026, 1, 15)
        polluted.calendar = Calendar(identifier: .buddhist)
        let clean = profile(name: "乾淨", start: DateFixture.components(2026, 1, 15))
        try writeRawProfiles([clean, profile(name: "佛曆", start: polluted)])

        let loaded = makeStore(at: instant).load()
        XCTAssertEqual(loaded.count, 2, "3.26")
        XCTAssertNil(loaded.last?.startDate.calendar, "3.26")

        let renderer = TemplateRenderer()
        let outputs = loaded.map {
            renderer.render(profile: $0, capturedAt: instant, calendar: DateFixture.taipei)
        }
        XCTAssertEqual(outputs, ["第 6 天", "第 6 天"], "3.26 no 543-year shift")
    }

    /// 3.27, the most important row. The time zone combination is fixed on
    /// purpose: a carried `Asia/Taipei` (+8) only shifts the date when the
    /// device is further west, so a device in `America/New_York` (-5) is what
    /// makes the bug observable. Reverse them and the row passes even with the
    /// stripping removed entirely.
    func testCarriedTimeZoneIsStrippedOnRead() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 20, hour: 12, in: DateFixture.newYork))
        var polluted = DateFixture.components(2026, 1, 15)
        polluted.timeZone = TimeZone(identifier: "Asia/Taipei")
        try writeRawProfiles([
            profile(name: "P1", start: DateFixture.components(2026, 1, 15)),
            profile(name: "P2", start: polluted)
        ])

        let loaded = makeStore(at: instant, calendar: DateFixture.newYork).load()
        XCTAssertEqual(loaded.count, 2, "3.27")
        XCTAssertNil(loaded.last?.startDate.timeZone, "3.27 the time zone is stripped")

        let renderer = TemplateRenderer()
        let outputs = loaded.map {
            renderer.render(profile: $0, capturedAt: instant, calendar: DateFixture.newYork)
        }
        XCTAssertEqual(outputs, ["第 6 天", "第 6 天"],
                       "3.27 without stripping P2 would read 第 7 天")
    }

    // MARK: - A-6 (3.28 ... 3.31) corruption and restored state

    func testUnreadableFileIsSetAsideAndReseeded() throws {
        let garbage = "這不是 JSON"
        try XCTUnwrap(garbage.data(using: .utf8)).write(to: fileURL, options: [.atomic])

        let instant = try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10))
        let store = makeStore(at: instant)
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 1, "3.28")
        XCTAssertEqual(loaded.first?.startDate, DateFixture.components(2026, 3, 5), "3.28 reseeded for today")
        XCTAssertTrue(store.didRecoverFromCorruption, "3.28")

        let saved = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("\(ProfileStore.fileName).corrupt-") }
        XCTAssertEqual(saved.count, 1, "3.28 the bad file is kept, not deleted")
        let savedName = try XCTUnwrap(saved.first)
        let contents = try String(contentsOf: directory.appendingPathComponent(savedName), encoding: .utf8)
        XCTAssertEqual(contents, garbage, "3.28 kept verbatim")
    }

    func testRecoveryFlagIsClearOnAHealthyLoad() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        XCTAssertFalse(store.didRecoverFromCorruption, "a clean first launch is not a recovery")

        let second = makeStore(at: instant)
        second.load()
        XCTAssertFalse(second.didRecoverFromCorruption)
    }

    func testSelectionIsRememberedAcrossStores() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let extra = try store.add(profile())
        store.select(id: extra.id)

        let reopened = makeStore(at: instant)
        reopened.load()
        XCTAssertEqual(reopened.lastUsedProfileID, extra.id, "3.29")
    }

    func testUnknownSelectionFallsBackToTheFirstProfile() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        try store.add(profile())

        defaults.set(UUID().uuidString, forKey: ProfileStore.lastUsedProfileIDKey)

        let reopened = makeStore(at: instant)
        let loaded = reopened.load()
        XCTAssertEqual(reopened.lastUsedProfileID, loaded.first?.id, "3.30")
        XCTAssertNotNil(reopened.lastUsedProfileID, "3.30 never nil")
    }

    func testDeletingTheSelectedProfileMovesTheSelection() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let extra = try store.add(profile())
        XCTAssertEqual(store.selectedProfileID, extra.id, "a new profile becomes active")

        try store.delete(id: extra.id)

        let remaining = try XCTUnwrap(store.profiles.first, "3.31")
        XCTAssertEqual(store.selectedProfileID, remaining.id, "3.31")
        XCTAssertEqual(store.lastUsedProfileID, remaining.id, "3.31")
    }

    // MARK: - Atomic write

    /// The previous file must survive a rejected write, or a validation failure
    /// would cost the user every profile they had.
    func testRejectedWriteLeavesThePreviousFileIntact() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let good = try store.add(profile(name: "好的"))

        let before = try Data(contentsOf: fileURL)
        XCTAssertThrowsError(try store.add(profile(name: "")))
        let after = try Data(contentsOf: fileURL)

        XCTAssertEqual(before, after, "a rejected add must not touch the file")
        XCTAssertTrue(makeStore(at: instant).load().contains { $0.id == good.id })
    }
}
