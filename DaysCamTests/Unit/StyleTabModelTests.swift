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

    private func baselineProfile(style: OverlayStyle = OverlayStyle()) -> CameraProfile {
        CameraProfile(name: "小寶",
                     startDate: DateComponents(year: 2026, month: 1, day: 1),
                     style: style)
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
                     updateProfile: spy.update)
    }

    // MARK: - 23.1 第二層無障礙標籤

    func testSubTabAccessibilityLabelsInOrder() {
        XCTAssertEqual(StyleTabModel.SubTab.allCases.map(\.accessibilityLabel),
                       ["字型", "顏色", "外框", "陰影", "字級"], "23.1")
    }

    // MARK: - 23.2 字型選項數與順序 (同 17.1)

    func testFontOptionsMatchOrder() {
        let model = makeModel()
        XCTAssertEqual(model.fontOptions.map(\.displayName),
                       ["SF Rounded", "SF Pro", "SF Mono", "New York", "Avenir Next",
                        "Futura", "Georgia", "Typewriter", "Didot", "Snell Roundhand"], "23.2")
    }

    // MARK: - 23.3 選 Futura 後持久化

    func testSelectFontPersistsAndUpdatesProfile() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.selectFont(.futura)
        XCTAssertEqual(model.profile.style.fontID, .futura, "23.3")
        XCTAssertEqual(spy.updated.last?.style.fontID, .futura, "23.3")
    }

    func testSelectFontNoOpsWhenUnchanged() {
        let spy = Spy()
        let model = makeModel(spy: spy) // default fontID is .sfRounded
        model.selectFont(.sfRounded)
        XCTAssertTrue(spy.updated.isEmpty)
    }

    // MARK: - 23.4 文字顏色第一排：7 色

    func testTextColorSwatchesAreTheSevenPresetsInOrder() {
        let model = makeModel()
        XCTAssertEqual(model.textColorSwatches, OverlayStyle.swatches, "23.4")
        XCTAssertEqual(model.textColorSwatches.count, 7, "23.4")
    }

    // MARK: - 23.5 外框顏色第一排：自動 + 前 6 色，初始選中自動

    func testOutlineColorSwatchesAreFirstSixPresetsAndAutoIsInitiallySelected() {
        let model = makeModel()
        XCTAssertEqual(model.outlineColorSwatches, Array(OverlayStyle.swatches.prefix(6)), "23.5")
        XCTAssertEqual(model.outlineColorSwatches.count, 6, "23.5")
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
        model.selectFont(.futura)
        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(model.profile.style.fontID, .futura)
    }
}
