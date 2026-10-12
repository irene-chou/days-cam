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

    /// A change the model refused because it would leave nothing to show
    /// (TASK-108, #422): the last checked unit, or the last of 天數／日期.
    /// The view answers each one with a bounce, a light haptic and a short
    /// hint (FR-11.2／FR-11.3); `serial` makes a repeated refusal a new event.
    struct Rejection: Equatable {
        enum Kind: Equatable {
            case lastUnit(DisplayUnit)
            case lastContentSwitch(ContentSwitch)
            /// A unit or 年改成歲 tapped while the day count is off (108.8).
            case dayCountOff
        }
        enum ContentSwitch: Equatable { case dayCount, date }
        let kind: Kind
        let serial: Int

        /// The hint the view floats for this refusal (D-7 proposal 3 wording).
        var hint: String {
            switch kind {
            case .lastUnit: return "至少保留一個單位"
            case .lastContentSwitch: return "至少顯示天數或日期"
            case .dayCountOff: return "先打開天數"
            }
        }
    }
    /// The most recent refusal; `nil` until one happens.
    @Published private(set) var lastRejection: Rejection?
    /// The refusal whose hint is on screen right now (TASK-108): set by
    /// `reject`, cleared `hintDuration` later; a newer refusal restarts the
    /// clock. Owned here, not by the view, so the hint's lifetime does not
    /// depend on view identity or re-renders.
    @Published private(set) var visibleHint: Rejection?
    /// How long a hint stays before fading (108.1): 1.5 s. UI tests launch
    /// with `-UITestLongHints` to stretch it, because `XCUIElement.tap()`
    /// only returns once the app's animations settle — by then a 1.5 s hint
    /// has nearly expired; the 1.5 s itself is pinned by a unit test.
    static var hintDuration: TimeInterval {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestLongHints") { return 6 }
        #endif
        return 1.5
    }
    private var hintTask: Task<Void, Never>?

    /// Refusals of the same kind closer together than this are one event:
    /// a switch that springs back can report its refusal more than once,
    /// and the feedback (haptic, bounce, hint) should play once per tap.
    static let rejectionDebounce: TimeInterval = 0.3
    private var lastRejectionTime: Date?

    private func reject(_ kind: Rejection.Kind) {
        let now = Date()
        if let last = lastRejection, last.kind == kind,
           let lastTime = lastRejectionTime, now.timeIntervalSince(lastTime) < Self.rejectionDebounce {
            return
        }
        lastRejectionTime = now
        let rejection = Rejection(kind: kind, serial: (lastRejection?.serial ?? 0) + 1)
        lastRejection = rejection
        visibleHint = rejection
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.hintDuration))
            guard !Task.isCancelled, let self, self.visibleHint == rejection else { return }
            self.visibleHint = nil
        }
    }
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
    /// Sets `showDayCount` (TASK-107, #426; FR-11.1). Turning it off while
    /// the date is off too is refused — the two may not both be off (PRD
    /// §4.1 invariant 3) — and the view's switch springs back (107.3).
    func setShowDayCount(_ newValue: Bool) {
        guard newValue != profile.showDayCount else { return }
        guard newValue || profile.showDate else {
            reject(.lastContentSwitch(.dayCount))
            return
        }
        mutate { $0.showDayCount = newValue }
    }

    /// Sets `showDate`; symmetric with `setShowDayCount` — turning it off
    /// while the day count is off is refused (107.3).
    func setShowDate(_ newValue: Bool) {
        guard newValue != profile.showDate else { return }
        guard newValue || profile.showDayCount else {
            reject(.lastContentSwitch(.date))
            return
        }
        mutate { $0.showDate = newValue }
    }

    /// Whether the day-count switch is the last of 天數／日期 still on, so
    /// turning it off would be refused (107.3; TASK-108 reads this for its
    /// bounce-and-hint feedback).
    var isDayCountTheLastContentSwitch: Bool { profile.showDayCount && !profile.showDate }

    /// Whether the date switch is the last of 天數／日期 still on.
    var isDateTheLastContentSwitch: Bool { profile.showDate && !profile.showDayCount }

    /// Whether the 天數單位 controls are inert: the day count is off, so the
    /// units have nothing to format and `toggleUnit`／`setUseAgeWording`
    /// refuse (107.4; FR-11.5 as revised by TASK-107 — the controls look as
    /// usual, neither dimmed nor hidden, with no explanatory text; TASK-108
    /// answers the refused tap with feedback).
    var areUnitsInert: Bool { !profile.showDayCount }

    func setShowName(_ newValue: Bool) {
        guard newValue != profile.showName else { return }
        mutate { $0.showName = newValue }
    }
}

// MARK: - Day-count format (FR-2.7–FR-2.10)

extension DisplaySettingsModel {
    /// Checks or unchecks `unit` (PRD 0.2 FR-11.3, TASK-27).
    ///
    /// Unchecking the last remaining unit is refused (`lastRejection`,
    /// TASK-108): `displayUnits` may never be empty. `useAgeWording` is left
    /// alone either way (FR-11.4 as amended by TASK-139 #486).
    func toggleUnit(_ unit: DisplayUnit) {
        // With the day count off the units have nothing to format: the tap
        // changes nothing (107.4; the feedback is TASK-108's 108.8).
        guard !areUnitsInert else {
            reject(.dayCountOff)
            return
        }
        if profile.displayUnits.contains(unit) {
            guard profile.displayUnits.count > 1 else {
                reject(.lastUnit(unit))
                return
            }
            mutate { $0.displayUnits.remove(unit) }
        } else {
            mutate { $0.displayUnits.insert(unit) }
        }
    }

    /// Whether `unit` is the last unit still checked, so unchecking it is
    /// refused (FR-11.3) — mirrors `toggleUnit`'s guard. Since TASK-108 the
    /// checkbox is not disabled or dimmed for it; the refusal is answered
    /// with feedback instead (was `isUnitToggleDisabled`).
    func isLastCheckedUnit(_ unit: DisplayUnit) -> Bool {
        profile.displayUnits.contains(unit) && profile.displayUnits.count == 1
    }

    /// Sets `useAgeWording`, whether or not the year is checked: the switch
    /// only renames the year unit 年 → 歲 (FR-11.4 as amended by TASK-139
    /// #486; it used to need the year checked).
    func setUseAgeWording(_ newValue: Bool) {
        guard newValue != profile.useAgeWording else { return }
        guard !areUnitsInert else {
            reject(.dayCountOff)
            return
        }
        mutate { $0.useAgeWording = newValue }
    }
}
