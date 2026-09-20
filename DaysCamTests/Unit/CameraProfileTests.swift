import XCTest
@testable import DaysCam

/// Covers the five invariants of PRD §4.1 at the model level.
///
/// `ProfileStore` is the layer that has to call these; TASK-03 will test the
/// file round trip. What is pinned here is that the rules exist, that the
/// memberwise initializer does not enforce them, and which deviations are
/// repaired versus rejected.
final class CameraProfileTests: XCTestCase {

    private func profile(name: String = "小寶",
                         startDate: DateComponents = DateFixture.components(2025, 1, 15),
                         showDayCount: Bool = true,
                         showDate: Bool = false,
                         largestUnit: DisplayUnit = .day,
                         smallestUnit: DisplayUnit = .day,
                         useAgeWording: Bool = false) -> CameraProfile {
        CameraProfile(name: name,
                      startDate: startDate,
                      showDayCount: showDayCount,
                      showDate: showDate,
                      largestUnit: largestUnit,
                      smallestUnit: smallestUnit,
                      useAgeWording: useAgeWording)
    }

    private func expectValidationFailure(_ subject: CameraProfile,
                                         _ expected: CameraProfileValidationError,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) {
        XCTAssertThrowsError(try subject.validatedForPersistence(calendar: DateFixture.taipei),
                             file: file, line: line) { error in
            XCTAssertEqual(error as? CameraProfileValidationError, expected, file: file, line: line)
        }
    }

    // MARK: - Defaults

    /// PRD FR-1.9 / §4.3: the defaults a new profile starts from.
    func testDefaultsMatchTheSpecifiedNewProfileValues() {
        let subject = CameraProfile(name: "預設", startDate: DateFixture.components(2026, 1, 10))
        XCTAssertEqual(subject.countingRule, .dayOne)
        XCTAssertTrue(subject.showDayCount)
        XCTAssertFalse(subject.showDate)
        XCTAssertFalse(subject.showName)
        XCTAssertEqual(subject.largestUnit, .day)
        XCTAssertEqual(subject.smallestUnit, .day)
        XCTAssertFalse(subject.useAgeWording)
        XCTAssertEqual(subject.position, .bottomTrailing)
        XCTAssertEqual(subject.themeID, .classicWhite)
    }

    /// The initializer must accept invalid states so that an editing screen can
    /// hold a half-typed profile and so that tests can build one to reject.
    func testMemberwiseInitializerDoesNotValidate() {
        let invalid = profile(name: "", showDayCount: false, showDate: false, largestUnit: .week, smallestUnit: .month)
        XCTAssertEqual(invalid.name, "")
        XCTAssertThrowsError(try invalid.validate(calendar: DateFixture.taipei))
    }

    func testCodableRoundTripPreservesEveryField() throws {
        var subject = profile(showDate: true, largestUnit: .year, smallestUnit: .month, useAgeWording: true)
        subject.showName = true
        subject.position = .topLeading
        subject.themeID = .filmStrip
        subject.countingRule = .dayZero

        let data = try JSONEncoder().encode(subject)
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: data)
        XCTAssertEqual(decoded, subject)
    }

    // MARK: - Invariant 1: name

    func testValidNameLengthsAreAccepted() throws {
        XCTAssertNoThrow(try profile(name: "小").validatedForPersistence(calendar: DateFixture.taipei))
        XCTAssertNoThrow(try profile(name: String(repeating: "一", count: 20))
            .validatedForPersistence(calendar: DateFixture.taipei))
    }

    func testEmptyOrWhitespaceOnlyNameIsRejected() {
        expectValidationFailure(profile(name: ""), .nameEmpty)
        expectValidationFailure(profile(name: "   "), .nameEmpty)
    }

    func testNameLongerThanTwentyCharactersIsRejected() {
        expectValidationFailure(profile(name: String(repeating: "一", count: 21)), .nameTooLong(length: 21))
    }

    func testNormalizationTrimsSurroundingWhitespace() throws {
        let normalized = try profile(name: "  小寶  ").validatedForPersistence(calendar: DateFixture.taipei)
        XCTAssertEqual(normalized.name, "小寶")
    }

    // MARK: - Invariant 2: startDate is exactly year/month/day

    func testStrippableStartDateComponentsAreRemovedNotRejected() throws {
        var polluted = DateFixture.components(2026, 1, 15)
        polluted.hour = 13
        polluted.minute = 30
        polluted.second = 45
        polluted.timeZone = TimeZone(identifier: "Asia/Taipei")
        polluted.calendar = Calendar(identifier: .buddhist)

        let cleaned = try profile(startDate: polluted).validatedForPersistence(calendar: DateFixture.taipei)
        XCTAssertEqual(cleaned.startDate.year, 2026)
        XCTAssertEqual(cleaned.startDate.month, 1)
        XCTAssertEqual(cleaned.startDate.day, 15)
        XCTAssertNil(cleaned.startDate.hour)
        XCTAssertNil(cleaned.startDate.minute)
        XCTAssertNil(cleaned.startDate.second)
        XCTAssertNil(cleaned.startDate.timeZone)
        XCTAssertNil(cleaned.startDate.calendar)
        XCTAssertTrue(cleaned.startDate.carriesOnlyYearMonthDay)
    }

    /// Stripping a `timeZone` is not cosmetic: left in place it moves the start
    /// date a whole day when the device is west of the stored zone, and
    /// `startOfDay` cannot recover it (PRD §4.1, TASK-03 3.27).
    func testStrippingTimeZoneRemovesTheOffByOneDay() throws {
        var polluted = DateFixture.components(2026, 1, 15)
        polluted.timeZone = TimeZone(identifier: "Asia/Taipei")

        let now = try XCTUnwrap(DateFixture.date(2026, 1, 20, hour: 12, in: DateFixture.newYork))
        let calculator = DayCountCalculator(calendar: DateFixture.newYork, now: { now })

        XCTAssertEqual(calculator.rawDayDifference(from: polluted), 6, "polluted input is off by one day")
        let cleaned = try profile(startDate: polluted).validatedForPersistence(calendar: DateFixture.newYork)
        XCTAssertEqual(calculator.rawDayDifference(from: cleaned.startDate), 5)
    }

    func testValidateRejectsUnstrippedExtraComponents() {
        var polluted = DateFixture.components(2026, 1, 15)
        polluted.hour = 13
        XCTAssertThrowsError(try profile(startDate: polluted).validate(calendar: DateFixture.taipei)) { error in
            XCTAssertEqual(error as? CameraProfileValidationError, .startDateHasExtraComponents)
        }
    }

    func testStartDateValuesThatNameNoRealDayAreRejected() {
        expectValidationFailure(profile(startDate: DateFixture.components(2026, 13, 1)), .startDateNotARealDate)
        expectValidationFailure(profile(startDate: DateFixture.components(2026, 2, 30)), .startDateNotARealDate)
        expectValidationFailure(profile(startDate: DateFixture.components(2026, 1, 0)), .startDateNotARealDate)
    }

    /// A missing `day` cannot be caught by a round trip — `Calendar.date(from:)`
    /// silently substitutes the first of the month — so the nil check has to be
    /// explicit.
    func testStartDateMissingAComponentIsRejected() {
        var missingDay = DateComponents()
        missingDay.year = 2026
        missingDay.month = 2
        expectValidationFailure(profile(startDate: missingDay), .startDateMissingComponents)

        var missingYear = DateComponents()
        missingYear.month = 2
        missingYear.day = 1
        expectValidationFailure(profile(startDate: missingYear), .startDateMissingComponents)
    }

    func testFebruary29InALeapYearIsAccepted() throws {
        XCTAssertNoThrow(try profile(startDate: DateFixture.components(2024, 2, 29))
            .validatedForPersistence(calendar: DateFixture.taipei))
    }

    // MARK: - Invariant 3: display switches

    func testDayCountAndDateCannotBothBeOff() {
        expectValidationFailure(profile(showDayCount: false, showDate: false), .displaySwitchesAllOff)
    }

    func testEitherDisplaySwitchAloneIsEnough() {
        XCTAssertNoThrow(try profile(showDayCount: true, showDate: false)
            .validatedForPersistence(calendar: DateFixture.taipei))
        XCTAssertNoThrow(try profile(showDayCount: false, showDate: true)
            .validatedForPersistence(calendar: DateFixture.taipei))
    }

    // MARK: - Invariant 4: unit pair

    func testAllEightLegalUnitPairsValidate() {
        for pair in DisplayUnitTrack.legalPairs {
            let subject = profile(largestUnit: pair.largest, smallestUnit: pair.smallest)
            XCTAssertNoThrow(try subject.validatedForPersistence(calendar: DateFixture.taipei),
                             "\(pair.largest) / \(pair.smallest) should be legal")
        }
    }

    func testUnitPairsOffTheTrackAreRejected() {
        let illegal: [(DisplayUnit, DisplayUnit)] = [
            (.year, .week), (.month, .year), (.month, .week),
            (.week, .year), (.week, .month), (.day, .year), (.day, .month), (.day, .week)
        ]
        for (largest, smallest) in illegal {
            expectValidationFailure(profile(largestUnit: largest, smallestUnit: smallest),
                                    .unitPairNotOnSameTrack(largest: largest, smallest: smallest))
        }
    }

    // MARK: - Invariant 5: age wording

    func testAgeWordingRequiresTheYearUnit() {
        expectValidationFailure(profile(largestUnit: .day, smallestUnit: .day, useAgeWording: true),
                                .ageWordingRequiresYearUnit)
        expectValidationFailure(profile(largestUnit: .month, smallestUnit: .day, useAgeWording: true),
                                .ageWordingRequiresYearUnit)
        XCTAssertNoThrow(try profile(largestUnit: .year, smallestUnit: .month, useAgeWording: true)
            .validatedForPersistence(calendar: DateFixture.taipei))
    }
}
