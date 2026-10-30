import Photos
import UIKit
import XCTest
@testable import DaysCam

/// What a stand-in `bake` was called with.
private final class ExportBakeRecorder: @unchecked Sendable {
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
private final class ExportLibrary: RecordAlbumLibrary {
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
private final class RecentsOnlyStubLibrary: PhotoLibraryAccessing {
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

/// #620 acceptance 1–7 and 10: the export page's bake, save, failures,
/// single export, success, write-back and the viewer's disabled button.
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
                           library: ExportLibrary,
                           recorder: ExportBakeRecorder = ExportBakeRecorder(),
                           save: @escaping ExportModel.Save = { _, completion in completion(.success("new")) },
                           scheduled: @escaping (TimeInterval, @escaping () -> Void) -> Void = { _, action in action() }) -> ExportModel {
        ExportModel(profileID: profile.id, photo: photo, store: store, library: library,
                    editor: makeEditor(store: store, profile: profile),
                    calendar: calendar,
                    bake: { recorder.bake($0, $1, $2, $3, $4, $5, $6, $7) },
                    save: save,
                    resolveFont: { _ in .pingFang },
                    scheduleAfter: scheduled)
    }

    // MARK: 1. What is baked

    /// 1: `bake` gets the original, the photo-moment text of `creationDate`,
    /// no crop, the standard tone and the film date of the photo's own day.
    func testExportBakesThePhotoMomentTextWithStandardToneAndNoCrop() async throws {
        let (store, profile) = try makeStore(showFilmDate: true)
        let photo = photo(day: 10)
        let recorder = ExportBakeRecorder()
        let model = makeModel(store: store, profile: profile, photo: photo, library: ExportLibrary(photos: [photo]),
                              recorder: recorder)
        await model.export()

        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertEqual(recorder.calls.count, 1)
        let expected = TemplateRenderer().render(profile: profile, capturedAt: try XCTUnwrap(photo.creationDate),
                                                 calendar: calendar, moment: .photo)
        XCTAssertEqual(call.text, expected)
        XCTAssertTrue(call.text.contains("第 10 天"), call.text)
        XCTAssertNil(call.cropRect)
        XCTAssertEqual(call.tone, .standard)
        XCTAssertEqual(call.imageSize, CGSize(width: 300, height: 400), "the original, not the display image")
        XCTAssertEqual(call.filmDate?.text, FilmDateStamp.text(for: DateFixture.components(2026, 1, 10)))
    }

    // MARK: 2. Where it is saved

    /// 2: the save goes through `saveToRecentsOnly`: one plain write, no album
    /// write, and nothing added to the record's album.
    func testExportSavesToRecentsOnlyAndNeverAddsToAnAlbum() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let library = ExportLibrary(photos: [photo])
        let photoLibrary = RecentsOnlyStubLibrary()
        let saver = PhotoSaver(library: photoLibrary)
        let model = makeModel(store: store, profile: profile, photo: photo, library: library,
                              save: { image, completion in saver.saveToRecentsOnly(image, completion: completion) })
        await model.export()

        XCTAssertEqual(photoLibrary.writes, 1)
        XCTAssertEqual(photoLibrary.albumWrites, 0)
        XCTAssertEqual(library.addAssetsCount, 0)
        XCTAssertNil(model.exportError)
        XCTAssertTrue(model.shouldDismiss)
    }

    // MARK: 3, 4. Failures

    /// 3: a failed save shows the error alert, never "已匯出".
    func testSaveFailureShowsAlertAndNoSuccess() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let photoLibrary = RecentsOnlyStubLibrary()
        photoLibrary.writeSucceeds = false
        let saver = PhotoSaver(library: photoLibrary)
        var announcements: [String] = []
        let model = makeModel(store: store, profile: profile, photo: photo, library: ExportLibrary(photos: [photo]),
                              save: { image, completion in saver.saveToRecentsOnly(image, completion: completion) })
        model.announce = { announcements.append($0) }
        await model.export()

        let error = try XCTUnwrap(model.exportError)
        XCTAssertTrue(error.message.contains("儲存失敗"), error.message)
        XCTAssertTrue(announcements.isEmpty)
        XCTAssertNil(model.toastState)
        XCTAssertFalse(model.shouldDismiss)
        XCTAssertFalse(model.isExporting)
        XCTAssertTrue(model.canExport)
    }

    /// 3: a refused permission offers 前往設定.
    func testPermissionDeniedOffersSettings() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let model = makeModel(store: store, profile: profile, photo: photo, library: ExportLibrary(photos: [photo]),
                              save: { _, completion in completion(.failure(.permissionDenied)) })
        await model.export()

        let error = try XCTUnwrap(model.exportError)
        XCTAssertEqual(error.message, PhotoSaveError.permissionDenied.displayMessage)
        XCTAssertTrue(error.showsSettingsAction)
        XCTAssertFalse(model.shouldDismiss)
    }

    /// 4: the original failing to download (iCloud) ends in the alert, nothing
    /// is baked or saved, and the checkmark works again.
    func testDownloadFailureShowsAlertAndReenablesTheCheckmark() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let library = ExportLibrary(photos: [photo])
        library.fullImageError = RecordAlbumError.failed("network")
        let recorder = ExportBakeRecorder()
        var saves = 0
        let model = makeModel(store: store, profile: profile, photo: photo, library: library, recorder: recorder,
                              save: { _, completion in saves += 1; completion(.success("x")) })
        await model.export()

        XCTAssertEqual(model.exportError?.message, ExportModel.downloadFailedMessage)
        XCTAssertTrue(recorder.calls.isEmpty)
        XCTAssertEqual(saves, 0)
        XCTAssertFalse(model.isExporting)
        XCTAssertTrue(model.canExport)
        XCTAssertNil(model.toastState)

        // Dismissed and tried again, it can succeed.
        model.dismissError()
        library.fullImageError = nil
        await model.export()
        XCTAssertNil(model.exportError)
        XCTAssertEqual(saves, 1)
    }

    /// A failed bake is not saved and not reported as exported (0.1 §7.3).
    func testBakeFailureShowsAlertAndSavesNothing() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let recorder = ExportBakeRecorder()
        recorder.succeeds = false
        var saves = 0
        let model = makeModel(store: store, profile: profile, photo: photo, library: ExportLibrary(photos: [photo]),
                              recorder: recorder,
                              save: { _, completion in saves += 1; completion(.success("x")) })
        await model.export()

        XCTAssertEqual(model.exportError?.message, ExportModel.bakeFailedMessage)
        XCTAssertEqual(saves, 0)
        XCTAssertNil(model.toastState)
        XCTAssertFalse(model.shouldDismiss)
    }

    // MARK: 5. One at a time

    /// 5: pressing the checkmark again while exporting starts nothing.
    func testSecondExportWhileExportingDoesNothing() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let library = ExportLibrary(photos: [photo])
        library.holdsFullImage = true
        var saves = 0
        let model = makeModel(store: store, profile: profile, photo: photo, library: library,
                              save: { _, completion in saves += 1; completion(.success("x")) })

        let first = Task { await model.export() }
        while library.heldCount == 0 { await Task.yield() }
        XCTAssertTrue(model.isExporting)
        XCTAssertFalse(model.canExport)

        await model.export()
        XCTAssertEqual(library.fullImageCount, 1)

        library.release()
        await first.value
        XCTAssertEqual(library.fullImageCount, 1)
        XCTAssertEqual(saves, 1)
    }

    /// While exporting, the panel and the preview's drag are locked so the
    /// screen keeps showing what is being baked; a failure unlocks them.
    func testEditingIsLockedWhileExporting() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let library = ExportLibrary(photos: [photo])
        library.holdsFullImage = true
        library.fullImageError = RecordAlbumError.failed("network")
        let model = makeModel(store: store, profile: profile, photo: photo, library: library)
        XCTAssertTrue(model.isEditable)
        XCTAssertTrue(model.isOverlayDraggable)

        let export = Task { await model.export() }
        while library.heldCount == 0 { await Task.yield() }
        XCTAssertFalse(model.isEditable)
        XCTAssertFalse(model.isOverlayDraggable)
        let before = store.profiles.first { $0.id == profile.id }?.position
        model.overlayDragEnded(center: CGPoint(x: 20, y: 20), frameSize: CGSize(width: 200, height: 200))
        XCTAssertEqual(store.profiles.first { $0.id == profile.id }?.position, before, "drag ignored")

        library.release()
        await export.value
        XCTAssertNotNil(model.exportError)
        XCTAssertTrue(model.isEditable, "unlocked after a failure")
        model.overlayDragEnded(center: CGPoint(x: 100, y: 50), frameSize: CGSize(width: 200, height: 200))
        XCTAssertNotEqual(store.profiles.first { $0.id == profile.id }?.position, before)
    }

    /// #633 驗收 1: the xmark cannot leave the page while exporting (so no
    /// orphan export saves a photo); a failure gives it back.
    func testCancelIsDisabledWhileExportingAndReturnsAfterFailure() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let library = ExportLibrary(photos: [photo])
        library.holdsFullImage = true
        library.fullImageError = RecordAlbumError.failed("network")
        let model = makeModel(store: store, profile: profile, photo: photo, library: library)
        XCTAssertTrue(model.canCancel)

        let export = Task { await model.export() }
        while library.heldCount == 0 { await Task.yield() }
        XCTAssertFalse(model.canCancel)

        library.release()
        await export.value
        XCTAssertNotNil(model.exportError)
        XCTAssertTrue(model.canCancel, "unlocked after a failure")
    }

    /// #633 驗收 2: the page cannot be left while exporting, so it cannot be
    /// reopened to bypass the one-at-a-time guard; success stays locked until
    /// the page dismisses.
    func testCancelStaysDisabledAfterSuccessUntilDismiss() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let model = makeModel(store: store, profile: profile, photo: photo, library: ExportLibrary(photos: [photo]),
                              scheduled: { _, _ in })
        await model.export()
        XCTAssertFalse(model.canCancel)
        XCTAssertFalse(model.canExport)
    }

    /// Success keeps it locked until the page closes.
    func testEditingStaysLockedAfterSuccess() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        let model = makeModel(store: store, profile: profile, photo: photo, library: ExportLibrary(photos: [photo]),
                              scheduled: { _, _ in })
        await model.export()
        XCTAssertFalse(model.isEditable)
        XCTAssertFalse(model.isOverlayDraggable)
    }

    // MARK: 6. Success

    /// 6: success announces "已匯出", shows the toast and goes back to the
    /// viewer after 0.9 seconds.
    func testSuccessAnnouncesShowsToastThenDismisses() async throws {
        let (store, profile) = try makeStore()
        let photo = photo()
        var pending: (delay: TimeInterval, action: () -> Void)?
        var announcements: [String] = []
        let model = makeModel(store: store, profile: profile, photo: photo, library: ExportLibrary(photos: [photo]),
                              scheduled: { delay, action in pending = (delay, action) })
        model.announce = { announcements.append($0) }
        await model.export()

        XCTAssertEqual(announcements, ["已匯出"])
        XCTAssertEqual(model.toastState?.message, "已匯出")
        XCTAssertFalse(model.shouldDismiss)
        XCTAssertFalse(model.canExport, "no second export while the toast shows")
        let scheduled = try XCTUnwrap(pending)
        XCTAssertEqual(scheduled.delay, 0.9, accuracy: 0.001)

        scheduled.action()
        XCTAssertNil(model.toastState)
        XCTAssertTrue(model.shouldDismiss)
    }

    // MARK: 7. Write-back

    /// 7: a panel change is in the store at once, and a new export page (after
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
        XCTAssertEqual(model.dayTitle, "第 10 天")
        var changed = profile
        changed.showFilmDate = true
        try store.updateAndWait(changed)
        let expectation = expectation(description: "profile follows")
        DispatchQueue.main.async { expectation.fulfill() }
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertNotNil(model.filmDateStamp)
    }

    // MARK: 10. No date, no export

    /// 10: a photo without `creationDate` cannot be exported, from the viewer
    /// or the page.
    func testPhotoWithoutDateCannotBeExported() async throws {
        let (store, profile) = try makeStore()
        let undated = photo(day: nil)
        let library = ExportLibrary(photos: [undated])
        let detail = PhotoDetailModel(profileID: profile.id, startingAt: undated.id, store: store, library: library,
                                      calendar: calendar, resolveFont: { _ in .pingFang })
        XCTAssertFalse(detail.canExport(undated))
        XCTAssertTrue(detail.canExport(photo(day: 9)))

        let model = makeModel(store: store, profile: profile, photo: undated, library: library)
        XCTAssertFalse(model.canExport)
        await model.export()
        XCTAssertEqual(library.fullImageCount, 0)
    }
}
