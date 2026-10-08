import Combine
import Foundation

/// Drives the 設定檔 sheet (#226 R-1～R-8, R-10; PRD 0.2 FR-9 as reshaped for
/// 0.4): switching, reordering, duplicating, deleting and adding profiles,
/// plus the navigation into a profile's edit page.
///
/// Holds the real `ProfileStore` and mirrors its published state; every
/// action forwards to the store, which persists immediately. What the store
/// does not decide lives here: which row to land on after deleting the
/// current profile (acceptance 26.6), and the disabled-state wording of
/// FR-9.7 and FR-9.10.
@MainActor
final class ProfileManagerModel: ObservableObject {
    /// One row of the list (#226 R-2): name and subtitle only, no overlay
    /// preview.
    struct Row: Identifiable, Equatable {
        let id: UUID
        let name: String
        /// "yyyy/MM/dd 起・今天第 N 天".
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
    /// The profile ids pushed onto the sheet's navigation stack: empty on the
    /// list, one id on that profile's edit page (R-4, R-7).
    @Published var path: [UUID] = []
    /// The profile just created by "新增設定檔", whose edit page focuses and
    /// selects the name field (R-7). Cleared by `resetNavigation()`.
    @Published private(set) var newlyAddedProfileID: UUID?

    private let store: ProfileStore
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer
    private let makeRulesModel: (CameraProfile) -> RulesTabModel
    private var subscriptions = Set<AnyCancellable>()

    /// Creates a model over `store`.
    ///
    /// - Parameter makeRulesModel: Builds the edit page's `RulesTabModel` for
    ///   one profile. The caller routes its `updateProfile` through a
    ///   `TabProfileWriter` so a write never overwrites fields another tab
    ///   just changed (#70). The default writes straight to `store`, which is
    ///   only fit for previews and tests.
    init(store: ProfileStore,
         calculator: DayCountCalculator = DayCountCalculator(),
         renderer: TemplateRenderer = TemplateRenderer(),
         makeRulesModel: ((CameraProfile) -> RulesTabModel)? = nil) {
        self.store = store
        self.calculator = calculator
        self.renderer = renderer
        self.makeRulesModel = makeRulesModel ?? { profile in
            RulesTabModel(profile: profile, calculator: calculator, renderer: renderer) {
                try store.update($0)
            }
        }
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
                subtitle: subtitle(for: profile),
                isCurrent: profile.id == selectedProfileID)
        }
    }

    /// R-2's subtitle: the start date and today's day count under the
    /// profile's own counting rule, formatted like the overlay with only 天
    /// ticked (R-13: the count is always shown).
    func subtitle(for profile: CameraProfile) -> String {
        let year = profile.startDate.year ?? 0
        let month = profile.startDate.month ?? 0
        let day = profile.startDate.day ?? 0
        let date = String(format: "%04d/%02d/%02d", year, month, day)
        return "\(date) 起・今天\(dayCountText(for: profile))"
    }

    private func dayCountText(for profile: CameraProfile) -> String {
        var daysOnly = profile
        daysOnly.showDayCount = true
        daysOnly.showDate = false
        daysOnly.showName = false
        daysOnly.displayUnits = [.day]
        daysOnly.useAgeWording = false
        return renderer.render(profile: daysOnly, capturedAt: calculator.now(), calendar: calculator.calendar)
    }

    // MARK: - Edit page

    /// The profile `id` as the store holds it now, for the edit page's title.
    func profile(id: UUID) -> CameraProfile? {
        profiles.first { $0.id == id }
    }

    /// Whether `id`'s edit page should focus the name field on appear (R-7).
    func focusesName(of id: UUID) -> Bool {
        id == newlyAddedProfileID
    }

    /// A fresh rules model for `profile`'s edit page.
    func rulesModel(for profile: CameraProfile) -> RulesTabModel {
        makeRulesModel(profile)
    }

    /// Opens `id`'s edit page without switching to it (R-4).
    func edit(id: UUID) {
        path = [id]
    }

    /// Back to the list, e.g. after duplicating or deleting from the edit
    /// page (R-10), and forgets the "just added" focus request.
    func resetNavigation() {
        path = []
        newlyAddedProfileID = nil
    }

    // MARK: - Limits (FR-9.7, FR-9.10)

    var canAdd: Bool { profiles.count < Self.profileLimit }
    var addTitle: String { canAdd ? "新增設定檔" : "已達 \(Self.profileLimit) 個上限" }

    var canDuplicate: Bool { canAdd }
    var duplicateTitle: String { canDuplicate ? "複製" : "複製（已達 \(Self.profileLimit) 個）" }

    var canDelete: Bool { profiles.count > 1 }
    var deleteTitle: String { canDelete ? "刪除" : "刪除（至少保留 1 個）" }

    // MARK: - Actions

    /// Switches to `id` (R-3); the view closes the sheet afterwards.
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

    /// Moves the profile `id` so it lands at insertion `index` of the
    /// current list (long-press drag and drop, R-5).
    func move(id: UUID, toIndex index: Int) {
        guard let from = profiles.firstIndex(where: { $0.id == id }) else { return }
        move(fromOffsets: IndexSet(integer: from), toOffset: min(max(index, 0), profiles.count))
    }

    /// Where a row dragged by `translation` points lands, as an index in the
    /// final list (TASK-58, R-5). The row moves one slot each time its
    /// center crosses half a row, so the threshold is half a row height;
    /// clamped to the list. `rowHeight <= 0` means "not measured yet".
    static func dragTargetIndex(from index: Int, translation: CGFloat, rowHeight: CGFloat, count: Int) -> Int {
        guard count > 0, rowHeight > 0 else { return index }
        let slots = Int((translation / rowHeight).rounded(.toNearestOrAwayFromZero))
        return min(max(index + slots, 0), count - 1)
    }

    /// Moves `id` so it ends at `finalIndex` of the list (the destination
    /// the drag showed), translating to `move(id:toIndex:)`'s insertion
    /// semantics.
    func move(id: UUID, toFinalIndex finalIndex: Int) {
        guard let from = profiles.firstIndex(where: { $0.id == id }), finalIndex != from else { return }
        move(id: id, toIndex: finalIndex > from ? finalIndex + 1 : finalIndex)
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

    /// Creates a default profile, selects it and pushes its edit page with
    /// the name field focused (R-7; creation rules FR-9.8 first half, FR-9.9).
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
        newlyAddedProfileID = profile.id
        path = [profile.id]
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
        // Deleting from the edit page lands back on the list (R-10).
        path = []
        if wasCurrent, let index, !profiles.isEmpty {
            store.select(id: profiles[max(0, index - 1)].id)
        }
    }
}
