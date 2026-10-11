import Foundation

/// Builds the overlay string for a profile as of a given capture moment.
///
/// `capturedAt` is the moment the photo was taken. MVP always passes the
/// shutter instant; a future import feature can pass a moment obtained
/// elsewhere without this type changing. Never read the system clock in here:
/// `capturedAt` is the only time source (PRD FR-2.18, §6.5.3).
struct TemplateRenderer {
    /// Shown instead of a count when the start date has not arrived yet:
    /// `還有 N 天`, `daysUntilStart` calendar days away (#250, replacing
    /// PRD §7.2's 尚未開始). Always in days, whatever the units or wording.
    static func notStartedText(daysUntilStart: Int) -> String {
        "還有 \(daysUntilStart) 天"
    }
    /// Separates every part of the overlay: a half-width space U+0020
    /// (#249, replacing PRD FR-2.5's ideographic space).
    static let partSeparator = " "

    init() {}

    /// Renders the overlay text for `profile` as of `capturedAt`.
    ///
    /// With the elapsed amount shown, the order is date, then name, then
    /// elapsed amount (#249); without the day count, date then name (TASK-107).
    /// Parts are joined by a single half-width space.
    func render(profile: CameraProfile,
                capturedAt: Date,
                calendar: Calendar = .autoupdatingCurrent) -> String {
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
        let elapsed: String? = profile.showDayCount ? elapsedText(profile: profile, calculator: calculator) : nil
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
    func elapsedText(profile: CameraProfile, calculator: DayCountCalculator) -> String {
        // Checked on the raw difference, not the day count: under `.dayOne` a
        // start date one day out still counts to 0, and 0 is not "day zero".
        // The counting rule plays no part in how far away the start is, so a
        // start date tomorrow reads 還有 1 天 under either rule.
        let rawDifference = calculator.rawDayDifference(from: profile.startDate)
        guard rawDifference >= 0 else {
            return Self.notStartedText(daysUntilStart: -rawDifference)
        }

        let units = profile.displayUnits
        if units == [.day] {
            // U-2: the one ordinal form in the product. Kept even at zero:
            // `.dayZero` on the start date prints 第 0 天, not the all-zero
            // fallback (0.1 FR-2.13).
            let count = calculator.dayCount(from: profile.startDate, rule: profile.countingRule)
            return "第 \(count) 天"
        }

        let breakdown = calculator.elapsedBreakdown(from: profile.startDate,
                                                    units: units,
                                                    rule: profile.countingRule)
        // U-1 order; U-7 drops zero units.
        let segments: [String] = DisplayUnit.allCases.compactMap { unit in
            guard units.contains(unit) else { return nil }
            let value = breakdown.value(of: unit)
            guard value != 0 else { return nil }
            return "\(value) \(label(for: unit, useAgeWording: profile.useAgeWording))"
        }
        guard !segments.isEmpty else {
            return allZeroText(units: units, useAgeWording: profile.useAgeWording)
        }
        return segments.joined(separator: separator(for: units))
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
