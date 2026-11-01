import Combine
import Foundation
import Photos
import UIKit

/// A page pushed on the 紀錄 list's navigation stack.
enum RecordRoute: Hashable {
    /// The photo wall of a record (FR-17).
    case wall(UUID)
    /// The editor of a record (FR-21).
    case editor(UUID)

    /// The record the page belongs to.
    var recordID: UUID {
        switch self {
        case let .wall(id), let .editor(id): return id
        }
    }
}

/// Drives the 紀錄 list, the home screen of 2.0 (PRD 2.0 FR-16, FR-21).
///
/// Mirrors the `ProfileStore` and reads photo counts from a
/// `RecordAlbumLibrary`. The list itself never asks for photo access: a count
/// is `nil` ("—") until access has been granted somewhere else.
@MainActor
final class RecordListModel: ObservableObject {
    /// One row of the list: name and the "今天第 N 天 · M 張" line only.
    struct Row: Identifiable, Equatable {
        let id: UUID
        let name: String
        let subtitle: String
    }

    /// What the editor's 相簿 row shows and whether it can be opened.
    enum AlbumRowState: Equatable {
        /// Tappable; `title` is the bound album or the "建立新相簿" text.
        case available(title: String)
        /// Not asked yet: shows the "建立時會在「照片」App 建立" text, not
        /// tappable, and never triggers the permission prompt (FR-21.4).
        case notAsked(title: String)
        /// Limited, denied or restricted: tapping opens Settings (FR-21.4).
        case needsSettings(title: String)
    }

    /// Placeholder shown while a new record's name is still empty.
    static let newRecordPlaceholder = "新紀錄"
    /// Delete confirmation when no bound album can be looked up (FR-16.5).
    static let deletionMessageWithoutAlbum = "照片會保留在「照片」App。"
    /// Shown when the library cannot report a count.
    static let unknownCountText = "—"
    /// Shown when an album could not be created in the Photos app (FR-21.6).
    static let albumCreationFailedMessage = "無法在「照片」App 建立相簿，之後會再試一次。"

    /// Every record, in store order; `rows` sorts them.
    @Published private(set) var profiles: [CameraProfile]
    /// Non-nil while the delete confirmation should show.
    @Published private(set) var deletionCandidate: CameraProfile?
    /// The latest failed action, for the view to surface.
    @Published var lastError: Error?
    /// The pages pushed onto the list's navigation stack: a record's photo
    /// wall, with its editor on top when opened from there. Leaving a new
    /// record's editor by back discards it.
    @Published var path: [RecordRoute] = [] {
        didSet { if path.isEmpty { discardDraft() } }
    }
    /// Bumped to re-read counts and album names when the library changed.
    @Published private(set) var libraryRevision = 0
    /// True for the one launch right after `ProfileStore.load()` found an
    /// unreadable profile file and re-seeded (PRD 0.1 §7.3, 15.1). Read once
    /// at `init`: the store only sets it during `load()`, which has already
    /// run. Moved here from the camera, which is no longer the first screen
    /// (#621).
    @Published private(set) var showsCorruptionRecoveredAlert: Bool

    let store: ProfileStore
    let library: any RecordAlbumLibrary
    /// The app's one queue of writes that may create an album; shared with
    /// every camera so album creation, "加入照片" and camera saves never make
    /// a second album for a record (#651).
    let saveCoordinator: CaptureSaveCoordinator
    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer
    private let makeRulesModel: (CameraProfile) -> RulesTabModel
    private let openSettings: (URL) -> Void
    /// Saves an exported photo to 「最近項目」 only (FR-22.1).
    private let exportSave: PhotoExportPipeline.Save
    /// The record created by "新增紀錄" that the checkmark has not confirmed.
    private var draftID: UUID?
    private var subscriptions = Set<AnyCancellable>()
    private var changesTask: Task<Void, Never>?
    /// Records with an album creation queued or running: a second trigger
    /// skips them (FR-21.6).
    private var albumCreationsInFlight: Set<UUID> = []
    /// Albums created for a record whose write-back then failed: the next
    /// attempt binds the same album instead of making another (#661 review).
    private var unboundCreatedAlbums: [UUID: String] = [:]

    /// Creates a model over `store`.
    ///
    /// - Parameter makeRulesModel: builds the editor's `RulesTabModel`; the
    ///   default routes writes through a `TabProfileWriter` so a rules edit
    ///   never overwrites a field another writer just changed (#70).
    /// - Parameter exportSave: saves an exported photo; defaults to
    ///   `PhotoSaver.saveToRecentsOnly`.
    /// - Parameter openSettings: opens the app's Settings page from the
    ///   editor's 相簿 row; injected so tests can capture the URL.
    /// - Parameter saveCoordinator: the queue album creation joins; pass the
    ///   cameras' one.
    init(store: ProfileStore,
         library: any RecordAlbumLibrary,
         saveCoordinator: CaptureSaveCoordinator? = nil,
         calendar: Calendar = .autoupdatingCurrent,
         calculator: DayCountCalculator? = nil,
         renderer: TemplateRenderer = TemplateRenderer(),
         makeRulesModel: ((CameraProfile) -> RulesTabModel)? = nil,
         exportSave: @escaping PhotoExportPipeline.Save = { image, completion in
             PhotoSaver().saveToRecentsOnly(image, completion: completion)
         },
         openSettings: ((URL) -> Void)? = nil) {
        self.exportSave = exportSave
        self.openSettings = openSettings ?? { UIApplication.shared.open($0) }
        let calculator = calculator ?? DayCountCalculator(calendar: calendar)
        self.store = store
        self.library = library
        self.saveCoordinator = saveCoordinator ?? CaptureSaveCoordinator()
        self.calendar = calendar
        self.calculator = calculator
        self.renderer = renderer
        self.makeRulesModel = makeRulesModel ?? { profile in
            let writer = TabProfileWriter(baseline: profile, profileStore: store)
            return RulesTabModel(profile: profile, calendar: calendar, calculator: calculator,
                                 renderer: renderer, updateProfile: writer.write)
        }
        self.profiles = store.profiles
        self.showsCorruptionRecoveredAlert = store.didRecoverFromCorruption
        store.$profiles
            .dropFirst()
            .sink { [weak self] in self?.profiles = $0 }
            .store(in: &subscriptions)
        // Profile writes are debounced (#464), so a failed save surfaces here
        // rather than as a throw. Only failing/not-failing is compared (the
        // error text carries a random file name): one failure shows once,
        // and a successful retry re-arms it. The camera showed this until
        // #621.
        store.$lastWriteError
            .map { $0 != nil }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasError in
                guard hasError, let self else { return }
                self.lastError = self.store.lastWriteError ?? ProfileStoreError.writeFailed("")
            }
            .store(in: &subscriptions)
    }

    /// A camera failure reported after the camera closed (#621): the photo
    /// was not saved, and the camera is no longer there to say so.
    @Published private(set) var captureFailure: CaptureAlertError?
    private var unacknowledgedCaptureFailures = 0

    /// Shows `error` for `count` photos that were not saved; later reports
    /// before it is dismissed add up to "N 張照片未儲存".
    func reportCaptureFailure(_ error: CaptureAlertError, count: Int) {
        let previous = unacknowledgedCaptureFailures > 0 ? captureFailure : nil
        unacknowledgedCaptureFailures += max(count, 1)
        guard let previous else {
            captureFailure = error
            return
        }
        captureFailure = CaptureAlertError(message: "\(unacknowledgedCaptureFailures) 張照片未儲存",
                                           showsSettingsAction: error.showsSettingsAction || previous.showsSettingsAction)
    }

    func dismissCaptureFailure() {
        captureFailure = nil
        unacknowledgedCaptureFailures = 0
    }

    /// Dismisses the one-time data-recovery alert (15.1).
    func dismissCorruptionRecoveredAlert() {
        showsCorruptionRecoveredAlert = false
    }

    /// Starts following library changes so counts stay current.
    func startObservingLibrary() {
        guard changesTask == nil else { return }
        let changes = library.changes()
        changesTask = Task { [weak self] in
            for await _ in changes {
                self?.libraryRevision += 1
            }
        }
    }

    /// Re-reads counts, e.g. when the list appears again.
    func reloadLibrary() {
        libraryRevision += 1
    }

    /// Launch, the list appearing and the app returning to the foreground
    /// (e.g. from Settings): re-reads counts and backfills albums if access
    /// is full. Only reads the status, never asks (§7.1).
    func sceneDidBecomeActive() {
        reloadLibrary()
        Task { await backfillAlbumsIfNeeded() }
    }

    // MARK: - Rows

    /// Records newest-modified first (FR-16.5).
    var rows: [Row] {
        _ = libraryRevision
        return sortedProfiles.map { Row(id: $0.id, name: $0.name, subtitle: subtitle(for: $0)) }
    }

    var sortedProfiles: [CameraProfile] {
        profiles.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// "今天第 N 天 · M 張" (FR-16.2).
    func subtitle(for profile: CameraProfile) -> String {
        let count = library.photoCount(albumIdentifier: profile.albumIdentifier,
                                       fallbackIDs: profile.fallbackAssetIDs)
        let countText = count.map { "\($0) 張" } ?? Self.unknownCountText
        return "\(dayCountText(for: profile)) · \(countText)"
    }

    /// Today's elapsed amount in the record's own units and wording; a start
    /// date still ahead reads as the countdown without "今天" (FR-16.3).
    func dayCountText(for profile: CameraProfile) -> String {
        Self.dayCountText(for: profile, renderer: renderer, calculator: calculator)
    }

    /// The same line for any screen that lists records, such as the
    /// camera's record switcher (FR-20.8).
    static func dayCountText(for profile: CameraProfile, renderer: TemplateRenderer,
                             calculator: DayCountCalculator) -> String {
        var elapsedOnly = profile
        elapsedOnly.showDayCount = true
        elapsedOnly.showDate = false
        elapsedOnly.showName = false
        let text = renderer.render(profile: elapsedOnly, capturedAt: calculator.now(),
                                   calendar: calculator.calendar, moment: .today)
        return calculator.rawDayDifference(from: profile.startDate) < 0 ? text : "今天\(text)"
    }

    func profile(id: UUID) -> CameraProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: - Deleting

    var canDelete: Bool { profiles.count > 1 }

    /// Arms the delete confirmation; a no-op with one record left.
    func requestDeletion(of id: UUID) {
        guard canDelete, let profile = profile(id: id) else { return }
        deletionCandidate = profile
    }

    func cancelDeletion() {
        deletionCandidate = nil
    }

    /// Deletes the armed record. The album and its photos are untouched.
    /// Deleting from the record's own photo wall returns to the list.
    func confirmDeletion() {
        guard let candidate = deletionCandidate else { return }
        deletionCandidate = nil
        do {
            try store.delete(id: candidate.id)
            if path.contains(where: { $0.recordID == candidate.id }) { path = [] }
        } catch {
            lastError = error
        }
    }

    // MARK: - Editor

    /// Opens `id`'s editor from the list.
    func edit(id: UUID) {
        path = [.editor(id)]
    }

    /// Opens `id`'s photo wall (FR-17).
    func openWall(id: UUID) {
        path = [.wall(id)]
    }

    /// The camera opened from `openedID`'s wall has closed with `selectedID`
    /// picked in its record switcher (FR-20.11). A different record becomes
    /// the selected one and its photo wall replaces the old one, so back
    /// leads to the list. Returns whether the wall changed; when it did not,
    /// the caller re-reads its own wall.
    @discardableResult
    func cameraDidClose(openedFrom openedID: UUID, selected selectedID: UUID) -> Bool {
        guard selectedID != openedID, profile(id: selectedID) != nil else { return false }
        store.select(id: selectedID)
        path = [.wall(selectedID)]
        return true
    }

    /// Opens `id`'s editor on top of its photo wall (FR-17.9).
    func editFromWall(id: UUID) {
        path.append(.editor(id))
    }

    /// The wall's model for `id`; `resolveFont` is the batch export's font path.
    func photoWallModel(for id: UUID,
                        resolveFont: @escaping @MainActor (OverlayStyle) -> ResolvedOverlayFont) -> PhotoWallModel {
        PhotoWallModel(profileID: id, store: store, library: library, calendar: calendar,
                       saveCoordinator: saveCoordinator,
                       todayText: { [weak self] profile in self?.dayCountText(for: profile) ?? "" },
                       backfillAlbums: { [weak self] in await self?.backfillAlbumsIfNeeded(reportsFailure: true) },
                       makeBatchExport: { [store, library, calendar, renderer, exportSave] photos in
                           let pipeline = PhotoExportPipeline(library: library, calendar: calendar,
                                                              renderer: renderer, save: exportSave)
                           return BatchExportModel(photos: photos, profileID: id, store: store, library: library,
                                                   calendar: calendar, renderer: renderer, resolveFont: resolveFont,
                                                   export: BatchExportModel.pipelineExport(pipeline, resolveFont: resolveFont))
                       })
    }

    /// The viewer's model, opened on `photoID` of record `id` (#619).
    func photoDetailModel(for id: UUID, startingAt photoID: String,
                          resolveFont: @escaping @MainActor (OverlayStyle) -> ResolvedOverlayFont) -> PhotoDetailModel {
        PhotoDetailModel(profileID: id, startingAt: photoID, store: store, library: library,
                         calendar: calendar, renderer: renderer, resolveFont: resolveFont,
                         pipeline: PhotoExportPipeline(library: library, calendar: calendar,
                                                       renderer: renderer, save: exportSave))
    }

    /// The 文字樣式 page's model for `photo` of record `id` (#620): the panel
    /// edits the record through the app's shared font path (`styleCenter`).
    func exportModel(for id: UUID, photo: RecordPhoto, styleCenter: StyleEditingCenter) -> ExportModel {
        let fontLibrary = styleCenter.fontLibrary
        return ExportModel(profileID: id, photo: photo, store: store, library: library,
                           editor: styleCenter.makeStyleEditor(for: id),
                           calendar: calendar, renderer: renderer,
                           resolveFont: { style in OverlayMetrics.resolvedFont(for: style, availability: fontLibrary) },
                           fontChanges: fontLibrary.objectWillChange)
    }

    var canAdd: Bool { profiles.count < ProfileStore.profileLimit }

    /// Creates a default record and pushes its editor, name empty (FR-21.2).
    ///
    /// Only style and position are inherited from the current record
    /// (FR-1.9, #484). The record exists in the store while the editor is up
    /// so the shared rules form can write to it; leaving by back deletes it,
    /// `confirmNewRecord()` keeps it.
    func addRecord() {
        guard canAdd else {
            lastError = ProfileStoreError.limitReached(limit: ProfileStore.profileLimit)
            return
        }
        var newProfile = CameraProfile(name: store.uniqueName(base: Self.newRecordPlaceholder),
                                       startDate: calculator.currentDateComponents(),
                                       showName: true)
        if let template = profile(id: store.selectedProfileID) {
            newProfile.position = template.position
            newProfile.style = template.style
        }
        let previousSelectedID = store.selectedProfileID
        do {
            let added = try store.add(newProfile)
            draftID = added.id
            draftPreviousSelectedID = previousSelectedID
            path = [.editor(added.id)]
        } catch {
            lastError = error
        }
    }

    private var draftPreviousSelectedID: UUID?

    private func profile(id: UUID?) -> CameraProfile? {
        guard let id else { return nil }
        return profile(id: id)
    }

    /// Whether `id` is the new record nobody has confirmed yet.
    func isDraft(_ id: UUID) -> Bool {
        draftID == id
    }

    /// The checkmark: keeps the new record and opens its photo wall in place
    /// of the editor (FR-21.2). With full access and no album picked, the
    /// record's album is created now (FR-21.6); `albumCreation` finishes
    /// when that is done. A failure leaves `albumIdentifier` `nil` for the
    /// next backfill and sets `lastError`.
    @discardableResult
    func confirmNewRecord() -> UUID? {
        guard let id = draftID else { return nil }
        draftID = nil
        path = [.wall(id)]
        albumCreation = Task { await createAlbumIfUnbound(for: id, reportsFailure: true) }
        return id
    }

    /// The album creation started by the last `confirmNewRecord()`, for tests.
    private(set) var albumCreation: Task<Void, Never>?

    private func discardDraft() {
        guard let id = draftID else { return }
        draftID = nil
        try? store.delete(id: id)
        if let previous = draftPreviousSelectedID, profiles.contains(where: { $0.id == previous }) {
            store.select(id: previous)
        }
    }

    /// A fresh rules model for `profile`'s editor; a draft starts with an
    /// empty name field.
    func rulesModel(for profile: CameraProfile) -> RulesTabModel {
        let model = makeRulesModel(profile)
        if isDraft(profile.id) { model.beginUntitled(placeholder: Self.newRecordPlaceholder) }
        return model
    }

    // MARK: - Album

    /// Creates an album for every record whose `albumIdentifier` is `nil`
    /// (made before access was granted, or migrated) and stores it (FR-21.6).
    ///
    /// Full access only; never asks. An album id that no longer resolves is
    /// not `nil` and is left alone. The unconfirmed draft is skipped. Safe to
    /// call from several triggers at once: a record already being created
    /// is skipped. A failed record stays `nil` and is retried next time.
    func backfillAlbumsIfNeeded(reportsFailure: Bool = false) async {
        guard library.authorizationStatus() == .authorized else { return }
        let ids = store.profiles.filter { $0.albumIdentifier == nil }.map(\.id)
        for id in ids {
            await createAlbumIfUnbound(for: id, reportsFailure: reportsFailure)
        }
    }

    /// Creates and binds `id`'s album unless it is a draft, already bound,
    /// already being created, or access is not full.
    private func createAlbumIfUnbound(for id: UUID, reportsFailure: Bool) async {
        guard library.authorizationStatus() == .authorized, id != draftID,
              store.profiles.first(where: { $0.id == id })?.albumIdentifier == nil else { return }
        do {
            try await createAndBindAlbum(for: id)
        } catch {
            if reportsFailure { lastError = error }
        }
    }

    /// Creates an album titled by `id`'s current name and binds it, reading
    /// the store's latest profile so no other field is overwritten.
    ///
    /// Runs in `saveCoordinator`'s queue, so a camera save or "加入照片" for
    /// the record waits for it and uses the album it stored, and it waits
    /// for them. The binding at the time of the request must still be there
    /// when the queue reaches it and when the album is made: an album bound
    /// meanwhile (a write before it in the queue, or a newer pick in the
    /// album picker) wins, and nothing is created or overwritten. Returns
    /// without creating when `id` is already queued here.
    private func createAndBindAlbum(for id: UUID) async throws {
        guard let requested = store.profiles.first(where: { $0.id == id }),
              albumCreationsInFlight.insert(id).inserted else { return }
        defer { albumCreationsInFlight.remove(id) }
        let bindingAtRequest = requested.albumIdentifier
        try await saveCoordinator.serialized {
            guard library.authorizationStatus() == .authorized,
                  let current = store.profiles.first(where: { $0.id == id }),
                  current.albumIdentifier == bindingAtRequest else { return }
            let albumID: String
            if let leftOver = unboundCreatedAlbums[id], library.userAlbums().contains(where: { $0.id == leftOver }) {
                albumID = leftOver
            } else {
                albumID = try await library.createAlbum(title: current.name)
            }
            unboundCreatedAlbums[id] = nil
            guard var latest = store.profiles.first(where: { $0.id == id }),
                  latest.albumIdentifier == bindingAtRequest else { return }
            latest.albumIdentifier = albumID
            do {
                try store.updateAndWait(latest)
            } catch {
                unboundCreatedAlbums[id] = albumID
                throw error
            }
        }
    }

    /// Text of the "建立新相簿" row and option for `name` (FR-21.4).
    static func createAlbumTitle(forRecordNamed name: String) -> String {
        "建立新相簿「\(name)」"
    }

    /// What the editor's 相簿 row shows for `profile`.
    func albumRowState(for profile: CameraProfile) -> AlbumRowState {
        _ = libraryRevision
        switch library.authorizationStatus() {
        case .notDetermined:
            return .notAsked(title: "建立時會在「照片」App 建立「\(profile.name)」")
        case .limited:
            return .needsSettings(title: "只允許部分照片時無法選相簿")
        case .denied, .restricted:
            return .needsSettings(title: "需要「照片」權限")
        default:
            let bound = library.userAlbums().first { $0.id == profile.albumIdentifier }
            return .available(title: bound?.title ?? Self.createAlbumTitle(forRecordNamed: profile.name))
        }
    }

    /// Opens the app's Settings page (the editor's 相簿 row, FR-21.4).
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openSettings(url)
    }

    /// Delete confirmation text for `profile` (FR-16.5).
    func deletionMessage(for profile: CameraProfile) -> String {
        if let bound = library.userAlbums().first(where: { $0.id == profile.albumIdentifier }) {
            return "「照片」App 裡的「\(bound.title)」相簿和照片都會保留。"
        }
        return Self.deletionMessageWithoutAlbum
    }

    /// One line under the list, by photo access (FR-16.6); `nil` when denied
    /// or restricted.
    var footerText: String? {
        _ = libraryRevision
        switch library.authorizationStatus() {
        case .authorized, .notDetermined:
            return "每個紀錄是「照片」App 裡的一本相簿，在那裡加入的照片會自動出現"
        case .limited:
            return "目前沒有開放完整權限，紀錄不會和原生相簿同步"
        default:
            return nil
        }
    }

    /// The picker's model for `id`.
    func albumPickerModel(for id: UUID) -> AlbumPickerModel {
        AlbumPickerModel(profileID: id, store: store, library: library,
                         isDraft: { self.isDraft(id) },
                         createAlbum: { try await self.createAndBindAlbum(for: id) })
    }
}

/// Drives the album picker of one record (PRD 2.0 FR-21.4, FR-21.5).
@MainActor
final class AlbumPickerModel: ObservableObject {
    /// One selectable row. `id == nil` is "建立新相簿".
    struct Option: Identifiable, Equatable {
        let id: String?
        let title: String
        /// `nil` for the "建立新相簿" row.
        let photoCount: Int?
        /// Name of another record already bound to this album.
        let usedBy: String?
        let isSelected: Bool

        /// Grey line under the title: "M 張" and who uses the album.
        var detail: String? {
            var parts: [String] = []
            if let photoCount { parts.append("\(photoCount) 張") }
            if let usedBy { parts.append("已被「\(usedBy)」使用") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    let profileID: UUID
    @Published private(set) var status: PHAuthorizationStatus
    @Published private(set) var albums: [AlbumSummary] = []
    @Published var lastError: Error?

    private let store: ProfileStore
    private let library: any RecordAlbumLibrary
    private let isDraft: () -> Bool
    private let createAlbum: () async throws -> Void
    private var subscription: AnyCancellable?

    /// - Parameter isDraft: whether the record is a new one not yet created
    ///   by the checkmark; its album waits for the checkmark (FR-21.6).
    /// - Parameter createAlbum: creates an album for the record and binds
    ///   it (the "建立新相簿" row under full access).
    init(profileID: UUID, store: ProfileStore, library: any RecordAlbumLibrary,
         isDraft: @escaping () -> Bool = { false },
         createAlbum: @escaping () async throws -> Void) {
        self.profileID = profileID
        self.store = store
        self.library = library
        self.isDraft = isDraft
        self.createAlbum = createAlbum
        self.status = library.authorizationStatus()
        // Selection and "used by" follow the store.
        subscription = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    /// Lists the albums. Never asks for access: that only happens on the
    /// photo wall's permission intro (§7.1, FR-21.4).
    func load() async {
        status = library.authorizationStatus()
        albums = library.userAlbums()
    }

    var profile: CameraProfile? {
        store.profiles.first { $0.id == profileID }
    }

    var createTitle: String {
        RecordListModel.createAlbumTitle(forRecordNamed: profile?.name ?? "")
    }

    /// "建立新相簿" first, then the user's albums in the Photos app's order.
    var options: [Option] {
        let bound = profile?.albumIdentifier
        let boundExists = albums.contains { $0.id == bound }
        var result = [Option(id: nil, title: createTitle, photoCount: nil, usedBy: nil,
                             isSelected: bound == nil || !boundExists)]
        for album in albums {
            let other = store.profiles.first { $0.id != profileID && $0.albumIdentifier == album.id }
            result.append(Option(id: album.id, title: album.title, photoCount: album.photoCount,
                                 usedBy: other?.name, isSelected: album.id == bound))
        }
        return result
    }

    /// Binds the record to `albumIdentifier`. `nil` is "建立新相簿": under
    /// full access a new album is created and bound right away (FR-21.4),
    /// except for a draft, which only clears the binding so the checkmark
    /// creates it (FR-21.6); otherwise the record is left to create one
    /// later. A pick made while that album is still being created wins over
    /// it. The album bound before is not deleted and `fallbackAssetIDs` is
    /// left alone (FR-21.5).
    func select(albumIdentifier: String?) async {
        if albumIdentifier == nil, library.authorizationStatus() == .authorized, !isDraft() {
            do {
                try await createAlbum()
                albums = library.userAlbums()
            } catch {
                lastError = error
            }
            return
        }
        guard var latest = profile, latest.albumIdentifier != albumIdentifier else { return }
        latest.albumIdentifier = albumIdentifier
        do {
            try store.updateAndWait(latest)
        } catch {
            lastError = error
        }
    }
}
