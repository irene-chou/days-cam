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

        XCTAssertEqual(seeded.name, ProfileStore.defaultProfileName, "3.2")
        XCTAssertEqual(ProfileStore.defaultProfileName, "我的紀錄", "119.1")
        XCTAssertEqual(seeded.startDate, DateFixture.components(2026, 1, 10), "3.2")
        XCTAssertEqual(seeded.countingRule, .dayOne, "3.2")
        XCTAssertTrue(seeded.showDayCount, "3.2")
        XCTAssertFalse(seeded.showDate, "3.2")
        XCTAssertTrue(seeded.showName, "119.1 name is shown by default")
        XCTAssertEqual(seeded.displayUnits, [.day], "3.2")
        XCTAssertFalse(seeded.useAgeWording, "3.2")
        XCTAssertEqual(seeded.position, .anchor(.bottomTrailing), "3.2")
        XCTAssertEqual(seeded.style, OverlayStyle(legacyTheme: .classicWhite), "3.2")
    }

    /// The seeded profile must print 我的紀錄 第 1 天 on its first day, which is
    /// the whole point of seeding it (PRD G-1, TASK-119).
    func testSeededProfileRendersDayOneOnTheDayItWasSeeded() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let seeded = try XCTUnwrap(makeStore(at: instant).load().first)
        let rendered = TemplateRenderer().render(profile: seeded,
                                                 capturedAt: instant,
                                                 calendar: DateFixture.taipei)
        XCTAssertEqual(rendered, "\(ProfileStore.defaultProfileName) 第 1 天", "119.1")
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

    // MARK: - TASK-96 (#400) 96.18 fresh-install detection

    /// 96.18: only a missing file counts as a fresh install.
    func testFreshInstallIsDetectedOnlyWhenTheFileIsMissing() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10))
        let first = makeStore(at: instant)
        XCTAssertFalse(first.didSeedFreshInstall, "nothing before load()")
        first.load()
        XCTAssertTrue(first.didSeedFreshInstall, "96.18 no file → fresh install")
        XCTAssertFalse(first.didRecoverFromCorruption)

        let second = makeStore(at: instant)
        second.load()
        XCTAssertFalse(second.didSeedFreshInstall, "96.18 the file exists now")

        try XCTUnwrap("這不是 JSON".data(using: .utf8)).write(to: fileURL, options: [.atomic])
        let corrupt = makeStore(at: instant)
        corrupt.load()
        XCTAssertFalse(corrupt.didSeedFreshInstall, "96.18 a corrupt file is an existing install")
        XCTAssertTrue(corrupt.didRecoverFromCorruption)
    }

    /// 96.18: a file whose every record is invalid is corruption, not a
    /// fresh install, and a later healthy load clears the flag.
    func testFreshInstallFlagIsFalseForInvalidRecordsAndClearsOnReload() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10))
        try writeRawProfiles([CameraProfile(name: "", startDate: DateFixture.components(2025, 1, 15))])
        let store = makeStore(at: instant)
        store.load()
        XCTAssertFalse(store.didSeedFreshInstall, "96.18 invalid records → corruption path")
        XCTAssertTrue(store.didRecoverFromCorruption)
        store.load()
        XCTAssertFalse(store.didSeedFreshInstall, "a reload with the re-seeded file present is not fresh")
    }

    func testUnreadableFileIsSetAsideAndReseeded() throws {
        let garbage = "這不是 JSON"
        try XCTUnwrap(garbage.data(using: .utf8)).write(to: fileURL, options: [.atomic])

        let instant = try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10))
        let store = makeStore(at: instant)
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 1, "3.28")
        XCTAssertEqual(loaded.first?.startDate, DateFixture.components(2026, 3, 5), "3.28 reseeded for today")
        XCTAssertTrue(store.didRecoverFromCorruption, "3.28")
        XCTAssertEqual(loaded.first?.name, ProfileStore.defaultProfileName, "119.5")
        XCTAssertEqual(loaded.first?.showName, true, "119.5")

        let saved = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("\(ProfileStore.fileName).corrupt-") }
        XCTAssertEqual(saved.count, 1, "3.28 the bad file is kept, not deleted")
        let savedName = try XCTUnwrap(saved.first)
        let contents = try String(contentsOf: directory.appendingPathComponent(savedName), encoding: .utf8)
        XCTAssertEqual(contents, garbage, "3.28 kept verbatim")
    }

    /// PRD §7.3: a file that decodes but whose every record is invalid leaves
    /// the user with nothing of their own, so it is announced like a lost file.
    func testFileWhereEveryRecordIsInvalidCountsAsCorruption() throws {
        try writeRawProfiles([
            profile(name: "  "),
            profile(name: "小寶", start: DateFixture.components(2026, 13, 1))
        ])

        let instant = try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10))
        let store = makeStore(at: instant)
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 1, "reseeded with the one default profile")
        XCTAssertEqual(loaded.first?.startDate, DateFixture.components(2026, 3, 5))
        XCTAssertTrue(store.didRecoverFromCorruption,
                      "every profile the user had is gone — the same loss as an unreadable file")

        let saved = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("\(ProfileStore.fileName).corrupt-") }
        XCTAssertEqual(saved.count, 1,
                       "re-seeding overwrites the file, so the only copy is kept aside first")
    }

    /// The other side of the same rule: losing one record while the others
    /// survive stays silent. That is a deliberate trade-off, not an oversight
    /// (PRD §7.3).
    func testOneInvalidRecordAmongValidOnesStaysSilent() throws {
        try writeRawProfiles([
            profile(name: "小寶"),
            profile(name: "", start: DateFixture.components(2025, 6, 1))
        ])

        let instant = try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10))
        let store = makeStore(at: instant)
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "小寶")
        XCTAssertFalse(store.didRecoverFromCorruption)
    }

    // MARK: - TASK-134 (#474) per-record decoding

    /// Writes `profiles` and makes the records at `brokenIndexes` undecodable
    /// by giving them an outline value no build knows.
    private func writeProfiles(_ profiles: [CameraProfile], breaking brokenIndexes: Set<Int>) throws {
        let encoded = try JSONEncoder().encode(profiles)
        var array = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        for index in brokenIndexes {
            var style = try XCTUnwrap(array[index]["style"] as? [String: Any])
            style["outline"] = "futureOutline"
            array[index]["style"] = style
        }
        try JSONSerialization.data(withJSONObject: array).write(to: fileURL, options: [.atomic])
    }

    private func partialBackups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("\(ProfileStore.fileName).partial-") }
    }

    /// 134.1
    func testOneUndecodableRecordIsDroppedAndTheOthersKept() throws {
        let kept = [profile(name: "甲"), profile(name: "丙")]
        try writeProfiles([kept[0], profile(name: "乙"), kept[1]], breaking: [1])
        let original = try Data(contentsOf: fileURL)

        let store = makeStore(at: try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10)))
        let loaded = store.load()

        XCTAssertEqual(loaded.map(\.name), ["甲", "丙"], "134.1")
        XCTAssertEqual(store.droppedUndecodableRecordCount, 1, "134.1")
        XCTAssertFalse(store.didRecoverFromCorruption, "134.1 the user keeps profiles")
        let backups = try partialBackups()
        XCTAssertEqual(backups.count, 1, "134.1")
        let backup = try Data(contentsOf: directory.appendingPathComponent(try XCTUnwrap(backups.first)))
        XCTAssertEqual(backup, original, "134.1 backup is the original file")

        let reopened = makeStore(at: Date())
        XCTAssertEqual(reopened.load().map(\.name), ["甲", "丙"], "134.1 cleaned file written back")
        XCTAssertEqual(reopened.droppedUndecodableRecordCount, 0)
    }

    /// 134.2
    func testEveryRecordUndecodableBehavesLikeCorruption() throws {
        try writeProfiles([profile(name: "甲"), profile(name: "乙")], breaking: [0, 1])

        let store = makeStore(at: try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10)))
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 1, "134.2 reseeded")
        XCTAssertEqual(loaded.first?.name, ProfileStore.defaultProfileName, "134.2")
        XCTAssertTrue(store.didRecoverFromCorruption, "134.2")
        XCTAssertEqual(store.droppedUndecodableRecordCount, 0, "134.2")
        let saved = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("\(ProfileStore.fileName).corrupt-") }
        XCTAssertEqual(saved.count, 1, "134.2")
        XCTAssertTrue(try partialBackups().isEmpty, "134.2")
    }

    /// 134.2: a top level that is not an array is still corruption.
    func testNonArrayTopLevelBehavesLikeCorruption() throws {
        try XCTUnwrap("{\"a\":1}".data(using: .utf8)).write(to: fileURL)
        let store = makeStore(at: try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10)))
        store.load()
        XCTAssertTrue(store.didRecoverFromCorruption, "134.2")
    }

    /// 134.3
    func testDroppedLastUsedProfileFallsBackToAnotherProfile() throws {
        let first = profile(name: "甲")
        let second = profile(name: "乙")
        try writeProfiles([first, second], breaking: [1])
        defaults.set(second.id.uuidString, forKey: ProfileStore.lastUsedProfileIDKey)

        let store = makeStore(at: try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10)))
        store.load()

        XCTAssertEqual(store.selectedProfileID, first.id, "134.3")
        XCTAssertEqual(store.lastUsedProfileID, first.id, "134.3")
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

    // MARK: - TASK-20 (20.1 ... 20.6): ordering, duplicating, naming (PRD 0.2 FR-9)

    /// 20.1: reordering persists and survives a reload.
    func test_move_reordersAndPersists() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load() // seeds one profile ("預設")
        let a = try store.add(profile(name: "A"))
        let b = try store.add(profile(name: "B"))
        let c = try store.add(profile(name: "C"))
        // profiles is now [預設, A, B, C]; drop the seeded one so indices line
        // up with the acceptance table's [A, B, C].
        try store.delete(id: store.profiles[0].id)
        XCTAssertEqual(store.profiles.map(\.name), ["A", "B", "C"])

        // Move C (index 2) to the front (index 0).
        try store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(store.profiles.map(\.id), [c.id, a.id, b.id], "20.1")
        let reloaded = makeStore(at: instant).load()
        XCTAssertEqual(reloaded.map(\.id), [c.id, a.id, b.id], "20.1 survives a reload")
    }

    /// Multi-row moves must match SwiftUI's `.onMove` semantics, since the
    /// store no longer borrows SwiftUI's `Array.move` (PR #45 review).
    func test_move_multipleOffsetsMatchesSwiftUISemantics() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let seeded = store.profiles[0]
        for name in ["A", "B", "C", "D", "E"] {
            _ = try store.add(profile(name: name))
        }
        try store.delete(id: seeded.id)
        XCTAssertEqual(store.profiles.map(\.name), ["A", "B", "C", "D", "E"])

        // Move A and C to just before E: SwiftUI yields [B, D, A, C, E].
        try store.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        XCTAssertEqual(store.profiles.map(\.name), ["B", "D", "A", "C", "E"])

        // Move E and B to the end: SwiftUI yields [D, A, C, B, E].
        try store.move(fromOffsets: IndexSet([0, 4]), toOffset: 5)
        XCTAssertEqual(store.profiles.map(\.name), ["D", "A", "C", "B", "E"])
    }

    /// A long name duplicated repeatedly must keep "副本" and number the
    /// copies, never clipping the tag (PR #45 review, FR-9.9).
    func test_duplicate_repeatedlyOnALongNameKeepsTheSuffixAndNumbers() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let longName = "一二三四五六七八九十一二三四五六七八九十" // 20 chars
        let saved = try store.add(profile(name: longName))

        let first = try store.duplicate(id: saved.id)
        let second = try store.duplicate(id: saved.id)
        let third = try store.duplicate(id: saved.id)

        XCTAssertEqual(first.name, String(longName.prefix(17)) + " 副本")
        XCTAssertEqual(second.name, String(longName.prefix(15)) + " 副本 2")
        XCTAssertEqual(third.name, String(longName.prefix(15)) + " 副本 3")
        for copy in [first, second, third] {
            XCTAssertLessThanOrEqual(copy.name.count, CameraProfile.maximumNameLength)
        }
    }

    /// 20.2: duplicating copies every field but `id`/`name`/timestamps, inserts
    /// right after the original, and does not touch the selection.
    func test_duplicate_insertsACopyRightAfterTheOriginalWithoutChangingSelection() throws {
        // A clock that advances on every read, so `createdAt`/`updatedAt` are
        // actually distinguishable between the original and its duplicate —
        // acceptance 20.2 excludes `id`/`name`/timestamps from "must be
        // identical" precisely because they are expected to differ.
        var tick = 0
        let base = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(now: {
            defer { tick += 1 }
            return base.addingTimeInterval(TimeInterval(tick))
        })
        store.load()
        var original = profile(name: "小寶")
        original.showDate = true
        original.showName = true
        original.useAgeWording = false
        original.displayUnits = [.week, .day]
        let saved = try store.add(original)
        let other = try store.add(profile(name: "其他"))
        // `add` selects whatever it just created (FR-1.10); pin the selection
        // to something other than `saved` before duplicating, so a duplicate
        // that wrongly re-selects would be caught.
        store.select(id: other.id)

        let copy = try store.duplicate(id: saved.id)

        XCTAssertEqual(copy.name, "小寶 副本", "20.2")
        XCTAssertNotEqual(copy.id, saved.id, "20.2")
        XCTAssertNotEqual(copy.createdAt, saved.createdAt, "20.2")
        XCTAssertNotEqual(copy.updatedAt, saved.updatedAt, "20.2")
        // Every other field matches.
        XCTAssertEqual(copy.startDate, saved.startDate, "20.2")
        XCTAssertEqual(copy.countingRule, saved.countingRule, "20.2")
        XCTAssertEqual(copy.showDayCount, saved.showDayCount, "20.2")
        XCTAssertEqual(copy.showDate, saved.showDate, "20.2")
        XCTAssertEqual(copy.showName, saved.showName, "20.2")
        XCTAssertEqual(copy.displayUnits, saved.displayUnits, "20.2")
        XCTAssertEqual(copy.useAgeWording, saved.useAgeWording, "20.2")
        XCTAssertEqual(copy.position, saved.position, "20.2")
        XCTAssertEqual(copy.style, saved.style, "20.2")

        let index = try XCTUnwrap(store.profiles.firstIndex { $0.id == copy.id })
        let sourceIndex = try XCTUnwrap(store.profiles.firstIndex { $0.id == saved.id })
        XCTAssertEqual(index, sourceIndex + 1, "20.2 inserted right after the original")

        XCTAssertEqual(store.selectedProfileID, other.id, "20.2 selection must not change")
    }

    /// 20.3: duplicating the same profile again picks up the next number.
    func test_duplicate_appendsAnIncrementingNumberOnRepeatedDuplicates() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let saved = try store.add(profile(name: "小寶"))

        let firstCopy = try store.duplicate(id: saved.id)
        let secondCopy = try store.duplicate(id: saved.id)

        XCTAssertEqual(firstCopy.name, "小寶 副本", "20.3")
        XCTAssertEqual(secondCopy.name, "小寶 副本 2", "20.3")
    }

    /// 20.4: `uniqueName(base:)` on its own, the way a brand-new "新設定檔"
    /// (ui-shell, TASK-26) is expected to use it.
    func test_uniqueName_incrementsPastExistingNumberedNames() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let seeded = store.profiles[0]
        _ = try store.add(profile(name: "新設定檔"))
        _ = try store.add(profile(name: "新設定檔 2"))
        try store.delete(id: seeded.id) // start from a known slate, seed gone

        XCTAssertEqual(store.uniqueName(base: "新設定檔"), "新設定檔 3", "20.4")
    }

    /// 20.5: a 20-character name, duplicated, must still fit in 20 characters
    /// and end with "副本" rather than have it clipped off.
    func test_duplicate_truncatesA20CharacterNameButKeepsTheSuffixIntact() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let longName = "一二三四五六七八九十一二三四五六七八九十"
        XCTAssertEqual(longName.count, 20, "the fixture itself must be exactly 20 characters")
        let saved = try store.add(profile(name: longName))

        let copy = try store.duplicate(id: saved.id)

        XCTAssertLessThanOrEqual(copy.name.count, CameraProfile.maximumNameLength, "20.5")
        XCTAssertTrue(copy.name.hasSuffix(" 副本"), "20.5, got \(copy.name)")
    }

    /// 20.6: duplicating at the profile limit throws and leaves the file
    /// untouched, the same guarantee `add(_:)` already gives (3.9).
    func test_duplicate_atTheLimitThrowsAndLeavesTheFileUntouched() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let first = try XCTUnwrap(store.profiles.first)
        for index in 1..<ProfileStore.profileLimit {
            try store.add(profile(name: "設定檔 \(index)"))
        }
        XCTAssertEqual(store.profiles.count, ProfileStore.profileLimit, "20.6 precondition")

        let before = try Data(contentsOf: fileURL)
        XCTAssertThrowsError(try store.duplicate(id: first.id), "20.6") { error in
            XCTAssertEqual(error as? ProfileStoreError, .limitReached(limit: ProfileStore.profileLimit), "20.6")
        }
        let after = try Data(contentsOf: fileURL)
        XCTAssertEqual(before, after, "20.6 the file must be unchanged")
        XCTAssertEqual(store.profiles.count, ProfileStore.profileLimit, "20.6")
    }

    /// `uniqueName(base:)` truncates only when the numbering forces it —
    /// exercising the general FR-9.9 rule beyond what 20.1-20.6 cover, since
    /// none of them happen to need a base *and* a number both at once.
    func test_uniqueName_truncatesTheBaseWhenNumberingWouldOtherwiseOverflow() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let store = makeStore(at: instant)
        store.load()
        let longName = "一二三四五六七八九十一二三四五六七八九十" // 20 chars
        _ = try store.add(profile(name: longName))
        _ = try store.add(profile(name: String(longName.prefix(18)) + " 2"))

        let name = store.uniqueName(base: longName)

        XCTAssertLessThanOrEqual(name.count, CameraProfile.maximumNameLength)
        XCTAssertTrue(name.hasSuffix(" 3"), "expected the next free number, got \(name)")
    }
}
