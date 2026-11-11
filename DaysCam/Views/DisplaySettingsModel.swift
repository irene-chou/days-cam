import Foundation

/// Drives PRD S-4, the display settings bottom sheet: display content,
/// day-count format, position and theme (FR-2.4, FR-2.7–FR-2.9, FR-4.1–FR-4.9).
/// Deliberately excludes start date and counting rule — those are the "logic
/// layer" and live on `ProfileEditModel` / PRD S-3 (FR-3.5).
///
/// Deliberately does not depend on `ProfileStore`'s concrete type — it holds
/// a working copy of one `CameraProfile` plus an `updateProfile` closure the
/// caller supplies, so it is constructible and unit-testable without a real
/// persistence layer. Unlike `ProfileEditModel`, there is no explicit save:
/// every mutating method writes through immediately (the panel has no
/// "cancel", per PRD §2.1 — the viewfinder is meant to update live while it
/// is open).
@MainActor
final class DisplaySettingsModel: ObservableObject {
    /// The profile as currently configured. Read-only from outside: every
    /// change goes through one of this model's setters so the FR-2.4/2.8/2.9
    /// invariants stay enforced and every change is persisted.
    @Published private(set) var profile: CameraProfile

    /// The most recent `updateProfile` failure, if any, for the view to surface.
    @Published var lastError: Error?

    private let calendar: Calendar
    private let calculator: DayCountCalculator
    private let renderer: TemplateRenderer
    private let updateProfile: (CameraProfile) throws -> Void

    /// Creates a display settings model for `profile`.
    ///
    /// - Parameters:
    ///   - calculator: Supplies the capture moment `overlayPreviewText` is
    ///     rendered as of. Defaults to `DayCountCalculator()`, whose default
    ///     clock honours `DAYSCAM_FAKE_TODAY` in debug builds.
    ///   - updateProfile: Forwarded to the real persistence layer by the
    ///     caller, called after every change. Throws to report a failure;
    ///     this model does not interpret the error, it only surfaces it.
    init(profile: CameraProfile,
         calendar: Calendar = .autoupdatingCurrent,
         calculator: DayCountCalculator = DayCountCalculator(),
         renderer: TemplateRenderer = TemplateRenderer(),
         updateProfile: @escaping (CameraProfile) throws -> Void) {
        self.profile = profile
        self.calendar = calendar
        self.calculator = calculator
        self.renderer = renderer
        self.updateProfile = updateProfile
    }

    /// The overlay text this profile would print right now, exactly what the
    /// viewfinder shows while the panel is open.
    var overlayPreviewText: String {
        renderer.render(profile: profile, capturedAt: calculator.now(), calendar: calendar)
    }

    private func mutate(_ change: (inout CameraProfile) -> Void) {
        change(&profile)
        do {
            try updateProfile(profile)
        } catch {
            lastError = error
        }
    }

    /// Takes over the store's current record for the same profile when it
    /// changed elsewhere — the edit page's 寫在照片上 switch writes the same
    /// `showName` this tab shows (TASK-109, #423, 109.3). Writes nothing.
    func applyExternalChanges(from latest: CameraProfile) {
        guard latest.id == profile.id, latest != profile else { return }
        profile = latest
    }
}

// MARK: - Display content (天數、日期、名稱; TASK-107 restores the day-count switch)

extension DisplaySettingsModel {
    /// Sets `showDayCount` (TASK-107, #426; FR-11.1). Any of 天數／日期／名稱
    /// may be turned off, all three included (#713).
    func setShowDayCount(_ newValue: Bool) {
        guard newValue != profile.showDayCount else { return }
        mutate { $0.showDayCount = newValue }
    }

    /// Sets `showDate`; symmetric with `setShowDayCount`.
    func setShowDate(_ newValue: Bool) {
        guard newValue != profile.showDate else { return }
        mutate { $0.showDate = newValue }
    }

    /// Whether the day count is off, so the 寫法 has nothing to format. The
    /// view hides the 寫法 row then; `setDayCountFormat` ignores a call as a
    /// backstop (107.4). The units themselves live on `RulesTabModel` (#721).
    var areUnitsInert: Bool { !profile.showDayCount }

    func setShowName(_ newValue: Bool) {
        guard newValue != profile.showName else { return }
        mutate { $0.showName = newValue }
    }

    /// Sets `showOverlay` (#718): the whole text layer. The switches under it,
    /// the style and the position are kept as they are.
    func setShowOverlay(_ newValue: Bool) {
        guard newValue != profile.showOverlay else { return }
        mutate { $0.showOverlay = newValue }
    }

    /// Sets `showFilmDate` (#521). Independent of 天數／日期 — never refused,
    /// and not counted in the "at least one of 天數／日期" rule.
    func setShowFilmDate(_ newValue: Bool) {
        guard newValue != profile.showFilmDate else { return }
        mutate { $0.showFilmDate = newValue }
    }

    /// Sets `filmDateCorner` (#521). Kept while the switch is off, so turning
    /// it back on returns to the same corner.
    func setFilmDateCorner(_ newValue: FilmDateCorner) {
        guard newValue != profile.filmDateCorner else { return }
        mutate { $0.filmDateCorner = newValue }
    }
}

// MARK: - Day-count format (FR-2.7–FR-2.10)

extension DisplaySettingsModel {
    /// Sets how a day-only count is written (#583). Allowed with other units
    /// checked too: the wording is kept and applies once only 天 is checked.
    func setDayCountFormat(_ newValue: DayCountFormat) {
        guard newValue != profile.dayCountFormat else { return }
        guard !areUnitsInert else { return }
        mutate { $0.dayCountFormat = newValue }
    }
}
