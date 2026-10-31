import Combine
import Foundation
import UIKit

/// Drives the batch export sheet of the photo wall (PRD 2.0 FR-22.4–22.10,
/// D8 「批次匯出」).
///
/// Opens on a preview of what will be saved; on 匯出 M 張 the photos go
/// through `PhotoExportPipeline` one at a time, each awaited before the next
/// starts, so only one original is held at once. A photo without a
/// `creationDate` is skipped, never exported and never counted as a failure.
/// Nothing here asks for permission, adds to an album or writes
/// `fallbackAssetIDs`; that is the pipeline's to keep (FR-22.1).
@MainActor
final class BatchExportModel: ObservableObject, Identifiable {
    /// Exports one photo with the record's style; `PhotoExportPipeline.export`
    /// in the app. `progress` reports the original's download, 0...1.
    typealias Export = @MainActor (RecordPhoto, CameraProfile, @escaping @Sendable (Double) -> Void) async
        -> Result<Void, PhotoExportError>

    /// What the sheet shows.
    enum Phase: Equatable {
        /// 匯出 M 張新照片 with the carousel (FR-22.5).
        case preview
        /// 匯出中: `done` of `total` finished, saved or failed (FR-22.7).
        case running(done: Int, total: Int)
        /// Some failed: 已匯出 S 張，F 張失敗 (FR-22.9).
        case failed(succeeded: Int, failed: Int)
    }

    /// How the sheet ended, for the wall to act on.
    enum Outcome: Equatable {
        /// 取消 on the preview: back to the selection as it was.
        case cancelled
        /// Every exportable photo was saved (FR-22.8).
        case allSaved(count: Int)
        /// 停止: `saved` photos were really saved (FR-22.7).
        case stopped(saved: Int)
        /// 好 on the failure sheet: keep selecting with only `failedIDs` ticked.
        case keptFailures(failedIDs: [String])
    }

    let id = UUID()
    /// The ticked photos that will be exported, in wall order.
    let exportable: [RecordPhoto]
    /// How many ticked photos are 日期不明 and skipped (FR-22.6).
    let skippedCount: Int
    let profileID: UUID

    @Published private(set) var phase: Phase = .preview
    /// The carousel's photo, an index into `exportable`.
    @Published private(set) var previewIndex = 0
    /// The record as the store has it now; the preview follows it (FR-22.5).
    @Published private(set) var profile: CameraProfile?
    /// The current photo's download progress, 0...1, while running.
    @Published private(set) var currentProgress: Double = 0
    /// 停止 was pressed; the photo in progress finishes, no more start.
    @Published private(set) var isStopping = false
    /// The last run hit a 「照片」 permission refusal.
    @Published private(set) var permissionDenied = false

    /// Called once when the sheet ends.
    var onFinish: (Outcome) -> Void = { _ in }

    /// Ids of the exportable photos saved so far, across retries.
    private(set) var savedIDs: Set<String> = []
    /// Ids of the photos that failed in the last run.
    private(set) var failedIDs: [String] = []

    private let store: ProfileStore
    private let library: any RecordAlbumLibrary
    private let calendar: Calendar
    private let renderer: TemplateRenderer
    private let bake: PhotoDetailModel.Bake
    private let resolveFont: @MainActor (OverlayStyle) -> ResolvedOverlayFont
    private let exportPhoto: Export
    private var runTask: Task<Void, Never>?
    private var subscription: AnyCancellable?

    /// - Parameters:
    ///   - photos: The ticked photos in wall order, 日期不明 ones included.
    ///   - bake: The preview's bake, the same one the viewer uses.
    ///   - export: One photo's export; injectable for tests.
    init(photos: [RecordPhoto],
         profileID: UUID,
         store: ProfileStore,
         library: any RecordAlbumLibrary,
         calendar: Calendar = .autoupdatingCurrent,
         renderer: TemplateRenderer = TemplateRenderer(),
         bake: @escaping PhotoDetailModel.Bake = { image, text, style, placement, font, cropRect, filmDate, tone in
             OverlayRenderer().bake(image: image, text: text, style: style, placement: placement,
                                    font: font, cropRect: cropRect, filmDate: filmDate, tone: tone)
         },
         resolveFont: @escaping @MainActor (OverlayStyle) -> ResolvedOverlayFont,
         tips: FirstRunTips = .shared,
         export: @escaping Export) {
        exportable = photos.filter { $0.creationDate != nil }
        skippedCount = photos.count - exportable.count
        self.profileID = profileID
        self.store = store
        self.library = library
        self.calendar = calendar
        self.renderer = renderer
        self.bake = bake
        self.resolveFont = resolveFont
        self.exportPhoto = export
        self.profile = store.profiles.first { $0.id == profileID }
        // Seeing the batch preview counts as seeing the first-export comparison (FR-22.3).
        tips.markExportIntroSeen()
        subscription = store.$profiles
            .dropFirst()
            .sink { [weak self] profiles in
                guard let self else { return }
                self.profile = profiles.first { $0.id == self.profileID }
            }
    }

    /// Builds the export over `pipeline` with the record's font path.
    static func pipelineExport(_ pipeline: PhotoExportPipeline,
                               resolveFont: @escaping @MainActor (OverlayStyle) -> ResolvedOverlayFont) -> Export {
        { photo, profile, progress in
            await pipeline.export(photo: photo, profile: profile, resolveFont: resolveFont, progress: progress)
        }
    }

    // MARK: - Preview (FR-22.5, FR-22.6)

    /// "匯出 M 張新照片".
    var previewTitle: String { "匯出 \(exportable.count) 張新照片" }

    static let previewMessage = "原圖不動，每張另存一張印上天數的新照片到「最近項目」。"

    /// "其中 N 張日期不明，無法標天數，會略過。", `nil` with none.
    var skippedMessage: String? {
        skippedCount > 0 ? "其中 \(skippedCount) 張日期不明，無法標天數，會略過。" : nil
    }

    /// "匯出 M 張".
    var exportButtonTitle: String { "匯出 \(exportable.count) 張" }

    /// The carousel's photo.
    var previewPhoto: RecordPhoto? {
        exportable.indices.contains(previewIndex) ? exportable[previewIndex] : nil
    }

    /// "i／M" under the carousel.
    var previewPosition: String { "\(previewIndex + 1)／\(exportable.count)" }

    /// ‹ and ›: wraps around, as D8 does.
    func showPrevious() {
        guard !exportable.isEmpty else { return }
        previewIndex = (previewIndex - 1 + exportable.count) % exportable.count
    }

    func showNext() {
        guard !exportable.isEmpty else { return }
        previewIndex = (previewIndex + 1) % exportable.count
    }

    /// The overlay text of `photo` with the record's current style.
    func overlayText(for photo: RecordPhoto) -> String? {
        guard let profile, let date = photo.creationDate else { return nil }
        return renderer.render(profile: profile, capturedAt: date, calendar: calendar, moment: .photo)
    }

    /// The carousel image of `photo`: screen-sized, marked the way the viewer
    /// marks it (`PhotoDetailModel.markedImage`), with its own date.
    func previewImage(for photo: RecordPhoto, targetSize: CGSize) async -> UIImage? {
        guard let source = await library.displayImage(id: photo.id, targetSize: targetSize) else { return nil }
        guard let profile else { return source }
        return await PhotoDetailModel.markedImage(source, photo: photo, profile: profile, calendar: calendar,
                                                  renderer: renderer, font: resolveFont(profile.style), bake: bake)
    }

    /// 取消 (or swiping the preview away): nothing is exported.
    func cancel() {
        guard phase == .preview else { return }
        onFinish(.cancelled)
    }

    // MARK: - Running (FR-22.4, FR-22.7)

    /// 匯出 M 張: exports every exportable photo.
    func start() {
        guard phase == .preview else { return }
        run(exportable)
    }

    /// 重試失敗的: runs only the photos that failed (FR-22.9).
    func retryFailed() {
        guard case .failed = phase else { return }
        let failing = Set(failedIDs)
        run(exportable.filter { failing.contains($0.id) })
    }

    /// 停止: the photo in progress finishes, then no other starts.
    func stop() {
        guard case .running = phase else { return }
        isStopping = true
    }

    /// The bar's fill, 0...1, counting the current photo's download.
    var progressFraction: Double {
        guard case let .running(done, total) = phase, total > 0 else { return 0 }
        return min(1, (Double(done) + currentProgress) / Double(total))
    }

    /// "i／N".
    var progressText: String {
        guard case let .running(done, total) = phase else { return "" }
        return "\(done)／\(total)"
    }

    /// Waits for the run in progress, if any; for tests.
    func waitForRun() async {
        await runTask?.value
    }

    private func run(_ photos: [RecordPhoto]) {
        guard runTask == nil else { return }
        isStopping = false
        permissionDenied = false
        failedIDs = []
        phase = .running(done: 0, total: photos.count)
        runTask = Task { [weak self] in
            await self?.exportAll(photos)
            self?.runTask = nil
        }
    }

    private func exportAll(_ photos: [RecordPhoto]) async {
        for (index, photo) in photos.enumerated() {
            if isStopping { break }
            // A refused permission fails every photo left without trying (FR-22.9).
            guard !permissionDenied, let profile = store.profiles.first(where: { $0.id == profileID }) else {
                failedIDs.append(photo.id)
                phase = .running(done: index + 1, total: photos.count)
                continue
            }
            currentProgress = 0
            let result = await exportPhoto(photo, profile) { [weak self] value in
                Task { @MainActor in self?.currentProgress = value }
            }
            switch result {
            case .success:
                savedIDs.insert(photo.id)
            case let .failure(error):
                failedIDs.append(photo.id)
                if error == .saveFailed(.permissionDenied) { permissionDenied = true }
            }
            currentProgress = 0
            phase = .running(done: index + 1, total: photos.count)
        }
        finishRun()
    }

    private func finishRun() {
        if isStopping {
            onFinish(.stopped(saved: savedIDs.count))
        } else if failedIDs.isEmpty {
            onFinish(.allSaved(count: savedIDs.count))
        } else {
            phase = .failed(succeeded: savedIDs.count, failed: failedIDs.count)
        }
    }

    // MARK: - Failures (FR-22.9)

    /// "已匯出 S 張，F 張失敗".
    var failureTitle: String {
        guard case let .failed(succeeded, failed) = phase else { return "" }
        return "已匯出 \(succeeded) 張，\(failed) 張失敗"
    }

    /// The permission text after a refusal (FR-22.2), else the iCloud／space note.
    var failureMessage: String {
        permissionDenied
            ? PhotoExportError.saveFailed(.permissionDenied).message
            : "失敗的照片可能還在從 iCloud 下載，或儲存空間不足。"
    }

    /// 好: back to the wall with only the failed photos ticked.
    func acknowledgeFailures() {
        guard case .failed = phase else { return }
        onFinish(.keptFailures(failedIDs: failedIDs))
    }
}
