import Combine
import Foundation

/// Drives PRD 0.2 FR-9, the management panel (S-6): switching, reordering,
/// duplicating, deleting and adding profiles.
///
/// Holds the real `ProfileStore` and mirrors its published state; every
/// action forwards to the store, which persists immediately. What the store
/// does not decide lives here: which row to land on after deleting the
/// current profile (acceptance 26.6), and the disabled-state wording of
/// FR-9.7 and FR-9.10.
@MainActor
final class ProfileManagerModel: ObservableObject {
    /// One row of the list (PRD FR-9.2): name and start-date subtitle only,
    /// no overlay preview.
    struct Row: Identifiable, Equatable {
        let id: UUID
        let name: String
        /// "yyyy/MM/dd 起", or "只顯示日期" when the day count is off.
        let subtitle: String
        let isCurrent: Bool
    }

    /// Maximum number of profiles (FR-9.10, same as FR-1.7).
    static let profileLimit = ProfileStore.profileLimit

    /// The profiles in list order, mirrored from the store.
    @Published private(set) var profiles: [CameraProfile]
    /// The profile the camera currently uses, mirrored from the store.
    @Published private(set) var selectedProfileID: UUID?
    /// Non-nil while the delete confirmation (FR-9.6) should show.
    @Published private(set) var deletionCandidate: CameraProfile?
    /// The latest failed action, for the view to surface.
    @Published var lastError: Error?

    private let store: ProfileStore
    private let calculator: DayCountCalculator
    private let onProfileAdded: () -> Void
    private var subscriptions = Set<AnyCancellable>()

    /// Creates a model over `store`.
    ///
    /// - Parameter onProfileAdded: Called after "新增設定檔" succeeded and the
    ///   new profile is selected; the caller closes this panel and switches
    ///   the overlay panel to 天數規則 (FR-9.8).
    init(store: ProfileStore,
         calculator: DayCountCalculator = DayCountCalculator(),
         onProfileAdded: @escaping () -> Void = {}) {
        self.store = store
        self.calculator = calculator
        self.onProfileAdded = onProfileAdded
        self.profiles = store.profiles
        self.selectedProfileID = store.selectedProfileID
        store.$profiles
            .dropFirst()
            .sink { [weak self] in self?.profiles = $0 }
            .store(in: &subscriptions)
        store.$selectedProfileID
            .dropFirst()
            .sink { [weak self] in self?.selectedProfileID = $0 }
            .store(in: &subscriptions)
    }

    // MARK: - Rows

    var rows: [Row] {
        profiles.map { profile in
            Row(id: profile.id,
                name: profile.name,
                subtitle: Self.subtitle(for: profile),
                isCurrent: profile.id == selectedProfileID)
        }
    }

    /// FR-9.2's subtitle.
    static func subtitle(for profile: CameraProfile) -> String {
        guard profile.showDayCount else { return "只顯示日期" }
        let year = profile.startDate.year ?? 0
        let month = profile.startDate.month ?? 0
        let day = profile.startDate.day ?? 0
        return String(format: "%04d/%02d/%02d 起", year, month, day)
    }

    // MARK: - Limits (FR-9.7, FR-9.10)

    var canAdd: Bool { profiles.count < Self.profileLimit }
    var addTitle: String { canAdd ? "新增設定檔" : "已達 \(Self.profileLimit) 個上限" }

    var canDuplicate: Bool { canAdd }
    var duplicateTitle: String { canDuplicate ? "複製" : "複製（已達 \(Self.profileLimit) 個）" }

    var canDelete: Bool { profiles.count > 1 }
    var deleteTitle: String { canDelete ? "刪除" : "刪除（至少保留 1 個）" }

    // MARK: - Actions

    /// Switches to `id` without closing the panel (FR-9.3).
    func select(id: UUID) {
        store.select(id: id)
    }

    /// Reorders and persists immediately (FR-9.4).
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        do {
            try store.move(fromOffsets: source, toOffset: destination)
        } catch {
            lastError = error
        }
    }

    /// Inserts "{原名} 副本" below `id` without switching to it (FR-9.5, A-3).
    func duplicate(id: UUID) {
        guard canDuplicate else { return }
        do {
            try store.duplicate(id: id)
        } catch {
            lastError = error
        }
    }

    /// Creates a default profile, selects it and reports through
    /// `onProfileAdded` (FR-9.8, FR-9.9).
    func addProfile() {
        guard canAdd else { return }
        let profile = CameraProfile(name: store.uniqueName(base: "新設定檔"),
                                    startDate: calculator.currentDateComponents())
        do {
            try store.add(profile)
        } catch {
            lastError = error
            return
        }
        onProfileAdded()
    }

    /// Arms the delete confirmation; a no-op with one profile left.
    func requestDeletion(of id: UUID) {
        guard canDelete, let profile = profiles.first(where: { $0.id == id }) else { return }
        deletionCandidate = profile
    }

    func cancelDeletion() {
        deletionCandidate = nil
    }

    /// Deletes the armed profile. When it was the current one, the previous
    /// row becomes current, or the next one if there was none (acceptance 26.6).
    func confirmDeletion() {
        guard let candidate = deletionCandidate else { return }
        deletionCandidate = nil
        let index = profiles.firstIndex { $0.id == candidate.id }
        let wasCurrent = candidate.id == selectedProfileID
        do {
            try store.delete(id: candidate.id)
        } catch {
            lastError = error
            return
        }
        if wasCurrent, let index, !profiles.isEmpty {
            store.select(id: profiles[max(0, index - 1)].id)
        }
    }
}
