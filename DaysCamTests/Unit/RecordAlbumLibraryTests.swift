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

    func test_limited_returnsAllVisibleImages_withoutReadingAlbums() {
        let library = FakeRecordAlbumLibrary(
            status: .limited,
            assets: [asset("a", day: 1), asset("b", day: 2), asset("v", day: 3, video: true), asset("hidden", day: 4)],
            albums: [.init(id: "alb", title: "x", assetIDs: ["a"])])
        library.visibleIDs = ["a", "b", "v"]
        XCTAssertEqual(ids(library.photos(albumIdentifier: "alb", fallbackIDs: ["hidden"])), ["a", "b"])
        XCTAssertEqual(library.albumReadCount, 0)
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
