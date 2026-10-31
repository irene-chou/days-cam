import Photos
import UIKit
import XCTest
@testable import DaysCam

/// What a stand-in `bake` was called with.
final class ExportBakeRecorder: @unchecked Sendable {
    struct Call {
        let text: String
        let cropRect: CGRect?
        let filmDate: FilmDateStamp?
        let tone: ColorTone
        let imageSize: CGSize
    }
    private let lock = NSLock()
    private var recorded: [Call] = []
    /// `false` makes the bake fail (return `nil`).
    var succeeds = true
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }

    func bake(_ image: UIImage, _ text: String, _ style: OverlayStyle, _ placement: OverlayPlacement,
              _ font: ResolvedOverlayFont, _ cropRect: CGRect?, _ filmDate: FilmDateStamp?, _ tone: ColorTone) -> UIImage? {
        lock.lock()
        recorded.append(Call(text: text, cropRect: cropRect, filmDate: filmDate, tone: tone, imageSize: image.size))
        let succeeds = self.succeeds
        lock.unlock()
        return succeeds ? image : nil
    }
}

/// A record library that counts what the export asks of it. `fullImage` can
/// be held until the test releases it, or made to throw.
@MainActor
final class ExportLibrary: RecordAlbumLibrary {
    var photosInAlbum: [RecordPhoto]
    var fullImageError: Error?
    var holdsFullImage = false
    private(set) var fullImageCount = 0
    private(set) var addAssetsCount = 0
    private var held: [CheckedContinuation<Void, Never>] = []

    init(photos: [RecordPhoto]) {
        photosInAlbum = photos
    }

    /// Lets every held `fullImage` call go on.
    func release() {
        holdsFullImage = false
        held.forEach { $0.resume() }
        held = []
    }

    var heldCount: Int { held.count }

    func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    func requestReadWriteAccess() async -> PHAuthorizationStatus { .authorized }
    func photos(albumIdentifier: String?, fallbackIDs: [String]) -> [RecordPhoto] { photosInAlbum }
    func photoCount(albumIdentifier: String?, fallbackIDs: [String]) -> Int? { photosInAlbum.count }
    func userAlbums() -> [AlbumSummary] { [] }
    func addAssets(_ ids: [String], albumIdentifier: String?, albumTitle: String) async throws -> String {
        addAssetsCount += 1
        return "album"
    }
    func removeAsset(_ id: String, fromAlbum albumIdentifier: String) async throws {}
    func deleteAsset(_ id: String) async -> Bool { false }
    func changes() -> AsyncStream<Void> { AsyncStream { _ in } }
    func thumbnail(id: String, targetSize: CGSize) async -> UIImage? { nil }
    func displayImage(id: String, targetSize: CGSize) async -> UIImage? { Self.image(width: 30, height: 40) }

    func fullImage(id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> UIImage {
        fullImageCount += 1
        if holdsFullImage {
            await withCheckedContinuation { held.append($0) }
        }
        if let fullImageError { throw fullImageError }
        progress(1)
        return Self.image(width: 300, height: 400)
    }

    static func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { context in
                UIColor.gray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
    }
}

/// A photo library that records which save path was used (FR-19.9).
final class RecentsOnlyStubLibrary: PhotoLibraryAccessing {
    var writes = 0
    var albumWrites = 0
    var writeSucceeds = true

    func authorizationStatus(for level: PHAccessLevel) -> PHAuthorizationStatus { .authorized }
    func requestAuthorization(for level: PHAccessLevel, handler: @escaping (PHAuthorizationStatus) -> Void) {
        handler(.authorized)
    }
    func performChanges(_ changes: @escaping () -> String?,
                        completion: @escaping (Bool, String?, Error?) -> Void) {
        writes += 1
        completion(writeSucceeds, writeSucceeds ? "exported-1" : nil,
                   writeSucceeds ? nil : NSError(domain: "test", code: 1,
                                                 userInfo: [NSLocalizedDescriptionKey: "空間不足"]))
    }
    func saveToAlbum(_ image: UIImage, albumIdentifier: String?, albumTitle: String,
                     completion: @escaping (AlbumWriteResult) -> Void) {
        albumWrites += 1
        completion(AlbumWriteResult(succeeded: true, assetIdentifier: "a", albumIdentifier: "b", error: nil))
    }
    func saveToRecordAlbum(_ image: UIImage, albumIdentifier: String?, albumTitle: String,
                           completion: @escaping (AlbumWriteResult) -> Void) {
        albumWrites += 1
        completion(AlbumWriteResult(succeeded: true, assetIdentifier: "a", albumIdentifier: "b", error: nil))
    }
}

/// #647 acceptance 11: the 文字樣式 page's header, write-back, drag and
/// preview (the export itself is `PhotoExportPipelineTests`).
@MainActor
final class ExportModelTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private let calendar = DateFixture.taipei

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ExportModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ExportModelTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeStore(showFilmDate: Bool = false) throws -> (ProfileStore, CameraProfile) {
        let store = ProfileStore(directory: directory, calendar: calendar,
                                 now: { DateFixture.date(2026, 1, 20, hour: 8) ?? Date(timeIntervalSince1970: 0) },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        store.load()
        var profile = CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1), albumIdentifier: "album")
        profile.showFilmDate = showFilmDate
        return (store, try store.add(profile))
    }

    private func photo(day: Int? = 10) -> RecordPhoto {
        RecordPhoto(id: "p1", creationDate: day.flatMap { DateFixture.date(2026, 1, $0, hour: 15, minute: 7) })
    }

    private func makeEditor(store: ProfileStore, profile: CameraProfile) -> ProfileStyleEditor {
        ProfileStyleEditor(profile: profile, profileStore: store, fontLibrary: FakeShellFontLibrary(),
                           calendar: calendar, calculator: DayCountCalculator(calendar: calendar),
                           renderer: TemplateRenderer(),
                           applyFont: { _, _ in }, allProfiles: { store.profiles },
                           didWriteStyle: { _, _ in })
    }

    private func makeModel(store: ProfileStore,
                           profile: CameraProfile,
                           photo: RecordPhoto,
                           library: ExportLibrary) -> ExportModel {
        ExportModel(profileID: profile.id, photo: photo, store: store, library: library,
                    editor: makeEditor(store: store, profile: profile),
                    calendar: calendar,
                    resolveFont: { _ in .pingFang })
    }

    // MARK: 7. Write-back

    /// 11: a panel change is in the store at once, and a reopened page (after
    /// `xmark`) shows it; nothing is rolled back.
    func testPanelChangeIsSavedAndSurvivesReopening() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let library = ExportLibrary(photos: [photo])
        var model: ExportModel? = makeModel(store: store, profile: profile, photo: photo, library: library)
        let style = try XCTUnwrap(model?.styleTabModel)
        XCTAssertNotEqual(style.profile.style.outline, .box)

        style.selectOutline(.box)
        XCTAssertEqual(store.profiles.first { $0.id == profile.id }?.style.outline, .box)

        model = nil
        let reopened = makeModel(store: store, profile: try XCTUnwrap(store.profiles.first { $0.id == profile.id }),
                                 photo: photo, library: library)
        XCTAssertEqual(reopened.styleTabModel?.profile.style.outline, .box)
        XCTAssertEqual(reopened.profile?.style.outline, .box)
    }

    /// 8 (model side): a drag on the preview ends as the record's `.custom`
    /// position.
    func testDragOnPreviewWritesThePosition() throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let model = makeModel(store: store, profile: profile, photo: photo, library: ExportLibrary(photos: [photo]))
        XCTAssertTrue(model.panelModel.isOverlayDraggable)
        model.panelModel.overlayDragHandler?.overlayDragEnded(center: CGPoint(x: 100, y: 50),
                                                              viewfinderSize: CGSize(width: 200, height: 200))
        guard case let .custom(x, y)? = store.profiles.first(where: { $0.id == profile.id })?.position else {
            return XCTFail("position not written")
        }
        XCTAssertEqual(x, 0.5, accuracy: 0.001)
        XCTAssertEqual(y, 0.25, accuracy: 0.001)
    }

    /// The preview follows the store: a change elsewhere redraws it.
    func testPreviewFollowsTheRecord() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let model = makeModel(store: store, profile: profile, photo: photo, library: ExportLibrary(photos: [photo]))
        var changed = profile
        changed.showFilmDate = true
        try store.updateAndWait(changed)
        let expectation = expectation(description: "profile follows")
        DispatchQueue.main.async { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertNotNil(model.filmDateStamp)
    }

    // MARK: Header

    /// 11: the subtitle names the record and says the style applies to all.
    func testSubtitleNamesTheRecord() throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let model = makeModel(store: store, profile: profile, photo: photo, library: ExportLibrary(photos: [photo]))
        XCTAssertEqual(model.subtitle, "小寶 · 套用到所有照片")
    }

    /// A photo without `creationDate` draws no text on the page.
    func testPhotoWithoutDateHasNoOverlayText() throws {
        let (store, profile) = try makeStore()
        let undated = photo(day: nil)
        let model = makeModel(store: store, profile: profile, photo: undated, library: ExportLibrary(photos: [undated]))
        XCTAssertNil(model.overlayText)
        XCTAssertNil(model.filmDateStamp)
    }
}
