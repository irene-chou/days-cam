import Foundation

/// Drives PRD S-3, the profile editing screen: name, start date and counting
/// rule (the "logic layer", FR-3.5), plus the live "今天會顯示為：…" preview.
///
/// Deliberately does not depend on `ProfileStore`'s concrete type. It holds an
/// in-progress `CameraProfile` and an `onSave` closure the caller supplies —
/// for a new profile that closure adds it and switches to it (FR-1.10), for
/// an existing one it updates it. This keeps the model constructible (and
/// unit-testable) without a real persistence layer.
@MainActor
final class ProfileEditModel: ObservableObject {
    /// Whether this screen is creating a brand new profile or editing one
    /// that already exists. Only affects the screen's title and save wording;
    /// the actual persistence behavior lives entirely in `onSave`.
    enum Mode: Equatable {
        case create
        case edit
    }

    /// The profile as currently typed, including states that could not be
    /// saved yet (e.g. an empty name mid-edit).
    @Published var profile: CameraProfile

    let mode: Mode

    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer
    private let onSave: (CameraProfile) throws -> Void

    /// Creates an edit model.
    ///
    /// - Parameters:
    ///   - calculator: Supplies "today" for the start-date picker's upper
    ///     bound and the preview's capture moment. Defaults to
    ///     `DayCountCalculator()`, whose default clock honours
    ///     `DAYSCAM_FAKE_TODAY` in debug builds, so the live preview follows
    ///     the same simulated date the rest of the screen does.
    ///   - onSave: Called with the normalized-or-not profile when the user
    ///     taps save. Throws to report a validation failure; the caller
    ///     (a list-level view model) decides what "add" vs "update" means.
    init(profile: CameraProfile,
         mode: Mode,
         calendar: Calendar = .current,
         calculator: DayCountCalculator = DayCountCalculator(),
         renderer: TemplateRenderer = TemplateRenderer(),
         onSave: @escaping (CameraProfile) throws -> Void) {
        self.profile = profile
        self.mode = mode
        self.calendar = calendar
        self.calculator = calculator
        self.renderer = renderer
        self.onSave = onSave
    }

    /// Sets `profile.name`, clamping to `CameraProfile.maximumNameLength`
    /// characters as the user types rather than only at save time (FR-1.6).
    func setName(_ newValue: String) {
        if newValue.count > CameraProfile.maximumNameLength {
            profile.name = String(newValue.prefix(CameraProfile.maximumNameLength))
        } else {
            profile.name = newValue
        }
    }

    /// `profile.startDate` as a `Date`, for binding to a `DatePicker`.
    var startDateAsDate: Date {
        calendar.date(from: profile.startDate) ?? calculator.now()
    }

    /// Sets `profile.startDate` from a `DatePicker`'s selection, keeping only
    /// the calendar day (PRD §4.1 invariant 2 — no time-of-day is stored).
    func setStartDate(_ date: Date) {
        profile.startDate = calendar.dateComponents([.year, .month, .day], from: date)
    }

    /// Latest selectable start date: today, never the future (PRD §7.2's
    /// UI-layer guard). Fake-today aware in debug builds, like `calculator`.
    var startDateUpperBound: Date {
        calculator.now()
    }

    /// Whether the start-date and counting-rule fields should be shown.
    ///
    /// They only affect the day-count output, so they are hidden once that
    /// output is turned off (FR-3.7) — the profile keeps the values, it just
    /// stops asking the user about them.
    var showsCountingFields: Bool {
        profile.showDayCount
    }

    /// The invariant `profile` currently violates, or nil if it could be
    /// saved as-is (after normalization).
    var validationError: CameraProfileValidationError? {
        do {
            _ = try profile.validatedForPersistence(calendar: calendar)
            return nil
        } catch let error as CameraProfileValidationError {
            return error
        } catch {
            return nil
        }
    }

    /// Whether the save button should be enabled.
    var canSave: Bool {
        validationError == nil
    }

    /// The "今天會顯示為：…" live preview (FR-3.6), reflecting the profile's
    /// in-progress edits as of the current moment.
    var todayPreviewText: String {
        renderer.render(profile: profile, capturedAt: calculator.now(), calendar: calendar)
    }

    /// Saves the current `profile` via `onSave`. Rethrows whatever error the
    /// caller's persistence step raises so the view can surface it.
    func save() throws {
        try onSave(profile)
    }
}
