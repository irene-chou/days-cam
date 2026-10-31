import Combine
import Foundation
import UIKit

/// Drives the 文字樣式 page of one photo (PRD 2.0 FR-19, D8 ④).
///
/// Hosts the overlay panel for the photo's record, so every change is written
/// back to the record at once (FR-19.4). Nothing is exported here: the
/// checkmark and the xmark both just go back (FR-19.1); exporting is
/// `PhotoExportPipeline`'s, started from the viewer (FR-22).
@MainActor
final class ExportModel: ObservableObject, OverlayPanelHosting {
    /// The panel stays open on this page; there is no viewfinder to give room to.
    let panelModel = OverlayPanelModel()
    /// The photo the page was opened from; the preview shows it.
    let photo: RecordPhoto
    let profileID: UUID
    /// The record as the store has it now; the preview follows it.
    @Published private(set) var profile: CameraProfile?

    private let editor: ProfileStyleEditor?
    private let store: ProfileStore
    private let library: any RecordAlbumLibrary
    private let calendar: Calendar
    private let renderer: TemplateRenderer
    private let resolveFont: @MainActor (OverlayStyle) -> ResolvedOverlayFont
    private var cancellables = Set<AnyCancellable>()

    /// - Parameters:
    ///   - editor: The panel's tab models for the record
    ///     (`CameraScreenModel.makeStyleEditor`); `nil` shows the placeholders.
    ///   - fontChanges: Fires before a font's state changes, so the preview
    ///     redraws with the font once it is usable.
    init(profileID: UUID,
         photo: RecordPhoto,
         store: ProfileStore,
         library: any RecordAlbumLibrary,
         editor: ProfileStyleEditor?,
         calendar: Calendar = .autoupdatingCurrent,
         renderer: TemplateRenderer = TemplateRenderer(),
         resolveFont: @escaping @MainActor (OverlayStyle) -> ResolvedOverlayFont,
         fontChanges: ObservableObjectPublisher? = nil) {
        self.profileID = profileID
        self.photo = photo
        self.store = store
        self.library = library
        self.editor = editor
        self.calendar = calendar
        self.renderer = renderer
        self.resolveFont = resolveFont
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

    // MARK: - Dragging

    /// Whether the preview's text can be dragged now.
    var isOverlayDraggable: Bool { panelModel.isOverlayDraggable }

    /// A drag on the preview moved the text.
    func overlayDragChanged(center: CGPoint, frameSize: CGSize) {
        panelModel.overlayDragHandler?.overlayDragChanged(center: center, viewfinderSize: frameSize)
    }

    /// A drag on the preview ended: writes the position.
    func overlayDragEnded(center: CGPoint, frameSize: CGSize) {
        panelModel.overlayDragHandler?.overlayDragEnded(center: center, viewfinderSize: frameSize)
    }

    // MARK: - Header and preview (FR-19.1, FR-19.2)

    /// "<紀錄名> · 套用到所有照片" under 文字樣式 (FR-19.1).
    var subtitle: String {
        "\(profile?.name ?? "") · 套用到所有照片"
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
}

#if DEBUG
/// `-UITestOpenExport` (#620): the photo wall opens its newest photo and the
/// viewer then opens that photo's 文字樣式 page, each once per launch.
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
