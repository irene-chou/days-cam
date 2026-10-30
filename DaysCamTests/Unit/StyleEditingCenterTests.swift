import Combine
import UIKit
import XCTest
@testable import DaysCam

/// A font library that records what the style editing asks of it and lets a
/// test move font states by hand.
@MainActor
final class FakeShellFontLibrary: FontShellControlling {
    let objectWillChange = ObservableObjectPublisher()
    let weightDownloadDidFinish = PassthroughSubject<FontDownloadID, Never>()
    private var states: [OverlayFontID: FontState]
    /// States of faces other than the default one.
    private var weightStates: [FontDownloadID: FontState] = [:]
    private(set) var preparedWeights: [FontDownloadID] = []
    private(set) var launchPriorityWeights: [String?] = []
    private(set) var downloads: [OverlayFontID] = []
    private(set) var prepared: [OverlayFontID] = []
    private(set) var launchPriorities: [OverlayFontID?] = []
    private(set) var cancelAllCount = 0
    /// How many times anyone asked for a font's state.
    private(set) var stateReadCount = 0

    init(_ states: [OverlayFontID: FontState] = [:]) {
        self.states = states
    }

    func state(for fontID: OverlayFontID) -> FontState {
        stateReadCount += 1
        return fontID == .pingFang ? .available : (states[fontID] ?? .notDownloaded)
    }

    func state(for fontID: OverlayFontID, weightID: String?) -> FontState {
        let unit = FontDownloadID(fontID: fontID, weightID: FontCatalog.entry(for: fontID).weight(for: weightID).id)
        if let state = weightStates[unit] { return state }
        return FontCatalog.entry(for: fontID).defaultWeight.id == unit.weightID ? state(for: fontID) : .notDownloaded
    }

    /// Moves one non-default face to `state`.
    func set(_ state: FontState, for fontID: OverlayFontID, weightID: String) {
        objectWillChange.send()
        weightStates[FontDownloadID(fontID: fontID, weightID: weightID)] = state
    }

    /// Moves `fontID` to `state` the way `FontLibrary` does (announce, then change).
    func set(_ state: FontState, for fontID: OverlayFontID) {
        objectWillChange.send()
        states[fontID] = state
    }

    /// A download completing: `.available`, then `downloadDidFinish`.
    func finishDownload(_ fontID: OverlayFontID) {
        set(.available, for: fontID)
        weightDownloadDidFinish.send(FontDownloadID(fontID: fontID, weightID: FontCatalog.entry(for: fontID).defaultWeight.id))
    }

    /// A non-default face finishing: `.available`, then the event for that exact unit.
    func finishDownload(_ fontID: OverlayFontID, weightID: String) {
        set(.available, for: fontID, weightID: weightID)
        weightDownloadDidFinish.send(FontDownloadID(fontID: fontID, weightID: weightID))
    }

    /// Starts one face's download and leaves it running until the test finishes it.
    func download(_ fontID: OverlayFontID, weightID: String?) -> Bool {
        set(.downloading(progress: 0), for: fontID, weightID: FontCatalog.entry(for: fontID).weight(for: weightID).id)
        return true
    }

    func cancel(_ fontID: OverlayFontID) { set(.notDownloaded, for: fontID) }
    func delete(_ fontID: OverlayFontID) -> Bool { false }

    func download(_ fontID: OverlayFontID) -> Bool {
        downloads.append(fontID)
        set(.downloading(progress: 0), for: fontID)
        return true
    }

    /// Never answers, like a match that hangs.
    func prepare(_ fontID: OverlayFontID) async {
        prepared.append(fontID)
        try? await Task.sleep(nanoseconds: 30_000_000_000)
    }

    func prepare(_ fontID: OverlayFontID, weightID: String?) async {
        preparedWeights.append(FontDownloadID(fontID: fontID, weightID: FontCatalog.entry(for: fontID).weight(for: weightID).id))
        await prepare(fontID)
    }

    func prepareAtLaunch(priority: OverlayFontID?) async {
        launchPriorities.append(priority)
        try? await Task.sleep(nanoseconds: 30_000_000_000)
    }

    func prepareAtLaunch(priority: OverlayFontID?, weightID: String?) async {
        launchPriorityWeights.append(weightID)
        await prepareAtLaunch(priority: priority)
    }

    func cancelAllDownloads() {
        cancelAllCount += 1
        for (fontID, state) in states {
            if case .downloading = state { set(.failed(.other), for: fontID) }
        }
    }
}

/// TASK-35 acceptance 35.4a to 35.9a, 122.1 to 122.4: what `StyleEditingCenter`
/// does with the font library (PRD 0.3 FR-5.15, FR-5.18, FR-16.6, FR-16.11).
/// The camera-only parts (shutter waiting for a font, the viewfinder picture,
/// the re-download notice) left with the camera's overlay (#621).
@MainActor
final class StyleEditingCenterTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("StyleEditingCenterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "StyleEditingCenterTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// What `notify` was asked to say.
    private final class Notifications {
        var messages: [String] = []
    }

    @MainActor
    private struct Harness {
        let center: StyleEditingCenter
        let store: ProfileStore
        let library: FakeShellFontLibrary
        let notifications: Notifications
        let profileA: CameraProfile
        let profileB: CameraProfile

        /// An editor for `profile`; the center holds editors weakly, so the
        /// caller keeps it for as long as its tabs are "on screen".
        func editor(for profile: CameraProfile) throws -> ProfileStyleEditor {
            try XCTUnwrap(center.makeStyleEditor(for: profile.id))
        }
    }

    private func profile(_ name: String, font: OverlayFontID = .pingFang) -> CameraProfile {
        var profile = CameraProfile(name: name, startDate: DateFixture.components(2026, 1, 1))
        profile.style.fontID = font
        return profile
    }

    /// Two profiles, A selected.
    private func makeHarness(fontA: OverlayFontID = .pingFang,
                             fontB: OverlayFontID = .pingFang,
                             states: [OverlayFontID: FontState] = [:]) throws -> Harness {
        let now = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 8))
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { now }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        let profileA = profile("A", font: fontA)
        let profileB = profile("B", font: fontB)
        _ = try store.add(profileA)
        _ = try store.add(profileB)
        store.select(id: profileA.id)
        let library = FakeShellFontLibrary(states)
        let notifications = Notifications()
        let center = StyleEditingCenter(profileStore: store,
                                        fontLibrary: library,
                                        calendar: DateFixture.taipei,
                                        calculator: DayCountCalculator(calendar: DateFixture.taipei, now: { now }),
                                        notify: { notifications.messages.append($0) })
        return Harness(center: center, store: store, library: library, notifications: notifications,
                       profileA: try XCTUnwrap(store.profiles.first { $0.id == profileA.id }),
                       profileB: try XCTUnwrap(store.profiles.first { $0.id == profileB.id }))
    }

    /// Lets main-queue hops (store and library change delivery) run.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func storedFont(_ id: UUID, in store: ProfileStore) -> OverlayFontID? {
        store.profiles.first { $0.id == id }?.style.fontID
    }

    private func storedStyle(_ id: UUID, in store: ProfileStore) -> (OverlayFontID, String)? {
        store.profiles.first { $0.id == id }.map { ($0.style.fontID, $0.style.resolvedFontWeight.id) }
    }

    // MARK: - makeStyleEditor

    func testMakeStyleEditorIsNilForAMissingProfile() throws {
        let harness = try makeHarness()
        XCTAssertNil(harness.center.makeStyleEditor(for: UUID()))
    }

    // MARK: - FR-5.15 launch preparation

    func testLaunchPreparationPutsTheSelectedProfilesFontFirst() async throws {
        let harness = try makeHarness(fontA: .xingkai, states: [.xingkai: .preparing])
        let task = Task { await harness.center.prepareFontsAtLaunch() }
        await settle()
        task.cancel()
        XCTAssertEqual(harness.library.launchPriorities, [.xingkai], "FR-5.15")
    }

    // MARK: - TASK-89 the chosen weight reaches launch preparation

    func testLaunchPreparationNamesTheProfilesWeight() async throws {
        let harness = try makeHarness(fontA: .notoSerifTC, states: [.notoSerifTC: .available])
        var profile = harness.profileA
        profile.style.fontWeight = "black"
        try harness.store.update(profile)

        let task = Task { await harness.center.prepareFontsAtLaunch() }
        for _ in 0..<50 where harness.library.launchPriorityWeights.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        task.cancel()
        XCTAssertEqual(harness.library.launchPriorityWeights, ["black"])
    }

    // MARK: - 35.4a background

    func testGoingToTheBackgroundCancelsAllDownloadsOnce() throws {
        let harness = try makeHarness()
        harness.center.sceneDidEnterBackground()
        XCTAssertEqual(harness.library.cancelAllCount, 1, "35.4a")
    }

    // MARK: - 35.6, 35.7, 35.9, 35.9a applyFont

    func testApplyFontDownloadsThenWritesTheProfileAndNotifiesWhenTheListIsNotShown() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        let editor = try harness.editor(for: harness.profileA)
        editor.styleTabModel.fontList.didTap(.xingkai)
        XCTAssertEqual(harness.library.downloads, [.xingkai], "35.6")
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .pingFang, "35.6: nothing before the download ends")

        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .xingkai, "35.6")
        XCTAssertEqual(editor.styleTabModel.profile.style.fontID, .xingkai, "FR-5.18")
        XCTAssertEqual(harness.notifications.messages, ["已套用「行楷」"], "35.6")
    }

    func testApplyFontAnnouncesInTheOpenListWhenItIsOpen() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        let editor = try harness.editor(for: harness.profileA)
        editor.styleTabModel.fontList.listDidAppear()
        harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(editor.styleTabModel.fontLibraryModel?.toast?.text, "已套用「行楷」")
        XCTAssertTrue(harness.notifications.messages.isEmpty, "the open list shows it, nothing else does")
    }

    func testApplyFontWithNoEditorOnScreenStillWritesAndNotifies() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .xingkai)
        XCTAssertEqual(harness.notifications.messages, ["已套用「行楷」"])
    }

    func testApplyingAnAvailableFontWritesAtOnceWithoutANotice() throws {
        let harness = try makeHarness(states: [.huninn: .available])
        harness.center.applyFont(.huninn, profileID: harness.profileA.id)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .huninn)
        XCTAssertTrue(harness.notifications.messages.isEmpty)
    }

    func testApplyFontWritesTheProfileThatStartedTheDownloadNotTheSelectedOne() async throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.store.select(id: harness.profileB.id)
        await settle()
        harness.library.finishDownload(.xingkai)

        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .xingkai, "35.7")
        XCTAssertEqual(storedFont(harness.profileB.id, in: harness.store), .pingFang, "35.7")
    }

    /// #492: font apply waits for the disk, so a failed save is reported as
    /// such and never as applied.
    func testFailedFileWriteOnFontApplyNotifiesTheFontSaveFailed() async throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        let editor = try harness.editor(for: harness.profileA)
        harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        harness.library.finishDownload(.xingkai)
        await settle()

        XCTAssertEqual(harness.notifications.messages, ["無法儲存字型設定"], "寫入失敗不可報成已套用")
        XCTAssertNil(editor.styleTabModel.fontLibraryModel?.toast?.text)
    }

    // MARK: - TASK-122 (#458): a later font choice is never overwritten by an earlier download

    /// 122.1: A (not downloaded) is tapped, then a usable weight of B: B wins.
    func testUsableWeightOfAnotherFontSupersedesAPendingDownload() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded, .notoSerifTC: .available])
        let editor = try harness.editor(for: harness.profileA)
        harness.library.set(.available, for: .notoSerifTC, weightID: "black")
        harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
        editor.styleTabModel.fontList.didTapWeight("black", of: .notoSerifTC)
        XCTAssertEqual(storedStyle(harness.profileA.id, in: harness.store)?.0, .notoSerifTC)

        harness.library.finishDownload(.xingkai)

        let result = storedStyle(harness.profileA.id, in: harness.store)
        XCTAssertEqual(result?.0, .notoSerifTC, "122.1")
        XCTAssertEqual(result?.1, "black", "122.1")
    }

    /// 122.2: B's weight needs a download too; A finishing first or last never wins.
    func testWeightDownloadOfAnotherFontIsNotOverwrittenByAEitherOrder() throws {
        for aFinishesFirst in [true, false] {
            let harness = try makeHarness(states: [.xingkai: .notDownloaded, .notoSerifTC: .available])
            let editor = try harness.editor(for: harness.profileA)
            harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
            editor.styleTabModel.fontList.didTapWeight("black", of: .notoSerifTC)

            if aFinishesFirst {
                harness.library.finishDownload(.xingkai)
                XCTAssertEqual(storedStyle(harness.profileA.id, in: harness.store)?.0, .pingFang,
                               "122.2 A is not applied over the newer pending choice")
                harness.library.finishDownload(.notoSerifTC, weightID: "black")
            } else {
                harness.library.finishDownload(.notoSerifTC, weightID: "black")
                harness.library.finishDownload(.xingkai)
            }

            let result = storedStyle(harness.profileA.id, in: harness.store)
            XCTAssertEqual(result?.0, .notoSerifTC, "122.2 aFinishesFirst=\(aFinishesFirst)")
            XCTAssertEqual(result?.1, "black", "122.2 aFinishesFirst=\(aFinishesFirst)")
        }
    }

    /// 122.3: nothing newer: A lands as before.
    func testLoneDownloadStillAppliesWhenNothingNewerWasChosen() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(storedStyle(harness.profileA.id, in: harness.store)?.0, .xingkai, "122.3")
    }

    /// 122.4: the other profile's choice leaves this profile's pending alone (A-8).
    func testAnotherProfilesWeightChoiceDoesNotCancelThisProfilesPending() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded, .notoSerifTC: .available])
        let editorB = try harness.editor(for: harness.profileB)
        harness.library.set(.available, for: .notoSerifTC, weightID: "black")
        harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
        editorB.styleTabModel.fontList.didTapWeight("black", of: .notoSerifTC)

        harness.library.finishDownload(.xingkai)

        XCTAssertEqual(storedStyle(harness.profileB.id, in: harness.store)?.0, .notoSerifTC, "122.4")
        XCTAssertEqual(storedStyle(harness.profileA.id, in: harness.store)?.0, .xingkai, "122.4")
    }

    func testDownloadFinishingForADeletedProfileWritesNothing() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        harness.center.applyFont(.xingkai, profileID: harness.profileB.id)
        try harness.store.delete(id: harness.profileB.id)
        harness.library.finishDownload(.xingkai)
        XCTAssertNil(storedFont(harness.profileB.id, in: harness.store), "A-8")
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .pingFang)
    }

    func testApplyingAnAvailableFontClearsTheProfilesPendingDownload() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded, .huninn: .available])
        harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.center.applyFont(.huninn, profileID: harness.profileA.id)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .huninn)

        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .huninn, "35.9")
        XCTAssertTrue(harness.notifications.messages.isEmpty, "35.9: nothing announced")
    }

    func testLastRequestForAProfileWins() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded, .songti: .notDownloaded])
        harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
        harness.center.applyFont(.songti, profileID: harness.profileA.id)
        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .pingFang, "FR-16.6: the replaced request is gone")
        harness.library.finishDownload(.songti)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .songti)
    }

    func testCancelledFailedOrInterruptedDownloadsDropTheirPendingApplication() async throws {
        let interruptions: [(String, (Harness) -> Void)] = [
            ("cancel", { $0.library.cancel(.xingkai) }),
            ("failure", { $0.library.set(.failed(.noNetwork), for: .xingkai) }),
            ("background", { $0.center.sceneDidEnterBackground() })
        ]
        for (name, interrupt) in interruptions {
            let harness = try makeHarness(states: [.xingkai: .notDownloaded])
            harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
            interrupt(harness)
            await settle()
            // Downloaded again later, with no new request for profile A.
            harness.library.finishDownload(.xingkai)
            XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .pingFang, "35.9a \(name)")
            XCTAssertTrue(harness.notifications.messages.isEmpty, "35.9a \(name)")
        }
    }

    /// FR-16.11: the center, not the editor, owns the pending application, so
    /// an editor going away (the export page closing) changes nothing.
    func testPendingApplicationSurvivesTheEditorGoingAway() throws {
        let harness = try makeHarness(states: [.xingkai: .notDownloaded])
        do {
            let editor = try harness.editor(for: harness.profileA)
            editor.styleTabModel.fontList.didTap(.xingkai)
        }
        harness.library.finishDownload(.xingkai)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .xingkai)
        XCTAssertEqual(harness.notifications.messages, ["已套用「行楷」"])
    }

    // MARK: - 35.8 one write path

    func testAppliedFontSurvivesALaterColorEditInTheStyleTab() throws {
        let harness = try makeHarness(states: [.xingkai: .available])
        let editor = try harness.editor(for: harness.profileA)
        harness.center.applyFont(.xingkai, profileID: harness.profileA.id)
        editor.styleTabModel.selectTextColor(OverlayStyle.swatches[2])

        let stored = try XCTUnwrap(harness.store.profiles.first { $0.id == harness.profileA.id })
        XCTAssertEqual(stored.style.fontID, .xingkai, "35.8")
        XCTAssertEqual(stored.style.textColor, OverlayStyle.swatches[2], "35.8")
    }

    func testFontChangeWrittenOutsideTheTabsIsFollowedByTheStyleTabBeforeItsNextEdit() async throws {
        let harness = try makeHarness(fontA: .huninn, states: [.huninn: .available])
        let editor = try harness.editor(for: harness.profileA)
        XCTAssertEqual(editor.styleTabModel.profile.style.fontID, .huninn)

        var changed = try XCTUnwrap(harness.store.profiles.first { $0.id == harness.profileA.id })
        changed.style.fontID = .pingFang
        try harness.store.update(changed)
        await settle()
        editor.styleTabModel.selectTextColor(OverlayStyle.swatches[3])

        let stored = try XCTUnwrap(harness.store.profiles.first { $0.id == harness.profileA.id })
        XCTAssertEqual(stored.style.fontID, .pingFang, "35.8: the old font is not written back")
        XCTAssertEqual(stored.style.textColor, OverlayStyle.swatches[3], "35.8")
    }

    func testStyleTabAndFontListShareTheCentersLibraryAndApplyPath() throws {
        let harness = try makeHarness(states: [.huninn: .available])
        let editor = try harness.editor(for: harness.profileA)
        editor.styleTabModel.fontList.didTap(.huninn)
        XCTAssertEqual(storedFont(harness.profileA.id, in: harness.store), .huninn, "FR-5.18: the grid goes through applyFont")
    }
}
