import XCTest
@testable import DaysCam

/// Covers `ProfileListModel.adapting(to:)` (TASK-06's `ProfileStore` wiring):
/// that `profiles`/`selectedProfileID` mirror the store, that actions forward
/// through to it, and that `ProfileStore`'s own FR-1.8/FR-1.10 auto-selection
/// is not duplicated by this adapter.
///
/// Every test gets its own temporary directory and `UserDefaults` suite, same
/// as `ProfileStoreTests`, so nothing here touches the real filesystem or the
/// real time.
@MainActor
final class ProfileListModelProfileStoreAdapterTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProfileListModelAdapterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ProfileListModelAdapterTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func fixedNow() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
    }

    private func makeStore(now: Date) -> ProfileStore {
        ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults)
    }

    /// Lets `@Published` sinks (dispatched via `.receive(on: DispatchQueue.main)`)
    /// run before the next assertion.
    private func pumpMainQueue() {
        let expectation = expectation(description: "main queue pumped")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Initial mirroring

    func testAdaptingSnapshotsTheStoresInitialProfilesAndSelection() throws {
        let store = makeStore(now: try fixedNow())
        store.load() // seeds the one default profile (fresh install)

        let model = ProfileListModel.adapting(to: store, calendar: DateFixture.taipei)

        XCTAssertEqual(model.profiles.map(\.name), ["預設"])
        XCTAssertEqual(model.selectedProfileID, store.selectedProfileID)
    }

    // MARK: - Store -> model mirroring

    func testModelReflectsProfilesAddedDirectlyOnTheStore() throws {
        let store = makeStore(now: try fixedNow())
        store.load()
        let model = ProfileListModel.adapting(to: store, calendar: DateFixture.taipei)

        try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        pumpMainQueue()

        XCTAssertEqual(model.profiles.map(\.name), ["預設", "小寶"])
    }

    func testModelReflectsSelectionChangedDirectlyOnTheStore() throws {
        let store = makeStore(now: try fixedNow())
        store.load()
        let second = try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        let first = try XCTUnwrap(store.profiles.first { $0.id != second.id })

        let model = ProfileListModel.adapting(to: store, calendar: DateFixture.taipei)
        store.select(id: first.id)
        pumpMainQueue()

        XCTAssertEqual(model.selectedProfileID, first.id)
    }

    // MARK: - Model -> store forwarding

    func testAddingThroughTheModelPersistsToTheStoreAndAutoSelects() throws {
        let store = makeStore(now: try fixedNow())
        store.load()
        let model = ProfileListModel.adapting(to: store, calendar: DateFixture.taipei)

        model.beginCreatingProfile()
        guard case let .create(draft) = model.presentedEditor else {
            return XCTFail("expected a .create presentation")
        }
        let editModel = try XCTUnwrap(model.editModel(for: .create(draft)))
        editModel.setName("小寶")
        try editModel.save()
        pumpMainQueue()

        // FR-1.10: ProfileStore.add auto-selects; the adapter must not
        // duplicate that, just mirror what the store already did.
        XCTAssertEqual(store.profiles.map(\.name), ["預設", "小寶"])
        XCTAssertEqual(store.selectedProfileID, draft.id)
        XCTAssertEqual(model.selectedProfileID, draft.id)
        XCTAssertNil(model.presentedEditor)
    }

    func testDeletingTheSelectedProfileThroughTheModelReassignsSelectionViaTheStore() throws {
        let store = makeStore(now: try fixedNow())
        store.load()
        let second = try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        store.select(id: second.id)

        let model = ProfileListModel.adapting(to: store, calendar: DateFixture.taipei)
        model.requestDeletion(of: second)
        model.confirmDeletion()
        pumpMainQueue()

        // FR-1.8: deleting the selected profile reassigns selection in the
        // store; the adapter must mirror the reassignment, not compute it.
        XCTAssertEqual(store.profiles.map(\.name), ["預設"])
        XCTAssertFalse(store.profiles.contains { $0.id == second.id })
        XCTAssertEqual(model.selectedProfileID, store.selectedProfileID)
        XCTAssertNil(model.lastError)
    }

    func testSelectingThroughTheModelForwardsToTheStore() throws {
        let store = makeStore(now: try fixedNow())
        store.load()
        let second = try store.add(CameraProfile(name: "小寶", startDate: DateFixture.components(2026, 1, 1)))
        let first = try XCTUnwrap(store.profiles.first { $0.id != second.id })

        let model = ProfileListModel.adapting(to: store, calendar: DateFixture.taipei)
        model.select(id: first.id)

        XCTAssertEqual(store.selectedProfileID, first.id)
        XCTAssertEqual(store.lastUsedProfileID, first.id)
    }

    // MARK: - Errors surface with FR-1.6–FR-1.8 wording

    func testDeletingTheLastProfileSurfacesTheLastProfileMessage() throws {
        let store = makeStore(now: try fixedNow())
        store.load() // exactly one profile
        let only = try XCTUnwrap(store.profiles.first)

        let model = ProfileListModel.adapting(to: store, calendar: DateFixture.taipei)
        // Bypass the view model's own `canDeleteProfiles` guard the way a
        // stale UI state or a race could: assert on the store's own error text
        // via the shared display-message mapping directly.
        do {
            try store.delete(id: only.id)
            XCTFail("expected ProfileStoreError.lastProfile")
        } catch let error as ProfileStoreError {
            XCTAssertEqual(error, .lastProfile)
            XCTAssertEqual(error.displayMessage, "至少需要保留一個設定檔")
        }
        // The model-level guard itself still no-ops as covered by
        // ProfileListModelTests; this test is about the message text.
    }
}
