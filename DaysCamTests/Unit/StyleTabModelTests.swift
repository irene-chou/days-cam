import XCTest
@testable import DaysCam

/// Covers `StyleTabModel`'s state transitions (PRD 0.2 FR-10), TASK-23
/// acceptance 23.1–23.10. 23.11 is a `grep` check run directly by QA, not a
/// unit test. 23.12/23.13 are B′ design-comparison, covered by the view's
/// `#Preview`s, not here.
@MainActor
final class StyleTabModelTests: XCTestCase {
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "StyleTabModelTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func hex(_ string: String) throws -> OverlayColor {
        try XCTUnwrap(OverlayColor(hex: string))
    }

    private final class Spy {
        var updated: [CameraProfile] = []
        var shouldThrow: Error?

        func update(_ profile: CameraProfile) throws {
            if let error = shouldThrow { throw error }
            updated.append(profile)
        }
    }

    private func makeModel(profile: CameraProfile = CameraProfile(name: "小寶",
                                                                  startDate: DateComponents(year: 2026, month: 1, day: 1)),
                           store: RecentColorsStore? = nil,
                           spy: Spy = Spy()) -> StyleTabModel {
        StyleTabModel(profile: profile,
                     recentColorsStore: store ?? RecentColorsStore(defaults: defaults),
                     applyFont: { _, _ in },
                     allProfiles: { [] },
                     updateProfile: spy.update)
    }

    // MARK: - 23.1 第二層無障礙標籤

    func testSubTabAccessibilityLabelsInOrder() {
        XCTAssertEqual(StyleTabModel.SubTab.allCases.map(\.accessibilityLabel),
                       ["顏色", "字級", "外框", "陰影", "字型"], "68.1")
    }

    func testDefaultSelectedSubTabIsColor() {
        XCTAssertEqual(makeModel().selectedSubTab, .color, "68.2")
    }

    // MARK: - 34.1 到 34.3, 34.6, 34.6a 字型格子（PRD 0.3 FR-10.2′）

    private struct AppliedFont: Equatable {
        let fontID: OverlayFontID
        let profileID: UUID
    }

    private func makeFontModel(library: FakeFontLibrary,
                               font: OverlayFontID = .pingFang,
                               applied: @escaping (AppliedFont) -> Void = { _ in },
                               spy: Spy = Spy()) -> StyleTabModel {
        var profile = CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1))
        profile.style.fontID = font
        return StyleTabModel(profile: profile,
                             recentColorsStore: RecentColorsStore(defaults: defaults),
                             fontLibrary: library,
                             applyFont: { applied(AppliedFont(fontID: $0, profileID: $1)) },
                             allProfiles: { [] },
                                     updateProfile: spy.update)
    }

    private func listFonts(_ model: StyleTabModel) -> [OverlayFontID] {
        model.fontList.sections.flatMap(\.cells).map(\.fontID)
    }

    func testListShowsEveryFontOnceAndTheDownloadedOnesFirst() {
        let model = makeFontModel(library: FakeFontLibrary([.xingkai: .available]))
        XCTAssertEqual(listFonts(model).count, OverlayFontID.allCases.count, "56.1")
        XCTAssertEqual(model.fontList.sections.first?.cells.map(\.fontID), [.pingFang, .xingkai], "56.1")
    }

    func testTappingAnAvailableCellAppliesOnceThroughApplyFontAndWritesNothing() {
        var applied: [AppliedFont] = []
        let spy = Spy()
        let model = makeFontModel(library: FakeFontLibrary([.huninn: .available]),
                                  applied: { applied.append($0) }, spy: spy)
        model.fontList.didTap(.huninn)
        XCTAssertEqual(applied, [AppliedFont(fontID: .huninn, profileID: model.profile.id)], "34.6")
        XCTAssertTrue(spy.updated.isEmpty, "34.6: the model does not write fontID itself")
        XCTAssertEqual(model.profile.style.fontID, .pingFang, "34.6")
    }

    func testListCellTapUsesTheSameApplyFontWithTheCurrentProfile() {
        var applied: [AppliedFont] = []
        let model = makeFontModel(library: FakeFontLibrary(), applied: { applied.append($0) })
        model.fontList.didTap(.songti)
        XCTAssertEqual(applied, [AppliedFont(fontID: .songti, profileID: model.profile.id)], "34.6")
    }

    func testApplyExternalChangesTakesTheFontAndTheNextColorEditKeepsIt() {
        let spy = Spy()
        let model = makeFontModel(library: FakeFontLibrary(), spy: spy)
        var latest = model.profile
        latest.style.fontID = .xingkai
        model.applyExternalChanges(from: latest)
        XCTAssertEqual(model.profile.style.fontID, .xingkai)
        XCTAssertTrue(spy.updated.isEmpty, "applyExternalChanges does not persist")

        model.selectTextColor(OverlayStyle.swatches[2])
        XCTAssertEqual(spy.updated.last?.style.fontID, .xingkai, "34.6a")
        XCTAssertEqual(spy.updated.last?.style.textColor, OverlayStyle.swatches[2], "34.6a")
    }

    func testApplyExternalChangesIgnoresAnotherProfileAndOtherStyleFields() {
        let spy = Spy()
        let model = makeFontModel(library: FakeFontLibrary(), spy: spy)
        var other = CameraProfile(name: "別人", startDate: DateComponents(year: 2026, month: 1, day: 1))
        other.style.fontID = .xingkai
        model.applyExternalChanges(from: other)
        XCTAssertEqual(model.profile.style.fontID, .pingFang)

        var latest = model.profile
        latest.style.fontID = .huninn
        latest.style.sizeScale = 150
        model.applyExternalChanges(from: latest)
        XCTAssertEqual(model.profile.style.fontID, .huninn)
        XCTAssertNotEqual(model.profile.style.sizeScale, 150, "the style tab owns the other style fields")
    }

    func testListFollowsExternalFontChanges() {
        let model = makeFontModel(library: FakeFontLibrary())
        var latest = model.profile
        latest.style.fontID = .xingkai
        model.applyExternalChanges(from: latest)
        XCTAssertEqual(model.fontList.currentFontID, .xingkai)
    }

    // MARK: - TASK-89 字重 (89.3 to 89.5)

    private func makeWeightModel(library: FakeFontLibrary,
                                 font: OverlayFontID = .notoSerifTC,
                                 weight: String? = nil,
                                 spy: Spy = Spy()) -> StyleTabModel {
        var profile = CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1))
        profile.style.fontID = font
        if let weight { profile.style.fontWeight = weight }
        return StyleTabModel(profile: profile,
                             recentColorsStore: RecentColorsStore(defaults: defaults),
                             fontLibrary: library,
                             applyFont: { _, _ in },
                             allProfiles: { [] },
                             updateProfile: spy.update)
    }

    func testTappingAnAvailableWeightWritesItAndSavesTheProfile() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        library.weightStates[FontDownloadID(fontID: .notoSerifTC, weightID: "black")] = .available
        let spy = Spy()
        let model = makeWeightModel(library: library, spy: spy)
        model.fontList.listDidAppear()
        model.fontList.didTapWeight("black")
        XCTAssertEqual(model.profile.style.fontWeight, "black", "89.3")
        XCTAssertEqual(spy.updated.last?.style.fontWeight, "black", "89.3 存進設定檔")
        XCTAssertEqual(spy.updated.last?.style.fontID, .notoSerifTC)
        XCTAssertEqual(model.fontList.currentWeightID, "black", "字型頁選取跟著設定檔")
    }

    func testAMissingWeightIsOnlyWrittenAfterItsDownloadFinishes() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let unit = FontDownloadID(fontID: .notoSerifTC, weightID: "black")
        let spy = Spy()
        let model = makeWeightModel(library: library, spy: spy)
        model.fontList.didTapWeight("black")
        XCTAssertEqual(model.profile.style.fontWeight, "bold", "89.5 下載中保留舊字重")
        XCTAssertTrue(spy.updated.isEmpty, "89.5 下載中不寫設定檔")
        library.weightStates[unit] = .available
        library.weightDownloadDidFinish.send(unit)
        XCTAssertEqual(model.profile.style.fontWeight, "black", "89.5 完成後才套用")
        XCTAssertEqual(spy.updated.last?.style.fontWeight, "black")
    }

    func testAFailedWeightKeepsTheOldOneInTheSavedProfile() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let unit = FontDownloadID(fontID: .notoSerifTC, weightID: "black")
        let spy = Spy()
        let model = makeWeightModel(library: library, spy: spy)
        model.fontList.listDidAppear()
        model.fontList.didTapWeight("black")
        library.weightStates[unit] = .failed(.other)
        model.fontList.libraryDidChange()
        XCTAssertEqual(model.profile.style.fontWeight, "bold", "89.5")
        XCTAssertTrue(spy.updated.isEmpty)
    }

    func testASaveFailureAfterTheDownloadKeepsTheOldWeightAndShowsFailure() {
        struct SaveError: Error {}
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let unit = FontDownloadID(fontID: .notoSerifTC, weightID: "black")
        let spy = Spy()
        let model = makeWeightModel(library: library, spy: spy)
        model.fontList.listDidAppear()
        model.fontList.didTapWeight("black")
        spy.shouldThrow = SaveError()
        library.weightStates[unit] = .available
        library.weightDownloadDidFinish.send(unit)
        XCTAssertEqual(model.profile.style.fontWeight, "bold", "存檔失敗保留原字重")
        XCTAssertEqual(model.fontList.currentWeightID, "bold")
        XCTAssertNil(model.fontList.pendingWeight, "pending 清除")
        XCTAssertEqual(model.fontList.toast?.text, FontLibraryModel.weightSaveFailedMessage, "顯示失敗而非已套用")
        XCTAssertNotNil(model.lastError)
        XCTAssertTrue(spy.updated.isEmpty)
        // The next edit does not write the unsaved weight back.
        spy.shouldThrow = nil
        model.selectTextColor(OverlayStyle.swatches[2])
        XCTAssertEqual(spy.updated.last?.style.fontWeight, "bold")
    }

    func testASaveFailureOnAnAvailableWeightKeepsTheOldOneAndShowsFailure() {
        struct SaveError: Error {}
        let library = FakeFontLibrary([.notoSerifTC: .available])
        library.weightStates[FontDownloadID(fontID: .notoSerifTC, weightID: "regular")] = .available
        let spy = Spy()
        let model = makeWeightModel(library: library, spy: spy)
        spy.shouldThrow = SaveError()
        model.fontList.didTapWeight("regular")
        XCTAssertEqual(model.profile.style.fontWeight, "bold")
        XCTAssertEqual(model.fontList.toast?.text, FontLibraryModel.weightSaveFailedMessage)
    }

    // MARK: - TASK-115 (#446) font and weight in one save

    /// 115.3: the font and the weight reach the store in a single write.
    func testApplyFontWithWeightSavesOnce() {
        let library = FakeFontLibrary([.notoSerifTC: .available, .songti: .available])
        library.weightStates[FontDownloadID(fontID: .songti, weightID: "light")] = .available
        let spy = Spy()
        let model = makeWeightModel(library: library, spy: spy)
        model.fontList.listDidAppear()
        model.fontList.didTapWeight("light", of: .songti)
        XCTAssertEqual(spy.updated.count, 1, "115.3 一次寫入，不先存預設字重")
        XCTAssertEqual(spy.updated.last?.style.fontID, .songti)
        XCTAssertEqual(spy.updated.last?.style.fontWeight, "light")
        XCTAssertEqual(model.profile.style.fontID, .songti)
        XCTAssertEqual(model.fontList.currentFontID, .songti, "字型頁選取跟著設定檔")
        XCTAssertEqual(model.fontList.currentWeightID, "light")
    }

    /// 115.7: after the download finishes, the font and weight are saved once.
    func testDownloadedWeightOfAnotherFontIsSavedOnceTogether() {
        let library = FakeFontLibrary([.notoSerifTC: .available])
        let unit = FontDownloadID(fontID: .songti, weightID: "light")
        let spy = Spy()
        let model = makeWeightModel(library: library, spy: spy)
        model.fontList.listDidAppear()
        model.fontList.didTapWeight("light", of: .songti)
        XCTAssertTrue(spy.updated.isEmpty, "下載中不寫設定檔")
        XCTAssertEqual(model.profile.style.fontID, .notoSerifTC)
        library.weightStates[unit] = .available
        library.weightDownloadDidFinish.send(unit)
        XCTAssertEqual(spy.updated.count, 1)
        XCTAssertEqual(spy.updated.last?.style.fontID, .songti)
        XCTAssertEqual(spy.updated.last?.style.fontWeight, "light")
    }

    /// A failed save restores both the font and the weight.
    func testFailedFontWithWeightSaveRestoresBoth() {
        struct SaveError: Error {}
        let library = FakeFontLibrary([.notoSerifTC: .available, .songti: .available])
        library.weightStates[FontDownloadID(fontID: .songti, weightID: "light")] = .available
        let spy = Spy()
        let model = makeWeightModel(library: library, weight: "black", spy: spy)
        model.fontList.listDidAppear()
        spy.shouldThrow = SaveError()
        model.fontList.didTapWeight("light", of: .songti)
        XCTAssertEqual(model.profile.style.fontID, .notoSerifTC, "字型回復")
        XCTAssertEqual(model.profile.style.fontWeight, "black", "字重回復")
        XCTAssertEqual(model.fontList.currentFontID, .notoSerifTC)
        XCTAssertEqual(model.fontList.currentWeightID, "black")
        XCTAssertEqual(model.fontList.toast?.text, FontLibraryModel.weightSaveFailedMessage)
        XCTAssertNotNil(model.lastError)
        XCTAssertTrue(spy.updated.isEmpty)
    }

    func testApplyFontWithWeightForTheCurrentFontIsAWeightChangeAndRejectsUnknownWeights() {
        let spy = Spy()
        let model = makeWeightModel(library: FakeFontLibrary([.notoSerifTC: .available]), spy: spy)
        XCTAssertFalse(model.applyFont(.songti, weightID: "nope"))
        XCTAssertTrue(spy.updated.isEmpty)
        XCTAssertTrue(model.applyFont(.notoSerifTC, weightID: "regular"))
        XCTAssertEqual(spy.updated.count, 1)
        XCTAssertEqual(spy.updated.last?.style.fontWeight, "regular")
    }

    func testApplyFontWeightIgnoresOtherFontsUnknownIDsAndTheCurrentWeight() {
        let spy = Spy()
        let model = makeWeightModel(library: FakeFontLibrary([.notoSerifTC: .available]), spy: spy)
        model.applyFontWeight("light", for: .songti)
        model.applyFontWeight("nope", for: .notoSerifTC)
        model.applyFontWeight("bold", for: .notoSerifTC)
        XCTAssertTrue(spy.updated.isEmpty)
        XCTAssertEqual(model.profile.style.fontWeight, "bold")
    }

    func testApplyExternalChangesTakesTheWeightAndAFontChangeResetsIt() {
        let spy = Spy()
        let model = makeWeightModel(library: FakeFontLibrary(), weight: "black", spy: spy)
        // Another writer changed the weight only.
        var latest = model.profile
        latest.style.fontWeight = "regular"
        model.applyExternalChanges(from: latest)
        XCTAssertEqual(model.profile.style.fontWeight, "regular", "89.3")
        XCTAssertEqual(model.fontList.currentWeightID, "regular")
        // Changing the font resets to the new font's default weight (89.4).
        var other = model.profile
        other.style.fontID = .huninn
        model.applyExternalChanges(from: other)
        XCTAssertEqual(model.profile.style.fontID, .huninn)
        XCTAssertEqual(model.profile.style.fontWeight, "regular", "89.4 芫荽預設字重")
        // Switching back lands on Noto's default, not on the old choice.
        var back = model.profile
        back.style.fontID = .notoSerifTC
        model.applyExternalChanges(from: back)
        XCTAssertEqual(model.profile.style.fontWeight, "bold", "89.4 換回思源宋體為預設字重")
        XCTAssertTrue(spy.updated.isEmpty, "applyExternalChanges does not persist")
        model.selectTextColor(OverlayStyle.swatches[2])
        XCTAssertEqual(spy.updated.last?.style.fontWeight, "bold", "下一次改色不會寫回舊字重")
    }

    func testResolvedFontForTheProfileUsesItsWeight() {
        // PingFang is built in, so its light face really resolves.
        let model = makeWeightModel(library: FakeFontLibrary(), font: .pingFang, weight: "light")
        XCTAssertEqual(model.resolvedFont(ofSize: 15).fontName, "PingFangTC-Light")
        XCTAssertEqual(model.resolvedFont(ofSize: 15, for: .pingFang).fontName, "PingFangTC-Light")
    }

    func testFontLibraryModelIsOnlyReachableWhileTheListIsOnScreen() {
        let model = makeFontModel(library: FakeFontLibrary())
        XCTAssertNil(model.fontLibraryModel)
        model.fontList.listDidAppear()
        XCTAssertTrue(model.fontLibraryModel === model.fontList)
        model.fontList.listDidDisappear()
        XCTAssertNil(model.fontLibraryModel)
    }

    func testResolvedFontIsPingFangUnlessTheFontIsAvailable() {
        let notReady = makeFontModel(library: FakeFontLibrary([.xingkai: .notDownloaded]), font: .xingkai)
        XCTAssertEqual(notReady.resolvedFont(ofSize: 15).fontName, FontCatalog.pingFangPostScriptName)
    }

    func testWithoutAnInjectedLibraryOnlyPingFangIsUsable() {
        let model = makeModel()
        XCTAssertEqual(model.fontList.sections.first?.cells.map(\.fontID), [.pingFang])
    }

    // MARK: - 23.4 文字顏色第一排：9 色

    func testTextColorSwatchesAreTheNinePresetsInOrder() {
        let model = makeModel()
        XCTAssertEqual(model.textColorSwatches, OverlayStyle.swatches, "23.4")
        XCTAssertEqual(model.textColorSwatches.count, 9, "23.4")
    }

    // MARK: - TASK-149 (#518) 文字顏色的淺色列

    /// 149.5: the text page's light row, column for column; outline and
    /// shadow keep their one row (149.8, `outlineColorSwatches` unchanged).
    func testTextColorHasALightRow() {
        let model = makeModel()
        XCTAssertEqual(model.textColorLightSwatches, OverlayStyle.lightSwatches, "149.5")
        XCTAssertEqual(model.textColorLightSwatches.count, model.textColorSwatches.count, "149.5 nine columns")
        XCTAssertEqual(model.outlineColorSwatches, OverlayStyle.swatches, "149.8")
    }

    /// 149.6: a light swatch is applied fully opaque and never enters 最近.
    func testSelectingALightSwatchIsOpaqueAndNotRecent() throws {
        let store = RecentColorsStore(defaults: defaults)
        let model = makeModel(store: store)
        model.applyCustomTextColor(try hex("#12345680"))
        for preset in OverlayStyle.lightSwatches {
            model.selectTextColor(preset)
            XCTAssertEqual(model.profile.style.textColor, preset, "149.6 \(preset.hexString)")
            XCTAssertEqual(model.profile.style.textColor.opacity, 1, "149.6 opaque")
            model.commitCustomColor(preset)
        }
        XCTAssertTrue(store.recentCustomColors.isEmpty, "149.6 最近 unchanged")
    }

    // MARK: - 23.5 外框顏色第一排：自動 + 9 色，初始選中自動

    func testOutlineColorSwatchesAreAllPresetsAndAutoIsInitiallySelected() {
        let model = makeModel()
        XCTAssertEqual(model.outlineColorSwatches, OverlayStyle.swatches, "23.5")
        XCTAssertEqual(model.outlineColorSwatches.count, 9, "23.5")
        XCTAssertNil(model.profile.style.outlineColor, "23.5: 初始選中「自動」")
    }

    // MARK: - 23.6 ColorPicker 選色：寫入、加入最近、文字與外框共用

    func testCommitCustomColorAddsRecentAndIsSharedWithOutline() throws {
        let store = RecentColorsStore(defaults: defaults)
        let model = makeModel(store: store)
        let picked = try hex("#123456")

        model.applyCustomTextColor(picked)
        model.commitCustomColor(picked)

        XCTAssertEqual(model.profile.style.textColor, picked, "23.6")
        XCTAssertEqual(model.recentColors.first, picked, "23.6")
        XCTAssertEqual(store.recentCustomColors.first, picked, "23.6: 外框顏色的「最近」排也出現它")
    }

    // MARK: - 53.6 拖曳中只套用、關閉時才記錄

    func testApplyingIntermediateColorsDoesNotTouchRecentUntilCommit() throws {
        let store = RecentColorsStore(defaults: defaults)
        let model = makeModel(store: store)
        let steps = try ["#111111", "#222222", "#333333"].map { try hex($0) }

        for color in steps { model.applyCustomTextColor(color) }
        XCTAssertEqual(model.profile.style.textColor, steps.last, "53.2: 即時預覽")
        XCTAssertTrue(store.recentCustomColors.isEmpty, "53.6: 只套用不新增")

        model.commitCustomColor(try XCTUnwrap(steps.last))
        XCTAssertEqual(store.recentCustomColors, [steps[2]], "53.6: 只新增最終色")
    }

    func testApplyingOutlineColorDoesNotTouchRecent() throws {
        let store = RecentColorsStore(defaults: defaults)
        let model = makeModel(store: store)
        let color = try hex("#444444")

        model.applyCustomOutlineColor(color)

        XCTAssertEqual(model.profile.style.outlineColor, color, "53.4")
        XCTAssertTrue(store.recentCustomColors.isEmpty, "53.4/53.6")
    }

    func testCommitPresetColorIsIgnoredByRecent() {
        let store = RecentColorsStore(defaults: defaults)
        let model = makeModel(store: store)

        model.commitCustomColor(OverlayStyle.swatches[0])

        XCTAssertTrue(store.recentCustomColors.isEmpty, "53.5")
    }

    // MARK: - 23.7 外框為「無」時外框顏色整塊 disabled

    func testOutlineColorSectionDisabledOnlyWhenOutlineIsNone() {
        let model = makeModel()
        XCTAssertTrue(model.isOutlineColorSectionDisabled, "23.7: 預設 outline 為 .none")
        model.selectOutline(.stroke)
        XCTAssertFalse(model.isOutlineColorSectionDisabled, "23.7")
        model.selectOutline(.none)
        XCTAssertTrue(model.isOutlineColorSectionDisabled, "23.7")
    }

    // MARK: - 23.8 外框、陰影都選無

    func testOutlineAndShadowBothNoneWritesSuccessfullyWithNoWarningState() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.selectOutline(.none)
        model.selectShadow(.none)
        XCTAssertEqual(model.profile.style.outline, .none, "23.8")
        XCTAssertEqual(model.profile.style.shadowPreset, OverlayShadowPreset.none, "23.8")
        XCTAssertNil(model.lastError, "23.8: 沒有任何警告狀態")
    }

    // MARK: - 23.9 字級滑桿設 72 對齊步進

    func testSizeScaleSnapsToNearestStepOf72() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.setSizeScale(72)
        XCTAssertEqual(model.profile.style.sizeScale, 70, "23.9")
        XCTAssertNotEqual(model.profile.style.sizeScale, 72, "23.9")
    }

    func testSizeScaleClampsToRange() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.setSizeScale(200)
        XCTAssertEqual(model.profile.style.sizeScale, 160)
        model.setSizeScale(0)
        XCTAssertEqual(model.profile.style.sizeScale, 70)
    }

    // MARK: - 49.15 點兩下回預設字級

    func testResetSizeScaleReturnsToDefaultAndWrites() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.setSizeScale(150)
        spy.updated.removeAll()
        model.resetSizeScale()
        XCTAssertEqual(model.profile.style.sizeScale, OverlayStyle().sizeScale, "49.15")
        XCTAssertEqual(spy.updated.count, 1)
        XCTAssertEqual(spy.updated.last?.style.sizeScale, OverlayStyle().sizeScale)
    }

    func testResetSizeScaleDoesNotWriteWhenAlreadyDefault() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.resetSizeScale()
        XCTAssertTrue(spy.updated.isEmpty, "49.15")
    }

    // MARK: - 23.10 字級滑桿範圍

    func testSizeScaleRangeIs70To160StepOf5() {
        XCTAssertEqual(StyleTabModel.sizeScaleRange.lowerBound, 70, "23.10")
        XCTAssertEqual(StyleTabModel.sizeScaleRange.upperBound, 160, "23.10")
        XCTAssertEqual(StyleTabModel.sizeScaleStep, 5, "23.10")
    }

    // MARK: - 選色（非彩虹圓）與外框選項行為

    func testSelectTextColorFromSwatchPersists() throws {
        let spy = Spy()
        let model = makeModel(spy: spy)
        let swatch = try XCTUnwrap(OverlayStyle.swatches.last)
        model.selectTextColor(swatch)
        XCTAssertEqual(model.profile.style.textColor, swatch)
        XCTAssertEqual(spy.updated.last?.style.textColor, swatch)
    }

    func testSelectOutlineColorAutoSetsNil() throws {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.selectOutline(.stroke)
        model.selectOutlineColor(try hex("#0A84FF"))
        XCTAssertEqual(model.profile.style.outlineColor, try hex("#0A84FF"))
        model.selectOutlineColor(nil)
        XCTAssertNil(model.profile.style.outlineColor)
    }

    func testOutlineAndShadowOptionOrder() {
        let model = makeModel()
        XCTAssertEqual(model.outlineOptions, [.none, .stroke, .box, .squareBox], "81.1")
        XCTAssertEqual(model.shadowOptions, [.none, .soft, .hard, .glow])
    }

    /// 81.3: 底框 ↔ 直角底框 keeps the padding, color and opacity.
    func testSwitchingBetweenBoxAndSquareBoxKeepsPaddingColorAndOpacity() throws {
        let model = makeModel()
        model.selectOutline(.box)
        model.setBoxPadding(18)
        model.applyCustomOutlineColor(try hex("#123456").withOpacity(0.4))
        let before = model.profile.style
        model.selectOutline(.squareBox)
        XCTAssertEqual(model.profile.style.outline, .squareBox)
        XCTAssertEqual(model.profile.style.boxPadding, 18, "81.3")
        XCTAssertEqual(model.profile.style.outlineColor, before.outlineColor, "81.3")
        XCTAssertEqual(model.profile.style.outlineColor?.opacity ?? 0, 0.4, accuracy: 0.003, "81.3")
        model.selectOutline(.box)
        XCTAssertEqual(model.profile.style.boxPadding, 18, "81.3")
        XCTAssertEqual(model.profile.style.outlineColor, before.outlineColor, "81.3")
    }

    /// 81.4: the square box choice survives a restart.
    func testSquareBoxSurvivesTheProfileFile() throws {
        let model = makeModel()
        model.selectOutline(.squareBox)
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(model.profile))
        XCTAssertEqual(decoded.style.outline, .squareBox, "81.4")
    }

    // MARK: - 失敗回報為 lastError

    func testUpdateProfileFailureIsSurfacedAsLastError() {
        let spy = Spy()
        struct DummyError: Error {}
        spy.shouldThrow = DummyError()
        let model = makeModel(spy: spy)
        model.selectTextColor(OverlayStyle.swatches[2])
        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(model.profile.style.textColor, OverlayStyle.swatches[2])
    }

    // MARK: - 透明度只從色盤設定（TASK-69 → TASK-113）

    /// 113.3: a swatch or recent color is always fully opaque, whatever the
    /// text's opacity was.
    func testSwatchAndRecentSelectionResetTextOpacity() throws {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.applyCustomTextColor(try hex("#123456").withOpacity(0.5))
        XCTAssertEqual(model.profile.style.textColor.opacity, 0.5, accuracy: 0.003)

        model.selectTextColor(OverlayStyle.swatches[3])

        XCTAssertEqual(model.profile.style.textColor, OverlayStyle.swatches[3].withOpacity(1), "113.3")
        XCTAssertEqual(spy.updated.last?.style.textColor, OverlayStyle.swatches[3].withOpacity(1), "即時寫入")
    }

    /// 113.4: an outline swatch and "automatic" are fully opaque.
    func testOutlineSwatchAndAutomaticResetOutlineOpacity() throws {
        let model = makeModel()
        model.selectOutline(.stroke)
        model.applyCustomOutlineColor(try hex("#654321").withOpacity(0.4))
        XCTAssertEqual(model.profile.style.outlineColor?.opacity ?? 0, 0.4, accuracy: 0.003)

        model.selectOutlineColor(try hex("#123456"))
        XCTAssertEqual(model.profile.style.outlineColor, try hex("#123456"), "113.4 色票")
        XCTAssertEqual(model.profile.style.outlineColor?.opacity, 1, "113.4 色票")

        model.applyCustomOutlineColor(try hex("#654321").withOpacity(0.4))
        model.selectOutlineColor(nil)
        XCTAssertNil(model.profile.style.outlineColor, "113.4 自動")
        XCTAssertEqual(model.profile.style.resolvedOutlineColor.opacity, 1, "113.4 自動不透明")
        XCTAssertEqual(model.profile.style.textColor.opacity, 1, "文字不受影響")
    }

    /// 113.2 / 69.4: the picker's alpha is kept, raised to the storable
    /// minimum, and written through at once.
    func testCustomPickerAlphaIsClampedToTheMinimumAndKept() throws {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.applyCustomTextColor(try hex("#123456").withOpacity(0.5))
        XCTAssertEqual(model.profile.style.textColor.opacity, 0.5, accuracy: 0.003, "113.2")
        XCTAssertEqual(spy.updated.last?.style.textColor, model.profile.style.textColor, "即時寫入")
        XCTAssertTrue(model.profile.style.textColor.isStorable)
        model.applyCustomTextColor(try hex("#123456").withOpacity(0.01))
        XCTAssertEqual(model.profile.style.textColor.opacity, OverlayColor.minimumStorableOpacity, "69.4")
        model.applyCustomOutlineColor(try hex("#654321").withOpacity(0))
        XCTAssertEqual(model.profile.style.outlineColor?.opacity, OverlayColor.minimumStorableOpacity, "69.4")
    }

    func testRecentColorsRememberRGBOnly() throws {
        let store = RecentColorsStore(defaults: defaults)
        let model = makeModel(store: store)
        model.commitCustomColor(try hex("#123456").withOpacity(0.5))
        XCTAssertEqual(model.recentColors, [try hex("#123456")])
    }

    /// 69.3 / 113.7: a picker opacity survives the profile file and is not
    /// changed by merely loading it.
    func testOpacityRoundTripsThroughTheProfileFile() throws {
        let model = makeModel()
        model.applyCustomTextColor(try hex("#123456").withOpacity(0.5))
        let encoded = try JSONEncoder().encode(model.profile)
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: encoded)
        XCTAssertEqual(decoded.style.textColor.opacity, 0.5, accuracy: 0.003, "69.3")
    }

    // MARK: - TASK-70 外框粗細／留白

    func testStrokeWidthWritesThroughSnapsAndClamps() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.setStrokeWidth(3.7)
        XCTAssertEqual(model.profile.style.strokeWidth, 3.5, "70.3")
        XCTAssertEqual(spy.updated.last?.style.strokeWidth, 3.5, "70.3: 即時寫入")
        model.setStrokeWidth(0)
        XCTAssertEqual(model.profile.style.strokeWidth, 1, "70.4")
        model.setStrokeWidth(99)
        XCTAssertEqual(model.profile.style.strokeWidth, 6, "70.4")
        XCTAssertTrue(model.profile.style.hasValidOutlineParameters)
    }

    func testBoxPaddingWritesThroughSnapsAndClamps() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.setBoxPadding(8.4)
        XCTAssertEqual(model.profile.style.boxPadding, 8, "70.3")
        XCTAssertEqual(spy.updated.last?.style.boxPadding, 8, "70.3: 即時寫入")
        model.setBoxPadding(-5)
        XCTAssertEqual(model.profile.style.boxPadding, 0, "70.4")
        model.setBoxPadding(99)
        XCTAssertEqual(model.profile.style.boxPadding, 24, "70.4")
        XCTAssertTrue(model.profile.style.hasValidOutlineParameters)
    }

    func testOutlineParametersSurviveSwitchingOutlineAndRoundTrip() throws {
        let model = makeModel()
        model.setStrokeWidth(5)
        model.setBoxPadding(20)
        model.selectOutline(.box)
        model.selectOutline(.stroke)
        XCTAssertEqual(model.profile.style.strokeWidth, 5)
        XCTAssertEqual(model.profile.style.boxPadding, 20)
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(model.profile))
        XCTAssertEqual(decoded.style.strokeWidth, 5, "70.4")
        XCTAssertEqual(decoded.style.boxPadding, 20, "70.4")
    }

    // MARK: - TASK-71 陰影參數

    private func customShadowProfile() -> CameraProfile {
        var profile = CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1))
        profile.style.shadowOffsetX = -3
        profile.style.shadowOffsetY = 3
        profile.style.shadowBlur = 3
        return profile
    }

    func testPresetFillsParametersAndCustomParametersShowNoSelection() {
        let model = makeModel()
        model.selectShadow(.hard)
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "71.3")
        XCTAssertEqual(model.profile.style.shadowOffsetX, 2, "71.3")
        XCTAssertEqual(model.profile.style.shadowBlur, 0, "71.3")
        let custom = makeModel(profile: customShadowProfile())
        XCTAssertNil(custom.profile.style.shadowPreset, "118.5: 自訂參數不顯示選中")
        custom.selectShadow(.hard)
        XCTAssertEqual(custom.profile.style.shadowPreset, .hard, "118.5")
        XCTAssertEqual(custom.profile.style.shadowBlur, 0, "118.5")
    }

    func testCustomShadowParametersAreKeptUntilAPresetIsTapped() {
        let spy = Spy()
        let profile = customShadowProfile()
        let model = makeModel(profile: profile, spy: spy)
        model.selectShadowColor(OverlayStyle.swatches[2])
        XCTAssertEqual(model.profile.style.shadowOffsetX, profile.style.shadowOffsetX, "118.5")
        XCTAssertEqual(model.profile.style.shadowOffsetY, profile.style.shadowOffsetY, "118.5")
        XCTAssertEqual(model.profile.style.shadowBlur, profile.style.shadowBlur, "118.5")
        XCTAssertEqual(spy.updated.last?.style.shadowBlur, profile.style.shadowBlur)
        XCTAssertTrue(model.profile.style.hasValidShadowParameters)
    }

    func testShadowPickerOpacityIsClampedAndKeepsTheColor() {
        let model = makeModel()
        model.selectShadow(.soft)
        model.applyCustomShadowColor(OverlayColor.black.withOpacity(0))
        XCTAssertEqual(model.profile.style.shadowOpacity, OverlayColor.minimumStorableOpacity)
        model.applyCustomShadowColor(OverlayColor.black.withOpacity(0.4))
        XCTAssertEqual(model.profile.style.shadowOpacity, 0.4, accuracy: 0.003)
        XCTAssertEqual(model.profile.style.shadowColor.red, 0)
    }

    /// 113.5: a shadow swatch or "follow the text color" resets the opacity
    /// to the default shadow's 60%; the picker alone sets another value.
    func testShadowSwatchAndFollowTextResetOpacityToTheDefault() {
        let model = makeModel()
        model.selectShadow(.soft)
        model.applyCustomShadowColor(OverlayStyle.swatches[2].withOpacity(0.3))
        XCTAssertEqual(model.profile.style.shadowOpacity, 0.3, accuracy: 0.003)

        model.selectShadowColor(OverlayStyle.swatches[5])
        XCTAssertEqual(model.profile.style.shadowOpacity, 153.0 / 255, accuracy: 0.003, "113.5 色票")
        XCTAssertEqual(StyleTabModel.swatchShadowOpacity, 153.0 / 255, accuracy: 0.003)
        XCTAssertTrue(StyleTabModel.hasSameRGB(model.profile.style.shadowColor, OverlayStyle.swatches[5]))
        XCTAssertEqual(model.profile.style.shadowColorSource, .custom)

        model.applyCustomShadowColor(OverlayStyle.swatches[2].withOpacity(0.3))
        model.selectShadowColor(nil)
        XCTAssertEqual(model.profile.style.shadowColorSource, .textColor)
        XCTAssertEqual(model.profile.style.shadowOpacity, 153.0 / 255, accuracy: 0.003, "113.5 跟隨文字顏色")

        model.applyCustomShadowColor(OverlayStyle.swatches[2].withOpacity(0.3))
        XCTAssertEqual(model.profile.style.shadowOpacity, 0.3, accuracy: 0.003, "113.5 色盤")
        XCTAssertEqual(model.profile.style.shadowColorSource, .custom)
    }

    func testSelectingGlowKeepsTheChosenColorAndOpacity() {
        let model = makeModel()
        model.selectShadow(.soft)
        model.applyCustomShadowColor(OverlayStyle.swatches[5].withOpacity(0.35))
        let before = model.profile.style
        model.selectShadow(.glow)
        XCTAssertEqual(model.profile.style.shadowColorSource, before.shadowColorSource, "86.1")
        XCTAssertEqual(model.profile.style.shadowColor, before.shadowColor, "86.1")
        XCTAssertEqual(model.profile.style.shadowOpacity, 0.35, accuracy: 0.003, "86.1")
        model.selectShadowColor(nil)
        XCTAssertEqual(model.profile.style.shadowColorSource, .textColor)
        model.selectTextColor(OverlayStyle.swatches[3])
        XCTAssertTrue(StyleTabModel.hasSameRGB(model.profile.style.resolvedShadowColor, OverlayStyle.swatches[3]))
    }

    func testSwitchingPresetsKeepsColorAndOpacityAndOnlyChangesShape() {
        let model = makeModel()
        model.selectShadow(.soft)
        model.applyCustomShadowColor(OverlayStyle.swatches[5].withOpacity(0.4))
        let color = model.profile.style.shadowColor
        for preset in [OverlayShadowPreset.hard, .glow, .soft] {
            model.selectShadow(preset)
            XCTAssertEqual(model.profile.style.shadowPreset, preset, "86.1")
            XCTAssertEqual(model.profile.style.shadowColor, color, "86.1")
            XCTAssertEqual(model.profile.style.shadowColorSource, .custom, "86.1")
            XCTAssertEqual(model.profile.style.shadowOpacity, 0.4, accuracy: 0.003, "86.1 / 113.8")
        }
    }

    func testChangingColorOrOpacityKeepsThePresetSelected() {
        let model = makeModel()
        model.selectShadow(.hard)
        model.selectShadowColor(OverlayStyle.swatches[5])
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2 色票")
        model.applyCustomShadowColor(OverlayStyle.swatches[2].withOpacity(0.5))
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2 自訂")
        model.selectShadowColor(nil)
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2 跟隨文字色")
        model.applyCustomShadowColor(OverlayStyle.swatches[2].withOpacity(0.2))
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2 色盤不透明度")
    }

    func testNoneKeepsColorAndShapeAndNextPresetReusesTheColor() {
        let model = makeModel()
        model.selectShadow(.hard)
        model.selectShadowColor(OverlayStyle.swatches[5])
        let before = model.profile.style
        model.selectShadow(.none)
        XCTAssertFalse(model.profile.style.showsShadow)
        XCTAssertEqual(model.profile.style.shadowColor, before.shadowColor, "86.4")
        XCTAssertEqual(model.profile.style.shadowOffsetX, before.shadowOffsetX, "86.4")
        XCTAssertEqual(model.profile.style.shadowBlur, before.shadowBlur, "86.4")
        model.selectShadow(.glow)
        XCTAssertEqual(model.profile.style.shadowColor, before.shadowColor, "86.4")
        XCTAssertEqual(model.profile.style.shadowColorSource, .custom, "86.4")
    }

    func testShadowColorIsDisabledOnlyWhileTheShadowIsOff() {
        let model = makeModel()
        model.selectShadow(.none)
        XCTAssertTrue(model.isShadowColorDisabled)
        model.selectShadow(.soft)
        XCTAssertFalse(model.isShadowColorDisabled)
    }

    func testShadowParametersRoundTrip() throws {
        let model = makeModel(profile: customShadowProfile())
        model.applyCustomShadowColor(OverlayColor.black.withOpacity(0.35))
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(model.profile))
        XCTAssertEqual(decoded.style.shadowOffsetX, -3, "71.5")
        XCTAssertEqual(decoded.style.shadowBlur, 3, "71.5")
        XCTAssertEqual(decoded.style.shadowOpacity, 0.35, accuracy: 0.003, "71.5")
    }
}
