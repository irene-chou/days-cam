import XCTest
@testable import DaysCam

/// Locks down every boundary in PRD §7.1 and the TASK-02 acceptance tables.
///
/// Every case pins the calendar to Gregorian/Asia-Taipei and injects the clock,
/// so none of these depend on where or when they run.
final class DayCountCalculatorTests: XCTestCase {

    private func calculator(now: Date, calendar: Calendar = DateFixture.taipei) -> DayCountCalculator {
        DayCountCalculator(calendar: calendar, now: { now })
    }

    // MARK: - 2.1 ... 2.15 day difference and counting rules

    func testDayDifferenceAndCountingRulesAcrossBoundaries() throws {
        // (id, start, now, raw, dayOne, dayZero) — values measured on Swift 6.0.3.
        let cases: [(String, DateComponents, (Int, Int, Int, Int, Int, Int), Int, Int, Int)] = [
            ("2.1 same day", DateFixture.components(2026, 1, 1), (2026, 1, 1, 12, 0, 0), 0, 1, 0),
            ("2.2 basic", DateFixture.components(2026, 1, 1), (2026, 1, 10, 8, 0, 0), 9, 10, 9),
            ("2.3 across month", DateFixture.components(2026, 1, 31), (2026, 2, 1, 0, 30, 0), 1, 2, 1),
            ("2.4 across year", DateFixture.components(2025, 12, 31), (2026, 1, 1, 0, 30, 0), 1, 2, 1),
            ("2.5 leap span", DateFixture.components(2024, 2, 28), (2024, 3, 1, 10, 0, 0), 2, 3, 2),
            ("2.6 non-leap span", DateFixture.components(2026, 2, 28), (2026, 3, 1, 10, 0, 0), 1, 2, 1),
            ("2.7 start on Feb 29", DateFixture.components(2024, 2, 29), (2024, 3, 1, 10, 0, 0), 1, 2, 1),
            ("2.8 full common year", DateFixture.components(2025, 1, 1), (2026, 1, 1, 10, 0, 0), 365, 366, 365),
            ("2.9 full leap year", DateFixture.components(2024, 1, 1), (2025, 1, 1, 10, 0, 0), 366, 367, 366),
            ("2.10 one second before midnight", DateFixture.components(2026, 1, 1), (2026, 1, 1, 23, 59, 59), 0, 1, 0),
            ("2.11 one second after midnight", DateFixture.components(2026, 1, 1), (2026, 1, 2, 0, 0, 1), 1, 2, 1),
            ("2.12 start in the future", DateFixture.components(2026, 12, 1), (2026, 9, 19, 10, 0, 0), -73, -72, -73),
            ("2.13 long span", DateFixture.components(2025, 1, 15), (2026, 3, 20, 10, 0, 0), 429, 430, 429),
            ("2.14 default profile next day", DateFixture.components(2026, 1, 10), (2026, 1, 11, 10, 0, 0), 1, 2, 1),
            ("2.15 default profile a month later", DateFixture.components(2026, 1, 10), (2026, 2, 10, 10, 0, 0), 31, 32, 31)
        ]

        for (label, start, nowParts, expectedRaw, expectedDayOne, expectedDayZero) in cases {
            let now = try XCTUnwrap(DateFixture.date(nowParts.0, nowParts.1, nowParts.2,
                                                     hour: nowParts.3, minute: nowParts.4, second: nowParts.5),
                                    "\(label): could not build the injected now")
            let subject = calculator(now: now)
            XCTAssertEqual(subject.rawDayDifference(from: start), expectedRaw, "\(label) raw")
            XCTAssertEqual(subject.dayCount(from: start, rule: .dayOne), expectedDayOne, "\(label) dayOne")
            XCTAssertEqual(subject.dayCount(from: start, rule: .dayZero), expectedDayZero, "\(label) dayZero")
        }
    }

    // MARK: - 2.16 ... 2.22 calendar breakdown

    func testCalendarBreakdownMatchesFoundationBehaviour() throws {
        let cases: [(String, DateComponents, (Int, Int, Int), (Int, Int, Int))] = [
            ("2.16", DateFixture.components(2025, 1, 15), (2026, 3, 20), (1, 2, 5)),
            ("2.17", DateFixture.components(2026, 1, 1), (2026, 1, 1), (0, 0, 0)),
            ("2.18", DateFixture.components(2026, 1, 1), (2026, 1, 10), (0, 0, 9)),
            ("2.19", DateFixture.components(2025, 1, 1), (2026, 1, 1), (1, 0, 0)),
            ("2.20", DateFixture.components(2025, 1, 1), (2026, 3, 1), (1, 2, 0)),
            ("2.21", DateFixture.components(2024, 2, 29), (2025, 2, 28), (1, 0, 0)),
            ("2.22", DateFixture.components(2024, 2, 29), (2025, 3, 1), (1, 0, 1))
        ]

        for (label, start, nowParts, expected) in cases {
            let now = try XCTUnwrap(DateFixture.date(nowParts.0, nowParts.1, nowParts.2, hour: 10),
                                    "\(label): could not build the injected now")
            let breakdown = calculator(now: now).calendarBreakdown(from: start)
            XCTAssertEqual(breakdown.years, expected.0, "\(label) years")
            XCTAssertEqual(breakdown.months, expected.1, "\(label) months")
            XCTAssertEqual(breakdown.days, expected.2, "\(label) days")
        }
    }

    /// 2.21 pins Foundation's own behaviour: it clamps the non-existent
    /// 2025-02-29 to 2025-02-28 and calls that a full year. The value is
    /// measured, not derived; the point of the test is to notice if a future OS
    /// changes it.
    func testFebruary29ToFebruary28CountsAsAFullYear() throws {
        let now = try XCTUnwrap(DateFixture.date(2025, 2, 28, hour: 10))
        let breakdown = calculator(now: now).calendarBreakdown(from: DateFixture.components(2024, 2, 29))
        XCTAssertEqual(breakdown.years, 1)
        XCTAssertEqual(breakdown.months, 0)
        XCTAssertEqual(breakdown.days, 0)
    }

    /// The counting rule's +1 must not leak into the calendar breakdown: on the
    /// start date itself the breakdown is all zeros while `dayCount` is 1.
    func testCountingRuleDoesNotAffectCalendarBreakdown() throws {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 1, hour: 9))
        let subject = calculator(now: now)
        let start = DateFixture.components(2026, 1, 1)
        XCTAssertEqual(subject.dayCount(from: start, rule: .dayOne), 1)
        let breakdown = subject.calendarBreakdown(from: start)
        XCTAssertEqual(breakdown.years, 0)
        XCTAssertEqual(breakdown.months, 0)
        XCTAssertEqual(breakdown.days, 0)
    }

    // MARK: - 0.2 elapsed breakdown by unit set (PRD 0.2 §4.5)

    /// Reference case: 2025-01-15 → 2026-03-20, n = 430.
    func testElapsedBreakdownSplitsOnlyTheCheckedUnits() throws {
        let subject = calculator(now: try XCTUnwrap(DateFixture.date(2026, 3, 20, hour: 10)))
        let start = DateFixture.components(2025, 1, 15)
        func breakdown(_ units: Set<DisplayUnit>) -> ElapsedBreakdown {
            subject.elapsedBreakdown(from: start, units: units, rule: .dayOne)
        }
        XCTAssertEqual(breakdown([.year, .day]), ElapsedBreakdown(years: 1, days: 64), "U-5")
        XCTAssertEqual(breakdown([.year, .month, .day]), ElapsedBreakdown(years: 1, months: 2, days: 5))
        XCTAssertEqual(breakdown([.month, .week, .day]), ElapsedBreakdown(months: 14, weeks: 0, days: 5))
        XCTAssertEqual(breakdown([.year, .week]), ElapsedBreakdown(years: 1, weeks: 9), "remainder dropped")
        XCTAssertEqual(breakdown([.week, .day]), ElapsedBreakdown(weeks: 61, days: 3), "U-3 uses n")
        XCTAssertEqual(breakdown([.week]), ElapsedBreakdown(weeks: 61))
    }

    /// U-3 applies the counting rule's +1; U-4 does not.
    func testCountingRuleAppliesOnlyWithoutYearOrMonth() throws {
        let subject = calculator(now: try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10)))
        let start = DateFixture.components(2026, 1, 1)
        XCTAssertEqual(subject.elapsedBreakdown(from: start, units: [.week, .day], rule: .dayOne),
                       ElapsedBreakdown(weeks: 1, days: 3))
        XCTAssertEqual(subject.elapsedBreakdown(from: start, units: [.week, .day], rule: .dayZero),
                       ElapsedBreakdown(weeks: 1, days: 2))
        XCTAssertEqual(subject.elapsedBreakdown(from: start, units: [.month, .week, .day], rule: .dayOne),
                       ElapsedBreakdown(weeks: 1, days: 2))
    }

    // MARK: - 2.23 ... 2.25 current date and time zones

    func testCurrentDateComponentsIgnoresTimeOfDay() throws {
        let morning = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        let justBeforeMidnight = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 23, minute: 59, second: 59))

        for now in [morning, justBeforeMidnight] {
            let components = calculator(now: now).currentDateComponents()
            XCTAssertEqual(components.year, 2026)
            XCTAssertEqual(components.month, 1)
            XCTAssertEqual(components.day, 10)
        }
    }

    /// 2.25: the same instant is a different local day in Taipei and New York,
    /// and both the day count and the printed date must follow the calendar's
    /// time zone (PRD §6.3).
    func testSameInstantResolvesPerCalendarTimeZone() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 9, hour: 20, in: DateFixture.utc))
        let start = DateFixture.components(2026, 1, 1)

        let taipei = calculator(now: instant, calendar: DateFixture.taipei)
        XCTAssertEqual(taipei.dayCount(from: start, rule: .dayOne), 10)
        XCTAssertEqual(taipei.currentDateComponents().month, 1)
        XCTAssertEqual(taipei.currentDateComponents().day, 10)

        let newYork = calculator(now: instant, calendar: DateFixture.newYork)
        XCTAssertEqual(newYork.dayCount(from: start, rule: .dayOne), 9)
        XCTAssertEqual(newYork.currentDateComponents().month, 1)
        XCTAssertEqual(newYork.currentDateComponents().day, 9)
    }

    // MARK: - Malformed input

    /// A start date that names no day yields 0 rather than trapping, because
    /// the signature is a non-optional Int.
    ///
    /// The under-specified cases are the ones that matter: `Calendar` does not
    /// reject them, it fills the gaps from its reference date, so without an
    /// explicit presence check empty components report a difference of over
    /// 700,000 days.
    func testStartDateThatNamesNoDayYieldsZero() throws {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let subject = calculator(now: now)

        var yearOnly = DateComponents()
        yearOnly.year = 2026
        var missingDay = DateComponents()
        missingDay.year = 2026
        missingDay.month = 1

        for malformed in [DateComponents(), yearOnly, missingDay] {
            XCTAssertEqual(subject.rawDayDifference(from: malformed), 0)
            XCTAssertEqual(subject.dayCount(from: malformed, rule: .dayZero), 0)
            let breakdown = subject.calendarBreakdown(from: malformed)
            XCTAssertEqual(breakdown.years, 0)
            XCTAssertEqual(breakdown.months, 0)
            XCTAssertEqual(breakdown.days, 0)
        }
    }

    /// A start date carrying a foreign `timeZone` is resolved in that zone and
    /// so lands a day early — `startOfDay` cannot undo it. This is exactly why
    /// the stripping has to happen in `ProfileStore` (PRD §4.1, TASK-03 3.27).
    func testCalculatorDoesNotStripTimeZonePollution() throws {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 20, hour: 12, in: DateFixture.newYork))
        let subject = calculator(now: now, calendar: DateFixture.newYork)

        var polluted = DateFixture.components(2026, 1, 15)
        polluted.timeZone = TimeZone(identifier: "Asia/Taipei")

        XCTAssertEqual(subject.rawDayDifference(from: DateFixture.components(2026, 1, 15)), 5)
        XCTAssertEqual(subject.rawDayDifference(from: polluted), 6,
                       "The calculator must not sanitise input: ProfileStore's stripping is what TASK-03 3.27 verifies")
    }

    // MARK: - Debug clock override

    #if DEBUG
    func testFakeTodayParsesToLocalNoon() throws {
        let overridden = try XCTUnwrap(
            DayCountCalculator.debugFakeToday(environment: ["DAYSCAM_FAKE_TODAY": "2026-01-10"],
                                              calendar: DateFixture.taipei)
        )
        let components = DateFixture.taipei.dateComponents([.year, .month, .day, .hour], from: overridden)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, 12, "Noon avoids midnight and daylight-saving edges")
    }

    func testFakeTodayIsIgnoredWhenAbsentOrMalformed() {
        XCTAssertNil(DayCountCalculator.debugFakeToday(environment: [:], calendar: DateFixture.taipei))
        XCTAssertNil(DayCountCalculator.debugFakeToday(environment: ["DAYSCAM_FAKE_TODAY": "not-a-date-x"],
                                                       calendar: DateFixture.taipei))
        XCTAssertNil(DayCountCalculator.debugFakeToday(environment: ["DAYSCAM_FAKE_TODAY": "2026-01"],
                                                       calendar: DateFixture.taipei))
    }

    /// The default clock must consult `DAYSCAM_FAKE_TODAY`.
    ///
    /// This is what a default argument that reads the system clock directly
    /// would break: the variable would be set and never read, so
    /// every simulator acceptance run that drives the app to a fixed date would
    /// silently use the real one.
    func testDefaultClockHonoursTheDebugOverride() {
        setenv(DayCountCalculator.fakeTodayEnvironmentKey, "2026-01-10", 1)
        defer { unsetenv(DayCountCalculator.fakeTodayEnvironmentKey) }

        let subject = DayCountCalculator(calendar: DateFixture.taipei)
        let components = subject.currentDateComponents()
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(subject.dayCount(from: DateFixture.components(2026, 1, 1), rule: .dayOne), 10)
    }

    /// ...and an injected clock must still beat it.
    ///
    /// This is what applying the override inside the initializer body would
    /// break: it would overwrite the caller's closure, so every test in this
    /// file would read `DAYSCAM_FAKE_TODAY` instead of its own fixture. The
    /// default argument is the only place the override can live.
    func testInjectedClockWinsOverTheDebugOverride() throws {
        setenv(DayCountCalculator.fakeTodayEnvironmentKey, "2020-05-05", 1)
        defer { unsetenv(DayCountCalculator.fakeTodayEnvironmentKey) }

        let injected = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        let subject = DayCountCalculator(calendar: DateFixture.taipei, now: { injected })
        XCTAssertEqual(subject.now(), injected)
        XCTAssertEqual(subject.currentDateComponents().year, 2026)
        XCTAssertEqual(subject.currentDateComponents().day, 10)
    }
    #endif
}
