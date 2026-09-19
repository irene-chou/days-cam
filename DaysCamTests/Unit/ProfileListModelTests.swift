import XCTest
@testable import DaysCam

/// Covers `ProfileListModel`'s state transitions (PRD FR-1.4, FR-1.7,
/// FR-1.8, FR-1.10) without a real `ProfileStore` — the model is driven
/// entirely through injected action closures.
@MainActor
final class ProfileListModelTests: XCTestCase {
    private func fixedNow() throws -> Date {
        try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
    }

    private func profile(name: String) -> CameraProfile {
        CameraProfile(name: name, startDate: DateFixture.components(2026, 1, 1))
    }

    private final class Spy {
        var added: [CameraProfile] = []
        var updated: [CameraProfile] = []
        var deletedIDs: [UUID] = []
        var selectedIDs: [UUID] = []
        var addShouldThrow: Error?
        var deleteShouldThrow: Error?

        func add(_ profile: CameraProfile) throws {
            if let error = addShouldThrow { throw error }
            added.append(profile)
        }

        func update(_ profile: CameraProfile) throws {
            updated.append(profile)
        }

        func delete(id: UUID) throws {
            if let error = deleteShouldThrow { throw error }
            deletedIDs.append(id)
        }

        func select(id: UUID) {
            selectedIDs.append(id)
        }
    }

    private func makeModel(profiles: [CameraProfile],
                           selectedProfileID: UUID? = nil,
                           now: Date,
                           spy: Spy) -> ProfileListModel {
        ProfileListModel(profiles: profiles,
                         selectedProfileID: selectedProfileID,
                         calendar: DateFixture.taipei,
                         calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
                         addProfile: spy.add,
                         updateProfile: spy.update,
                         deleteProfile: spy.delete,
                         selectProfile: spy.select)
    }

    // MARK: - Limit (FR-1.7)

    func testIsAtProfileLimitAtExactlyTwenty() throws {
        let spy = Spy()
        let model = makeModel(profiles: (0..<20).map { profile(name: "P\($0)") }, now: try fixedNow(), spy: spy)
        XCTAssertTrue(model.isAtProfileLimit)
    }

    func testIsNotAtProfileLimitBelowTwenty() throws {
        let spy = Spy()
        let model = makeModel(profiles: (0..<19).map { profile(name: "P\($0)") }, now: try fixedNow(), spy: spy)
        XCTAssertFalse(model.isAtProfileLimit)
    }

    func testBeginCreatingProfileNoOpsAtLimit() throws {
        let spy = Spy()
        let model = makeModel(profiles: (0..<20).map { profile(name: "P\($0)") }, now: try fixedNow(), spy: spy)
        model.beginCreatingProfile()
        XCTAssertNil(model.presentedEditor)
    }

    // MARK: - New profile defaults (FR-1.9)

    func testBeginCreatingProfileDefaultsStartDateToToday() throws {
        let spy = Spy()
        let model = makeModel(profiles: [profile(name: "預設")], now: try fixedNow(), spy: spy)
        model.beginCreatingProfile()
        guard case let .create(draft) = model.presentedEditor else {
            return XCTFail("expected a .create presentation")
        }
        XCTAssertEqual(draft.startDate.year, 2026)
        XCTAssertEqual(draft.startDate.month, 1)
        XCTAssertEqual(draft.startDate.day, 10)
        XCTAssertEqual(draft.name, "")
        XCTAssertTrue(draft.showDayCount)
        XCTAssertFalse(draft.showDate)
        XCTAssertFalse(draft.showName)
        XCTAssertEqual(draft.largestUnit, .day)
        XCTAssertEqual(draft.smallestUnit, .day)
        XCTAssertEqual(draft.position, .bottomTrailing)
        XCTAssertEqual(draft.themeID, .classicWhite)
        XCTAssertEqual(draft.countingRule, .dayOne)
    }

    // MARK: - Auto-switch to a newly created profile (FR-1.10)

    func testSavingANewProfileAddsThenSelectsIt() throws {
        let spy = Spy()
        let model = makeModel(profiles: [profile(name: "預設")], now: try fixedNow(), spy: spy)
        model.beginCreatingProfile()
        guard case let .create(draft) = model.presentedEditor else {
            return XCTFail("expected a .create presentation")
        }
        let editModel = model.makeEditModel(for: .create(draft))
        editModel.setName("小寶")
        try editModel.save()

        XCTAssertEqual(spy.added.map(\.name), ["小寶"])
        XCTAssertEqual(spy.selectedIDs, [draft.id])
        XCTAssertNil(model.presentedEditor)
    }

    func testSavingAnEditedProfileUpdatesButDoesNotSelect() throws {
        let spy = Spy()
        let existing = profile(name: "小寶")
        let model = makeModel(profiles: [existing], now: try fixedNow(), spy: spy)
        let editModel = model.makeEditModel(for: .edit(existing))
        editModel.setName("小寶貝")
        try editModel.save()

        XCTAssertEqual(spy.updated.map(\.name), ["小寶貝"])
        XCTAssertTrue(spy.selectedIDs.isEmpty)
    }

    // MARK: - Deletion (FR-1.3, FR-1.8)

    func testCanDeleteProfilesIsFalseWithOnlyOneLeft() throws {
        let spy = Spy()
        let model = makeModel(profiles: [profile(name: "唯一")], now: try fixedNow(), spy: spy)
        XCTAssertFalse(model.canDeleteProfiles)
    }

    func testRequestDeletionNoOpsWhenOnlyOneProfileRemains() throws {
        let spy = Spy()
        let only = profile(name: "唯一")
        let model = makeModel(profiles: [only], now: try fixedNow(), spy: spy)
        model.requestDeletion(of: only)
        XCTAssertNil(model.deletionCandidate)
    }

    func testConfirmDeletionCallsThroughAndClearsCandidate() throws {
        let spy = Spy()
        let a = profile(name: "A")
        let b = profile(name: "B")
        let model = makeModel(profiles: [a, b], now: try fixedNow(), spy: spy)
        model.requestDeletion(of: a)
        XCTAssertEqual(model.deletionCandidate?.id, a.id)
        model.confirmDeletion()
        XCTAssertEqual(spy.deletedIDs, [a.id])
        XCTAssertNil(model.deletionCandidate)
    }

    func testCancelDeletionClearsCandidateWithoutDeleting() throws {
        let spy = Spy()
        let a = profile(name: "A")
        let b = profile(name: "B")
        let model = makeModel(profiles: [a, b], now: try fixedNow(), spy: spy)
        model.requestDeletion(of: a)
        model.cancelDeletion()
        XCTAssertNil(model.deletionCandidate)
        XCTAssertTrue(spy.deletedIDs.isEmpty)
    }

    func testConfirmDeletionSurfacesThrownErrorAsLastError() throws {
        struct DummyError: Error {}
        let spy = Spy()
        spy.deleteShouldThrow = DummyError()
        let a = profile(name: "A")
        let b = profile(name: "B")
        let model = makeModel(profiles: [a, b], now: try fixedNow(), spy: spy)
        model.requestDeletion(of: a)
        model.confirmDeletion()
        XCTAssertNotNil(model.lastError)
        XCTAssertNil(model.deletionCandidate)
    }
}
