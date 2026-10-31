import Photos
import XCTest
@testable import DaysCam

/// Covers the record-album rules (#616) on the in-memory fake, which shares
/// `RecordAlbumLogic` with the system implementation. The `PHAsset` fetches
/// themselves are a code check: `SystemRecordAlbumLibrary.imageOptions`
/// (mediaType = image) and `userAlbums` (`.album` + `.albumRegular`).
@MainActor
final class RecordAlbumLibraryTests: XCTestCase {

    private func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
    }

    private func asset(_ id: String, day: Int? = nil, video: Bool = false) -> FakeRecordAlbumLibrary.Asset {
        .init(id: id, mediaType: video ? .video : .image, creationDate: day.map(date))
    }

    private func ids(_ photos: [RecordPhoto]) -> [String] { photos.map(\.id) }

    func test_photos_unionsAlbumAndFallback_dropsDeleted_sortsOldestFirst() {
        let library = FakeRecordAlbumLibrary(
            assets: [asset("a", day: 3), asset("b", day: 1)],
            albums: [.init(id: "alb", title: "小寶", assetIDs: ["a", "b"])])
        // "c" was deleted from the library; "b" is in both.
        XCTAssertEqual(ids(library.photos(albumIdentifier: "alb", fallbackIDs: ["b", "c"])), ["b", "a"])
    }

    func test_photos_excludeVideos() {
        let library = FakeRecordAlbumLibrary(
            assets: [asset("a", day: 1), asset("v", day: 2, video: true)],
            albums: [.init(id: "alb", title: "x", assetIDs: ["a", "v"])])
        XCTAssertEqual(ids(library.photos(albumIdentifier: "alb", fallbackIDs: ["v"])), ["a"])
        XCTAssertEqual(library.photoCount(albumIdentifier: "alb", fallbackIDs: ["v"]), 1)
    }

    func test_photos_nilDateFirst_tiesBreakOnID() {
        let library = FakeRecordAlbumLibrary(
            assets: [asset("z", day: 5), asset("b", day: 5), asset("n")],
            albums: [.init(id: "alb", title: "x", assetIDs: ["z", "b", "n"])])
        XCTAssertEqual(ids(library.photos(albumIdentifier: "alb", fallbackIDs: [])), ["n", "b", "z"])
    }

    func test_unknownAlbum_returnsOnlyFallback_andAddAssetsCreatesNewAlbum() async throws {
        let library = FakeRecordAlbumLibrary(assets: [asset("a", day: 1), asset("f", day: 2)])
        XCTAssertEqual(ids(library.photos(albumIdentifier: "gone", fallbackIDs: ["f", "x"])), ["f"])
        let newID = try await library.addAssets(["a"], albumIdentifier: "gone", albumTitle: "小寶")
        XCTAssertNotEqual(newID, "gone")
        XCTAssertEqual(ids(library.photos(albumIdentifier: newID, fallbackIDs: [])), ["a"])
    }

    func test_addAssets_sameTitleStillCreatesSeparateAlbum() async throws {
        let library = FakeRecordAlbumLibrary(
            assets: [asset("a", day: 1)],
            albums: [.init(id: "existing", title: "小寶", assetIDs: [])])
        let newID = try await library.addAssets(["a"], albumIdentifier: nil, albumTitle: "小寶")
        XCTAssertNotEqual(newID, "existing")
        XCTAssertEqual(library.userAlbums().filter { $0.title == "小寶" }.count, 2)
    }

    func test_addAssets_existingAlbum_returnsSameID() async throws {
        let library = FakeRecordAlbumLibrary(
            assets: [asset("a", day: 1)],
            albums: [.init(id: "alb", title: "x", assetIDs: [])])
        let id = try await library.addAssets(["a"], albumIdentifier: "alb", albumTitle: "x")
        XCTAssertEqual(id, "alb")
    }

    func test_addAssets_failureThrows() async {
        let library = FakeRecordAlbumLibrary(assets: [asset("a")])
        library.failure = .failed("boom")
        do {
            _ = try await library.addAssets(["a"], albumIdentifier: nil, albumTitle: "x")
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? RecordAlbumError, .failed("boom"))
        }
    }

    /// #651: `createAlbum` makes an empty album even when the title is taken,
    /// counts calls, and fails without full access or when told to.
    func test_createAlbum_makesAnEmptyAlbumEachCall() async throws {
        let library = FakeRecordAlbumLibrary(albums: [.init(id: "old", title: "小芽", assetIDs: ["a"])])
        let first = try await library.createAlbum(title: "小芽")
        let second = try await library.createAlbum(title: "小芽")
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, "old")
        XCTAssertEqual(library.albums.first { $0.id == first }, .init(id: first, title: "小芽", assetIDs: []))
        XCTAssertEqual(library.createdAlbumTitles, ["小芽", "小芽"])
    }

    func test_createAlbum_failsWithoutFullAccessOrWhenInjected() async {
        for status in [PHAuthorizationStatus.limited, .notDetermined, .denied] {
            let library = FakeRecordAlbumLibrary(status: status)
            do {
                _ = try await library.createAlbum(title: "x")
                XCTFail("expected a throw for \(status)")
            } catch {
                XCTAssertEqual(error as? RecordAlbumError, .permissionDenied)
            }
            XCTAssertTrue(library.albums.isEmpty)
        }
        let library = FakeRecordAlbumLibrary()
        library.createAlbumFailure = .failed("boom")
        do {
            _ = try await library.createAlbum(title: "x")
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? RecordAlbumError, .failed("boom"))
        }
        XCTAssertTrue(library.albums.isEmpty)
    }

    /// #651: `-UITestPhotoAccess notDetermined` starts undecided and grants
    /// full access when asked.
    func test_forUITests_notDeterminedGrantsFullWhenAsked() async throws {
        let library = try XCTUnwrap(FakeRecordAlbumLibrary.forUITests(
            arguments: ["-UITestRecordPhotos", "0", "-UITestPhotoAccess", "notDetermined"], environment: [:]))
        XCTAssertEqual(library.authorizationStatus(), .notDetermined)
        let status = await library.requestReadWriteAccess()
        XCTAssertEqual(status, .authorized)
    }

    /// #640-1: under limited access a record shows only its own fallback ids;
    /// a visible photo no record lists shows nowhere, and albums are not read.
    func test_limited_eachRecordShowsOnlyItsFallback_withoutReadingAlbums() {
        let library = FakeRecordAlbumLibrary(
            status: .limited,
            assets: [asset("A", day: 1), asset("B", day: 2), asset("C", day: 3), asset("v", day: 4, video: true)],
            albums: [.init(id: "alb", title: "x", assetIDs: ["A", "B", "C"])])
        library.visibleIDs = ["A", "B", "C", "v"]
        XCTAssertEqual(ids(library.photos(albumIdentifier: "alb", fallbackIDs: ["A"])), ["A"], "640-1 record 1")
        XCTAssertEqual(ids(library.photos(albumIdentifier: nil, fallbackIDs: ["B", "v"])), ["B"], "640-1 record 2")
        XCTAssertEqual(library.photoCount(albumIdentifier: nil, fallbackIDs: []), 0, "640-1 C is no record's")
        XCTAssertEqual(library.albumReadCount, 0)
    }

    /// #640-2: a fallback id the user took out of the limited selection, or
    /// deleted, is skipped and not counted.
    func test_limited_fallbackOutsideTheSelection_isSkippedAndNotCounted() {
        let library = FakeRecordAlbumLibrary(status: .limited, assets: [asset("A", day: 1), asset("hidden", day: 2)])
        library.visibleIDs = ["A"]
        let fallback = ["hidden", "A", "deleted"]
        XCTAssertEqual(ids(library.photos(albumIdentifier: nil, fallbackIDs: fallback)), ["A"], "640-2")
        XCTAssertEqual(library.photoCount(albumIdentifier: nil, fallbackIDs: fallback), 1, "640-2")
        XCTAssertEqual(library.photoCount(albumIdentifier: nil, fallbackIDs: ["hidden"]), 0, "640-2")
    }

    /// #640-5: full access still unites the album with the fallback ids.
    func test_full_stillUnitesAlbumAndFallback() {
        let library = FakeRecordAlbumLibrary(
            assets: [asset("A", day: 1), asset("B", day: 2), asset("C", day: 3)],
            albums: [.init(id: "alb", title: "x", assetIDs: ["A"])])
        XCTAssertEqual(ids(library.photos(albumIdentifier: "alb", fallbackIDs: ["B"])), ["A", "B"], "640-5")
        XCTAssertEqual(RecordReadMode(status: .authorized), .album)
        XCTAssertEqual(RecordReadMode(status: .limited), .fallbackOnly)
    }

    func test_denied_isEmptyAndCountIsNil() {
        let library = FakeRecordAlbumLibrary(
            status: .denied, assets: [asset("a")],
            albums: [.init(id: "alb", title: "x", assetIDs: ["a"])])
        XCTAssertTrue(library.photos(albumIdentifier: "alb", fallbackIDs: ["a"]).isEmpty)
        XCTAssertNil(library.photoCount(albumIdentifier: "alb", fallbackIDs: ["a"]))
    }

    func test_removeAsset_keepsPhotoInLibrary() async throws {
        let library = FakeRecordAlbumLibrary(
            assets: [asset("a", day: 1)],
            albums: [.init(id: "alb", title: "x", assetIDs: ["a"])])
        try await library.removeAsset("a", fromAlbum: "alb")
        XCTAssertTrue(library.photos(albumIdentifier: "alb", fallbackIDs: []).isEmpty)
        XCTAssertEqual(library.assets.map(\.id), ["a"])
    }

    func test_userAlbums_countsOnlyPhotos() {
        let library = FakeRecordAlbumLibrary(
            assets: [asset("a"), asset("v", video: true)],
            albums: [.init(id: "1", title: "甲", assetIDs: ["a", "v"]), .init(id: "2", title: "乙", assetIDs: [])])
        XCTAssertEqual(library.userAlbums(), [
            AlbumSummary(id: "1", title: "甲", photoCount: 1),
            AlbumSummary(id: "2", title: "乙", photoCount: 0),
        ])
    }

    func test_forUITests_generatesOnePhotoPerDayBackFromFakeToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        let library = try XCTUnwrap(FakeRecordAlbumLibrary.forUITests(
            arguments: ["-UITestRecordPhotos", "5"],
            environment: ["DAYSCAM_FAKE_TODAY": "2026-01-10"],
            calendar: calendar))
        let photos = library.photos(albumIdentifier: nil, fallbackIDs: library.assets.map(\.id))
        XCTAssertEqual(photos.count, 5)
        let days = photos.compactMap { $0.creationDate }.map { calendar.dateComponents([.year, .month, .day], from: $0) }
        XCTAssertEqual(days.map(\.day), [6, 7, 8, 9, 10])
        XCTAssertTrue(days.allSatisfy { $0.year == 2026 && $0.month == 1 })
    }

    func test_forUITests_withoutArgument_isNil() {
        XCTAssertNil(FakeRecordAlbumLibrary.forUITests(arguments: [], environment: [:]))
    }
}
