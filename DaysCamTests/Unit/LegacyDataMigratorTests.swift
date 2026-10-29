import XCTest
@testable import DaysCam

/// Covers the #615 acceptance table (1 ... 9) for the 1.3.0 -> 2.0 migration.
final class LegacyDataMigratorTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private let instant = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LegacyDataMigratorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "LegacyDataMigratorTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private var profilesURL: URL { directory.appendingPathComponent(ProfileStore.fileName) }
    private var backupURL: URL { directory.appendingPathComponent(LegacyDataMigrator.backupFileName) }
    private var photosURL: URL { directory.appendingPathComponent(CapturedPhotoStore.fileName) }
    private let photoIDs = ["A/L0/001", "B/L0/001", "C/L0/001", "D/L0/001", "E/L0/001"]

    private func makeStore(dataWriter: ProfileStore.DataWriter? = nil) -> ProfileStore {
        let writer: ProfileStore.DataWriter = dataWriter ?? { data, url in try data.write(to: url, options: [.atomic]) }
        return ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { self.instant },
                            defaults: defaults, scheduler: ProfileStore.immediateScheduler,
                            dataWriter: writer, notificationCenter: NotificationCenter())
    }

    /// Writes a 1.3.0-style install: three profiles, the second last used.
    @discardableResult
    private func seedLegacyInstall(lastUsedIndex: Int? = 1,
                                   photos: [String]? = nil) throws -> [CameraProfile] {
        let profiles = (1...3).map {
            CameraProfile(name: "紀錄\($0)", startDate: DateFixture.components(2025, 1, $0))
        }
        try JSONEncoder().encode(profiles).write(to: profilesURL)
        if let lastUsedIndex {
            defaults.set(profiles[lastUsedIndex].id.uuidString, forKey: ProfileStore.lastUsedProfileIDKey)
        }
        if let photos {
            try JSONEncoder().encode(photos).write(to: photosURL)
        }
        return profiles
    }

    private struct DiskFailure: Error {}

    // MARK: - 1, 2

    func testPhotosAndAlbumLandOnLastUsedProfile() throws {
        let legacy = try seedLegacyInstall(photos: photoIDs)
        defaults.set("X", forKey: "daysCamAlbumIdentifier")

        let loaded = makeStore().load()

        XCTAssertEqual(loaded.map(\.id), legacy.map(\.id))
        XCTAssertEqual(loaded[1].fallbackAssetIDs, photoIDs)
        XCTAssertEqual(loaded[0].fallbackAssetIDs, [])
        XCTAssertEqual(loaded[2].fallbackAssetIDs, [])
        XCTAssertEqual(loaded[1].albumIdentifier, "X")
        XCTAssertNil(loaded[0].albumIdentifier)
        XCTAssertEqual(defaults.integer(forKey: LegacyDataMigrator.dataVersionKey), 2)
        // Persisted too, not only in memory.
        let reloaded = makeStore().load()
        XCTAssertEqual(reloaded[1].fallbackAssetIDs, photoIDs)
    }

    func testNoAlbumKeyLeavesAlbumIdentifierNil() throws {
        try seedLegacyInstall(photos: photoIDs)
        let loaded = makeStore().load()
        XCTAssertNil(loaded[1].albumIdentifier)
    }

    func testAlbumBindsEvenWhenSwitchIsOff() throws {
        try seedLegacyInstall(photos: photoIDs)
        defaults.set(false, forKey: "savesToDaysCamAlbum")
        defaults.set("X", forKey: "daysCamAlbumIdentifier")
        XCTAssertEqual(makeStore().load()[1].albumIdentifier, "X")
    }

    // MARK: - 3, 4

    func testBackupIsByteIdenticalToOriginal() throws {
        try seedLegacyInstall(photos: photoIDs)
        let original = try Data(contentsOf: profilesURL)
        makeStore().load()
        XCTAssertEqual(try Data(contentsOf: backupURL), original)
        XCTAssertNotEqual(try Data(contentsOf: profilesURL), original)
    }

    func testExistingBackupIsNotOverwritten() throws {
        try seedLegacyInstall(photos: photoIDs)
        let sentinel = Data("keep me".utf8)
        try sentinel.write(to: backupURL)
        makeStore().load()
        XCTAssertEqual(try Data(contentsOf: backupURL), sentinel)
    }

    // MARK: - 5

    func testWriteFailureKeepsVersionOneAndRetryDoesNotDuplicate() throws {
        let legacy = try seedLegacyInstall(photos: photoIDs)
        let original = try Data(contentsOf: profilesURL)

        let failing = makeStore(dataWriter: { _, _ in throw DiskFailure() })
        failing.load()
        XCTAssertNotEqual(defaults.integer(forKey: LegacyDataMigrator.dataVersionKey), 2)
        XCTAssertEqual(try Data(contentsOf: profilesURL), original)
        XCTAssertEqual(failing.profiles.map(\.id), legacy.map(\.id))

        let loaded = makeStore().load()
        XCTAssertEqual(loaded[1].fallbackAssetIDs, photoIDs)
        XCTAssertEqual(defaults.integer(forKey: LegacyDataMigrator.dataVersionKey), 2)
    }

    func testRetryAfterPartialAttachmentDoesNotDuplicate() {
        var profile = CameraProfile(name: "a", startDate: DateFixture.components(2025, 1, 1))
        profile.fallbackAssetIDs = ["A/L0/001", "Z/L0/001"]
        try? JSONEncoder().encode(["A/L0/001", "B/L0/001", "A/L0/001"]).write(to: photosURL)
        let result = LegacyDataMigrator.migrated([profile], targetID: profile.id,
                                                 photosURL: photosURL, defaults: defaults)
        XCTAssertEqual(result[0].fallbackAssetIDs, ["A/L0/001", "Z/L0/001", "B/L0/001"])
    }

    // MARK: - 6, 7

    func testMissingLastUsedProfileFallsToFirst() throws {
        try seedLegacyInstall(lastUsedIndex: nil, photos: photoIDs)
        defaults.set(UUID().uuidString, forKey: ProfileStore.lastUsedProfileIDKey)
        let loaded = makeStore().load()
        XCTAssertEqual(loaded[0].fallbackAssetIDs, photoIDs)
        XCTAssertEqual(loaded[1].fallbackAssetIDs, [])
    }

    func testMissingPhotosFileStillCompletes() throws {
        try seedLegacyInstall()
        let loaded = makeStore().load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[1].fallbackAssetIDs, [])
        XCTAssertEqual(defaults.integer(forKey: LegacyDataMigrator.dataVersionKey), 2)
    }

    func testCorruptPhotosFileStillCompletes() throws {
        try seedLegacyInstall()
        try Data("not json".utf8).write(to: photosURL)
        let loaded = makeStore().load()
        XCTAssertEqual(loaded[1].fallbackAssetIDs, [])
        XCTAssertEqual(defaults.integer(forKey: LegacyDataMigrator.dataVersionKey), 2)
    }

    func testPhotosFileIsKept() throws {
        try seedLegacyInstall(photos: photoIDs)
        makeStore().load()
        XCTAssertTrue(FileManager.default.fileExists(atPath: photosURL.path))
    }

    // MARK: - 8, 9

    func testFreshInstallIsVersionTwoWithoutBackup() {
        let loaded = makeStore().load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(defaults.integer(forKey: LegacyDataMigrator.dataVersionKey), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func testMissingProfilesFileWithPhotosMigratesIntoSeededProfile() throws {
        try JSONEncoder().encode(photoIDs).write(to: photosURL)
        defaults.set("X", forKey: "daysCamAlbumIdentifier")
        let store = makeStore()
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].fallbackAssetIDs, photoIDs)
        XCTAssertEqual(loaded[0].albumIdentifier, "X")
        XCTAssertFalse(store.didSeedFreshInstall)
        XCTAssertEqual(defaults.integer(forKey: LegacyDataMigrator.dataVersionKey), 2)
    }

    func testCorruptFileWithFailedWritesThenNextLaunchStillMigrates() throws {
        try seedLegacyInstall(photos: photoIDs)
        try Data("not json".utf8).write(to: profilesURL)
        // Launch 1: file is set aside, re-seed and migration writes all fail.
        makeStore(dataWriter: { _, _ in throw DiskFailure() }).load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: profilesURL.path))
        XCTAssertNotEqual(defaults.integer(forKey: LegacyDataMigrator.dataVersionKey), 2)
        // Launch 2: disk works again.
        let loaded = makeStore().load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].fallbackAssetIDs, photoIDs)
        XCTAssertEqual(defaults.integer(forKey: LegacyDataMigrator.dataVersionKey), 2)
    }

    func testSecondLoadDoesNotRerunMigration() throws {
        try seedLegacyInstall(photos: photoIDs)
        makeStore().load()
        // New photos.json content must be ignored once the version is 2.
        try JSONEncoder().encode(["NEW"]).write(to: photosURL)
        let loaded = makeStore().load()
        XCTAssertEqual(loaded[1].fallbackAssetIDs, photoIDs)
    }

    // MARK: - Repair first, then migrate (#615 assumption 3)

    func testUndecodableRecordIsRepairedThenMigrated() throws {
        let good = CameraProfile(name: "好", startDate: DateFixture.components(2025, 1, 1))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode([good])) as? [[String: Any]])
        json.append(["bogus": true])
        try JSONSerialization.data(withJSONObject: json).write(to: profilesURL)
        try JSONEncoder().encode(photoIDs).write(to: photosURL)

        let store = makeStore()
        let loaded = store.load()

        XCTAssertEqual(loaded.map(\.id), [good.id])
        XCTAssertEqual(loaded[0].fallbackAssetIDs, photoIDs)
        XCTAssertEqual(store.droppedUndecodableRecordCount, 1)
        let partials = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains(".partial-") }
        XCTAssertEqual(partials.count, 1)
    }

    // MARK: - M-4 backup failure

    func testBackupFailureSkipsMigrationAndKeepsVersion() throws {
        try seedLegacyInstall(photos: photoIDs)
        let blocked = FailingCopyFileManager()
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { self.instant },
                                 defaults: defaults, fileManager: blocked,
                                 scheduler: ProfileStore.immediateScheduler,
                                 notificationCenter: NotificationCenter())
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[1].fallbackAssetIDs, [])
        XCTAssertNotEqual(defaults.integer(forKey: LegacyDataMigrator.dataVersionKey), 2)
    }
}

/// A `FileManager` whose copies always fail.
private final class FailingCopyFileManager: FileManager {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}
