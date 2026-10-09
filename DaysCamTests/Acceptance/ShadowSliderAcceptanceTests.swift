import XCTest
@testable import DaysCam

/// TASK-71 ui-panel independent QA (71.3, 71.4, 71.5 UI part): the shadow
/// presets fill the parameters, a changed parameter drops the preset, glow
/// follows the text color, and values go through a real `ProfileStore` and
/// back without ever leaving their ranges.
@MainActor
final class ShadowSliderAcceptanceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ShadowSliderAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "ShadowSliderAcceptance-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeStore() throws -> ProfileStore {
        let instant = try XCTUnwrap(DateFixture.date(2026, 1, 10, hour: 10))
        return ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant }, defaults: defaults)
    }

    private func makeModel(store: ProfileStore) throws -> StyleTabModel {
        store.load()
        let profile = try XCTUnwrap(store.profiles.first)
        return StyleTabModel(profile: profile,
                             recentColorsStore: RecentColorsStore(defaults: defaults),
                             applyFont: { _, _ in },
                             allProfiles: { store.profiles },
                             updateProfile: { try? store.update($0) })
    }

    /// 71.3: a preset fills the exact parameters of the old constants.
    func testPresetsFillTheirParameters() throws {
        let model = try makeModel(store: makeStore())
        let expected: [(OverlayShadowPreset, Double, Double, Double)] = [
            (.soft, 0, 2, 4), (.hard, 2, 2, 0), (.glow, 0, 0, 8)
        ]
        for (preset, x, y, blur) in expected {
            model.selectShadow(preset)
            let style = model.profile.style
            XCTAssertEqual(style.shadowPreset, preset)
            XCTAssertEqual([style.shadowOffsetX, style.shadowOffsetY, style.shadowBlur], [x, y, blur], "\(preset)")
            XCTAssertFalse(model.isShadowParametersDisabled)
        }
        model.selectShadow(.none)
        XCTAssertEqual(model.profile.style.shadowPreset, OverlayShadowPreset.none)
        XCTAssertTrue(model.isShadowParametersDisabled, "無 disables the rows")
    }

    /// 71.3, updated by TASK-86 (86.2/86.3): only a shape change (offsets, blur)
    /// leaves no preset selected; opacity and color changes keep it.
    func testAnyParameterChangeDropsThePreset() throws {
        let model = try makeModel(store: makeStore())
        let changes: [(String, (StyleTabModel) -> Void)] = [
            ("x", { $0.setShadowOffsetX(3) }), ("y", { $0.setShadowOffsetY(-3) }),
            ("blur", { $0.setShadowBlur(9) })
        ]
        for (name, change) in changes {
            model.selectShadow(.hard)
            XCTAssertEqual(model.profile.style.shadowPreset, .hard, name)
            change(model)
            XCTAssertNil(model.profile.style.shadowPreset, "\(name) should deselect the preset")
            XCTAssertTrue(model.profile.style.showsShadow, name)
            model.selectShadow(.hard)
            XCTAssertEqual(model.profile.style.shadowPreset, .hard, "\(name): tapping restores it")
        }
        model.setShadowOpacityPercent(40)
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2 opacity keeps the preset")
        model.selectShadowColor(OverlayColor(hex: "#FF0000"))
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2 color keeps the preset")
    }

    /// 71.4, updated by TASK-86: glow no longer forces the text color; the
    /// follow-text source, once chosen, follows; a custom shadow color does not.
    func testGlowFollowsTextColorAndCustomDoesNot() throws {
        let model = try makeModel(store: makeStore())
        model.selectShadow(.glow)
        XCTAssertEqual(model.profile.style.shadowColorSource, .custom, "86.1 glow does not force follow-text")
        model.selectShadowColor(nil)
        XCTAssertEqual(model.profile.style.shadowColorSource, .textColor)
        for hex in ["#FFD60A", "#0A84FF", "#FF453A"] {
            model.selectTextColor(try XCTUnwrap(OverlayColor(hex: hex)))
            let style = model.profile.style
            XCTAssertEqual(style.resolvedShadowColor.hexString.prefix(7), Substring(hex), "glow follows \(hex)")
            XCTAssertEqual(style.shadowPreset, .glow, "still the glow preset after a text color change")
        }
        model.selectShadowColor(try XCTUnwrap(OverlayColor(hex: "#00FF00")))
        XCTAssertEqual(model.profile.style.shadowColorSource, .custom)
        model.selectTextColor(.white)
        XCTAssertEqual(model.profile.style.resolvedShadowColor.hexString.prefix(7), "#00FF00", "custom does not follow")
        model.selectShadowColor(nil)
        XCTAssertEqual(model.profile.style.resolvedShadowColor.hexString.prefix(7), "#FFFFFF", "back to following")
    }

    /// 71.5: values reach disk at once, a fresh store reads them, and nothing out of range is stored.
    func testParametersSurviveAFreshStoreAndExtremesAreClamped() throws {
        let store = try makeStore()
        let model = try makeModel(store: store)
        model.setShadowOffsetX(5)
        model.setShadowOffsetY(-6)
        model.setShadowBlur(11)
        model.setShadowOpacityPercent(35)
        model.selectShadowColor(OverlayColor(hex: "#336699"))
        var style = try XCTUnwrap(makeStore().load().first).style
        XCTAssertEqual([style.shadowOffsetX, style.shadowOffsetY, style.shadowBlur], [5, -6, 11])
        XCTAssertEqual(model.shadowOpacityPercent, 35)
        XCTAssertEqual(style.shadowColor, model.profile.style.shadowColor.quantized, "stored alpha is the 8-bit quantized value")
        XCTAssertEqual(Int((style.shadowColor.opacity * 100).rounded()), 35)
        XCTAssertNil(style.shadowPreset)

        for raw in [-1e9, -9, -8.4, 0.49, 8.6, 17, 1e9, .infinity, -.infinity] {
            model.setShadowOffsetX(raw)
            model.setShadowOffsetY(raw)
            model.setShadowBlur(raw)
        }
        for percent in [-50, 0, 1, 4, 101, 9999] { model.setShadowOpacityPercent(percent) }
        style = try XCTUnwrap(makeStore().load().first).style
        XCTAssertTrue(style.hasValidOutlineParameters)
        XCTAssertTrue(OverlayStyle.shadowOffsetRange.contains(style.shadowOffsetX))
        XCTAssertTrue(OverlayStyle.shadowOffsetRange.contains(style.shadowOffsetY))
        XCTAssertTrue(OverlayStyle.shadowBlurRange.contains(style.shadowBlur))
        XCTAssertTrue(style.shadowColor.isStorable)
        XCTAssertGreaterThanOrEqual(style.shadowColor.opacity, 0.05 - 0.005)
        XCTAssertEqual(OverlayStyle.shadowOffsetRange, -8.0...8.0)
        XCTAssertEqual(OverlayStyle.shadowBlurRange, 0.0...16.0)
    }

    /// The custom picker alpha is clamped to the storable range too.
    func testCustomShadowColorAlphaIsClamped() throws {
        let model = try makeModel(store: makeStore())
        model.applyCustomShadowColor(OverlayColor(hex: "#11223300") ?? .black.withOpacity(0))
        XCTAssertTrue(model.profile.style.shadowColor.isStorable)
        XCTAssertTrue(model.profile.style.showsShadow)
    }
}
