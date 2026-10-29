import Foundation

/// Builds the overlay string for a profile as of a given capture moment.
///
/// `capturedAt` is the moment the photo was taken. MVP always passes the
/// shutter instant; a future import feature can pass a moment obtained
/// elsewhere without this type changing. Never read the system clock in here:
/// `capturedAt` is the only time source (PRD FR-2.18, §6.5.3).
struct TemplateRenderer {
    /// Shown instead of a count when the start date has not arrived yet and
    /// the checked units leave nothing to show: `還有 N 天`, `daysUntilStart`
    /// calendar days away (#250, replacing PRD §7.2's 尚未開始). Other
    /// settings read in the checked units, e.g. `還有 3 個月又 4 天`
    /// (TASK-140 #487).
    static func notStartedText(daysUntilStart: Int) -> String {
        "還有 \(daysUntilStart) 天"
    }
    /// Separates every part of the overlay: a half-width space U+0020
    /// (#249, replacing PRD FR-2.5's ideographic space).
    static let partSeparator = " "

    /// Shown for a photo that has no creation date (PRD 2.0 §6.1.3).
    static let unknownDateText = "日期不明"

    /// Which moment `capturedAt` stands for (PRD 2.0 §6.2).
    enum RenderMoment {
        /// The shutter instant, or "now": a start date still ahead reads
        /// as a countdown, `還有 N 天`.
        case today
        /// A photo's own moment, possibly long past: a photo taken before
        /// the start date reads `前 N 天` instead of a countdown.
        case photo
    }

    /// Words before the day gap for a photo taken before the start date.
    static func daysBeforeStartText(days: Int) -> String {
        "前 \(days) 天"
    }

    init() {}

    /// Renders the overlay text for `profile` as of `capturedAt`.
    ///
    /// With the elapsed amount shown, the order is date, then name, then
    /// elapsed amount (#249); without the day count, date then name (TASK-107).
    /// Parts are joined by a single half-width space.
    func render(profile: CameraProfile,
                capturedAt: Date,
                calendar: Calendar = .autoupdatingCurrent,
                moment: RenderMoment = .today) -> String {
        // One clock for the whole render, and it is the caller's.
        let calculator = DayCountCalculator(calendar: calendar, now: { capturedAt })

        // An empty name would otherwise leave the overlay with a stray space.
        // The persistence layer rejects those, but a half-typed profile in the
        // editor has not been through it yet.
        let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String? = profile.showName && !trimmedName.isEmpty ? trimmedName : nil
        let date: String? = profile.showDate ? dateText(calculator: calculator) : nil

        // Date, name, then the elapsed amount; with the day count off the
        // same order minus the last part — "日期 名稱", not the old "名稱
        // 日期" (TASK-107, #426, unified on purpose).
        let elapsed: String? = profile.showDayCount ? elapsedText(profile: profile, calculator: calculator, moment: moment) : nil
        return [date, name, elapsed].compactMap { $0 }.joined(separator: Self.partSeparator)
    }
}

// MARK: - Date

private extension TemplateRenderer {
    /// The capture date as `yyyy.MM.dd`.
    ///
    /// This branch deliberately touches neither `startDate`, nor the counting
    /// rule, nor any day count — it reads only the capture moment. Approximating
    /// it from "start date is today" would print "第 2 天" the following day
    /// instead of that day's date (PRD FR-2.17).
    func dateText(calculator: DayCountCalculator) -> String {
        let components = calculator.currentDateComponents()
        return String(format: "%04d.%02d.%02d",
                      components.year ?? 0,
                      components.month ?? 0,
                      components.day ?? 0)
    }
}

// MARK: - Elapsed amount

private extension TemplateRenderer {
    /// The elapsed amount in the checked `displayUnits` (PRD 0.2 §4.5).
    func elapsedText(profile: CameraProfile, calculator: DayCountCalculator, moment: RenderMoment) -> String {
        // Checked on the raw difference, not the day count: under `.dayOne` a
        // start date one day out still counts to 0, and 0 is not "day zero".
        // The counting rule plays no part in how far away the start is, so a
        // start date tomorrow reads 還有 1 天 under either rule.
        let rawDifference = calculator.rawDayDifference(from: profile.startDate)
        guard rawDifference >= 0 else {
            // A photo earlier than the start date: calendar days before it,
            // whatever the rule, units, wording or format (PRD 2.0 §6.2).
            if moment == .photo {
                return Self.daysBeforeStartText(days: -rawDifference)
            }
            return countdownText(profile: profile, calculator: calculator, daysUntilStart: -rawDifference)
        }

        let units = profile.displayUnits
        if units == [.day] {
            // U-2: day only is written in the profile's `dayCountFormat`
            // (#582), `ordinal` being the 第 N 天 of 0.1 FR-2.13. Kept even at
            // zero: `.dayZero` on the start date prints 第 0 天, not the
            // all-zero fallback. `dDay` ignores the counting rule, so the
            // start date is D-Day under either rule.
            let format = profile.dayCountFormat
            let count = format.usesCountingRule
                ? calculator.dayCount(from: profile.startDate, rule: profile.countingRule)
                : rawDifference
            return format.elapsedText(count: count)
        }

        let breakdown = calculator.elapsedBreakdown(from: profile.startDate,
                                                    units: units,
                                                    rule: profile.countingRule)
        guard let text = unitText(breakdown, units: units, useAgeWording: profile.useAgeWording) else {
            return allZeroText(units: units, useAgeWording: profile.useAgeWording)
        }
        return text
    }

    /// The time left before a future start date in the checked units
    /// (TASK-140 #487, replacing #250's days-only 52.3): `還有 ` followed by
    /// the same segments and separator as the elapsed amount. Years always
    /// read 年 — an age that has not started is not an age. When every
    /// checked unit is zero, and for day only, it is `還有 N 天` rather than
    /// a meaningless `還有 0 年`. Day only is written in the profile's
    /// `dayCountFormat` (#582); other units ignore it.
    func countdownText(profile: CameraProfile, calculator: DayCountCalculator, daysUntilStart: Int) -> String {
        let units = profile.displayUnits
        if units == [.day] {
            return profile.dayCountFormat.countdownText(daysUntilStart: daysUntilStart)
        }
        let breakdown = calculator.countdownBreakdown(to: profile.startDate, units: units)
        guard let text = unitText(breakdown, units: units, useAgeWording: false) else {
            return Self.notStartedText(daysUntilStart: daysUntilStart)
        }
        return "還有 \(text)"
    }

    /// The non-zero checked units of `breakdown` in U-1 order (U-7 drops
    /// zero units), joined per U-8; nil when every one is zero.
    func unitText(_ breakdown: ElapsedBreakdown, units: Set<DisplayUnit>, useAgeWording: Bool) -> String? {
        let segments: [String] = DisplayUnit.allCases.compactMap { unit in
            guard units.contains(unit) else { return nil }
            let value = breakdown.value(of: unit)
            guard value != 0 else { return nil }
            return "\(value) \(label(for: unit, useAgeWording: useAgeWording))"
        }
        return segments.isEmpty ? nil : segments.joined(separator: separator(for: units))
    }

    /// Shown when every checked unit is zero (PRD 0.2 U-7, TASK-93 #392): `0`
    /// with the label of the *smallest* checked unit (天 < 週 < 月 < 年), so
    /// a profile that never shows days reads `0 個月`／`0 週`／`0 歲` rather
    /// than a `0 天` it never asked for. Human decision 2026-10-10,
    /// replacing 0.1 FR-2.12's fixed `0 天` (4.24 and the year-only case
    /// changed on purpose). `DisplayUnit.allCases` runs largest to
    /// smallest, so the last checked case is the smallest; `displayUnits`
    /// is never empty, but a day fallback keeps this total.
    func allZeroText(units: Set<DisplayUnit>, useAgeWording: Bool) -> String {
        let smallest = DisplayUnit.allCases.last { units.contains($0) } ?? .day
        return "0 \(label(for: smallest, useAgeWording: useAgeWording))"
    }

    /// The unit's printed label; years read as ages when asked (U-9).
    func label(for unit: DisplayUnit, useAgeWording: Bool) -> String {
        switch unit {
        case .year: return useAgeWording ? "歲" : "年"
        case .month: return "個月"
        case .week: return "週"
        case .day: return "天"
        }
    }

    /// U-8: exactly two checked units without a year are joined with 「又」
    /// (`61 週又 3 天`); everything else with a half-width space
    /// (`1 年 2 個月 5 天`). Decided by what is checked, not by which
    /// segments happen to be non-zero, so one setting always reads one way.
    func separator(for units: Set<DisplayUnit>) -> String {
        units.count == 2 && !units.contains(.year) ? "又 " : " "
    }
}
