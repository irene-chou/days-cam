import Combine
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
        profile.showOverlay = true
        return profile
    }

    /// p0 before the start, u undated, p1 … p10 on 2026-01-01 … 01-10.
    private func makeLibrary(aspect: CGFloat? = nil) -> FakeRecordAlbumLibrary {
        let assets = [photo("p0", 12, 25, year: 2025), FakeRecordAlbumLibrary.Asset(id: "u", creationDate: nil)]
            + (1...10).map { id -> FakeRecordAlbumLibrary.Asset in
                var asset = photo("p\(id)", 1, id)
                asset.aspectRatio = aspect
                return asset
            }
        return FakeRecordAlbumLibrary(assets: assets, albums: [.init(id: "album", title: "小寶", assetIDs: assets.map(\.id))])
    }

    private func makeModel(library: FakeRecordAlbumLibrary,
                           profile: CameraProfile? = nil,
                           log: ComposeLog = ComposeLog(),
                           profileChanges: AnyPublisher<CameraProfile?, Never> = Empty().eraseToAnyPublisher(),
                           composeResult: Bool = true,
                           save: @escaping PhotoExportPipeline.Save = { _, completion in completion(.success("new")) },
                           openSettings: @escaping (URL) -> Void = { _ in }) -> ComparisonModel {
        let photos = library.photos(albumIdentifier: "album", fallbackIDs: [])
        return ComparisonModel(profile: profile ?? self.profile(), photos: photos, leftID: "p1", rightID: "p10",
                               library: library, calendar: calendar, profileChanges: profileChanges,
                               resolveFont: { _ in .pingFang },
                               compose: { left, right, _, _, _, side in
                                   log.record(left, right, side: side)
                                   return composeResult ? UIImage() : nil
                               },
                               save: save, openSettings: openSettings)
    }

    /// 5: the preview puts the earliest on the left and the latest on the
    /// right, each with its own day count, composed within 1080 off the main thread.
    /// Each tile prints what the viewer and the export print: with the
    /// name and date ticked, both appear next to the day count.
    func testTilesPrintTheRecordsOverlayText() async {
        var profile = profile()
        profile.showName = true
        profile.showDate = true
        let log = ComposeLog()
        let model = makeModel(library: makeLibrary(), profile: profile, log: log)
        await model.makePreview()
        guard let capturedAt = DateFixture.date(2026, 1, 1, hour: 15) else { return XCTFail("fixture date") }
        let expected = TemplateRenderer().overlayText(profile: profile, capturedAt: capturedAt,
                                                      calendar: calendar, moment: .photo)
        XCTAssertEqual(log.all.first?.left, expected)
        XCTAssertTrue(expected.contains("小寶") && expected.contains("第 1 天"), expected)
    }

    /// 疊字 off for the record: the tiles print nothing.
    func testTilesPrintNothingWithTheOverlayOff() async {
        var profile = profile()
        profile.showOverlay = false
        let log = ComposeLog()
        let model = makeModel(library: makeLibrary(), profile: profile, log: log)
        await model.makePreview()
        XCTAssertEqual(log.all.first?.left, "")
    }

    func testPreviewHasEarliestLeftAndLatestRight() async {
        let log = ComposeLog()
        let model = makeModel(library: makeLibrary(), log: log)
        await model.makePreview()
        XCTAssertNotNil(model.previewImage)
        let call = log.all.first
        XCTAssertEqual(call?.left, "第 1 天", "5")
        XCTAssertEqual(call?.right, "第 10 天", "5")
        XCTAssertEqual(call?.side, 1080)
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

    /// #740-8: 隱藏文字 prints no day count on either tile; a record with 疊字
    /// off already reads as hidden and the sheet cannot switch it.
    func testHidingTextBlanksBothTiles() async {
        let log = ComposeLog()
        let model = makeModel(library: makeLibrary(), log: log)
        let key = model.previewKey
        model.toggleHidesText()
        XCTAssertTrue(model.hidesText, "8")
        XCTAssertNotEqual(model.previewKey, key, "8 the preview is remade")
        await model.makePreview()
        XCTAssertEqual(log.all.last?.left, "", "8")
        XCTAssertEqual(log.all.last?.right, "", "8")
        model.toggleHidesText()
        XCTAssertFalse(model.hidesText)

        var off = profile()
        off.showOverlay = false
        let hidden = makeModel(library: makeLibrary(), profile: off)
        XCTAssertTrue(hidden.hidesText)
        XCTAssertTrue(hidden.recordHidesText)
        hidden.toggleHidesText()
        XCTAssertFalse(hidden.hidesTextChoice, "8 the record's setting is not the sheet's to change")
    }

    /// #740-9: a record change from the style page redraws the preview.
    func testProfileChangeRemakesThePreview() async {
        let log = ComposeLog()
        let changes = PassthroughSubject<CameraProfile?, Never>()
        let model = makeModel(library: makeLibrary(), log: log, profileChanges: changes.eraseToAnyPublisher())
        let key = model.previewKey
        var changed = profile()
        changed.showFilmDate = true
        changes.send(changed)
        XCTAssertEqual(model.profile, changed, "9")
        XCTAssertNotEqual(model.previewKey, key, "9")
        await model.makePreview()
        XCTAssertEqual(log.all.last?.filmDate, true, "9 the new style is used")
        changes.send(nil)
        XCTAssertEqual(model.profile, changed, "9 a vanished record keeps the last one")
    }

    /// #740-10: two landscape photos stack, and the halves are called 上面／下面.
    func testLandscapePairIsStacked() async {
        let model = makeModel(library: makeLibrary(aspect: 4.0 / 3))
        XCTAssertEqual(model.arrangement, .sideBySide, "before the preview is made")
        await model.makePreview()
        XCTAssertEqual(model.arrangement, .stacked, "10")
        XCTAssertEqual(model.tileAccessibilityLabel(.left), "上面照片，第 1 天，點兩下換照片", "10")
        XCTAssertEqual(model.tileAccessibilityLabel(.right), "下面照片，第 10 天，點兩下換照片", "10")
        XCTAssertEqual(model.name(of: .left), "上面")
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

    /// 7: 匯出 composes within 2160 from the originals, saves once and finishes.
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
        XCTAssertEqual(log.all.last?.side, 2160)
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
