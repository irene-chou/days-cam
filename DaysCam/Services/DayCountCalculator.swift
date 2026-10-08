import Foundation

/// The single source of truth for how many days have passed since a start date.
///
/// Both the calendar and the clock are injected so every boundary case can be
/// tested without touching the host clock (PRD §8). Nothing here reads image or
/// file metadata: the capture moment is always handed in (PRD §6.1).
struct DayCountCalculator {
    /// Calendar and time zone every comparison is made in (PRD §6.3).
    let calendar: Calendar
    /// The capture moment. MVP passes the shutter instant; tests pass a fixture.
    let now: () -> Date

    /// Creates a calculator.
    ///
    /// The default `now` is `defaultNow()` rather than a literal `{ Date() }`
    /// so that the debug clock override is consulted. Applying the override
    /// inside the initializer body instead would overwrite a clock the caller
    /// deliberately injected, which would break every test that passes one.
    init(calendar: Calendar = .autoupdatingCurrent,
         now: @escaping () -> Date = DayCountCalculator.defaultNow()) {
        self.calendar = calendar
        self.now = now
    }

    /// Calendar day difference, ignoring time of day. Can be negative.
    ///
    /// Both ends are normalized to local midnight, so 23:59:59 and 00:00:01 on
    /// the same day give the same answer. Returns 0 when `startDate` does not
    /// resolve to a date at all; the persistence layer is what rejects
    /// malformed start dates (PRD §4.1).
    func rawDayDifference(from startDate: DateComponents) -> Int {
        guard let fromMidnight = startOfStartDate(startDate) else { return 0 }
        let toMidnight = calendar.startOfDay(for: now())
        return calendar.dateComponents([.day], from: fromMidnight, to: toMidnight).day ?? 0
    }

    /// Day count after applying the counting rule. Can be zero or negative.
    ///
    /// A negative result means the start date is in the future; the display
    /// layer turns that into "還有 N 天" (#250).
    func dayCount(from startDate: DateComponents, rule: CountingRule) -> Int {
        let raw = rawDayDifference(from: startDate)
        switch rule {
        case .dayOne:
            return raw + 1
        case .dayZero:
            return raw
        }
    }

    /// Calendar year/month/day breakdown for the unit-converted template.
    ///
    /// The counting rule is deliberately **not** applied: "day one" is a notion
    /// that belongs to a day count, not to "1 year 2 months". On the start date
    /// itself this returns `(0, 0, 0)` while `dayCount` returns 1 under
    /// `.dayOne`, and that difference is intended (PRD §3.2).
    func calendarBreakdown(from startDate: DateComponents) -> (years: Int, months: Int, days: Int) {
        let components = calendarDifference([.year, .month, .day], from: startDate)
        return (components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// The elapsed amount broken into the checked `units` (PRD 0.2 §4.5).
    ///
    /// - No year and no month checked (U-3): everything comes from the day
    ///   count `n`, so the counting rule's +1 **is** applied. Weeks are
    ///   `n / 7` and days `n % 7`; without a day unit the remainder is dropped.
    /// - Year or month checked (U-4): the calendar difference in exactly the
    ///   checked year/month units plus days, so an unchecked unit is not split
    ///   out (U-5: year and day only gives "1 年 64 天"). The counting rule is
    ///   **not** applied (0.1 §3.2). The leftover days then become weeks and
    ///   days as above. Month arithmetic clamps a missing day to the month's
    ///   end, as Foundation does (U-6).
    ///
    /// Asking `Calendar` for all the checked components in one call is what
    /// keeps every 0.1 combination's output identical to 0.1, which made the
    /// same single call. Only the checked units carry values; the rest are 0.
    /// The ordinal "day only" case (U-2) is the caller's to special-case.
    func elapsedBreakdown(from startDate: DateComponents,
                          units: Set<DisplayUnit>,
                          rule: CountingRule) -> ElapsedBreakdown {
        var breakdown = ElapsedBreakdown()
        let remainder: Int
        if units.contains(.year) || units.contains(.month) {
            var components: Set<Calendar.Component> = [.day]
            if units.contains(.year) { components.insert(.year) }
            if units.contains(.month) { components.insert(.month) }
            let difference = calendarDifference(components, from: startDate)
            breakdown.years = difference.year ?? 0
            breakdown.months = difference.month ?? 0
            remainder = difference.day ?? 0
        } else {
            remainder = dayCount(from: startDate, rule: rule)
        }

        if units.contains(.week) {
            breakdown.weeks = remainder / 7
            breakdown.days = units.contains(.day) ? remainder % 7 : 0
        } else {
            breakdown.days = units.contains(.day) ? remainder : 0
        }
        return breakdown
    }

    /// `Calendar`'s difference in `components` from `startDate` to today,
    /// all zero when `startDate` names no day.
    private func calendarDifference(_ components: Set<Calendar.Component>,
                                    from startDate: DateComponents) -> DateComponents {
        guard let fromMidnight = startOfStartDate(startDate) else { return DateComponents() }
        return calendar.dateComponents(components, from: fromMidnight, to: calendar.startOfDay(for: now()))
    }

    /// Local midnight on `startDate`, or nil when it names no day.
    ///
    /// The `year`/`month`/`day` presence check is not redundant:
    /// `Calendar.date(from:)` does not fail on an under-specified value, it
    /// fills the gaps from its reference date, so empty components resolve to
    /// year 1 and would report a difference of over 700,000 days.
    ///
    /// Note what this deliberately does **not** do: it passes `startDate`
    /// through untouched, so a stray `timeZone` still shifts the result. Only
    /// `ProfileStore` strips those. Sanitising here too would make TASK-03's
    /// 3.27 pass even with the stripping unimplemented (PRD §4.1).
    private func startOfStartDate(_ startDate: DateComponents) -> Date? {
        guard startDate.year != nil, startDate.month != nil, startDate.day != nil else { return nil }
        guard let start = calendar.date(from: startDate) else { return nil }
        return calendar.startOfDay(for: start)
    }

    /// Today's date in this calculator's calendar and time zone.
    ///
    /// Used for the printed date and for defaulting a new profile's start date.
    func currentDateComponents() -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: now())
    }
}

/// An elapsed amount split into the four display units. Units that were
/// not checked are 0 (PRD 0.2 §4.5).
struct ElapsedBreakdown: Equatable {
    var years = 0
    var months = 0
    var weeks = 0
    var days = 0

    /// The value for `unit`.
    func value(of unit: DisplayUnit) -> Int {
        switch unit {
        case .year: return years
        case .month: return months
        case .week: return weeks
        case .day: return days
        }
    }
}

// MARK: - Default clock

extension DayCountCalculator {
    /// The clock used when the caller does not inject one.
    ///
    /// In debug builds it honours `DAYSCAM_FAKE_TODAY`, which lets the
    /// simulator be driven to any date without changing the host clock. In
    /// release builds it is exactly `Date()`.
    static func defaultNow() -> () -> Date {
        return {
            #if DEBUG
            if let overridden = debugFakeToday() {
                return overridden
            }
            #endif
            return Date()
        }
    }

    #if DEBUG
    /// Environment variable that overrides today's date in debug builds.
    static let fakeTodayEnvironmentKey = "DAYSCAM_FAKE_TODAY"

    /// Parses `DAYSCAM_FAKE_TODAY` (format `yyyy-MM-dd`) into local noon.
    ///
    /// Noon rather than midnight so that neither a daylight-saving jump nor an
    /// off-by-one-second rounding can move the result onto a neighbouring day.
    /// Returns nil when the variable is absent or unparseable, in which case
    /// the real clock is used.
    ///
    /// This whole member is compiled out of release builds.
    static func debugFakeToday(environment: [String: String] = ProcessInfo.processInfo.environment,
                               calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard let raw = environment[fakeTodayEnvironmentKey] else { return nil }
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)
    }
    #endif
}
