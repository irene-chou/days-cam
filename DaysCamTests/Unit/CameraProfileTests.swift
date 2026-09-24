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
        XCTAssertEqual(subject.position, .anchor(.bottomTrailing))
        XCTAssertEqual(subject.style, OverlayStyle(legacyTheme: .classicWhite))
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
        subject.position = .anchor(.topLeading)
        subject.style = OverlayStyle(legacyTheme: .filmStrip)
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

// MARK: - 0.2 style and position (TASK-17)

/// Covers TASK-17 17.3 ... 17.8: reading 0.1 files, the unknown-font
/// fallback and the style and position invariants of PRD 0.2 §4.1.
final class CameraProfileStyleMigrationTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CameraProfileStyleMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CameraProfileStyleMigrationTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private var fileURL: URL {
        directory.appendingPathComponent(ProfileStore.fileName)
    }

    private func makeStore() throws -> ProfileStore {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        return ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant }, defaults: defaults)
    }

    /// One record exactly as 0.1's synthesized `Codable` wrote it: a
    /// `themeID` key, and `position` as a bare string.
    private func legacyRecord(id: String, name: String, themeID: String, position: String) -> String {
        """
        {"id":"\(id)","name":"\(name)","startDate":{"year":2026,"month":1,"day":1},\
        "countingRule":"dayOne","showDayCount":true,"showDate":false,"showName":false,\
        "largestUnit":"day","smallestUnit":"day","useAgeWording":false,\
        "position":"\(position)","themeID":"\(themeID)",\
        "createdAt":789000000,"updatedAt":789000000}
        """
    }

    /// The five 0.1 themes, each paired with a distinct 0.1 position string.
    private let legacyFixture: [(id: String, themeID: String, position: OverlayPosition)] = [
        ("00000000-0000-0000-0000-000000000001", "classicWhite", .topLeading),
        ("00000000-0000-0000-0000-000000000002", "retroOrange", .topCenter),
        ("00000000-0000-0000-0000-000000000003", "filmStrip", .middleCenter),
        ("00000000-0000-0000-0000-000000000004", "minimalDark", .bottomLeading),
        ("00000000-0000-0000-0000-000000000005", "softPink", .bottomTrailing)
    ]

    private func writeLegacyFixture() throws {
        let records = legacyFixture.enumerated().map { index, row in
            legacyRecord(id: row.id, name: "舊檔\(index + 1)", themeID: row.themeID, position: row.position.rawValue)
        }
        try Data("[\(records.joined(separator: ","))]".utf8).write(to: fileURL, options: [.atomic])
    }

    /// PRD 0.2 §4.3 style table, written out independently of
    /// `OverlayStyle(legacyTheme:)` so that a wrong mapping cannot pass itself.
    private let expectedStyles: [String: OverlayStyle] = [
        "classicWhite": OverlayStyle(fontID: .sfRounded, textColor: .white,
                                     outline: .none, outlineColor: nil, shadow: .soft, sizeScale: 100),
        "retroOrange": OverlayStyle(fontID: .sfMono, textColor: OverlayColor(red8: 0xFF, green8: 0x95, blue8: 0x00),
                                    outline: .none, outlineColor: nil, shadow: .soft, sizeScale: 100),
        "filmStrip": OverlayStyle(fontID: .sfMono, textColor: .white,
                                  outline: .translucentBox, outlineColor: nil, shadow: .none, sizeScale: 100),
        "minimalDark": OverlayStyle(fontID: .sfPro, textColor: OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E),
                                    outline: .translucentBox, outlineColor: nil, shadow: .none, sizeScale: 100),
        "softPink": OverlayStyle(fontID: .sfRounded, textColor: OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D),
                                 outline: .thinStroke, outlineColor: nil, shadow: .soft, sizeScale: 100)
    ]

    /// 17.3: every 0.1 record is kept and converted.
    func testLegacyFileLoadsEveryRecordWithConvertedStyleAndPosition() throws {
        try writeLegacyFixture()
        let loaded = try makeStore().load()

        XCTAssertEqual(loaded.count, 5, "17.3: no record dropped")
        for row in legacyFixture {
            let profile = try XCTUnwrap(loaded.first { $0.id.uuidString == row.id }, "17.3 \(row.themeID)")
            XCTAssertEqual(profile.style, expectedStyles[row.themeID], "17.3 style of \(row.themeID)")
            XCTAssertEqual(profile.position, .anchor(row.position), "17.3 position of \(row.themeID)")
        }
    }

    /// 17.4: once written back, the file is in the new format.
    ///
    /// `ProfileStore.persist` is private, so the write goes through `update`,
    /// which persists the whole list.
    func testPersistingConvertedRecordsDropsThemeIDAndWritesStyle() throws {
        try writeLegacyFixture()
        let store = try makeStore()
        let loaded = store.load()
        let first = try XCTUnwrap(loaded.first)
        try store.update(first)

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("themeID"), "17.4")
        XCTAssertTrue(text.contains("\"style\""), "17.4")

        // And the new format reads back to the same styles and positions.
        let reloaded = try makeStore().load()
        XCTAssertEqual(reloaded.map(\.id), loaded.map(\.id))
        XCTAssertEqual(reloaded.map(\.style), loaded.map(\.style))
        XCTAssertEqual(reloaded.map(\.position), loaded.map(\.position))
    }

    /// 17.5: an unknown font falls back to SF Rounded instead of dropping the record.
    func testUnknownFontIDFallsBackToSFRounded() throws {
        var profile = CameraProfile(name: "字型", startDate: DateFixture.components(2026, 1, 1))
        profile.style = OverlayStyle(fontID: .futura)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode([profile]), encoding: .utf8))
        XCTAssertTrue(encoded.contains("\"futura\""), "fixture sanity")
        try Data(encoded.replacingOccurrences(of: "\"futura\"", with: "\"comicSans\"").utf8)
            .write(to: fileURL, options: [.atomic])

        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 1, "17.5: record kept")
        XCTAssertEqual(loaded.first?.id, profile.id, "17.5")
        XCTAssertEqual(loaded.first?.style.fontID, .sfRounded, "17.5")
    }

    func testUnknownLegacyThemeFallsBackToDefaultStyle() throws {
        let record = legacyRecord(id: "00000000-0000-0000-0000-000000000009", name: "未知",
                                  themeID: "neonGreen", position: "topTrailing")
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: Data(record.utf8))
        XCTAssertEqual(decoded.style, OverlayStyle())
        XCTAssertEqual(decoded.position, .anchor(.topTrailing))
    }

    func testNewFormatRoundTripsCustomPlacementAndFullStyle() throws {
        var profile = CameraProfile(name: "新格式", startDate: DateFixture.components(2026, 1, 1))
        profile.position = .custom(x: 0.25, y: 0.75)
        profile.style = OverlayStyle(fontID: .didot,
                                     textColor: OverlayColor(red8: 0x12, green8: 0x34, blue8: 0x56),
                                     outline: .solidBox,
                                     outlineColor: OverlayColor(red8: 0x0A, green8: 0x84, blue8: 0xFF),
                                     shadow: .glow,
                                     sizeScale: 135)
        let data = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(CameraProfile.self, from: data), profile)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("themeID"))
    }

    // MARK: - 17.6 ... 17.8 invariants

    private func profile(sizeScale: Int = 100,
                         position: OverlayPlacement = .default) -> CameraProfile {
        CameraProfile(name: "小寶",
                      startDate: DateFixture.components(2026, 1, 1),
                      position: position,
                      style: OverlayStyle(sizeScale: sizeScale))
    }

    func testSizeScaleOutsideRangeOrOffStepIsRejected() {
        for scale in [65, 165, 72] {
            XCTAssertThrowsError(try profile(sizeScale: scale).validate(calendar: DateFixture.taipei), "17.6 \(scale)") {
                XCTAssertEqual($0 as? CameraProfileValidationError, .sizeScaleOutOfRange(scale), "17.6 \(scale)")
            }
        }
    }

    func testSizeScaleInsideRangeOnStepIsAccepted() {
        for scale in [70, 100, 160] {
            XCTAssertNoThrow(try profile(sizeScale: scale).validate(calendar: DateFixture.taipei), "17.7 \(scale)")
        }
    }

    func testCustomPositionOutsideUnitSquareIsRejected() {
        XCTAssertThrowsError(try profile(position: .custom(x: 1.2, y: 0.5)).validate(calendar: DateFixture.taipei), "17.8") {
            XCTAssertEqual($0 as? CameraProfileValidationError, .customPositionOutOfRange(x: 1.2, y: 0.5), "17.8")
        }
        XCTAssertNoThrow(try profile(position: .custom(x: 0, y: 1)).validate(calendar: DateFixture.taipei), "17.8")
        XCTAssertThrowsError(try profile(position: .custom(x: 0.5, y: -0.01)).validate(calendar: DateFixture.taipei))
        XCTAssertThrowsError(try profile(position: .custom(x: .nan, y: 0.5)).validate(calendar: DateFixture.taipei))
    }

    func testNonStorableColorsAreRejected() {
        var outOfRange = profile()
        outOfRange.style.textColor = OverlayColor(red: 1.2, green: 0, blue: 0)
        XCTAssertThrowsError(try outOfRange.validate(calendar: DateFixture.taipei)) {
            XCTAssertEqual($0 as? CameraProfileValidationError, .colorNotStorable)
        }

        var translucentOutline = profile()
        translucentOutline.style.outlineColor = OverlayColor(red: 0, green: 0, blue: 0, opacity: 0.5)
        XCTAssertThrowsError(try translucentOutline.validate(calendar: DateFixture.taipei)) {
            XCTAssertEqual($0 as? CameraProfileValidationError, .colorNotStorable)
        }
    }
}
