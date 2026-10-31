import Foundation
import UIKit

/// Why one export failed (PRD 2.0 FR-22.2, 0.1 §7.3).
enum PhotoExportError: Error, Equatable {
    /// The photo is gone from the library.
    case photoMissing
    /// The original could not be fetched, e.g. an iCloud download failed.
    case downloadFailed
    /// Baking returned no image.
    case bakeFailed
    /// The new photo could not be saved.
    case saveFailed(PhotoSaveError)

    /// The text of the failure alert.
    var message: String {
        switch self {
        case .photoMissing: return "找不到這張照片，它可能已被刪除。"
        case .downloadFailed: return "無法取得原始照片，請確認網路連線後再試一次。"
        case .bakeFailed: return "照片處理失敗，請再試一次。"
        case .saveFailed(.permissionDenied):
            return "新照片沒有存起來。請到「設定」›「DaysCam」›「照片」允許取用後再匯出一次。"
        case let .saveFailed(error): return error.displayMessage
        }
    }

    /// Whether the alert offers 前往設定.
    var showsSettingsAction: Bool {
        if case let .saveFailed(error) = self { return error.showsSettingsAction }
        return false
    }
}

/// Exports one photo (PRD 2.0 FR-22.1): fetches the original, bakes the
/// record's overlay into it and saves the result as a new photo to 「最近項目」
/// only. The original is never changed, the new photo is not added to an
/// album and no `fallbackAssetIDs` is written. Shared by the viewer's single
/// export and the wall's batch export.
@MainActor
final class PhotoExportPipeline {
    /// `OverlayRenderer.bake`, injectable for tests. Runs off the main thread.
    typealias Bake = PhotoDetailModel.Bake
    /// Saves a baked image to 「最近項目」 only; completes once, on main.
    typealias Save = (UIImage, @escaping (Result<String, PhotoSaveError>) -> Void) -> Void

    private let library: any RecordAlbumLibrary
    private let calendar: Calendar
    private let renderer: TemplateRenderer
    private let bake: Bake
    private let save: Save
    private let bakeQueue = DispatchQueue(label: "dayscam.export-bake", qos: .userInitiated)

    /// - Parameter save: Defaults to `PhotoSaver.saveToRecentsOnly`.
    init(library: any RecordAlbumLibrary,
         calendar: Calendar = .autoupdatingCurrent,
         renderer: TemplateRenderer = TemplateRenderer(),
         bake: @escaping Bake = { image, text, style, placement, font, cropRect, filmDate, tone in
             OverlayRenderer().bake(image: image, text: text, style: style, placement: placement,
                                    font: font, cropRect: cropRect, filmDate: filmDate, tone: tone)
         },
         save: @escaping Save = { image, completion in
             PhotoSaver().saveToRecentsOnly(image, completion: completion)
         }) {
        self.library = library
        self.calendar = calendar
        self.renderer = renderer
        self.bake = bake
        self.save = save
    }

    /// Exports `photo` with the style of `profile`, the text made from the
    /// photo's own `creationDate` (§6.1); a photo without one is never
    /// exported. The font is resolved when the call starts, so what is baked
    /// is what was on screen at the press.
    ///
    /// - Parameter progress: the original's download progress, 0...1.
    func export(photo: RecordPhoto,
                profile: CameraProfile,
                resolveFont: @MainActor (OverlayStyle) -> ResolvedOverlayFont,
                progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> Result<Void, PhotoExportError> {
        guard let date = photo.creationDate else { return .failure(.photoMissing) }
        let text = renderer.render(profile: profile, capturedAt: date, calendar: calendar, moment: .photo)
        let style = profile.style
        let placement = profile.position
        let font = resolveFont(style)
        let filmDate = PhotoDetailModel.filmDateStamp(for: profile, creationDate: date, calendar: calendar)

        let original: UIImage
        do {
            original = try await library.fullImage(id: photo.id, progress: progress)
        } catch RecordAlbumError.notFound {
            return .failure(.photoMissing)
        } catch {
            return .failure(.downloadFailed)
        }

        let bake = self.bake
        let baked: UIImage? = await withCheckedContinuation { continuation in
            bakeQueue.async {
                // A full-resolution bake can take ~100MB; release it here,
                // not whenever the queue's pool drains (as the camera does).
                let result = autoreleasepool {
                    bake(original, text, style, placement, font, nil, filmDate, .standard)
                }
                continuation.resume(returning: result)
            }
        }
        guard let baked else { return .failure(.bakeFailed) }

        let saved: Result<String, PhotoSaveError> = await withCheckedContinuation { continuation in
            save(baked) { continuation.resume(returning: $0) }
        }
        return saved.map { _ in () }.mapError { .saveFailed($0) }
    }
}
