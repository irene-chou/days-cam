import Foundation

/// Builds the overlay string for a profile as of a given capture moment.
///
/// `capturedAt` is the moment the photo was taken. MVP always passes the
/// shutter instant; a future import feature can pass a moment obtained
/// elsewhere without this type changing. Never read the system clock in here:
/// `capturedAt` is the only time source (PRD FR-2.18, §6.5.3).
struct TemplateRenderer {
    /// Shown instead of a count when the start date has not arrived yet
    /// (PRD §7.2).
    static let notStartedText = "尚未開始"
    /// Shown when every unit on the chosen track is zero (PRD FR-2.12).
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
                calendar: Calendar = .current) -> String {
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
    /// The elapsed amount on the track chosen by `largestUnit`.
    func elapsedText(profile: CameraProfile, calculator: DayCountCalculator) -> String {
        // Checked on the raw difference, not the day count: under `.dayOne` a
        // start date one day out still counts to 0, and 0 is not "day zero".
        guard calculator.rawDayDifference(from: profile.startDate) >= 0 else {
            return Self.notStartedText
        }

        switch profile.largestUnit {
        case .day:
            // The one ordinal form in the product, and the only track where the
            // day is `n` itself. Kept even at zero: `.dayZero` on the start date
            // prints 第 0 天, not the all-zero fallback (PRD FR-2.13).
            let count = calculator.dayCount(from: profile.startDate, rule: profile.countingRule)
            return "第 \(count) 天"

        case .week:
            let count = calculator.dayCount(from: profile.startDate, rule: profile.countingRule)
            return weekTrackText(dayCount: count, smallestUnit: profile.smallestUnit)

        case .month:
            let breakdown = calculator.monthDayBreakdown(from: profile.startDate)
            return monthTrackText(breakdown: breakdown, smallestUnit: profile.smallestUnit)

        case .year:
            let breakdown = calculator.calendarBreakdown(from: profile.startDate)
            return yearTrackText(breakdown: breakdown,
                                 smallestUnit: profile.smallestUnit,
                                 useAgeWording: profile.useAgeWording)
        }
    }

    /// Weeks and days, both derived from `n` and so both carrying the counting
    /// rule's +1 — unlike the year and month tracks (PRD §3.2).
    func weekTrackText(dayCount: Int, smallestUnit: DisplayUnit) -> String {
        let weeks = dayCount / 7
        let days = dayCount % 7
        var segments: [String] = []
        if weeks != 0 {
            segments.append("\(weeks) 週")
        }
        // At `.week` the remainder is truncated by the chosen smallest unit
        // rather than omitted for being zero.
        if smallestUnit == .day && days != 0 {
            segments.append("\(days) 天")
        }
        return joined(segments, separator: "又 ")
    }

    /// Total elapsed months and the leftover days.
    func monthTrackText(breakdown: (months: Int, days: Int), smallestUnit: DisplayUnit) -> String {
        var segments: [String] = []
        if breakdown.months != 0 {
            segments.append("\(breakdown.months) 個月")
        }
        if smallestUnit == .day && breakdown.days != 0 {
            segments.append("\(breakdown.days) 天")
        }
        return joined(segments, separator: "又 ")
    }

    /// Years, months and days from the calendar difference.
    ///
    /// The days here are the calendar remainder (5 in the reference case), not
    /// `n` and not `n % 7`. Reusing one "days" variable across the tracks is the
    /// single easiest way to get this section wrong (PRD §3.2).
    func yearTrackText(breakdown: (years: Int, months: Int, days: Int),
                       smallestUnit: DisplayUnit,
                       useAgeWording: Bool) -> String {
        var units = DisplayUnitTrack.units(largest: .year, smallest: smallestUnit)
        if units.isEmpty {
            // Only reachable with a profile the persistence layer would reject.
            units = DisplayUnitTrack.units(forLargest: .year)
        }

        var segments: [String] = []
        for unit in units {
            switch unit {
            case .year where breakdown.years != 0:
                segments.append("\(breakdown.years) \(useAgeWording ? "歲" : "年")")
            case .month where breakdown.months != 0:
                segments.append("\(breakdown.months) 個月")
            case .day where breakdown.days != 0:
                segments.append("\(breakdown.days) 天")
            default:
                break
            }
        }
        // No connective on this track: "1 年 2 個月又 5 天" does not read well
        // with three segments (PRD FR-2.14).
        return joined(segments, separator: " ")
    }

    /// Joins the non-zero segments, falling back to `0 天` when every unit on
    /// the track was zero (PRD FR-2.12).
    func joined(_ segments: [String], separator: String) -> String {
        segments.isEmpty ? Self.allZeroText : segments.joined(separator: separator)
    }
}
