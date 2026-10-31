import Photos
import UIKit
import XCTest
@testable import DaysCam

/// #617 acceptance 2–5, 7, 8: the 紀錄 list's rows, deletion and the album
/// picker, over a real `ProfileStore` and a `FakeRecordAlbumLibrary`.
@MainActor
final class RecordListModelTests: XCTestCase {
    private final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private var clock = Clock(Date())

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RecordListModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "RecordListModelTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        clock = Clock(try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8)))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeStore() -> ProfileStore {
        let clock = clock
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { clock.now },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        store.load()
        return store
    }

    private func makeModel(store: ProfileStore, library: FakeRecordAlbumLibrary) -> RecordListModel {
        let clock = clock
        let calculator = DayCountCalculator(calendar: DateFixture.taipei, now: { clock.now })
        return RecordListModel(store: store, library: library, calendar: DateFixture.taipei, calculator: calculator)
    }

    @discardableResult
    private func addRecord(_ name: String, to store: ProfileStore, start: DateComponents? = nil,
                           albumIdentifier: String? = nil) throws -> CameraProfile {
        clock.now = clock.now.addingTimeInterval(60)
        return try store.add(CameraProfile(name: name, startDate: start ?? DateFixture.components(2026, 1, 1),
                                           albumIdentifier: albumIdentifier))
    }

    private func photos(_ count: Int) -> [FakeRecordAlbumLibrary.Asset] {
        (1...max(count, 1)).prefix(count).map { FakeRecordAlbumLibrary.Asset(id: "p\($0)") }
    }

    // MARK: Rows (2, 3, 4)

    /// 2: no access reads "—".
    func testSubtitleShowsDashWithoutAccess() throws {
        let store = makeStore()
        try addRecord("小寶", to: store)
        let model = makeModel(store: store, library: FakeRecordAlbumLibrary(status: .denied))
        XCTAssertEqual(model.rows.first { $0.name == "小寶" }?.subtitle, "今天第 10 天 · —")
    }

    /// 3: with access and a bound album the count follows the album.
    func testSubtitleCountsTheBoundAlbum() throws {
        let store = makeStore()
        try addRecord("小寶", to: store, albumIdentifier: "album-1")
        let library = FakeRecordAlbumLibrary(status: .authorized, assets: photos(5),
                                             albums: [.init(id: "album-1", title: "寶寶", assetIDs: (1...5).map { "p\($0)" })])
        let model = makeModel(store: store, library: library)
        XCTAssertEqual(model.rows.first { $0.name == "小寶" }?.subtitle, "今天第 10 天 · 5 張")
    }

    /// #640-6: under limited access each row counts only its record's visible
    /// fallback ids, the same photos its wall shows.
    func testLimitedSubtitleCountMatchesTheWall() throws {
        let store = makeStore()
        var first = try addRecord("甲", to: store)
        var second = try addRecord("乙", to: store)
        first.fallbackAssetIDs = ["p1", "p2", "gone"]
        second.fallbackAssetIDs = ["p3"]
        try store.updateAndWait(first)
        try store.updateAndWait(second)
        let library = FakeRecordAlbumLibrary(status: .limited, assets: photos(4))
        library.visibleIDs = ["p1", "p2", "p3", "p4"]
        let model = makeModel(store: store, library: library)
        for record in [first, second] {
            let wall = PhotoWallModel(profileID: record.id, store: store, library: library,
                                      calendar: DateFixture.taipei, todayText: { _ in "" })
            XCTAssertEqual(model.rows.first { $0.id == record.id }?.subtitle,
                           "今天第 10 天 · \(wall.photoIDs.count) 張", "640-6 \(record.name)")
        }
        XCTAssertEqual(model.rows.first { $0.id == first.id }?.subtitle, "今天第 10 天 · 2 張")
        XCTAssertEqual(model.rows.first { $0.id == second.id }?.subtitle, "今天第 10 天 · 1 張")
    }

    /// FR-16.3: a start date still ahead reads as the countdown.
    func testFutureStartDateReadsAsCountdown() throws {
        let store = makeStore()
        try addRecord("預產期", to: store, start: DateFixture.components(2026, 1, 15))
        let model = makeModel(store: store, library: FakeRecordAlbumLibrary(status: .denied))
        XCTAssertEqual(model.rows.first { $0.name == "預產期" }?.subtitle, "還有 5 天 · —")
    }

    /// 4: newest `updatedAt` first.
    func testRowsAreNewestFirst() throws {
        let store = makeStore()
        let a = try addRecord("甲", to: store)
        try addRecord("乙", to: store)
        let model = makeModel(store: store, library: FakeRecordAlbumLibrary(status: .denied))
        XCTAssertEqual(model.rows.map(\.name).prefix(2), ["乙", "甲"])

        clock.now = clock.now.addingTimeInterval(600)
        var edited = try XCTUnwrap(store.profiles.first { $0.id == a.id })
        edited.name = "甲改"
        try store.update(edited)
        XCTAssertEqual(model.rows.first?.name, "甲改")
    }

    // MARK: Deleting (5)

    func testDeletionNeedsConfirmationAndKeepsTheLastRecord() throws {
        let store = makeStore()
        let model = makeModel(store: store, library: FakeRecordAlbumLibrary())
        let only = try XCTUnwrap(store.profiles.first)
        XCTAssertFalse(model.canDelete)
        model.requestDeletion(of: only.id)
        XCTAssertNil(model.deletionCandidate)

        let second = try addRecord("乙", to: store)
        XCTAssertTrue(model.canDelete)
        model.requestDeletion(of: second.id)
        XCTAssertEqual(model.deletionCandidate?.id, second.id)
        model.confirmDeletion()
        XCTAssertEqual(store.profiles.count, 1)
    }

    // MARK: Album picker (7, 8)

    func testPickingAnAlbumBindsItAndKeepsFallbackIDs() throws {
        let store = makeStore()
        var record = try addRecord("小寶", to: store)
        record.fallbackAssetIDs = ["keep-1", "keep-2"]
        try store.update(record)
        let library = FakeRecordAlbumLibrary(status: .authorized,
                                             albums: [.init(id: "album-1", title: "寶寶", assetIDs: [])])
        let picker = AlbumPickerModel(profileID: record.id, store: store, library: library)

        picker.select(albumIdentifier: "album-1")
        XCTAssertEqual(store.profiles.first { $0.id == record.id }?.albumIdentifier, "album-1")
        XCTAssertEqual(store.profiles.first { $0.id == record.id }?.fallbackAssetIDs, ["keep-1", "keep-2"])

        picker.select(albumIdentifier: nil)
        XCTAssertNil(store.profiles.first { $0.id == record.id }?.albumIdentifier)
        XCTAssertEqual(store.profiles.first { $0.id == record.id }?.fallbackAssetIDs, ["keep-1", "keep-2"])
    }

    func testAlbumBoundElsewhereIsLabelledButSelectable() async throws {
        let store = makeStore()
        try addRecord("甲", to: store, albumIdentifier: "album-1")
        let mine = try addRecord("乙", to: store)
        let library = FakeRecordAlbumLibrary(status: .authorized,
                                             albums: [.init(id: "album-1", title: "共用", assetIDs: [])])
        let picker = AlbumPickerModel(profileID: mine.id, store: store, library: library)
        await picker.load()

        let options = picker.options
        XCTAssertNil(options.first?.id, "the create row comes first")
        XCTAssertTrue(options[0].isSelected)
        XCTAssertEqual(options[0].title, "建立新相簿「乙」")
        let shared = try XCTUnwrap(options.first { $0.id == "album-1" })
        XCTAssertEqual(shared.usedBy, "甲")
        XCTAssertEqual(shared.detail, "0 張 · 已被「甲」使用")

        picker.select(albumIdentifier: "album-1")
        XCTAssertEqual(store.profiles.first { $0.id == mine.id }?.albumIdentifier, "album-1")
        XCTAssertTrue(picker.options.first { $0.id == "album-1" }?.isSelected == true)
    }

    func testPickerRequestsAccessOnlyWhenUndetermined() async throws {
        let store = makeStore()
        let record = try XCTUnwrap(store.profiles.first)
        let library = FakeRecordAlbumLibrary(status: .notDetermined)
        let model = makeModel(store: store, library: library)
        XCTAssertEqual(library.authorizationStatus(), .notDetermined, "the list never asks")
        _ = model.rows

        let picker = model.albumPickerModel(for: record.id)
        await picker.load()
        XCTAssertEqual(library.authorizationStatus(), .authorized)
    }

    /// #649-5: the album row's four states.
    func testAlbumRowStatesFollowPhotoAccess() throws {
        let store = makeStore()
        let record = try XCTUnwrap(store.profiles.first)
        let undecided = makeModel(store: store, library: FakeRecordAlbumLibrary(status: .notDetermined))
        XCTAssertEqual(undecided.albumRowState(for: record), .notAsked(title: "建立時會在「照片」App 建立「\(record.name)」"))
        let limited = makeModel(store: store, library: FakeRecordAlbumLibrary(status: .limited))
        XCTAssertEqual(limited.albumRowState(for: record), .needsSettings(title: "只允許部分照片時無法選相簿"))
        for status in [PHAuthorizationStatus.denied, .restricted] {
            let model = makeModel(store: store, library: FakeRecordAlbumLibrary(status: status))
            XCTAssertEqual(model.albumRowState(for: record), .needsSettings(title: "需要「照片」權限"), "\(status)")
        }
        let open = makeModel(store: store, library: FakeRecordAlbumLibrary(status: .authorized))
        XCTAssertEqual(open.albumRowState(for: record), .available(title: "建立新相簿「\(record.name)」"))
        let bound = FakeRecordAlbumLibrary(status: .authorized, albums: [.init(id: "a1", title: "寶寶", assetIDs: [])])
        var withAlbum = record
        withAlbum.albumIdentifier = "a1"
        XCTAssertEqual(makeModel(store: store, library: bound).albumRowState(for: withAlbum), .available(title: "寶寶"))
    }

    /// #649-5: the settings rows open the injected URL.
    func testOpenAppSettingsUsesTheInjectedOpener() {
        var opened: [URL] = []
        let model = RecordListModel(store: makeStore(), library: FakeRecordAlbumLibrary(),
                                    openSettings: { opened.append($0) })
        model.openAppSettings()
        XCTAssertEqual(opened.map(\.absoluteString), [UIApplication.openSettingsURLString])
    }

    /// #649-3: footer text by access state.
    func testFooterTextByAuthorization() {
        let same = "每個紀錄是「照片」App 裡的一本相簿，在那裡加入的照片會自動出現"
        for status in [PHAuthorizationStatus.authorized, .notDetermined] {
            XCTAssertEqual(makeModel(store: makeStore(), library: FakeRecordAlbumLibrary(status: status)).footerText, same)
        }
        XCTAssertEqual(makeModel(store: makeStore(), library: FakeRecordAlbumLibrary(status: .limited)).footerText,
                       "目前沒有開放完整權限，紀錄不會和原生相簿同步")
        for status in [PHAuthorizationStatus.denied, .restricted] {
            XCTAssertNil(makeModel(store: makeStore(), library: FakeRecordAlbumLibrary(status: status)).footerText)
        }
    }

    /// #649-6: the delete confirmation names the bound album.
    func testDeletionMessageNamesTheBoundAlbum() throws {
        let store = makeStore()
        var record = try XCTUnwrap(store.profiles.first)
        let library = FakeRecordAlbumLibrary(status: .authorized, albums: [.init(id: "a1", title: "寶寶", assetIDs: [])])
        let model = makeModel(store: store, library: library)
        record.albumIdentifier = "a1"
        XCTAssertEqual(model.deletionMessage(for: record), "「照片」App 裡的「寶寶」相簿和照片都會保留。")
        record.albumIdentifier = nil
        XCTAssertEqual(model.deletionMessage(for: record), "照片會保留在「照片」App。")
        record.albumIdentifier = "gone"
        XCTAssertEqual(model.deletionMessage(for: record), "照片會保留在「照片」App。")
    }

    // MARK: New record

    func testBackingOutOfANewRecordDiscardsItAndCheckmarkKeepsIt() throws {
        let store = makeStore()
        let model = makeModel(store: store, library: FakeRecordAlbumLibrary())
        let before = store.profiles.count

        model.addRecord()
        XCTAssertEqual(store.profiles.count, before + 1)
        model.path = []
        XCTAssertEqual(store.profiles.count, before)

        model.addRecord()
        guard case let .editor(id)? = model.path.first else { return XCTFail("the editor is pushed") }
        XCTAssertEqual(model.confirmNewRecord(), id)
        XCTAssertEqual(model.path, [.wall(id)], "the checkmark opens the new record's wall")
        XCTAssertEqual(store.profiles.count, before + 1)
    }

    // MARK: Data recovery alert (15.1, moved from the camera in #621)

    /// Writes unreadable bytes straight to `store`'s file, bypassing every
    /// check the store makes.
    private func corrupt(_ store: ProfileStore) throws {
        let garbage = try XCTUnwrap("這不是 JSON".data(using: .utf8))
        try garbage.write(to: store.fileURL)
    }

    private func makeRecoveredStore() throws -> ProfileStore {
        let clock = clock
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { clock.now },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        try corrupt(store)
        store.load()
        XCTAssertTrue(store.didRecoverFromCorruption) // sanity check on the fixture
        return store
    }

    /// #636 review: a camera failure reported after the camera closed shows
    /// once; more before dismissal add up; dismissing clears it.
    func testCaptureFailureAfterTheCameraClosedShowsAndAddsUp() {
        let model = makeModel(store: makeStore(), library: FakeRecordAlbumLibrary())
        XCTAssertNil(model.captureFailure)

        model.reportCaptureFailure(CaptureAlertError(message: "儲存失敗", showsSettingsAction: false), count: 1)
        XCTAssertEqual(model.captureFailure?.message, "儲存失敗")

        model.reportCaptureFailure(CaptureAlertError(message: "需要權限", showsSettingsAction: true), count: 2)
        XCTAssertEqual(model.captureFailure?.message, "3 張照片未儲存")
        XCTAssertEqual(model.captureFailure?.showsSettingsAction, true)

        model.dismissCaptureFailure()
        XCTAssertNil(model.captureFailure)
        model.reportCaptureFailure(CaptureAlertError(message: "儲存失敗", showsSettingsAction: false), count: 1)
        XCTAssertEqual(model.captureFailure?.message, "儲存失敗", "counting starts over after dismissal")
    }

    func testShowsCorruptionRecoveredAlertWhenTheStoreJustRecovered() throws {
        let model = makeModel(store: try makeRecoveredStore(), library: FakeRecordAlbumLibrary())
        XCTAssertTrue(model.showsCorruptionRecoveredAlert)
    }

    func testShowsNoCorruptionRecoveredAlertOnANormalLaunch() {
        let model = makeModel(store: makeStore(), library: FakeRecordAlbumLibrary())
        XCTAssertFalse(model.showsCorruptionRecoveredAlert)
    }

    func testDismissCorruptionRecoveredAlertClearsIt() throws {
        let model = makeModel(store: try makeRecoveredStore(), library: FakeRecordAlbumLibrary())
        XCTAssertTrue(model.showsCorruptionRecoveredAlert)

        model.dismissCorruptionRecoveredAlert()

        XCTAssertFalse(model.showsCorruptionRecoveredAlert)
    }

    // MARK: Save failure (#492, moved from the camera in #621)

    private func setDirectoryWritable(_ writable: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: writable ? 0o700 : 0o500],
                                              ofItemAtPath: directory.path)
    }

    /// Lets main-queue hops (store change delivery) run.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    /// A debounced write that fails reaches `lastError` once; a later success
    /// clears the store's error without a new alert, and a new failure after
    /// that shows again.
    func testBackgroundWriteFailureSetsLastErrorOnceAndRetryReArmsIt() async throws {
        let store = makeStore()
        let model = makeModel(store: store, library: FakeRecordAlbumLibrary())
        var edited = try XCTUnwrap(store.profiles.first)
        edited.name = "改名"
        try setDirectoryWritable(false)
        defer { try? setDirectoryWritable(true) }

        try store.update(edited)
        await settle()
        XCTAssertNotNil(model.lastError, "the failed write is surfaced")

        model.lastError = nil
        store.flush() // still failing: same error, no second alert
        await settle()
        XCTAssertNil(model.lastError)

        try setDirectoryWritable(true)
        store.flush()
        await settle()
        XCTAssertNil(store.lastWriteError)
        XCTAssertNil(model.lastError, "no alert for a successful retry")

        edited.name = "再改名"
        try setDirectoryWritable(false)
        try store.update(edited)
        await settle()
        XCTAssertNotNil(model.lastError, "a new failure shows again")
    }

    // MARK: Export model (#620)

    /// The export page's model edits the record through the shared
    /// `StyleEditingCenter`.
    func testExportModelIsBuiltOverTheStyleCenter() throws {
        let store = makeStore()
        let record = try XCTUnwrap(store.profiles.first)
        let model = makeModel(store: store, library: FakeRecordAlbumLibrary())
        let center = StyleEditingCenter(profileStore: store, fontLibrary: FakeShellFontLibrary(),
                                        calendar: DateFixture.taipei)

        let export = model.exportModel(for: record.id, photo: RecordPhoto(id: "p1", creationDate: nil),
                                       styleCenter: center)

        XCTAssertEqual(export.profileID, record.id)
    }
}
