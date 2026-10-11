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

// MARK: - Display content (0.4 R-13: 日期、名稱)

extension DisplaySettingsModel {
    /// Sets `showDate`. Either display switch may be off, so this never
    /// refuses: the day count is always shown (0.4 R-13, TASK-48).
    func setShowDate(_ newValue: Bool) {
        guard newValue != profile.showDate else { return }
        mutate { $0.showDate = newValue }
    }

    func setShowName(_ newValue: Bool) {
        guard newValue != profile.showName else { return }
        mutate { $0.showName = newValue }
    }
}

// MARK: - Day-count format (FR-2.7–FR-2.10)

extension DisplaySettingsModel {
    /// Checks or unchecks `unit` (PRD 0.2 FR-11.3, TASK-27).
    ///
    /// Unchecking the last remaining unit is a no-op: `displayUnits` may
    /// never be empty. Unchecking the year also turns `useAgeWording` off
    /// (FR-11.4).
    func toggleUnit(_ unit: DisplayUnit) {
        if profile.displayUnits.contains(unit) {
            guard profile.displayUnits.count > 1 else { return }
            mutate { profile in
                profile.displayUnits.remove(unit)
                if unit == .year {
                    profile.useAgeWording = false
                }
            }
        } else {
            mutate { $0.displayUnits.insert(unit) }
        }
    }

    /// Whether `unit`'s checkbox should be disabled: it is the last unit
    /// still checked, so unchecking it would leave `displayUnits` empty
    /// (FR-11.3) — mirrors `toggleUnit`'s own no-op guard, so the view can
    /// show the same rule it enforces.
    func isUnitToggleDisabled(_ unit: DisplayUnit) -> Bool {
        profile.displayUnits.contains(unit) && profile.displayUnits.count == 1
    }

    /// Whether the "歲措辭" toggle should be disabled: it only applies to the
    /// year unit (FR-2.9, 0.2 FR-11.4).
    var isAgeWordingToggleDisabled: Bool {
        !profile.displayUnits.contains(.year)
    }

    /// Sets `useAgeWording`. A no-op while the year is not checked — the
    /// view is expected to disable the toggle in that state already; this is
    /// the defensive backstop (FR-2.9).
    func setUseAgeWording(_ newValue: Bool) {
        guard newValue != profile.useAgeWording else { return }
        guard profile.displayUnits.contains(.year) else { return }
        mutate { $0.useAgeWording = newValue }
    }
}
