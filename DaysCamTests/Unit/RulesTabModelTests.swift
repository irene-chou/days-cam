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

    // MARK: - 25.3 起始日上限

    func testStartDateUpperBoundIsToday() throws {
        let spy = Spy()
        let now = try fixedNow()
        let model = makeModel(profile: baselineProfile(), now: now, spy: spy)
        XCTAssertEqual(model.startDateUpperBound, now, "25.3")
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

    // MARK: - 43.2／43.6 天數關閉時欄位照常、另顯示提示（#226 R-9，取代 25.5）

    func testDayCountOffShowsHintAndFieldsStayWritable() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(showDayCount: false), now: try fixedNow(), spy: spy)
        XCTAssertTrue(model.showsDayCountOffHint, "43.6")
        XCTAssertEqual(RulesTabModel.dayCountOffHintMessage, "目前不顯示天數，起始日和起算不會出現在照片上", "43.6")
        model.setStartDate(try XCTUnwrap(DateFixture.date(2026, 1, 2)))
        model.setCountingRule(.dayZero)
        XCTAssertEqual(spy.updated.count, 2, "43.6: 天數關閉時起始日、起算仍可寫入")
        XCTAssertEqual(spy.updated.last?.countingRule, .dayZero)
        XCTAssertFalse(model.overlayPreviewText.contains("天"), "43.2: 預覽句為日期文字")
    }

    func testDayCountOnHidesHint() throws {
        let spy = Spy()
        let model = makeModel(profile: baselineProfile(showDayCount: true), now: try fixedNow(), spy: spy)
        XCTAssertFalse(model.showsDayCountOffHint)
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

    // MARK: - #167 其他畫面對同一設定檔的變更

    func testExternalShowDayCountChangeUpdatesVisibleFields() throws {
        let spy = Spy()
        let profile = baselineProfile()
        let model = makeModel(profile: profile, now: try fixedNow(), spy: spy)
        XCTAssertFalse(model.showsDayCountOffHint)

        var turnedOff = profile
        turnedOff.showDayCount = false
        model.applyExternalChanges(from: turnedOff)
        XCTAssertTrue(model.showsDayCountOffHint, "W.1／W.3")

        model.applyExternalChanges(from: profile)
        XCTAssertFalse(model.showsDayCountOffHint, "W.2／W.3")
        XCTAssertEqual(model.profile.startDate, profile.startDate, "起始日保留原值")
        XCTAssertEqual(model.profile.countingRule, profile.countingRule, "起算保留原值")
        XCTAssertTrue(spy.updated.isEmpty, "同步外部變更不應寫回")
    }

    func testExternalChangeFromAnotherProfileIsIgnored() throws {
        let model = makeModel(profile: baselineProfile(), now: try fixedNow(), spy: Spy())
        let other = CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1), showDayCount: false)
        model.applyExternalChanges(from: other)
        XCTAssertFalse(model.showsDayCountOffHint)
    }

    func testExternalRenameDoesNotClobberAnInProgressNameEdit() throws {
        let model = makeModel(profile: baselineProfile(name: "小寶"), now: try fixedNow(), spy: Spy())
        model.setName("")  // mid-edit: draft differs from the persisted name
        var renamed = model.profile
        renamed.name = "大寶"
        model.applyExternalChanges(from: renamed)
        XCTAssertEqual(model.nameDraft, "", "編輯中不被覆蓋")

        model.endEditingName()
        model.applyExternalChanges(from: renamed)
        XCTAssertEqual(model.nameDraft, "大寶")
    }
}
