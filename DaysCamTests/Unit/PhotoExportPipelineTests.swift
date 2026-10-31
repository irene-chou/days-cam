import Photos
import UIKit
import XCTest
@testable import DaysCam

/// #647 acceptance 4 and 5: what the pipeline bakes, where it saves, and how
/// it fails.
@MainActor
final class PhotoExportPipelineTests: XCTestCase {
    private let calendar = DateFixture.taipei

    private func profile(showFilmDate: Bool = false, fallback: [String] = []) -> CameraProfile {
        var profile = CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1),
                                    albumIdentifier: "album", fallbackAssetIDs: fallback)
        profile.showFilmDate = showFilmDate
        return profile
    }

    private func photo(day: Int? = 10) -> RecordPhoto {
        RecordPhoto(id: "p1", creationDate: day.flatMap { DateFixture.date(2026, 1, $0, hour: 15, minute: 7) })
    }

    private func pipeline(library: ExportLibrary,
                          recorder: ExportBakeRecorder = ExportBakeRecorder(),
                          save: @escaping PhotoExportPipeline.Save = { _, completion in completion(.success("new")) })
        -> PhotoExportPipeline {
        PhotoExportPipeline(library: library, calendar: calendar,
                            bake: { recorder.bake($0, $1, $2, $3, $4, $5, $6, $7) }, save: save)
    }

    /// The failure, `nil` on success.
    private func run(_ pipeline: PhotoExportPipeline, photo: RecordPhoto, profile: CameraProfile) async
        -> PhotoExportError? {
        let result = await pipeline.export(photo: photo, profile: profile, resolveFont: { _ in .pingFang })
        if case let .failure(error) = result { return error }
        return nil
    }

    /// 4: `bake` gets the original, the photo-moment text of `creationDate`,
    /// no crop, the standard tone and the film date of the photo's own day.
    func testBakesThePhotoMomentTextWithStandardToneAndNoCrop() async throws {
        let profile = profile(showFilmDate: true)
        let photo = photo(day: 10)
        let recorder = ExportBakeRecorder()
        let result = await run(pipeline(library: ExportLibrary(photos: [photo]), recorder: recorder),
                               photo: photo, profile: profile)

        XCTAssertNil(result)
        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertEqual(recorder.calls.count, 1)
        let expected = TemplateRenderer().render(profile: profile, capturedAt: try XCTUnwrap(photo.creationDate),
                                                 calendar: calendar, moment: .photo)
        XCTAssertEqual(call.text, expected)
        XCTAssertTrue(call.text.contains("第 10 天"), call.text)
        XCTAssertNil(call.cropRect)
        XCTAssertEqual(call.tone, .standard)
        XCTAssertNotNil(call.filmDate)
        XCTAssertEqual(call.filmDate, PhotoDetailModel.filmDateStamp(
            for: profile, creationDate: try XCTUnwrap(photo.creationDate), calendar: calendar))
        XCTAssertEqual(call.imageSize, CGSize(width: 300, height: 400), "the full original, not the display image")
    }

    /// 4: saved to 「最近項目」 only: one plain write, no album write, nothing
    /// added to the record's album, and the record's `fallbackAssetIDs` is
    /// not touched.
    func testSavesToRecentsOnlyAndWritesNoFallbackID() async throws {
        let photo = photo()
        let library = ExportLibrary(photos: [photo])
        let stub = RecentsOnlyStubLibrary()
        let saver = PhotoSaver(library: stub)
        let record = profile(fallback: ["p1"])
        let result = await run(pipeline(library: library,
                                        save: { image, completion in saver.saveToRecentsOnly(image, completion: completion) }),
                               photo: photo, profile: record)

        XCTAssertNil(result)
        XCTAssertEqual(stub.writes, 1)
        XCTAssertEqual(stub.albumWrites, 0)
        XCTAssertEqual(library.addAssetsCount, 0)
        XCTAssertEqual(record.fallbackAssetIDs, ["p1"])
    }

    /// 5: a failed save is a failure with the saver's text.
    func testSaveFailureIsReported() async throws {
        let photo = photo()
        let stub = RecentsOnlyStubLibrary()
        stub.writeSucceeds = false
        let saver = PhotoSaver(library: stub)
        let result = await run(pipeline(library: ExportLibrary(photos: [photo]),
                                        save: { image, completion in saver.saveToRecentsOnly(image, completion: completion) }),
                               photo: photo, profile: profile())

        let error = try XCTUnwrap(result, "a failed save is not a success")
        XCTAssertTrue(error.message.contains("儲存失敗"), error.message)
        XCTAssertFalse(error.showsSettingsAction)
    }

    /// 5: a refused permission has the export-only wording and offers 前往設定.
    func testPermissionDeniedHasTheExportWording() async throws {
        let photo = photo()
        let result = await run(pipeline(library: ExportLibrary(photos: [photo]),
                                        save: { _, completion in completion(.failure(.permissionDenied)) }),
                               photo: photo, profile: profile())

        let error = try XCTUnwrap(result, "a refused save is not a success")
        XCTAssertEqual(error.message, "新照片沒有存起來。請到「設定」›「DaysCam」›「照片」允許取用後再匯出一次。")
        XCTAssertTrue(error.showsSettingsAction)
    }

    /// An original that fails to download is reported; nothing is baked or saved.
    func testDownloadFailureBakesAndSavesNothing() async throws {
        let photo = photo()
        let library = ExportLibrary(photos: [photo])
        library.fullImageError = NSError(domain: "icloud", code: 1)
        let recorder = ExportBakeRecorder()
        var saves = 0
        let result = await run(pipeline(library: library, recorder: recorder,
                                        save: { _, completion in saves += 1; completion(.success("x")) }),
                               photo: photo, profile: profile())

        XCTAssertEqual(result, PhotoExportError.downloadFailed)
        XCTAssertTrue(recorder.calls.isEmpty)
        XCTAssertEqual(saves, 0)
    }

    /// A photo gone from the library says so.
    func testMissingPhotoIsReported() async throws {
        let photo = photo()
        let library = ExportLibrary(photos: [photo])
        library.fullImageError = RecordAlbumError.notFound
        let result = await run(pipeline(library: library), photo: photo, profile: profile())
        XCTAssertEqual(result, PhotoExportError.photoMissing)
    }

    /// A bake that returns nothing saves nothing.
    func testBakeFailureSavesNothing() async throws {
        let photo = photo()
        let recorder = ExportBakeRecorder()
        recorder.succeeds = false
        var saves = 0
        let result = await run(pipeline(library: ExportLibrary(photos: [photo]), recorder: recorder,
                                        save: { _, completion in saves += 1; completion(.success("x")) }),
                               photo: photo, profile: profile())

        XCTAssertEqual(result, PhotoExportError.bakeFailed)
        XCTAssertEqual(saves, 0)
    }

    /// No `creationDate`, no export: the original is never even fetched.
    func testPhotoWithoutDateIsNotExported() async throws {
        let undated = photo(day: nil)
        let library = ExportLibrary(photos: [undated])
        let result = await run(pipeline(library: library), photo: undated, profile: profile())
        XCTAssertNotNil(result)
        XCTAssertEqual(library.fullImageCount, 0)
    }
}
