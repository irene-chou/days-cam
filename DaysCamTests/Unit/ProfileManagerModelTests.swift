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

    private func makeModel(store: ProfileStore, onAdded: @escaping () -> Void = {}) throws -> ProfileManagerModel {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        let calculator = DayCountCalculator(calendar: DateFixture.taipei, now: { now })
        return ProfileManagerModel(store: store, calculator: calculator, onProfileAdded: onAdded)
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

    func testSubtitleShowsStartDateOrDateOnly() throws {
        let store = try makeStore()
        try addProfile("小寶", to: store)
        try addProfile("只看日期", to: store, showDayCount: false)
        let model = try makeModel(store: store)

        XCTAssertEqual(model.rows.map(\.subtitle), ["2026/01/10 起", "2026/01/01 起", "只顯示日期"])
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

    func testAddSelectsTheNewProfileAndReportsIt() throws {
        let store = try makeStore()
        var addedCount = 0
        let model = try makeModel(store: store) { addedCount += 1 }

        model.addProfile()

        XCTAssertEqual(store.profiles.map(\.name), ["預設", "新設定檔"])
        XCTAssertEqual(store.selectedProfileID, store.profiles.last?.id)
        XCTAssertEqual(model.selectedProfileID, store.profiles.last?.id)
        XCTAssertEqual(store.profiles.last?.startDate, DateFixture.components(2026, 1, 10))
        XCTAssertEqual(addedCount, 1)
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
