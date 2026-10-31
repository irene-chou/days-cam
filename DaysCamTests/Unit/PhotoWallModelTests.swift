import Photos
import UIKit
import XCTest
@testable import DaysCam

/// A fake library whose change stream the test can fire.
@MainActor
private final class ChangingLibrary: RecordAlbumLibrary {
    let base: FakeRecordAlbumLibrary
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init(base: FakeRecordAlbumLibrary) {
        self.base = base
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    func fireChange() { continuation.yield() }

    func authorizationStatus() -> PHAuthorizationStatus { base.authorizationStatus() }
    func requestReadWriteAccess() async -> PHAuthorizationStatus { await base.requestReadWriteAccess() }
    func photos(albumIdentifier: String?, fallbackIDs: [String]) -> [RecordPhoto] {
        base.photos(albumIdentifier: albumIdentifier, fallbackIDs: fallbackIDs)
    }
    func photoCount(albumIdentifier: String?, fallbackIDs: [String]) -> Int? {
        base.photoCount(albumIdentifier: albumIdentifier, fallbackIDs: fallbackIDs)
    }
    func userAlbums() -> [AlbumSummary] { base.userAlbums() }
    func addAssets(_ ids: [String], albumIdentifier: String?, albumTitle: String) async throws -> String {
        try await base.addAssets(ids, albumIdentifier: albumIdentifier, albumTitle: albumTitle)
    }
    func removeAsset(_ id: String, fromAlbum albumIdentifier: String) async throws {
        try await base.removeAsset(id, fromAlbum: albumIdentifier)
    }
    func deleteAsset(_ id: String) async -> Bool { await base.deleteAsset(id) }
    func changes() -> AsyncStream<Void> { stream }
    func thumbnail(id: String, targetSize: CGSize) async -> UIImage? { await base.thumbnail(id: id, targetSize: targetSize) }
    func displayImage(id: String, targetSize: CGSize) async -> UIImage? { await base.displayImage(id: id, targetSize: targetSize) }
    func fullImage(id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> UIImage {
        try await base.fullImage(id: id, progress: progress)
    }
}

/// #618 acceptance 1–6 and 8–10: the wall's marks, months, adding and
/// following the library, over a real `ProfileStore` and a fake library.
@MainActor
final class PhotoWallModelTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private let calendar = DateFixture.taipei

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PhotoWallModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "PhotoWallModelTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeStore(start: DateComponents = DateFixture.components(2026, 1, 1),
                           rule: CountingRule = .dayOne,
                           albumIdentifier: String? = nil) throws -> (ProfileStore, CameraProfile) {
        let store = ProfileStore(directory: directory, calendar: calendar,
                                 now: { DateFixture.date(2026, 1, 10, hour: 8) ?? Date(timeIntervalSince1970: 0) },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        store.load()
        let profile = try store.add(CameraProfile(name: "小寶", startDate: start, countingRule: rule,
                                                  albumIdentifier: albumIdentifier))
        return (store, profile)
    }

    private func asset(_ id: String, _ month: Int, _ day: Int, year: Int = 2026) -> FakeRecordAlbumLibrary.Asset {
        FakeRecordAlbumLibrary.Asset(id: id, creationDate: DateFixture.date(year, month, day, hour: 15))
    }

    private func makeModel(store: ProfileStore, profile: CameraProfile, library: any RecordAlbumLibrary) -> PhotoWallModel {
        PhotoWallModel(profileID: profile.id, store: store, library: library, calendar: calendar,
                       todayText: { _ in "今天第 10 天" })
    }

    private func texts(_ model: PhotoWallModel) -> [String] {
        model.sections.flatMap(\.cells).map(\.dayText)
    }

    private func fiveJanuaryPhotos() -> FakeRecordAlbumLibrary {
        let assets = (6...10).map { asset("p\($0)", 1, $0) }
        let album = FakeRecordAlbumLibrary.Album(id: "album", title: "小寶", assetIDs: assets.map(\.id))
        return FakeRecordAlbumLibrary(assets: assets, albums: [album])
    }

    // MARK: Marks (1–5)

    /// 1: five photos run 第 6 天 to 第 10 天, oldest first.
    func testMarksCountFromTheStartDateOldestFirst() throws {
        let (store, profile) = try makeStore(albumIdentifier: "album")
        let model = makeModel(store: store, profile: profile, library: fiveJanuaryPhotos())
        XCTAssertEqual(texts(model), ["第 6 天", "第 7 天", "第 8 天", "第 9 天", "第 10 天"])
        XCTAssertEqual(model.content, .photos)
    }

    /// 2: a photo before the start date reads 前 N 天 and is flagged for the
    /// warm color.
    func testPhotosBeforeTheStartDateReadBeforeNDays() throws {
        let (store, profile) = try makeStore(start: DateFixture.components(2026, 1, 8), albumIdentifier: "album")
        let model = makeModel(store: store, profile: profile, library: fiveJanuaryPhotos())
        let cells = model.sections.flatMap(\.cells)
        XCTAssertEqual(cells.map(\.dayText), ["前 2 天", "前 1 天", "第 1 天", "第 2 天", "第 3 天"])
        XCTAssertEqual(cells.map(\.isBeforeStart), [true, true, false, false, false])
    }

    /// 3: under dayZero the start date itself is 第 0 天.
    func testDayZeroMarksTheStartDateAsDayZero() throws {
        let (store, profile) = try makeStore(start: DateFixture.components(2026, 1, 6), rule: .dayZero,
                                             albumIdentifier: "album")
        let model = makeModel(store: store, profile: profile, library: fiveJanuaryPhotos())
        XCTAssertEqual(texts(model).first, "第 0 天")
    }

    /// 4: a photo with no date is marked 日期不明 and leads the wall.
    func testPhotoWithoutADateIsUnknown() throws {
        let (store, profile) = try makeStore(albumIdentifier: "album")
        let undated = FakeRecordAlbumLibrary.Asset(id: "undated", creationDate: nil)
        let dated = asset("dated", 1, 5)
        let library = FakeRecordAlbumLibrary(assets: [dated, undated],
                                             albums: [.init(id: "album", title: "小寶", assetIDs: ["dated", "undated"])])
        let model = makeModel(store: store, profile: profile, library: library)
        XCTAssertEqual(texts(model), [TemplateRenderer.unknownDateText, "第 5 天"])
        XCTAssertEqual(model.sections.first?.title, PhotoWallModel.unknownMonthTitle)
    }

    /// 5: the wall's 前 N 天 is the very text the viewer and export render.
    func testBeforeStartTextMatchesTheTemplateRenderer() throws {
        let (store, profile) = try makeStore(start: DateFixture.components(2026, 1, 8), albumIdentifier: "album")
        let model = makeModel(store: store, profile: profile, library: fiveJanuaryPhotos())
        var dayCountOnly = profile
        dayCountOnly.showDayCount = true
        dayCountOnly.showDate = false
        dayCountOnly.showName = false
        let photoDate = try XCTUnwrap(DateFixture.date(2026, 1, 6, hour: 15))
        let rendered = TemplateRenderer().render(profile: dayCountOnly, capturedAt: photoDate,
                                                 calendar: calendar, moment: .photo)
        XCTAssertEqual(texts(model).first, rendered)
    }

    /// Changing the start date recomputes every mark (FR-21.3).
    func testEditingTheStartDateRecomputesTheMarks() throws {
        let (store, profile) = try makeStore(albumIdentifier: "album")
        let model = makeModel(store: store, profile: profile, library: fiveJanuaryPhotos())
        var edited = profile
        edited.startDate = DateFixture.components(2026, 1, 8)
        try store.updateAndWait(edited)
        XCTAssertEqual(texts(model).first, "前 2 天")
        XCTAssertEqual(model.subtitle, "2026/1/8 起 · 今天第 10 天")
    }

    // MARK: Months (6)

    /// 6: photos across months split into sections titled "YYYY 年 M 月".
    func testPhotosSplitIntoMonthsOldestFirst() throws {
        let (store, profile) = try makeStore(albumIdentifier: "album")
        let assets = [asset("a", 1, 31), asset("b", 2, 1), asset("c", 2, 14), asset("d", 12, 25, year: 2025)]
        let library = FakeRecordAlbumLibrary(assets: assets,
                                             albums: [.init(id: "album", title: "小寶", assetIDs: assets.map(\.id))])
        let model = makeModel(store: store, profile: profile, library: library)
        XCTAssertEqual(model.sections.map(\.title), ["2025 年 12 月", "2026 年 1 月", "2026 年 2 月"])
        XCTAssertEqual(model.sections.map { $0.cells.map(\.id) }, [["d"], ["a"], ["b", "c"]])
    }

    // MARK: Permission and states

    func testContentFollowsPermissionAndPhotos() throws {
        let (store, profile) = try makeStore()
        let empty = makeModel(store: store, profile: profile, library: FakeRecordAlbumLibrary())
        XCTAssertEqual(empty.content, .empty)
        for status in [PHAuthorizationStatus.denied, .restricted] {
            let model = makeModel(store: store, profile: profile, library: FakeRecordAlbumLibrary(status: status))
            XCTAssertEqual(model.content, .needsPermission, "\(status)")
        }
        let undecided = makeModel(store: store, profile: profile, library: FakeRecordAlbumLibrary(status: .notDetermined))
        XCTAssertEqual(undecided.content, .waiting)
    }

    /// #622-1: limited access still shows the wall (or its empty state), flagged
    /// for the notice; full access is not flagged.
    func testLimitedAccessShowsTheWallWithTheNotice() throws {
        let (store, profile) = try makeStore()
        let limited = makeModel(store: store, profile: profile, library: FakeRecordAlbumLibrary(status: .limited))
        XCTAssertEqual(limited.content, .empty)
        XCTAssertTrue(limited.isLimited)
        let full = makeModel(store: store, profile: profile, library: FakeRecordAlbumLibrary())
        XCTAssertFalse(full.isLimited)
    }

    /// #622-2: under limited access 「加入照片」 opens the system picker, shows
    /// no `PHPicker` and writes nothing to the library's albums.
    func testLimitedAddOpensTheSystemPickerAndWritesNoAlbum() throws {
        let (store, profile) = try makeStore()
        let library = FakeRecordAlbumLibrary(status: .limited, assets: [asset("x", 1, 3)])
        let presented = expectation(description: "system picker")
        let model = PhotoWallModel(profileID: profile.id, store: store, library: library, calendar: calendar,
                                   todayText: { _ in "" }, presentLimitedPicker: { presented.fulfill(); return [] })

        XCTAssertFalse(model.beginAddingPhotos(), "no PHPicker")
        wait(for: [presented], timeout: 2)
        XCTAssertTrue(library.albums.isEmpty, "addAssets not called")
        XCTAssertNil(store.profiles.first { $0.id == profile.id }?.albumIdentifier)
    }

    /// #640-4: photos newly selected in the system picker join this record's
    /// fallback ids only, once each, and show on its wall but not another's.
    func testLimitedPickerAppendsToThisRecordOnlyWithoutRepeats() async throws {
        let (store, first) = try makeStore()
        let second = try store.add(CameraProfile(name: "二寶", startDate: DateFixture.components(2026, 1, 1)))
        var withB = second
        withB.fallbackAssetIDs = ["B"]
        try store.updateAndWait(withB)
        let library = FakeRecordAlbumLibrary(status: .limited, assets: [asset("A", 1, 2), asset("B", 1, 3), asset("D", 1, 4)])
        library.visibleIDs = ["A", "B"]
        var picks: [[String]] = [["D"], ["D", "B", "D"]]
        let wall = PhotoWallModel(profileID: second.id, store: store, library: library, calendar: calendar,
                                  todayText: { _ in "" }, presentLimitedPicker: {
                                      library.visibleIDs?.formUnion(picks.first ?? [])
                                      return picks.isEmpty ? [] : picks.removeFirst()
                                  })
        let otherWall = makeModel(store: store, profile: first, library: library)

        await wall.addFromLimitedPicker()
        XCTAssertEqual(store.profiles.first { $0.id == second.id }?.fallbackAssetIDs, ["B", "D"], "640-4")
        XCTAssertEqual(wall.photoIDs, ["B", "D"], "640-4")
        XCTAssertEqual(store.profiles.first { $0.id == first.id }?.fallbackAssetIDs, [], "640-4 record 1 untouched")
        XCTAssertEqual(otherWall.photoIDs, [], "640-4 record 1 does not show D")

        await wall.addFromLimitedPicker()
        XCTAssertEqual(store.profiles.first { $0.id == second.id }?.fallbackAssetIDs, ["B", "D"], "640-4 no repeats")
    }

    /// #640-4: the dedup keeps the existing order and the picked order.
    func testAppendingNewKeepsOrderAndSkipsRepeats() {
        XCTAssertEqual(PhotoWallModel.appendingNew(["c", "a", "d", "c"], to: ["a", "b"]), ["a", "b", "c", "d"])
        XCTAssertEqual(PhotoWallModel.appendingNew([], to: ["a"]), ["a"])
    }

    /// #640-3: a photo taken in record 1 under limited access (no album)
    /// shows on record 1's wall only.
    func testLimitedCaptureShowsOnlyOnItsOwnRecord() throws {
        let (store, first) = try makeStore()
        let second = try store.add(CameraProfile(name: "二寶", startDate: DateFixture.components(2026, 1, 1)))
        let library = FakeRecordAlbumLibrary(status: .limited, assets: [asset("old", 1, 2)])
        library.visibleIDs = ["old"]
        let firstWall = makeModel(store: store, profile: first, library: library)
        let secondWall = makeModel(store: store, profile: second, library: library)
        let before = (firstWall.photoIDs.count, secondWall.photoIDs.count)

        library.addAsset(asset("new", 1, 10))
        library.visibleIDs?.insert("new")
        CameraScreenModel.record(RecordSaveOutcome(assetID: "new", albumID: nil),
                                 savedFor: .init(profileID: first.id, albumTitle: first.name),
                                 albumAtSave: nil, in: store, reportWriteFailure: { XCTFail("\($0)") })
        firstWall.reload()
        secondWall.reload()
        XCTAssertEqual(firstWall.photoIDs.count, before.0 + 1, "640-3")
        XCTAssertEqual(secondWall.photoIDs.count, before.1, "640-3")
        XCTAssertEqual(firstWall.photoIDs, ["new"])
    }

    /// #622-2: under full access the caller still shows its own picker.
    func testFullAccessAddLeavesThePickerToTheCaller() throws {
        let (store, profile) = try makeStore()
        var presented = 0
        let model = PhotoWallModel(profileID: profile.id, store: store, library: FakeRecordAlbumLibrary(),
                                   calendar: calendar, todayText: { _ in "" }, presentLimitedPicker: { presented += 1; return [] })
        XCTAssertTrue(model.beginAddingPhotos())
        XCTAssertEqual(presented, 0)
    }

    /// #622-5: coming back from Settings with access granted swaps the
    /// permission page for the wall; withdrawing it swaps back.
    func testReloadRereadsTheAuthorization() throws {
        let (store, profile) = try makeStore(albumIdentifier: "album")
        let library = fiveJanuaryPhotos()
        library.status = .denied
        let model = makeModel(store: store, profile: profile, library: library)
        XCTAssertEqual(model.content, .needsPermission)

        library.status = .authorized
        model.reload()
        XCTAssertEqual(model.content, .photos)
        XCTAssertFalse(model.isLimited)

        library.status = .denied
        model.reload()
        XCTAssertEqual(model.content, .needsPermission)
    }

    func testPrepareAsksOnceWhenUndecided() async throws {
        let (store, profile) = try makeStore(albumIdentifier: "album")
        let library = fiveJanuaryPhotos()
        library.status = .notDetermined
        let model = makeModel(store: store, profile: profile, library: library)
        await model.prepare()
        XCTAssertEqual(library.status, .authorized)
        XCTAssertEqual(model.content, .photos)
    }

    // MARK: Adding (8, 9)

    /// 8: a record with no album gets the new album's id, and the wall shows
    /// the added photos.
    func testAddingPhotosCreatesTheAlbumAndStoresItsID() async throws {
        let (store, profile) = try makeStore()
        let library = FakeRecordAlbumLibrary(assets: [asset("x", 1, 3), asset("y", 1, 4)])
        let model = makeModel(store: store, profile: profile, library: library)
        XCTAssertEqual(model.content, .empty)

        await model.addPhotos(ids: ["x", "y"])

        let stored = try XCTUnwrap(store.profiles.first { $0.id == profile.id })
        let albumID = try XCTUnwrap(stored.albumIdentifier)
        XCTAssertEqual(library.userAlbums().first { $0.id == albumID }?.title, "小寶")
        XCTAssertEqual(texts(model), ["第 3 天", "第 4 天"])
        XCTAssertNil(model.errorMessage)
    }

    /// 8: a bound album keeps its id.
    func testAddingToABoundAlbumKeepsTheID() async throws {
        let (store, profile) = try makeStore(albumIdentifier: "album")
        let library = fiveJanuaryPhotos()
        library.addAsset(asset("new", 1, 2))
        let model = makeModel(store: store, profile: profile, library: library)
        await model.addPhotos(ids: ["new"])
        XCTAssertEqual(store.profiles.first { $0.id == profile.id }?.albumIdentifier, "album")
        XCTAssertEqual(texts(model).first, "第 2 天")
    }

    /// 9: a failure shows an error, leaves the wall and the record alone.
    func testFailedAddShowsAnErrorAndChangesNothing() async throws {
        let (store, profile) = try makeStore()
        let library = FakeRecordAlbumLibrary(assets: [asset("x", 1, 3)])
        library.failure = .failed("相簿忙碌中")
        let model = makeModel(store: store, profile: profile, library: library)

        await model.addPhotos(ids: ["x"])

        XCTAssertEqual(model.errorMessage, "相簿忙碌中")
        XCTAssertEqual(model.content, .empty)
        XCTAssertNil(store.profiles.first { $0.id == profile.id }?.albumIdentifier)
    }

    // MARK: Following the library (10)

    /// 10: a change event from the library reloads the wall.
    func testLibraryChangeReloadsTheWall() async throws {
        let (store, profile) = try makeStore(albumIdentifier: "album")
        let base = fiveJanuaryPhotos()
        let library = ChangingLibrary(base: base)
        let model = makeModel(store: store, profile: profile, library: library)
        model.startObservingLibrary()
        XCTAssertEqual(model.photoIDs.count, 5)

        base.removeFromLibrary("p6")
        library.fireChange()
        for _ in 0..<50 where model.photoIDs.count != 4 { try await Task.sleep(nanoseconds: 20_000_000) }

        XCTAssertEqual(model.photoIDs, ["p7", "p8", "p9", "p10"])
        model.stopObservingLibrary()
    }
}
