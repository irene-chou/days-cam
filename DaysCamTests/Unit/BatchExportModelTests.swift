import Photos
import UIKit
import XCTest
@testable import DaysCam

/// A stand-in for one photo's export: records the calls and how many run at
/// once, fails the ids it is told to, and can hold each call until released.
@MainActor
private final class FakeBatchExport {
    var failures: [String: PhotoExportError] = [:]
    var holds = false
    private(set) var calls: [String] = []
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    private var held: [CheckedContinuation<Void, Never>] = []

    var heldCount: Int { held.count }

    func export(_ photo: RecordPhoto, _ profile: CameraProfile) async -> Result<Void, PhotoExportError> {
        calls.append(photo.id)
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        if holds {
            await withCheckedContinuation { held.append($0) }
        } else {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        inFlight -= 1
        if let failure = failures[photo.id] { return .failure(failure) }
        return .success(())
    }

    /// Lets the oldest held call finish.
    func releaseOne() {
        guard !held.isEmpty else { return }
        held.removeFirst().resume()
    }

    var asExport: BatchExportModel.Export {
        { [self] photo, profile, _ in await self.export(photo, profile) }
    }
}

/// A record library for the real pipeline: tracks how many originals are
/// being exported at once, hands out large originals, notes whether the
/// previous one is still alive when the next is fetched, and counts the
/// writes and permission requests the export must not make.
@MainActor
private final class TrackingLibrary: RecordAlbumLibrary {
    let photosInAlbum: [RecordPhoto]
    private(set) var fullImageOrder: [String] = []
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    private(set) var requestCount = 0
    private(set) var addAssetsCount = 0
    /// For each `fullImage` after the first: whether the previous original was still alive.
    private(set) var previousAlive: [Bool] = []
    private weak var lastOriginal: UIImage?

    init(photos: [RecordPhoto]) {
        photosInAlbum = photos
    }

    /// The save finished: the export of one photo is over.
    func exportEnded() { inFlight -= 1 }

    func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    func requestReadWriteAccess() async -> PHAuthorizationStatus {
        requestCount += 1
        return .authorized
    }
    func photos(albumIdentifier: String?, fallbackIDs: [String]) -> [RecordPhoto] { photosInAlbum }
    func photoCount(albumIdentifier: String?, fallbackIDs: [String]) -> Int? { photosInAlbum.count }
    func userAlbums() -> [AlbumSummary] { [] }
    func addAssets(_ ids: [String], albumIdentifier: String?, albumTitle: String) async throws -> String {
        addAssetsCount += 1
        return "album"
    }
    func removeAssets(_ ids: [String], fromAlbum albumIdentifier: String) async throws {}
    func deleteAssets(_ ids: [String]) async -> Bool { false }
    func changes() -> AsyncStream<Void> { AsyncStream { _ in } }
    func thumbnail(id: String, targetSize: CGSize) async -> UIImage? { nil }
    func displayImage(id: String, targetSize: CGSize) async -> UIImage? { ExportLibrary.image(width: 30, height: 40) }

    func fullImage(id: String, progress: @escaping @Sendable (Double) -> Void) async throws -> UIImage {
        if !fullImageOrder.isEmpty { previousAlive.append(lastOriginal != nil) }
        fullImageOrder.append(id)
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        try? await Task.sleep(nanoseconds: 3_000_000)
        progress(1)
        let original = autoreleasepool { ExportLibrary.image(width: 2000, height: 1500) }
        lastOriginal = original
        return original
    }
}

/// #650 acceptance 1–13: the batch export's preview, order, stop, failures
/// and what it never writes, over a real `ProfileStore`.
@MainActor
final class BatchExportModelTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private let calendar = DateFixture.taipei

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BatchExportModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "BatchExportModelTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeStore(fallback: [String] = []) throws -> (ProfileStore, CameraProfile) {
        let store = ProfileStore(directory: directory, calendar: calendar,
                                 now: { DateFixture.date(2026, 1, 10, hour: 8) ?? Date(timeIntervalSince1970: 0) },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        store.load()
        let profile = try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1),
                                                  albumIdentifier: "album", fallbackAssetIDs: fallback))
        return (store, profile)
    }

    private func photo(_ day: Int?) -> RecordPhoto {
        RecordPhoto(id: day.map { "p\($0)" } ?? "undated",
                    creationDate: day.flatMap { DateFixture.date(2026, 1, $0, hour: 15) })
    }

    private func tips() -> FirstRunTips { FirstRunTips(defaults: defaults) }

    private func makeBatch(_ photos: [RecordPhoto], store: ProfileStore, profile: CameraProfile,
                           library: (any RecordAlbumLibrary)? = nil,
                           bake: ExportBakeRecorder = ExportBakeRecorder(),
                           tips: FirstRunTips? = nil,
                           export: @escaping BatchExportModel.Export) -> BatchExportModel {
        BatchExportModel(photos: photos, profileID: profile.id, store: store,
                         library: library ?? ExportLibrary(photos: photos), calendar: calendar,
                         bake: { bake.bake($0, $1, $2, $3, $4, $5, $6, $7) },
                         resolveFont: { _ in .pingFang }, tips: tips ?? self.tips(), export: export)
    }

    /// Records each outcome the batch reports.
    private func outcomes(of batch: BatchExportModel) -> () -> [BatchExportModel.Outcome] {
        var recorded: [BatchExportModel.Outcome] = []
        batch.onFinish = { recorded.append($0) }
        return { recorded }
    }

    /// Yields until `condition` holds, failing after a while.
    private func until(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("condition never held", file: file, line: line)
    }

    // MARK: - Wall

    private func wallLibrary(days: [Int?]) -> FakeRecordAlbumLibrary {
        let assets = days.map { day in
            FakeRecordAlbumLibrary.Asset(id: day.map { "p\($0)" } ?? "undated",
                                         creationDate: day.flatMap { DateFixture.date(2026, 1, $0, hour: 15) })
        }
        let album = FakeRecordAlbumLibrary.Album(id: "album", title: "小寶", assetIDs: assets.map(\.id))
        return FakeRecordAlbumLibrary(assets: assets, albums: [album])
    }

    /// A wall over `days` whose batch export runs through `fake`, with every
    /// photo ticked; `spoken` collects what VoiceOver hears.
    private func makeWall(days: [Int?], store: ProfileStore, profile: CameraProfile, fake: FakeBatchExport,
                          library: FakeRecordAlbumLibrary? = nil) -> (PhotoWallModel, () -> [String]) {
        let library = library ?? wallLibrary(days: days)
        var spoken: [String] = []
        let wall = PhotoWallModel(profileID: profile.id, store: store, library: library, calendar: calendar,
                                  todayText: { _ in "" }, defaults: defaults, scheduleAfter: { _, _ in },
                                  makeBatchExport: { [unowned self] photos in
                                      self.makeBatch(photos, store: store, profile: profile, export: fake.asExport)
                                  })
        wall.announce = { spoken.append($0) }
        wall.beginSelecting()
        wall.selectAll()
        return (wall, { spoken })
    }

    // MARK: - 1, 2: preview

    /// 1: three photos: the title and note, and the carousel steps 1／3 to
    /// 3／3, each with its own day, both in the text and in what is baked.
    func testPreviewCountsAndStepsThroughEachPhotosOwnDay() async throws {
        let (store, profile) = try makeStore()
        let recorder = ExportBakeRecorder()
        let fake = FakeBatchExport()
        let batch = makeBatch([photo(5), photo(6), photo(7)], store: store, profile: profile,
                              bake: recorder, export: fake.asExport)

        XCTAssertEqual(batch.phase, .preview)
        XCTAssertEqual(batch.previewTitle, "匯出 3 張新照片")
        XCTAssertEqual(BatchExportModel.previewMessage, "原圖不動，每張另存一張印上天數的新照片到「最近項目」。")
        XCTAssertNil(batch.skippedMessage)
        XCTAssertEqual(batch.exportButtonTitle, "匯出 3 張")

        var seen: [String] = []
        for expected in 1...3 {
            XCTAssertEqual(batch.previewPosition, "\(expected)／3")
            let shown = try XCTUnwrap(batch.previewPhoto)
            XCTAssertTrue(batch.overlayText(for: shown)?.contains("第 \(expected + 4) 天") == true)
            _ = await batch.previewImage(for: shown, targetSize: CGSize(width: 100, height: 100))
            seen.append(try XCTUnwrap(recorder.calls.last).text)
            batch.showNext()
        }
        XCTAssertEqual(batch.previewPosition, "1／3", "› wraps around")
        XCTAssertTrue(seen[0].contains("第 5 天") && seen[1].contains("第 6 天") && seen[2].contains("第 7 天"), "\(seen)")
        XCTAssertTrue(recorder.calls.allSatisfy { $0.cropRect == nil && $0.tone == .standard })
        batch.showPrevious()
        XCTAssertEqual(batch.previewPosition, "3／3")
        XCTAssertTrue(fake.calls.isEmpty, "the preview exports nothing")
    }

    /// 2: four ticked with one 日期不明: three to export, one more line, and
    /// the undated one never reaches the export nor counts as failed.
    func testUndatedPhotoIsSkippedNotFailed() async throws {
        let (store, profile) = try makeStore()
        let fake = FakeBatchExport()
        let batch = makeBatch([photo(nil), photo(5), photo(6), photo(7)], store: store, profile: profile,
                              export: fake.asExport)
        let finished = outcomes(of: batch)

        XCTAssertEqual(batch.previewTitle, "匯出 3 張新照片")
        XCTAssertEqual(batch.skippedMessage, "其中 1 張日期不明，無法標天數，會略過。")
        XCTAssertEqual(batch.exportable.map(\.id), ["p5", "p6", "p7"])

        batch.start()
        await batch.waitForRun()
        XCTAssertEqual(fake.calls, ["p5", "p6", "p7"])
        XCTAssertEqual(finished(), [.allSaved(count: 3)])
    }

    /// 4: a change made on the 文字樣式 page reaches the preview.
    func testPreviewFollowsTheRecordsStyle() async throws {
        let (store, profile) = try makeStore()
        let batch = makeBatch([photo(5)], store: store, profile: profile, export: FakeBatchExport().asExport)
        var changed = try XCTUnwrap(store.profiles.first { $0.id == profile.id })
        changed.style.showsShadow.toggle()
        try store.updateAndWait(changed)

        await until { batch.profile?.style == changed.style }
        XCTAssertEqual(batch.phase, .preview)
    }

    // MARK: - 3: cancel

    /// 3: 取消 on the preview: back to selecting, ticks unchanged, nothing exported.
    func testCancelKeepsTheSelectionAndExportsNothing() throws {
        let (store, profile) = try makeStore()
        let fake = FakeBatchExport()
        let (wall, spoken) = makeWall(days: [5, 6, 7], store: store, profile: profile, fake: fake)
        wall.toggle("p6")
        let ticked = wall.selectedIDs

        wall.beginBatchExport()
        let batch = try XCTUnwrap(wall.batchExport)
        XCTAssertEqual(batch.exportable.map(\.id), ["p5", "p7"], "wall order")
        batch.cancel()

        XCTAssertNil(wall.batchExport)
        XCTAssertTrue(wall.isSelecting)
        XCTAssertEqual(wall.selectedIDs, ticked)
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertNil(wall.toastState)
        XCTAssertTrue(spoken().isEmpty)
    }

    // MARK: - 5, 11, 13: the real pipeline

    /// 5, 13: through the real pipeline, one photo at a time in wall order,
    /// each baked with its own day, the standard tone and no crop; the
    /// previous original is gone before the next is fetched.
    /// 11: no album write, no permission request, `fallbackAssetIDs` untouched,
    /// saved by the 「最近項目」-only path.
    func testPipelineRunsOneAtATimeInOrderWithOwnDatesAndWritesNothingElse() async throws {
        let (store, profile) = try makeStore(fallback: ["p5"])
        let photos = [photo(5), photo(6), photo(7), photo(8)]
        let library = TrackingLibrary(photos: photos)
        let recorder = ExportBakeRecorder()
        let stub = RecentsOnlyStubLibrary()
        let saver = PhotoSaver(library: stub)
        let pipeline = PhotoExportPipeline(library: library, calendar: calendar,
                                           bake: { recorder.bake($0, $1, $2, $3, $4, $5, $6, $7) },
                                           save: { image, completion in
                                               library.exportEnded()
                                               saver.saveToRecentsOnly(image, completion: completion)
                                           })
        let batch = makeBatch(photos, store: store, profile: profile, library: library,
                              export: BatchExportModel.pipelineExport(pipeline, resolveFont: { _ in .pingFang }))
        let finished = outcomes(of: batch)

        batch.start()
        await batch.waitForRun()

        XCTAssertEqual(finished(), [.allSaved(count: 4)])
        XCTAssertEqual(library.fullImageOrder, ["p5", "p6", "p7", "p8"])
        XCTAssertEqual(library.maxInFlight, 1, "never two at once")
        XCTAssertEqual(recorder.calls.count, 4)
        for (call, day) in zip(recorder.calls, 5...8) {
            XCTAssertTrue(call.text.contains("第 \(day) 天"), call.text)
            XCTAssertNil(call.cropRect)
            XCTAssertEqual(call.tone, .standard)
            XCTAssertEqual(call.imageSize, CGSize(width: 2000, height: 1500))
        }
        XCTAssertEqual(library.previousAlive, [false, false, false], "each original released before the next")
        XCTAssertEqual(stub.writes, 4)
        XCTAssertEqual(stub.albumWrites, 0)
        XCTAssertEqual(library.addAssetsCount, 0)
        XCTAssertEqual(library.requestCount, 0)
        XCTAssertEqual(store.profiles.first { $0.id == profile.id }?.fallbackAssetIDs, ["p5"])
    }

    /// 5: the injected export never overlaps either, and keeps wall order.
    func testExportsOneAtATimeInWallOrder() async throws {
        let (store, profile) = try makeStore()
        let fake = FakeBatchExport()
        let batch = makeBatch([photo(7), photo(5), photo(6)], store: store, profile: profile, export: fake.asExport)

        batch.start()
        batch.start()
        await batch.waitForRun()
        XCTAssertEqual(fake.calls, ["p7", "p5", "p6"], "the order given, once")
        XCTAssertEqual(fake.maxInFlight, 1)
    }

    // MARK: - 6: progress

    /// 6: 匯出中 counts up as each photo finishes.
    func testProgressCountsUpPerPhoto() async throws {
        let (store, profile) = try makeStore()
        let fake = FakeBatchExport()
        fake.holds = true
        let batch = makeBatch([photo(5), photo(6), photo(7)], store: store, profile: profile, export: fake.asExport)

        batch.start()
        XCTAssertEqual(batch.phase, .running(done: 0, total: 3))
        XCTAssertEqual(batch.progressText, "0／3")
        for done in 1...3 {
            await until { fake.heldCount == 1 }
            fake.releaseOne()
            if done < 3 {
                await until { batch.progressText == "\(done)／3" }
            }
        }
        await batch.waitForRun()
        XCTAssertEqual(fake.maxInFlight, 1)
    }

    // MARK: - 7: stop

    /// 7: 停止 during the second photo: it finishes, the third never starts,
    /// the toast counts what was really saved, selection ends, nothing is deleted.
    func testStopFinishesTheCurrentPhotoAndStartsNoMore() async throws {
        let (store, profile) = try makeStore()
        let fake = FakeBatchExport()
        fake.holds = true
        let library = wallLibrary(days: [5, 6, 7, 8])
        let (wall, spoken) = makeWall(days: [5, 6, 7, 8], store: store, profile: profile, fake: fake, library: library)
        wall.beginBatchExport()
        let batch = try XCTUnwrap(wall.batchExport)

        batch.start()
        await until { fake.heldCount == 1 }
        fake.releaseOne()
        await until { fake.calls.count == 2 && fake.heldCount == 1 }
        batch.stop()
        XCTAssertTrue(batch.isStopping)
        fake.releaseOne()
        await batch.waitForRun()

        XCTAssertEqual(fake.calls, ["p5", "p6"])
        XCTAssertNil(wall.batchExport)
        XCTAssertEqual(wall.toastState?.message, "已匯出 2 張")
        XCTAssertEqual(spoken(), ["已匯出 2 張"])
        XCTAssertFalse(wall.isSelecting)
        XCTAssertTrue(library.deleteCalls.isEmpty)
    }

    /// 7: a stopped run counts only what really saved: the failed one is not in the toast.
    func testStopCountsOnlyRealSaves() async throws {
        let (store, profile) = try makeStore()
        let fake = FakeBatchExport()
        fake.holds = true
        fake.failures = ["p5": .downloadFailed]
        let batch = makeBatch([photo(5), photo(6), photo(7)], store: store, profile: profile, export: fake.asExport)
        let finished = outcomes(of: batch)

        batch.start()
        await until { fake.heldCount == 1 }
        fake.releaseOne()
        await until { fake.calls.count == 2 && fake.heldCount == 1 }
        batch.stop()
        fake.releaseOne()
        await batch.waitForRun()
        XCTAssertEqual(finished(), [.stopped(saved: 1)])
    }

    // MARK: - 8: all saved

    /// 8: every photo saved: toast and VoiceOver "已匯出 N 張", selection ends.
    func testAllSavedToastsAndEndsSelection() async throws {
        let (store, profile) = try makeStore()
        let fake = FakeBatchExport()
        let (wall, spoken) = makeWall(days: [nil, 5, 6, 7], store: store, profile: profile, fake: fake)
        wall.beginBatchExport()
        let batch = try XCTUnwrap(wall.batchExport)

        batch.start()
        await batch.waitForRun()

        XCTAssertNil(wall.batchExport)
        XCTAssertEqual(wall.toastState?.message, "已匯出 3 張")
        XCTAssertEqual(spoken(), ["已匯出 3 張"])
        XCTAssertFalse(wall.isSelecting)
        XCTAssertTrue(wall.selectedIDs.isEmpty)
    }

    // MARK: - 9: some failed

    /// 9: the 2nd and 4th of five fail: "已匯出 3 張，2 張失敗" with the note;
    /// 重試失敗的 reruns just those two; 好 keeps selecting with only the
    /// still-failed ticked; never "已匯出 5 張".
    func testFailuresShowCountsRetryOnlyTheFailedAndKeepThemTicked() async throws {
        let (store, profile) = try makeStore()
        let fake = FakeBatchExport()
        fake.failures = ["p6": .downloadFailed, "p8": .saveFailed(.saveFailed("空間不足"))]
        let (wall, spoken) = makeWall(days: [5, 6, 7, 8, 9], store: store, profile: profile, fake: fake)
        wall.beginBatchExport()
        let batch = try XCTUnwrap(wall.batchExport)

        batch.start()
        await batch.waitForRun()
        XCTAssertEqual(batch.phase, .failed(succeeded: 3, failed: 2))
        XCTAssertEqual(batch.failureTitle, "已匯出 3 張，2 張失敗")
        XCTAssertEqual(batch.failureMessage, "失敗的照片可能還在從 iCloud 下載，或儲存空間不足。")
        XCTAssertNotNil(wall.batchExport, "the sheet stays")
        XCTAssertNil(wall.toastState)

        fake.failures = ["p8": .downloadFailed]
        batch.retryFailed()
        XCTAssertEqual(batch.phase, .running(done: 0, total: 2))
        await batch.waitForRun()
        XCTAssertEqual(fake.calls, ["p5", "p6", "p7", "p8", "p9", "p6", "p8"])
        XCTAssertEqual(batch.failureTitle, "已匯出 4 張，1 張失敗")

        batch.acknowledgeFailures()
        XCTAssertNil(wall.batchExport)
        XCTAssertTrue(wall.isSelecting)
        XCTAssertEqual(wall.selectedIDs, ["p8"])
        XCTAssertNil(wall.toastState)
        XCTAssertTrue(spoken().isEmpty, "no success is announced: \(spoken())")
    }

    /// 9: once the retry saves the rest, it is all saved: the toast counts every saved photo.
    func testRetryThatSavesTheRestCountsEverySavedPhoto() async throws {
        let (store, profile) = try makeStore()
        let fake = FakeBatchExport()
        fake.failures = ["p6": .downloadFailed]
        let (wall, spoken) = makeWall(days: [5, 6, 7], store: store, profile: profile, fake: fake)
        wall.beginBatchExport()
        let batch = try XCTUnwrap(wall.batchExport)

        batch.start()
        await batch.waitForRun()
        XCTAssertEqual(batch.phase, .failed(succeeded: 2, failed: 1))
        fake.failures = [:]
        batch.retryFailed()
        await batch.waitForRun()

        XCTAssertEqual(fake.calls, ["p5", "p6", "p7", "p6"])
        XCTAssertEqual(wall.toastState?.message, "已匯出 3 張")
        XCTAssertEqual(spoken(), ["已匯出 3 張"])
        XCTAssertFalse(wall.isSelecting)
    }

    // MARK: - 10: permission

    /// 10: a permission refusal on the 2nd photo: nothing more is tried,
    /// the rest count as failed, the permission text shows, no success toast.
    func testPermissionRefusalStopsTryingAndShowsThePermissionText() async throws {
        let (store, profile) = try makeStore()
        let fake = FakeBatchExport()
        fake.failures = ["p6": .saveFailed(.permissionDenied)]
        let (wall, spoken) = makeWall(days: [5, 6, 7, 8], store: store, profile: profile, fake: fake)
        wall.beginBatchExport()
        let batch = try XCTUnwrap(wall.batchExport)

        batch.start()
        await batch.waitForRun()

        XCTAssertEqual(fake.calls, ["p5", "p6"])
        XCTAssertEqual(batch.phase, .failed(succeeded: 1, failed: 3))
        XCTAssertTrue(batch.permissionDenied)
        XCTAssertEqual(batch.failureMessage,
                       "新照片沒有存起來。請到「設定」›「DaysCam」›「照片」允許取用後再匯出一次。")
        XCTAssertNil(wall.toastState)
        XCTAssertTrue(spoken().isEmpty)

        batch.acknowledgeFailures()
        XCTAssertEqual(wall.selectedIDs, ["p6", "p7", "p8"])
    }

    // MARK: - 12: first-export comparison

    /// 12: after the batch preview opened, the viewer's first export skips
    /// the comparison and exports at once.
    func testBatchPreviewCountsAsSeeingTheComparison() async throws {
        let (store, profile) = try makeStore()
        let tips = tips()
        XCTAssertFalse(tips.exportIntroSeen)
        _ = makeBatch([photo(5)], store: store, profile: profile, tips: tips, export: FakeBatchExport().asExport)
        XCTAssertTrue(tips.exportIntroSeen)

        let library = ExportLibrary(photos: [photo(5)])
        var saves = 0
        let viewer = PhotoDetailModel(profileID: profile.id, startingAt: "p5", store: store, library: library,
                                      calendar: calendar, resolveFont: { _ in .pingFang },
                                      pipeline: PhotoExportPipeline(library: library, calendar: calendar,
                                                                    bake: { image, _, _, _, _, _, _, _ in image },
                                                                    save: { _, completion in
                                                                        saves += 1
                                                                        completion(.success("new"))
                                                                    }),
                                      tips: tips, scheduleAfter: { _, _ in })
        await viewer.requestExport()
        XCTAssertFalse(viewer.showsExportIntro)
        XCTAssertEqual(saves, 1)
    }
}
