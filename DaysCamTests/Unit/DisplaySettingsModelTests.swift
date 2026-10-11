import XCTest
@testable import DaysCam

/// Covers `DisplaySettingsModel`'s state transitions (PRD FR-2.1–FR-2.10,
/// FR-4.1–FR-4.9) without a real `ProfileStore` — the model is driven
/// entirely through an injected `updateProfile` closure.
///
/// Fixture matches TASK-11's acceptance table exactly: start date
/// 2026-01-01, `.dayOne`, `DAYSCAM_FAKE_TODAY` fixed at 2026-01-10, so
/// `n = 10`, year track `(0,0,9)`, month track `(0,9)`, week track `(1,3)`
/// (all already verified in TASKS.md 11.1–11.33).
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
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.toggleUnit(.week)
        XCTAssertEqual(model.profile.displayUnits, [.week, .day])
        XCTAssertEqual(model.overlayPreviewText, "1 週又 3 天")
    }

    func testWeekOnlyOmitsTheDayRemainder() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.toggleUnit(.week)
        model.toggleUnit(.day)
        XCTAssertEqual(model.profile.displayUnits, [.week])
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

    // MARK: - toggleUnit (0.2 FR-11.3, TASK-27; replaces 0.1 11.21–11.27)

    func testTogglingTheOnlyCheckedUnitIsANoOp() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.toggleUnit(.day)
        XCTAssertEqual(model.profile.displayUnits, [.day], "27.13")
        XCTAssertTrue(spy.updated.isEmpty, "27.13")
    }

    func testToggleAddsAndRemovesAnyUnit() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.toggleUnit(.year)
        model.toggleUnit(.week)
        XCTAssertEqual(model.profile.displayUnits, [.year, .week, .day])
        model.toggleUnit(.day)
        XCTAssertEqual(model.profile.displayUnits, [.year, .week])
        XCTAssertEqual(spy.updated.count, 3)
    }

    // MARK: - isUnitToggleDisabled (24.2, mirrors toggleUnit's no-op guard)

    func testOnlyTheLastCheckedUnitIsDisabled() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.day]), now: try fixedNow(), spy: spy)
        XCTAssertTrue(model.isUnitToggleDisabled(.day), "24.2: 只剩天，天 disabled")
        XCTAssertFalse(model.isUnitToggleDisabled(.year), "24.2: 未勾的年不 disabled")
        XCTAssertFalse(model.isUnitToggleDisabled(.month))
        XCTAssertFalse(model.isUnitToggleDisabled(.week))
    }

    func testNoUnitIsDisabledOnceMoreThanOneIsChecked() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(displayUnits: [.year, .day]), now: try fixedNow(), spy: spy)
        XCTAssertFalse(model.isUnitToggleDisabled(.year))
        XCTAssertFalse(model.isUnitToggleDisabled(.day))
    }

    // MARK: - A-5 歲措辭 (11.28–11.31)

    func testAgeWordingDisabledWithoutYear() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        XCTAssertTrue(model.isAgeWordingToggleDisabled)
    }

    func testAgeWordingEnabledOnceYearIsChecked() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.toggleUnit(.year)
        XCTAssertFalse(model.isAgeWordingToggleDisabled)
        XCTAssertFalse(model.profile.useAgeWording)
    }

    func testAgeWordingOnYearOnlyPrintsSui() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(startDate: DateFixture.components(2025, 1, 1),
                                                        displayUnits: [.year]),
                              now: try fixedNow(), spy: spy)
        model.setUseAgeWording(true)
        XCTAssertEqual(model.overlayPreviewText, "1 歲")
    }

    func testUncheckingYearTurnsAgeWordingOffAndDisablesIt() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(startDate: DateFixture.components(2025, 1, 1),
                                                        displayUnits: [.year, .month],
                                                        useAgeWording: true),
                              now: try fixedNow(), spy: spy)
        model.toggleUnit(.year)
        XCTAssertFalse(model.profile.useAgeWording)
        XCTAssertTrue(model.isAgeWordingToggleDisabled)
        XCTAssertFalse(model.overlayPreviewText.contains("歲"))
    }

    func testSetUseAgeWordingNoOpsWithoutYear() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy) // units = [.day]
        model.setUseAgeWording(true)
        XCTAssertFalse(model.profile.useAgeWording)
        XCTAssertTrue(spy.updated.isEmpty)
    }

    // MARK: - A-6 持久化 (11.32–11.33)

    func testEveryMutationForwardsTheUpdatedProfileToUpdateProfile() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setShowName(true)
        model.setShowDate(!model.profile.showDate)
        model.toggleUnit(.week)
        XCTAssertEqual(spy.updated.count, 3)
        XCTAssertEqual(spy.updated.last?.showName, true)
        XCTAssertEqual(spy.updated.last?.showDate, model.profile.showDate)
        XCTAssertEqual(spy.updated.last?.displayUnits, model.profile.displayUnits)
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

    /// 107.3: the last of 天數／日期 refuses to turn off, both ways.
    func testTheLastOfDayCountAndDateRefusesToTurnOff() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        XCTAssertTrue(model.isDayCountTheLastContentSwitch)
        model.setShowDayCount(false)
        XCTAssertTrue(model.profile.showDayCount, "107.3 springs back")
        XCTAssertTrue(spy.updated.isEmpty, "107.3 nothing written")

        model.setShowDate(true)
        model.setShowDayCount(false)
        XCTAssertTrue(model.isDateTheLastContentSwitch)
        model.setShowDate(false)
        XCTAssertTrue(model.profile.showDate, "107.3 the date springs back too")
        XCTAssertFalse(model.profile.showDayCount)
    }

    /// 107.4: with the day count off the unit controls refuse every tap and
    /// keep their ticks; turning it on restores them.
    func testUnitsAreInertWhileTheDayCountIsOff() throws {
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: Spy())
        model.toggleUnit(.year)
        model.toggleUnit(.week)
        model.setShowDate(true)
        model.setShowDayCount(false)
        XCTAssertTrue(model.areUnitsInert, "107.4")
        model.toggleUnit(.month)
        model.toggleUnit(.day)
        model.setUseAgeWording(true)
        XCTAssertEqual(model.profile.displayUnits, [.year, .week, .day], "107.4 taps change nothing")
        XCTAssertFalse(model.profile.useAgeWording, "107.4 age wording refused too")
        model.setShowDayCount(true)
        XCTAssertFalse(model.areUnitsInert)
        model.setUseAgeWording(true)
        XCTAssertTrue(model.profile.useAgeWording, "107.4 live again")
        XCTAssertTrue(model.overlayPreviewText.contains("週"), "107.4 the units are back in use: \(model.overlayPreviewText)")
    }
}
