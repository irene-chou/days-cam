import XCTest
@testable import DaysCam

/// Covers the invariants of PRD §4.1 (as amended by 0.2 §4.1) at the model level.
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
                         displayUnits: Set<DisplayUnit> = [.day],
                         useAgeWording: Bool = false) -> CameraProfile {
        CameraProfile(name: name,
                      startDate: startDate,
                      showDayCount: showDayCount,
                      showDate: showDate,
                      displayUnits: displayUnits,
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
    func testWeightMigrationThroughStoreKeepsAllProfilesAndSurvivesRestart() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Task89-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "Task89-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var profiles: [CameraProfile] = []
        var records: [[String: Any]] = []
        for (index, value) in (["unknown", 42, ["weight": "black"], NSNull(), ["bold"], false] as [Any]).enumerated() {
            var subject = profile(name: "字重\(index)")
            subject.style = OverlayStyle(fontID: .notoSerifTC)
            profiles.append(subject)
            var record = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(subject)) as? [String: Any])
            var style = try XCTUnwrap(record["style"] as? [String: Any])
            style["fontWeight"] = value
            record["style"] = style
            records.append(record)
        }
        let data = try JSONSerialization.data(withJSONObject: records)
        let url = folder.appendingPathComponent(ProfileStore.fileName)
        try data.write(to: url)
        let store = ProfileStore(directory: folder, calendar: DateFixture.taipei, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        XCTAssertEqual(store.load(), profiles)
        XCTAssertEqual(try Data(contentsOf: url), data, "loading does not rewrite old data")
        var selected = profiles[0]
        selected.style.fontWeight = "black"
        try store.update(selected)
        let reopened = ProfileStore(directory: folder, calendar: DateFixture.taipei, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        let loaded = reopened.load()
        XCTAssertEqual(loaded.count, 6)
        XCTAssertEqual(loaded.first?.style.fontWeight, "black")
        XCTAssertEqual(loaded.dropFirst().map(\.id), profiles.dropFirst().map(\.id))
        XCTAssertTrue(loaded.dropFirst().allSatisfy { $0.style.fontWeight == "bold" })
    }

    func testMalformedWeightDoesNotDropOrAlterProfileData() throws {
        var original = profile()
        original.style = OverlayStyle(fontID: .notoSerifTC)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var style = try XCTUnwrap(json["style"] as? [String: Any])
        for value in ["unknown", 42, ["weight": "black"], NSNull()] as [Any] {
            style["fontWeight"] = value
            json["style"] = style
            let decoded = try JSONDecoder().decode(CameraProfile.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(decoded, original)
            XCTAssertNoThrow(try decoded.validate(calendar: DateFixture.taipei))
            XCTAssertEqual(decoded.style.resolvedFontWeight.postScriptName, "NotoSerifTC-Bold")
        }
    }

    func testDefaultsMatchTheSpecifiedNewProfileValues() {
        let subject = CameraProfile(name: "預設", startDate: DateFixture.components(2026, 1, 10))
        XCTAssertEqual(subject.countingRule, .dayOne)
        XCTAssertTrue(subject.showDayCount)
        XCTAssertFalse(subject.showDate)
        XCTAssertFalse(subject.showName)
        XCTAssertEqual(subject.displayUnits, [.day])
        XCTAssertFalse(subject.useAgeWording)
        XCTAssertEqual(subject.position, .anchor(.bottomTrailing))
        XCTAssertEqual(subject.style, OverlayStyle(legacyTheme: .classicWhite))
    }

    /// The initializer must accept invalid states so that an editing screen can
    /// hold a half-typed profile and so that tests can build one to reject.
    func testMemberwiseInitializerDoesNotValidate() {
        let invalid = profile(name: "", showDayCount: false, showDate: false, displayUnits: [])
        XCTAssertEqual(invalid.name, "")
        XCTAssertThrowsError(try invalid.validate(calendar: DateFixture.taipei))
    }

    func testCodableRoundTripPreservesEveryField() throws {
        var subject = profile(showDate: true, displayUnits: [.year, .month, .week], useAgeWording: true)
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

    // MARK: - Invariant 3: display switches (TASK-107 brings the day-count switch back)

    /// 107.7: both off should not exist; persistence turns the day count on
    /// instead of dropping the profile.
    func testBothSwitchesOffIsRepairedByTurningTheDayCountOn() throws {
        let stored = try profile(showDayCount: false, showDate: false)
            .validatedForPersistence(calendar: DateFixture.taipei)
        XCTAssertTrue(stored.showDayCount, "107.7")
        XCTAssertFalse(stored.showDate, "107.7: showDate untouched")
        XCTAssertThrowsError(try profile(showDayCount: false, showDate: false).validate(calendar: DateFixture.taipei)) {
            XCTAssertEqual($0 as? CameraProfileValidationError, .displaySwitchesAllOff, "invariant 3 itself still holds")
        }
    }

    /// 107.2: a date-only profile is stored as it is — TASK-107 (#426)
    /// reverses TASK-47's forcing of the day count on.
    func testDateOnlyProfileIsStoredWithTheDayCountOff() throws {
        let stored = try profile(showDayCount: false, showDate: true)
            .validatedForPersistence(calendar: DateFixture.taipei)
        XCTAssertFalse(stored.showDayCount, "107.2")
        XCTAssertTrue(stored.showDate, "107.2")
        XCTAssertNoThrow(try profile(showDayCount: true, showDate: false)
            .validatedForPersistence(calendar: DateFixture.taipei))
    }

    /// TASK-107: `normalized()` leaves a date-only profile's switches alone.
    func testNormalizingKeepsADateOnlyProfile() {
        var original = profile(showDayCount: false, showDate: true,
                               displayUnits: [.year, .week], useAgeWording: true)
        original.showName = true
        original.countingRule = .dayZero
        original.position = .custom(x: 0.25, y: 0.75)
        original.style = OverlayStyle(legacyTheme: .softPink)
        XCTAssertEqual(original.normalized(), original, "107.2 nothing changes")
    }

    // MARK: - Units (PRD 0.2 §4.1, replacing 0.1 invariants 4 and 5)

    /// Every non-empty subset is legal now, including the 0.1-illegal mixes.
    func testEveryNonEmptyUnitSetValidates() {
        for mask in 1..<16 {
            let units = Set(DisplayUnit.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            XCTAssertNoThrow(try profile(displayUnits: units).validatedForPersistence(calendar: DateFixture.taipei),
                             "\(units)")
        }
    }

    func testEmptyUnitSetIsRejected() {
        expectValidationFailure(profile(displayUnits: []), .displayUnitsEmpty)
    }

    /// TASK-139 (#486): age wording no longer needs the year unit; every
    /// unit set is valid with it on or off (139.7, was invariant 5).
    func testAgeWordingIsValidWithAnyUnitSet() {
        for mask in 1..<16 {
            let units = Set(DisplayUnit.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            XCTAssertNoThrow(try profile(displayUnits: units, useAgeWording: true)
                .validatedForPersistence(calendar: DateFixture.taipei), "139.7 \(units)")
        }
    }

    /// The file lists units in year → day order, not `Set` order.
    func testDisplayUnitsAreEncodedInDisplayOrder() throws {
        let data = try JSONEncoder().encode(profile(displayUnits: [.day, .week, .year]))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains(#""displayUnits":["year","week","day"]"#), text)
        XCTAssertFalse(text.contains("largestUnit"))
        XCTAssertFalse(text.contains("smallestUnit"))
    }

    // MARK: - #582 dayCountFormat

    private func formatSample(_ format: DayCountFormat = .dDay) -> CameraProfile {
        CameraProfile(name: "小寶",
                      startDate: DateFixture.components(2025, 1, 15),
                      countingRule: .dayZero,
                      showDate: true,
                      showName: true,
                      displayUnits: [.day],
                      useAgeWording: true,
                      dayCountFormat: format,
                      position: .custom(x: 0.3, y: 0.7),
                      style: OverlayStyle(legacyTheme: .softPink),
                      showFilmDate: true,
                      filmDateCorner: .topTrailing,
                      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                      updatedAt: Date(timeIntervalSince1970: 1_700_000_500))
    }

    private func jsonObject(_ profile: CameraProfile) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> CameraProfile {
        try JSONDecoder().decode(CameraProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func test_582_3_newProfileDefaultsToOrdinal() {
        XCTAssertEqual(profile().dayCountFormat, .ordinal)
    }

    func test_582_3_fileWithoutTheFieldDecodesAsOrdinalAndKeepsEverythingElse() throws {
        let original = formatSample(.ordinal)
        var json = try jsonObject(original)
        XCTAssertEqual(json.removeValue(forKey: "dayCountFormat") as? String, "ordinal")

        let decoded = try decode(json)

        XCTAssertEqual(decoded.dayCountFormat, .ordinal)
        XCTAssertEqual(decoded, original)
        XCTAssertNoThrow(try decoded.validatedForPersistence(calendar: DateFixture.taipei))
    }

    func test_582_3_everyFormatSurvivesARoundTrip() throws {
        for format in DayCountFormat.allCases {
            let original = formatSample(format)
            let decoded = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(original))
            XCTAssertEqual(decoded, original, "\(format)")
            XCTAssertNoThrow(try decoded.validatedForPersistence(calendar: DateFixture.taipei))
        }
    }

    func test_582_3_badValueFallsBackWithoutLosingTheProfile() throws {
        let original = formatSample(.dDay)
        for bad in ["banana", "", 3, NSNull()] as [Any] {
            var json = try jsonObject(original)
            json["dayCountFormat"] = bad
            let decoded = try decode(json)
            XCTAssertEqual(decoded.dayCountFormat, .ordinal, "\(bad)")
            var expected = original
            expected.dayCountFormat = .ordinal
            XCTAssertEqual(decoded, expected, "\(bad)")
        }
    }

    func test_582_4_duplicatingAProfileKeepsTheFormat() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "CameraProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let instant = Date(timeIntervalSince1970: 1_760_000_000)
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        let added = try store.add(formatSample(.dayN))

        let copy = try store.duplicate(id: added.id)

        XCTAssertEqual(copy.dayCountFormat, .dayN)
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
        return ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
    }

    /// One record exactly as 0.1's synthesized `Codable` wrote it: a
    /// `themeID` key, and `position` as a bare string.
    private func legacyRecord(id: String, name: String, themeID: String, position: String,
                              largestUnit: String = "day", smallestUnit: String = "day") -> String {
        """
        {"id":"\(id)","name":"\(name)","startDate":{"year":2026,"month":1,"day":1},\
        "countingRule":"dayOne","showDayCount":true,"showDate":false,"showName":false,\
        "largestUnit":"\(largestUnit)","smallestUnit":"\(smallestUnit)","useAgeWording":false,\
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
    /// TASK-70 states its translucent box as a box at outline alpha 50%,
    /// stored as 128/255.
    /// The font column is PingFang throughout: 0.3 §4.3 replaces the 0.2 fonts
    /// the table named.
    private let expectedStyles: [String: OverlayStyle] = [
        "classicWhite": OverlayStyle(fontID: .pingFang, textColor: .white,
                                     outline: .none, outlineColor: nil, shadow: .soft, sizeScale: 100),
        "retroOrange": OverlayStyle(fontID: .pingFang, textColor: OverlayColor(red8: 0xFF, green8: 0x95, blue8: 0x00),
                                    outline: .none, outlineColor: nil, shadow: .soft, sizeScale: 100),
        "filmStrip": OverlayStyle(fontID: .pingFang, textColor: .white,
                                  outline: .box, outlineColor: nil,
                                  autoOutlineOpacity: 128.0 / 255, shadow: .none, sizeScale: 100),
        "minimalDark": OverlayStyle(fontID: .pingFang, textColor: OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E),
                                    outline: .box, outlineColor: nil,
                                  autoOutlineOpacity: 128.0 / 255, shadow: .none, sizeScale: 100),
        "softPink": OverlayStyle(fontID: .pingFang, textColor: OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D),
                                 outline: .stroke, outlineColor: nil, strokeWidth: 2, shadow: .soft, sizeScale: 100)
    ]

    /// 17.3 / 32.4: every 0.1 record is kept and converted, in PingFang.
    func testLegacyFileLoadsEveryRecordWithConvertedStyleAndPosition() throws {
        try writeLegacyFixture()
        let loaded = try makeStore().load()

        XCTAssertEqual(loaded.count, 5, "17.3: no record dropped")
        for row in legacyFixture {
            let profile = try XCTUnwrap(loaded.first { $0.id.uuidString == row.id }, "17.3 \(row.themeID)")
            XCTAssertEqual(profile.style, expectedStyles[row.themeID], "17.3 style of \(row.themeID)")
            XCTAssertEqual(profile.style.fontID, .pingFang, "32.4 font of \(row.themeID)")
            XCTAssertEqual(profile.position, .anchor(row.position), "17.3 position of \(row.themeID)")
        }
    }

    // MARK: - 0.2 files (TASK-32 32.2, 32.3)

    /// The ten 0.2 font IDs, removed in 0.3.
    private static let removedFontIDs = ["sfRounded", "sfPro", "sfMono", "newYork", "avenirNext",
                                         "futura", "georgia", "americanTypewriter", "didot", "snellRoundhand"]

    /// One record exactly as 0.2 wrote it, with a distinct non-default value
    /// in every other style field so a field lost in conversion shows up.
    private func record02(index: Int, fontID: String) -> String {
        let id = String(format: "00000000-0000-0000-0000-%012d", index + 200)
        let x = Double(index + 1) / 20
        return """
        {"id":"\(id)","name":"0.2-\(index)","startDate":{"year":2026,"month":1,"day":1},\
        "countingRule":"dayOne","showDayCount":true,"showDate":false,"showName":false,\
        "displayUnits":["day"],"useAgeWording":false,\
        "position":{"x":\(x),"y":0.5},\
        "style":{"fontID":"\(fontID)","textColor":"#12345\(index % 10)","outline":"thickStroke",\
        "outlineColor":"#0A84FF","shadow":"glow","sizeScale":\(70 + index * 5)},\
        "createdAt":789000000,"updatedAt":789000000}
        """
    }

    /// The style `record02(index:fontID:)` should read back as, in PingFang.
    private func expectedStyle02(index: Int) throws -> OverlayStyle {
        var style = OverlayStyle(fontID: .pingFang,
                     textColor: try XCTUnwrap(OverlayColor(hex: "#12345\(index % 10)")),
                     outline: .stroke,
                     outlineColor: try XCTUnwrap(OverlayColor(hex: "#0A84FF")),
                     strokeWidth: 4,
                     shadow: .glow,
                     sizeScale: 70 + index * 5)
        // Legacy glow preserves its text color and alpha; current presets only change geometry.
        style.shadowColorSource = .textColor
        style.shadowOpacity = 230.0 / 255
        return style
    }

    /// 32.3: a 0.2 `profiles.json` with one record per removed font loads with
    /// every record kept, all in PingFang, and every other style field intact;
    /// written back, it reads the same and no longer names a 0.2 font.
    func test02FileWithEveryRemovedFontKeepsRecordsAndOtherFields() throws {
        let records = Self.removedFontIDs.enumerated().map { record02(index: $0.offset, fontID: $0.element) }
        try Data("[\(records.joined(separator: ","))]".utf8).write(to: fileURL, options: [.atomic])

        let store = try makeStore()
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 10, "32.3: no record dropped")
        for index in Self.removedFontIDs.indices {
            let profile = try XCTUnwrap(loaded.first { $0.name == "0.2-\(index)" }, "32.3 \(index)")
            XCTAssertEqual(profile.style, try expectedStyle02(index: index), "32.3 \(Self.removedFontIDs[index])")
            XCTAssertEqual(profile.position, .custom(x: Double(index + 1) / 20, y: 0.5), "32.3 position")
        }

        // `ProfileStore.persist` is private; `update` writes the whole list.
        try store.update(try XCTUnwrap(loaded.first))
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        for removed in Self.removedFontIDs {
            XCTAssertFalse(text.contains("\"\(removed)\""), "32.3: \(removed) written back")
        }
        let reloaded = try makeStore().load()
        XCTAssertEqual(reloaded.map(\.id), loaded.map(\.id), "32.3 after saving")
        XCTAssertEqual(reloaded.map(\.style), loaded.map(\.style), "32.3 after saving")
    }

    /// 139.5: a file with age wording on and no year checked — invalid
    /// before TASK-139 (#486) — loads with the record kept and unchanged,
    /// survives a write-back, and still renders the ordinal day count.
    func testAgeWordingWithoutYearInAFileLoadsUnchanged() throws {
        let record = """
        {"id":"00000000-0000-0000-0000-000000000139","name":"奶茶","startDate":{"year":2023,"month":8,"day":5},\
        "countingRule":"dayOne","showDayCount":true,"showDate":false,"showName":false,\
        "displayUnits":["day"],"useAgeWording":true,"position":{"x":0.5,"y":0.5},\
        "style":{"fontID":"pingFang","textColor":"#FFFFFF","outline":"thickStroke","outlineColor":"#0A84FF","shadow":"glow","sizeScale":100},\
        "createdAt":789000000,"updatedAt":789000000}
        """
        try Data("[\(record)]".utf8).write(to: fileURL, options: [.atomic])

        let store = try makeStore()
        let loaded = store.load()
        XCTAssertFalse(store.didRecoverFromCorruption, "139.5 not treated as corrupt")
        let kept = try XCTUnwrap(loaded.first { $0.name == "奶茶" }, "139.5 record kept")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(kept.useAgeWording, "139.5")
        XCTAssertEqual(kept.displayUnits, [.day], "139.5")

        let capturedAt = try XCTUnwrap(DateFixture.date(2026, 10, 12, hour: 10))
        XCTAssertEqual(TemplateRenderer().render(profile: kept, capturedAt: capturedAt, calendar: DateFixture.taipei),
                       "第 1165 天", "139.5")

        try store.update(kept)
        let reloaded = try makeStore().load()
        XCTAssertEqual(reloaded.map(\.useAgeWording), [true], "139.5 after saving")
        XCTAssertEqual(reloaded.map(\.displayUnits), [[.day]], "139.5 after saving")
    }

    /// 32.2: removed and unknown IDs in a file decode as PingFang without
    /// losing the record.
    func testRemovedAndUnknownFontIDsInAFileKeepTheRecord() throws {
        let values = ["futura", "sfRounded", "不存在"]
        let records = values.enumerated().map { record02(index: $0.offset, fontID: $0.element) }
        try Data("[\(records.joined(separator: ","))]".utf8).write(to: fileURL, options: [.atomic])

        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 3, "32.2: no record dropped")
        XCTAssertEqual(loaded.map(\.style.fontID), [.pingFang, .pingFang, .pingFang], "32.2")
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

    /// 17.5, with 0.3's fallback: an unknown font falls back to PingFang
    /// instead of dropping the record (PRD 0.3 §4.1).
    func testUnknownFontIDFallsBackToPingFang() throws {
        var profile = CameraProfile(name: "字型", startDate: DateFixture.components(2026, 1, 1))
        profile.style = OverlayStyle(fontID: .songti)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode([profile]), encoding: .utf8))
        XCTAssertTrue(encoded.contains("\"songti\""), "fixture sanity")
        try Data(encoded.replacingOccurrences(of: "\"songti\"", with: "\"comicSans\"").utf8)
            .write(to: fileURL, options: [.atomic])

        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 1, "17.5: record kept")
        XCTAssertEqual(loaded.first?.id, profile.id, "17.5")
        XCTAssertEqual(loaded.first?.style.fontID, .pingFang, "17.5 / 32.2")
    }

    /// 27.11: each 0.1 unit pair becomes the PRD 0.2 §4.3 set, in a real
    /// 0.1-format file read through `ProfileStore`.
    func testLegacyUnitPairsConvertToUnitSets() throws {
        let records = TemplateRendererTests.legacyPairs.enumerated().map { index, pair in
            legacyRecord(id: String(format: "00000000-0000-0000-0000-%012d", index + 100),
                         name: "單位\(index)", themeID: "classicWhite", position: "bottomTrailing",
                         largestUnit: pair.largest.rawValue, smallestUnit: pair.smallest.rawValue)
        }
        try Data("[\(records.joined(separator: ","))]".utf8).write(to: fileURL, options: [.atomic])

        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 8, "27.11: no record dropped")
        for (index, pair) in TemplateRendererTests.legacyPairs.enumerated() {
            XCTAssertEqual(loaded.first { $0.name == "單位\(index)" }?.displayUnits,
                           TemplateRendererTests.legacyUnits(largest: pair.largest, smallest: pair.smallest),
                           "27.11 \(pair.largest)/\(pair.smallest)")
        }
    }

    /// A pair 0.1 itself would have rejected is kept, with its largest unit.
    func testIllegalLegacyUnitPairKeepsTheLargestUnit() throws {
        let record = legacyRecord(id: "00000000-0000-0000-0000-000000000099", name: "壞",
                                  themeID: "classicWhite", position: "bottomTrailing",
                                  largestUnit: "week", smallestUnit: "month")
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: Data(record.utf8))
        XCTAssertEqual(decoded.displayUnits, [.week])
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
        profile.style = OverlayStyle(fontID: .songti,
                                     textColor: OverlayColor(red8: 0x12, green8: 0x34, blue8: 0x56),
                                     outline: .box,
                                     outlineColor: OverlayColor(red8: 0x0A, green8: 0x84, blue8: 0xFF),
                                     autoOutlineOpacity: 0.4,
                                     strokeWidth: 5,
                                     boxPadding: 18,
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

        // TASK-69 69.4: opacity outside 0.05...1 is rejected, for both colors.
        for opacity in [0.04, 0, -0.5, 1.01, .nan] {
            var faintText = profile()
            faintText.style.textColor = OverlayColor.white.withOpacity(opacity)
            XCTAssertThrowsError(try faintText.validatedForPersistence(calendar: DateFixture.taipei), "69.4 \(opacity)") {
                XCTAssertEqual($0 as? CameraProfileValidationError, .colorNotStorable, "69.4 \(opacity)")
            }
            var faintOutline = profile()
            faintOutline.style.outlineColor = OverlayColor.black.withOpacity(opacity)
            XCTAssertThrowsError(try faintOutline.validatedForPersistence(calendar: DateFixture.taipei), "69.4 \(opacity)") {
                XCTAssertEqual($0 as? CameraProfileValidationError, .colorNotStorable, "69.4 \(opacity)")
            }
        }
    }

    /// TASK-69 69.4 / 69.5: translucent text and outline colors inside
    /// 0.05...1 are storable (PRD 0.2 §4.1 as amended).
    func testTranslucentColorsInsideTheRangeAreAccepted() {
        for opacity in [OverlayColor.minimumStorableOpacity, 0.5, 1] {
            var subject = profile()
            subject.style.textColor = OverlayColor.white.withOpacity(opacity)
            subject.style.outlineColor = OverlayColor.black.withOpacity(opacity)
            XCTAssertNoThrow(try subject.validatedForPersistence(calendar: DateFixture.taipei), "69.4 \(opacity)")
        }
    }

    /// TASK-69: what is validated is what is written — colors come out of
    /// `normalized()` on the 8-bit grid, alpha included.
    func testNormalizedQuantizesStyleColorsToEightBits() throws {
        var subject = profile()
        subject.style.textColor = OverlayColor(red: 0.1234, green: 0.5, blue: 1, opacity: 0.5)
        subject.style.outlineColor = OverlayColor(red: 0, green: 0, blue: 0, opacity: 0.3)
        let normalized = try subject.validatedForPersistence(calendar: DateFixture.taipei)
        XCTAssertEqual(normalized.style.textColor, OverlayColor(red8: 31, green8: 128, blue8: 255, opacity: 128.0 / 255))
        XCTAssertEqual(normalized.style.outlineColor, OverlayColor(red8: 0, green8: 0, blue8: 0, opacity: 77.0 / 255))
        let data = try JSONEncoder().encode(normalized)
        XCTAssertEqual(try JSONDecoder().decode(CameraProfile.self, from: data), normalized, "exact round trip")
    }
}

/// Covers TASK-69 69.1, 69.3 and 69.4 through `ProfileStore`: colors with
/// an alpha channel (`#RRGGBBAA`) next to pre-TASK-69 files (`#RRGGBB`).
final class CameraProfileColorOpacityTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CameraProfileColorOpacityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CameraProfileColorOpacityTests-\(UUID().uuidString)"
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
        let instant = try XCTUnwrap(DateFixture.date(2026, 3, 20, hour: 10))
        return ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
    }

    /// One 0.5 record with a non-default value in every field.
    private func record(id: String, textColor: String, outlineColor: String) -> String {
        """
        {"id":"\(id)","name":"小寶","startDate":{"year":2025,"month":1,"day":15},\
        "countingRule":"dayZero","showDayCount":true,"showDate":true,"showName":true,\
        "displayUnits":["month","day"],"useAgeWording":false,\
        "position":{"x":0.25,"y":0.75},\
        "style":{"fontID":"songti","textColor":"\(textColor)","outline":"thickStroke",\
        "outlineColor":"\(outlineColor)","shadow":"glow","sizeScale":120},\
        "createdAt":789000000,"updatedAt":789000000}
        """
    }

    private static let firstID = "00000000-0000-0000-0000-000000000691"
    private static let secondID = "00000000-0000-0000-0000-000000000692"

    /// 69.1: a pre-TASK-69 file loads with every field intact, both colors
    /// at alpha 100%, and is not rewritten; saving again still writes
    /// `#RRGGBB`, so the stored text is unchanged.
    func testOpaqueHexFileLoadsUnchangedWithFullAlpha() throws {
        let fixture = "[\(record(id: Self.firstID, textColor: "#123456", outlineColor: "#0A84FF"))]"
        try Data(fixture.utf8).write(to: fileURL, options: [.atomic])
        let bytesBefore = try Data(contentsOf: fileURL)

        let loaded = try makeStore().load()

        let profile = try XCTUnwrap(loaded.first, "69.1: profile kept")
        XCTAssertEqual(loaded.count, 1, "69.1")
        XCTAssertEqual(profile.name, "小寶")
        XCTAssertEqual(profile.startDate, DateFixture.components(2025, 1, 15))
        XCTAssertEqual(profile.countingRule, .dayZero)
        XCTAssertTrue(profile.showDate && profile.showName && profile.showDayCount)
        XCTAssertEqual(profile.displayUnits, [.month, .day])
        XCTAssertEqual(profile.position, .custom(x: 0.25, y: 0.75))
        // A pre-0.5 "glow" keeps its own colour (text colour at 230/255, the
        // TASK-86 migration table); presets applied to a new style no longer
        // carry a colour, so the expectation sets it explicitly.
        var expected = OverlayStyle(fontID: .songti,
                                    textColor: OverlayColor(red8: 0x12, green8: 0x34, blue8: 0x56),
                                    outline: .stroke,
                                    outlineColor: OverlayColor(red8: 0x0A, green8: 0x84, blue8: 0xFF),
                                    strokeWidth: 4,
                                    shadow: .glow,
                                    sizeScale: 120)
        expected.shadowColorSource = .textColor
        expected.shadowOpacity = 230.0 / 255
        XCTAssertEqual(profile.style, expected, "69.1")
        XCTAssertEqual(profile.style.textColor.opacity, 1, "69.1: alpha 100%")
        XCTAssertEqual(profile.style.outlineColor?.opacity, 1, "69.1: alpha 100%")
        XCTAssertEqual(try Data(contentsOf: fileURL), bytesBefore, "69.1: no write-back")

        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(loaded), encoding: .utf8))
        XCTAssertTrue(encoded.contains(##""textColor":"#123456""##), "69.1: still #RRGGBB")
        XCTAssertTrue(encoded.contains(##""outlineColor":"#0A84FF""##), "69.1: still #RRGGBB")
    }

    /// 69.3: translucent colors saved through the store come back from a
    /// fresh store (an app restart) as the same 8-bit values.
    func testTranslucentColorsSurviveARestart() throws {
        let store = try makeStore()
        store.load()
        var style = OverlayStyle(textColor: OverlayColor.white.withOpacity(0.5),
                                 outline: .stroke,
                                 outlineColor: OverlayColor(red8: 0x0A, green8: 0x84, blue8: 0xFF).withOpacity(0.3))
        style.sizeScale = 120
        let added = try store.add(CameraProfile(name: "半透明", startDate: DateFixture.components(2025, 1, 15),
                                                style: style))

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains(##""#FFFFFF80""##), "69.3: stored as #RRGGBBAA, got \(text)")
        XCTAssertTrue(text.contains(##""#0A84FF4D""##), "69.3: stored as #RRGGBBAA, got \(text)")

        let reloaded = try XCTUnwrap(try makeStore().load().first { $0.id == added.id }, "69.3: profile kept")
        XCTAssertEqual(reloaded.style, added.style, "69.3")
        XCTAssertEqual(reloaded.style.textColor.opacity, 0.5, accuracy: 0.5 / 255, "69.3")
        XCTAssertEqual(reloaded.style.outlineColor?.opacity ?? 0, 0.3, accuracy: 0.5 / 255, "69.3")
    }

    /// 69.4: the store refuses to write an opacity below the minimum.
    func testStoreRejectsAnOpacityBelowTheMinimum() throws {
        let store = try makeStore()
        store.load()
        let faint = CameraProfile(name: "太淡", startDate: DateFixture.components(2025, 1, 15),
                                  style: OverlayStyle(textColor: OverlayColor.white.withOpacity(0.01)))
        XCTAssertThrowsError(try store.add(faint), "69.4")
        XCTAssertFalse((try? String(contentsOf: fileURL, encoding: .utf8))?.contains("太淡") ?? false, "69.4: not written")
    }

    /// 69.4: a file holding an alpha below the minimum (only possible by
    /// hand-editing) keeps its profile, with the alpha raised into range.
    func testFileWithTooFaintAlphaKeepsTheProfileRaisedIntoRange() throws {
        let fixture = "[\(record(id: Self.firstID, textColor: "#FFFFFF00", outlineColor: "#00000005")),"
            + "\(record(id: Self.secondID, textColor: "#FFFFFF80", outlineColor: "#0A84FF"))]"
        try Data(fixture.utf8).write(to: fileURL, options: [.atomic])

        let loaded = try makeStore().load()

        XCTAssertEqual(loaded.map(\.id.uuidString), [Self.firstID, Self.secondID], "69.4: no profile lost")
        let minimum = 13.0 / 255
        XCTAssertEqual(loaded[0].style.textColor.opacity, minimum, "69.4")
        XCTAssertEqual(loaded[0].style.outlineColor?.opacity, minimum, "69.4")
        XCTAssertEqual(loaded[1].style.textColor.opacity, 128.0 / 255, "69.3")
    }
}

/// TASK-47's 47.1 ... 47.4 reversed by TASK-107 (#426, 107.6／107.7): a
/// date-only record is kept as it is; only a record with both switches off
/// is repaired, and no profile is ever dropped for either.
final class CameraProfileDayCountMigrationTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CameraProfileDayCountMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CameraProfileDayCountMigrationTests-\(UUID().uuidString)"
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

    private func referenceInstant() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 3, 20, hour: 10))
    }

    private func makeStore() throws -> ProfileStore {
        let instant = try referenceInstant()
        return ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
    }

    /// One 0.3 record with a non-default value in every field, so a field
    /// changed by the migration shows up.
    private func record(id: String, name: String, showDayCount: Bool, showDate: Bool = true) -> String {
        """
        {"id":"\(id)","name":"\(name)","startDate":{"year":2025,"month":1,"day":15},\
        "countingRule":"dayZero","showDayCount":\(showDayCount),"showDate":\(showDate),"showName":true,\
        "displayUnits":["month","day"],"useAgeWording":false,\
        "position":{"x":0.25,"y":0.75},\
        "style":{"fontID":"pingFang","textColor":"#123456","outline":"thickStroke",\
        "outlineColor":"#0A84FF","shadow":"glow","sizeScale":120},\
        "createdAt":789000000,"updatedAt":789000000}
        """
    }

    private static let dateOnlyID = "00000000-0000-0000-0000-000000000471"
    private static let countingID = "00000000-0000-0000-0000-000000000472"

    private func writeFixture(_ records: [String]) throws {
        try Data("[\(records.joined(separator: ","))]".utf8).write(to: fileURL, options: [.atomic])
    }

    private func rawProfiles() throws -> [CameraProfile] {
        try JSONDecoder().decode([CameraProfile].self, from: Data(contentsOf: fileURL))
    }

    /// 107.7: a `showDayCount: false` record (date only) is kept exactly as
    /// it is — the file is not rewritten and a fresh load reads it unchanged.
    func testDateOnlyRecordIsKeptAsItIs() throws {
        try writeFixture([record(id: Self.dateOnlyID, name: "只看日期", showDayCount: false),
                          record(id: Self.countingID, name: "小寶", showDayCount: true)])
        let before = try rawProfiles()
        let bytesBefore = try Data(contentsOf: fileURL)
        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 2, "107.7: no profile lost")
        XCTAssertEqual(loaded, before, "107.7: nothing changes")
        XCTAssertFalse(loaded[0].showDayCount, "107.2: still date only")
        XCTAssertEqual(try Data(contentsOf: fileURL), bytesBefore, "107.7: no write-back")
    }

    /// 107.7: a hand-made record with both switches off has the day count
    /// turned on, is written back, and the profile is kept.
    func testBothOffRecordIsRepairedAndKept() throws {
        try writeFixture([record(id: Self.dateOnlyID, name: "都關", showDayCount: false, showDate: false),
                          record(id: Self.countingID, name: "小寶", showDayCount: true)])
        let before = try rawProfiles()
        let loaded = try makeStore().load()
        XCTAssertEqual(loaded.count, 2, "107.7: no profile lost")
        var expected = before
        expected[0].showDayCount = true
        XCTAssertEqual(loaded, expected, "107.7: only showDayCount changes")
        XCTAssertEqual(try rawProfiles(), expected, "107.7: written back")
    }

    /// 47.2: a file where every record already shows the day count is left
    /// byte-for-byte alone and keeps every profile.
    func testAllTrueFileIsNotRewritten() throws {
        try writeFixture([record(id: Self.dateOnlyID, name: "日期", showDayCount: true),
                          record(id: Self.countingID, name: "小寶", showDayCount: true)])
        let bytesBefore = try Data(contentsOf: fileURL)

        let loaded = try makeStore().load()

        XCTAssertEqual(loaded.map(\.id.uuidString), [Self.dateOnlyID, Self.countingID], "47.2")
        XCTAssertTrue(loaded.allSatisfy(\.showDayCount), "47.2")
        XCTAssertEqual(try Data(contentsOf: fileURL), bytesBefore, "47.2: no write-back")
    }

    /// 107.2: adding or duplicating a date-only profile keeps it date only.
    func testAddedAndDuplicatedDateOnlyProfilesStayDateOnly() throws {
        let store = try makeStore()
        store.load()
        let added = try store.add(CameraProfile(name: "只看日期",
                                                startDate: DateFixture.components(2025, 1, 15),
                                                showDayCount: false,
                                                showDate: true))
        XCTAssertFalse(added.showDayCount, "107.2 add")
        let copy = try store.duplicate(id: added.id)
        XCTAssertFalse(copy.showDayCount, "107.2 duplicate")
        XCTAssertEqual(try rawProfiles().map(\.showDayCount), [true, false, false], "107.2 persisted")
    }

    /// 107.2: an edit that turns the day count off (with the date on) is stored.
    func testUpdateCanTurnTheDayCountOff() throws {
        let store = try makeStore()
        var current = try XCTUnwrap(store.load().first)
        current.showDayCount = false
        current.showDate = true
        let stored = try store.update(current)
        XCTAssertFalse(stored.showDayCount, "107.2 update")
        XCTAssertTrue(stored.showDate, "107.2 update keeps showDate")
    }

    /// 107.6: a date-only profile prints the date (and the name), never a
    /// count, in the date-then-name order.
    func testDateOnlyProfileRendersDateAndName() throws {
        try writeFixture([record(id: Self.dateOnlyID, name: "只看日期", showDayCount: false)])
        let loaded = try XCTUnwrap(makeStore().load().first)
        let output = TemplateRenderer().render(profile: loaded,
                                               capturedAt: try referenceInstant(),
                                               calendar: DateFixture.taipei)
        XCTAssertEqual(output, "2026.03.20 只看日期", "107.6／107.8")
    }
}

/// Covers TASK-70 70.2, 70.4 and 70.5 through `ProfileStore`: the 0.5
/// outlines migrate with every other field kept, the new parameters
/// survive a restart, and values out of range are never written.
final class CameraProfileOutlineTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CameraProfileOutlineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CameraProfileOutlineTests-\(UUID().uuidString)"
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
        let instant = try XCTUnwrap(DateFixture.date(2026, 3, 20, hour: 10))
        return ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
    }

    /// One 0.5 record with a non-default value in every field.
    private func record(index: Int, outline: String, outlineColor: String?) -> String {
        let color = outlineColor.map { #""outlineColor":"\#($0)","# } ?? ""
        return """
        {"id":"00000000-0000-0000-0000-00000000070\(index)","name":"外框\(index)",\
        "startDate":{"year":2025,"month":1,"day":15},\
        "countingRule":"dayZero","showDayCount":true,"showDate":true,"showName":true,\
        "displayUnits":["month","day"],"useAgeWording":false,\
        "position":{"x":0.25,"y":0.75},\
        "style":{"fontID":"songti","textColor":"#FF6B9D","outline":"\(outline)",\(color)\
        "shadow":"glow","sizeScale":120},\
        "createdAt":789000000,"updatedAt":789000000}
        """
    }

    /// The 0.5 outlines with an automatic and a chosen outline color, and
    /// the style each must load as — written out independently of the
    /// decoder. Alpha 50% is stored as 128/255.
    private func fixture() -> [(record: String, style: OverlayStyle)] {
        let pink = OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D)
        let blue = OverlayColor(red8: 0x0A, green8: 0x84, blue8: 0xFF)
        let half = 128.0 / 255
        func style(_ outline: OverlayOutline, _ outlineColor: OverlayColor?, auto: Double = 1,
                   width: Double = 2) -> OverlayStyle {
            var style = OverlayStyle(fontID: .songti, textColor: pink, outline: outline, outlineColor: outlineColor,
                                     autoOutlineOpacity: auto, strokeWidth: width, boxPadding: 12, shadow: .glow,
                                     sizeScale: 120)
            // The pre-0.5 glow keeps its text-colour source at 230/255 (TASK-86).
            style.shadowColorSource = .textColor
            style.shadowOpacity = 230.0 / 255
            return style
        }
        return [
            (record(index: 0, outline: "thinStroke", outlineColor: nil), style(.stroke, nil, width: 2)),
            (record(index: 1, outline: "thinStroke", outlineColor: "#0A84FF"), style(.stroke, blue, width: 2)),
            (record(index: 2, outline: "thickStroke", outlineColor: nil), style(.stroke, nil, width: 4)),
            (record(index: 3, outline: "thickStroke", outlineColor: "#0A84FF"), style(.stroke, blue, width: 4)),
            (record(index: 4, outline: "translucentBox", outlineColor: nil), style(.box, nil, auto: half)),
            (record(index: 5, outline: "translucentBox", outlineColor: "#0A84FF"), style(.box, blue.withOpacity(half))),
            (record(index: 6, outline: "solidBox", outlineColor: nil), style(.box, nil)),
            (record(index: 7, outline: "solidBox", outlineColor: "#0A84FF"), style(.box, blue))
        ]
    }

    /// 70.2 / 70.5: every 0.5 outline loads as the migration table says,
    /// with no profile lost and every other field intact; saved and reloaded
    /// (a restart), it is the same and names no 0.5 outline.
    func testEveryLegacyOutlineMigratesAndSurvivesARestart() throws {
        let rows = fixture()
        try Data("[\(rows.map(\.record).joined(separator: ","))]".utf8).write(to: fileURL, options: [.atomic])

        let store = try makeStore()
        let loaded = store.load()

        XCTAssertEqual(loaded.count, rows.count, "70.2: no profile lost")
        for (index, row) in rows.enumerated() {
            let profile = loaded[index]
            XCTAssertEqual(profile.style, row.style, "70.2 \(profile.name)")
            XCTAssertEqual(profile.name, "外框\(index)")
            XCTAssertEqual(profile.countingRule, .dayZero)
            XCTAssertEqual(profile.displayUnits, [.month, .day])
            XCTAssertEqual(profile.position, .custom(x: 0.25, y: 0.75))
        }

        try store.update(loaded[0])
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        for legacy in ["thinStroke", "thickStroke", "translucentBox", "solidBox"] {
            XCTAssertFalse(text.contains("\"\(legacy)\""), "70.2: \(legacy) written back")
        }
        XCTAssertEqual(try makeStore().load().map(\.style), loaded.map(\.style), "70.4 after a restart")
    }

    /// 70.4: parameters set through the store come back from a fresh store.
    func testParametersSurviveARestart() throws {
        let store = try makeStore()
        store.load()
        let style = OverlayStyle(outline: .box, autoOutlineOpacity: 0.3, strokeWidth: 5.5, boxPadding: 20)
        let added = try store.add(CameraProfile(name: "參數", startDate: DateFixture.components(2025, 1, 15),
                                                style: style))

        let reloaded = try XCTUnwrap(try makeStore().load().first { $0.id == added.id }, "70.4: profile kept")
        XCTAssertEqual(reloaded.style, added.style, "70.4")
        XCTAssertEqual(reloaded.style.strokeWidth, 5.5, "70.4")
        XCTAssertEqual(reloaded.style.boxPadding, 20, "70.4")
        XCTAssertEqual(reloaded.style.autoOutlineOpacity, 0.3, accuracy: 0.5 / 255, "70.4")
    }

    /// 70.4: values out of range are rejected and never written.
    func testOutOfRangeParametersAreRejected() throws {
        let store = try makeStore()
        store.load()
        let cases: [(OverlayStyle, CameraProfileValidationError)] = [
            (OverlayStyle(strokeWidth: 0.5), .outlineParameterOutOfRange),
            (OverlayStyle(strokeWidth: 6.5), .outlineParameterOutOfRange),
            (OverlayStyle(strokeWidth: .nan), .outlineParameterOutOfRange),
            (OverlayStyle(boxPadding: -1), .outlineParameterOutOfRange),
            (OverlayStyle(boxPadding: 25), .outlineParameterOutOfRange),
            (OverlayStyle(autoOutlineOpacity: 0.04), .colorNotStorable),
            (OverlayStyle(autoOutlineOpacity: 1.01), .colorNotStorable)
        ]
        for (index, (style, error)) in cases.enumerated() {
            let name = "超出\(index)"
            let profile = CameraProfile(name: name, startDate: DateFixture.components(2025, 1, 15), style: style)
            XCTAssertThrowsError(try profile.validatedForPersistence(calendar: DateFixture.taipei), "70.4 \(index)") {
                XCTAssertEqual($0 as? CameraProfileValidationError, error, "70.4 \(index)")
            }
            XCTAssertThrowsError(try store.add(profile), "70.4 \(index)")
            XCTAssertFalse((try? String(contentsOf: fileURL, encoding: .utf8))?.contains(name) ?? false,
                           "70.4: \(name) not written")
        }
        for style in [OverlayStyle(strokeWidth: 1, boxPadding: 0), OverlayStyle(strokeWidth: 6, boxPadding: 24)] {
            let profile = CameraProfile(name: "邊界", startDate: DateFixture.components(2025, 1, 15), style: style)
            XCTAssertNoThrow(try profile.validatedForPersistence(calendar: DateFixture.taipei), "70.4 bounds")
        }
    }
}

// MARK: - TASK-71: shadow parameters

/// Covers TASK-71 71.2 and 71.5 through `ProfileStore`: 0.5 shadows load as
/// their presets without a rewrite, parameters survive a restart, and values
/// out of range are never written.
final class CameraProfileShadowTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CameraProfileShadowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CameraProfileShadowTests-\(UUID().uuidString)"
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
        let instant = try XCTUnwrap(DateFixture.date(2026, 3, 20, hour: 10))
        return ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
    }

    /// One 0.5 record with a non-default value in every field.
    private func record(index: Int, shadow: String) -> String {
        """
        {"id":"00000000-0000-0000-0000-00000000071\(index)","name":"陰影\(index)",\
        "startDate":{"year":2025,"month":1,"day":15},\
        "countingRule":"dayZero","showDayCount":true,"showDate":true,"showName":true,\
        "displayUnits":["month","day"],"useAgeWording":false,\
        "position":{"x":0.25,"y":0.75},\
        "style":{"fontID":"songti","textColor":"#FF6B9DB3","outline":"thickStroke","outlineColor":"#0A84FF",\
        "shadow":"\(shadow)","sizeScale":120},\
        "createdAt":789000000,"updatedAt":789000000}
        """
    }

    /// 71.2 / 71.5: every 0.5 shadow loads as its preset — written out here
    /// independently of the decoder — with no profile lost, every other
    /// field intact and the file untouched; saved and reloaded (a restart),
    /// it is the same and no `shadow` name is written.
    func testEveryLegacyShadowMigratesAndSurvivesARestart() throws {
        let shadows = ["none", "soft", "hard", "glow"]
        let before = Data("[\(shadows.enumerated().map { record(index: $0, shadow: $1) }.joined(separator: ","))]".utf8)
        try before.write(to: fileURL, options: [.atomic])
        typealias Expected = (shows: Bool, source: OverlayShadowColorSource, alpha8: Int, x: Double, y: Double,
                              blur: Double)
        let expected: [Expected] = [
            (false, .custom, 153, 0, 2, 4),
            (true, .custom, 153, 0, 2, 4),
            (true, .custom, 191, 2, 2, 0),
            (true, .textColor, 230, 0, 0, 8)
        ]

        let store = try makeStore()
        let loaded = store.load()

        XCTAssertEqual(loaded.count, shadows.count, "71.2: no profile lost")
        for (index, profile) in loaded.enumerated() {
            let style = profile.style
            let row = expected[index]
            let label = "71.2 \(shadows[index])"
            XCTAssertEqual(style.showsShadow, row.shows, label)
            XCTAssertEqual(style.shadowColorSource, row.source, label)
            XCTAssertEqual(style.shadowColor, OverlayColor(red8: 0, green8: 0, blue8: 0,
                                                           opacity: Double(row.alpha8) / 255), label)
            XCTAssertEqual(style.shadowOffsetX, row.x, label)
            XCTAssertEqual(style.shadowOffsetY, row.y, label)
            XCTAssertEqual(style.shadowBlur, row.blur, label)
            XCTAssertEqual(style.shadowPreset?.rawValue, shadows[index], label)
            XCTAssertEqual(style.textColor, OverlayColor(hex: "#FF6B9DB3"), label)
            XCTAssertEqual(style.outline, .stroke, label)
            XCTAssertEqual(style.strokeWidth, 4, label)
            XCTAssertEqual(style.outlineColor, OverlayColor(hex: "#0A84FF"), label)
            XCTAssertEqual(style.fontID, .songti, label)
            XCTAssertEqual(style.sizeScale, 120, label)
            XCTAssertEqual(profile.name, "陰影\(index)")
            XCTAssertEqual(profile.countingRule, .dayZero)
            XCTAssertEqual(profile.position, .custom(x: 0.25, y: 0.75))
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), before, "71.2: loading alone does not rewrite the file")

        try store.update(loaded[0])
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("\"shadow\""), "71.2: the 0.5 shadow name is written back")
        XCTAssertEqual(try makeStore().load().map(\.style), loaded.map(\.style), "71.5 after a restart")
    }

    /// 71.5: parameters set through the store come back from a fresh store.
    func testParametersSurviveARestart() throws {
        let store = try makeStore()
        store.load()
        var style = OverlayStyle(shadow: .glow)
        style.shadowColorSource = .custom
        style.shadowColor = OverlayColor(red8: 0xED, green8: 0x49, blue8: 0x56, opacity: 0.35)
        style.shadowOffsetX = -6.5
        style.shadowOffsetY = 8
        style.shadowBlur = 12.5
        let added = try store.add(CameraProfile(name: "陰影參數", startDate: DateFixture.components(2025, 1, 15),
                                                style: style))

        let reloaded = try XCTUnwrap(try makeStore().load().first { $0.id == added.id }, "71.5: profile kept")
        XCTAssertEqual(reloaded.style, added.style, "71.5")
        XCTAssertEqual(reloaded.style.shadowColorSource, .custom, "71.5")
        XCTAssertEqual(reloaded.style.shadowOffsetX, -6.5, "71.5")
        XCTAssertEqual(reloaded.style.shadowOffsetY, 8, "71.5")
        XCTAssertEqual(reloaded.style.shadowBlur, 12.5, "71.5")
        XCTAssertEqual(reloaded.style.shadowOpacity, 0.35, accuracy: 0.5 / 255, "71.5")
        XCTAssertNil(reloaded.style.shadowPreset, "71.3: custom parameters name no preset")
    }

    /// 71.5: values out of range are rejected and never written.
    func testOutOfRangeParametersAreRejected() throws {
        let store = try makeStore()
        store.load()
        func style(_ edit: (inout OverlayStyle) -> Void) -> OverlayStyle {
            var style = OverlayStyle()
            edit(&style)
            return style
        }
        let cases: [(OverlayStyle, CameraProfileValidationError)] = [
            (style { $0.shadowOffsetX = -8.5 }, .shadowParameterOutOfRange),
            (style { $0.shadowOffsetX = .nan }, .shadowParameterOutOfRange),
            (style { $0.shadowOffsetY = 9 }, .shadowParameterOutOfRange),
            (style { $0.shadowBlur = -0.1 }, .shadowParameterOutOfRange),
            (style { $0.shadowBlur = 16.5 }, .shadowParameterOutOfRange),
            (style { $0.showsShadow = false; $0.shadowBlur = 30 }, .shadowParameterOutOfRange),
            (style { $0.shadowOpacity = 0.04 }, .colorNotStorable),
            (style { $0.shadowColor = OverlayColor(red: 1.2, green: 0, blue: 0) }, .colorNotStorable)
        ]
        for (index, (style, error)) in cases.enumerated() {
            let name = "陰影超出\(index)"
            let profile = CameraProfile(name: name, startDate: DateFixture.components(2025, 1, 15), style: style)
            XCTAssertThrowsError(try profile.validatedForPersistence(calendar: DateFixture.taipei), "71.5 \(index)") {
                XCTAssertEqual($0 as? CameraProfileValidationError, error, "71.5 \(index)")
            }
            XCTAssertThrowsError(try store.add(profile), "71.5 \(index)")
            XCTAssertFalse((try? String(contentsOf: fileURL, encoding: .utf8))?.contains(name) ?? false,
                           "71.5: \(name) not written")
        }
        let bounds = [style { $0.shadowOffsetX = -8; $0.shadowOffsetY = 8; $0.shadowBlur = 0 },
                      style { $0.shadowOffsetX = 8; $0.shadowOffsetY = -8; $0.shadowBlur = 16 }]
        for style in bounds {
            let profile = CameraProfile(name: "邊界", startDate: DateFixture.components(2025, 1, 15), style: style)
            XCTAssertNoThrow(try profile.validatedForPersistence(calendar: DateFixture.taipei), "71.5 bounds")
        }
    }
}

// MARK: - 614 album, fallback and export format

/// Covers #614: the album, fallback and export-format fields of `CameraProfile`.
final class CameraProfileAlbumFieldsTests: XCTestCase {

    private func jsonObject(_ profile: CameraProfile) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> CameraProfile {
        try JSONDecoder().decode(CameraProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func albumSample() -> CameraProfile {
        CameraProfile(name: "小寶",
                      startDate: DateFixture.components(2025, 1, 15),
                      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                      updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
                      albumIdentifier: "ALBUM-1",
                      fallbackAssetIDs: ["A/L0/001", "B/L0/002"],
                      exportFormat: .polaroid)
    }

    /// 614.1: a 1.3.0 record has none of the three keys.
    func test_614_1_version130RecordDecodesWithDefaults() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"小寶",
        "startDate":{"year":2025,"month":1,"day":15},"countingRule":"dayOne",
        "showDayCount":true,"showDate":false,"showName":false,"displayUnits":["day"],
        "useAgeWording":false,"dayCountFormat":"ordinal","position":{"anchor":"bottomTrailing"},
        "showFilmDate":false,"filmDateCorner":"bottomTrailing",
        "createdAt":1700000000,"updatedAt":1700000500}
        """
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        // Borrow a real `position` and `style` encoding so the fixture tracks the format.
        let template = try jsonObject(albumSample())
        object["position"] = template["position"]
        object["filmDateCorner"] = template["filmDateCorner"]
        object["style"] = template["style"]
        object["createdAt"] = template["createdAt"]
        object["updatedAt"] = template["updatedAt"]
        for key in ["albumIdentifier", "fallbackAssetIDs", "exportFormat"] {
            XCTAssertNil(object[key])
        }
        let decoded = try decode(object)
        XCTAssertNil(decoded.albumIdentifier)
        XCTAssertEqual(decoded.fallbackAssetIDs, [])
        XCTAssertEqual(decoded.exportFormat, .overlay)
        XCTAssertEqual(decoded.name, "小寶")
    }

    /// 614.2
    func test_614_2_newFieldsSurviveARoundTrip() throws {
        let original = albumSample()
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.albumIdentifier, "ALBUM-1")
        XCTAssertEqual(decoded.fallbackAssetIDs, ["A/L0/001", "B/L0/002"])
        XCTAssertEqual(decoded.exportFormat, .polaroid)
    }

    /// 614.3
    func test_614_3_unknownExportFormatFallsBackToOverlay() throws {
        var json = try jsonObject(albumSample())
        json["exportFormat"] = "film"
        let decoded = try decode(json)
        XCTAssertEqual(decoded.exportFormat, .overlay)
        XCTAssertEqual(decoded.albumIdentifier, "ALBUM-1")
        XCTAssertEqual(decoded.name, "小寶")
    }

    /// The three fields are not validated: a profile with them still persists.
    func test_614_newFieldsAreNotValidated() throws {
        var subject = albumSample()
        subject.albumIdentifier = ""
        XCTAssertNoThrow(try subject.validatedForPersistence(calendar: DateFixture.taipei))
    }
}
