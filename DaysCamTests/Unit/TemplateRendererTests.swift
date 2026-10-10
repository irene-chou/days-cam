import XCTest
@testable import DaysCam

/// Covers the TASK-04 acceptance table (4.1 ... 4.56), and since 0.2 TASK-27
/// also 27.1: every expected string below is unchanged from 0.1. Only the
/// input changed — each 0.1 `(largest, smallest)` pair is turned into the
/// unit set PRD 0.2 §4.3 maps it to, by `legacyUnits(largest:smallest:)`.
///
/// Reference case throughout, unless a test says otherwise: name 小寶,
/// start 2025-01-15, `.dayOne`, captured 2026-03-20 10:00 Asia/Taipei. That
/// gives n = 430, year track (1, 2, 5), month track (14, 5), week track (61, 3)
/// — all measured on Swift 6.0.3.
final class TemplateRendererTests: XCTestCase {

    private let renderer = TemplateRenderer()

    /// The eight 0.1 `(largest, smallest)` pairs (0.1 PRD §4.1 invariant 4).
    static let legacyPairs: [(largest: DisplayUnit, smallest: DisplayUnit)] = [
        (.day, .day),
        (.week, .day), (.week, .week),
        (.month, .day), (.month, .month),
        (.year, .day), (.year, .month), (.year, .year)
    ]

    /// PRD 0.2 §4.3: a 0.1 pair becomes the units of its track from the
    /// largest down to the smallest. Written out as a table, independently of
    /// the migration code, so a wrong migration cannot pass itself.
    static func legacyUnits(largest: DisplayUnit, smallest: DisplayUnit) -> Set<DisplayUnit> {
        switch (largest, smallest) {
        case (.day, .day): return [.day]
        case (.week, .day): return [.week, .day]
        case (.week, .week): return [.week]
        case (.month, .day): return [.month, .day]
        case (.month, .month): return [.month]
        case (.year, .day): return [.year, .month, .day]
        case (.year, .month): return [.year, .month]
        case (.year, .year): return [.year]
        default: return []
        }
    }

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
                      displayUnits: Self.legacyUnits(largest: largest, smallest: smallest),
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

    /// The pair list really is the eight 0.1 pairs, each mapped to a
    /// distinct, non-empty set.
    func testTheEightLegacyPairsMapToDistinctUnitSets() {
        XCTAssertEqual(Self.legacyPairs.count, 8)
        let sets = Self.legacyPairs.map { Self.legacyUnits(largest: $0.largest, smallest: $0.smallest) }
        XCTAssertFalse(sets.contains { $0.isEmpty })
        XCTAssertEqual(Set(sets).count, 8)
    }

    // MARK: - A-2 (4.9 ... 4.14) date and ordering

    /// TASK-47: a stored profile always has `showDayCount == true` now, so
    /// this (and the date-only cases in A-8 ... A-11) render an unpersisted
    /// profile to isolate the date branch. The renderer's rule is unchanged;
    /// the migrated output is pinned by 47.4 in `CameraProfileDayCountMigrationTests`.
    func testDateOnlyProfileRendersTheDateAlone() throws {
        let output = render(profile(showDayCount: false, showDate: true), at: try referenceCapture())
        XCTAssertEqual(output, "2026.03.20", "4.9")
    }

    /// #249 replaces 4.14's ideographic space with a half-width space.
    func testDateAndCountAreSeparatedByAHalfWidthSpace() throws {
        let output = render(profile(showDate: true), at: try referenceCapture())
        XCTAssertEqual(output, "2026.03.20 第 430 天", "4.10")
        XCTAssertFalse(output.contains("\u{3000}"), "4.14 (#249) separator must be U+0020")
    }

    /// #249: with the count shown the name sits between the date and the count.
    func testNameSitsBetweenDateAndCount() throws {
        let capturedAt = try referenceCapture()
        XCTAssertEqual(render(profile(showDate: true, showName: true), at: capturedAt),
                       "2026.03.20 小寶 第 430 天", "4.11 / 51.1")
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
            // TASK-93 (93.11): all zero reads as the smallest checked unit, 個月, not 0 天.
            ("4.24", DateFixture.components(2026, 1, 1), (2026, 1, 6), .year, .month, true, "0 個月"),
            ("4.25", DateFixture.components(2025, 1, 1), (2026, 1, 1), .month, .day, false, "12 個月"),
            ("4.26", DateFixture.components(2026, 1, 1), (2026, 1, 10), .month, .day, false, "9 天")
        ]
        for (label, start, parts, largest, smallest, ageWording, expected) in cases {
            let capturedAt = try XCTUnwrap(DateFixture.date(parts.0, parts.1, parts.2, hour: 10), label)
            let subject = profile(start: start, largest: largest, smallest: smallest, useAgeWording: ageWording)
            XCTAssertEqual(render(subject, at: capturedAt), expected, label)
        }
    }

    /// TASK-93 (#392): the all-zero fallback uses the smallest checked unit,
    /// so age wording reaches it only when the year is that unit — 4.24
    /// (year + month) says `0 個月`; year alone says `0 歲` (93.2).
    func testAllZeroFallbackUsesTheSmallestCheckedUnitWithAgeWording() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 1, 6, hour: 10))
        let yearAndMonth = profile(start: DateFixture.components(2026, 1, 1),
                                   largest: .year, smallest: .month, useAgeWording: true)
        XCTAssertEqual(render(yearAndMonth, at: capturedAt), "0 個月", "4.24 / 93.11")
        let yearOnly = profile(start: DateFixture.components(2026, 1, 1),
                               largest: .year, smallest: .year, useAgeWording: true)
        XCTAssertEqual(render(yearOnly, at: capturedAt), "0 歲", "93.2")
    }

    // MARK: - TASK-93 (#392) all zero reads as the smallest checked unit

    /// 93.1–93.10: when every checked unit is zero the output is `0` plus the
    /// smallest checked unit's label (天 < 週 < 月 < 年); day-only (U-2) and
    /// non-zero outputs are unchanged. Human decision 2026-10-10.
    func testAllZeroUsesTheSmallestCheckedUnit() throws {
        let cases: [(String, DateComponents, (Int, Int, Int), Set<DisplayUnit>, CountingRule, Bool, String)] = [
            ("93.1", DateFixture.components(2026, 1, 15), (2026, 6, 20), [.year], .dayOne, false, "0 年"),
            ("93.2", DateFixture.components(2026, 1, 15), (2026, 6, 20), [.year], .dayOne, true, "0 歲"),
            ("93.3", DateFixture.components(2026, 10, 1), (2026, 10, 11), [.year, .month], .dayOne, false, "0 個月"),
            ("93.4", DateFixture.components(2026, 10, 1), (2026, 10, 21), [.month], .dayOne, false, "0 個月"),
            ("93.5", DateFixture.components(2026, 10, 1), (2026, 10, 4), [.week], .dayOne, false, "0 週"),
            ("93.6", DateFixture.components(2026, 10, 1), (2026, 10, 6), [.year, .week], .dayOne, false, "0 週"),
            ("93.7", DateFixture.components(2026, 10, 1), (2026, 10, 1), [.week], .dayZero, false, "0 週"),
            ("93.8", DateFixture.components(2026, 10, 1), (2026, 10, 1), [.year, .month, .day], .dayOne, false, "0 天"),
            ("93.9", DateFixture.components(2026, 10, 1), (2026, 10, 11), [.year, .month, .day], .dayOne, false, "10 天"),
            ("93.10", DateFixture.components(2026, 10, 1), (2026, 11, 1), [.year, .month], .dayOne, false, "1 個月")
        ]
        for (label, start, capture, units, rule, ageWording, expected) in cases {
            XCTAssertEqual(try render(start: start, capturedAt: capture, units: units, rule: rule,
                                      useAgeWording: ageWording), expected, label)
        }
    }

    /// 93.12: the two paths beside the all-zero fallback are untouched — the
    /// ordinal day-only form (even 第 0 天) and the not-started text.
    func testDayOnlyAndNotStartedAreUnchangedByTheSmallestUnitRule() throws {
        let start = DateFixture.components(2026, 10, 1)
        XCTAssertEqual(try render(start: start, capturedAt: (2026, 10, 1), units: [.day]), "第 1 天", "93.12")
        XCTAssertEqual(try render(start: start, capturedAt: (2026, 10, 1), units: [.day], rule: .dayZero), "第 0 天", "93.12")
        XCTAssertEqual(try render(start: start, capturedAt: (2026, 9, 21), units: [.year]), "還有 10 天", "93.12")
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
    /// (Still 0 天 after TASK-93: the smallest checked unit here is the day.)
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
    //
    // `showDayCount: false` here isolates the date branch; see the TASK-47
    // note on `testDateOnlyProfileRendersTheDateAlone`.

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
                for pair in Self.legacyPairs {
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
        for pair in Self.legacyPairs {
            let subject = profile(start: start, largest: pair.largest, smallest: pair.smallest)
            XCTAssertEqual(render(subject, at: capturedAt), "還有 73 天",
                           "4.53 \(pair.largest)/\(pair.smallest)")
        }
    }

    func testNotStartedStillComposesWithNameAndDateText() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 9, 19, hour: 10))
        let start = DateFixture.components(2026, 12, 1)
        XCTAssertEqual(render(profile(start: start, showName: true), at: capturedAt),
                       "小寶 還有 73 天", "4.54")
        XCTAssertEqual(render(profile(start: start, showDate: true), at: capturedAt),
                       "2026.09.19 還有 73 天", "4.55")
    }

    /// `.dayOne` with a start date one day out gives n = 0, which is still the
    /// future. Checking the raw difference rather than n is what gets this right.
    func testStartDateOneDayAheadIsNotStartedUnderDayOne() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 3, 20, hour: 10))
        let subject = profile(start: DateFixture.components(2026, 3, 21))
        XCTAssertEqual(render(subject, at: capturedAt), "還有 1 天")
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

// MARK: - #249 (TASK-51): name in the middle, half-width separators

extension TemplateRendererTests {

    /// 51.2: every other combination keeps its order; nothing uses U+3000.
    func testOtherCombinationsKeepTheirOrderWithHalfWidthSpaces() throws {
        let capturedAt = try referenceCapture()
        let cases: [(CameraProfile, String)] = [
            (profile(), "第 430 天"),
            (profile(showDate: true), "2026.03.20 第 430 天"),
            (profile(showName: true), "小寶 第 430 天"),
            (profile(showDayCount: false, showDate: true, showName: true), "小寶 2026.03.20")
        ]
        for (subject, expected) in cases {
            let output = render(subject, at: capturedAt)
            XCTAssertEqual(output, expected, "51.2")
            XCTAssertFalse(output.contains("\u{3000}"), "51.2 \(expected)")
        }
    }

    /// 51.3: the not-started text takes the count's place.
    func testNotStartedSitsAfterDateAndName() throws {
        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 9, 19, hour: 10))
        let subject = profile(start: DateFixture.components(2026, 12, 1), showDate: true, showName: true)
        XCTAssertEqual(render(subject, at: capturedAt), "2026.09.19 小寶 還有 73 天", "51.3")
    }

    /// 51.4: a blank name drops out without leaving a double space.
    func testBlankNameBetweenDateAndCountLeavesNoExtraSpace() throws {
        let subject = profile(name: "  ", showDate: true, showName: true)
        XCTAssertEqual(render(subject, at: try referenceCapture()), "2026.03.20 第 430 天", "51.4")
    }

    /// 51.5: age wording and multiple units do not move the name.
    func testNameStaysInTheMiddleForMultiUnitAndAgeWording() throws {
        let capturedAt = try referenceCapture()
        XCTAssertEqual(render(profile(showDate: true, showName: true,
                                      largest: .year, smallest: .day, useAgeWording: true),
                              at: capturedAt),
                       "2026.03.20 小寶 1 歲 2 個月 5 天", "51.5")
        XCTAssertEqual(render(profile(showDate: true, showName: true, largest: .week, smallest: .day),
                              at: capturedAt),
                       "2026.03.20 小寶 61 週又 3 天", "51.5")
    }
}

// MARK: - 0.2 TASK-27: any combination of units

/// Covers TASK-27 27.2 ... 27.10 and the PRD 0.2 §4.5 reference table.
final class TemplateRendererUnitSetTests: XCTestCase {

    private func render(start: DateComponents,
                        capturedAt: (Int, Int, Int),
                        units: Set<DisplayUnit>,
                        rule: CountingRule = .dayOne,
                        useAgeWording: Bool = false) throws -> String {
        let moment = try XCTUnwrap(DateFixture.date(capturedAt.0, capturedAt.1, capturedAt.2, hour: 10))
        let profile = CameraProfile(name: "小寶", startDate: start, countingRule: rule,
                                    displayUnits: units, useAgeWording: useAgeWording)
        return TemplateRenderer().render(profile: profile, capturedAt: moment, calendar: DateFixture.taipei)
    }

    private let reference = DateFixture.components(2025, 1, 15)
    private let referenceCapture = (2026, 3, 20)

    /// PRD 0.2 §4.5 table, reference case n = 430.
    func testReferenceTable() throws {
        let cases: [(String, Set<DisplayUnit>, String)] = [
            ("天", [.day], "第 430 天"),
            ("週天", [.week, .day], "61 週又 3 天"),
            ("月天", [.month, .day], "14 個月又 5 天"),
            ("年月", [.year, .month], "1 年 2 個月"),
            ("年月天", [.year, .month, .day], "1 年 2 個月 5 天"),
            ("27.2 年天", [.year, .day], "1 年 64 天"),
            ("27.3 年月週天", [.year, .month, .week, .day], "1 年 2 個月 5 天"),
            ("27.4 月週", [.month, .week], "14 個月")
        ]
        for (label, units, expected) in cases {
            XCTAssertEqual(try render(start: reference, capturedAt: referenceCapture, units: units), expected, label)
        }
    }

    func testWeeksAfterYearsAndMonths() throws {
        let start = DateFixture.components(2024, 8, 1)
        let capture = (2026, 1, 22)
        XCTAssertEqual(try render(start: start, capturedAt: capture, units: [.year, .month, .week]),
                       "1 年 5 個月 3 週", "27.5")
        XCTAssertEqual(try render(start: start, capturedAt: capture, units: [.month, .week]),
                       "17 個月又 3 週", "27.6")
        XCTAssertEqual(try render(start: start, capturedAt: capture, units: [.year, .month]),
                       "1 年 5 個月", "27.7")
        XCTAssertEqual(try render(start: start, capturedAt: capture, units: [.year, .month, .week, .day]),
                       "1 年 5 個月 3 週", "21 days is exactly 3 weeks, day omitted")
    }

    func testCountingRuleAppliesOnlyWithoutYearAndMonth() throws {
        let start = DateFixture.components(2026, 1, 1)
        let capture = (2026, 1, 10)
        XCTAssertEqual(try render(start: start, capturedAt: capture, units: [.week, .day]), "1 週又 3 天", "27.8")
        XCTAssertEqual(try render(start: start, capturedAt: capture, units: [.month, .day]), "9 天", "27.9")
        XCTAssertEqual(try render(start: start, capturedAt: capture, units: [.week, .day], rule: .dayZero),
                       "1 週又 2 天")
    }

    func testFebruary29ClampsToAFullYear() throws {
        XCTAssertEqual(try render(start: DateFixture.components(2024, 2, 29), capturedAt: (2025, 2, 28),
                                  units: [.year, .month, .day]), "1 年", "27.10")
    }

    /// U-8 is decided by the checked units, not by the non-zero segments.
    func testConnectiveFollowsTheCheckedUnits() throws {
        // Three checked units, no year: spaces even though only two show.
        XCTAssertEqual(try render(start: reference, capturedAt: referenceCapture, units: [.month, .week, .day]),
                       "14 個月 5 天")
        // Two checked units with a year: a space.
        XCTAssertEqual(try render(start: reference, capturedAt: referenceCapture, units: [.year, .week]),
                       "1 年 9 週")
    }

    func testAgeWordingAndAllZero() throws {
        XCTAssertEqual(try render(start: reference, capturedAt: referenceCapture, units: [.year, .day],
                                  useAgeWording: true), "1 歲 64 天", "U-9")
        let start = DateFixture.components(2026, 1, 1)
        // U-7 as changed by TASK-93: the smallest checked unit, not 天.
        XCTAssertEqual(try render(start: start, capturedAt: (2026, 1, 1), units: [.year, .month]), "0 個月", "U-7 / 93.3")
        XCTAssertEqual(try render(start: start, capturedAt: (2026, 1, 3), units: [.week]), "0 週", "U-7 / 93.5")
    }

    func testFutureStartIsNotStartedForAnySet() throws {
        for units: Set<DisplayUnit> in [[.day], [.year, .week], [.month, .week, .day]] {
            XCTAssertEqual(try render(start: DateFixture.components(2026, 12, 1), capturedAt: (2026, 9, 19),
                                      units: units), "還有 73 天", "\(units)")
        }
    }
}

// MARK: - #250 (TASK-52): 還有 N 天 before the start date

extension TemplateRendererTests {

    /// 52.1: a start date tomorrow is one day away under either rule.
    func testStartDateTomorrowIsOneDayAwayUnderEitherRule() throws {
        let capturedAt = try referenceCapture()
        let tomorrow = DateFixture.components(2026, 3, 21)
        for rule in [CountingRule.dayOne, .dayZero] {
            XCTAssertEqual(render(profile(start: tomorrow, rule: rule), at: capturedAt),
                           "還有 1 天", "52.1 \(rule)")
        }
    }

    /// 52.2: the distance is printed in days however far away it is.
    func testDistanceIsPrintedInDays() throws {
        let capturedAt = try referenceCapture() // 2026-03-20
        let cases: [(DateComponents, String)] = [
            (DateFixture.components(2026, 3, 23), "還有 3 天"),
            (DateFixture.components(2026, 4, 29), "還有 40 天"),
            (DateFixture.components(2027, 4, 24), "還有 400 天")
        ]
        for (start, expected) in cases {
            XCTAssertEqual(render(profile(start: start), at: capturedAt), expected, "52.2")
        }
    }

    /// 52.3: neither the checked units nor age wording reach the distance.
    func testDistanceIgnoresUnitsAndAgeWording() throws {
        let capturedAt = try referenceCapture()
        let start = DateFixture.components(2026, 4, 29)
        XCTAssertEqual(render(profile(start: start, largest: .year, smallest: .month, useAgeWording: true),
                              at: capturedAt),
                       "還有 40 天", "52.3")
        XCTAssertEqual(render(profile(start: start, largest: .year, smallest: .day), at: capturedAt),
                       "還有 40 天", "52.3")
    }

    /// 52.4: the start date itself is unchanged.
    func testStartDateItselfIsUnchanged() throws {
        let capturedAt = try referenceCapture()
        let today = DateFixture.components(2026, 3, 20)
        XCTAssertEqual(render(profile(start: today, rule: .dayOne), at: capturedAt), "第 1 天", "52.4")
        XCTAssertEqual(render(profile(start: today, rule: .dayZero), at: capturedAt), "第 0 天", "52.4")
    }

    /// 52.5: the distance takes the count's place next to the date and name.
    func testDistanceComposesWithDateAndName() throws {
        let capturedAt = try referenceCapture()
        let start = DateFixture.components(2026, 3, 23)
        XCTAssertEqual(render(profile(start: start, showDate: true), at: capturedAt),
                       "2026.03.20 還有 3 天", "52.5")
        XCTAssertEqual(render(profile(start: start, showName: true), at: capturedAt),
                       "小寶 還有 3 天", "52.5")
        XCTAssertEqual(render(profile(start: start, showDate: true, showName: true), at: capturedAt),
                       "2026.03.20 小寶 還有 3 天", "52.5")
    }

    /// 52.6: calendar days in the capture's time zone, across a DST change.
    func testDistanceCountsCalendarDaysAcrossTimeZonesAndDST() throws {
        // 2026-01-09 20:00 UTC is already 01-10 in Taipei, still 01-09 in New York.
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 9, hour: 20, in: DateFixture.utc))
        let start = DateFixture.components(2026, 1, 11)
        XCTAssertEqual(render(profile(start: start), at: instant, calendar: DateFixture.taipei),
                       "還有 1 天", "52.6")
        XCTAssertEqual(render(profile(start: start), at: instant, calendar: DateFixture.newYork),
                       "還有 2 天", "52.6")

        // New York springs forward on 2026-03-08; the 23-hour day still counts once.
        let lateEvening = try XCTUnwrap(DateFixture.date(2026, 3, 7, hour: 23, in: DateFixture.newYork))
        XCTAssertEqual(render(profile(start: DateFixture.components(2026, 3, 8)),
                              at: lateEvening, calendar: DateFixture.newYork),
                       "還有 1 天", "52.6")
        XCTAssertEqual(render(profile(start: DateFixture.components(2026, 3, 10)),
                              at: lateEvening, calendar: DateFixture.newYork),
                       "還有 3 天", "52.6")
    }
}
