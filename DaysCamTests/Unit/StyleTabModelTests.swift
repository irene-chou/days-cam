import XCTest
@testable import DaysCam

/// Covers `StyleTabModel`'s state transitions: the row of looks and the box
/// button (#678), the text color and the size (PRD 0.2 FR-10).
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

    // MARK: - 34.6a 其他寫入者改的字型（PRD 0.3 FR-5.18）

    private struct AppliedFont: Equatable {
        let fontID: OverlayFontID
        let profileID: UUID
    }

    private func makeFontModel(library: FakeFontLibrary,
                               font: OverlayFontID = .pingFang,
                               weight: String? = nil,
                               applied: @escaping (AppliedFont) -> Void = { _ in },
                               spy: Spy = Spy()) -> StyleTabModel {
        var profile = CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1))
        profile.style.fontID = font
        if let weight { profile.style.fontWeight = weight }
        return StyleTabModel(profile: profile,
                             recentColorsStore: RecentColorsStore(defaults: defaults),
                             fontLibrary: library,
                             applyFont: { applied(AppliedFont(fontID: $0, profileID: $1)) },
                             allProfiles: { [] },
                                     updateProfile: spy.update)
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

    func testApplyExternalChangesTakesTheWeightAndAFontChangeResetsIt() {
        let spy = Spy()
        let model = makeFontModel(library: FakeFontLibrary(), font: .notoSerifTC, weight: "black", spy: spy)
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

    /// 149.5: the text page's light row, column for column.
    func testTextColorHasALightRow() {
        let model = makeModel()
        XCTAssertEqual(model.textColorLightSwatches, OverlayStyle.lightSwatches, "149.5")
        XCTAssertEqual(model.textColorLightSwatches.count, model.textColorSwatches.count, "149.5 nine columns")
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

    // MARK: - 23.6 ColorPicker 選色：寫入、加入最近

    func testCommitCustomColorAddsRecent() throws {
        let store = RecentColorsStore(defaults: defaults)
        let model = makeModel(store: store)
        let picked = try hex("#123456")

        model.applyCustomTextColor(picked)
        model.commitCustomColor(picked)

        XCTAssertEqual(model.profile.style.textColor, picked, "23.6")
        XCTAssertEqual(model.recentColors.first, picked, "23.6")
        XCTAssertEqual(store.recentCustomColors.first, picked, "23.6")
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

    func testCommitPresetColorIsIgnoredByRecent() {
        let store = RecentColorsStore(defaults: defaults)
        let model = makeModel(store: store)

        model.commitCustomColor(OverlayStyle.swatches[0])

        XCTAssertTrue(store.recentCustomColors.isEmpty, "53.5")
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

    // MARK: - 選色（非彩虹圓）

    func testSelectTextColorFromSwatchPersists() throws {
        let spy = Spy()
        let model = makeModel(spy: spy)
        let swatch = try XCTUnwrap(OverlayStyle.swatches.last)
        model.selectTextColor(swatch)
        XCTAssertEqual(model.profile.style.textColor, swatch)
        XCTAssertEqual(spy.updated.last?.style.textColor, swatch)
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

    // MARK: - #678 樣式列與底框鈕

    /// 678-2: the ten looks in case order; a new profile shows 經典.
    func testPresetsAreTheTenLooksAndANewProfileIsClassic() {
        let model = makeModel()
        XCTAssertEqual(model.presets, OverlayStylePreset.allCases, "678-2")
        XCTAssertEqual(model.presets.count, 10)
        XCTAssertEqual(model.selectedPreset, .classic, "678-2")
        XCTAssertEqual(model.boxState, .base)
    }

    /// 678-3: 海報 writes the look's font, weight, outline and shadow with
    /// one save; the text color and the size stay.
    func testSelectingPosterWritesTheLookOnceAndKeepsColorAndSize() throws {
        let spy = Spy()
        let model = makeFontModel(library: FakeFontLibrary(), spy: spy)
        let color = try hex("#3897F0")
        model.selectTextColor(color)
        model.setSizeScale(120)
        spy.updated.removeAll()

        model.selectPreset(.poster)

        var expected = OverlayStyle()
        expected.apply(.poster)
        let style = model.profile.style
        XCTAssertEqual(spy.updated.count, 1, "678-3 one save")
        XCTAssertEqual(spy.updated.last?.style, style, "678-3 the saved style")
        XCTAssertEqual(style.fontID, expected.fontID, "678-3")
        XCTAssertEqual(style.fontWeight, expected.fontWeight, "678-3")
        XCTAssertEqual(style.outline, expected.outline, "678-3")
        XCTAssertEqual(style.outlineColor, expected.outlineColor)
        XCTAssertEqual(style.autoOutlineOpacity, expected.autoOutlineOpacity)
        XCTAssertEqual(style.strokeWidth, expected.strokeWidth)
        XCTAssertEqual(style.boxPadding, expected.boxPadding)
        XCTAssertEqual(style.showsShadow, expected.showsShadow, "678-3")
        XCTAssertEqual(style.shadowColorSource, expected.shadowColorSource)
        XCTAssertEqual(style.shadowColor, expected.shadowColor)
        XCTAssertEqual(style.textColor, color, "678-3 color kept")
        XCTAssertEqual(style.sizeScale, 120, "678-3 size kept")
        XCTAssertEqual(model.selectedPreset, .poster)
    }

    /// 678-4: a look whose font is not downloaded is selected at once and
    /// starts the download through `applyFont`; the badge follows the
    /// library; a failure retried by tapping the look again.
    func testANotDownloadedLookIsSelectedAndDownloadsThroughApplyFont() {
        let library = FakeFontLibrary()
        let spy = Spy()
        var applied: [AppliedFont] = []
        let model = makeFontModel(library: library, applied: { applied.append($0) }, spy: spy)

        model.selectPreset(.handwriting)
        XCTAssertEqual(model.selectedPreset, .handwriting, "678-4 selected at once")
        XCTAssertEqual(applied, [AppliedFont(fontID: .chenyuluoyan, profileID: model.profile.id)], "678-4 once")
        XCTAssertEqual(model.fontState(for: .handwriting), .notDownloaded)

        library.states[.chenyuluoyan] = .downloading(progress: 0.4)
        XCTAssertEqual(model.fontState(for: .handwriting), .downloading(progress: 0.4), "678-4 the ring")
        model.selectPreset(.handwriting)
        XCTAssertEqual(applied.count, 1, "a tap while it downloads does not restart it")

        // The download finishing: `StyleEditingCenter` finds the font already
        // written and only hands the stored copy back.
        library.states[.chenyuluoyan] = .available
        model.applyExternalChanges(from: model.profile)
        XCTAssertEqual(spy.updated.last?.style.fontID, .chenyuluoyan, "678-4")
        XCTAssertEqual(spy.updated.last?.style.fontWeight, "thin", "678-4")
        XCTAssertEqual(model.fontState(for: .handwriting), .available, "678-4 no badge")

        library.states[.chenyuluoyan] = .failed(.other)
        XCTAssertEqual(model.fontState(for: .handwriting), .failed(.other), "678-4 the warning badge")
        model.selectPreset(.handwriting)
        XCTAssertEqual(applied.count, 2, "678-4 tapping again retries")
        XCTAssertEqual(spy.updated.count, 1, "a retry writes nothing")
        XCTAssertEqual(model.selectedPreset, .handwriting, "stays selected")
    }

    /// 678-5: an available font is not downloaded again.
    func testAnAvailableLookDoesNotCallApplyFont() {
        var applied: [AppliedFont] = []
        let model = makeFontModel(library: FakeFontLibrary([.chenyuluoyan: .available, .huninn: .available]),
                                  applied: { applied.append($0) })
        model.selectPreset(.handwriting)
        model.selectPreset(.neon)
        model.selectPreset(.classic)
        XCTAssertTrue(applied.isEmpty, "678-5")
        XCTAssertEqual(model.selectedPreset, .classic)
    }

    /// 思源黑體 特粗 is not the family's default face, which is all `applyFont`
    /// fetches: 海報 downloads that exact face from the library.
    func testALookOnANonDefaultFaceDownloadsThatFace() {
        let library = FakeFontLibrary([.notoSansTC: .available])
        var applied: [AppliedFont] = []
        let model = makeFontModel(library: library, applied: { applied.append($0) })
        model.selectPreset(.poster)
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(library.weightDownloads, [FontDownloadID(fontID: .notoSansTC, weightID: "black")])
        XCTAssertEqual(model.fontState(for: .poster), .downloading(progress: 0))
        model.selectPreset(.outline)
        XCTAssertEqual(library.weightDownloads.count, 1, "already downloading")
    }

    /// 678-4: a capsule's name is in the look's face once it is usable, in
    /// PingFang until then.
    func testNameFontFallsBackToPingFangUntilTheFaceIsUsable() {
        let model = makeFontModel(library: FakeFontLibrary())
        XCTAssertEqual(model.nameFont(for: .handwriting, ofSize: 15).fontName, FontCatalog.pingFangPostScriptName)
        XCTAssertEqual(model.nameFont(for: .classic, ofSize: 15).fontName, FontCatalog.pingFangPostScriptName)
    }

    /// 678-6: solid, translucent, back to the look's own outline; the look
    /// stays selected throughout (#676 Lead ruling for 經典).
    func testBoxButtonCyclesThroughTheThreeStates() {
        let spy = Spy()
        let model = makeModel(spy: spy)
        model.cycleBoxState()
        XCTAssertEqual(model.boxState, .solid, "678-6")
        XCTAssertEqual(model.profile.style.outline, .box, "678-6")
        XCTAssertEqual(model.profile.style.autoOutlineOpacity, 1, "678-6")
        model.cycleBoxState()
        XCTAssertEqual(model.boxState, .translucent, "678-6")
        XCTAssertEqual(model.profile.style.autoOutlineOpacity, 0.45, "678-6")
        XCTAssertEqual(model.selectedPreset, .classic, "#676 ruling: still 經典")
        model.cycleBoxState()
        XCTAssertEqual(model.boxState, .base, "678-6")
        XCTAssertEqual(model.profile.style.outline, .none, "678-6")
        XCTAssertEqual(spy.updated.count, 3, "each press saves")
        XCTAssertEqual(spy.updated.last?.style, model.profile.style)
    }

    /// 678-7: a style matching no look shows 自訂 with the box button off;
    /// picking a look ends it.
    func testACustomStyleHasNoPresetAndADisabledBoxButtonUntilALookIsPicked() {
        let spy = Spy()
        var profile = CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1))
        profile.style.strokeWidth = 4
        let model = makeModel(profile: profile, spy: spy)
        XCTAssertNil(model.selectedPreset, "678-7")
        XCTAssertNil(model.boxState, "678-7 disabled")
        model.cycleBoxState()
        XCTAssertTrue(spy.updated.isEmpty, "678-7 the box button does nothing")
        model.selectPreset(.classic)
        XCTAssertEqual(model.selectedPreset, .classic, "678-7")
        XCTAssertEqual(model.boxState, .base)
    }

    /// 678-8: the color and the size do not decide the look.
    func testColorAndSizeKeepTheLookSelected() throws {
        let model = makeFontModel(library: FakeFontLibrary([.huninn: .available]))
        model.selectPreset(.neon)
        model.selectTextColor(OverlayStyle.swatches[3])
        model.applyCustomTextColor(try hex("#123456").withOpacity(0.5))
        model.setSizeScale(140)
        XCTAssertEqual(model.selectedPreset, .neon, "678-8")
        model.cycleBoxState()
        XCTAssertEqual(model.selectedPreset, .neon, "678-8 box states keep it too")
    }

    /// 678-9: the font list is never on screen, so messages go to the toast.
    func testFontLibraryModelIsAlwaysNil() {
        let model = makeFontModel(library: FakeFontLibrary())
        XCTAssertNil(model.fontLibraryModel)
        model.fontList.listDidAppear()
        XCTAssertNil(model.fontLibraryModel, "678-9")
    }

    /// A failed save keeps the error for the alert.
    func testAFailedPresetSaveIsSurfaced() {
        let spy = Spy()
        struct DummyError: Error {}
        spy.shouldThrow = DummyError()
        let model = makeModel(spy: spy)
        model.selectPreset(.caption)
        XCTAssertNotNil(model.lastError)
    }
}
