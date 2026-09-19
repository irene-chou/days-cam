import XCTest
@testable import DaysCam

/// Covers `ProfileEditModel`'s state transitions (PRD FR-1.6, FR-3.6, FR-3.7)
/// without a real `ProfileStore` — the model is built directly from a
/// `CameraProfile` and a save closure.
@MainActor
final class ProfileEditModelTests: XCTestCase {
    private func fixedNow() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
    }

    private func profile(name: String = "小寶",
                         startDate: DateComponents = DateFixture.components(2026, 1, 1),
                         showDayCount: Bool = true,
                         showDate: Bool = false) -> CameraProfile {
        CameraProfile(name: name, startDate: startDate, showDayCount: showDayCount, showDate: showDate)
    }

    private func makeModel(profile: CameraProfile,
                           mode: ProfileEditModel.Mode = .edit,
                           now: Date,
                           onSave: @escaping (CameraProfile) throws -> Void = { _ in }) -> ProfileEditModel {
        ProfileEditModel(profile: profile,
                         mode: mode,
                         calendar: DateFixture.taipei,
                         calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
                         renderer: TemplateRenderer(),
                         onSave: onSave)
    }

    // MARK: - Name clamping (FR-1.6)

    func testSetNameClampsAt20CharactersRatherThanRejecting() throws {
        let model = makeModel(profile: profile(), now: try fixedNow())
        model.setName("一二三四五六七八九十一二三四五六七八九十壹") // 21 characters
        XCTAssertEqual(model.profile.name.count, 20)
    }

    func testSetNameUnder20CharactersIsUnchanged() throws {
        let model = makeModel(profile: profile(), now: try fixedNow())
        model.setName("小寶貝")
        XCTAssertEqual(model.profile.name, "小寶貝")
    }

    // MARK: - Validation / canSave

    func testEmptyNameIsInvalid() throws {
        let model = makeModel(profile: profile(name: ""), now: try fixedNow())
        XCTAssertEqual(model.validationError, .nameEmpty)
        XCTAssertFalse(model.canSave)
    }

    func testWhitespaceOnlyNameIsInvalid() throws {
        let model = makeModel(profile: profile(name: "   "), now: try fixedNow())
        XCTAssertEqual(model.validationError, .nameEmpty)
        XCTAssertFalse(model.canSave)
    }

    func testValidProfileCanSave() throws {
        let model = makeModel(profile: profile(), now: try fixedNow())
        XCTAssertNil(model.validationError)
        XCTAssertTrue(model.canSave)
    }

    // MARK: - Counting fields visibility (FR-3.7)

    func testCountingFieldsShownWhenDayCountOn() throws {
        let model = makeModel(profile: profile(showDayCount: true, showDate: false), now: try fixedNow())
        XCTAssertTrue(model.showsCountingFields)
    }

    func testCountingFieldsHiddenWhenDayCountOff() throws {
        let model = makeModel(profile: profile(showDayCount: false, showDate: true), now: try fixedNow())
        XCTAssertFalse(model.showsCountingFields)
    }

    // MARK: - Start date binding

    func testStartDateRoundTripsThroughDateKeepingOnlyYearMonthDay() throws {
        let model = makeModel(profile: profile(), now: try fixedNow())
        let picked = try XCTUnwrap(DateFixture.date(2025, 6, 15, hour: 14, minute: 30, in: DateFixture.taipei))
        model.setStartDate(picked)
        XCTAssertEqual(model.profile.startDate.year, 2025)
        XCTAssertEqual(model.profile.startDate.month, 6)
        XCTAssertEqual(model.profile.startDate.day, 15)
        XCTAssertNil(model.profile.startDate.hour)
    }

    func testStartDateUpperBoundIsTheInjectedNow() throws {
        let now = try fixedNow()
        let model = makeModel(profile: profile(), now: now)
        XCTAssertEqual(model.startDateUpperBound, now)
    }

    // MARK: - Save

    func testSaveForwardsTheCurrentProfileToOnSave() throws {
        var savedProfile: CameraProfile?
        let model = makeModel(profile: profile(name: "小寶"), now: try fixedNow()) { savedProfile = $0 }
        model.setName("小寶貝")
        try model.save()
        XCTAssertEqual(savedProfile?.name, "小寶貝")
    }

    func testSaveRethrowsOnSaveFailure() throws {
        struct DummyError: Error {}
        let model = makeModel(profile: profile(), now: try fixedNow()) { _ in throw DummyError() }
        XCTAssertThrowsError(try model.save())
    }
}
