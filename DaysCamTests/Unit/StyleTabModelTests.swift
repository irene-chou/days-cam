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
                       ["字型", "顏色", "外框", "陰影", "字級"], "23.1")
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
        model.selectOutline(.thinStroke)
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
        XCTAssertEqual(model.profile.style.shadow, .none, "23.8")
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
        model.selectOutline(.thinStroke)
        model.selectOutlineColor(try hex("#0A84FF"))
        XCTAssertEqual(model.profile.style.outlineColor, try hex("#0A84FF"))
        model.selectOutlineColor(nil)
        XCTAssertNil(model.profile.style.outlineColor)
    }

    func testOutlineAndShadowOptionOrder() {
        let model = makeModel()
        XCTAssertEqual(model.outlineOptions, [.none, .thinStroke, .thickStroke, .translucentBox, .solidBox])
        XCTAssertEqual(model.shadowOptions, [.none, .soft, .hard, .glow])
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
}
