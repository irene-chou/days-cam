import UIKit
import XCTest
@testable import DaysCam

/// #725 acceptance 5–8: the comparison sheet's preview, swapping, export and
/// failures, with injected images, composition and save.
@MainActor
final class ComparisonModelTests: XCTestCase {
    private let calendar = DateFixture.taipei

    /// What the injected `compose` was handed.
    private final class ComposeLog: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [(left: String, right: String, side: CGFloat, leftSize: CGSize, rightSize: CGSize,
                             filmDate: Bool, onMain: Bool)] = []

        func record(_ left: ComparisonRenderer.Tile, _ right: ComparisonRenderer.Tile, side: CGFloat) {
            lock.lock()
            defer { lock.unlock() }
            calls.append((left.text, right.text, side, left.image.size, right.image.size,
                          left.filmDate != nil, Thread.isMainThread))
        }

        var all: [(left: String, right: String, side: CGFloat, leftSize: CGSize, rightSize: CGSize,
                   filmDate: Bool, onMain: Bool)] {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }
    }

    private func photo(_ id: String, _ month: Int, _ day: Int, year: Int = 2026) -> FakeRecordAlbumLibrary.Asset {
        FakeRecordAlbumLibrary.Asset(id: id, creationDate: DateFixture.date(year, month, day, hour: 15))
    }

    private func profile(showFilmDate: Bool = false) -> CameraProfile {
        var profile = CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1))
        profile.showFilmDate = showFilmDate
        return profile
    }

    /// p0 before the start, u undated, p1 … p10 on 2026-01-01 … 01-10.
    private func makeLibrary() -> FakeRecordAlbumLibrary {
        let assets = [photo("p0", 12, 25, year: 2025), FakeRecordAlbumLibrary.Asset(id: "u", creationDate: nil)]
            + (1...10).map { photo("p\($0)", 1, $0) }
        return FakeRecordAlbumLibrary(assets: assets, albums: [.init(id: "album", title: "小寶", assetIDs: assets.map(\.id))])
    }

    private func makeModel(library: FakeRecordAlbumLibrary,
                           profile: CameraProfile? = nil,
                           log: ComposeLog = ComposeLog(),
                           composeResult: Bool = true,
                           save: @escaping PhotoExportPipeline.Save = { _, completion in completion(.success("new")) },
                           openSettings: @escaping (URL) -> Void = { _ in }) -> ComparisonModel {
        let photos = library.photos(albumIdentifier: "album", fallbackIDs: [])
        return ComparisonModel(profile: profile ?? self.profile(), photos: photos, leftID: "p1", rightID: "p10",
                               library: library, calendar: calendar, resolveFont: { _ in .pingFang },
                               compose: { left, right, _, _, _, side in
                                   log.record(left, right, side: side)
                                   return composeResult ? UIImage() : nil
                               },
                               save: save, openSettings: openSettings)
    }

    /// 5: the preview puts the earliest on the left and the latest on the
    /// right, each with its own day count, composed at 540 off the main thread.
    func testPreviewHasEarliestLeftAndLatestRight() async {
        let log = ComposeLog()
        let model = makeModel(library: makeLibrary(), log: log)
        await model.makePreview()
        XCTAssertNotNil(model.previewImage)
        let call = log.all.first
        XCTAssertEqual(call?.left, "第 1 天", "5")
        XCTAssertEqual(call?.right, "第 10 天", "5")
        XCTAssertEqual(call?.side, 540)
        XCTAssertEqual(call?.leftSize, CGSize(width: 1080, height: 1080), "screen-size source")
        XCTAssertEqual(call?.onMain, false, "composed off the main thread")
        XCTAssertEqual(call?.filmDate, false, "film date only when the record shows it")
        XCTAssertEqual(model.tileAccessibilityLabel(.left), "左邊照片，第 1 天，點兩下換照片")
        XCTAssertEqual(model.tileAccessibilityLabel(.right), "右邊照片，第 10 天，點兩下換照片")
    }

    /// 5: a record that prints its film date passes it to each tile.
    func testFilmDateFollowsTheRecord() async {
        let log = ComposeLog()
        let model = makeModel(library: makeLibrary(), profile: profile(showFilmDate: true), log: log)
        await model.makePreview()
        XCTAssertEqual(log.all.first?.filmDate, true)
    }

    /// 6: the picker lists dated photos from the start date on; choosing one
    /// swaps that half and the next preview uses it.
    func testChoosingAnotherPhotoUpdatesThePreview() async {
        let log = ComposeLog()
        let model = makeModel(library: makeLibrary(), log: log)
        XCTAssertEqual(model.choices.map(\.id), (1...10).map { "p\($0)" }, "6 no undated, none before the start")
        XCTAssertEqual(model.pickerSections.flatMap(\.cells).count, 10)
        let key = model.previewKey
        model.choose("p4", for: .left)
        XCTAssertEqual(model.leftID, "p4", "6")
        XCTAssertNotEqual(model.previewKey, key, "the view remakes the preview")
        await model.makePreview()
        XCTAssertEqual(log.all.last?.left, "第 4 天", "6")
        XCTAssertEqual(log.all.last?.right, "第 10 天")

        model.choose("p0", for: .right)
        model.choose("u", for: .right)
        XCTAssertEqual(model.rightID, "p10", "not offered")
    }

    /// 7: 匯出 composes at 1080 from the originals, saves once and finishes.
    func testExportSavesOnceAndFinishes() async {
        let log = ComposeLog()
        var saved = 0
        let model = makeModel(library: makeLibrary(), log: log, save: { _, completion in
            saved += 1
            completion(.success("new"))
        })
        var outcomes: [ComparisonModel.Outcome] = []
        model.onFinish = { outcomes.append($0) }
        await model.export()
        XCTAssertEqual(saved, 1, "7")
        XCTAssertEqual(outcomes, [.exported], "7")
        XCTAssertEqual(log.all.last?.side, 1080)
        XCTAssertEqual(log.all.last?.left, "第 1 天")
        XCTAssertEqual(log.all.last?.right, "第 10 天")
        XCTAssertEqual(log.all.last?.onMain, false)
        XCTAssertNil(model.exportError)
        XCTAssertFalse(model.isExporting)
    }

    /// 7: a refused save shows the permission text with 前往設定, keeps the
    /// sheet and never finishes as exported.
    func testPermissionFailureUsesTheExportText() async {
        var opened: [URL] = []
        let model = makeModel(library: makeLibrary(),
                              save: { _, completion in completion(.failure(.permissionDenied)) },
                              openSettings: { opened.append($0) })
        var outcomes: [ComparisonModel.Outcome] = []
        model.onFinish = { outcomes.append($0) }
        await model.export()
        XCTAssertEqual(model.exportError, .saveFailed(.permissionDenied), "7")
        XCTAssertEqual(model.exportError?.message,
                       "新照片沒有存起來。請到「設定」›「DaysCam」›「照片」允許取用後再匯出一次。", "7")
        XCTAssertEqual(model.exportError?.showsSettingsAction, true)
        XCTAssertTrue(outcomes.isEmpty, "7 no toast")
        model.openPhotoSettings()
        XCTAssertEqual(opened.count, 1)
    }

    /// 7: a missing original, a failed download and a failed composition
    /// are failures too, and nothing is saved.
    func testOtherFailuresAreNotReportedAsSuccess() async {
        var saved = 0
        let save: PhotoExportPipeline.Save = { _, completion in
            saved += 1
            completion(.success("new"))
        }
        let missing = makeLibrary()
        missing.failure = .notFound
        let first = makeModel(library: missing, save: save)
        await first.export()
        XCTAssertEqual(first.exportError, .photoMissing)

        let offline = makeLibrary()
        offline.failure = .failed("offline")
        let second = makeModel(library: offline, save: save)
        await second.export()
        XCTAssertEqual(second.exportError, .downloadFailed)

        let third = makeModel(library: makeLibrary(), composeResult: false, save: save)
        var outcomes: [ComparisonModel.Outcome] = []
        third.onFinish = { outcomes.append($0) }
        await third.export()
        XCTAssertEqual(third.exportError, .bakeFailed)
        XCTAssertEqual(saved, 0)
        XCTAssertTrue(outcomes.isEmpty)
    }

    /// 8: while exporting the sheet cannot be dismissed or cancelled and
    /// the halves cannot be swapped; a second 匯出 does nothing.
    func testExportingLocksTheSheet() async {
        var pending: ((Result<String, PhotoSaveError>) -> Void)?
        var saves = 0
        let model = makeModel(library: makeLibrary(), save: { _, completion in
            saves += 1
            pending = completion
        })
        var outcomes: [ComparisonModel.Outcome] = []
        model.onFinish = { outcomes.append($0) }
        XCTAssertTrue(model.canDismiss)

        let export = Task { await model.export() }
        while pending == nil { await Task.yield() }
        XCTAssertTrue(model.isExporting, "8")
        XCTAssertFalse(model.canDismiss, "8 cannot be swiped away")
        model.cancel()
        XCTAssertTrue(outcomes.isEmpty, "8 取消 ignored")
        model.choose("p3", for: .left)
        XCTAssertEqual(model.leftID, "p1")
        await model.export()
        XCTAssertEqual(saves, 1, "8 one save")

        pending?(.success("new"))
        await export.value
        XCTAssertEqual(outcomes, [.exported])
        XCTAssertTrue(model.canDismiss)
    }

    /// 8: the new photo goes to 「最近項目」 only: no album gains it and the
    /// record's `fallbackAssetIDs` is untouched.
    func testExportWritesNoAlbumAndNoFallbackIDs() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ComparisonModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "ComparisonModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProfileStore(directory: directory, calendar: calendar, defaults: defaults,
                                 scheduler: ProfileStore.immediateScheduler)
        store.load()
        var record = profile()
        record.albumIdentifier = "album"
        record.fallbackAssetIDs = ["p2"]
        record = try store.add(record)
        let library = makeLibrary()
        let albumsBefore = library.albums
        let wall = PhotoWallModel(profileID: record.id, store: store, library: library, calendar: calendar,
                                  todayText: { _ in "" }, defaults: defaults, scheduleAfter: { _, _ in })
        wall.announce = { _ in }
        wall.openComparison(resolveFont: { _ in .pingFang }, compose: { _, _, _, _, _, _ in UIImage() },
                            save: { _, completion in completion(.success("new")) })
        await wall.comparisonSheet?.export()
        XCTAssertEqual(wall.toastState?.message, "已匯出")
        XCTAssertEqual(library.albums, albumsBefore, "8 no album write")
        XCTAssertEqual(store.profiles.first { $0.id == record.id }?.fallbackAssetIDs, ["p2"], "8")
    }
}
