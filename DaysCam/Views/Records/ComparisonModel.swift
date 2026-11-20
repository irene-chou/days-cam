import Combine
import Foundation
import UIKit

/// Drives the comparison sheet (#725, #740): the two photos side by side or
/// stacked (`ComparisonLayout`), each with its own day count, a preview made off the main thread, swapping either
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
                                     font: font, maxSide: side)
    }

    /// Which half of the comparison: the left or top photo is `left`, the
    /// right or bottom one `right`.
    enum Side: String, Identifiable {
        case left
        case right

        var id: String { rawValue }
    }

    /// What the preview shows, for the view's `.task(id:)`.
    struct PreviewKey: Equatable {
        let leftID: String
        let rightID: String
        let profile: CameraProfile
        let hidesText: Bool
    }

    /// How the sheet ended.
    enum Outcome: Equatable {
        case cancelled
        case exported
    }

    /// Longest side of the preview's row or column, in pixels.
    static let previewMaxSide: CGFloat = 1080
    /// Longest side of the exported row or column, in pixels.
    static let exportMaxSide: CGFloat = ComparisonLayout.exportMaxSide
    /// Long side asked of the library for a preview photo.
    static let previewSourceSide: CGFloat = 1080

    let id = UUID()
    /// The record as the store has it now; the preview follows it.
    @Published private(set) var profile: CameraProfile
    /// The left photo, earliest by default.
    @Published private(set) var leftID: String
    /// The right photo, latest by default.
    @Published private(set) var rightID: String
    /// The composed preview; `nil` while it is being made or if it failed.
    @Published private(set) var previewImage: UIImage?
    /// How the two photos sit in the preview; side by side until it is made.
    @Published private(set) var arrangement: ComparisonLayout.Arrangement = .sideBySide
    /// 隱藏文字 was chosen on this sheet: neither tile prints the day count.
    @Published private(set) var hidesTextChoice = false
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
    private var subscription: AnyCancellable?
    private let composeQueue = DispatchQueue(label: "dayscam.comparison-compose", qos: .userInitiated)

    /// - Parameters:
    ///   - photos: the wall's photos, oldest first; the picker lists the
    ///     dated ones from the start date on.
    ///   - profileChanges: the record as the store has it, each time it changes.
    ///   - leftID: the card's earliest photo.
    ///   - rightID: the card's latest photo.
    init(profile: CameraProfile,
         photos: [RecordPhoto],
         leftID: String,
         rightID: String,
         library: any RecordAlbumLibrary,
         calendar: Calendar,
         profileChanges: AnyPublisher<CameraProfile?, Never> = Empty().eraseToAnyPublisher(),
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
        subscription = profileChanges.sink { [weak self] changed in
            guard let self, let changed else { return }
            self.profile = changed
        }
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

    /// The left (top) photo, the one the style page previews.
    var leftPhoto: RecordPhoto? { photos.first { $0.id == leftID } }

    /// The text is hidden, by the sheet or by the record (#718).
    var hidesText: Bool { hidesTextChoice || profile.showOverlay == false }

    /// The record's 疊字 is off: it reads as hidden and cannot be switched here.
    var recordHidesText: Bool { profile.showOverlay == false }

    /// 隱藏文字／顯示文字; the record's own setting stays as it is.
    func toggleHidesText() {
        guard !isExporting, !recordHidesText else { return }
        hidesTextChoice.toggle()
    }

    /// The day count printed on `side`: the record's full unit text (#722).
    func dayText(on side: Side) -> String {
        dayText(for: photoID(on: side))
    }

    /// "左邊照片，<天數>，點兩下換照片"; 上面／下面 when stacked.
    func tileAccessibilityLabel(_ side: Side) -> String {
        "\(name(of: side))照片，\(dayText(on: side))，點兩下換照片"
    }

    /// 左邊／右邊, or 上面／下面 while the photos are stacked.
    func name(of side: Side) -> String {
        switch (arrangement, side) {
        case (.sideBySide, .left): return "左邊"
        case (.sideBySide, .right): return "右邊"
        case (.stacked, .left): return "上面"
        case (.stacked, .right): return "下面"
        }
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
        return ComparisonRenderer.Tile(image: image, text: hidesText ? "" : dayText(for: photoID), filmDate: filmDate)
    }

    // MARK: - Preview

    /// Identifies what the preview shows, for the view's `.task(id:)`.
    var previewKey: PreviewKey {
        PreviewKey(leftID: leftID, rightID: rightID, profile: profile, hidesText: hidesText)
    }

    /// Loads both photos at screen size and composes them within 1080px off
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
                                         side: Self.previewMaxSide)
        guard key == previewKey, !Task.isCancelled else { return }
        arrangement = ComparisonLayout.plan(first: Self.pixelSize(leftImage), second: Self.pixelSize(rightImage)).arrangement
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

    private static func pixelSize(_ image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    /// 匯出: fetches both originals one after the other, composes them within
    /// 2160px off the main thread and saves one new photo to 「最近項目」. Success
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
                                               side: Self.exportMaxSide) else {
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
