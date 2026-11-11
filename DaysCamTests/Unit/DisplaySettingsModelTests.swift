import XCTest
@testable import DaysCam

/// Covers `DisplaySettingsModel`'s state transitions (PRD FR-2.1–FR-2.10,
/// FR-4.1–FR-4.9) without a real `ProfileStore` — the model is driven
/// entirely through an injected `updateProfile` closure.
///
/// Fixture matches TASK-11's acceptance table exactly: start date
/// 2026-01-01, `.dayOne`, `DAYSCAM_FAKE_TODAY` fixed at 2026-01-10, so
/// `n = 10`, year track `(0,0,9)`, month track `(0,9)`, week track `(1,3)`
/// (TASK-11 acceptance 11.1–11.33).
@MainActor
final class DisplaySettingsModelTests: XCTestCase {
    private func fixedNow() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
    }

    private func baselineProfile(name: String = "小寶",
                                 startDate: DateComponents = DateFixture.components(2026, 1, 1),
                                 showDayCount: Bool = true,
                                 showDate: Bool = false,
                                 showName: Bool = false,
                                 displayUnits: Set<DisplayUnit> = [.day],
                                 useAgeWording: Bool = false) -> CameraProfile {
        CameraProfile(name: name,
                     startDate: startDate,
                     showDayCount: showDayCount,
                     showDate: showDate,
                     showName: showName,
                     displayUnits: displayUnits,
                     useAgeWording: useAgeWording)
    }

    private final class Spy {
        var updated: [CameraProfile] = []
        var shouldThrow: Error?

        func update(_ profile: CameraProfile) throws {
            if let error = shouldThrow { throw error }
            updated.append(profile)
        }
    }

    private func makeModel(profile: CameraProfile,
                           now: Date,
                           spy: Spy) -> DisplaySettingsModel {
        DisplaySettingsModel(profile: profile,
                             calendar: DateFixture.taipei,
                             calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
                             renderer: TemplateRenderer(),
                             updateProfile: spy.update)
    }

    // MARK: - 11.7 initial overlay

    func testInitialOverlayIsDayCountOnly() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        XCTAssertEqual(model.overlayPreviewText, "第 10 天")
    }

    // MARK: - A-2 顯示開關 (11.8–11.14)

    func testTogglingShowNameOnPrependsNameWithHalfWidthSpace() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setShowName(true)
        XCTAssertEqual(model.overlayPreviewText, "小寶 第 10 天")
    }

    func testTogglingShowNameOffLeavesNoLeadingSpace() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(showName: true), now: try fixedNow(), spy: spy)
        model.setShowName(false)
        XCTAssertEqual(model.overlayPreviewText, "第 10 天")
    }

    func testTogglingShowDateOnPrependsDateWithIdeographicSpace() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setShowDate(true)
        XCTAssertEqual(model.overlayPreviewText, "2026.01.10 第 10 天")
    }

    /// 48.2: 日期 and 名稱 may both be off; the day count remains.
    func testShowDateAndNameCanBothBeTurnedOffLeavingOnlyTheDayCount() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(showDate: true, showName: true), now: try fixedNow(), spy: spy)
        model.setShowDate(false)
        model.setShowName(false)
        XCTAssertFalse(model.profile.showDate, "48.2")
        XCTAssertFalse(model.profile.showName, "48.2")
        XCTAssertTrue(model.profile.showDayCount, "48.2")
        XCTAssertEqual(spy.updated.count, 2, "48.2 each change persists")
        XCTAssertEqual(model.overlayPreviewText, "第 10 天", "48.2")
    }

    /// 48.2: turning 日期 off never no-ops, even with 名稱 already off.
    func testSetShowDateOffAppliesEvenWhenNameIsOff() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(showDate: true, showName: false), now: try fixedNow(), spy: spy)
        model.setShowDate(false)
        XCTAssertFalse(model.profile.showDate, "48.2")
        XCTAssertEqual(spy.updated.count, 1, "48.2")
    }

    // MARK: - A-3 單位區間 (11.15–11.20), inputs as 0.2 unit sets; texts unchanged

    func testDayDayIsTheDefaultOrdinalForm() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        XCTAssertEqual(model.overlayPreviewText, "第 10 天")
    }

    func testWeekAndDayReadsWeekAndDay() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.week, .day]), now: try fixedNow(), spy: spy)
        XCTAssertEqual(model.overlayPreviewText, "1 週又 3 天")
    }

    func testWeekOnlyOmitsTheDayRemainder() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.week]), now: try fixedNow(), spy: spy)
        XCTAssertEqual(model.overlayPreviewText, "1 週")
    }

    func testMonthDayOmitsAZeroMonth() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.month, .day]), now: try fixedNow(), spy: spy)
        XCTAssertEqual(model.overlayPreviewText, "9 天")
    }

    func testYearMonthDayOmitsZeroYearAndMonth() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.year, .month, .day]), now: try fixedNow(), spy: spy)
        XCTAssertEqual(model.overlayPreviewText, "9 天")
    }

    /// 93.15 (TASK-93): all zero reads as the smallest checked unit — the year.
    func testYearOnlyWithAllZeroShowsZeroYears() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.year]), now: try fixedNow(), spy: spy)
        XCTAssertEqual(model.overlayPreviewText, "0 年", "93.15")
    }

    // MARK: - A-6 持久化 (11.32–11.33)

    func testEveryMutationForwardsTheUpdatedProfileToUpdateProfile() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setShowName(true)
        model.setShowDate(!model.profile.showDate)
        model.setDayCountFormat(.plain)
        XCTAssertEqual(spy.updated.count, 3)
        XCTAssertEqual(spy.updated.last?.showDate, model.profile.showDate)
        XCTAssertEqual(spy.updated.last?.dayCountFormat, .plain)
    }

    func testDistinctModelsForDifferentProfilesDoNotShareState() throws {
        let spyA = Spy()
        let spyB = Spy()
        let modelA = makeModel(profile: baselineProfile(name: "A"), now: try fixedNow(), spy: spyA)
        let modelB = makeModel(profile: baselineProfile(name: "B"), now: try fixedNow(), spy: spyB)
        modelA.setShowName(!modelA.profile.showName)
        XCTAssertNotEqual(modelA.profile.showName, modelB.profile.showName)
    }

    // MARK: - Failure surfaces as lastError

    func testUpdateProfileFailureIsSurfacedAsLastError() throws {
        struct DummyError: Error {}
        let spy = Spy()
        spy.shouldThrow = DummyError()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setShowName(true)
        XCTAssertNotNil(model.lastError)
        // The local copy still reflects the attempted change even though the
        // write failed, matching ProfileEditModel's "state, not a round trip"
        // model — there is no server-authoritative copy to roll back to here.
        XCTAssertTrue(model.profile.showName)
    }

    // MARK: - TASK-109 (#423) the edit page's 寫在照片上 is this tab's 名稱

    /// 109.3: a `showName` written elsewhere shows up here without a write.
    func testExternalShowNameChangeIsTakenOverWithoutWriting() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        var latest = model.profile
        latest.showName = true
        model.applyExternalChanges(from: latest)
        XCTAssertTrue(model.profile.showName, "109.3")
        XCTAssertTrue(spy.updated.isEmpty, "109.3 nothing written back")
        var other = baselineProfile(name: "別人")
        other.showName = false
        model.applyExternalChanges(from: other)
        XCTAssertTrue(model.profile.showName, "another profile's record is ignored")
    }

    // MARK: - TASK-107 (#426) the day-count switch

    /// 107.1／107.2: the day count can be turned off once the date is on,
    /// and the overlay then prints the date (and name) alone.
    func testDayCountCanBeTurnedOffWhenTheDateIsOn() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setShowDate(true)
        model.setShowDayCount(false)
        XCTAssertFalse(model.profile.showDayCount, "107.2")
        XCTAssertEqual(model.overlayPreviewText, "2026.01.10", "107.2 date only")
        model.setShowName(true)
        XCTAssertEqual(model.overlayPreviewText, "2026.01.10 小寶", "107.2 date then name")
        XCTAssertEqual(spy.updated.last?.showDayCount, false, "persisted")
    }

    /// #713-1: 天數／日期／名稱 may all be off; each write is persisted.
    func testAllThreeContentSwitchesCanBeTurnedOff() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setShowName(false)
        model.setShowDayCount(false)
        XCTAssertFalse(model.profile.showDayCount, "#713-1 last switch turns off")
        XCTAssertEqual(spy.updated.last?.showDayCount, false, "#713-1 persisted")
        XCTAssertEqual(model.overlayPreviewText, "", "#713-3 nothing to print")

        model.setShowDate(true)
        model.setShowDate(false)
        XCTAssertFalse(model.profile.showDate)
    }

    // MARK: - #521 底片日期 (152.3–152.5)

    func testFilmDateCornerWritesThroughAndSurvivesTogglingOffAndOn() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setShowFilmDate(true)
        XCTAssertEqual(model.profile.filmDateCorner, .bottomLeading, "default is bottom-left")
        model.setFilmDateCorner(.topTrailing)
        XCTAssertEqual(spy.updated.last?.filmDateCorner, .topTrailing, "152.3 persisted at once")
        model.setShowFilmDate(false)
        model.setShowFilmDate(true)
        XCTAssertEqual(model.profile.filmDateCorner, .topTrailing, "152.3 corner kept")
    }

    func testFilmDateSwitchIsIndependentOfDateAndDayCount() throws {
        for dayCount in [true, false] {
            for date in [true, false] {
                let spy = Spy()
                let model = makeModel(profile: baselineProfile(showDayCount: dayCount, showDate: date),
                                      now: try fixedNow(), spy: spy)
                model.setShowFilmDate(true)
                XCTAssertTrue(model.profile.showFilmDate)
                XCTAssertEqual(model.profile.showDayCount, dayCount, "152.4")
                XCTAssertEqual(model.profile.showDate, date, "152.4")
                model.setShowFilmDate(false)
                XCTAssertEqual(model.profile.showDayCount, dayCount)
                XCTAssertEqual(model.profile.showDate, date)
            }
        }
    }

    /// #713: the film date has no bearing on the content switches; with it on,
    /// the last of 天數／日期／名稱 still turns off.
    func testFilmDateDoesNotKeepTheContentSwitchesOn() throws {
        let spy = Spy()
        let profile = CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1),
                                    showDayCount: true, showDate: false, showName: false,
                                    showFilmDate: true)
        let model = makeModel(profile: profile, now: try fixedNow(), spy: spy)
        model.setShowDayCount(false)
        XCTAssertFalse(model.profile.showDayCount)
        XCTAssertTrue(model.profile.showFilmDate, "film date untouched")
        XCTAssertEqual(spy.updated.last?.showDayCount, false)
    }

    // MARK: - #583 寫法

    func test_583_setDayCountFormatSavesAndUpdatesTheOverlay() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setDayCountFormat(.dDay)
        XCTAssertEqual(model.profile.dayCountFormat, .dDay)
        XCTAssertEqual(spy.updated.last?.dayCountFormat, .dDay, "sent through onChange")
        XCTAssertEqual(model.overlayPreviewText, "D+9")
    }

    func test_583_sameFormatIsNotSaved() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setDayCountFormat(.ordinal)
        XCTAssertTrue(spy.updated.isEmpty)
    }

    func test_583_refusedWhileUnitsAreInert() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(showDate: true), now: try fixedNow(), spy: spy)
        model.setShowDayCount(false)
        XCTAssertTrue(model.areUnitsInert)
        spy.updated.removeAll()
        model.setDayCountFormat(.dayN)
        XCTAssertEqual(model.profile.dayCountFormat, .ordinal)
        XCTAssertTrue(spy.updated.isEmpty)
    }

    func test_583_changeableWithOtherUnitsCheckedButNotApplied() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(startDate: DateFixture.components(2025, 12, 29),
                                                       displayUnits: [.week, .day]),
                              now: try fixedNow(), spy: spy)
        let before = model.overlayPreviewText
        model.setDayCountFormat(.dayN)
        XCTAssertEqual(spy.updated.last?.dayCountFormat, .dayN)
        XCTAssertEqual(model.overlayPreviewText, before, "not applied while 週 is checked")
    }
}

// MARK: - 107.4 寫法 inert while the day count is off (units moved to RulesTabModel, #721)

extension DisplaySettingsModelTests {
    func testAreUnitsInertTracksTheDayCountSwitch() throws {
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: Spy())
        XCTAssertFalse(model.areUnitsInert)
        model.setShowDate(true)
        model.setShowDayCount(false)
        XCTAssertTrue(model.areUnitsInert, "107.4")
        model.setShowDayCount(true)
        XCTAssertFalse(model.areUnitsInert)
    }
}
