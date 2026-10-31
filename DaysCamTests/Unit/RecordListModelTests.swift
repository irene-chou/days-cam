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

    /// Also #651-14: "建立新相簿" under full access creates and binds an
    /// album right away; the album bound before stays (FR-21.5).
    func testPickingAnAlbumBindsItAndKeepsFallbackIDs() async throws {
        let store = makeStore()
        var record = try addRecord("小寶", to: store)
        record.fallbackAssetIDs = ["keep-1", "keep-2"]
        try store.update(record)
        let library = FakeRecordAlbumLibrary(status: .authorized,
                                             albums: [.init(id: "album-1", title: "寶寶", assetIDs: [])])
        let picker = makeModel(store: store, library: library).albumPickerModel(for: record.id)

        await picker.select(albumIdentifier: "album-1")
        XCTAssertEqual(store.profiles.first { $0.id == record.id }?.albumIdentifier, "album-1")
        XCTAssertEqual(store.profiles.first { $0.id == record.id }?.fallbackAssetIDs, ["keep-1", "keep-2"])

        await picker.select(albumIdentifier: nil)
        XCTAssertEqual(library.createdAlbumTitles, ["小寶"], "14")
        let created = try XCTUnwrap(library.albums.last)
        XCTAssertEqual(store.profiles.first { $0.id == record.id }?.albumIdentifier, created.id, "14 bound")
        XCTAssertEqual(store.profiles.first { $0.id == record.id }?.fallbackAssetIDs, ["keep-1", "keep-2"])
        XCTAssertTrue(library.albums.contains { $0.id == "album-1" }, "the old album is not deleted")
        XCTAssertTrue(picker.options.first { $0.id == created.id }?.isSelected == true)
        XCTAssertEqual(library.accessRequestCount, 0)
    }

    /// #651-7: a failed "建立新相簿" keeps the binding and reports it.
    func testPickerCreateFailureKeepsTheBindingAndReports() async throws {
        let store = makeStore()
        let record = try addRecord("小寶", to: store, albumIdentifier: "album-1")
        let library = FakeRecordAlbumLibrary(status: .authorized,
                                             albums: [.init(id: "album-1", title: "寶寶", assetIDs: [])])
        library.createAlbumFailure = .failed("boom")
        let picker = makeModel(store: store, library: library).albumPickerModel(for: record.id)
        await picker.select(albumIdentifier: nil)
        XCTAssertEqual(store.profiles.first { $0.id == record.id }?.albumIdentifier, "album-1")
        XCTAssertEqual(picker.lastError as? RecordAlbumError, .failed("boom"))
    }

    func testAlbumBoundElsewhereIsLabelledButSelectable() async throws {
        let store = makeStore()
        try addRecord("甲", to: store, albumIdentifier: "album-1")
        let mine = try addRecord("乙", to: store)
        let library = FakeRecordAlbumLibrary(status: .authorized,
                                             albums: [.init(id: "album-1", title: "共用", assetIDs: [])])
        let picker = makeModel(store: store, library: library).albumPickerModel(for: mine.id)
        await picker.load()

        let options = picker.options
        XCTAssertNil(options.first?.id, "the create row comes first")
        XCTAssertTrue(options[0].isSelected)
        XCTAssertEqual(options[0].title, "建立新相簿「乙」")
        let shared = try XCTUnwrap(options.first { $0.id == "album-1" })
        XCTAssertEqual(shared.usedBy, "甲")
        XCTAssertEqual(shared.detail, "0 張 · 已被「甲」使用")

        await picker.select(albumIdentifier: "album-1")
        XCTAssertEqual(store.profiles.first { $0.id == mine.id }?.albumIdentifier, "album-1")
        XCTAssertTrue(picker.options.first { $0.id == "album-1" }?.isSelected == true)
    }

    /// #651-14: neither the list nor the picker asks; only the wall's intro
    /// does (§7.1).
    func testPickerNeverRequestsAccess() async throws {
        let store = makeStore()
        let record = try XCTUnwrap(store.profiles.first)
        let library = FakeRecordAlbumLibrary(status: .notDetermined)
        let model = makeModel(store: store, library: library)
        _ = model.rows

        let picker = model.albumPickerModel(for: record.id)
        await picker.load()
        await picker.select(albumIdentifier: nil)
        XCTAssertEqual(library.accessRequestCount, 0)
        XCTAssertEqual(library.authorizationStatus(), .notDetermined)
        XCTAssertEqual(library.createdAlbumTitles, [])
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

    // MARK: Album on create and backfill (#651)

    /// Adds a draft, names it and confirms it, waiting for its album.
    private func confirmDraft(named name: String, in model: RecordListModel, store: ProfileStore,
                              albumIdentifier: String? = nil) async throws -> UUID {
        model.addRecord()
        guard case let .editor(id)? = model.path.first,
              var draft = store.profiles.first(where: { $0.id == id }) else {
            XCTFail("the editor is pushed")
            throw CancellationError()
        }
        draft.name = name
        draft.albumIdentifier = albumIdentifier
        try store.updateAndWait(draft)
        XCTAssertEqual(model.confirmNewRecord(), id)
        await model.albumCreation?.value
        return id
    }

    /// 1: full access, the checkmark creates one album titled by the record
    /// and stores it.
    func testConfirmingANewRecordCreatesItsAlbum() async throws {
        let store = makeStore()
        let library = FakeRecordAlbumLibrary(status: .authorized)
        let model = makeModel(store: store, library: library)
        let id = try await confirmDraft(named: "小芽", in: model, store: store)
        XCTAssertEqual(library.createdAlbumTitles, ["小芽"])
        let album = try XCTUnwrap(library.albums.first)
        XCTAssertEqual(album.title, "小芽")
        XCTAssertEqual(store.profiles.first { $0.id == id }?.albumIdentifier, album.id)
        XCTAssertNil(model.lastError)
    }

    /// 2: backing out of the draft creates nothing; neither does a backfill
    /// while the draft is up.
    func testDiscardedDraftCreatesNoAlbum() async throws {
        let store = makeStore()
        try store.updateAndWait(try XCTUnwrap(store.profiles.first).with(albumIdentifier: "bound"))
        let library = FakeRecordAlbumLibrary(status: .authorized)
        let model = makeModel(store: store, library: library)
        model.addRecord()
        await model.backfillAlbumsIfNeeded()
        model.path = []
        await model.backfillAlbumsIfNeeded()
        XCTAssertEqual(library.createdAlbumTitles, [])
        XCTAssertTrue(library.albums.isEmpty)
    }

    /// 3: an existing album picked while adding is kept, nothing is created.
    func testNewRecordWithAPickedAlbumCreatesNone() async throws {
        let store = makeStore()
        let library = FakeRecordAlbumLibrary(status: .authorized, albums: [.init(id: "mine", title: "舊相簿", assetIDs: [])])
        let model = makeModel(store: store, library: library)
        let id = try await confirmDraft(named: "小芽", in: model, store: store, albumIdentifier: "mine")
        XCTAssertEqual(library.createdAlbumTitles, [])
        XCTAssertEqual(store.profiles.first { $0.id == id }?.albumIdentifier, "mine")
    }

    /// 4: without full access nothing is created and nothing is asked.
    func testNewRecordWithoutFullAccessCreatesNoAlbum() async throws {
        for status in [PHAuthorizationStatus.limited, .notDetermined, .denied] {
            let store = makeStore()
            let library = FakeRecordAlbumLibrary(status: status)
            let model = makeModel(store: store, library: library)
            let id = try await confirmDraft(named: "小芽", in: model, store: store)
            XCTAssertEqual(library.createdAlbumTitles, [], "\(status)")
            XCTAssertNil(store.profiles.first { $0.id == id }?.albumIdentifier, "\(status)")
            XCTAssertEqual(library.accessRequestCount, 0, "\(status)")
            try store.delete(id: id)
        }
    }

    /// 5: two unbound records and one bound: only two albums, each stored;
    /// a second run creates none; two runs at once still create two.
    func testBackfillCreatesOneAlbumPerUnboundRecordOnce() async throws {
        let store = makeStore()
        try store.updateAndWait(try XCTUnwrap(store.profiles.first).with(albumIdentifier: "bound"))
        let first = try addRecord("甲", to: store)
        let second = try addRecord("乙", to: store)
        let library = FakeRecordAlbumLibrary(status: .authorized, albums: [.init(id: "bound", title: "既有", assetIDs: [])])
        let model = makeModel(store: store, library: library)

        async let one: Void = model.backfillAlbumsIfNeeded()
        async let two: Void = model.backfillAlbumsIfNeeded()
        _ = await (one, two)
        XCTAssertEqual(library.createdAlbumTitles.sorted(), ["乙", "甲"], "5 at once")
        let firstAlbum = store.profiles.first { $0.id == first.id }?.albumIdentifier
        let secondAlbum = store.profiles.first { $0.id == second.id }?.albumIdentifier
        XCTAssertEqual(library.albums.first { $0.id == firstAlbum }?.title, "甲")
        XCTAssertEqual(library.albums.first { $0.id == secondAlbum }?.title, "乙")
        XCTAssertEqual(store.profiles.filter { $0.albumIdentifier == "bound" }.count, 1)

        await model.backfillAlbumsIfNeeded()
        model.sceneDidBecomeActive()
        await Task.yield()
        XCTAssertEqual(library.createdAlbumTitles.count, 2, "5 again")
    }

    /// 6: an album id that no longer resolves is not recreated.
    func testBackfillSkipsAMissingBoundAlbum() async throws {
        let store = makeStore()
        try store.updateAndWait(try XCTUnwrap(store.profiles.first).with(albumIdentifier: "deleted-by-user"))
        let library = FakeRecordAlbumLibrary(status: .authorized)
        await makeModel(store: store, library: library).backfillAlbumsIfNeeded()
        XCTAssertEqual(library.createdAlbumTitles, [])
        XCTAssertEqual(store.profiles.first?.albumIdentifier, "deleted-by-user")
    }

    /// 7: a failed create still creates the record, keeps `nil`, reports
    /// the failure, and is retried by the next trigger.
    func testFailedAlbumCreationKeepsTheRecordAndRetries() async throws {
        let store = makeStore()
        try store.updateAndWait(try XCTUnwrap(store.profiles.first).with(albumIdentifier: "bound"))
        let library = FakeRecordAlbumLibrary(status: .authorized, albums: [.init(id: "bound", title: "既有", assetIDs: [])])
        library.createAlbumFailure = .failed("boom")
        let model = makeModel(store: store, library: library)
        let id = try await confirmDraft(named: "小芽", in: model, store: store)
        XCTAssertNotNil(store.profiles.first { $0.id == id }, "the record is kept")
        XCTAssertNil(store.profiles.first { $0.id == id }?.albumIdentifier)
        XCTAssertEqual(model.lastError as? RecordAlbumError, .failed("boom"), "not reported as created")
        XCTAssertEqual(library.albums.count, 1)

        library.createAlbumFailure = nil
        await model.backfillAlbumsIfNeeded()
        XCTAssertEqual(library.createdAlbumTitles, ["小芽", "小芽"])
        XCTAssertNotNil(store.profiles.first { $0.id == id }?.albumIdentifier)
    }

    /// 8: a rename and a style change landing while the album is created
    /// both survive the write-back.
    func testAlbumWriteBackKeepsConcurrentEdits() async throws {
        let store = makeStore()
        let record = try XCTUnwrap(store.profiles.first)
        let library = FakeRecordAlbumLibrary(status: .authorized)
        library.onCreateAlbum = {
            guard var latest = store.profiles.first(where: { $0.id == record.id }) else { return }
            latest.name = "改過"
            latest.style.showsShadow = !latest.style.showsShadow
            try? store.updateAndWait(latest)
        }
        await makeModel(store: store, library: library).backfillAlbumsIfNeeded()
        let saved = try XCTUnwrap(store.profiles.first { $0.id == record.id })
        XCTAssertEqual(saved.name, "改過")
        XCTAssertEqual(saved.style.showsShadow, !record.style.showsShadow)
        XCTAssertEqual(saved.albumIdentifier, library.albums.first?.id)
        XCTAssertNotNil(saved.albumIdentifier)
    }

    /// 9: renaming a record touches no album.
    func testRenamingARecordLeavesItsAlbumAlone() async throws {
        let store = makeStore()
        var record = try XCTUnwrap(store.profiles.first)
        let library = FakeRecordAlbumLibrary(status: .authorized, albums: [.init(id: "a1", title: "舊名", assetIDs: [])])
        record.albumIdentifier = "a1"
        try store.updateAndWait(record)
        let model = makeModel(store: store, library: library)
        record.name = "新名"
        try store.updateAndWait(record)
        await model.backfillAlbumsIfNeeded()
        XCTAssertEqual(library.albums, [.init(id: "a1", title: "舊名", assetIDs: [])])
        XCTAssertEqual(store.profiles.first?.albumIdentifier, "a1")
        XCTAssertEqual(library.createdAlbumTitles, [])
    }

    /// #651 review: "加入照片" while the new record's album is still being
    /// created waits for it and goes into that album: one album in all.
    func testAddingPhotosWhileTheAlbumIsBeingCreatedUsesThatAlbum() async throws {
        let store = makeStore()
        let library = FakeRecordAlbumLibrary(status: .authorized, assets: [.init(id: "x")])
        let latch = AlbumCreationLatch()
        library.onCreateAlbum = { await latch.hold() }
        let model = makeModel(store: store, library: library)
        model.addRecord()
        guard case let .editor(id)? = model.path.first else { return XCTFail("the editor is pushed") }
        model.confirmNewRecord()
        try await latch.waitUntilHolding()

        let wall = model.photoWallModel(for: id)
        let adding = Task { await wall.addPhotos(ids: ["x"]) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(library.albums.isEmpty, "adding waits for the creation")

        latch.release()
        await model.albumCreation?.value
        await adding.value
        XCTAssertEqual(library.createdAlbumTitles.count, 1)
        XCTAssertEqual(library.albums.count, 1, "one album")
        let album = try XCTUnwrap(library.albums.first)
        XCTAssertEqual(album.assetIDs, ["x"], "the photo went into it")
        XCTAssertEqual(store.profiles.first { $0.id == id }?.albumIdentifier, album.id)
        XCTAssertNil(wall.errorMessage)
    }

    /// #651 review: a backfill queued behind "加入照片" for a record without an
    /// album finds the album that add created and makes none.
    func testBackfillAfterAddingPhotosCreatesNoSecondAlbum() async throws {
        let store = makeStore()
        let record = try XCTUnwrap(store.profiles.first)
        let library = FakeRecordAlbumLibrary(status: .authorized, assets: [.init(id: "x")])
        let model = makeModel(store: store, library: library)
        let wall = model.photoWallModel(for: record.id)
        async let adding: Void = wall.addPhotos(ids: ["x"])
        async let backfill: Void = model.backfillAlbumsIfNeeded()
        _ = await (adding, backfill)
        XCTAssertEqual(library.albums.count, 1)
        XCTAssertEqual(library.albums.first?.assetIDs, ["x"])
        XCTAssertEqual(store.profiles.first?.albumIdentifier, library.albums.first?.id)
    }

    /// #661 review: "建立新相簿" in a draft's picker creates nothing until the
    /// checkmark; backing out leaves no album.
    func testDraftPickerCreateWaitsForTheCheckmark() async throws {
        let store = makeStore()
        try store.updateAndWait(try XCTUnwrap(store.profiles.first).with(albumIdentifier: "bound"))
        let library = FakeRecordAlbumLibrary(status: .authorized, albums: [.init(id: "bound", title: "既有", assetIDs: [])])
        let model = makeModel(store: store, library: library)

        model.addRecord()
        guard case let .editor(discarded)? = model.path.first else { return XCTFail("the editor is pushed") }
        await model.albumPickerModel(for: discarded).select(albumIdentifier: "bound")
        await model.albumPickerModel(for: discarded).select(albumIdentifier: nil)
        XCTAssertEqual(library.createdAlbumTitles, [], "not while a draft")
        XCTAssertNil(store.profiles.first { $0.id == discarded }?.albumIdentifier, "marked to be created")
        model.path = []
        XCTAssertEqual(library.albums.count, 1, "backing out leaves no album")

        model.addRecord()
        guard case let .editor(kept)? = model.path.first else { return XCTFail("the editor is pushed") }
        await model.albumPickerModel(for: kept).select(albumIdentifier: nil)
        XCTAssertEqual(library.createdAlbumTitles, [])
        model.confirmNewRecord()
        await model.albumCreation?.value
        XCTAssertEqual(library.createdAlbumTitles.count, 1, "created by the checkmark")
        XCTAssertEqual(store.profiles.first { $0.id == kept }?.albumIdentifier, library.albums.last?.id)
    }

    /// #661 review: picking another album while "建立新相簿" is still being
    /// created keeps the newer pick.
    func testNewerPickWhileTheAlbumIsBeingCreatedWins() async throws {
        let store = makeStore()
        let record = try XCTUnwrap(store.profiles.first)
        let library = FakeRecordAlbumLibrary(status: .authorized, albums: [
            .init(id: "a1", title: "一", assetIDs: []), .init(id: "a2", title: "二", assetIDs: [])
        ])
        try store.updateAndWait(record.with(albumIdentifier: "a1"))
        let latch = AlbumCreationLatch()
        library.onCreateAlbum = { await latch.hold() }
        let picker = makeModel(store: store, library: library).albumPickerModel(for: record.id)

        let creating = Task { await picker.select(albumIdentifier: nil) }
        try await latch.waitUntilHolding()
        await picker.select(albumIdentifier: "a2")
        latch.release()
        await creating.value
        XCTAssertEqual(library.createdAlbumTitles.count, 1)
        XCTAssertEqual(store.profiles.first?.albumIdentifier, "a2", "the newer pick wins")
        XCTAssertNil(picker.lastError)
    }

    /// #661 review: an album whose write-back failed is bound by the next
    /// attempt instead of a second album being made.
    func testFailedWriteBackReusesTheCreatedAlbum() async throws {
        let store = makeStore()
        let library = FakeRecordAlbumLibrary(status: .authorized)
        let model = makeModel(store: store, library: library)
        try setDirectoryWritable(false)
        await model.backfillAlbumsIfNeeded(reportsFailure: true)
        try setDirectoryWritable(true)
        XCTAssertNotNil(model.lastError, "the failed write is reported")
        XCTAssertNil(store.profiles.first?.albumIdentifier)
        XCTAssertEqual(library.albums.count, 1)

        await model.backfillAlbumsIfNeeded()
        XCTAssertEqual(library.createdAlbumTitles.count, 1, "no second album")
        XCTAssertEqual(store.profiles.first?.albumIdentifier, library.albums.first?.id)
    }

    /// 10: launch and returning to the foreground never ask, even undecided.
    func testLaunchAndForegroundNeverRequestAccess() async throws {
        for status in [PHAuthorizationStatus.notDetermined, .limited, .denied, .authorized] {
            let store = makeStore()
            let library = FakeRecordAlbumLibrary(status: status)
            let model = makeModel(store: store, library: library)
            model.startObservingLibrary()
            model.sceneDidBecomeActive()
            await model.backfillAlbumsIfNeeded()
            _ = model.rows
            _ = model.footerText
            XCTAssertEqual(library.accessRequestCount, 0, "\(status)")
            XCTAssertEqual(library.createdAlbumTitles.isEmpty, status != .authorized, "\(status)")
        }
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

private extension CameraProfile {
    func with(albumIdentifier: String?) -> CameraProfile {
        var copy = self
        copy.albumIdentifier = albumIdentifier
        return copy
    }
}

/// Holds a fake album creation open until the test releases it (#651).
@MainActor
final class AlbumCreationLatch {
    private var continuation: CheckedContinuation<Void, Never>?

    var isHolding: Bool { continuation != nil }

    func hold() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    /// Yields until a creation is held; fails after about two seconds.
    func waitUntilHolding() async throws {
        for _ in 0..<200 where !isHolding {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(isHolding, "an album creation started")
    }
}
