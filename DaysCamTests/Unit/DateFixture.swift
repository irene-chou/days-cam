import Foundation

/// Fixed calendars and date builders for the unit tests.
///
/// Tests must never read the real clock, so there is deliberately no helper
/// here that returns "now" (PRD §8).
enum DateFixture {
    /// The calendar the acceptance tables are stated in.
    static let taipei = calendar(timeZoneIdentifier: "Asia/Taipei")
    static let newYork = calendar(timeZoneIdentifier: "America/New_York")
    static let utc = calendar(timeZoneIdentifier: "UTC")

    /// A Gregorian calendar pinned to one time zone.
    static func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    /// A clean `year`/`month`/`day` start date, as the persistence layer stores it.
    static func components(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return components
    }

    /// An instant in `calendar`'s time zone. Nil if the input names no real date.
    static func date(_ year: Int,
                     _ month: Int,
                     _ day: Int,
                     hour: Int = 0,
                     minute: Int = 0,
                     second: Int = 0,
                     in calendar: Calendar = DateFixture.taipei) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)
    }
}
