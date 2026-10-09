import Combine
import XCTest
@testable import DaysCam

/// TASK-89 (PR #374) independent QA: 89.3, 89.4, 89.5, 89.7 and the license
/// page through the public models, with a stand-in library written apart from
/// the developer's `FakeFontLibrary`.
@MainActor
final class FontWeightPanelAcceptanceTests: XCTestCase {
    /// A library whose downloads finish or fail only when the test says so.
    private final class StandInLibrary: FontListControlling {
        let objectWillChange = ObservableObjectPublisher()
        let weightDownloadDidFinish = PassthroughSubject<FontDownloadID, Never>()
        var fontStates: [OverlayFontID: FontState] = [:]
        var weightStates: [FontDownloadID: FontState] = [:]
        private(set) var started: [FontDownloadID] = []
        var acceptsDownloads = true

        func state(for fontID: OverlayFontID) -> FontState {
            fontID == .pingFang ? .available : (fontStates[fontID] ?? .notDownloaded)
        }

        func state(for fontID: OverlayFontID, weightID: String?) -> FontState {
            let entry = FontCatalog.entry(for: fontID)
            let weight = entry.weight(for: weightID)
            if entry.source == .builtIn || weight.id == entry.defaultWeight.id { return state(for: fontID) }
            return weightStates[FontDownloadID(fontID: fontID, weightID: weight.id)] ?? .notDownloaded
        }

        func cancel(_ fontID: OverlayFontID) {}
        func delete(_ fontID: OverlayFontID) -> Bool { true }

        func download(_ fontID: OverlayFontID, weightID: String?) -> Bool {
            guard acceptsDownloads else { return false }
            let unit = FontDownloadID(fontID: fontID, weightID: FontCatalog.entry(for: fontID).weight(for: weightID).id)
            started.append(unit)
            weightStates[unit] = .downloading(progress: 0.3)
            return true
        }

        /// The download of `unit` succeeds, in the order the real library
        /// does it: state first, then the finish event.
        func finish(_ unit: FontDownloadID) {
            weightStates[unit] = .available
            weightDownloadDidFinish.send(unit)
        }

        func fail(_ unit: FontDownloadID, _ reason: FontFailureReason = .other) {
            weightStates[unit] = .failed(reason)
        }
    }

    private final class Saved {
        var profiles: [CameraProfile] = []
    }

    private var defaults: UserDefaults!
    private let suiteName = "FontWeightPanelAcceptanceTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func black() -> FontDownloadID { FontDownloadID(fontID: .notoSerifTC, weightID: "black") }
    private func regular() -> FontDownloadID { FontDownloadID(fontID: .notoSerifTC, weightID: "regular") }

    private func makePanel(profile: CameraProfile? = nil,
                           library: StandInLibrary,
                           saved: Saved = Saved()) -> StyleTabModel {
        var start = profile ?? CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1))
        if profile == nil { start.style.fontID = .notoSerifTC }
        let model = StyleTabModel(profile: start,
                                  recentColorsStore: RecentColorsStore(defaults: defaults),
                                  fontLibrary: library,
                                  applyFont: { _, _ in },
                                  allProfiles: { [] },
                                  updateProfile: { saved.profiles.append($0) })
        model.fontList.listDidAppear()
        return model
    }

    private func cell(_ fontID: OverlayFontID, in list: FontLibraryModel) throws -> FontLibraryModel.Cell {
        try XCTUnwrap(list.sections.flatMap(\.cells).first { $0.fontID == fontID })
    }

    // MARK: 89.3

    /// 89.3: 思源宋體「粗」(black) chosen, saved, JSON round-tripped (a
    /// relaunch) and loaded into a fresh panel is still the chosen weight.
    func testChosenSourceSerifWeightSurvivesARelaunch() throws {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        library.weightStates[black()] = .available
        let saved = Saved()
        let panel = makePanel(library: library, saved: saved)
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "bold", "預設為現行 Bold")
        panel.fontList.didTapWeight("black")

        let written = try XCTUnwrap(saved.profiles.last, "89.3 選字重後要存設定檔")
        let data = try JSONEncoder().encode(written)
        let reloaded = try JSONDecoder().decode(CameraProfile.self, from: data)
        XCTAssertEqual(reloaded.style.resolvedFontWeight.id, "black", "89.3 重啟後仍是特粗")
        XCTAssertEqual(reloaded.style.resolvedFontWeight.postScriptName, "NotoSerifTC-Black")

        let fresh = makePanel(profile: reloaded, library: library)
        let notoCell = try cell(.notoSerifTC, in: fresh.fontList)
        XCTAssertEqual(notoCell.weights.first(where: \.isSelected)?.weightID, "black", "89.3 離頁後回來仍選取")
        XCTAssertEqual(notoCell.nameWeightID, "black")
    }

    /// 89.3: leaving the page (listDidDisappear/Appear) keeps the weight.
    func testWeightSurvivesLeavingTheFontPage() throws {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        library.weightStates[regular()] = .available
        let panel = makePanel(library: library)
        panel.fontList.didTapWeight("regular")
        panel.fontList.listDidDisappear()
        panel.fontList.listDidAppear()
        XCTAssertEqual(panel.profile.style.fontWeight, "regular")
        XCTAssertEqual(try cell(.notoSerifTC, in: panel.fontList).weights.first(where: \.isSelected)?.weightID, "regular")
    }

    // MARK: 89.4

    /// 89.4: Noto black -> 芫荽 (single weight) -> back to Noto lands on the
    /// default weight, and the next color change does not write black back.
    func testSwitchingToASingleWeightFontAndBackResetsTheWeight() {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        library.weightStates[black()] = .available
        let saved = Saved()
        var profile = CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1))
        profile.style.fontID = .notoSerifTC
        profile.style.fontWeight = "black"
        let panel = makePanel(profile: profile, library: library, saved: saved)

        // The camera applies a font by rewriting the profile; the panel follows.
        var toIansui = panel.profile
        toIansui.style.fontID = .iansui
        toIansui.style.fontWeight = nil
        panel.applyExternalChanges(from: toIansui)
        XCTAssertEqual(panel.profile.style.fontID, .iansui)
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id,
                       FontCatalog.entry(for: .iansui).defaultWeight.id)

        var back = panel.profile
        back.style.fontID = .notoSerifTC
        back.style.fontWeight = nil
        panel.applyExternalChanges(from: back)
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "bold", "89.4 換回後字重回預設")

        panel.selectTextColor(OverlayStyle.swatches[1])
        XCTAssertEqual(saved.profiles.last?.style.resolvedFontWeight.id, "bold", "舊的特粗不會被寫回")
    }

    /// 89.3: another writer changed only the weight; the panel follows and the
    /// next color change does not write the old weight back.
    func testExternalWeightOnlyChangeIsNotOverwrittenByTheNextEdit() {
        let library = StandInLibrary()
        let saved = Saved()
        let panel = makePanel(library: library, saved: saved)
        var latest = panel.profile
        latest.style.fontWeight = "black"
        panel.applyExternalChanges(from: latest)
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "black")
        XCTAssertEqual(panel.fontList.currentWeightID, "black")
        panel.selectTextColor(OverlayStyle.swatches[1])
        XCTAssertEqual(saved.profiles.last?.style.resolvedFontWeight.id, "black", "改色不得寫回舊字重")
    }

    /// 89.4 through the real applyFont reset rule: changing `fontID` clears the weight.
    func testChangingFontIDClearsTheStoredWeight() {
        var style = OverlayStyle()
        style.fontID = .notoSerifTC
        style.fontWeight = "black"
        style.fontID = .songti
        XCTAssertEqual(style.resolvedFontWeight.id, FontCatalog.entry(for: .songti).defaultWeight.id)
    }

    // MARK: 89.5

    /// 89.5: a missing weight shows downloading, is not applied nor saved,
    /// and is applied only once the library says that face finished.
    func testMissingWeightShowsDownloadingAndAppliesOnlyAfterFinishing() throws {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        let saved = Saved()
        let panel = makePanel(library: library, saved: saved)
        XCTAssertEqual(try cell(.notoSerifTC, in: panel.fontList).weights.last?.status, .notDownloaded, "下載圖示")

        panel.fontList.didTapWeight("black")
        XCTAssertEqual(library.started, [black()])
        XCTAssertEqual(try cell(.notoSerifTC, in: panel.fontList).weights.last?.status,
                       .downloading(progress: 0.3), "89.5 顯示下載中")
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "bold", "89.5 下載中保留原字重")
        XCTAssertTrue(saved.profiles.isEmpty, "89.5 下載中不寫設定檔")
        XCTAssertEqual(try cell(.notoSerifTC, in: panel.fontList).weights.first(where: \.isSelected)?.weightID, "bold")

        library.finish(black())
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "black", "89.5 完成才套用")
        XCTAssertEqual(saved.profiles.last?.style.resolvedFontWeight.id, "black")
        XCTAssertEqual(panel.fontList.toast?.text, "已套用「思源宋體　特粗」")
    }

    /// 89.5: failure keeps the old weight, says failed, never says applied.
    func testFailedDownloadKeepsTheOldWeightAndNeverReportsSuccess() throws {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        let saved = Saved()
        let panel = makePanel(library: library, saved: saved)
        panel.fontList.didTapWeight("black")
        library.fail(black())
        panel.fontList.libraryDidChange()

        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "bold", "89.5 保留原字重")
        XCTAssertTrue(saved.profiles.isEmpty)
        XCTAssertEqual(try cell(.notoSerifTC, in: panel.fontList).weights.last?.status, .failed, "89.5 按鈕顯示失敗")
        let text = try XCTUnwrap(panel.fontList.toast?.text, "89.5 要顯示失敗訊息")
        XCTAssertTrue(text.contains("失敗"), text)
        XCTAssertFalse(text.contains("已套用"), text)
        XCTAssertNil(panel.fontList.pendingWeight)

        // A stray finish for the dropped request must not apply it.
        library.weightDownloadDidFinish.send(black())
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "bold", "失敗後遲到的完成事件不套用")
    }

    /// 89.5: the offline failure uses the offline message, not a success.
    func testOfflineFailureIsReportedAsOffline() throws {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        let panel = makePanel(library: library)
        panel.fontList.didTapWeight("black")
        library.fail(black(), .noNetwork)
        panel.fontList.libraryDidChange()
        XCTAssertEqual(panel.fontList.toast?.text, FontStateText.offlineMessage)
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "bold")
    }

    /// 89.5 race: while 特粗 downloads the user taps an available 標準; the
    /// later finish of 特粗 must not override that choice.
    func testChoosingAnotherWeightWhileDownloadingCancelsThePendingOne() {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        library.weightStates[regular()] = .available
        let panel = makePanel(library: library)
        panel.fontList.didTapWeight("black")
        panel.fontList.didTapWeight("regular")
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "regular")
        library.finish(black())
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "regular", "舊請求完成不覆蓋後來的選擇")
    }

    /// 89.5 race: switching the font before the face finishes drops the request.
    func testFinishingAfterTheFontChangedDoesNotWriteTheWeight() {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        library.fontStates[.songti] = .available
        let saved = Saved()
        let panel = makePanel(library: library, saved: saved)
        panel.fontList.didTapWeight("black")
        var songti = panel.profile
        songti.style.fontID = .songti
        songti.style.fontWeight = nil
        panel.applyExternalChanges(from: songti)
        library.finish(black())
        XCTAssertEqual(panel.profile.style.fontID, .songti)
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, FontCatalog.entry(for: .songti).defaultWeight.id)
        XCTAssertTrue(saved.profiles.isEmpty, "不得把 Noto 的字重寫進宋體的設定檔")
    }

    /// 89.3/89.5: when saving the profile fails, the old weight stays and the
    /// failure is shown, never reported as applied.
    func testSaveFailureKeepsTheOldWeightAndSaysSo() {
        struct Boom: Error {}
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        library.weightStates[black()] = .available
        var start = CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1))
        start.style.fontID = .notoSerifTC
        let panel = StyleTabModel(profile: start,
                                  recentColorsStore: RecentColorsStore(defaults: defaults),
                                  fontLibrary: library,
                                  applyFont: { _, _ in },
                                  allProfiles: { [] },
                                  updateProfile: { _ in throw Boom() })
        panel.fontList.listDidAppear()
        panel.fontList.didTapWeight("black")
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "bold", "存檔失敗保留原字重")
        XCTAssertEqual(panel.fontList.toast?.text, FontLibraryModel.weightSaveFailedMessage)

        // The same through a finished download.
        library.weightStates[regular()] = .notDownloaded
        panel.fontList.didTapWeight("regular")
        library.finish(regular())
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "bold")
        XCTAssertEqual(panel.fontList.toast?.text, FontLibraryModel.weightSaveFailedMessage)
        XCTAssertFalse(panel.fontList.toast?.text.contains("已套用") ?? false)
    }

    /// 89.5: a library that refuses to start the download leaves nothing pending.
    func testRefusedDownloadLeavesNothingPending() {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        library.acceptsDownloads = false
        let panel = makePanel(library: library)
        panel.fontList.didTapWeight("black")
        XCTAssertNil(panel.fontList.pendingWeight)
        library.finish(black())
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "bold")
    }

    /// 89.5: retry after a failure downloads again and applies on success.
    func testRetryAfterFailureCanStillApply() {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        let panel = makePanel(library: library)
        panel.fontList.didTapWeight("black")
        library.fail(black())
        panel.fontList.libraryDidChange()
        panel.fontList.didTapWeight("black")
        XCTAssertEqual(library.started, [black(), black()])
        library.finish(black())
        XCTAssertEqual(panel.profile.style.resolvedFontWeight.id, "black")
    }

    // MARK: 89.7

    /// 89.7: for every font as the selection, only that font expands, only if
    /// it has several weights; every other multi-weight row shows "N 種字重".
    func testOnlyTheSelectedMultiWeightRowExpandsForEveryFont() throws {
        for selected in OverlayFontID.allCases {
            let library = StandInLibrary()
            let list = FontLibraryModel(profileID: UUID(), currentFontID: selected, library: library,
                                        profiles: { [] }, applyFont: { _, _ in })
            list.listDidAppear()
            let cells = list.sections.flatMap(\.cells)
            let expanded = cells.filter(\.isExpanded).map(\.fontID)
            let count = FontCatalog.entry(for: selected).weights.count
            XCTAssertEqual(expanded, count > 1 ? [selected] : [], "\(selected)")
            for cell in cells where cell.fontID != selected {
                let n = FontCatalog.entry(for: cell.fontID).weights.count
                XCTAssertEqual(cell.weightCountText, n > 1 ? "\(n) 種字重" : nil, "\(cell.fontID)")
                XCTAssertTrue(cell.weights.isEmpty)
            }
            if count == 1 {
                XCTAssertNil(try cell(selected, in: list).weightCountText, "單一字重不顯示 N 種字重")
            }
        }
    }

    /// 89.7: exactly one button is the selected frame; undownloaded faces get
    /// the download icon, and the buttons use their own face, not `.bold()`.
    func testButtonsHaveOneSelectionDownloadIconsAndTheirOwnFaces() throws {
        let library = StandInLibrary()
        library.fontStates[.notoSerifTC] = .available
        let panel = makePanel(library: library)
        let notoCell = try cell(.notoSerifTC, in: panel.fontList)
        XCTAssertEqual(notoCell.weights.filter(\.isSelected).count, 1)
        XCTAssertEqual(notoCell.weights.map(\.status), [.notDownloaded, .none, .notDownloaded])
        let ps = FontCatalog.entry(for: .notoSerifTC).weights.map(\.postScriptName)
        XCTAssertEqual(ps, ["NotoSerifTC-Regular", "NotoSerifTC-Bold", "NotoSerifTC-Black"])
        XCTAssertEqual(Set(ps).count, 3, "每個字重解析到不同的 face")
    }

    // MARK: License page

    /// Every open-source weight file is listed with its own file name,
    /// version and copyright, verbatim from the catalog; license texts once.
    func testLicensePageListsEveryWeightFileOnce() throws {
        let model = FontLicenseModel()
        for entry in FontCatalog.entries where entry.openSource != nil {
            let listed = try XCTUnwrap(model.entries.first { $0.fontID == entry.fontID }, "\(entry.fontID)")
            let assets = entry.weights.compactMap(\.openSource)
            XCTAssertEqual(listed.files.map(\.fileName), assets.map(\.fileName), "\(entry.fontID)")
            XCTAssertEqual(listed.files.map(\.copyright), assets.map(\.copyright))
            XCTAssertEqual(listed.files.map(\.version), assets.map(\.version))
            XCTAssertTrue(listed.files.allSatisfy { !$0.copyright.isEmpty })
            let titles = listed.licenses.map(\.title)
            XCTAssertEqual(Set(titles).count, titles.count, "共用授權只列一次 \(entry.fontID)")
            XCTAssertTrue(listed.licenses.allSatisfy { !$0.text.isEmpty }, "授權全文讀得到")
        }
        let noto = try XCTUnwrap(model.entries.first { $0.fontID == .notoSerifTC })
        XCTAssertEqual(noto.files.count, 3)
    }
}
