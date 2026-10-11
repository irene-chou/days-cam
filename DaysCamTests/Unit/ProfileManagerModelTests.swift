import XCTest
@testable import DaysCam

/// TASK-26 acceptance 26.1, 26.3–26.6 (plus the 0.1 TASK-06/13 logic that
/// moved here: selection, creation, deletion, last-profile and 20-profile
/// limits). Uses a real `ProfileStore` over a temporary directory.
@MainActor
final class ProfileManagerModelTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProfileManagerModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ProfileManagerModelTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeStore() throws -> ProfileStore {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults)
        store.load() // seeds "預設"
        return store
    }

    private func makeModel(store: ProfileStore,
                           makeRulesModel: ((CameraProfile) -> RulesTabModel)? = nil) throws -> ProfileManagerModel {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        let calculator = DayCountCalculator(calendar: DateFixture.taipei, now: { now })
        return ProfileManagerModel(store: store, calculator: calculator, makeRulesModel: makeRulesModel)
    }

    @discardableResult
    private func addProfile(_ name: String, to store: ProfileStore, showDayCount: Bool = true) throws -> CameraProfile {
        try store.add(CameraProfile(name: name, startDate: DateFixture.components(2026, 1, 1), showDayCount: showDayCount, showDate: !showDayCount))
    }

    private func fillToLimit(_ store: ProfileStore) throws {
        while store.profiles.count < ProfileManagerModel.profileLimit {
            try addProfile("設定檔 \(store.profiles.count)", to: store)
        }
    }

    // MARK: - 26.1 Subtitle

    func testSubtitleShowsStartDateAndTodaysDayCount() throws {
        let store = try makeStore()
        try addProfile("小寶", to: store)
        try store.add(CameraProfile(name: "第零天", startDate: DateFixture.components(2026, 1, 1),
                                    countingRule: .dayZero))
        let model = try makeModel(store: store)

        XCTAssertEqual(model.rows.map(\.subtitle),
                       ["2026/01/10 起・今天第 1 天", "2026/01/01 起・今天第 10 天", "2026/01/01 起・今天第 9 天"])
    }

    func testSubtitleIgnoresDisplayTogglesAndUnits() throws {
        let store = try makeStore()
        try store.add(CameraProfile(name: "年月", startDate: DateFixture.components(2026, 1, 1),
                                    showDate: true, showName: true, displayUnits: [.year, .month]))
        let model = try makeModel(store: store)

        XCTAssertEqual(model.rows.last?.subtitle, "2026/01/01 起・今天第 10 天")
    }

    /// 107.5: a date-only profile's subtitle says so; the others keep the count.
    func testSubtitleOfADateOnlyProfileSaysDateOnly() throws {
        let store = try makeStore()
        try addProfile("只看日期", to: store, showDayCount: false)
        let model = try makeModel(store: store)

        XCTAssertEqual(model.rows.map(\.subtitle), ["2026/01/10 起・今天第 1 天", "2026/01/01 起・只顯示日期"], "107.5")
    }

    func testCurrentRowIsMarkedAndRowsFollowStoreOrder() throws {
        let store = try makeStore()
        let second = try addProfile("小寶", to: store)
        let model = try makeModel(store: store)

        XCTAssertEqual(model.rows.map(\.name), ["預設", "小寶"])
        XCTAssertEqual(model.rows.filter(\.isCurrent).map(\.id), [second.id])
    }

    // MARK: - 26.3 / 26.4 Limits

    func testDeleteIsDisabledWithOneProfileLeft() throws {
        let model = try makeModel(store: try makeStore())

        XCTAssertFalse(model.canDelete)
        XCTAssertEqual(model.deleteTitle, "刪除（至少保留 1 個）")
        let only = try XCTUnwrap(model.profiles.first)
        model.requestDeletion(of: only.id)
        XCTAssertNil(model.deletionCandidate)
    }

    func testAddAndDuplicateAreDisabledAtTwentyProfiles() throws {
        let store = try makeStore()
        try fillToLimit(store)
        let model = try makeModel(store: store)

        XCTAssertEqual(model.profiles.count, 20)
        XCTAssertFalse(model.canAdd)
        XCTAssertEqual(model.addTitle, "已達 20 個上限")
        XCTAssertFalse(model.canDuplicate)
        XCTAssertEqual(model.duplicateTitle, "複製（已達 20 個）")

        model.addProfile()
        model.duplicate(id: model.profiles[0].id)
        XCTAssertEqual(store.profiles.count, 20)
    }

    func testEnabledTitlesBelowTheLimits() throws {
        let store = try makeStore()
        try addProfile("小寶", to: store)
        let model = try makeModel(store: store)

        XCTAssertEqual(model.addTitle, "新增設定檔")
        XCTAssertEqual(model.duplicateTitle, "複製")
        XCTAssertEqual(model.deleteTitle, "刪除")
    }

    // MARK: - 26.5 Add

    func testAddSelectsTheNewProfileAndPushesItsEditPage() throws {
        let store = try makeStore()
        let model = try makeModel(store: store)

        model.addProfile()

        XCTAssertEqual(store.profiles.map(\.name), ["預設", "新設定檔"])
        XCTAssertEqual(store.selectedProfileID, store.profiles.last?.id)
        XCTAssertEqual(model.selectedProfileID, store.profiles.last?.id)
        XCTAssertEqual(store.profiles.last?.startDate, DateFixture.components(2026, 1, 10))
        XCTAssertEqual(model.path, [store.profiles.last?.id].compactMap { $0 })
        XCTAssertTrue(model.focusesName(of: model.path[0]))
    }

    // MARK: - TASK-106 (#421) new profile: untouched is not kept

    /// 106.1: adding and leaving by the back button (path emptied) with
    /// nothing changed removes the profile and restores the previous one.
    func testUntouchedNewProfileIsDiscardedOnBack() throws {
        let store = try makeStore()
        let model = try makeModel(store: store)
        let original = try XCTUnwrap(store.selectedProfileID)

        model.addProfile()
        XCTAssertEqual(store.profiles.count, 2)
        model.path = []

        XCTAssertEqual(store.profiles.map(\.name), ["預設"], "106.1 nothing left behind")
        XCTAssertEqual(store.selectedProfileID, original, "106.1 back on the original profile")
        XCTAssertEqual(model.selectedProfileID, original)
    }

    /// 106.2: the sheet going away (swipe down / tap outside) does the same.
    func testUntouchedNewProfileIsDiscardedWhenTheSheetDismisses() throws {
        let store = try makeStore()
        let model = try makeModel(store: store)
        let original = try XCTUnwrap(store.selectedProfileID)

        model.addProfile()
        model.sheetDidDismiss()

        XCTAssertEqual(store.profiles.count, 1, "106.2")
        XCTAssertEqual(store.selectedProfileID, original)
        XCTAssertTrue(model.path.isEmpty)
    }

    /// 106.4: a typed name keeps the profile, selected, with the current
    /// profile's style and content settings and today's start date.
    func testNamedNewProfileIsKeptAndInheritsTheCurrentSettings() throws {
        let store = try makeStore()
        var template = store.profiles[0]
        template.showDate = true
        template.showName = true
        template.displayUnits = [.year, .day]
        template.useAgeWording = true
        template.position = .custom(x: 0.2, y: 0.3)
        template.style.textColor = OverlayColor(red8: 0x12, green8: 0x34, blue8: 0x56)
        template.style.sizeScale = 140
        template.countingRule = .dayZero
        try store.update(template)
        let model = try makeModel(store: store)

        model.addProfile()
        let added = try XCTUnwrap(store.profiles.last)
        XCTAssertTrue(model.isUntitledDraft(added.id), "106.3 the name field starts as a placeholder")
        model.rulesModel(for: added).setName("小寶")
        model.path = []

        XCTAssertEqual(store.profiles.map(\.name), ["預設", "小寶"], "106.4 kept")
        XCTAssertEqual(store.selectedProfileID, added.id, "106.4 switched to it")
        let kept = try XCTUnwrap(store.profiles.last)
        XCTAssertEqual(kept.startDate, DateFixture.components(2026, 1, 10), "106.4 start date is today")
        XCTAssertEqual(kept.countingRule, .dayOne, "counting rule is reset, not copied")
        XCTAssertEqual(kept.showDate, true)
        XCTAssertEqual(kept.showName, true)
        XCTAssertEqual(kept.displayUnits, [.year, .day])
        XCTAssertEqual(kept.useAgeWording, true)
        XCTAssertEqual(kept.position, .custom(x: 0.2, y: 0.3))
        XCTAssertEqual(kept.style, template.style, "106.4 same colors, size, font, outline, shadow")
        XCTAssertFalse(model.isUntitledDraft(added.id))
    }

    /// 106.5: only the counting rule changed, no name typed: kept under the
    /// automatic name.
    func testChangedRuleWithoutANameKeepsTheAutomaticName() throws {
        let store = try makeStore()
        let model = try makeModel(store: store)

        model.addProfile()
        let added = try XCTUnwrap(store.profiles.last)
        model.rulesModel(for: added).setCountingRule(.dayZero)
        model.path = []

        XCTAssertEqual(store.profiles.map(\.name), ["預設", "新設定檔"], "106.5")
        XCTAssertEqual(store.profiles.last?.countingRule, .dayZero)
    }

    /// 106.5: the automatic name is numbered when a kept new profile would clash.
    func testChangedStartDateWithoutANameIsNumbered() throws {
        let store = try makeStore()
        try addProfile("新設定檔", to: store)
        let model = try makeModel(store: store)

        model.addProfile()
        let added = try XCTUnwrap(store.profiles.last)
        model.rulesModel(for: added).setStartDate(try XCTUnwrap(DateFixture.date(2025, 12, 1, hour: 8)))
        model.path = []

        XCTAssertEqual(store.profiles.map(\.name), ["預設", "新設定檔", "新設定檔 2"], "106.5")
    }

    /// 106.3: the draft's rules model shows an empty name with the automatic
    /// name as placeholder; leaving it empty does not restore anything (A-5
    /// is for existing profiles); the first typed name turns it into a
    /// normal field.
    func testDraftRulesModelShowsThePlaceholderUntilNamed() throws {
        let store = try makeStore()
        let model = try makeModel(store: store)

        model.addProfile()
        let added = try XCTUnwrap(store.profiles.last)
        let rules = model.rulesModel(for: added)
        XCTAssertEqual(rules.nameDraft, "", "106.3 empty field")
        XCTAssertEqual(rules.namePlaceholder, "新設定檔", "106.3 placeholder")
        rules.endEditingName()
        XCTAssertEqual(rules.nameDraft, "", "106.3 stays empty, no A-5 restore")
        XCTAssertEqual(store.profiles.last?.name, "新設定檔", "the store keeps the automatic name meanwhile")
        rules.setName("小寶")
        XCTAssertEqual(rules.namePlaceholder, "名稱")
        rules.setName("")
        rules.endEditingName()
        XCTAssertEqual(rules.nameDraft, "小寶", "A-5 applies once named")
        XCTAssertEqual(model.rulesModel(for: store.profiles[0]).nameDraft, "預設", "existing profiles are unaffected")
    }

    /// 106.7: the limit still applies; nothing is drafted at twenty.
    func testAddAtTheLimitDraftsNothing() throws {
        let store = try makeStore()
        for index in 1..<ProfileManagerModel.profileLimit { try addProfile("P\(index)", to: store) }
        let model = try makeModel(store: store)
        model.addProfile()
        XCTAssertEqual(store.profiles.count, ProfileManagerModel.profileLimit)
        XCTAssertTrue(model.path.isEmpty)
    }

    func testEditPushesThePageWithoutSwitchingProfiles() throws {
        let store = try makeStore()
        let second = try addProfile("小寶", to: store)
        let model = try makeModel(store: store)
        let current = model.selectedProfileID

        model.edit(id: second.id)

        XCTAssertEqual(model.path, [second.id])
        XCTAssertEqual(model.selectedProfileID, current)
        XCTAssertFalse(model.focusesName(of: second.id))
        model.resetNavigation()
        XCTAssertTrue(model.path.isEmpty)
    }

    func testDeletingFromTheEditPageReturnsToTheList() throws {
        let store = try makeStore()
        let second = try addProfile("小寶", to: store)
        let model = try makeModel(store: store)
        model.edit(id: second.id)

        model.requestDeletion(of: second.id)
        model.confirmDeletion()

        XCTAssertTrue(model.path.isEmpty)
        XCTAssertEqual(store.profiles.count, 1)
    }

    func testEditPageRulesModelWritesThroughTheInjectedWriter() throws {
        let store = try makeStore()
        var written: [CameraProfile] = []
        let model = try makeModel(store: store) { profile in
            RulesTabModel(profile: profile) { written.append($0) }
        }

        model.rulesModel(for: store.profiles[0]).setName("改名")

        XCTAssertEqual(written.map(\.name), ["改名"])
        XCTAssertEqual(store.profiles[0].name, "預設", "must not bypass the injected writer")
    }

    func testAddNumbersDuplicateNames() throws {
        let store = try makeStore()
        let model = try makeModel(store: store)

        model.addProfile()
        model.addProfile()

        XCTAssertEqual(store.profiles.map(\.name), ["預設", "新設定檔", "新設定檔 2"])
    }

    // MARK: - Select / duplicate / move

    func testSelectSwitchesWithoutClosing() throws {
        let store = try makeStore()
        try addProfile("小寶", to: store)
        let model = try makeModel(store: store)
        let first = try XCTUnwrap(model.profiles.first)

        model.select(id: first.id)

        XCTAssertEqual(store.selectedProfileID, first.id)
        XCTAssertEqual(store.lastUsedProfileID, first.id)
        XCTAssertEqual(model.selectedProfileID, first.id)
    }

    func testDuplicateInsertsBelowAndDoesNotSwitch() throws {
        let store = try makeStore()
        try addProfile("小寶", to: store)
        let model = try makeModel(store: store)
        let first = try XCTUnwrap(model.profiles.first)
        store.select(id: first.id)

        model.duplicate(id: first.id)

        XCTAssertEqual(model.rows.map(\.name), ["預設", "預設 副本", "小寶"])
        XCTAssertEqual(model.selectedProfileID, first.id)
    }

    func testMovePersistsTheNewOrder() throws {
        let store = try makeStore()
        try addProfile("小寶", to: store)
        try addProfile("阿公", to: store)
        let model = try makeModel(store: store)

        model.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(model.rows.map(\.name), ["阿公", "預設", "小寶"])
        let reloaded = ProfileStore(directory: directory, calendar: DateFixture.taipei, defaults: defaults)
        XCTAssertEqual(reloaded.load().map(\.name), ["阿公", "預設", "小寶"])
    }

    // MARK: - 26.6 Delete

    func testMoveToInsertionIndexPersistsTheNewOrder() throws {
        let store = try makeStore()
        let second = try addProfile("小寶", to: store)
        try addProfile("阿公", to: store)
        let model = try makeModel(store: store)
        let first = model.profiles[0].id

        model.move(id: first, toIndex: 3) // dropped below the last row
        XCTAssertEqual(store.profiles.map(\.name), ["小寶", "阿公", "預設"])

        model.move(id: second.id, toIndex: 2) // down one slot
        XCTAssertEqual(store.profiles.map(\.name), ["阿公", "小寶", "預設"])
        model.move(id: UUID(), toIndex: 0)
        XCTAssertEqual(store.profiles.count, 3)
    }

    // MARK: - TASK-58 長按拖曳（57.1／57.2／57.6）

    func testDragTargetIndexUsesAHalfRowThresholdAndClamps() {
        let target = { (from: Int, dy: CGFloat) in
            ProfileManagerModel.dragTargetIndex(from: from, translation: dy, rowHeight: 60, count: 4)
        }
        XCTAssertEqual(target(1, 0), 1)
        XCTAssertEqual(target(1, 29), 1, "未過半列")
        XCTAssertEqual(target(1, 30), 2, "過半列")
        XCTAssertEqual(target(1, 125), 3, "兩格")
        XCTAssertEqual(target(1, -31), 0)
        XCTAssertEqual(target(1, 1000), 3, "不超過最後一列")
        XCTAssertEqual(target(1, -1000), 0, "不超過第一列")
        XCTAssertEqual(ProfileManagerModel.dragTargetIndex(from: 2, translation: 500, rowHeight: 0, count: 4), 2, "尚未量到列高")
        XCTAssertEqual(ProfileManagerModel.dragTargetIndex(from: 0, translation: 50, rowHeight: 60, count: 0), 0)
    }

    // MARK: - TASK-76 放手不跳動（76.1／76.2／76.4）

    func testReleaseResidualIsTheFingerOffsetFromTheNewSlot() {
        let residual = { (dy: CGFloat, from: Int, to: Int) in
            ProfileManagerModel.releaseResidual(translation: dy, from: from, to: to, rowHeight: 60)
        }
        XCTAssertEqual(residual(40, 1, 2), -20, "往下 1 格：手指比新槽少 20，列從新槽上方滑回")
        XCTAssertEqual(residual(-100, 3, 2), -40, "往上 1 格")
        XCTAssertEqual(residual(200, 0, 3), 20, "往下 3 格，手指略過頭")
        XCTAssertEqual(residual(-190, 4, 1), -10, "往上 3 格")
        XCTAssertEqual(residual(25, 2, 2), 25, "拖回原位：剩餘位移就是整段位移")
        // Dragged row's on-screen offset before and after the reorder is continuous.
        let (dy, from, to): (CGFloat, Int, Int) = (130, 1, 3)
        XCTAssertEqual(CGFloat(from) * 60 + dy, CGFloat(to) * 60 + residual(dy, from, to))
    }

    func testReleaseInPlaceDoesNotWriteAndReleaseElsewherePersists() throws {
        let store = try makeStore()
        try addProfile("小寶", to: store)
        try addProfile("阿公", to: store)
        let model = try makeModel(store: store)
        let url = directory.appendingPathComponent("profiles.json")
        let before = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        model.move(id: model.profiles[1].id, toFinalIndex: 1) // 76.2: dropped back in place
        XCTAssertEqual(store.profiles.map(\.name), ["預設", "小寶", "阿公"])
        let after = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        XCTAssertEqual(before, after, "原位放手不寫入")

        model.move(id: model.profiles[0].id, toFinalIndex: 2) // 76.4: order survives a restart
        let reloaded = ProfileStore(directory: directory, calendar: DateFixture.taipei, defaults: defaults)
        XCTAssertEqual(reloaded.load().map(\.name), ["小寶", "阿公", "預設"])
    }

    func testMoveToFinalIndexMatchesWhereTheDragShowedTheRow() throws {
        let store = try makeStore()
        try addProfile("小寶", to: store)
        try addProfile("阿公", to: store)
        let model = try makeModel(store: store)
        let first = model.profiles[0].id

        model.move(id: first, toFinalIndex: 2) // 57.1: down two slots
        XCTAssertEqual(store.profiles.map(\.name), ["小寶", "阿公", "預設"])
        model.move(id: first, toFinalIndex: 0) // 57.2: back to the top
        XCTAssertEqual(store.profiles.map(\.name), ["預設", "小寶", "阿公"])
        model.move(id: first, toFinalIndex: 0) // same slot: no change
        XCTAssertEqual(store.profiles.map(\.name), ["預設", "小寶", "阿公"])
    }

    func testDeletingTheCurrentProfileSelectsThePreviousRow() throws {
        let store = try makeStore()
        try addProfile("小寶", to: store)
        let third = try addProfile("阿公", to: store)
        let model = try makeModel(store: store)
        XCTAssertEqual(model.selectedProfileID, third.id)

        model.requestDeletion(of: third.id)
        model.confirmDeletion()

        XCTAssertEqual(model.rows.map(\.name), ["預設", "小寶"])
        XCTAssertEqual(store.selectedProfileID, model.profiles[1].id)
        XCTAssertEqual(model.selectedProfileID, model.profiles[1].id)
        XCTAssertNil(model.lastError)
    }

    func testDeletingTheFirstCurrentProfileSelectsTheNextRow() throws {
        let store = try makeStore()
        try addProfile("小寶", to: store)
        let model = try makeModel(store: store)
        let first = try XCTUnwrap(model.profiles.first)
        store.select(id: first.id)

        model.requestDeletion(of: first.id)
        model.confirmDeletion()

        XCTAssertEqual(model.rows.map(\.name), ["小寶"])
        XCTAssertEqual(store.selectedProfileID, model.profiles.first?.id)
    }

    func testDeletingANonCurrentProfileKeepsTheSelection() throws {
        let store = try makeStore()
        let second = try addProfile("小寶", to: store)
        let model = try makeModel(store: store)
        let first = try XCTUnwrap(model.profiles.first)

        model.requestDeletion(of: first.id)
        model.confirmDeletion()

        XCTAssertEqual(store.selectedProfileID, second.id)
    }

    func testCancelDeletionKeepsTheProfile() throws {
        let store = try makeStore()
        let second = try addProfile("小寶", to: store)
        let model = try makeModel(store: store)

        model.requestDeletion(of: second.id)
        XCTAssertEqual(model.deletionCandidate?.id, second.id)
        model.cancelDeletion()

        XCTAssertNil(model.deletionCandidate)
        XCTAssertEqual(store.profiles.count, 2)
    }

    // MARK: - 26.2 No overlay preview

    func testRowCarriesNoOverlayPreviewField() {
        let labels = Mirror(reflecting: ProfileManagerModel.Row(id: UUID(), name: "", subtitle: "", isCurrent: false)).children.compactMap(\.label)
        XCTAssertEqual(labels, ["id", "name", "subtitle", "isCurrent"])
    }
}
