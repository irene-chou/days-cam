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
                           visible: Bool = true) -> FontLibraryModel {
        let model = FontLibraryModel(profileID: profileID,
                                     currentFontID: current,
                                     library: library,
                                     profiles: { profiles },
                                     applyFont: { calls.applied.append(Applied(fontID: $0, profileID: $1)) })
        if visible { model.listDidAppear() }
        return model
    }

    private func cell(_ fontID: OverlayFontID, in model: FontLibraryModel) throws -> FontLibraryModel.Cell {
        try XCTUnwrap(model.sections.flatMap(\.cells).first { $0.fontID == fontID })
    }

    private func section(_ category: FontSection?, in model: FontLibraryModel) -> FontLibraryModel.Section? {
        model.sections.first { $0.category == category }
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
        XCTAssertNil(first?.category, "56.1: 已下載段沒有小標")
        XCTAssertNil(first?.title, "56.1")
        XCTAssertEqual(first?.cells.map(\.fontID), [.pingFang, .huninn, .xingkai], "56.1: 蘋方第一格，其餘依 allCases 順序")
    }

    func testNotDownloadedFontsFollowByCategoryWithTitles() throws {
        let model = makeModel(library: FakeFontLibrary())
        let titles = model.sections.dropFirst().compactMap(\.title)
        XCTAssertEqual(titles, ["開源", "黑", "圓", "宋", "楷", "手寫", "書法", "可愛"], "56.1")
        let all = model.sections.flatMap(\.cells).map(\.fontID)
        XCTAssertEqual(Set(all), Set(OverlayFontID.allCases), "56.1: 每款字型恰好出現一次")
        XCTAssertEqual(all.count, OverlayFontID.allCases.count, "56.1")
    }

    func testCategoryWithEveryFontDownloadedIsHiddenWithItsTitle() {
        let openSource: [OverlayFontID] = FontCatalog.entries.filter { $0.section == .openSource }.map(\.fontID)
        var states: [OverlayFontID: FontState] = [:]
        for fontID in openSource { states[fontID] = .available }
        let model = makeModel(library: FakeFontLibrary(states))
        XCTAssertNil(section(.openSource, in: model), "56.1/56.9: 整段（含小標）隱藏")
        XCTAssertNotNil(section(.hei, in: model))
    }

    func testCurrentFontThatIsNotDownloadedStaysInTheDownloadedSectionSelected() throws {
        let model = makeModel(library: FakeFontLibrary([.xingkai: .notDownloaded]), current: .xingkai)
        let cell = try cell(.xingkai, in: model)
        XCTAssertTrue(model.sections[0].cells.contains(cell), "56.13: 在已下載段")
        XCTAssertTrue(cell.isSelected, "56.13")
        XCTAssertEqual(cell.status, .notDownloaded, "56.13: 灰色 ↓")
        XCTAssertFalse(cell.usesRealFont, "56.13")
        XCTAssertNil(section(.kai, in: model)?.cells.first { $0.fontID == .xingkai })
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
        XCTAssertNotNil(section(.song, in: model)?.cells.first { $0.fontID == .songti })

        library.states[.songti] = .available
        model.update(profileID: profileID, currentFontID: .songti)   // auto-applied
        model.libraryDidChange()

        let finished = try cell(.songti, in: model)
        XCTAssertEqual(finished.status, .justCompleted, "56.7")
        XCTAssertTrue(finished.usesRealFont, "56.7")
        XCTAssertTrue(finished.isSelected, "56.7")
        XCTAssertNotNil(section(.song, in: model)?.cells.first { $0.fontID == .songti }, "56.7: 留在原位")
        XCTAssertFalse(model.sections[0].cells.contains { $0.fontID == .songti })

        model.expireCompletionCheck(of: .songti)
        XCTAssertEqual(try cell(.songti, in: model).status, .none, "56.7: 勾消失後轉為已下載樣式")
        XCTAssertNotNil(section(.song, in: model)?.cells.first { $0.fontID == .songti }, "56.7: 仍在原位")

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
}

/// TASK-89 acceptance 89.3 to 89.5 and 89.7 at the font list: the expanded
/// card, weight taps, pending downloads.
@MainActor
final class FontWeightListTests: XCTestCase {
    private let profileID = UUID()

    private final class Calls {
        var weights: [String] = []
        var fonts: [OverlayFontID] = []
    }

    private func makeModel(library: FakeFontLibrary, current: OverlayFontID = .notoSerifTC,
                           weight: String? = nil, calls: Calls = Calls()) -> FontLibraryModel {
        let model = FontLibraryModel(profileID: profileID,
                                     currentFontID: current,
                                     currentWeightID: weight,
                                     library: library,
                                     profiles: { [] },
                                     applyFont: { id, _ in calls.fonts.append(id) },
                                     applyWeight: { _, weightID in calls.weights.append(weightID); return true })
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
        XCTAssertNil(selected.weightCountText, "展開時不顯示 N 種字重")
        let songti = try cell(.songti, in: model)
        XCTAssertTrue(songti.weights.isEmpty, "89.7 同時只展開選中的一列")
        XCTAssertEqual(songti.weightCountText, "3 種字重", "89.7")
        XCTAssertEqual(try cell(.hiraginoSans, in: model).weightCountText, "2 種字重", "89.7")
        let single = try cell(.huninn, in: model)
        XCTAssertNil(single.weightCountText, "89.7 單一字重不標示")
        XCTAssertNil(try cell(.chenyuluoyan, in: model).weightCountText, "89.7 辰宇落雁體只有細體")
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
        XCTAssertEqual(try cell(.huninn, in: model).name, "jf open 粉圓 2.1", "單一字重維持 fullName")
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
        XCTAssertEqual(requested, ["huninn-OFL.txt", "huninn-Apache-2.0.txt",
                                   "notoSerifTC-OFL.txt", "iansui-OFL.txt", "chenyuluoyan-OFL.txt"])
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
