import Combine
import Foundation
import UIKit

/// Drives the export page of one photo (PRD 2.0 FR-19, D-7 screen 4).
///
/// Hosts the overlay panel for the photo's record, so every change is written
/// back to the record at once (FR-19.4). The checkmark fetches the original
/// image, bakes the record's overlay into it with the text of the photo's own
/// `creationDate` (§6.1, §6.3) and saves the result as a new photo to
/// 「最近項目」 only (FR-19.5, FR-19.9). The original is never changed.
@MainActor
final class ExportModel: ObservableObject, OverlayPanelHosting {
    /// `OverlayRenderer.bake`, injectable for tests. Runs off the main thread.
    typealias Bake = PhotoDetailModel.Bake
    /// Saves a baked image to 「最近項目」 only; completes once, on main.
    typealias Save = (UIImage, @escaping (Result<String, PhotoSaveError>) -> Void) -> Void

    /// What VoiceOver hears, and the toast shows, after a successful export.
    static let exportedMessage = "已匯出"
    /// How long the toast stays before going back to the viewer (FR-19.6).
    static let toastDuration: TimeInterval = 0.9
    /// Baking failed (0.1 §7.3, the same text the camera used).
    static let bakeFailedMessage = "照片處理失敗，請再試一次。"
    /// The original could not be fetched, e.g. an iCloud download failed.
    static let downloadFailedMessage = "無法取得原始照片，請確認網路連線後再試一次。"
    /// The photo is gone from the library.
    static let photoMissingMessage = "找不到這張照片，它可能已被刪除。"

    /// The panel stays open on this page; there is no viewfinder to give room to.
    let panelModel = OverlayPanelModel()
    /// The photo being exported.
    let photo: RecordPhoto
    let profileID: UUID
    /// The record as the store has it now; the preview follows it.
    @Published private(set) var profile: CameraProfile?
    /// From the checkmark until the result is known (FR-19.7).
    @Published private(set) var isExporting = false
    /// The original's download progress, 0...1, while exporting.
    @Published private(set) var progress: Double = 0
    /// A failure to alert on (0.1 §7.3); `nil` once dismissed.
    @Published private(set) var exportError: CaptureAlertError?
    /// The "已匯出" toast while it shows.
    @Published private(set) var toastState: ToastState?
    /// Set after the success toast: the page goes back to the viewer.
    @Published private(set) var shouldDismiss = false

    /// Speaks `message` to VoiceOver. Replaceable so tests can observe it.
    var announce: (String) -> Void = { message in
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private let editor: ProfileStyleEditor?
    private let store: ProfileStore
    private let library: any RecordAlbumLibrary
    private let calendar: Calendar
    private let renderer: TemplateRenderer
    private let bake: Bake
    private let save: Save
    private let resolveFont: @MainActor (OverlayStyle) -> ResolvedOverlayFont
    private let scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void
    private let bakeQueue = DispatchQueue(label: "dayscam.export-bake", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - editor: The panel's tab models for the record
    ///     (`CameraScreenModel.makeStyleEditor`); `nil` shows the placeholders.
    ///   - fontChanges: Fires before a font's state changes, so the preview
    ///     redraws with the font once it is usable.
    ///   - save: Defaults to `PhotoSaver.saveToRecentsOnly`, which never adds
    ///     the photo to an album.
    ///   - scheduleAfter: Runs a closure after a delay; tests run it at once.
    init(profileID: UUID,
         photo: RecordPhoto,
         store: ProfileStore,
         library: any RecordAlbumLibrary,
         editor: ProfileStyleEditor?,
         calendar: Calendar = .autoupdatingCurrent,
         renderer: TemplateRenderer = TemplateRenderer(),
         bake: @escaping Bake = { image, text, style, placement, font, cropRect, filmDate, tone in
             OverlayRenderer().bake(image: image, text: text, style: style, placement: placement,
                                    font: font, cropRect: cropRect, filmDate: filmDate, tone: tone)
         },
         save: @escaping Save = { image, completion in
             PhotoSaver().saveToRecentsOnly(image, completion: completion)
         },
         resolveFont: @escaping @MainActor (OverlayStyle) -> ResolvedOverlayFont,
         fontChanges: ObservableObjectPublisher? = nil,
         scheduleAfter: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
         }) {
        self.profileID = profileID
        self.photo = photo
        self.store = store
        self.library = library
        self.editor = editor
        self.calendar = calendar
        self.renderer = renderer
        self.bake = bake
        self.save = save
        self.resolveFont = resolveFont
        self.scheduleAfter = scheduleAfter
        self.profile = store.profiles.first { $0.id == profileID }
        panelModel.overlayDragHandler = editor?.dragAdapter
        panelModel.open()

        store.$profiles
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profiles in
                guard let self else { return }
                self.profile = profiles.first { $0.id == self.profileID }
                self.editor?.applyExternalChanges(from: profiles)
            }
            .store(in: &cancellables)
        // `OverlayPanelView` observes only this model (see `OverlayPanelHosting`).
        panelModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        fontChanges?
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Panel host

    var styleTabModel: StyleTabModel? { editor?.styleTabModel }
    var formatTabModel: FormatTabModel? { editor?.formatTabModel }
    var positionTabModel: PositionTabModel? { editor?.positionTabModel }

    // MARK: - Header and preview (FR-19.1, FR-19.2)

    /// "第 N 天" (or "前 N 天", "日期不明") under 匯出.
    var dayTitle: String {
        guard let profile else { return "" }
        return PhotoWallModel.dayMark(creationDate: photo.creationDate, profile: profile, calendar: calendar).text
    }

    /// The overlay text of the photo's own moment; `nil` without a date.
    var overlayText: String? {
        guard let profile, let date = photo.creationDate else { return nil }
        return renderer.render(profile: profile, capturedAt: date, calendar: calendar, moment: .photo)
    }

    /// The film date of the photo's own day, `nil` while the record has it off.
    var filmDateStamp: FilmDateStamp? {
        guard let profile, let date = photo.creationDate else { return nil }
        return PhotoDetailModel.filmDateStamp(for: profile, creationDate: date, calendar: calendar)
    }

    /// The face the overlay draws with, resolved now.
    var overlayFont: ResolvedOverlayFont {
        resolveFont(profile?.style ?? OverlayStyle())
    }

    /// The plain screen-sized image under the preview's overlay.
    func previewImage(targetSize: CGSize) async -> UIImage? {
        await library.displayImage(id: photo.id, targetSize: targetSize)
    }

    // MARK: - Export (FR-19.5–FR-19.7, FR-19.9)

    /// Whether the checkmark can be pressed: one export at a time, and never
    /// for a photo without a date (§6.1.3).
    var canExport: Bool {
        !isExporting && photo.creationDate != nil && profile != nil
    }

    /// Fetches the original (downloading it from iCloud if needed), bakes the
    /// overlay in and saves a new photo to 「最近項目」. Any failure ends in
    /// the error alert and nothing is reported as exported; success announces
    /// "已匯出", shows the toast and goes back to the viewer.
    func export() async {
        guard canExport, let profile, let date = photo.creationDate else { return }
        isExporting = true
        progress = 0
        let text = renderer.render(profile: profile, capturedAt: date, calendar: calendar, moment: .photo)
        let style = profile.style
        let placement = profile.position
        let font = resolveFont(style)
        let filmDate = PhotoDetailModel.filmDateStamp(for: profile, creationDate: date, calendar: calendar)

        let original: UIImage
        do {
            original = try await library.fullImage(id: photo.id) { [weak self] value in
                Task { @MainActor in self?.progress = value }
            }
        } catch RecordAlbumError.notFound {
            fail(message: Self.photoMissingMessage)
            return
        } catch {
            fail(message: Self.downloadFailedMessage)
            return
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
        guard let baked else {
            fail(message: Self.bakeFailedMessage)
            return
        }

        let result: Result<String, PhotoSaveError> = await withCheckedContinuation { continuation in
            save(baked) { continuation.resume(returning: $0) }
        }
        switch result {
        case .success:
            succeed()
        case let .failure(error):
            fail(message: error.displayMessage, showsSettingsAction: error.showsSettingsAction)
        }
    }

    /// Dismisses the failure alert.
    func dismissError() {
        exportError = nil
    }

    private func fail(message: String, showsSettingsAction: Bool = false) {
        exportError = CaptureAlertError(message: message, showsSettingsAction: showsSettingsAction)
        isExporting = false
    }

    private func succeed() {
        progress = 1
        announce(Self.exportedMessage)
        let toast = ToastState(message: Self.exportedMessage)
        toastState = toast
        scheduleAfter(Self.toastDuration) { [weak self] in
            guard let self else { return }
            self.toastState = nil
            self.isExporting = false
            self.shouldDismiss = true
        }
    }
}

#if DEBUG
/// `-UITestOpenExport` (#620): the photo wall opens its newest photo and the
/// viewer then opens that photo's export page, each once per launch.
@MainActor
enum UITestExportLaunch {
    private static var opensViewer = ProcessInfo.processInfo.arguments.contains("-UITestOpenExport")
    private static var opensExport = ProcessInfo.processInfo.arguments.contains("-UITestOpenExport")

    /// `true` the first time it is asked while the argument is present.
    static func consumeViewer() -> Bool {
        defer { opensViewer = false }
        return opensViewer
    }

    /// `true` the first time it is asked while the argument is present.
    static func consumeExport() -> Bool {
        defer { opensExport = false }
        return opensExport
    }
}
#endif
