import Combine
import XCTest
@testable import DaysCam

/// A `FontListControlling` that records what the UI asks of it.
@MainActor
final class FakeFontLibrary: FontListControlling {
    let objectWillChange = ObservableObjectPublisher()
    var states: [OverlayFontID: FontState]
    private(set) var cancelled: [OverlayFontID] = []
    private(set) var deleted: [OverlayFontID] = []
    var deleteResult = true
    /// Called when `delete` runs, to record its order relative to others.
    var onDelete: (() -> Void)?
    /// States of non-default faces; unlisted ones are `.notDownloaded`
    /// (PingFang's are always available).
    var weightStates: [FontDownloadID: FontState] = [:]
    private(set) var weightDownloads: [FontDownloadID] = []
    let weightDownloadDidFinish = PassthroughSubject<FontDownloadID, Never>()

    func state(for fontID: OverlayFontID, weightID: String?) -> FontState {
        let entry = FontCatalog.entry(for: fontID)
        let weight = entry.weight(for: weightID)
        if entry.source == .builtIn || weight.id == entry.defaultWeight.id { return state(for: fontID) }
        return weightStates[FontDownloadID(fontID: fontID, weightID: weight.id)] ?? .notDownloaded
    }

    func download(_ fontID: OverlayFontID, weightID: String?) -> Bool {
        let unit = FontDownloadID(fontID: fontID, weightID: FontCatalog.entry(for: fontID).weight(for: weightID).id)
        weightDownloads.append(unit)
        weightStates[unit] = .downloading(progress: 0)
        return true
    }

    init(_ states: [OverlayFontID: FontState] = [:]) {
        self.states = states
    }

    func state(for fontID: OverlayFontID) -> FontState {
        fontID == .pingFang ? .available : (states[fontID] ?? .notDownloaded)
    }

    func cancel(_ fontID: OverlayFontID) {
        cancelled.append(fontID)
        states[fontID] = .notDownloaded
    }

    func delete(_ fontID: OverlayFontID) -> Bool {
        onDelete?()
        deleted.append(fontID)
        return deleteResult
    }
}

/// TASK-56 acceptance 56.1, 56.4 to 56.13, 56.16: the font list's sections,
/// cell states, taps, messages and delete flow.
@MainActor
final class FontLibraryModelTests: XCTestCase {
    private let profileID = UUID()

    private struct Applied: Equatable {
        let fontID: OverlayFontID
        let profileID: UUID
    }

    private final class Calls {
        var applied: [Applied] = []
    }

    private func makeModel(library: FakeFontLibrary,
                           current: OverlayFontID = .pingFang,
                           profiles: [CameraProfile] = [],
                           calls: Calls = Calls(),
                           visible: Bool = true,
                           entries: [FontCatalogEntry]? = nil) -> FontLibraryModel {
        let model = FontLibraryModel(profileID: profileID,
                                     currentFontID: current,
                                     library: library,
                                     profiles: { profiles },
                                     applyFont: { calls.applied.append(Applied(fontID: $0, profileID: $1)) },
                                     catalogEntries: { entries ?? FontCatalog.entries })
        if visible { model.listDidAppear() }
        return model
    }

    private func cell(_ fontID: OverlayFontID, in model: FontLibraryModel) throws -> FontLibraryModel.Cell {
        try XCTUnwrap(model.sections.flatMap(\.cells).first { $0.fontID == fontID })
    }

    private func section(_ source: FontSource?, in model: FontLibraryModel) -> FontLibraryModel.Section? {
        model.sections.first { $0.source == source }
    }

    private func profile(named name: String, font: OverlayFontID) -> CameraProfile {
        var profile = CameraProfile(name: name, startDate: DateComponents(year: 2026, month: 1, day: 1))
        profile.style.fontID = font
        return profile
    }

    // MARK: - 56.1 分段

    func testDownloadedSectionComesFirstWithoutTitleAndPingFangLeads() {
        let model = makeModel(library: FakeFontLibrary([.xingkai: .available, .huninn: .available]))
        let first = model.sections.first
        XCTAssertNil(first?.source, "56.1: 已下載段沒有小標")
        XCTAssertNil(first?.title, "56.1")
        XCTAssertEqual(first?.cells.map(\.fontID), [.pingFang, .huninn, .xingkai], "56.1: 蘋方第一格，其餘依 allCases 順序")
    }

    /// 120.1: two headings only, 開源字型 then 系統字型, each ordered by type.
    func testNotDownloadedFontsFollowInTwoSourceGroups() throws {
        let model = makeModel(library: FakeFontLibrary())
        XCTAssertEqual(model.sections.dropFirst().compactMap(\.title), ["開源字型", "系統字型"], "120.1")
        XCTAssertEqual(try XCTUnwrap(section(.openSource, in: model)).cells.map(\.fontID),
                       [.huninn, .notoSerifTC, .iansui, .chenyuluoyan], "120.1 粉圓、思源宋體、芫荽、辰宇落雁體")
        let system = try XCTUnwrap(section(.system, in: model)).cells.map(\.fontID)
        let ranks = system.map { FontStyleCategory.allCases.firstIndex(of: FontCatalog.entry(for: $0).category)! }
        XCTAssertEqual(ranks, ranks.sorted(), "120.1 系統字型依 黑→圓→宋→楷→手寫→書法→可愛")
        XCTAssertEqual(Set(ranks).count, FontStyleCategory.allCases.count, "每種類型都有")
        let all = model.sections.flatMap(\.cells).map(\.fontID)
        XCTAssertEqual(Set(all), Set(OverlayFontID.allCases), "56.1: 每款字型恰好出現一次")
        XCTAssertEqual(all.count, OverlayFontID.allCases.count, "56.1")
    }

    /// 120.2: downloaded fonts sort by source, then type.
    func testDownloadedSectionIsOrderedBySourceThenCategory() throws {
        let model = makeModel(library: FakeFontLibrary([.kaiti: .available, .notoSerifTC: .available,
                                                         .huninn: .available, .songti: .available]))
        XCTAssertEqual(model.sections[0].cells.map(\.fontID), [.pingFang, .huninn, .notoSerifTC, .songti, .kaiti], "120.2")
        XCTAssertEqual(model.sections.compactMap(\.title), ["開源字型", "系統字型"])
        XCTAssertEqual(try XCTUnwrap(section(.openSource, in: model)).cells.map(\.fontID), [.iansui, .chenyuluoyan])
    }

    /// 120.5: a font filled in with a source and a category lands by type, not last.
    func testANewFontLandsByItsCategory() throws {
        var entries = FontCatalog.entries
        let index = try XCTUnwrap(entries.firstIndex { $0.fontID == .liSong })
        let real = entries[index]
        // 儷宋 stands in for a new system font whose type is 楷.
        entries[index] = FontCatalogEntry(fontID: real.fontID, displayName: real.displayName, category: .kai,
                                          source: .system, postScriptName: real.postScriptName,
                                          downloadSizeMegabytes: real.downloadSizeMegabytes, openSource: nil)
        let model = makeModel(library: FakeFontLibrary(), entries: entries)
        let system = try XCTUnwrap(section(.system, in: model)).cells.map(\.fontID)
        let kai = Set<OverlayFontID>([.liSong, .kaiti, .biauKai])
        let positions = system.enumerated().filter { kai.contains($0.element) }.map(\.offset)
        XCTAssertEqual(positions, Array(positions[0]...positions[0] + 2), "三個楷體類字型相連")
        XCTAssertEqual(system.firstIndex(of: .songti).map { $0 < positions[0] }, true, "宋在楷前")
        XCTAssertLessThan(positions[2], try XCTUnwrap(system.firstIndex(of: .hanziPen)), "楷在手寫前，不在最後")
    }

    /// 120.3: a group whose fonts are all downloaded loses its heading.
    func testGroupWithEveryFontDownloadedIsHiddenWithItsTitle() {
        let openSource: [OverlayFontID] = FontCatalog.entries.filter { $0.source == .openSource }.map(\.fontID)
        var states: [OverlayFontID: FontState] = [:]
        for fontID in openSource { states[fontID] = .available }
        let model = makeModel(library: FakeFontLibrary(states))
        XCTAssertNil(section(.openSource, in: model), "56.1/56.9: 整段（含小標）隱藏")
        XCTAssertNotNil(section(.system, in: model), "120.3 系統字型照常")
    }

    func testCurrentFontThatIsNotDownloadedStaysInTheDownloadedSectionSelected() throws {
        let model = makeModel(library: FakeFontLibrary([.xingkai: .notDownloaded]), current: .xingkai)
        let cell = try cell(.xingkai, in: model)
        XCTAssertTrue(model.sections[0].cells.contains(cell), "56.13: 在已下載段")
        XCTAssertTrue(cell.isSelected, "56.13")
        XCTAssertEqual(cell.status, .notDownloaded, "56.13: 灰色 ↓")
        XCTAssertFalse(cell.usesRealFont, "56.13")
        XCTAssertNil(section(.system, in: model)?.cells.first { $0.fontID == .xingkai })
    }

    // MARK: - 56.4 到 56.5 格子狀態只有 icon

    func testStatusForEveryState() throws {
        let library = FakeFontLibrary([.songti: .notDownloaded,
                                       .kaiti: .downloading(progress: 0.38),
                                       .hiraginoSans: .preparing,
                                       .xingkai: .failed(.noNetwork),
                                       .huninn: .available])
        let model = makeModel(library: library)
        XCTAssertEqual(try cell(.songti, in: model).status, .notDownloaded, "56.4")
        XCTAssertEqual(try cell(.kaiti, in: model).status, .downloading(progress: 0.38), "56.5")
        XCTAssertEqual(try cell(.hiraginoSans, in: model).status, .preparing)
        XCTAssertEqual(try cell(.xingkai, in: model).status, .failed, "56.10")
        XCTAssertEqual(try cell(.huninn, in: model).status, .none)
        XCTAssertEqual(try cell(.pingFang, in: model).status, .none)
    }

    func testEveryRowUsesFullNameRegardlessOfAvailability() throws {
        for state in [FontState.notDownloaded, .available] {
            let library = FakeFontLibrary(Dictionary(uniqueKeysWithValues: OverlayFontID.allCases.map { ($0, state) }))
            let model = makeModel(library: library)
            for entry in FontCatalog.entries {
                let row = try cell(entry.fontID, in: model)
                // A multi-weight font shows its family name only (TASK-89).
                let expected = entry.weights.count > 1 ? FontLibraryModel.listName(of: entry) : entry.fullName
                XCTAssertEqual(row.name, expected, "78.1")
                XCTAssertTrue(row.accessibilityLabel.hasPrefix(expected), "78.4")
            }
        }
    }

    func testVoiceOverLabelsCarryTheStateButCellsShowNoText() throws {
        let library = FakeFontLibrary([.songti: .notDownloaded, .kaiti: .downloading(progress: 0.38)])
        let model = makeModel(library: library)
        XCTAssertEqual(try cell(.songti, in: model).accessibilityLabel, "宋體-繁，未下載，點兩下下載", "56.14")
        XCTAssertEqual(try cell(.kaiti, in: model).accessibilityLabel, "楷體-繁，下載中，38%", "56.14")
        XCTAssertEqual(try cell(.pingFang, in: model).accessibilityLabel, "蘋方-繁", "56.14")
    }

    // MARK: - 56.5 到 56.6 點擊

    func testTappingNotDownloadedFailedAndAvailableAppliesOnce() {
        for state in [FontState.notDownloaded, .failed(.other), .available] {
            let calls = Calls()
            let model = makeModel(library: FakeFontLibrary([.songti: state]), calls: calls)
            model.didTap(.songti)
            XCTAssertEqual(calls.applied, [Applied(fontID: .songti, profileID: profileID)], "56.5 \(state)")
        }
    }

    func testTappingDownloadingOrPreparingDoesNothingAndNeverCancels() {
        for state in [FontState.downloading(progress: 0.5), .preparing] {
            let calls = Calls()
            let library = FakeFontLibrary([.songti: state])
            let model = makeModel(library: library, calls: calls)
            model.didTap(.songti)
            XCTAssertTrue(calls.applied.isEmpty, "56.6 \(state)")
            XCTAssertTrue(library.cancelled.isEmpty, "56.6: 不取消 \(state)")
        }
    }

    func testSeveralFontsCanBeStartedAtOnce() {
        let calls = Calls()
        let model = makeModel(library: FakeFontLibrary(), calls: calls)
        model.didTap(.songti)
        model.didTap(.kaiti)
        XCTAssertEqual(calls.applied.map(\.fontID), [.songti, .kaiti], "56.6")
    }

    // MARK: - 56.7 剛完成：打勾、留在原位；56.9 重新整理後歸位

    func testFinishedDownloadShowsACheckAndStaysInPlaceUntilTheNextAppearance() throws {
        let library = FakeFontLibrary([.songti: .downloading(progress: 0.9)])
        let model = makeModel(library: library)
        XCTAssertNotNil(section(.system, in: model)?.cells.first { $0.fontID == .songti })

        library.states[.songti] = .available
        model.update(profileID: profileID, currentFontID: .songti)   // auto-applied
        model.libraryDidChange()

        let finished = try cell(.songti, in: model)
        XCTAssertEqual(finished.status, .justCompleted, "56.7")
        XCTAssertTrue(finished.usesRealFont, "56.7")
        XCTAssertTrue(finished.isSelected, "56.7")
        XCTAssertNotNil(section(.system, in: model)?.cells.first { $0.fontID == .songti }, "56.7: 留在原位")
        XCTAssertFalse(model.sections[0].cells.contains { $0.fontID == .songti })

        model.expireCompletionCheck(of: .songti)
        XCTAssertEqual(try cell(.songti, in: model).status, .none, "56.7: 勾消失後轉為已下載樣式")
        XCTAssertNotNil(section(.system, in: model)?.cells.first { $0.fontID == .songti }, "56.7: 仍在原位")

        model.listDidAppear()
        XCTAssertTrue(model.sections[0].cells.contains { $0.fontID == .songti }, "56.9: 重新出現後歸入已下載段")
    }

    func testDownloadThatGoesThroughPreparingAlsoShowsTheCheck() throws {
        let library = FakeFontLibrary([.huninn: .downloading(progress: 1)])
        let model = makeModel(library: library)
        library.states[.huninn] = .preparing
        model.libraryDidChange()
        XCTAssertEqual(try cell(.huninn, in: model).status, .preparing)
        library.states[.huninn] = .available
        model.libraryDidChange()
        XCTAssertEqual(try cell(.huninn, in: model).status, .justCompleted, "56.7")
    }

    func testPreparingAtLaunchDoesNotShowTheCheck() throws {
        let library = FakeFontLibrary([.huninn: .preparing])
        let model = makeModel(library: library)
        library.states[.huninn] = .available
        model.libraryDidChange()
        XCTAssertEqual(try cell(.huninn, in: model).status, .none, "只有使用者啟動的下載才打勾")
    }

    func testFinishedDownloadThatWasNotAutoAppliedStaysUnselected() throws {
        let library = FakeFontLibrary([.songti: .downloading(progress: 0.9)])
        let model = makeModel(library: library, current: .huninn)
        library.states[.songti] = .available
        model.libraryDidChange()
        XCTAssertFalse(try cell(.songti, in: model).isSelected, "56.8")
    }

    // MARK: - 56.10 失敗

    func testFailureMessages() {
        XCTAssertEqual(FontStateText.offlineMessage, "沒有網路，連上後再點一次")
        XCTAssertEqual(FontStateText.failedMessage(name: "宋體"), "「宋體」下載失敗，點一下重試")
    }

    func testDownloadFailureIsAnnouncedOnlyOnce() {
        let library = FakeFontLibrary([.songti: .downloading(progress: 0.5)])
        let model = makeModel(library: library)
        library.states[.songti] = .failed(.noNetwork)
        model.libraryDidChange()
        XCTAssertEqual(model.toast?.text, FontStateText.offlineMessage, "56.10")
        let first = model.toast
        model.libraryDidChange()
        XCTAssertEqual(model.toast, first, "同一次失敗不重複通知")
        library.states[.songti] = .notDownloaded
        model.libraryDidChange()
        library.states[.songti] = .failed(.other)
        model.libraryDidChange()
        XCTAssertEqual(model.toast?.text, FontStateText.failedMessage(name: "宋體"))
    }

    func testPreparingThatFailsAtLaunchIsNotAnnounced() {
        let library = FakeFontLibrary([.songti: .preparing])
        let model = makeModel(library: library)
        library.states[.songti] = .failed(.other)
        model.libraryDidChange()
        XCTAssertNil(model.toast)
    }

    // MARK: - 56.11 到 56.13 刪除

    func testOnlyDownloadedOpenSourceFontsCanBeDeleted() throws {
        let library = FakeFontLibrary([.huninn: .available, .songti: .available])
        let model = makeModel(library: library)
        XCTAssertTrue(try cell(.huninn, in: model).canDelete, "56.11")
        XCTAssertFalse(try cell(.pingFang, in: model).canDelete, "56.12")
        XCTAssertFalse(try cell(.songti, in: model).canDelete, "系統字型不能刪")
        XCTAssertFalse(try cell(.iansui, in: model).canDelete, "未下載不能刪")
        model.requestDeletion(of: .pingFang)
        model.requestDeletion(of: .songti)
        model.requestDeletion(of: .iansui)
        XCTAssertNil(model.deletePrompt, "56.12")
    }

    func testDeletePromptNamesTheSizeAndWhoUsesTheFont() throws {
        let library = FakeFontLibrary([.huninn: .available])
        let one = makeModel(library: library, profiles: [profile(named: "小寶", font: .huninn)])
        one.requestDeletion(of: .huninn)
        XCTAssertEqual(one.deletePrompt?.title, "粉圓　4.9 MB", "56.11")
        XCTAssertEqual(one.deletePrompt?.usage, "「小寶」正在使用，刪除後暫以蘋方顯示", "56.11")

        let none = makeModel(library: library)
        none.requestDeletion(of: .huninn)
        XCTAssertEqual(none.deletePrompt?.usage, "沒有設定檔在用這套字型")

        let many = makeModel(library: library, profiles: [profile(named: "A", font: .huninn),
                                                          profile(named: "B", font: .huninn)])
        many.requestDeletion(of: .huninn)
        XCTAssertEqual(many.deletePrompt?.usage, "「A」等 2 個設定檔正在使用，刪除後暫以蘋方顯示")
    }

    func testConfirmingDeletesAndMovesTheCellBackToItsCategory() throws {
        let library = FakeFontLibrary([.huninn: .available])
        let model = makeModel(library: library)
        XCTAssertTrue(model.sections[0].cells.contains { $0.fontID == .huninn })
        model.requestDeletion(of: .huninn)
        library.onDelete = { library.states[.huninn] = .notDownloaded }
        model.confirmDeletion()

        XCTAssertEqual(library.deleted, [.huninn], "56.11")
        XCTAssertNil(model.deletePrompt)
        XCTAssertEqual(model.toast?.text, "已刪除「粉圓」，釋放 4.9 MB", "56.11")
        XCTAssertNotNil(section(.openSource, in: model)?.cells.first { $0.fontID == .huninn }, "56.11: 回到所屬分類")
        XCTAssertEqual(try cell(.huninn, in: model).status, .notDownloaded, "56.11: 灰色 ↓")
    }

    func testDeletingTheCurrentFontKeepsItSelectedInTheDownloadedSection() throws {
        let library = FakeFontLibrary([.huninn: .available])
        let model = makeModel(library: library, current: .huninn)
        model.requestDeletion(of: .huninn)
        library.onDelete = { library.states[.huninn] = .notDownloaded }
        model.confirmDeletion()

        let cell = try cell(.huninn, in: model)
        XCTAssertTrue(model.sections[0].cells.contains(cell), "56.13: 仍在已下載段")
        XCTAssertTrue(cell.isSelected, "56.13: 選中")
        XCTAssertEqual(cell.status, .notDownloaded, "56.13: 灰色 ↓")
    }

    func testDeleteFailureIsReportedNotShownAsDeleted() {
        let library = FakeFontLibrary([.huninn: .available])
        library.deleteResult = false
        let model = makeModel(library: library)
        model.requestDeletion(of: .huninn)
        model.confirmDeletion()
        XCTAssertEqual(model.toast?.text, FontLibraryModel.deleteFailedMessage)
        XCTAssertTrue(model.sections[0].cells.contains { $0.fontID == .huninn }, "刪除失敗格子不動")
    }

    func testCancellingThePromptDeletesNothing() {
        let library = FakeFontLibrary([.huninn: .available])
        let model = makeModel(library: library)
        model.requestDeletion(of: .huninn)
        model.cancelDeletion()
        XCTAssertNil(model.deletePrompt)
        XCTAssertTrue(library.deleted.isEmpty)
    }

    // MARK: - 跟隨設定檔、訊息、重新發布

    func testSelectionFollowsTheProfile() throws {
        let model = makeModel(library: FakeFontLibrary())
        model.update(profileID: profileID, currentFontID: .iansui)
        XCTAssertEqual(model.currentFontID, .iansui)
        XCTAssertTrue(try cell(.iansui, in: model).isSelected)
    }

    func testVisibilityGatesWhereAnAppliedMessageGoes() {
        let model = makeModel(library: FakeFontLibrary(), visible: false)
        XCTAssertFalse(model.isVisible)
        model.listDidAppear()
        XCTAssertTrue(model.isVisible)
        model.listDidDisappear()
        XCTAssertFalse(model.isVisible)
    }

    func testLibraryChangesAreIgnoredWhileTheListIsOffScreen() {
        let library = FakeFontLibrary([.songti: .downloading(progress: 0.5)])
        let model = makeModel(library: library, visible: false)
        library.states[.songti] = .failed(.noNetwork)
        model.libraryDidChange()
        XCTAssertNil(model.toast, "面板關著不讀字型狀態、不發通知")
    }

    func testListRepublishesWhenTheLibraryChanges() {
        let library = FakeFontLibrary()
        let model = makeModel(library: library)
        var fired = 0
        let cancellable = model.objectWillChange.sink { fired += 1 }
        library.objectWillChange.send()
        XCTAssertGreaterThan(fired, 0)
        cancellable.cancel()
    }

    // MARK: - TASK-112 (#437) the selected multi-weight font collapses

    /// 112.1: the selected multi-weight font starts collapsed, showing its
    /// current weight; the buttons exist but are not expanded.
    func testSelectedMultiWeightFontStartsCollapsed() throws {
        let model = makeModel(library: FakeFontLibrary())
        let cell = try cell(.pingFang, in: model)
        XCTAssertTrue(cell.canExpand, "112.1 can expand")
        XCTAssertFalse(cell.isExpanded, "112.1 collapsed by default")
        XCTAssertFalse((model.expandedFontID != nil))
        XCTAssertEqual(cell.currentWeightName, "粗", "112.1 the stored weight")
        XCTAssertNil(cell.pendingWeightStatus)
        XCTAssertEqual(cell.accessibilityLabel, "蘋方-繁", "112.9 label is the name")
        XCTAssertEqual(cell.accessibilityValue, "粗", "112.9 value is the weight")
        XCTAssertEqual(cell.accessibilityHint, "點兩下展開字重", "112.9")
    }

    /// 112.2: tapping the selected row toggles, never re-applies.
    func testTappingTheSelectedRowTogglesWithoutApplying() throws {
        let calls = Calls()
        let model = makeModel(library: FakeFontLibrary(), calls: calls)
        model.didTap(.pingFang)
        XCTAssertTrue((model.expandedFontID != nil), "112.2 expanded")
        XCTAssertTrue(try cell(.pingFang, in: model).isExpanded)
        XCTAssertEqual(try cell(.pingFang, in: model).accessibilityHint, "點兩下收合字重", "112.9")
        model.didTap(.pingFang)
        XCTAssertFalse((model.expandedFontID != nil), "112.2 collapsed again")
        XCTAssertTrue(calls.applied.isEmpty, "112.2 no applyFont")
    }

    /// 112.4: tapping another font applies it and shows it collapsed.
    func testTappingAnotherFontAppliesAndStaysCollapsed() throws {
        let calls = Calls()
        let model = makeModel(library: FakeFontLibrary([.songti: .available]), calls: calls)
        model.didTap(.pingFang)
        XCTAssertTrue((model.expandedFontID != nil))
        model.didTap(.songti)
        XCTAssertEqual(calls.applied.map(\.fontID), [.songti], "112.4 applied")
        XCTAssertFalse((model.expandedFontID != nil), "112.4 collapsed")
        model.update(profileID: profileID, currentFontID: .songti, currentWeightID: nil)
        XCTAssertFalse((model.expandedFontID != nil), "112.4 still collapsed once selected")
        XCTAssertTrue(try cell(.songti, in: model).canExpand)
        XCTAssertFalse(try cell(.songti, in: model).isExpanded)
    }

    /// 112.4／112.5: a font change from outside and every appearance reset
    /// the expansion.
    func testFontChangeAndAppearanceCollapse() throws {
        let model = makeModel(library: FakeFontLibrary([.songti: .available]))
        model.didTap(.pingFang)
        XCTAssertTrue((model.expandedFontID != nil))
        model.update(profileID: profileID, currentFontID: .songti, currentWeightID: nil)
        XCTAssertFalse((model.expandedFontID != nil), "112.4 reset on font change")
        model.didTap(.songti)
        XCTAssertTrue((model.expandedFontID != nil))
        model.listDidDisappear()
        model.listDidAppear()
        XCTAssertFalse((model.expandedFontID != nil), "112.5 reset on appearance")
    }

    /// 112.7: a single-weight font keeps the old tap behaviour and never expands.
    func testSingleWeightFontDoesNotToggle() throws {
        let calls = Calls()
        let model = makeModel(library: FakeFontLibrary([.huninn: .available]), current: .huninn, calls: calls)
        model.didTap(.huninn)
        XCTAssertFalse((model.expandedFontID != nil), "112.7")
        XCTAssertEqual(calls.applied.map(\.fontID), [.huninn], "112.7 applied as before")
        let cell = try cell(.huninn, in: model)
        XCTAssertFalse(cell.canExpand)
        XCTAssertNil(cell.currentWeightName)
        XCTAssertNil(cell.accessibilityHint)
    }
}

/// TASK-89 acceptance 89.3 to 89.5 and 89.7 at the font list: the expanded
/// card, weight taps, pending downloads.
@MainActor
final class FontWeightListTests: XCTestCase {
    private let profileID = UUID()

    private final class Calls {
        var weights: [String] = []
        var fonts: [OverlayFontID] = []
        /// `applyFontWithWeight` calls (TASK-115).
        var fontWeights: [FontDownloadID] = []
        var fontWeightResult = true
    }

    private func makeModel(library: FakeFontLibrary, current: OverlayFontID = .notoSerifTC,
                           weight: String? = nil, calls: Calls = Calls()) -> FontLibraryModel {
        let model = FontLibraryModel(profileID: profileID,
                                     currentFontID: current,
                                     currentWeightID: weight,
                                     library: library,
                                     profiles: { [] },
                                     applyFont: { id, _ in calls.fonts.append(id) },
                                     applyWeight: { _, weightID in calls.weights.append(weightID); return true },
                                     applyFontWithWeight: { fontID, weightID in
                                         calls.fontWeights.append(FontDownloadID(fontID: fontID, weightID: weightID))
                                         return calls.fontWeightResult
                                     })
        model.listDidAppear()
        return model
    }

    private func cell(_ fontID: OverlayFontID, in model: FontLibraryModel) throws -> FontLibraryModel.Cell {
        try XCTUnwrap(model.sections.flatMap(\.cells).first { $0.fontID == fontID })
    }

    private func noto(_ weightID: String) -> FontDownloadID {
        FontDownloadID(fontID: .notoSerifTC, weightID: weightID)
    }

    func testOnlyTheSelectedMultiWeightFontExpands() throws {
        let library = FakeFontLibrary([.notoSerifTC: .available, .songti: .available, .huninn: .available])
        let model = makeModel(library: library)
        let selected = try cell(.notoSerifTC, in: model)
        XCTAssertEqual(selected.weights.map(\.name), ["標準", "粗", "特粗"], "89.7")
        XCTAssertEqual(selected.weights.map(\.isSelected), [false, true, false], "89.7 預設字重為粗")
        let songti = try cell(.songti, in: model)
        XCTAssertTrue(songti.weights.isEmpty, "89.7 只有選中的一列有字重")
        XCTAssertTrue(try cell(.hiraginoSans, in: model).weights.isEmpty, "89.7")
        XCTAssertEqual(songti.weightCount, 3, "111.2 收合列不再顯示「N 種字重」，字重數只留給展開後的按鈕")
    }

    func testMultiWeightRowsShowOnlyTheFamilyName() throws {
        let model = makeModel(library: FakeFontLibrary([.notoSerifTC: .available]))
        let expected: [OverlayFontID: String] = [
            .pingFang: "蘋方-繁", .notoSerifTC: "Noto Serif TC", .hiraginoSans: "冬青黑體繁體中文",
            .songti: "宋體-繁", .kaiti: "楷體-繁", .yuanti: "圓體-繁", .hannotate: "手札體-繁",
        ]
        for (fontID, name) in expected {
            XCTAssertEqual(try cell(fontID, in: model).name, name, "展開與收合都不帶字重字樣")
        }
        XCTAssertEqual(expected.count, FontCatalog.entries.filter { $0.weights.count > 1 }.count, "名單涵蓋所有多字重字型")
        XCTAssertEqual(try cell(.huninn, in: model).name, "jf open 粉圓", "單一字重維持 fullName；111.2 不含版本號")
        XCTAssertEqual(try cell(.chenyuluoyan, in: model).name, "辰宇落雁體 2.0 細體")
        XCTAssertEqual(try cell(.notoSerifTC, in: model).accessibilityLabel, "Noto Serif TC")
    }

    func testSingleWeightSelectedFontDoesNotExpand() throws {
        let model = makeModel(library: FakeFontLibrary([.huninn: .available]), current: .huninn)
        XCTAssertTrue(try cell(.huninn, in: model).weights.isEmpty, "89.7")
        let chenyu = makeModel(library: FakeFontLibrary([.chenyuluoyan: .available]), current: .chenyuluoyan)
        XCTAssertTrue(try cell(.chenyuluoyan, in: chenyu).weights.isEmpty, "89.7")
    }

    func testSelectedWeightFollowsTheProfile() throws {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let model = makeModel(library: library, weight: "black")
        XCTAssertEqual(try cell(.notoSerifTC, in: model).weights.map(\.isSelected), [false, false, true], "89.3")
        XCTAssertEqual(try cell(.notoSerifTC, in: model).nameWeightID, "black")
        model.update(profileID: profileID, currentFontID: .notoSerifTC, currentWeightID: "regular")
        XCTAssertEqual(try cell(.notoSerifTC, in: model).weights.map(\.isSelected), [true, false, false])
    }

    func testBuiltInWeightsAreAllUsable() throws {
        let model = makeModel(library: FakeFontLibrary(), current: .pingFang)
        let weights = try cell(.pingFang, in: model).weights
        XCTAssertEqual(weights.map(\.name), ["細", "標準", "粗"])
        XCTAssertTrue(weights.allSatisfy { $0.status == .none }, "內建字重不需下載")
    }

    func testTappingAnAvailableWeightAppliesAtOnce() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        library.weightStates[noto("regular")] = .available
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapWeight("regular")
        XCTAssertEqual(calls.weights, ["regular"], "89.3")
        XCTAssertTrue(library.weightDownloads.isEmpty)
        XCTAssertNil(model.pendingWeight)
    }

    func testTappingAMissingWeightKeepsTheOldOneUntilItFinishes() throws {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        XCTAssertEqual(try cell(.notoSerifTC, in: model).weights[2].status, .notDownloaded, "89.5 顯示下載圖示")
        model.didTapWeight("black")
        XCTAssertEqual(library.weightDownloads, [noto("black")], "89.5 先下載")
        XCTAssertTrue(calls.weights.isEmpty, "89.5 下載中不套用，保留舊字重")
        XCTAssertEqual(model.pendingWeight, noto("black"))
        XCTAssertEqual(try cell(.notoSerifTC, in: model).weights[2].status, .downloading(progress: 0), "89.5")
        XCTAssertEqual(try cell(.notoSerifTC, in: model).weights.map(\.isSelected), [false, true, false])

        library.weightStates[noto("black")] = .available
        library.weightDownloadDidFinish.send(noto("black"))
        XCTAssertEqual(calls.weights, ["black"], "89.5 完成後才套用")
        XCTAssertNil(model.pendingWeight)
        XCTAssertEqual(model.toast?.text, "已套用「思源宋體　特粗」")
    }

    func testAnotherWeightFinishingDoesNotApplyThePendingOne() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapWeight("black")
        library.weightDownloadDidFinish.send(noto("regular"))
        library.weightDownloadDidFinish.send(FontDownloadID(fontID: .songti, weightID: "black"))
        XCTAssertTrue(calls.weights.isEmpty, "89.5 只收符合 pending 的完成事件")
        XCTAssertEqual(model.pendingWeight, noto("black"))
    }

    func testFailedDownloadKeepsTheOldWeightAndSaysSo() throws {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapWeight("black")
        library.weightStates[noto("black")] = .failed(.other)
        model.libraryDidChange()
        XCTAssertTrue(calls.weights.isEmpty, "89.5 失敗不套用")
        XCTAssertNil(model.pendingWeight)
        XCTAssertEqual(model.toast?.text, FontStateText.failedMessage(name: "思源宋體　特粗"), "89.5 顯示失敗")
        let button = try cell(.notoSerifTC, in: model).weights[2]
        XCTAssertEqual(button.status, .failed)
        XCTAssertEqual(try cell(.notoSerifTC, in: model).weights.map(\.isSelected), [false, true, false], "89.5 保留原字重")
        // A late finish for the dropped request must not apply.
        library.weightDownloadDidFinish.send(noto("black"))
        XCTAssertTrue(calls.weights.isEmpty)
    }

    func testOfflineFailureUsesTheOfflineMessage() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let model = makeModel(library: library)
        model.didTapWeight("regular")
        library.weightStates[noto("regular")] = .failed(.noNetwork)
        model.libraryDidChange()
        XCTAssertEqual(model.toast?.text, FontStateText.offlineMessage, "89.5")
    }

    func testFailureReadsOnlyTheRequestedFace() {
        // The default face failing must not be taken for the pending face failing.
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapWeight("black")
        library.states[.notoSerifTC] = .failed(.other)
        model.libraryDidChange()
        XCTAssertEqual(model.pendingWeight, noto("black"), "89.5 只讀該 unit 的狀態")
    }

    func testRetryAfterFailureDownloadsAgain() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        library.weightStates[noto("black")] = .failed(.other)
        let model = makeModel(library: library)
        model.didTapWeight("black")
        XCTAssertEqual(library.weightDownloads, [noto("black")])
        XCTAssertEqual(model.pendingWeight, noto("black"))
    }

    func testChangingFontOrProfileDropsThePendingWeight() {
        let library = FakeFontLibrary([.notoSerifTC: .available, .songti: .available])
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapWeight("black")
        model.update(profileID: profileID, currentFontID: .songti, currentWeightID: nil)
        XCTAssertNil(model.pendingWeight, "換字型後不再套用舊請求")
        library.weightDownloadDidFinish.send(noto("black"))
        XCTAssertTrue(calls.weights.isEmpty)
    }

    func testTappingAnotherFontAtOnceDropsThePendingWeight() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapWeight("black")
        // The new font is still downloading, so the current font has not changed yet.
        model.didTap(.songti)
        XCTAssertEqual(calls.fonts, [.songti])
        XCTAssertNil(model.pendingWeight, "點別的字型立即清除 pending")
        library.weightStates[noto("black")] = .available
        library.weightDownloadDidFinish.send(noto("black"))
        XCTAssertTrue(calls.weights.isEmpty, "較舊的字重請求不得在較新的選擇之後套用")
        XCTAssertNil(model.toast)
    }

    func testTappingTheCurrentFontKeepsThePendingWeight() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let model = makeModel(library: library)
        model.didTapWeight("black")
        model.didTap(.notoSerifTC)
        XCTAssertEqual(model.pendingWeight, noto("black"))
    }

    func testPickingAnAvailableWeightDropsAPendingOne() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        library.weightStates[noto("regular")] = .available
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapWeight("black")
        model.didTapWeight("regular")
        library.weightDownloadDidFinish.send(noto("black"))
        XCTAssertEqual(calls.weights, ["regular"], "後點的字重取代先前的 pending")
    }

    func testWeightTapsAreIgnoredForSingleWeightFonts() {
        let library = FakeFontLibrary([.huninn: .available])
        let calls = Calls()
        let model = makeModel(library: library, current: .huninn, calls: calls)
        model.didTapWeight("regular")
        XCTAssertTrue(calls.weights.isEmpty)
        XCTAssertTrue(library.weightDownloads.isEmpty)
    }

    func testFamilyIsDeletableWhenOnlyANonDefaultWeightIsDownloaded() throws {
        // The default face is gone, a sibling is on the device.
        let library = FakeFontLibrary([.notoSerifTC: .notDownloaded])
        library.weightStates[noto("regular")] = .available
        let model = makeModel(library: library, current: .pingFang)
        XCTAssertTrue(try cell(.notoSerifTC, in: model).canDelete, "任一字重可用即可刪整套")
        model.requestDeletion(of: .notoSerifTC)
        XCTAssertNotNil(model.deletePrompt)
        let none = makeModel(library: FakeFontLibrary(), current: .pingFang)
        XCTAssertFalse(try cell(.notoSerifTC, in: none).canDelete)
        XCTAssertFalse(try cell(.pingFang, in: none).canDelete, "內建字型不能刪")
    }

    func testAPendingWeightThatSettlesWithoutADownloadEventIsApplied() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        library.weightStates[noto("black")] = .preparing
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapWeight("black")
        XCTAssertEqual(model.pendingWeight, noto("black"))
        library.weightStates[noto("black")] = .available
        model.libraryDidChange()
        XCTAssertEqual(calls.weights, ["black"], ".preparing 完成後也要套用")
        XCTAssertNil(model.pendingWeight)
    }

    func testPendingWeightFinishedWhileListWasOffScreenIsAppliedOnReturn() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        library.weightStates[noto("black")] = .preparing
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapWeight("black")
        model.listDidDisappear()
        library.weightStates[noto("black")] = .available
        model.listDidAppear()
        XCTAssertEqual(calls.weights, ["black"])
    }

    func testFailureOfThePendingDefaultWeightDropsThePending() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let calls = Calls()
        // The default face (bold) was deleted; the user picks it again.
        library.states[.notoSerifTC] = .notDownloaded
        let model = makeModel(library: library, current: .notoSerifTC, weight: "black", calls: calls)
        model.didTapWeight("bold")
        XCTAssertEqual(model.pendingWeight, noto("bold"))
        library.states[.notoSerifTC] = .failed(.other)
        model.libraryDidChange()
        XCTAssertNil(model.pendingWeight, "預設字重失敗也要清除 pending")
        XCTAssertTrue(calls.weights.isEmpty)
    }

    func testAccessibilityLabelsNameTheWeightState() throws {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let model = makeModel(library: library)
        XCTAssertEqual(try cell(.notoSerifTC, in: model).weights[2].accessibilityLabel, "特粗，未下載，點兩下下載")
        XCTAssertEqual(try cell(.notoSerifTC, in: model).weights[1].accessibilityLabel, "粗")
    }

    // MARK: - TASK-112 (#437) collapse with weights

    /// 112.3: choosing a weight keeps the card expanded and the row's weight
    /// name follows the stored weight.
    func testChoosingAWeightKeepsItExpandedAndUpdatesTheName() throws {
        let calls = Calls()
        let model = makeModel(library: FakeFontLibrary(), current: .pingFang, calls: calls)
        model.didTap(.pingFang)
        model.didTapWeight("light")
        XCTAssertEqual(calls.weights, ["light"], "112.3 applied")
        XCTAssertTrue((model.expandedFontID != nil), "112.3 stays expanded")
        model.update(profileID: profileID, currentFontID: .pingFang, currentWeightID: "light")
        XCTAssertTrue((model.expandedFontID != nil), "a weight change is not a font change")
        model.didTap(.pingFang)
        XCTAssertFalse((model.expandedFontID != nil))
        XCTAssertEqual(try cell(.pingFang, in: model).currentWeightName, "細", "112.3 the row shows the new weight")
    }

    /// 112.8: a face downloading for the selected font shows on the collapsed
    /// row as a ring while the row keeps the stored weight's name.
    func testCollapsedRowShowsThePendingDownload() throws {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let model = makeModel(library: library)
        model.didTap(.notoSerifTC)
        model.didTapWeight("regular")
        XCTAssertEqual(library.weightDownloads, [noto("regular")])
        library.weightStates[noto("regular")] = .downloading(progress: 0.4)
        model.didTap(.notoSerifTC)
        let cell = try cell(.notoSerifTC, in: model)
        XCTAssertFalse(cell.isExpanded, "collapsed")
        XCTAssertEqual(cell.currentWeightName, "粗", "112.8 the stored weight until the download finishes")
        if case .downloading(let progress)? = cell.pendingWeightStatus {
            XCTAssertEqual(progress, 0.4, accuracy: 0.001, "112.8 the ring")
        } else {
            XCTFail("112.8 expected a downloading ring, got \(String(describing: cell.pendingWeightStatus))")
        }
    }

    // MARK: - TASK-115 (#446) chevron on every multi-weight row

    private func songti(_ weightID: String) -> FontDownloadID {
        FontDownloadID(fontID: .songti, weightID: weightID)
    }

    /// 115.1: a multi-weight row that is selected or on the device has a
    /// chevron; single-weight and not-downloaded fonts do not.
    func testOnlyOnDeviceMultiWeightRowsCanExpand() throws {
        let model = makeModel(library: FakeFontLibrary([.notoSerifTC: .available, .huninn: .available]), current: .pingFang)
        for entry in FontCatalog.entries {
            let expected = entry.weights.count > 1 && [.pingFang, .notoSerifTC].contains(entry.fontID)
            XCTAssertEqual(try cell(entry.fontID, in: model).canExpand, expected, "\(entry.fontID)")
        }
        XCTAssertFalse(try cell(.songti, in: model).canExpand, "115.1 未下載的多字重字型沒有 chevron")
        XCTAssertFalse(try cell(.notoSerifTC, in: model).isSelected)
        XCTAssertEqual(try cell(.notoSerifTC, in: model).expandActionName, "展開字重", "115.9")
    }

    /// 115.2: an unselected row expands with no framed weight, changes nothing.
    func testUnselectedRowExpandsWithoutAFrame() throws {
        let calls = Calls()
        let model = makeModel(library: FakeFontLibrary([.notoSerifTC: .available, .songti: .available]), calls: calls)
        model.toggleExpansion(of: .songti)
        let cell = try cell(.songti, in: model)
        XCTAssertTrue(cell.isExpanded)
        XCTAssertEqual(cell.weights.count, 3)
        XCTAssertTrue(cell.weights.allSatisfy { !$0.isSelected }, "115.2 no yellow frame")
        XCTAssertNil(cell.currentWeightName, "unselected collapsed row shows no weight")
        XCTAssertNil(cell.accessibilityValue, "115.9 value does not read a weight")
        XCTAssertEqual(cell.expandActionName, "收合字重")
        XCTAssertTrue(calls.fonts.isEmpty && calls.fontWeights.isEmpty && calls.weights.isEmpty, "115.2 nothing applied")
        XCTAssertEqual(model.currentFontID, .notoSerifTC)
        model.toggleExpansion(of: .songti)
        XCTAssertNil(model.expandedFontID, "the chevron toggles back")
    }

    /// 115.4: at most one row is expanded.
    func testOnlyOneRowIsExpandedAtATime() throws {
        let model = makeModel(library: FakeFontLibrary([.notoSerifTC: .available, .songti: .available]))
        model.toggleExpansion(of: .songti)
        model.toggleExpansion(of: .pingFang)
        XCTAssertEqual(model.expandedFontID, .pingFang)
        XCTAssertFalse(try cell(.songti, in: model).isExpanded)
        XCTAssertTrue(try cell(.pingFang, in: model).isExpanded)
        model.toggleExpansion(of: .huninn)
        XCTAssertEqual(model.expandedFontID, .pingFang, "a single-weight font has no chevron")
    }

    /// 115.5: the name area of an unselected row applies the font and collapses all.
    func testTappingAnUnselectedRowBodyAppliesAndCollapsesEverything() {
        let calls = Calls()
        let model = makeModel(library: FakeFontLibrary([.notoSerifTC: .available, .songti: .available]), calls: calls)
        model.toggleExpansion(of: .songti)
        model.didTap(.songti)
        XCTAssertEqual(calls.fonts, [.songti])
        XCTAssertTrue(calls.fontWeights.isEmpty)
        XCTAssertNil(model.expandedFontID, "115.5")
    }

    /// 115.3: a usable weight of an unselected font is applied with the font in one call.
    func testTappingAUsableWeightOfAnotherFontAppliesBothAtOnce() {
        let library = FakeFontLibrary([.notoSerifTC: .available, .songti: .available])
        library.weightStates[songti("light")] = .available
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.toggleExpansion(of: .songti)
        model.didTapWeight("light", of: .songti)
        XCTAssertEqual(calls.fontWeights, [songti("light")], "115.3 one combined write")
        XCTAssertTrue(calls.fonts.isEmpty, "never the font on its own")
        XCTAssertTrue(calls.weights.isEmpty, "never the weight on its own")
        XCTAssertTrue(library.weightDownloads.isEmpty)
        model.update(profileID: profileID, currentFontID: .songti, currentWeightID: "light")
        XCTAssertEqual(model.expandedFontID, .songti, "115.3 stays expanded")
        let cell = try? cell(.songti, in: model)
        XCTAssertEqual(cell?.weights.map(\.isSelected), [true, false, false], "115.3 the frame lands on the weight")
        XCTAssertEqual(cell?.currentWeightName, "細")
    }

    /// A failed combined save is reported and nothing is pending.
    func testFailedCombinedSaveIsReported() {
        let library = FakeFontLibrary([.notoSerifTC: .available, .songti: .available])
        library.weightStates[songti("light")] = .available
        let calls = Calls()
        calls.fontWeightResult = false
        let model = makeModel(library: library, calls: calls)
        model.didTapWeight("light", of: .songti)
        XCTAssertEqual(model.toast?.text, FontLibraryModel.weightSaveFailedMessage)
        XCTAssertNil(model.pendingWeight)
    }

    /// 115.7: a missing weight of an unselected font downloads first and applies
    /// font and weight together only when that exact face finishes.
    func testMissingWeightOfAnotherFontDownloadsThenAppliesBoth() {
        let library = FakeFontLibrary([.pingFang: .available, .notoSerifTC: .available])
        let calls = Calls()
        let model = makeModel(library: library, current: .pingFang, calls: calls)
        model.toggleExpansion(of: .notoSerifTC)
        model.didTapWeight("black", of: .notoSerifTC)
        XCTAssertEqual(library.weightDownloads, [noto("black")])
        XCTAssertEqual(model.pendingWeight, noto("black"))
        XCTAssertTrue(calls.fontWeights.isEmpty, "115.7 nothing applied while downloading")
        XCTAssertEqual(model.currentFontID, .pingFang)
        // A different face finishing does not apply it.
        library.weightStates[noto("regular")] = .available
        library.weightDownloadDidFinish.send(noto("regular"))
        XCTAssertTrue(calls.fontWeights.isEmpty)
        library.weightStates[noto("black")] = .available
        library.weightDownloadDidFinish.send(noto("black"))
        XCTAssertEqual(calls.fontWeights, [noto("black")], "applied once, together")
        XCTAssertNil(model.pendingWeight)
        XCTAssertEqual(model.toast?.text, "已套用「思源宋體　特粗」")
    }

    /// 115.7: a failed download keeps the old setting and shows the message.
    func testFailedDownloadOfAnotherFontsWeightKeepsEverything() {
        let library = FakeFontLibrary([.pingFang: .available])
        let calls = Calls()
        let model = makeModel(library: library, current: .pingFang, calls: calls)
        model.didTapWeight("black", of: .notoSerifTC)
        library.weightStates[noto("black")] = .failed(.noNetwork)
        model.libraryDidChange()
        XCTAssertNil(model.pendingWeight)
        XCTAssertEqual(model.toast?.text, FontStateText.offlineMessage)
        XCTAssertTrue(calls.fontWeights.isEmpty)
        XCTAssertEqual(model.currentFontID, .pingFang)
    }

    /// Mid-download the user taps another font: the old request is dropped.
    func testTappingAnotherFontMidDownloadDropsThePendingFontWeight() {
        let library = FakeFontLibrary([.pingFang: .available, .songti: .available])
        let calls = Calls()
        let model = makeModel(library: library, current: .pingFang, calls: calls)
        model.didTapWeight("black", of: .notoSerifTC)
        model.didTap(.songti)
        XCTAssertNil(model.pendingWeight)
        library.weightStates[noto("black")] = .available
        library.weightDownloadDidFinish.send(noto("black"))
        XCTAssertTrue(calls.fontWeights.isEmpty, "a stale request is never applied")
    }

    /// An update that leaves the profile and font as they were (another
    /// setting changed) keeps a pending face of an unselected font.
    func testUnrelatedProfileUpdateKeepsThePendingFontWeight() {
        let library = FakeFontLibrary([.pingFang: .available])
        let calls = Calls()
        let model = makeModel(library: library, current: .pingFang, calls: calls)
        model.didTapWeight("black", of: .notoSerifTC)
        model.update(profileID: profileID, currentFontID: .pingFang, currentWeightID: nil)
        XCTAssertEqual(model.pendingWeight, noto("black"), "字型沒變就保留 pending")
        library.weightStates[noto("black")] = .available
        library.weightDownloadDidFinish.send(noto("black"))
        XCTAssertEqual(calls.fontWeights, [noto("black")])
    }

    /// A real font change to another font, or a profile switch, still drops it.
    func testFontOrProfileChangeDropsThePendingFontWeight() {
        let library = FakeFontLibrary([.pingFang: .available, .songti: .available])
        let model = makeModel(library: library, current: .pingFang)
        model.didTapWeight("black", of: .notoSerifTC)
        model.update(profileID: profileID, currentFontID: .songti, currentWeightID: nil)
        XCTAssertNil(model.pendingWeight)
        model.didTapWeight("black", of: .notoSerifTC)
        model.update(profileID: UUID(), currentFontID: .songti, currentWeightID: nil)
        XCTAssertNil(model.pendingWeight)
    }

    /// A newer weight tap replaces the older pending one, even across fonts.
    func testANewerWeightTapReplacesThePendingOne() {
        let library = FakeFontLibrary([.pingFang: .available])
        let calls = Calls()
        let model = makeModel(library: library, current: .pingFang, calls: calls)
        model.didTapWeight("black", of: .notoSerifTC)
        model.didTapWeight("light", of: .songti)
        XCTAssertEqual(model.pendingWeight, songti("light"))
        library.weightStates[noto("black")] = .available
        library.weightDownloadDidFinish.send(noto("black"))
        XCTAssertTrue(calls.fontWeights.isEmpty)
        library.weightStates[songti("light")] = .available
        library.weightDownloadDidFinish.send(songti("light"))
        XCTAssertEqual(calls.fontWeights, [songti("light")])
    }

    /// 115.1／115.7: a font not downloaded yet has no chevron and cannot expand.
    func testNotDownloadedFontHasNoChevronAndCannotExpand() throws {
        let model = makeModel(library: FakeFontLibrary(), current: .pingFang)
        let cell = try cell(.notoSerifTC, in: model)
        XCTAssertFalse(cell.canExpand, "未下載的字型沒有 chevron")
        XCTAssertEqual(cell.status, .notDownloaded)
        model.toggleExpansion(of: .notoSerifTC)
        XCTAssertNil(model.expandedFontID, "不能展開")
        XCTAssertTrue(try self.cell(.notoSerifTC, in: model).weights.isEmpty)
        XCTAssertNil(try self.cell(.notoSerifTC, in: model).accessibilityHint)
    }

    /// A row that shows a download icon shows only that: no chevron, even when
    /// another face of the font is on the device, and also while it downloads or failed.
    func testRowWithADownloadIconHasNoChevron() throws {
        let library = FakeFontLibrary()
        library.weightStates[noto("regular")] = .available
        let model = makeModel(library: library, current: .pingFang)
        XCTAssertEqual(try cell(.notoSerifTC, in: model).status, .notDownloaded)
        XCTAssertFalse(try cell(.notoSerifTC, in: model).canExpand, "預設字重未下載：只有下載 icon")
        for state in [FontState.downloading(progress: 0.4), .preparing, .failed(.other)] {
            library.states[.notoSerifTC] = state
            XCTAssertFalse(try cell(.notoSerifTC, in: model).canExpand, "\(state)")
        }
        library.states[.notoSerifTC] = .available
        XCTAssertTrue(try cell(.notoSerifTC, in: model).canExpand, "預設字重在裝置上就有 chevron")
    }
}

/// TASK-34 acceptance 34.10 and 34.11: the license page.
@MainActor
final class FontLicenseViewTests: XCTestCase {
    func testListsTheOpenSourceFontsWithNoticesAndFullTexts() throws {
        let model = FontLicenseModel()
        XCTAssertEqual(model.entries.map(\.name), ["粉圓", "思源宋體", "芫荽", "辰宇落雁體"], "34.10")
        XCTAssertEqual(model.entries.map(\.version), ["2.1", "2.003", "1.012", "2.100"], "34.10")
        for entry in model.entries {
            XCTAssertFalse(entry.copyright.isEmpty, "34.10 \(entry.name)")
            XCTAssertFalse(entry.licenses.isEmpty)
            for license in entry.licenses {
                XCTAssertFalse(license.text.isEmpty, "34.10 \(entry.name) 授權全文要讀得到")
            }
        }
        let huninn = try XCTUnwrap(model.entries.first)
        XCTAssertEqual(huninn.licenses.map(\.title), ["SIL Open Font License 1.1", "Apache License 2.0"], "34.10")
        XCTAssertTrue(huninn.licenses[1].text.contains("Apache License"))
        XCTAssertEqual(model.entries[1].licenses.map(\.title), ["SIL Open Font License 1.1"])
    }

    func testCopyrightIsVerbatimFromTheCatalog() {
        let model = FontLicenseModel()
        XCTAssertEqual(model.entries[1].copyright, FontCatalog.notoSerifTCAsset.copyright)
        XCTAssertEqual(model.entries[2].copyright,
                       "Copyright 2025 The Iansui Project Authors (https://github.com/ButTaiwan/iansui)")
    }

    func testReadsEachFileTheCatalogNames() {
        var requested: [String] = []
        _ = FontLicenseModel(loadText: { requested.append($0); return "text" })
        XCTAssertEqual(Array(requested.prefix(5)), ["huninn-OFL.txt", "huninn-Apache-2.0.txt",
                                                    "notoSerifTC-OFL.txt", "iansui-OFL.txt", "chenyuluoyan-OFL.txt"])
        XCTAssertEqual(Array(requested.dropFirst(5)), FontCatalog.downloadFamilies.flatMap { family in
            family.faces.flatMap(\.asset.licenseFileNames).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        }, "142.5 每套的授權檔各讀一次")
    }

    func testListsEveryWeightFileWithItsOwnNotice() throws {
        let model = FontLicenseModel()
        let noto = try XCTUnwrap(model.entries.first { $0.fontID == .notoSerifTC })
        XCTAssertEqual(noto.files.map(\.fileName),
                       ["NotoSerifTC-Regular.otf", "NotoSerifTC-Bold.otf", "NotoSerifTC-Black.otf"], "89.5 授權頁逐字重列檔名")
        XCTAssertEqual(noto.files.map(\.weightName), ["標準", "粗", "特粗"])
        XCTAssertTrue(noto.files.allSatisfy { !$0.copyright.isEmpty && !$0.version.isEmpty }, "每個檔案都有 copyright")
        XCTAssertEqual(noto.licenses.map(\.title), ["SIL Open Font License 1.1"], "共用授權全文只列一次")
        let huninn = try XCTUnwrap(model.entries.first { $0.fontID == .huninn })
        XCTAssertEqual(huninn.files.map(\.fileName), [FontCatalog.entry(for: .huninn).openSource?.fileName ?? ""],
                       "單一檔案的字型也列檔名")
        XCTAssertFalse(try XCTUnwrap(huninn.files.first).weightName.isEmpty)
    }

    func testSystemFontsAreCreditedToApple() {
        XCTAssertTrue(FontLicenseModel.systemFontNote.contains("Apple"), "34.10")
    }
}
