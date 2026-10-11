import XCTest
@testable import DaysCam

/// Covers `RulesTabModel`'s state transitions (PRD 0.2 FR-13), TASK-25
/// acceptance 25.1–25.6. 25.6's actual on-screen layout is a view-level, B′
/// concern (`RulesTabView`'s `#Preview`); here it only covers the labels'
/// text and order.
///
/// Fixture matches the shared TASKS-0.2 scenario: start date 2026-01-01,
/// `.dayOne`, `DAYSCAM_FAKE_TODAY` fixed at 2026-01-10, so `n = 10`.
@MainActor
final class RulesTabModelTests: XCTestCase {
    private func fixedNow() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
    }

    private func baselineProfile(name: String = "小寶",
                                 startDate: DateComponents = DateFixture.components(2026, 1, 1),
                                 showDayCount: Bool = true,
                                 countingRule: CountingRule = .dayOne) -> CameraProfile {
        CameraProfile(name: name,
                     startDate: startDate,
                     countingRule: countingRule,
                     showDayCount: showDayCount)
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
                           spy: Spy) -> RulesTabModel {
        RulesTabModel(profile: profile,
                     calendar: DateFixture.taipei,
                     calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
                     renderer: TemplateRenderer(),
                     updateProfile: spy.update)
    }

    // MARK: - 25.1 輸入第 21 個字被擋

    func testTypingA21stCharacterIsClampedAt20() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        let twentyOneCharacters = String(repeating: "一", count: 21)

        model.setName(twentyOneCharacters)

        XCTAssertEqual(model.nameDraft.count, 20, "25.1")
        XCTAssertEqual(model.profile.name.count, 20, "25.1")
    }

    // MARK: - 25.2 清空名稱後結束編輯

    func testClearingNameThenEndingEditingRestoresOriginalWithoutPersistingEmpty() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(name: "小寶"), now: try fixedNow(), spy: spy)

        model.setName("")
        XCTAssertEqual(model.nameDraft, "", "25.2: 輸入框本身可以先是空的")
        XCTAssertEqual(model.profile.name, "小寶", "25.2: 但還沒寫入")
        XCTAssertTrue(spy.updated.isEmpty, "25.2: 未寫入空字串")

        model.endEditingName()
        XCTAssertEqual(model.nameDraft, "小寶", "25.2: 還原為原值")
        XCTAssertEqual(model.profile.name, "小寶")
    }

    func testWhitespaceOnlyNameBehavesLikeEmpty() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(name: "小寶"), now: try fixedNow(), spy: spy)

        model.setName("   ")
        XCTAssertTrue(spy.updated.isEmpty)
        model.endEditingName()
        XCTAssertEqual(model.nameDraft, "小寶")
    }

    func testNonEmptyNameWritesThroughImmediately() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(name: "小寶"), now: try fixedNow(), spy: spy)

        model.setName("小明")

        XCTAssertEqual(model.nameDraft, "小明")
        XCTAssertEqual(model.profile.name, "小明")
        XCTAssertEqual(spy.updated.last?.name, "小明")

        // Ending editing afterward is a no-op: already committed.
        model.endEditingName()
        XCTAssertEqual(model.nameDraft, "小明")
        XCTAssertEqual(spy.updated.count, 1)
    }

    func testSetNameNoOpsWhenUnchanged() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(name: "小寶"), now: try fixedNow(), spy: spy)
        model.setName("小寶")
        XCTAssertTrue(spy.updated.isEmpty)
    }

    // MARK: - TASK-94 (#393) a future start date is allowed (replaces 25.3)

    /// 94.1／94.2／94.4: tomorrow and a year out are stored like any other
    /// date, and the preview reads 還有 N 天 (#250) under either rule.
    func testFutureStartDateIsStoredAndPreviewsAsNotStarted() throws {
        for rule in [CountingRule.dayOne, .dayZero] {
            let spy = Spy()
            let model = makeModel(profile: baselineProfile(countingRule: rule), now: try fixedNow(), spy: spy)

            model.setStartDate(try XCTUnwrap(DateFixture.date(2026, 1, 11, hour: 13)))
            XCTAssertEqual(model.profile.startDate, DateFixture.components(2026, 1, 11), "94.1 tomorrow")
            XCTAssertEqual(spy.updated.last?.startDate, DateFixture.components(2026, 1, 11), "94.2 saved")
            XCTAssertEqual(model.overlayPreviewText, "還有 1 天", "94.4 \(rule)")

            model.setStartDate(try XCTUnwrap(DateFixture.date(2027, 1, 10, hour: 9)))
            XCTAssertEqual(spy.updated.last?.startDate, DateFixture.components(2027, 1, 10), "94.2 a year out")
            XCTAssertEqual(model.overlayPreviewText, "還有 365 天", "94.4 \(rule)")
        }
    }

    /// 94.5: back to today or the past, the preview is the ordinal again.
    func testStartDateBackToTodayPreviewsTheOrdinalAgain() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        model.setStartDate(try XCTUnwrap(DateFixture.date(2026, 2, 1)))
        XCTAssertEqual(model.overlayPreviewText, "還有 22 天")
        model.setStartDate(try XCTUnwrap(DateFixture.date(2026, 1, 10)))
        XCTAssertEqual(model.overlayPreviewText, "第 1 天", "94.5")
    }

    func testSetStartDateKeepsOnlyYearMonthDay() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: spy)
        let newDate = try XCTUnwrap(DateFixture.date(2026, 1, 5, hour: 13, minute: 30))

        model.setStartDate(newDate)

        XCTAssertEqual(model.profile.startDate, DateFixture.components(2026, 1, 5))
        XCTAssertEqual(spy.updated.last?.startDate, DateFixture.components(2026, 1, 5))
    }

    // MARK: - 25.4 起算切到「第 0 天」

    func testSwitchingToDayZeroRendersOneFewerDay() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(countingRule: .dayOne), now: try fixedNow(), spy: spy)
        XCTAssertEqual(model.overlayPreviewText, "第 10 天")

        model.setCountingRule(.dayZero)

        XCTAssertEqual(model.profile.countingRule, .dayZero, "25.4")
        XCTAssertEqual(model.overlayPreviewText, "第 9 天", "25.4")
    }

    func testSetCountingRuleNoOpsWhenUnchanged() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(countingRule: .dayOne), now: try fixedNow(), spy: spy)
        model.setCountingRule(.dayOne)
        XCTAssertTrue(spy.updated.isEmpty)
    }

    // MARK: - 43.1／43.1b 預覽句（#227 → TASK-109 改為實際疊字）

    /// 109.2／109.5: the preview is the actual overlay — date, name and the
    /// chosen units — not a days-only count (#227 reversed by TASK-109).
    func testPreviewIsTheActualOverlayText() throws {
        var profile = baselineProfile(showDayCount: true)
        profile.showDate = true
        profile.showName = true
        let model = makeModel(profile: profile, now: try fixedNow(), spy: Spy())
        XCTAssertEqual(model.overlayPreviewText, "2026.01.10 小寶 第 10 天", "109.2")
        profile.displayUnits = [.week, .day]
        let weekly = makeModel(profile: profile, now: try fixedNow(), spy: Spy())
        XCTAssertEqual(weekly.overlayPreviewText, "2026.01.10 小寶 1 週又 3 天", "109.5")
    }

    /// 109.1／109.2: the 寫在照片上 switch is `showName`; turning it on puts
    /// the name into the preview and writes through.
    func testNameOnPhotoSwitchWritesShowNameAndShowsInThePreview() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(name: "寶寶"), now: try fixedNow(), spy: spy)
        XCTAssertFalse(model.profile.showName, "109.1 follows the profile")
        XCTAssertEqual(model.overlayPreviewText, "第 10 天")
        model.setShowName(true)
        XCTAssertEqual(model.overlayPreviewText, "寶寶 第 10 天", "109.2")
        XCTAssertEqual(spy.updated.map(\.showName), [true], "109.3 persisted for the content tab")
        model.setShowName(true)
        XCTAssertEqual(spy.updated.count, 1, "no-op when unchanged")
    }

    /// 109.4: clearing the name and leaving restores it (A-5) and leaves the
    /// switch as it was.
    func testClearingTheNameKeepsTheSwitch() throws {
        let model = makeModel(profile: baselineProfile(name: "寶寶"), now: try fixedNow(), spy: Spy())
        model.setShowName(true)
        model.setName("")
        model.endEditingName()
        XCTAssertEqual(model.nameDraft, "寶寶", "A-5")
        XCTAssertTrue(model.profile.showName, "109.4")
    }

    func testFieldsStayWritableWhateverTheDayCountFlag() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(showDayCount: false), now: try fixedNow(), spy: spy)
        model.setStartDate(try XCTUnwrap(DateFixture.date(2026, 1, 2)))
        model.setCountingRule(.dayZero)
        XCTAssertEqual(spy.updated.count, 2, "43.2／43.6")
        XCTAssertEqual(model.overlayPreviewText, "第 8 天")
    }

    // MARK: - 25.6 起算分段控制的兩個選項文字

    func testCountingRuleLabelsAreBothPresentAndInOrder() {
        XCTAssertEqual(RulesTabModel.countingRuleDayOneLabel, "當天算第 1 天", "25.6")
        XCTAssertEqual(RulesTabModel.countingRuleDayZeroLabel, "第 0 天", "25.6")
        XCTAssertEqual(CountingRule.allCases, [.dayOne, .dayZero], "25.6: 順序 = 標籤順序")
    }

    // MARK: - 失敗回報為 lastError

    func testUpdateProfileFailureIsSurfacedAsLastError() throws {
        struct DummyError: Error {}
        let spy = Spy()
        spy.shouldThrow = DummyError()
        let model = makeModel(profile: baselineProfile(name: "小寶"), now: try fixedNow(), spy: spy)
        model.setName("小明")
        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(model.profile.name, "小明")
    }

    // MARK: - 每次變更都轉發給 updateProfile

    func testEveryPersistedMutationForwardsToUpdateProfile() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(name: "小寶"), now: try fixedNow(), spy: spy)
        model.setName("小明")
        model.setStartDate(try XCTUnwrap(DateFixture.date(2026, 1, 2)))
        model.setCountingRule(.dayZero)
        XCTAssertEqual(spy.updated.count, 3)
        XCTAssertEqual(spy.updated.last?.countingRule, .dayZero)
    }
}
