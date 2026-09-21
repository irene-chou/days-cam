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
    /// Shown next to whichever of "顯示天數"/"顯示日期" is currently the only
    /// one on, and as the reason it is disabled (PRD FR-2.4).
    static let mustShowAtLeastOneMessage = "至少需要顯示天數或日期其中一項"

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
         calendar: Calendar = .current,
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
}

// MARK: - Display content (FR-2.1–FR-2.4)

extension DisplaySettingsModel {
    /// Whether the "顯示天數" toggle should be disabled: it is the only one
    /// of the two still on, so turning it off would leave both off (FR-2.4).
    var isShowDayCountToggleDisabled: Bool {
        profile.showDayCount && !profile.showDate
    }

    /// Whether the "顯示日期" toggle should be disabled, mirroring
    /// `isShowDayCountToggleDisabled`.
    var isShowDateToggleDisabled: Bool {
        profile.showDate && !profile.showDayCount
    }

    /// Sets `showDayCount`. A no-op if this would leave both display
    /// switches off — the view is expected to disable the toggle in that
    /// state already; this is the defensive backstop (FR-2.4).
    func setShowDayCount(_ newValue: Bool) {
        guard newValue != profile.showDayCount else { return }
        guard newValue || profile.showDate else { return }
        mutate { $0.showDayCount = newValue }
    }

    /// Sets `showDate`, mirroring `setShowDayCount`.
    func setShowDate(_ newValue: Bool) {
        guard newValue != profile.showDate else { return }
        guard newValue || profile.showDayCount else { return }
        mutate { $0.showDate = newValue }
    }

    func setShowName(_ newValue: Bool) {
        guard newValue != profile.showName else { return }
        mutate { $0.showName = newValue }
    }
}

// MARK: - Day-count format (FR-2.7–FR-2.10)

extension DisplaySettingsModel {
    /// Whether the whole "天數格式" section should be disabled: it has no
    /// effect while the elapsed amount is not shown at all.
    var isDayCountFormatSectionDisabled: Bool {
        !profile.showDayCount
    }

    /// The smallest-unit options for the current `largestUnit`, in
    /// largest-to-smallest order (PRD §3.2's track table).
    var availableSmallestUnits: [DisplayUnit] {
        DisplayUnitTrack.allowedSmallestUnits(forLargest: profile.largestUnit)
    }

    /// Sets `largestUnit`, clamping `smallestUnit` when it falls off the new
    /// track and turning off `useAgeWording` when the new track is not year.
    ///
    /// Clamp target is `newValue` itself, not the new track's actual smallest
    /// unit: switching largest from year/month to week leaves smallest at
    /// week (i.e. week/week), not week/day — verified against TASK-11
    /// acceptance 11.25/11.26.
    func setLargestUnit(_ newValue: DisplayUnit) {
        guard newValue != profile.largestUnit else { return }
        mutate { profile in
            profile.largestUnit = newValue
            if !DisplayUnitTrack.isLegalPair(largest: newValue, smallest: profile.smallestUnit) {
                profile.smallestUnit = newValue
            }
            if newValue != .year {
                profile.useAgeWording = false
            }
        }
    }

    /// Sets `smallestUnit`. A no-op for a unit not on the current track — the
    /// view is expected to only offer `availableSmallestUnits` (FR-2.8).
    func setSmallestUnit(_ newValue: DisplayUnit) {
        guard newValue != profile.smallestUnit else { return }
        guard DisplayUnitTrack.isLegalPair(largest: profile.largestUnit, smallest: newValue) else { return }
        mutate { $0.smallestUnit = newValue }
    }

    /// Whether the "歲措辭" toggle should be disabled: it only applies to the
    /// year track (FR-2.9).
    var isAgeWordingToggleDisabled: Bool {
        profile.largestUnit != .year
    }

    /// Sets `useAgeWording`. A no-op while `largestUnit` is not `.year` — the
    /// view is expected to disable the toggle in that state already; this is
    /// the defensive backstop (FR-2.9).
    func setUseAgeWording(_ newValue: Bool) {
        guard newValue != profile.useAgeWording else { return }
        guard profile.largestUnit == .year else { return }
        mutate { $0.useAgeWording = newValue }
    }
}

// MARK: - Position and theme (FR-4.1–FR-4.9)

extension DisplaySettingsModel {
    func setPosition(_ newValue: OverlayPosition) {
        guard newValue != profile.position else { return }
        mutate { $0.position = newValue }
    }

    func setThemeID(_ newValue: ThemeID) {
        guard newValue != profile.themeID else { return }
        mutate { $0.themeID = newValue }
    }
}
