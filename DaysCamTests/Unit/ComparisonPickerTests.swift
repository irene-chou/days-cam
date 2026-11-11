import XCTest
@testable import DaysCam

/// #723 acceptance 1-3: default pair and milestone caption.
final class ComparisonPickerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    private func profile(units: Set<DisplayUnit> = [.day], age: Bool = false,
                         rule: CountingRule = .dayOne) -> CameraProfile {
        CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 8, day: 5),
                      countingRule: rule, displayUnits: units, useAgeWording: age)
    }

    private func candidate(_ id: String, _ month: Int, _ day: Int, year: Int = 2026) -> ComparisonPicker.Candidate {
        .init(id: id, creationDate: date(year, month, day))
    }

    /// #723-1
    func testReturnsNilWhenTooFewSameIdOrTooClose() {
        let p = profile()
        XCTAssertNil(ComparisonPicker.defaultPair([], profile: p, calendar: calendar))
        XCTAssertNil(ComparisonPicker.defaultPair([candidate("a", 9, 1)], profile: p, calendar: calendar))
        XCTAssertNil(ComparisonPicker.defaultPair([candidate("a", 9, 1), candidate("a", 10, 1)],
                                                  profile: p, calendar: calendar))
        XCTAssertNil(ComparisonPicker.defaultPair([candidate("a", 9, 1), candidate("b", 9, 7)],
                                                  profile: p, calendar: calendar))
        let pair = ComparisonPicker.defaultPair([candidate("a", 9, 1), candidate("b", 9, 8)],
                                                profile: p, calendar: calendar)
        XCTAssertEqual(pair?.earliest.id, "a")
        XCTAssertEqual(pair?.latest.id, "b")
    }

    /// #723-2
    func testIgnoresPhotosBeforeStartDate() {
        let candidates = [candidate("old", 7, 1), candidate("mid", 9, 1),
                          candidate("new", 11, 1), candidate("before", 8, 4)]
        let pair = ComparisonPicker.defaultPair(candidates, profile: profile(), calendar: calendar)
        XCTAssertEqual(pair?.earliest.id, "mid")
        XCTAssertEqual(pair?.latest.id, "new")
    }

    func testTiesKeepInputOrder() {
        let candidates = [candidate("a", 9, 1), candidate("b", 9, 1),
                          candidate("c", 11, 1), candidate("d", 11, 1)]
        let pair = ComparisonPicker.defaultPair(candidates, profile: profile(), calendar: calendar)
        XCTAssertEqual(pair?.earliest.id, "a")
        XCTAssertEqual(pair?.latest.id, "d")
    }

    /// #723-3
    func testMilestoneSubtitles() {
        let months = profile(units: [.day, .month])
        XCTAssertEqual(ComparisonPicker.milestoneSubtitle(latest: date(2026, 11, 5), profile: months, calendar: calendar),
                       "滿 3 個月了")
        XCTAssertNil(ComparisonPicker.milestoneSubtitle(latest: date(2026, 11, 5), profile: profile(), calendar: calendar))
        XCTAssertEqual(ComparisonPicker.milestoneSubtitle(latest: date(2027, 8, 5),
                                                          profile: profile(age: true), calendar: calendar),
                       "滿 1 歲了")
        XCTAssertEqual(ComparisonPicker.milestoneSubtitle(latest: date(2027, 8, 5),
                                                          profile: profile(), calendar: calendar),
                       "滿 1 年了")
        // dayOne: day 100 is start + 99 days = 2026-11-12.
        XCTAssertEqual(ComparisonPicker.milestoneSubtitle(latest: date(2026, 11, 12),
                                                          profile: profile(), calendar: calendar),
                       "滿 100 天了")
        XCTAssertNil(ComparisonPicker.milestoneSubtitle(latest: date(2026, 11, 13),
                                                        profile: profile(), calendar: calendar))
    }

    func testYearBeatsHundredDays() {
        // dayZero: 2027-08-05 is 365 days later; use a start where both coincide.
        let start = DateComponents(year: 2026, month: 8, day: 5)
        let target = calendar.date(from: DateComponents(year: 2027, month: 8, day: 5, hour: 12)) ?? Date()
        let days = DayCountCalculator(calendar: calendar, now: { target })
            .dayCount(from: start, rule: .dayZero)
        XCTAssertEqual(days, 365)
        // Pick a start where the year anniversary lands on a multiple of 100 (leap span: 366 days).
        let leapStart = DateComponents(year: 2023, month: 8, day: 5)
        let leapProfile = CameraProfile(name: "x", startDate: leapStart, countingRule: .dayZero)
        let latest = date(2024, 8, 5)
        XCTAssertEqual(ComparisonPicker.milestoneSubtitle(latest: latest, profile: leapProfile, calendar: calendar),
                       "滿 1 年了")
        let hundred = ComparisonPicker.milestoneSubtitle(latest: date(2026, 11, 13),
                                                         profile: profile(rule: .dayZero), calendar: calendar)
        XCTAssertEqual(hundred, "滿 100 天了")
    }
}
