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
                     replaceFont: { _, _ in [] },
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
                             updateProfile: spy.update)
    }

    private func gridFonts(_ model: StyleTabModel) -> [OverlayFontID] {
        model.fontGridItems.compactMap {
            if case .font(let cell) = $0 { return cell.fontID }
            return nil
        }
    }

    func testGridWithOnlyPingFangIsPingFangAndMoreFonts() {
        let model = makeFontModel(library: FakeFontLibrary())
        XCTAssertEqual(gridFonts(model), [.pingFang], "34.1")
        XCTAssertEqual(model.fontGridItems.count, 2, "34.1")
        XCTAssertEqual(model.fontGridItems.last, .moreFonts, "34.1")
    }

    func testGridListsAvailableFontsInCatalogOrder() {
        // Declared out of order on purpose: the grid follows §4.1, not the states.
        let library = FakeFontLibrary([.xingkai: .available, .huninn: .available])
        let model = makeFontModel(library: library)
        XCTAssertEqual(gridFonts(model), [.pingFang, .huninn, .xingkai], "34.2")
        XCTAssertEqual(model.fontGridItems.last, .moreFonts)
    }

    func testCurrentFontThatIsNotAvailableStaysInTheGridSelectedWithItsCaption() throws {
        let cases: [(FontState, FontGridCell.Caption)] = [
            (.notDownloaded, .needsRedownload),
            (.failed(.other), .needsRedownload),
            (.preparing, .preparing),
            (.downloading(progress: 0.38), .percent("38%"))
        ]
        for (state, caption) in cases {
            let model = makeFontModel(library: FakeFontLibrary([.xingkai: state]), font: .xingkai)
            guard case .font(let cell)? = model.fontGridItems.first(where: { $0.id == "xingkai" }) else {
                return XCTFail("34.3: 行楷 should be in the grid for \(state)")
            }
            XCTAssertTrue(cell.isSelected, "34.3 \(state)")
            XCTAssertFalse(cell.usesRealFont, "34.3 \(state)")
            XCTAssertEqual(cell.caption, caption, "34.3 \(state)")
        }
    }

    func testTappingTheCurrentFontNeedingDownloadOpensTheListScrolledToIt() {
        for state in [FontState.notDownloaded, .failed(.noNetwork)] {
            let model = makeFontModel(library: FakeFontLibrary([.xingkai: state]), font: .xingkai)
            model.didTapFontCell(.xingkai)
            XCTAssertNotNil(model.fontLibraryModel, "34.3 \(state)")
            XCTAssertEqual(model.fontLibraryModel?.scrollTarget, .xingkai, "34.3 \(state)")
        }
    }

    func testTappingThePreparingOrDownloadingCurrentFontDoesNothing() {
        var applied: [AppliedFont] = []
        for state in [FontState.preparing, .downloading(progress: 0.38)] {
            let model = makeFontModel(library: FakeFontLibrary([.xingkai: state]), font: .xingkai,
                                      applied: { applied.append($0) })
            model.didTapFontCell(.xingkai)
            XCTAssertNil(model.fontLibraryModel, "34.3 \(state)")
        }
        XCTAssertTrue(applied.isEmpty, "34.3")
    }

    func testMoreFontsOpensTheList() {
        let model = makeFontModel(library: FakeFontLibrary())
        XCTAssertNil(model.fontLibraryModel)
        model.presentFontLibrary()
        XCTAssertNotNil(model.fontLibraryModel)
        XCTAssertNil(model.fontLibraryModel?.scrollTarget)
        model.dismissFontLibrary()
        XCTAssertNil(model.fontLibraryModel)
    }

    func testTappingAnAvailableCellAppliesOnceThroughApplyFontAndWritesNothing() {
        var applied: [AppliedFont] = []
        let spy = Spy()
        let model = makeFontModel(library: FakeFontLibrary([.huninn: .available]),
                                  applied: { applied.append($0) }, spy: spy)
        model.didTapFontCell(.huninn)
        XCTAssertEqual(applied, [AppliedFont(fontID: .huninn, profileID: model.profile.id)], "34.6")
        XCTAssertTrue(spy.updated.isEmpty, "34.6: the model does not write fontID itself")
        XCTAssertEqual(model.profile.style.fontID, .pingFang, "34.6")
    }

    func testListRowTapUsesTheSameApplyFontWithTheCurrentProfile() {
        var applied: [AppliedFont] = []
        let model = makeFontModel(library: FakeFontLibrary(), applied: { applied.append($0) })
        model.presentFontLibrary()
        model.fontLibraryModel?.didTapRow(.songti)
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

    func testOpenListFollowsExternalFontChanges() {
        let model = makeFontModel(library: FakeFontLibrary())
        model.presentFontLibrary()
        var latest = model.profile
        latest.style.fontID = .xingkai
        model.applyExternalChanges(from: latest)
        XCTAssertEqual(model.fontLibraryModel?.currentFontID, .xingkai)
    }

    func testResolvedFontIsPingFangUnlessTheFontIsAvailable() {
        let notReady = makeFontModel(library: FakeFontLibrary([.xingkai: .notDownloaded]), font: .xingkai)
        XCTAssertEqual(notReady.resolvedFont(ofSize: 15).fontName, FontCatalog.pingFangPostScriptName)
    }

    func testWithoutAnInjectedLibraryOnlyPingFangIsUsable() {
        let model = makeModel()
        XCTAssertEqual(gridFonts(model), [.pingFang])
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

    func testPickCustomTextColorUpdatesStyleRecentColorsAndIsSharedWithOutline() throws {
        let spy = Spy()
        let store = RecentColorsStore(defaults: defaults)
        let model = makeModel(store: store, spy: spy)
        let picked = try hex("#123456")

        model.pickCustomTextColor(picked)

        XCTAssertEqual(model.profile.style.textColor, picked, "23.6")
        XCTAssertEqual(model.recentColors.first, picked, "23.6")
        // "最近" is shared app-wide (A-8): a model built for outline color's
        // section sees the same store and therefore the same recent list.
        XCTAssertEqual(store.recentCustomColors.first, picked, "23.6: 外框顏色的「最近」排也出現它")
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
