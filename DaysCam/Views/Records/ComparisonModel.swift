import Foundation
import UIKit

/// Drives the comparison sheet (#725): the two photos side by side, each with
/// its own day count, a preview made off the main thread, swapping either
/// photo for another on the wall, and 匯出 as one new photo to 「最近項目」.
///
/// The swapped pair lives only here; closing the sheet goes back to the
/// card's default pair. Nothing is added to an album and `fallbackAssetIDs`
/// is never written (FR-22.1).
@MainActor
final class ComparisonModel: ObservableObject, Identifiable {
    /// `ComparisonRenderer.compose`, injectable for tests. Runs off the main thread.
    typealias Compose = @Sendable (ComparisonRenderer.Tile, ComparisonRenderer.Tile, OverlayStyle,
                                   OverlayPlacement, ResolvedOverlayFont, CGFloat) -> UIImage?

    /// The real composition.
    static let renderCompose: Compose = { left, right, style, placement, font, side in
        ComparisonRenderer().compose(left: left, right: right, style: style, placement: placement,
                                     font: font, tileSide: side)
    }

    /// Which half of the comparison.
    enum Side: String, Identifiable {
        case left
        case right

        var id: String { rawValue }
    }

    /// How the sheet ended.
    enum Outcome: Equatable {
        case cancelled
        case exported
    }

    /// Pixel side of each preview tile.
    static let previewTileSide: CGFloat = 540
    /// Pixel side of each exported tile.
    static let exportTileSide: CGFloat = 1080
    /// Long side asked of the library for a preview photo.
    static let previewSourceSide: CGFloat = 1080

    let id = UUID()
    let profile: CameraProfile
    /// The left photo, earliest by default.
    @Published private(set) var leftID: String
    /// The right photo, latest by default.
    @Published private(set) var rightID: String
    /// The composed preview; `nil` while it is being made or if it failed.
    @Published private(set) var previewImage: UIImage?
    /// 匯出 is running: both buttons are off and the sheet cannot be swiped away.
    @Published private(set) var isExporting = false
    /// The export failed; the sheet shows it as an alert and stays up.
    @Published var exportError: PhotoExportError?

    /// Called once when the sheet should close.
    var onFinish: (Outcome) -> Void = { _ in }

    private let photos: [RecordPhoto]
    private let library: any RecordAlbumLibrary
    private let calendar: Calendar
    private let resolveFont: @MainActor (OverlayStyle) -> ResolvedOverlayFont
    private let compose: Compose
    private let save: PhotoExportPipeline.Save
    private let openSettings: (URL) -> Void
    private let composeQueue = DispatchQueue(label: "dayscam.comparison-compose", qos: .userInitiated)

    /// - Parameters:
    ///   - photos: the wall's photos, oldest first; the picker lists the
    ///     dated ones from the start date on.
    ///   - leftID: the card's earliest photo.
    ///   - rightID: the card's latest photo.
    init(profile: CameraProfile,
         photos: [RecordPhoto],
         leftID: String,
         rightID: String,
         library: any RecordAlbumLibrary,
         calendar: Calendar,
         resolveFont: @escaping @MainActor (OverlayStyle) -> ResolvedOverlayFont,
         compose: @escaping Compose = ComparisonModel.renderCompose,
         save: @escaping PhotoExportPipeline.Save,
         openSettings: @escaping (URL) -> Void = { UIApplication.shared.open($0) }) {
        self.profile = profile
        self.photos = photos
        self.leftID = leftID
        self.rightID = rightID
        self.library = library
        self.calendar = calendar
        self.resolveFont = resolveFont
        self.compose = compose
        self.save = save
        self.openSettings = openSettings
    }

    // MARK: - Photos and texts

    /// The photos the picker offers: dated and not before the start date, oldest first.
    var choices: [RecordPhoto] {
        photos.filter { photo in
            guard let date = photo.creationDate else { return false }
            return DayCountCalculator(calendar: calendar, now: { date }).rawDayDifference(from: profile.startDate) >= 0
        }
    }

    /// The picker's grid, by month like the wall.
    var pickerSections: [PhotoWallModel.Section] {
        PhotoWallModel.sections(for: choices, profile: profile, calendar: calendar)
    }

    /// The photo on `side`.
    func photoID(on side: Side) -> String {
        side == .left ? leftID : rightID
    }

    /// The day count printed on `side`: the record's full unit text (#722).
    func dayText(on side: Side) -> String {
        dayText(for: photoID(on: side))
    }

    /// "左邊照片，<天數>，點兩下換照片".
    func tileAccessibilityLabel(_ side: Side) -> String {
        "\(side == .left ? "左邊" : "右邊")照片，\(dayText(on: side))，點兩下換照片"
    }

    /// Puts `photoID` on `side`; the preview is then made again.
    func choose(_ photoID: String, for side: Side) {
        guard !isExporting, choices.contains(where: { $0.id == photoID }) else { return }
        switch side {
        case .left: leftID = photoID
        case .right: rightID = photoID
        }
    }

    private func dayText(for photoID: String) -> String {
        let date = photos.first { $0.id == photoID }?.creationDate
        return PhotoWallModel.dayMarkTexts(creationDate: date, profile: profile, calendar: calendar).texts[0]
    }

    private func tile(_ image: UIImage, photoID: String) -> ComparisonRenderer.Tile {
        let date = photos.first { $0.id == photoID }?.creationDate
        let filmDate = date.flatMap { PhotoDetailModel.filmDateStamp(for: profile, creationDate: $0, calendar: calendar) }
        return ComparisonRenderer.Tile(image: image, text: dayText(for: photoID), filmDate: filmDate)
    }

    // MARK: - Preview

    /// Identifies what the preview shows, for the view's `.task(id:)`.
    var previewKey: String { "\(leftID)|\(rightID)" }

    /// Loads both photos at screen size and composes them at 540pt tiles off
    /// the main thread. A result for a pair no longer chosen is dropped.
    func makePreview() async {
        let key = previewKey
        let (leftID, rightID) = (self.leftID, self.rightID)
        previewImage = nil
        let target = CGSize(width: Self.previewSourceSide, height: Self.previewSourceSide)
        guard let leftImage = await library.displayImage(id: leftID, targetSize: target),
              let rightImage = await library.displayImage(id: rightID, targetSize: target),
              key == previewKey else { return }
        let image = await composeOffMain(left: tile(leftImage, photoID: leftID),
                                         right: tile(rightImage, photoID: rightID),
                                         side: Self.previewTileSide)
        guard key == previewKey, !Task.isCancelled else { return }
        previewImage = image
    }

    // MARK: - Export

    /// The sheet may be swiped away or cancelled: not while exporting.
    var canDismiss: Bool { !isExporting }

    /// 取消, or the sheet swiped away. Ignored while exporting.
    func cancel() {
        guard canDismiss else { return }
        onFinish(.cancelled)
    }

    /// 匯出: fetches both originals one after the other, composes them at
    /// 1080 off the main thread and saves one new photo to 「最近項目」. Success
    /// closes the sheet; a failure keeps it up with `exportError`.
    func export() async {
        guard !isExporting else { return }
        isExporting = true
        let result = await runExport()
        isExporting = false
        switch result {
        case .success: onFinish(.exported)
        case let .failure(error): exportError = error
        }
    }

    private func runExport() async -> Result<Void, PhotoExportError> {
        let (leftID, rightID) = (self.leftID, self.rightID)
        let left: UIImage
        let right: UIImage
        do {
            left = try await library.fullImage(id: leftID, progress: { _ in })
            right = try await library.fullImage(id: rightID, progress: { _ in })
        } catch RecordAlbumError.notFound {
            return .failure(.photoMissing)
        } catch {
            return .failure(.downloadFailed)
        }
        guard let image = await composeOffMain(left: tile(left, photoID: leftID),
                                               right: tile(right, photoID: rightID),
                                               side: Self.exportTileSide) else {
            return .failure(.bakeFailed)
        }
        let saved: Result<String, PhotoSaveError> = await withCheckedContinuation { continuation in
            save(image) { continuation.resume(returning: $0) }
        }
        return saved.map { _ in () }.mapError { .saveFailed($0) }
    }

    /// The alert's 前往設定, offered only for a permission failure.
    func openPhotoSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openSettings(url)
    }

    private func composeOffMain(left: ComparisonRenderer.Tile, right: ComparisonRenderer.Tile,
                                side: CGFloat) async -> UIImage? {
        let style = profile.style
        let placement = profile.position
        let font = resolveFont(style)
        let compose = self.compose
        return await withCheckedContinuation { continuation in
            composeQueue.async {
                let image = autoreleasepool { compose(left, right, style, placement, font, side) }
                continuation.resume(returning: image)
            }
        }
    }
}
