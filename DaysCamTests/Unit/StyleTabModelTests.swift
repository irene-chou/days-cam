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
        model.selectOutlineColor(try hex("#123456"))
        model.setOutlineOpacityPercent(40)
        let before = model.profile.style
        model.selectOutline(.squareBox)
        XCTAssertEqual(model.profile.style.outline, .squareBox)
        XCTAssertEqual(model.profile.style.boxPadding, 18, "81.3")
        XCTAssertEqual(model.profile.style.outlineColor, before.outlineColor, "81.3")
        XCTAssertEqual(model.outlineOpacityPercent, 40, "81.3")
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

    // MARK: - TASK-69 透明度（UI 半邊）

    func testSetTextOpacityWritesThroughAndKeepsRGB() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        let before = model.profile.style.textColor

        model.setTextOpacityPercent(50)

        let stored = model.profile.style.textColor
        XCTAssertTrue(StyleTabModel.hasSameRGB(stored, before), "69.2")
        XCTAssertEqual(model.textOpacityPercent, 50, "69.2")
        XCTAssertEqual(spy.updated.last?.style.textColor, stored, "即時寫入")
        XCTAssertTrue(stored.isStorable)
    }

    func testOpacityPercentIsClampedToTheStorableRange() {
        let model = makeModel()
        model.setTextOpacityPercent(0)
        XCTAssertEqual(model.textOpacityPercent, 5, "69.4")
        XCTAssertTrue(model.profile.style.textColor.isStorable, "69.4")
        model.setTextOpacityPercent(250)
        XCTAssertEqual(model.textOpacityPercent, 100, "69.4")
        XCTAssertEqual(model.profile.style.textColor.opacity, 1)
    }

    func testSwatchAndRecentSelectionKeepTheCurrentOpacity() throws {
        let model = makeModel()
        model.setTextOpacityPercent(40)
        model.selectTextColor(OverlayStyle.swatches[3])
        XCTAssertEqual(model.textOpacityPercent, 40)
        XCTAssertTrue(StyleTabModel.hasSameRGB(model.profile.style.textColor, OverlayStyle.swatches[3]))

        model.setOutlineOpacityPercent(30)
        model.selectOutlineColor(try hex("#123456"))
        XCTAssertEqual(model.outlineOpacityPercent, 30)
    }

    func testCustomPickerAlphaIsClampedToTheMinimumAndKept() throws {
        let model = makeModel()
        model.applyCustomTextColor(try hex("#123456").withOpacity(0.5))
        XCTAssertEqual(model.textOpacityPercent, 50, "69.2: 滑桿同步")
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

    func testOutlineOpacityOnAutomaticBecomesExplicitAutomaticColor() {
        let model = makeModel()
        let resolved = model.profile.style.resolvedOutlineColor
        XCTAssertNil(model.profile.style.outlineColor)

        model.setOutlineOpacityPercent(50)

        let outline = model.profile.style.outlineColor
        XCTAssertNotNil(outline, "69.5")
        XCTAssertTrue(StyleTabModel.hasSameRGB(outline ?? .white, resolved), "69.5")
        XCTAssertEqual(model.outlineOpacityPercent, 50, "69.5")
        XCTAssertEqual(model.profile.style.textColor.opacity, 1, "文字不受影響")
    }

    func testOpacityRoundTripsThroughTheProfileFile() throws {
        let model = makeModel()
        model.setTextOpacityPercent(50)
        let encoded = try JSONEncoder().encode(model.profile)
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: encoded)
        XCTAssertEqual(StyleTabModel.opacityPercent(of: decoded.style.textColor), 50, "69.3")
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

    func testPresetFillsParametersAndAdjustingClearsTheSelection() {
        let model = makeModel()
        model.selectShadow(.hard)
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "71.3")
        XCTAssertEqual(model.profile.style.shadowOffsetX, 2, "71.3")
        XCTAssertEqual(model.profile.style.shadowBlur, 0, "71.3")
        model.setShadowBlur(3)
        XCTAssertNil(model.profile.style.shadowPreset, "71.3: 改參數後預設不再選中")
        model.selectShadow(.hard)
        XCTAssertEqual(model.profile.style.shadowPreset, .hard)
        XCTAssertEqual(model.profile.style.shadowBlur, 0)
    }

    func testShadowParametersSnapClampAndWriteThrough() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.selectShadow(.soft)
        model.setShadowOffsetX(-20)
        model.setShadowOffsetY(3.4)
        model.setShadowBlur(99)
        XCTAssertEqual(model.profile.style.shadowOffsetX, -8, "71.5")
        XCTAssertEqual(model.profile.style.shadowOffsetY, 3, "71.5")
        XCTAssertEqual(model.profile.style.shadowBlur, 16, "71.5")
        XCTAssertEqual(spy.updated.last?.style.shadowBlur, 16)
        XCTAssertTrue(model.profile.style.hasValidShadowParameters)
    }

    func testShadowOpacityIsClampedAndKeepsTheColor() {
        let model = makeModel()
        model.selectShadow(.soft)
        model.setShadowOpacityPercent(0)
        XCTAssertEqual(model.shadowOpacityPercent, 5)
        model.setShadowOpacityPercent(40)
        XCTAssertEqual(model.shadowOpacityPercent, 40)
        XCTAssertEqual(model.profile.style.shadowColor.red, 0)
    }

    func testGlowFollowsTheTextColorUntilACustomShadowColorIsPicked() {
        let model = makeModel()
        model.selectShadow(.glow)
        XCTAssertEqual(model.profile.style.shadowColorSource, .textColor, "71.4")
        model.selectTextColor(OverlayStyle.swatches[3])
        XCTAssertTrue(StyleTabModel.hasSameRGB(model.profile.style.resolvedShadowColor, OverlayStyle.swatches[3]), "71.4")
        model.selectShadowColor(OverlayStyle.swatches[5])
        XCTAssertEqual(model.profile.style.shadowColorSource, .custom)
        XCTAssertTrue(StyleTabModel.hasSameRGB(model.profile.style.resolvedShadowColor, OverlayStyle.swatches[5]))
        XCTAssertEqual(model.shadowOpacityPercent, StyleTabModel.opacityPercent(of: model.profile.style.shadowColor))
        model.selectShadowColor(nil)
        XCTAssertEqual(model.profile.style.shadowColorSource, .textColor)
    }

    func testShadowParametersAreDisabledOnlyWhileTheShadowIsOff() {
        let model = makeModel()
        model.selectShadow(.none)
        XCTAssertTrue(model.isShadowParametersDisabled)
        model.selectShadow(.soft)
        XCTAssertFalse(model.isShadowParametersDisabled)
    }

    func testShadowParametersRoundTrip() throws {
        let model = makeModel()
        model.selectShadow(.soft)
        model.setShadowOffsetX(-3)
        model.setShadowBlur(9)
        model.setShadowOpacityPercent(35)
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(model.profile))
        XCTAssertEqual(decoded.style.shadowOffsetX, -3, "71.5")
        XCTAssertEqual(decoded.style.shadowBlur, 9, "71.5")
        XCTAssertEqual(StyleTabModel.opacityPercent(of: decoded.style.shadowColor), 35, "71.5")
    }
}
