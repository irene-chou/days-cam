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

/// TASK-34 acceptance 34.4 to 34.9: the font list's sections, row states,
/// taps, messages and delete menu.
@MainActor
final class FontLibraryModelTests: XCTestCase {
    private let profileID = UUID()

    private struct Applied: Equatable {
        let fontID: OverlayFontID
        let profileID: UUID
    }

    private final class Calls {
        var applied: [Applied] = []
        var log: [String] = []
        var replaceResult: Result<[UUID], Error> = .success([])
    }

    private struct ReplaceError: Error {}

    private func makeModel(library: FakeFontLibrary,
                           current: OverlayFontID = .pingFang,
                           profiles: [CameraProfile] = [],
                           calls: Calls = Calls()) -> FontLibraryModel {
        FontLibraryModel(profileID: profileID,
                         currentFontID: current,
                         library: library,
                         profiles: { profiles },
                         applyFont: { calls.applied.append(Applied(fontID: $0, profileID: $1)) },
                         replaceFont: { font, replacement in
                             calls.log.append("replace \(font.rawValue)->\(replacement.rawValue)")
                             return try calls.replaceResult.get()
                         })
    }

    private func row(_ fontID: OverlayFontID, in model: FontLibraryModel) throws -> FontLibraryModel.Row {
        try XCTUnwrap(model.sections.flatMap(\.rows).first { $0.fontID == fontID })
    }

    private func profile(named name: String, font: OverlayFontID) -> CameraProfile {
        var profile = CameraProfile(name: name, startDate: DateComponents(year: 2026, month: 1, day: 1))
        profile.style.fontID = font
        return profile
    }

    // MARK: - 34.4 分段

    func testNineSectionsMatchTheCatalogOrder() {
        let model = makeModel(library: FakeFontLibrary())
        XCTAssertEqual(model.sections.map(\.title),
                       ["內建", "開源", "黑", "圓", "宋", "楷", "手寫", "書法", "可愛"], "34.4")
        XCTAssertEqual(model.sections.map { $0.rows.map(\.fontID) },
                       [[.pingFang],
                        [.huninn, .notoSerifTC, .iansui, .chenyuluoyan],
                        [.lantinghei, .liHei, .hiraginoSans],
                        [.yuanti],
                        [.songti, .liSong],
                        [.kaiti, .biauKai],
                        [.hanziPen, .hannotate, .lingWai],
                        [.xingkai, .weibei, .libian, .baoli],
                        [.wawa, .yuppy]], "34.4")
        XCTAssertEqual(model.sections.flatMap(\.rows).map(\.fontID), OverlayFontID.allCases, "34.4")
    }

    func testOnlyTheCurrentFontHasTheCheckmark() {
        let model = makeModel(library: FakeFontLibrary([.huninn: .available]), current: .huninn)
        let current = model.sections.flatMap(\.rows).filter(\.isCurrent).map(\.fontID)
        XCTAssertEqual(current, [.huninn])
    }

    // MARK: - 34.5 右側狀態

    func testTrailingTextForEveryState() throws {
        let library = FakeFontLibrary([.huninn: .available,
                                       .xingkai: .downloading(progress: 0.38),
                                       .weibei: .failed(.other),
                                       .kaiti: .preparing,
                                       .iansui: .available,
                                       .liSong: .available])
        let model = makeModel(library: library)
        XCTAssertEqual(try row(.songti, in: model).trailing, .download(sizeText: "43.7 MB"), "34.5")
        XCTAssertEqual(try row(.xingkai, in: model).trailing,
                       .downloading(percentText: "38%", progress: 0.38), "34.5")
        XCTAssertEqual(try row(.weibei, in: model).trailing, .retry, "34.5")
        XCTAssertEqual(try row(.kaiti, in: model).trailing, .preparing)
        XCTAssertEqual(try row(.huninn, in: model).trailing, .menu, "34.5 開源有 ⋯")
        XCTAssertEqual(try row(.iansui, in: model).trailing, .menu, "34.5")
        XCTAssertEqual(try row(.liSong, in: model).trailing, .none, "34.5/34.9 系統字型沒有 ⋯")
        XCTAssertEqual(try row(.pingFang, in: model).trailing, .none, "34.5 蘋方沒有")
    }

    func testNotDownloadedRowShowsItsSize() throws {
        let model = makeModel(library: FakeFontLibrary())
        XCTAssertEqual(try row(.notoSerifTC, in: model).trailing, .download(sizeText: "8.3 MB"))
    }

    // MARK: - 34.6 點列

    func testTappingNotDownloadedFailedAndAvailableRowsAppliesOnce() {
        let library = FakeFontLibrary([.huninn: .available, .weibei: .failed(.noNetwork)])
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapRow(.songti)
        model.didTapRow(.weibei)
        model.didTapRow(.huninn)
        XCTAssertEqual(calls.applied, [Applied(fontID: .songti, profileID: profileID),
                                       Applied(fontID: .weibei, profileID: profileID),
                                       Applied(fontID: .huninn, profileID: profileID)], "34.6")
        XCTAssertTrue(library.cancelled.isEmpty)
        XCTAssertTrue(library.deleted.isEmpty)
    }

    func testTappingAPreparingRowDoesNothing() {
        let library = FakeFontLibrary([.kaiti: .preparing])
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapRow(.kaiti)
        XCTAssertTrue(calls.applied.isEmpty)
        XCTAssertTrue(library.cancelled.isEmpty)
        XCTAssertNil(model.toast)
    }

    // MARK: - 34.7 點下載中

    func testTappingADownloadingRowCancelsAndSaysSo() {
        let library = FakeFontLibrary([.xingkai: .downloading(progress: 0.38)])
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.didTapRow(.xingkai)
        XCTAssertEqual(library.cancelled, [.xingkai], "34.7")
        XCTAssertEqual(model.toast?.text, "已取消下載", "34.7")
        XCTAssertTrue(calls.applied.isEmpty, "取消不套用")
    }

    // MARK: - 34.8 刪除

    func testDeleteMenuNamesTheSizeAndHowManyProfilesUseTheFont() throws {
        let profiles = [profile(named: "小寶", font: .huninn),
                        profile(named: "毛毛", font: .huninn),
                        profile(named: "其他", font: .pingFang)]
        let model = makeModel(library: FakeFontLibrary([.huninn: .available]), profiles: profiles)
        model.requestDeletion(of: .huninn)
        let prompt = try XCTUnwrap(model.deletePrompt)
        XCTAssertEqual(prompt.title, "粉圓　4.9 MB")
        XCTAssertTrue(prompt.usage.contains("2 個設定檔正在使用"), "34.8")
        XCTAssertEqual(prompt.usage, "「小寶」等 2 個設定檔正在使用，刪除後改回蘋方")
    }

    func testDeleteMenuWithOneOrNoUser() throws {
        let one = makeModel(library: FakeFontLibrary([.iansui: .available]),
                            profiles: [profile(named: "小寶", font: .iansui)])
        one.requestDeletion(of: .iansui)
        XCTAssertEqual(one.deletePrompt?.usage, "「小寶」正在使用，刪除後改回蘋方")

        let none = makeModel(library: FakeFontLibrary([.iansui: .available]),
                             profiles: [profile(named: "小寶", font: .pingFang)])
        none.requestDeletion(of: .iansui)
        XCTAssertEqual(none.deletePrompt?.usage, "沒有設定檔在用這套字型")
    }

    func testConfirmingReplacesBeforeItDeletes() {
        let library = FakeFontLibrary([.huninn: .available])
        let calls = Calls()
        library.onDelete = { calls.log.append("delete") }
        let id = profileID
        calls.replaceResult = .success([id])
        let model = makeModel(library: library, current: .huninn,
                              profiles: [profile(named: "小寶", font: .huninn)], calls: calls)
        model.requestDeletion(of: .huninn)
        model.confirmDeletion()
        XCTAssertEqual(calls.log, ["replace huninn->pingFang", "delete"], "34.8 先 replaceFont 再 delete")
        XCTAssertEqual(library.deleted, [.huninn])
        XCTAssertEqual(model.toast?.text, "已刪除「粉圓」，釋放 4.9 MB")
        XCTAssertNil(model.deletePrompt)
        XCTAssertEqual(model.currentFontID, .pingFang)
    }

    func testReplaceFailureKeepsTheFontFile() {
        let library = FakeFontLibrary([.huninn: .available])
        let calls = Calls()
        calls.replaceResult = .failure(ReplaceError())
        let model = makeModel(library: library, calls: calls)
        model.requestDeletion(of: .huninn)
        model.confirmDeletion()
        XCTAssertTrue(library.deleted.isEmpty, "改回蘋方沒存成功就不能刪檔")
        XCTAssertEqual(model.toast?.text, FontLibraryModel.deleteFailedMessage)
    }

    func testDeleteFailureIsReportedNotShownAsDeleted() {
        let library = FakeFontLibrary([.huninn: .available])
        library.deleteResult = false
        let model = makeModel(library: library)
        model.requestDeletion(of: .huninn)
        model.confirmDeletion()
        XCTAssertEqual(model.toast?.text, FontLibraryModel.deleteFailedMessage)
    }

    func testCancellingTheMenuDeletesNothing() {
        let library = FakeFontLibrary([.huninn: .available])
        let calls = Calls()
        let model = makeModel(library: library, calls: calls)
        model.requestDeletion(of: .huninn)
        model.cancelDeletion()
        XCTAssertNil(model.deletePrompt)
        XCTAssertTrue(calls.log.isEmpty)
        XCTAssertTrue(library.deleted.isEmpty)
    }

    // MARK: - 34.9 系統字型沒有選單

    func testSystemFontsAndPingFangHaveNoDeleteMenu() {
        let library = FakeFontLibrary([.songti: .available])
        let model = makeModel(library: library)
        model.requestDeletion(of: .songti)
        model.requestDeletion(of: .pingFang)
        XCTAssertNil(model.deletePrompt, "34.9")
    }

    // MARK: - FR-16.10 失敗提示

    func testFailureMessages() {
        let library = FakeFontLibrary([.songti: .downloading(progress: 0.5), .xingkai: .notDownloaded])
        let model = makeModel(library: library)
        library.states[.songti] = .failed(.other)
        model.libraryDidChange()
        XCTAssertEqual(model.toast?.text, "「宋體」下載失敗，點一下重試")
        library.states[.xingkai] = .failed(.noNetwork)
        model.libraryDidChange()
        XCTAssertEqual(model.toast?.text, "沒有網路，連上後再點一次")
    }

    /// The model re-reads the library on the main queue after each
    /// `objectWillChange`; a failure must be announced once however many
    /// times that happens afterwards.
    func testDownloadFailureIsAnnouncedOnlyOnce() async throws {
        let library = FakeFontLibrary([.songti: .downloading(progress: 0.5)])
        let model = makeModel(library: library)
        var posted: [FontLibraryModel.Toast] = []
        let cancellable = model.$toast.dropFirst().compactMap { $0 }.sink { posted.append($0) }

        // The library's willChange fires before the state changes.
        library.objectWillChange.send()
        library.states[.songti] = .failed(.other)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(posted.map(\.text), ["「宋體」下載失敗，點一下重試"])

        // Later changes elsewhere, and extra reads, do not repeat it.
        library.objectWillChange.send()
        model.libraryDidChange()
        library.states[.huninn] = .available
        library.objectWillChange.send()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(posted.count, 1, "失敗只提示一次")
        cancellable.cancel()
    }

    func testPreparingThatFailsAtLaunchIsNotAnnounced() {
        let library = FakeFontLibrary([.songti: .preparing])
        let model = makeModel(library: library)
        library.states[.songti] = .failed(.other)
        model.libraryDidChange()
        XCTAssertNil(model.toast)
    }

    // MARK: - 跟著設定檔

    func testCheckmarkFollowsTheProfile() {
        let model = makeModel(library: FakeFontLibrary())
        model.update(profileID: profileID, currentFontID: .iansui)
        XCTAssertEqual(model.currentFontID, .iansui)
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
    func testListsTheThreeOpenSourceFontsWithNoticesAndFullTexts() throws {
        let model = FontLicenseModel()
        XCTAssertEqual(model.entries.map(\.name), ["粉圓", "思源宋體", "芫荽"], "34.10")
        XCTAssertEqual(model.entries.map(\.version), ["2.1", "2.003", "1.012"], "34.10")
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
