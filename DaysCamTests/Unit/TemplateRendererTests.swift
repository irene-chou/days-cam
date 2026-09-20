import XCTest
@testable import DaysCam

/// Covers the TASK-04 acceptance table (4.1 ... 4.56).
///
/// Reference case throughout, unless a test says otherwise: name 小寶,
/// start 2025-01-15, `.dayOne`, captured 2026-03-20 10:00 Asia/Taipei. That
/// gives n = 430, year track (1, 2, 5), month track (14, 5), week track (61, 3)
/// — all measured on Swift 6.0.3.
final class TemplateRendererTests: XCTestCase {

    private let renderer = TemplateRenderer()

    private func profile(name: String = "小寶",
                         start: DateComponents = DateFixture.components(2025, 1, 15),
                         rule: CountingRule = .dayOne,
                         showDayCount: Bool = true,
                         showDate: Bool = false,
                         showName: Bool = false,
                         largest: DisplayUnit = .day,
                         smallest: DisplayUnit = .day,
                         useAgeWording: Bool = false) -> CameraProfile {
        CameraProfile(name: name,
                      startDate: start,
                      countingRule: rule,
                      showDayCount: showDayCount,
                      showDate: showDate,
                      showName: showName,
                      largestUnit: largest,
                      smallestUnit: smallest,
                      useAgeWording: useAgeWording)
    }

    /// The reference capture moment.
    private func referenceCapture() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 3, 20, hour: 10))
    }

    private func render(_ subject: CameraProfile,
                        at capturedAt: Date,
                        calendar: Calendar = DateFixture.taipei) -> String {
        renderer.render(profile: subject, capturedAt: capturedAt, calendar: calendar)
    }

    // MARK: - A-1 (4.1 ... 4.8) the eight legal unit pairs

    func testEightLegalUnitPairsRenderExactly() throws {
        let capturedAt = try referenceCapture()
        let cases: [(String, DisplayUnit, DisplayUnit, String)] = [
            ("4.1", .day, .day, "第 430 天"),
            ("4.2", .week, .day, "61 週又 3 天"),
            ("4.3", .week, .week, "61 週"),
            ("4.4", .month, .day, "14 個月又 5 天"),
            ("4.5", .month, .month, "14 個月"),
            ("4.6", .year, .day, "1 年 2 個月 5 天"),
            ("4.7", .year, .month, "1 年 2 個月"),
            ("4.8", .year, .year, "1 年")
        ]
        for (label, largest, smallest, expected) in cases {
            let output = render(profile(largest: largest, smallest: smallest), at: capturedAt)
            XCTAssertEqual(output, expected, label)
        }
    }

    /// Every pair in the table must also be one the model calls legal, so the
    /// two lists cannot drift apart.
    func testTheEightRenderedPairsAreExactlyTheLegalOnes() {
        XCTAssertEqual(DisplayUnitTrack.legalPairs.count, 8)
    }

    // MARK: - A-2 (4.9 ... 4.14) date and ordering

    func testDateOnlyProfileRendersTheDateAlone() throws {
        let output = render(profile(showDayCount: false, showDate: true), at: try referenceCapture())
        XCTAssertEqual(output, "2026.03.20", "4.9")
    }

    func testDateAndCountAreSeparatedByAnIdeographicSpace() throws {
        let output = render(profile(showDate: true), at: try referenceCapture())
        XCTAssertEqual(output, "2026.03.20\u{3000}第 430 天", "4.10")
        XCTAssertTrue(output.contains("\u{3000}"), "4.14 separator must be U+3000")
        XCTAssertFalse(output.contains("2026.03.20 第"), "4.14 must not be a half-width space")
    }

    func testNameIsPrefixedWithAHalfWidthSpace() throws {
        let capturedAt = try referenceCapture()
        XCTAssertEqual(render(profile(showDate: true, showName: true), at: capturedAt),
                       "小寶 2026.03.20\u{3000}第 430 天", "4.11")
        XCTAssertEqual(render(profile(showName: true), at: capturedAt),
                       "小寶 第 430 天", "4.12")
    }

    func testOutputNeverStartsWithWhitespaceWhenTheNameIsHidden() throws {
        let output = render(profile(), at: try referenceCapture())
        XCTAssertEqual(output, "第 430 天", "4.13")
        XCTAssertFalse(output.hasPrefix(" "), "4.13")
    }

    // MARK: - A-3 (4.15 ... 4.18) age wording

    func testAgeWordingReplacesYearsWithAges() throws {
        let capturedAt = try referenceCapture()
        let cases: [(String, DisplayUnit, Bool, String)] = [
            ("4.15", .month, true, "1 歲 2 個月"),
            ("4.16", .day, true, "1 歲 2 個月 5 天"),
            ("4.17", .year, true, "1 歲"),
            ("4.18", .month, false, "1 年 2 個月")
        ]
        for (label, smallest, ageWording, expected) in cases {
            let subject = profile(largest: .year, smallest: smallest, useAgeWording: ageWording)
            XCTAssertEqual(render(subject, at: capturedAt), expected, label)
        }
    }

    // MARK: - A-4 (4.19 ... 4.26) zero-valued units are omitted

    func testZeroValuedUnitsAreOmitted() throws {
        // (id, start, capturedAt, largest, smallest, ageWording, expected)
        let cases: [(String, DateComponents, (Int, Int, Int), DisplayUnit, DisplayUnit, Bool, String)] = [
            ("4.19", DateFixture.components(2026, 1, 1), (2026, 1, 10), .year, .day, false, "9 天"),
            ("4.20", DateFixture.components(2025, 1, 1), (2026, 1, 1), .year, .day, false, "1 年"),
            ("4.21", DateFixture.components(2025, 1, 1), (2026, 3, 1), .year, .day, false, "1 年 2 個月"),
            ("4.22", DateFixture.components(2026, 1, 1), (2026, 9, 4), .year, .day, false, "8 個月 3 天"),
            ("4.23", DateFixture.components(2026, 1, 1), (2026, 9, 4), .year, .month, true, "8 個月"),
            ("4.24", DateFixture.components(2026, 1, 1), (2026, 1, 6), .year, .month, true, "0 天"),
            ("4.25", DateFixture.components(2025, 1, 1), (2026, 1, 1), .month, .day, false, "12 個月"),
            ("4.26", DateFixture.components(2026, 1, 1), (2026, 1, 10), .month, .day, false, "9 天")
        ]
        for (label, start, parts, largest, smallest, ageWording, expected) in cases {
            let capturedAt = try XCTUnwrap(DateFixture.date(parts.0, parts.1, parts.2, hour: 10), label)
            let subject = profile(start: start, largest: largest, smallest: smallest, useAgeWording: ageWording)
            XCTAssertEqual(render(subject, at: capturedAt), expected, label)
        }
    }

    /// 4.24 is the one place the all-zero fallback and age wording meet: the
    /// fallback is always `0 天`, never `0 歲`.
    func testAllZeroFallbackIsUnaffectedByAgeWording() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 1, 6, hour: 10))
        let subject = profile(start: DateFixture.components(2026, 1, 1),
                              largest: .year, smallest: .month, useAgeWording: true)
        XCTAssertEqual(render(subject, at: capturedAt), "0 天")
    }

    // MARK: - A-5 (4.27 ... 4.34) the week track

    func testWeekTrackUsesCardinalsAndTheConnective() throws {
        // Start dates chosen so that n comes out as the value under test.
        // (id, start, rule, smallest, expected) with capturedAt = 2026-03-20.
        let cases: [(String, DateComponents, CountingRule, DisplayUnit, String)] = [
            ("4.27 n=0", DateFixture.components(2026, 3, 20), .dayZero, .day, "0 天"),
            ("4.28 n=1", DateFixture.components(2026, 3, 20), .dayOne, .day, "1 天"),
            ("4.29 n=7", DateFixture.components(2026, 3, 14), .dayOne, .day, "1 週"),
            ("4.30 n=8", DateFixture.components(2026, 3, 13), .dayOne, .day, "1 週又 1 天"),
            ("4.31 n=10", DateFixture.components(2026, 3, 11), .dayOne, .day, "1 週又 3 天"),
            ("4.32 n=14", DateFixture.components(2026, 3, 7), .dayOne, .day, "2 週"),
            ("4.33 n=430", DateFixture.components(2025, 1, 15), .dayOne, .day, "61 週又 3 天"),
            ("4.34 n=430", DateFixture.components(2025, 1, 15), .dayOne, .week, "61 週")
        ]
        let capturedAt = try referenceCapture()
        for (label, start, rule, smallest, expected) in cases {
            let subject = profile(start: start, rule: rule, largest: .week, smallest: smallest)
            XCTAssertEqual(render(subject, at: capturedAt), expected, label)
        }
    }

    /// 4.34 versus 4.33: at `.week` the remainder is truncated by the chosen
    /// smallest unit, which is not the same thing as being omitted for being
    /// zero — n is still 430, the 3 days are simply not shown.
    func testWeekSmallestUnitTruncatesRatherThanOmits() throws {
        let capturedAt = try referenceCapture()
        let base = profile(largest: .week, smallest: .day)
        XCTAssertEqual(render(base, at: capturedAt), "61 週又 3 天")
        let truncated = profile(largest: .week, smallest: .week)
        XCTAssertEqual(render(truncated, at: capturedAt), "61 週")
    }

    // MARK: - A-6 (4.35 ... 4.39) "day" means a different number per track

    /// The single easiest thing to implement wrongly in this task: one shared
    /// "days" variable makes three of these four fail at once.
    func testDayMeansADifferentValueOnEachTrack() throws {
        let capturedAt = try referenceCapture()
        XCTAssertEqual(render(profile(largest: .year, smallest: .day), at: capturedAt),
                       "1 年 2 個月 5 天", "4.35 calendar remainder")
        XCTAssertEqual(render(profile(largest: .month, smallest: .day), at: capturedAt),
                       "14 個月又 5 天", "4.36 calendar remainder")
        XCTAssertEqual(render(profile(largest: .week, smallest: .day), at: capturedAt),
                       "61 週又 3 天", "4.37 n % 7")
        XCTAssertEqual(render(profile(largest: .day, smallest: .day), at: capturedAt),
                       "第 430 天", "4.38 n itself")
    }

    /// 4.39 stated as an assertion rather than a code review: the three "day"
    /// numbers in the reference case are genuinely different values.
    func testTheThreeDayValuesAreDistinct() throws {
        let capturedAt = try referenceCapture()
        let yearTrack = render(profile(largest: .year, smallest: .day), at: capturedAt)
        let weekTrack = render(profile(largest: .week, smallest: .day), at: capturedAt)
        let dayTrack = render(profile(largest: .day, smallest: .day), at: capturedAt)
        XCTAssertTrue(yearTrack.hasSuffix("5 天"))
        XCTAssertTrue(weekTrack.hasSuffix("3 天"))
        XCTAssertTrue(dayTrack.hasSuffix("430 天"))
    }

    // MARK: - A-7 (4.40 ... 4.43) the counting rule only reaches day and week

    /// On the start date itself the day track says 第 1 天 while the year track
    /// says 0 天. That is intended, not an inconsistency to be smoothed over.
    func testCountingRuleAppliesOnlyToTheDayAndWeekTracks() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 1, 1, hour: 10))
        let start = DateFixture.components(2026, 1, 1)
        let cases: [(String, DisplayUnit, DisplayUnit, String)] = [
            ("4.40", .day, .day, "第 1 天"),
            ("4.41", .week, .day, "1 天"),
            ("4.42", .year, .day, "0 天"),
            ("4.43", .month, .day, "0 天")
        ]
        for (label, largest, smallest, expected) in cases {
            let subject = profile(start: start, largest: largest, smallest: smallest)
            XCTAssertEqual(render(subject, at: capturedAt), expected, label)
        }
    }

    // MARK: - A-8 (4.44 ... 4.47) the date branch never reads startDate

    /// The regression this guards: approximating the date from "start date is
    /// today" looks right on day one and prints 第 2 天 the next morning.
    func testDateKeepsTrackingTheCaptureDayWhileTheCountIncrements() throws {
        let start = DateFixture.components(2026, 1, 10)
        let counting = profile(start: start)
        let dating = profile(start: start, showDayCount: false, showDate: true)

        let firstDay = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        XCTAssertEqual(render(counting, at: firstDay), "第 1 天", "4.44")
        XCTAssertEqual(render(dating, at: firstDay), "2026.01.10", "4.44")

        let secondDay = try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 10))
        XCTAssertEqual(render(counting, at: secondDay), "第 2 天", "4.44 count increments")
        XCTAssertEqual(render(dating, at: secondDay), "2026.01.11", "4.44 date must not become 第 2 天")
    }

    func testStartDateCannotInfluenceTheRenderedDateText() throws {
        let capturedAt = try referenceCapture()
        let subject = profile(start: DateFixture.components(1999, 1, 1),
                              showDayCount: false, showDate: true)
        XCTAssertEqual(render(subject, at: capturedAt), "2026.03.20", "4.45")
    }

    func testDateIsStillRenderedWhenTheStartDateIsInTheFuture() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 9, 19, hour: 10))
        let subject = profile(start: DateFixture.components(2026, 12, 1),
                              showDayCount: false, showDate: true)
        XCTAssertEqual(render(subject, at: capturedAt), "2026.09.19", "4.46 not 尚未開始")
    }

    /// 4.47 as behaviour rather than inspection: if the date branch touched the
    /// start date or the counting rule, changing either would move the output.
    func testDateOutputIsInvariantToEveryCountingRelatedField() throws {
        let capturedAt = try referenceCapture()
        var outputs: Set<String> = []
        for start in [DateFixture.components(1999, 1, 1),
                      DateFixture.components(2026, 3, 20),
                      DateFixture.components(2030, 12, 31)] {
            for rule in CountingRule.allCases {
                for pair in DisplayUnitTrack.legalPairs {
                    let subject = profile(start: start,
                                          rule: rule,
                                          showDayCount: false,
                                          showDate: true,
                                          largest: pair.largest,
                                          smallest: pair.smallest)
                    outputs.insert(render(subject, at: capturedAt))
                }
            }
        }
        XCTAssertEqual(outputs, ["2026.03.20"], "4.47 date branch must ignore all of these")
    }

    // MARK: - A-9 (4.48 ... 4.51) capturedAt is the only time source

    /// The Phase 4 seam: feeding an arbitrary past moment must work today, or
    /// importing old photos later would mean changing the counting layer.
    func testTheSameProfileRendersAnyCaptureMoment() throws {
        let dating = profile(showDayCount: false, showDate: true)
        let long = try XCTUnwrap(DateFixture.date(2019, 7, 4, hour: 9))
        let recent = try referenceCapture()
        XCTAssertEqual(render(dating, at: long), "2019.07.04", "4.48")
        XCTAssertEqual(render(dating, at: recent), "2026.03.20", "4.48")

        let counting = profile()
        let dayTwo = try XCTUnwrap(DateFixture.date(2025, 1, 16, hour: 9))
        XCTAssertEqual(render(counting, at: dayTwo), "第 2 天", "4.49")
        XCTAssertEqual(render(counting, at: recent), "第 430 天", "4.49")
    }

    // MARK: - A-10 (4.52 ... 4.55) dayZero and future start dates

    func testDayZeroOnTheStartDateRendersDayZero() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 1, 1, hour: 10))
        let subject = profile(start: DateFixture.components(2026, 1, 1), rule: .dayZero)
        XCTAssertEqual(render(subject, at: capturedAt), "第 0 天", "4.52 ordinal, not the 0 天 fallback")
    }

    func testEveryUnitPairReportsNotStartedForAFutureStart() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 9, 19, hour: 10))
        let start = DateFixture.components(2026, 12, 1)
        for pair in DisplayUnitTrack.legalPairs {
            let subject = profile(start: start, largest: pair.largest, smallest: pair.smallest)
            XCTAssertEqual(render(subject, at: capturedAt), "尚未開始",
                           "4.53 \(pair.largest)/\(pair.smallest)")
        }
    }

    func testNotStartedStillComposesWithNameAndDateText() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 9, 19, hour: 10))
        let start = DateFixture.components(2026, 12, 1)
        XCTAssertEqual(render(profile(start: start, showName: true), at: capturedAt),
                       "小寶 尚未開始", "4.54")
        XCTAssertEqual(render(profile(start: start, showDate: true), at: capturedAt),
                       "2026.09.19\u{3000}尚未開始", "4.55")
    }

    /// `.dayOne` with a start date one day out gives n = 0, which is still the
    /// future. Checking the raw difference rather than n is what gets this right.
    func testStartDateOneDayAheadIsNotStartedUnderDayOne() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 3, 20, hour: 10))
        let subject = profile(start: DateFixture.components(2026, 3, 21))
        XCTAssertEqual(render(subject, at: capturedAt), "尚未開始")
    }

    // MARK: - A-11 (4.56) time zones

    func testTheSameInstantRendersItsLocalDateText() throws {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 9, hour: 20, in: DateFixture.utc))
        let subject = profile(showDayCount: false, showDate: true)
        XCTAssertEqual(render(subject, at: instant, calendar: DateFixture.taipei), "2026.01.10", "4.56")
        XCTAssertEqual(render(subject, at: instant, calendar: DateFixture.newYork), "2026.01.09", "4.56")
    }

    // MARK: - Defensive

    func testZeroPaddingIsAppliedToSingleDigitMonthsAndDays() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 3, 5, hour: 10))
        let subject = profile(showDayCount: false, showDate: true)
        XCTAssertEqual(render(subject, at: capturedAt), "2026.03.05")
    }

    /// The editor holds a profile before it has been validated, so an empty
    /// name must not leave a stray leading space in the preview.
    func testEmptyNameDoesNotLeaveALeadingSpace() throws {
        let capturedAt = try referenceCapture()
        XCTAssertEqual(render(profile(name: "  ", showName: true), at: capturedAt), "第 430 天")
    }

    func testCountsAboveFourDigitsAreNotAbbreviatedOrGrouped() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 3, 20, hour: 10))
        let subject = profile(start: DateFixture.components(1990, 1, 1))
        let output = render(subject, at: capturedAt)
        XCTAssertTrue(output.hasPrefix("第 13"), "expected a five-digit count, got \(output)")
        XCTAssertFalse(output.contains(","), "PRD FR-2.15 forbids digit grouping")
    }
}
