import Foundation

/// Drives the overlay panel's 天數規則 (rules) tab: name, start date and
/// counting rule (PRD 0.2 FR-13). Replaces 0.1's separate profile-edit screen
/// (`ProfileEditModel` / PRD S-3) with three inline rows on the panel.
///
/// Follows `DisplaySettingsModel`'s shape: it holds a working copy of one
/// `CameraProfile` and an injected `updateProfile` closure, so it is
/// constructible and unit-testable without a real `ProfileStore` or panel
/// shell (TASK-22 has not landed yet). Every mutating method writes through
/// immediately — there is no separate save step (FR-8.6) — **except** the
/// name field, whose live text can transiently be empty while the user is
/// still editing; see `setName(_:)` and `endEditingName()` (FR-13.2, A-5).
///
/// The validation this reuses is `ProfileEditModel`'s: the 20-character name
/// clamp (FR-1.6) and the "no later than today" start-date bound (0.1 §7.2).
@MainActor
final class RulesTabModel: ObservableObject {
    /// Gray hint under the preview sentence when the day count is off (#226
    /// R-9). The start-date and counting-rule rows stay visible and editable.
    static let dayCountOffHintMessage = "目前不顯示天數，起始日和起算不會出現在照片上"
    /// Label for `CountingRule.dayOne` (FR-13.4). Order matches
    /// `CountingRule.allCases`: this one is listed first.
    static let countingRuleDayOneLabel = "當天算第 1 天"
    /// Label for `CountingRule.dayZero` (FR-13.4).
    static let countingRuleDayZeroLabel = "第 0 天"

    /// The profile as currently configured. Read-only from outside: every
    /// change goes through one of this model's setters so it is always
    /// persisted (FR-8.6), aside from the name field's draft state below.
    @Published private(set) var profile: CameraProfile
    /// The name field's live text (FR-13.2). Distinct from `profile.name`:
    /// every change writes through immediately once it is non-empty, but an
    /// emptied field is held here only, not persisted, until
    /// `endEditingName()` resolves it (A-5).
    @Published private(set) var nameDraft: String
    /// The most recent `updateProfile` failure, if any, for the view to surface.
    @Published var lastError: Error?

    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer
    private let updateProfile: (CameraProfile) throws -> Void

    /// Creates a rules tab model for `profile`.
    ///
    /// - Parameters:
    ///   - calculator: Supplies the start-date picker's upper bound and the
    ///     capture moment `overlayPreviewText` is rendered as of. Defaults to
    ///     `DayCountCalculator()`, whose default clock honours
    ///     `DAYSCAM_FAKE_TODAY` in debug builds.
    ///   - updateProfile: Forwarded to the real persistence layer by the
    ///     caller, called after every non-draft change. Throws to report a
    ///     failure; this model does not interpret the error, it only
    ///     surfaces it.
    init(profile: CameraProfile,
         calendar: Calendar = .autoupdatingCurrent,
         calculator: DayCountCalculator = DayCountCalculator(),
         renderer: TemplateRenderer = TemplateRenderer(),
         updateProfile: @escaping (CameraProfile) throws -> Void) {
        self.profile = profile
        self.nameDraft = profile.name
        self.calendar = calendar
        self.calculator = calculator
        self.renderer = renderer
        self.updateProfile = updateProfile
    }

    /// Pulls in changes another screen made to the same profile while this
    /// model was alive (#167): the model is only rebuilt when the selected
    /// profile changes, so without this the 格式 tab turning 天數 off never
    /// reached `showsCountingFields`.
    ///
    /// Only the fields this tab reads but does not own are taken —
    /// `showDayCount` (格式 tab) and `name` (profile list rename, only when
    /// the field is not mid-edit). `startDate` and `countingRule` are this
    /// tab's own, so its working copy is already current. Does not persist
    /// anything and ignores a profile with a different id.
    func applyExternalChanges(from latest: CameraProfile) {
        guard latest.id == profile.id else { return }
        if latest.showDayCount != profile.showDayCount {
            profile.showDayCount = latest.showDayCount
        }
        if latest.name != profile.name, nameDraft == profile.name {
            profile.name = latest.name
            nameDraft = latest.name
        }
    }

    private func mutate(_ change: (inout CameraProfile) -> Void) {
        change(&profile)
        do {
            try updateProfile(profile)
        } catch {
            lastError = error
        }
    }
}

// MARK: - 名稱 (FR-13.2, A-5)

extension RulesTabModel {
    /// Sets the name field's live text, clamping to
    /// `CameraProfile.maximumNameLength` raw characters as the user types
    /// rather than only at some later validation step (FR-1.6, 25.1) —
    /// mirrors `ProfileEditModel.setName`.
    ///
    /// Writes through immediately once the (untrimmed) value is not entirely
    /// whitespace; a value that trims to empty is kept in `nameDraft` only
    /// (FR-13.2, A-5) — the row is editable inline with no save button, so
    /// there is nowhere else to hold a momentarily-empty name while the user
    /// is still typing. `endEditingName()` is what resolves it once editing
    /// ends.
    func setName(_ newValue: String) {
        let clamped = newValue.count > CameraProfile.maximumNameLength
            ? String(newValue.prefix(CameraProfile.maximumNameLength))
            : newValue
        nameDraft = clamped
        guard !clamped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard clamped != profile.name else { return }
        mutate { $0.name = clamped }
    }

    /// Called when the name field loses focus (view wires this to
    /// `FocusState` and `onSubmit`). Restores `nameDraft` to the last
    /// persisted name if it was left empty or whitespace-only (25.2, A-5);
    /// otherwise a no-op, since `setName` already wrote the value through.
    func endEditingName() {
        guard nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        nameDraft = profile.name
    }
}

// MARK: - 起始日 (FR-13.3)

extension RulesTabModel {
    /// `profile.startDate` as a `Date`, for binding to a `DatePicker`.
    var startDateAsDate: Date {
        calendar.date(from: profile.startDate) ?? calculator.now()
    }

    /// Latest selectable start date: today, never the future (0.1 §7.2's
    /// UI-layer guard). Fake-today aware in debug builds, like `calculator`
    /// (25.3).
    var startDateUpperBound: Date {
        calculator.now()
    }

    /// Sets `profile.startDate` from a `DatePicker`'s selection, keeping only
    /// the calendar day (PRD §4.1 invariant 2 — no time-of-day is stored).
    func setStartDate(_ date: Date) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components != profile.startDate else { return }
        mutate { $0.startDate = components }
    }
}

// MARK: - 起算規則 (FR-13.4)

extension RulesTabModel {
    /// Selects `newValue` and persists.
    func setCountingRule(_ newValue: CountingRule) {
        guard newValue != profile.countingRule else { return }
        mutate { $0.countingRule = newValue }
    }
}

// MARK: - 顯示狀態與預覽 (FR-13.1, #226 R-9)

extension RulesTabModel {
    /// Whether to show the "day count is off" hint (#226 R-9). The
    /// start-date and counting-rule rows are always shown; they only affect
    /// the day-count output, so the hint tells the user they are not on the
    /// photo while that output is off.
    var showsDayCountOffHint: Bool {
        !profile.showDayCount
    }

    /// The overlay text this profile would print right now — exists so a
    /// counting-rule change (25.4) can be checked end-to-end rather than only
    /// as a stored enum value.
    var overlayPreviewText: String {
        renderer.render(profile: profile, capturedAt: calculator.now(), calendar: calendar)
    }
}
