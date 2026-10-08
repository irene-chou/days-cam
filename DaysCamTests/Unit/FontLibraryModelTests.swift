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

    func testVoiceOverLabelsCarryTheStateButCellsShowNoText() throws {
        let library = FakeFontLibrary([.songti: .notDownloaded, .kaiti: .downloading(progress: 0.38)])
        let model = makeModel(library: library)
        XCTAssertEqual(try cell(.songti, in: model).accessibilityLabel, "宋體，未下載，點兩下下載", "56.14")
        XCTAssertEqual(try cell(.kaiti, in: model).accessibilityLabel, "楷體，下載中，38%", "56.14")
        XCTAssertEqual(try cell(.pingFang, in: model).accessibilityLabel, "蘋方", "56.14")
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

    func testSystemFontsAreCreditedToApple() {
        XCTAssertTrue(FontLicenseModel.systemFontNote.contains("Apple"), "34.10")
    }
}
