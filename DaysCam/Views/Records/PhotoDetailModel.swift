import Combine
import Foundation
import UIKit

/// Drives the photo viewer of one record (PRD 2.0 FR-18, D-7 screen 3).
///
/// The photos come in the wall's order. Each page shows the screen-sized
/// image with the record's overlay baked in by `OverlayRenderer.bake`, the
/// same function the export uses, so the preview and the result differ only
/// in resolution. The text is made from the photo's own `creationDate`
/// (§6.1); nothing is written to a photo.
@MainActor
final class PhotoDetailModel: ObservableObject {
    /// `OverlayRenderer.bake`, injectable for tests. Runs off the main thread.
    typealias Bake = @Sendable (UIImage, String, OverlayStyle, OverlayPlacement, ResolvedOverlayFont,
                                CGRect?, FilmDateStamp?, ColorTone) -> UIImage?

    /// The record's photos, oldest first, as the wall lists them.
    @Published private(set) var photos: [RecordPhoto] = []
    /// The photo on screen.
    @Published var selectedID: String
    @Published private(set) var profile: CameraProfile?
    /// Set when removing failed; the view surfaces it and clears it.
    @Published var errorMessage: String?
    /// Nothing is left to show next: the view goes back to the wall.
    @Published private(set) var shouldDismiss = false
    /// The export sheet of the photo on screen while it is up (#679); it
    /// carries the progress and failures too.
    @Published private(set) var export: BatchExportModel?
    /// The "已匯出" toast while it shows.
    @Published private(set) var toastState: ToastState?
    /// The pointer bubble was dismissed (or the viewer left) in this session.
    @Published private(set) var coachDismissed = false

    /// What VoiceOver hears, and the toast shows, after a successful export.
    static let exportedMessage = "已匯出"
    /// How long the toast stays.
    static let toastDuration: TimeInterval = 1.6

    /// Speaks `message` to VoiceOver. Replaceable so tests can observe it.
    var announce: (String) -> Void = { message in
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    let profileID: UUID
    private let store: ProfileStore
    private let library: any RecordAlbumLibrary
    private let calendar: Calendar
    private let renderer: TemplateRenderer
    private let bake: Bake
    private let resolveFont: @MainActor (OverlayStyle) -> ResolvedOverlayFont
    private let makeExport: (([RecordPhoto]) -> BatchExportModel)?
    private let tips: FirstRunTips
    private let scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void
    private var subscription: AnyCancellable?
    private var changesTask: Task<Void, Never>?

    init(profileID: UUID,
         startingAt photoID: String,
         store: ProfileStore,
         library: any RecordAlbumLibrary,
         calendar: Calendar = .autoupdatingCurrent,
         renderer: TemplateRenderer = TemplateRenderer(),
         bake: @escaping Bake = { image, text, style, placement, font, cropRect, filmDate, tone in
             OverlayRenderer().bake(image: image, text: text, style: style, placement: placement,
                                    font: font, cropRect: cropRect, filmDate: filmDate, tone: tone)
         },
         resolveFont: @escaping @MainActor (OverlayStyle) -> ResolvedOverlayFont,
         makeExport: (([RecordPhoto]) -> BatchExportModel)? = nil,
         tips: FirstRunTips = .shared,
         scheduleAfter: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
         }) {
        self.makeExport = makeExport
        self.tips = tips
        self.scheduleAfter = scheduleAfter
        self.profileID = profileID
        self.selectedID = photoID
        self.store = store
        self.library = library
        self.calendar = calendar
        self.renderer = renderer
        self.bake = bake
        self.resolveFont = resolveFont
        self.profile = store.profiles.first { $0.id == profileID }
        subscription = store.$profiles
            .dropFirst()
            .sink { [weak self] profiles in
                guard let self else { return }
                self.profile = profiles.first { $0.id == self.profileID }
                self.reload()
            }
        reload()
    }

    deinit {
        changesTask?.cancel()
    }

    // MARK: - Photos

    /// The photo on screen.
    var currentPhoto: RecordPhoto? { photos.first { $0.id == selectedID } }

    /// Re-reads the photos. Keeps the selection while its photo exists.
    func reload() {
        guard let profile else {
            photos = []
            shouldDismiss = true
            return
        }
        photos = library.photos(albumIdentifier: profile.albumIdentifier,
                                fallbackIDs: profile.fallbackAssetIDs)
        shouldDismiss = photos.isEmpty
        if !photos.contains(where: { $0.id == selectedID }), let newest = photos.last {
            selectedID = newest.id
        }
    }

    /// Follows library changes, such as the photo being deleted elsewhere.
    func startObservingLibrary() {
        guard changesTask == nil else { return }
        let changes = library.changes()
        changesTask = Task { [weak self] in
            for await _ in changes { self?.reload() }
        }
    }

    func stopObservingLibrary() {
        changesTask?.cancel()
        changesTask = nil
    }

    // MARK: - Header and caption

    /// "第 N 天", "前 N 天" or "日期不明" (FR-18.1, §6.1.3).
    func title(for photo: RecordPhoto) -> String {
        guard let profile else { return "" }
        return PhotoWallModel.dayMark(creationDate: photo.creationDate, profile: profile, calendar: calendar).text
    }

    /// "YYYY/M/D HH:mm" of the photo's `creationDate`; `nil` without one.
    func dateLine(for photo: RecordPhoto) -> String? {
        guard let date = photo.creationDate else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%d/%d/%d %02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                      parts.hour ?? 0, parts.minute ?? 0)
    }

    /// The overlay text of the photo's own moment (FR-18.3), `nil` when the
    /// photo has no date and so nothing is drawn.
    func overlayText(for photo: RecordPhoto) -> String? {
        guard let profile, let date = photo.creationDate else { return nil }
        return renderer.render(profile: profile, capturedAt: date, calendar: calendar, moment: .photo)
    }

    /// Whether `photo` can be exported: only with a `creationDate`, since the
    /// day count comes from it (§6.1.3, FR-18.5).
    func canExport(_ photo: RecordPhoto) -> Bool {
        profile != nil && photo.creationDate != nil
    }

    /// Whether 匯出 can be pressed for the photo on screen: no sheet already
    /// up, and only with a date.
    var canStartExport: Bool {
        export == nil && (currentPhoto.map(canExport) ?? false)
    }

    /// The name of the record, for the remove action's title.
    var recordName: String { profile?.name ?? "" }

    // MARK: - Page image

    /// The screen-sized image of `photo` with the overlay baked in
    /// (FR-18.2, FR-18.3, FR-18.7). Falls back to the plain image when the
    /// photo has no date or baking fails; `nil` when the image cannot load.
    func pageImage(for photo: RecordPhoto, targetSize: CGSize) async -> UIImage? {
        guard let source = await library.displayImage(id: photo.id, targetSize: targetSize) else { return nil }
        guard let profile else { return source }
        // Resolved here on the main actor; the background bake never reads the library.
        return await Self.markedImage(source, photo: photo, profile: profile, calendar: calendar,
                                      renderer: renderer, font: resolveFont(profile.style), bake: bake)
    }

    /// `source` with `profile`'s overlay for `photo`'s own moment baked in,
    /// the way the viewer and the batch preview show it; `source` itself
    /// when the photo has no date or baking fails.
    /// With `hidesText` (隱藏文字, #679) only the film date stamp is drawn.
    static func markedImage(_ source: UIImage, photo: RecordPhoto, profile: CameraProfile, calendar: Calendar,
                            renderer: TemplateRenderer, font: ResolvedOverlayFont, hidesText: Bool = false,
                            bake: @escaping Bake) async -> UIImage {
        guard let date = photo.creationDate else { return source }
        let text = hidesText ? "" : renderer.render(profile: profile, capturedAt: date, calendar: calendar, moment: .photo)
        let filmDate = filmDateStamp(for: profile, creationDate: date, calendar: calendar)
        let style = profile.style
        let placement = profile.position
        let baked = await Task.detached(priority: .userInitiated) {
            bake(source, text, style, placement, font, nil, filmDate, .standard)
        }.value
        return baked ?? source
    }

    /// The film date stamp for a photo taken at `creationDate`, `nil` while
    /// the record has it off.
    static func filmDateStamp(for profile: CameraProfile, creationDate: Date, calendar: Calendar) -> FilmDateStamp? {
        guard profile.showFilmDate else { return nil }
        let components = DayCountCalculator(calendar: calendar, now: { creationDate }).currentDateComponents()
        return FilmDateStamp(text: FilmDateStamp.text(for: components), corner: profile.filmDateCorner)
    }

    // MARK: - Export (#679)

    /// 匯出: opens the export sheet over the photo on screen, the same sheet
    /// as the wall's batch export with just this one photo.
    func beginExport() {
        guard canStartExport, let photo = currentPhoto, let makeExport else { return }
        let model = makeExport([photo])
        model.onFinish = { [weak self] outcome in self?.finishExport(outcome) }
        export = model
    }

    /// The sheet ended. A saved photo toasts and announces 已匯出; the viewer
    /// stays on the same photo either way.
    func finishExport(_ outcome: BatchExportModel.Outcome) {
        export = nil
        switch outcome {
        case let .allSaved(count), let .stopped(count):
            guard count > 0 else { return }
            announce(Self.exportedMessage)
            let toast = ToastState(message: Self.exportedMessage)
            toastState = toast
            scheduleAfter(ToastTiming.duration(Self.toastDuration)) { [weak self] in
                guard self?.toastState?.id == toast.id else { return }
                self?.toastState = nil
            }
        case .cancelled, .keptFailures:
            break
        }
    }

    // MARK: - Pointer bubble (FR-18.8)

    /// Whether the first-visit bubble shows: not seen yet, and the photo on
    /// screen has overlay text to point at.
    var showsCoach: Bool {
        guard !tips.viewerCoachSeen, !coachDismissed, let photo = currentPhoto else { return false }
        return overlayText(for: photo)?.isEmpty == false
    }

    /// 知道了: never shows again.
    func dismissCoach() {
        tips.markViewerCoachSeen()
        coachDismissed = true
    }

    /// Where the overlay's block sits when `photo`'s image is drawn at
    /// `imageSize`, laid out the way the bake does (FR-18.8); `nil` without text.
    func overlayFrame(for photo: RecordPhoto, imageSize: CGSize) -> CGRect? {
        guard let profile, let text = overlayText(for: photo), !text.isEmpty,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let font = resolveFont(profile.style)
        let fontSize = OverlayRenderer.fittedFontSize(for: text, style: profile.style, frameSize: imageSize, font: font)
        guard let block = OverlayRenderer().renderText(text, style: profile.style, fontSize: fontSize,
                                                       displayScale: 1, font: font)?.blockSize else { return nil }
        let origin = OverlayMetrics.origin(forBlockSize: block, in: imageSize, placement: profile.position)
        return CGRect(origin: origin, size: block)
    }

    // MARK: - Removing and deleting (FR-18.6)

    /// Takes the photo on screen out of the record, no confirmation: out of
    /// the album, and out of `fallbackAssetIDs` when listed there. The photo
    /// stays in the library. Then moves to the next photo, or empties.
    func removeFromRecord() async {
        guard let profile, let photo = currentPhoto else { return }
        let next = neighbor(after: photo.id)
        do {
            if let albumID = profile.albumIdentifier, library.authorizationStatus() == .authorized {
                try await library.removeAsset(photo.id, fromAlbum: albumID)
            }
            if var latest = store.profiles.first(where: { $0.id == profileID }),
               latest.fallbackAssetIDs.contains(photo.id) {
                latest.fallbackAssetIDs.removeAll { $0 == photo.id }
                try store.updateAndWait(latest)
            }
        } catch let error as RecordAlbumError {
            errorMessage = Self.message(for: error)
            return
        } catch let error as ProfileStoreError {
            errorMessage = error.displayMessage
            return
        } catch {
            errorMessage = "無法從紀錄移除，請再試一次。"
            return
        }
        advance(from: photo.id, to: next, stillShown: "這張照片無法從紀錄移除。")
    }

    /// Deletes the photo through the system confirmation. A cancel changes
    /// nothing.
    func deletePhoto() async {
        guard let photo = currentPhoto else { return }
        let next = neighbor(after: photo.id)
        guard await library.deleteAsset(photo.id) else { return }
        advance(from: photo.id, to: next, stillShown: "無法刪除這張照片。")
    }

    /// The photo to show once `id` is gone: the one after it, none when it is last.
    private func neighbor(after id: String) -> String? {
        guard let index = photos.firstIndex(where: { $0.id == id }), photos.indices.contains(index + 1) else { return nil }
        return photos[index + 1].id
    }

    private func advance(from id: String, to next: String?, stillShown message: String) {
        reload()
        if photos.contains(where: { $0.id == id }) {
            errorMessage = message
            return
        }
        guard let next else {
            shouldDismiss = true
            return
        }
        selectedID = next
    }

    /// The text of the failure alert for `error`.
    static func message(for error: RecordAlbumError) -> String {
        switch error {
        case .permissionDenied: return "需要「照片」權限才能從紀錄移除。"
        case .notFound: return "找不到這張照片，它可能已被刪除。"
        case let .failed(reason): return reason.isEmpty ? "無法從紀錄移除，請再試一次。" : reason
        }
    }
}
