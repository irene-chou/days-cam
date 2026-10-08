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
    /// Shown when every checked unit is zero (PRD FR-2.12, 0.2 U-7).
    static let allZeroText = "0 天"
    /// Separates the date from the elapsed amount: ideographic space U+3000
    /// (PRD FR-2.5).
    static let dateSeparator = "\u{3000}"

    init() {}

    /// Renders the overlay text for `profile` as of `capturedAt`.
    ///
    /// Assembly order is name, then date, then elapsed amount (PRD FR-2.5).
    /// The name is followed by a half-width space; the date and the elapsed
    /// amount are separated by an ideographic space.
    func render(profile: CameraProfile,
                capturedAt: Date,
                calendar: Calendar = .autoupdatingCurrent) -> String {
        // One clock for the whole render, and it is the caller's.
        let calculator = DayCountCalculator(calendar: calendar, now: { capturedAt })

        var trailing: [String] = []
        if profile.showDate {
            trailing.append(dateText(calculator: calculator))
        }
        if profile.showDayCount {
            trailing.append(elapsedText(profile: profile, calculator: calculator))
        }

        var result = trailing.joined(separator: Self.dateSeparator)

        // An empty name would otherwise leave the overlay with a leading space.
        // The persistence layer rejects those, but a half-typed profile in the
        // editor has not been through it yet.
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if profile.showName && !name.isEmpty {
            result = result.isEmpty ? name : "\(name) \(result)"
        }
        return result
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
        guard !segments.isEmpty else { return Self.allZeroText }
        return segments.joined(separator: separator(for: units))
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
