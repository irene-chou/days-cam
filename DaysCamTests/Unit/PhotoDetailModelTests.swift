import Photos
import UIKit
import XCTest
@testable import DaysCam

/// What a stand-in `bake` was called with.
private final class BakeRecorder: @unchecked Sendable {
    struct Call {
        let text: String
        let cropRect: CGRect?
        let tone: ColorTone
    }
    private let lock = NSLock()
    private var recorded: [Call] = []
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }

    func bake(_ image: UIImage, _ text: String, _ style: OverlayStyle, _ placement: OverlayPlacement,
              _ font: ResolvedOverlayFont, _ cropRect: CGRect?, _ filmDate: FilmDateStamp?, _ tone: ColorTone) -> UIImage? {
        lock.lock()
        recorded.append(Call(text: text, cropRect: cropRect, tone: tone))
        lock.unlock()
        return image
    }
}

/// #619 acceptance 2, 3, 4, 6 and 7: the viewer's text, bake call, removal and
/// deletion, over a real `ProfileStore` and a fake library.
@MainActor
final class PhotoDetailModelTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private let calendar = DateFixture.taipei

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PhotoDetailModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "PhotoDetailModelTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeStore(start: DateComponents = DateFixture.components(2026, 1, 1),
                           albumIdentifier: String? = "album",
                           fallbackIDs: [String] = []) throws -> (ProfileStore, CameraProfile) {
        let store = ProfileStore(directory: directory, calendar: calendar,
                                 now: { DateFixture.date(2026, 1, 10, hour: 8) ?? Date(timeIntervalSince1970: 0) },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        store.load()
        let profile = try store.add(CameraProfile(name: "小寶", startDate: start,
                                                  albumIdentifier: albumIdentifier, fallbackAssetIDs: fallbackIDs))
        return (store, profile)
    }

    private func library(albumIDs: [String]? = nil, dates: [Int?] = [6, 7, 8, 9, 10]) -> FakeRecordAlbumLibrary {
        let assets = dates.enumerated().map { index, day in
            FakeRecordAlbumLibrary.Asset(id: "p\(index + 1)",
                                         creationDate: day.flatMap { DateFixture.date(2026, 1, $0, hour: 15, minute: 7) })
        }
        let album = FakeRecordAlbumLibrary.Album(id: "album", title: "小寶", assetIDs: albumIDs ?? assets.map(\.id))
        return FakeRecordAlbumLibrary(assets: assets, albums: [album])
    }

    private func makeModel(store: ProfileStore, profile: CameraProfile, library: FakeRecordAlbumLibrary,
                           startingAt id: String = "p5", recorder: BakeRecorder = BakeRecorder()) -> PhotoDetailModel {
        PhotoDetailModel(profileID: profile.id, startingAt: id, store: store, library: library, calendar: calendar,
                         bake: { recorder.bake($0, $1, $2, $3, $4, $5, $6, $7) },
                         resolveFont: { _ in .pingFang })
    }

    // MARK: Header and overlay (1, 2, 3, 4)

    /// 1: the header reads 第 10 天 and the photo's own date and time.
    func testHeaderShowsDayAndDateOfThePhoto() throws {
        let (store, profile) = try makeStore()
        let model = makeModel(store: store, profile: profile, library: library())
        let photo = try XCTUnwrap(model.currentPhoto)
        XCTAssertEqual(model.title(for: photo), "第 10 天")
        XCTAssertEqual(model.dateLine(for: photo), "2026/1/10 15:07")
    }

    /// 2: the text is the renderer's photo-moment output and the page is
    /// drawn by `bake` with the standard tone and no crop.
    func testPageIsBakedWithTheRendererTextAndStandardTone() async throws {
        let (store, profile) = try makeStore()
        let recorder = BakeRecorder()
        let model = makeModel(store: store, profile: profile, library: library(), recorder: recorder)
        let photo = try XCTUnwrap(model.currentPhoto)
        let expected = TemplateRenderer().render(profile: profile, capturedAt: try XCTUnwrap(photo.creationDate),
                                                 calendar: calendar, moment: .photo)
        let image = await model.pageImage(for: photo, targetSize: CGSize(width: 200, height: 300))
        XCTAssertNotNil(image)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls.first?.text, expected)
        XCTAssertEqual(recorder.calls.first?.tone, .standard)
        XCTAssertNil(recorder.calls.first?.cropRect)
        XCTAssertTrue(expected.contains("10"), "the text carries the photo's day count")
    }

    /// 3: a start date after the photo reads 前 N 天 in both the header and
    /// the overlay, the same as the wall's mark.
    func testStartDateAfterThePhotoReadsBeforeNDays() async throws {
        let (store, profile) = try makeStore(start: DateFixture.components(2026, 1, 12))
        let recorder = BakeRecorder()
        let model = makeModel(store: store, profile: profile, library: library(), recorder: recorder)
        let photo = try XCTUnwrap(model.currentPhoto)
        XCTAssertEqual(model.title(for: photo), "前 2 天")
        let wall = PhotoWallModel.dayMark(creationDate: photo.creationDate, profile: profile, calendar: calendar)
        XCTAssertEqual(model.title(for: photo), wall.text)
        _ = await model.pageImage(for: photo, targetSize: CGSize(width: 200, height: 300))
        XCTAssertTrue(try XCTUnwrap(recorder.calls.first?.text).contains("前 2 天"))
    }

    /// 4: no `creationDate` means no bake and 日期不明.
    func testPhotoWithoutADateIsNotBaked() async throws {
        let (store, profile) = try makeStore()
        let recorder = BakeRecorder()
        let model = makeModel(store: store, profile: profile, library: library(dates: [nil, 7]),
                              startingAt: "p1", recorder: recorder)
        let photo = try XCTUnwrap(model.currentPhoto)
        XCTAssertEqual(model.title(for: photo), "日期不明")
        XCTAssertNil(model.dateLine(for: photo))
        let image = await model.pageImage(for: photo, targetSize: CGSize(width: 200, height: 300))
        XCTAssertNotNil(image, "the plain photo is still shown")
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    /// The order is the wall's.
    func testPhotosFollowTheWallOrder() throws {
        let (store, profile) = try makeStore()
        let lib = library()
        let model = makeModel(store: store, profile: profile, library: lib)
        let wall = PhotoWallModel(profileID: profile.id, store: store, library: lib, calendar: calendar,
                                  todayText: { _ in "" })
        XCTAssertEqual(model.photos.map(\.id), wall.photoIDs)
    }

    // MARK: Remove (6)

    /// 6: an album photo goes through `removeAsset`, stays in the library,
    /// and the next photo is shown.
    func testRemovingAnAlbumPhotoKeepsItInTheLibrary() async throws {
        let (store, profile) = try makeStore()
        let lib = library()
        let model = makeModel(store: store, profile: profile, library: lib, startingAt: "p3")
        await model.removeFromRecord()
        XCTAssertFalse(try XCTUnwrap(lib.albums.first).assetIDs.contains("p3"))
        XCTAssertTrue(lib.assets.contains { $0.id == "p3" })
        XCTAssertEqual(model.photos.map(\.id), ["p1", "p2", "p4", "p5"])
        XCTAssertEqual(model.selectedID, "p4")
        XCTAssertFalse(model.shouldDismiss)
    }

    /// 6: a fallback photo loses its id from the record.
    func testRemovingAFallbackPhotoDropsItsID() async throws {
        let (store, profile) = try makeStore(albumIdentifier: nil, fallbackIDs: ["p2", "p4"])
        let lib = library(albumIDs: [])
        let model = makeModel(store: store, profile: profile, library: lib, startingAt: "p2")
        await model.removeFromRecord()
        XCTAssertEqual(store.profiles.first { $0.id == profile.id }?.fallbackAssetIDs, ["p4"])
        XCTAssertTrue(lib.assets.contains { $0.id == "p2" })
        XCTAssertEqual(model.selectedID, "p4")
    }

    /// 6: a photo in both places leaves both.
    func testRemovingAPhotoInBothLeavesBoth() async throws {
        let (store, profile) = try makeStore(fallbackIDs: ["p3"])
        let lib = library(albumIDs: ["p1", "p3"])
        let model = makeModel(store: store, profile: profile, library: lib, startingAt: "p3")
        await model.removeFromRecord()
        XCTAssertEqual(try XCTUnwrap(lib.albums.first).assetIDs, ["p1"])
        XCTAssertEqual(store.profiles.first { $0.id == profile.id }?.fallbackAssetIDs, [])
        XCTAssertEqual(model.photos.map(\.id), ["p1"])
    }

    /// The last photo has no next: the viewer goes back to the wall.
    func testRemovingTheLastPhotoGoesBackToTheWall() async throws {
        let (store, profile) = try makeStore()
        let model = makeModel(store: store, profile: profile, library: library(), startingAt: "p5")
        await model.removeFromRecord()
        XCTAssertTrue(model.shouldDismiss)
    }

    /// A failing album change reports and keeps everything.
    func testRemoveFailureKeepsThePhotoAndReports() async throws {
        let (store, profile) = try makeStore()
        let lib = library()
        lib.failure = .failed("壞了")
        let model = makeModel(store: store, profile: profile, library: lib, startingAt: "p3")
        await model.removeFromRecord()
        XCTAssertEqual(model.errorMessage, "壞了")
        XCTAssertEqual(model.photos.count, 5)
        XCTAssertEqual(model.selectedID, "p3")
        XCTAssertFalse(model.shouldDismiss)
    }

    // MARK: Delete (7)

    /// 7: a cancelled system dialog changes nothing.
    func testCancelledDeletionChangesNothing() async throws {
        let (store, profile) = try makeStore()
        let lib = library()
        lib.confirmsDeletion = false
        let model = makeModel(store: store, profile: profile, library: lib, startingAt: "p3")
        await model.deletePhoto()
        XCTAssertEqual(model.photos.count, 5)
        XCTAssertEqual(model.selectedID, "p3")
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.shouldDismiss)
        XCTAssertEqual(lib.assets.count, 5)
    }

    /// A confirmed deletion removes the photo and moves on.
    func testConfirmedDeletionMovesToTheNextPhoto() async throws {
        let (store, profile) = try makeStore()
        let lib = library()
        let model = makeModel(store: store, profile: profile, library: lib, startingAt: "p3")
        await model.deletePhoto()
        XCTAssertEqual(lib.assets.count, 4)
        XCTAssertEqual(model.selectedID, "p4")
        XCTAssertEqual(model.photos.count, 4)
    }

    // MARK: Export (#647: 3, 5, 6, 7, 8)

    private var tipsSuite = ""

    private func makeTips(exportIntroSeen: Bool = true, coachSeen: Bool = true) throws -> FirstRunTips {
        tipsSuite = "FirstRunTips-\(UUID().uuidString)"
        let tips = FirstRunTips(defaults: try XCTUnwrap(UserDefaults(suiteName: tipsSuite)))
        if exportIntroSeen { tips.markExportIntroSeen() }
        if coachSeen { tips.markViewerCoachSeen() }
        return tips
    }


    private final class SaveCounter {
        var count = 0
        var result: Result<String, PhotoSaveError> = .success("new")
    }

    private final class Announcements {
        var messages: [String] = []
    }

    /// A viewer over `ExportLibrary` whose pipeline counts saves; toast
    /// expiry runs only when the test says so.
    private func makeExportRig(store: ProfileStore, profile: CameraProfile, tips: FirstRunTips,
                               photoDay: Int? = 10) -> (PhotoDetailModel, ExportLibrary, SaveCounter, Announcements, ScheduledActions) {
        let photo = RecordPhoto(id: "p1", creationDate: photoDay.flatMap { DateFixture.date(2026, 1, $0, hour: 15, minute: 7) })
        let library = ExportLibrary(photos: [photo])
        let saves = SaveCounter()
        let announced = Announcements()
        let scheduled = ScheduledActions()
        let pipeline = PhotoExportPipeline(library: library, calendar: calendar,
                                           bake: { image, _, _, _, _, _, _, _ in image },
                                           save: { _, completion in
                                               saves.count += 1
                                               completion(saves.result)
                                           })
        let model = PhotoDetailModel(profileID: profile.id, startingAt: "p1", store: store, library: library,
                                     calendar: calendar, resolveFont: { _ in .pingFang },
                                     pipeline: pipeline, tips: tips,
                                     scheduleAfter: { _, action in scheduled.actions.append(action) })
        model.announce = { announced.messages.append($0) }
        return (model, library, saves, announced, scheduled)
    }

    private final class ScheduledActions {
        var actions: [() -> Void] = []
    }

    /// 3: a seen comparison exports at once; success announces and toasts
    /// 已匯出, stays on the same photo, and the toast goes away later.
    func testExportSucceedsWithToastAndStaysOnThePhoto() async throws {
        let (store, profile) = try makeStore()
        let (model, _, saves, announced, scheduled) = makeExportRig(store: store, profile: profile, tips: try makeTips())
        await model.requestExport()

        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(model.toastState?.message, "已匯出")
        XCTAssertEqual(announced.messages, ["已匯出"])
        XCTAssertNil(model.exportError)
        XCTAssertFalse(model.isExporting)
        XCTAssertEqual(model.selectedID, "p1")
        XCTAssertFalse(model.shouldDismiss)
        scheduled.actions.forEach { $0() }
        XCTAssertNil(model.toastState)
    }

    /// 5: a failed save alerts, never toasts or announces, and the button works again.
    func testSaveFailureAlertsWithoutToast() async throws {
        let (store, profile) = try makeStore()
        let (model, _, saves, announced, _) = makeExportRig(store: store, profile: profile, tips: try makeTips())
        saves.result = .failure(.permissionDenied)
        await model.requestExport()

        let error = try XCTUnwrap(model.exportError)
        XCTAssertEqual(error.message, "新照片沒有存起來。請到「設定」›「DaysCam」›「照片」允許取用後再匯出一次。")
        XCTAssertTrue(error.showsSettingsAction)
        XCTAssertNil(model.toastState)
        XCTAssertTrue(announced.messages.isEmpty)
        XCTAssertFalse(model.isExporting)
        XCTAssertTrue(model.canStartExport)
        model.dismissExportError()
        XCTAssertNil(model.exportError)
    }

    /// 6: pressing again while the original downloads starts no second export.
    func testSecondPressWhileExportingDoesNothing() async throws {
        let (store, profile) = try makeStore()
        let (model, library, saves, _, _) = makeExportRig(store: store, profile: profile, tips: try makeTips())
        library.holdsFullImage = true
        let first = Task { await model.requestExport() }
        for _ in 0..<200 where library.heldCount == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(model.isExporting)
        XCTAssertFalse(model.canStartExport)

        await model.requestExport()
        XCTAssertEqual(library.fullImageCount, 1)

        library.release()
        await first.value
        XCTAssertEqual(saves.count, 1)
        XCTAssertFalse(model.isExporting)
    }

    /// 7: the first press opens the comparison and exports nothing.
    func testFirstPressOpensTheComparisonFirst() async throws {
        let (store, profile) = try makeStore()
        let tips = try makeTips(exportIntroSeen: false)
        let (model, library, saves, _, _) = makeExportRig(store: store, profile: profile, tips: tips)
        await model.requestExport()

        XCTAssertTrue(model.showsExportIntro)
        XCTAssertEqual(saves.count, 0)
        XCTAssertEqual(library.fullImageCount, 0)
        XCTAssertFalse(tips.exportIntroSeen, "opening it is not seeing it")
    }

    /// 7: 匯出 on the comparison counts as seen and exports; later presses go straight through.
    func testExportOnTheComparisonExportsAndIsSeen() async throws {
        let (store, profile) = try makeStore()
        let tips = try makeTips(exportIntroSeen: false)
        let (model, _, saves, _, _) = makeExportRig(store: store, profile: profile, tips: tips)
        await model.requestExport()
        await model.confirmExportIntro()

        XCTAssertFalse(model.showsExportIntro)
        XCTAssertTrue(tips.exportIntroSeen)
        XCTAssertEqual(saves.count, 1)
        await model.requestExport()
        XCTAssertFalse(model.showsExportIntro)
        XCTAssertEqual(saves.count, 2)
    }

    /// 7: 先調整文字樣式 counts as seen and exports nothing.
    func testStyleFirstOnTheComparisonIsSeenWithoutExporting() async throws {
        let (store, profile) = try makeStore()
        let tips = try makeTips(exportIntroSeen: false)
        let (model, _, saves, _, _) = makeExportRig(store: store, profile: profile, tips: tips)
        await model.requestExport()
        model.skipExportIntroForStyle()

        XCTAssertFalse(model.showsExportIntro)
        XCTAssertTrue(tips.exportIntroSeen)
        XCTAssertEqual(saves.count, 0)
    }

    /// 7: swiping the sheet away (the binding going false) is not seeing it and exports nothing.
    func testSwipingTheComparisonAwayIsNotSeen() async throws {
        let (store, profile) = try makeStore()
        let tips = try makeTips(exportIntroSeen: false)
        let (model, _, saves, _, _) = makeExportRig(store: store, profile: profile, tips: tips)
        await model.requestExport()
        model.showsExportIntro = false

        XCTAssertFalse(tips.exportIntroSeen)
        XCTAssertEqual(saves.count, 0)
        await model.requestExport()
        XCTAssertTrue(model.showsExportIntro, "it comes back at the next press")
    }

    /// 8: after the batch preview marked it, a single export skips the comparison.
    func testSeenByTheBatchPreviewSkipsTheComparison() async throws {
        let (store, profile) = try makeStore()
        let tips = try makeTips(exportIntroSeen: false)
        tips.markExportIntroSeen()
        let (model, _, saves, _, _) = makeExportRig(store: store, profile: profile, tips: tips)
        await model.requestExport()

        XCTAssertFalse(model.showsExportIntro)
        XCTAssertEqual(saves.count, 1)
    }

    /// 1: a photo without a date cannot be exported, and nothing happens on a press.
    func testPhotoWithoutDateCannotStartAnExport() async throws {
        let (store, profile) = try makeStore()
        let (model, library, saves, _, _) = makeExportRig(store: store, profile: profile, tips: try makeTips(),
                                                          photoDay: nil)
        XCTAssertFalse(model.canStartExport)
        await model.requestExport()
        XCTAssertEqual(saves.count, 0)
        XCTAssertEqual(library.fullImageCount, 0)
    }

    // MARK: Pointer bubble (#647: 9)

    /// 9: the bubble shows on a photo with overlay text until 知道了.
    func testCoachShowsUntilDismissed() throws {
        let (store, profile) = try makeStore()
        let tips = try makeTips(coachSeen: false)
        let (model, _, _, _, _) = makeExportRig(store: store, profile: profile, tips: tips)
        XCTAssertTrue(model.showsCoach)
        model.dismissCoach()
        XCTAssertFalse(model.showsCoach)
        XCTAssertTrue(tips.viewerCoachSeen)
    }

    /// 9: seen once, a new viewer does not show it again.
    func testCoachStaysGoneInANewViewer() throws {
        let (store, profile) = try makeStore()
        let tips = try makeTips(coachSeen: false)
        let (first, _, _, _, _) = makeExportRig(store: store, profile: profile, tips: tips)
        first.dismissCoach()
        let (second, _, _, _, _) = makeExportRig(store: store, profile: profile, tips: tips)
        XCTAssertFalse(second.showsCoach)
    }

    /// The ring's frame sits inside the image and follows the placement.
    func testOverlayFrameFollowsThePlacement() throws {
        let (store, profile) = try makeStore()
        let (model, _, _, _, _) = makeExportRig(store: store, profile: profile, tips: try makeTips())
        let photo = try XCTUnwrap(model.currentPhoto)
        let size = CGSize(width: 300, height: 400)
        let frame = try XCTUnwrap(model.overlayFrame(for: photo, imageSize: size))
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frame), "\(frame)")
        XCTAssertGreaterThan(frame.width, 0)
    }

    // MARK: Wording (#647: 12)

    /// 12: removing without the 「照片」 permission says so.
    func testRemovePermissionMessage() {
        XCTAssertEqual(PhotoDetailModel.message(for: .permissionDenied), "需要「照片」權限才能從紀錄移除。")
    }
}
