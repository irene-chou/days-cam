import Foundation

/// Drives PRD S-2, the profile list screen: selection, creation, deletion
/// and the sheet that presents `ProfileEditModel` (FR-1.1–FR-1.10).
///
/// Deliberately does not depend on `ProfileStore`'s concrete type — it holds
/// a snapshot of `profiles`/`selectedProfileID` plus action closures the
/// caller supplies, so it is constructible and unit-testable without a real
/// persistence layer. The caller is expected to keep the snapshot current by
/// setting `profiles`/`selectedProfileID` whenever the underlying store
/// publishes a change (e.g. from a `Combine` subscription set up where this
/// model is created).
@MainActor
final class ProfileListModel: ObservableObject {
    /// Which screen `presentedEditor` is showing, and with what starting data.
    enum EditorPresentation: Identifiable {
        case create(CameraProfile)
        case edit(CameraProfile)

        var id: UUID {
            switch self {
            case let .create(profile): return profile.id
            case let .edit(profile): return profile.id
            }
        }

        var profile: CameraProfile {
            switch self {
            case let .create(profile): return profile
            case let .edit(profile): return profile
            }
        }

        var mode: ProfileEditModel.Mode {
            switch self {
            case .create: return .create
            case .edit: return .edit
            }
        }
    }

    /// Maximum number of profiles a user may keep (FR-1.7).
    static let profileLimit = 20

    /// The current profiles, in list order. The caller keeps this current.
    @Published var profiles: [CameraProfile]
    /// The id of the profile currently applied to the camera screen.
    @Published var selectedProfileID: UUID?
    /// Non-nil while the create/edit sheet should be shown.
    @Published private(set) var presentedEditor: EditorPresentation?
    /// Non-nil while the delete confirmation alert should be shown.
    @Published private(set) var deletionCandidate: CameraProfile?
    /// The most recent action's failure, if any, for the view to surface.
    @Published var lastError: Error?

    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let addProfile: (CameraProfile) throws -> Void
    private let updateProfile: (CameraProfile) throws -> Void
    private let deleteProfile: (UUID) throws -> Void
    private let selectProfile: (UUID) -> Void

    /// Creates a list model.
    ///
    /// - Parameters:
    ///   - calculator: Supplies "today" for a new profile's default start
    ///     date (FR-1.9). Defaults to `DayCountCalculator()`, whose default
    ///     clock honours `DAYSCAM_FAKE_TODAY` in debug builds.
    ///   - addProfile/updateProfile/deleteProfile/selectProfile: Forwarded to
    ///     the real persistence layer by the caller. Each throws to report a
    ///     failure (over the limit, invalid profile, last profile left); this
    ///     model does not interpret the error, it only surfaces it.
    init(profiles: [CameraProfile],
         selectedProfileID: UUID?,
         calendar: Calendar = .current,
         calculator: DayCountCalculator = DayCountCalculator(),
         addProfile: @escaping (CameraProfile) throws -> Void,
         updateProfile: @escaping (CameraProfile) throws -> Void,
         deleteProfile: @escaping (UUID) throws -> Void,
         selectProfile: @escaping (UUID) -> Void) {
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
        self.calendar = calendar
        self.calculator = calculator
        self.addProfile = addProfile
        self.updateProfile = updateProfile
        self.deleteProfile = deleteProfile
        self.selectProfile = selectProfile
    }

    /// Whether "add" should be disabled, with an explanatory string to show
    /// alongside it (FR-1.7).
    var isAtProfileLimit: Bool {
        profiles.count >= Self.profileLimit
    }

    var profileLimitMessage: String {
        "已達上限 \(Self.profileLimit) 個設定檔"
    }

    /// Whether delete should be disabled — at least one profile must always
    /// remain (FR-1.8).
    var canDeleteProfiles: Bool {
        profiles.count > 1
    }

    var lastProfileMessage: String {
        "至少需要保留一個設定檔"
    }

    /// Selects `id` as the profile the camera screen uses.
    func select(id: UUID) {
        selectProfile(id)
    }

    /// Opens the sheet to create a new profile, defaulted per FR-1.9.
    func beginCreatingProfile() {
        guard !isAtProfileLimit else { return }
        let today = calculator.currentDateComponents()
        presentedEditor = .create(CameraProfile(name: "", startDate: today))
    }

    /// Opens the sheet to edit an existing profile.
    func beginEditing(_ profile: CameraProfile) {
        presentedEditor = .edit(profile)
    }

    func dismissEditor() {
        presentedEditor = nil
    }

    /// Builds the edit model for whatever `presentedEditor` currently is.
    ///
    /// A new profile is added then immediately selected, satisfying "building
    /// a profile switches to it" (FR-1.10) without needing the store to hand
    /// the new id back — `CameraProfile.id` is generated client-side at
    /// construction, so it is already known before `addProfile` is called.
    func makeEditModel(for presentation: EditorPresentation) -> ProfileEditModel {
        switch presentation {
        case let .create(draft):
            return ProfileEditModel(profile: draft, mode: .create, calendar: calendar, calculator: calculator) { [weak self] saved in
                try self?.addProfile(saved)
                self?.selectProfile(saved.id)
                self?.presentedEditor = nil
            }
        case let .edit(existing):
            return ProfileEditModel(profile: existing, mode: .edit, calendar: calendar, calculator: calculator) { [weak self] saved in
                try self?.updateProfile(saved)
                self?.presentedEditor = nil
            }
        }
    }

    /// Arms the delete-confirmation alert for `profile` (FR-1.3). A no-op
    /// while only one profile remains (FR-1.8) — the delete affordance is
    /// disabled in that state, this is the defensive backstop.
    func requestDeletion(of profile: CameraProfile) {
        guard canDeleteProfiles else { return }
        deletionCandidate = profile
    }

    func cancelDeletion() {
        deletionCandidate = nil
    }

    /// Deletes the profile armed by `requestDeletion(of:)`.
    func confirmDeletion() {
        guard let candidate = deletionCandidate else { return }
        do {
            try deleteProfile(candidate.id)
        } catch {
            lastError = error
        }
        deletionCandidate = nil
    }
}
