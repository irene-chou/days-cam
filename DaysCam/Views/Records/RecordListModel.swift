import Combine
import Foundation
import Photos

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
        /// Access is denied, restricted or limited (FR-21.4).
        case needsPermission
    }

    /// Placeholder shown while a new record's name is still empty.
    static let newRecordPlaceholder = "新紀錄"
    /// Shown in the delete confirmation (FR-16.5).
    static let deletionMessage = "相簿與照片不會被刪除。"
    /// Shown when the library cannot report a count.
    static let unknownCountText = "—"

    /// Every record, in store order; `rows` sorts them.
    @Published private(set) var profiles: [CameraProfile]
    /// Non-nil while the delete confirmation should show.
    @Published private(set) var deletionCandidate: CameraProfile?
    /// The latest failed action, for the view to surface.
    @Published var lastError: Error?
    /// The record ids pushed onto the list's navigation stack: one id is that
    /// record's editor. Leaving a new record's editor by back discards it.
    @Published var path: [UUID] = [] {
        didSet { if path.isEmpty { discardDraft() } }
    }
    /// Bumped to re-read counts and album names when the library changed.
    @Published private(set) var libraryRevision = 0

    let store: ProfileStore
    let library: any RecordAlbumLibrary
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer
    private let makeRulesModel: (CameraProfile) -> RulesTabModel
    /// The record created by "新增紀錄" that the checkmark has not confirmed.
    private var draftID: UUID?
    private var subscriptions = Set<AnyCancellable>()
    private var changesTask: Task<Void, Never>?

    /// Creates a model over `store`.
    ///
    /// - Parameter makeRulesModel: builds the editor's `RulesTabModel`; the
    ///   default routes writes through a `TabProfileWriter` so a rules edit
    ///   never overwrites a field another writer just changed (#70).
    init(store: ProfileStore,
         library: any RecordAlbumLibrary,
         calendar: Calendar = .autoupdatingCurrent,
         calculator: DayCountCalculator? = nil,
         renderer: TemplateRenderer = TemplateRenderer(),
         makeRulesModel: ((CameraProfile) -> RulesTabModel)? = nil) {
        let calculator = calculator ?? DayCountCalculator(calendar: calendar)
        self.store = store
        self.library = library
        self.calculator = calculator
        self.renderer = renderer
        self.makeRulesModel = makeRulesModel ?? { profile in
            let writer = TabProfileWriter(baseline: profile, profileStore: store)
            return RulesTabModel(profile: profile, calendar: calendar, calculator: calculator,
                                 renderer: renderer, updateProfile: writer.write)
        }
        self.profiles = store.profiles
        store.$profiles
            .dropFirst()
            .sink { [weak self] in self?.profiles = $0 }
            .store(in: &subscriptions)
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
    func confirmDeletion() {
        guard let candidate = deletionCandidate else { return }
        deletionCandidate = nil
        do {
            try store.delete(id: candidate.id)
        } catch {
            lastError = error
        }
    }

    // MARK: - Editor

    /// Opens `id`'s editor.
    func edit(id: UUID) {
        path = [id]
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
            path = [added.id]
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

    /// The checkmark: keeps the new record and returns to the list. The
    /// caller then opens the record.
    @discardableResult
    func confirmNewRecord() -> UUID? {
        guard let id = draftID else { return nil }
        draftID = nil
        path = []
        return id
    }

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

    /// Text of the "建立新相簿" row and option for `name` (FR-21.4).
    static func createAlbumTitle(forRecordNamed name: String) -> String {
        "建立新相簿「\(name)」"
    }

    /// What the editor's 相簿 row shows for `profile`.
    func albumRowState(for profile: CameraProfile) -> AlbumRowState {
        _ = libraryRevision
        switch library.authorizationStatus() {
        case .denied, .restricted, .limited:
            return .needsPermission
        default:
            let bound = library.userAlbums().first { $0.id == profile.albumIdentifier }
            return .available(title: bound?.title ?? Self.createAlbumTitle(forRecordNamed: profile.name))
        }
    }

    /// The picker's model for `id`.
    func albumPickerModel(for id: UUID) -> AlbumPickerModel {
        AlbumPickerModel(profileID: id, store: store, library: library)
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
    private var subscription: AnyCancellable?

    init(profileID: UUID, store: ProfileStore, library: any RecordAlbumLibrary) {
        self.profileID = profileID
        self.store = store
        self.library = library
        self.status = library.authorizationStatus()
        // Selection and "used by" follow the store.
        subscription = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    /// Requests access when undecided, then lists the albums. Only called on
    /// opening the picker, never from the list (PRD §7.1).
    func load() async {
        if library.authorizationStatus() == .notDetermined {
            status = await library.requestReadWriteAccess()
        } else {
            status = library.authorizationStatus()
        }
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

    /// Binds the record to `albumIdentifier`, or to a to-be-created album with
    /// `nil`. `fallbackAssetIDs` is left alone (FR-21.5).
    func select(albumIdentifier: String?) {
        guard var latest = profile, latest.albumIdentifier != albumIdentifier else { return }
        latest.albumIdentifier = albumIdentifier
        do {
            try store.updateAndWait(latest)
        } catch {
            lastError = error
        }
    }
}
