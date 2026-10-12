import XCTest
@testable import DaysCam

/// TASK-71 ui-panel independent QA (71.3, 71.4, 71.5 UI part), updated by
/// TASK-118 (the offset and blur sliders are gone): the shadow presets fill
/// the parameters, a profile with custom parameters shows no preset and any
/// preset replaces them, glow follows the text color, and values go through a
/// real `ProfileStore` and back without ever leaving their ranges.
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
        return ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant }, defaults: defaults, scheduler: ProfileStore.immediateScheduler)
    }

    /// `customize` edits the stored style first, standing in for a profile
    /// whose parameters an older build's sliders had set (118.5).
    private func makeModel(store: ProfileStore,
                           customize: ((inout OverlayStyle) -> Void)? = nil) throws -> StyleTabModel {
        store.load()
        var profile = try XCTUnwrap(store.profiles.first)
        if let customize {
            customize(&profile.style)
            try store.update(profile)
        }
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
            XCTAssertFalse(model.isShadowColorDisabled)
        }
        model.selectShadow(.none)
        XCTAssertEqual(model.profile.style.shadowPreset, OverlayShadowPreset.none)
        XCTAssertTrue(model.isShadowColorDisabled, "無 disables the color section")
    }

    /// 118.5: custom parameters (set by an older build's sliders) leave no
    /// preset selected and keep their look; tapping a preset replaces them.
    /// Opacity and color changes keep the selection (86.2).
    func testCustomParametersShowNoPresetAndAPresetReplacesThem() throws {
        let customs: [(String, (inout OverlayStyle) -> Void)] = [
            ("x", { $0.shadowOffsetX = 3 }), ("y", { $0.shadowOffsetY = -3 }),
            ("blur", { $0.shadowBlur = 9 })
        ]
        for (name, customize) in customs {
            let model = try makeModel(store: makeStore(), customize: customize)
            let before = model.profile.style
            XCTAssertNil(before.shadowPreset, "\(name): no preset selected")
            XCTAssertTrue(before.showsShadow, name)
            model.selectShadow(.soft)
            XCTAssertEqual(model.profile.style.shadowPreset, .soft, "\(name): tapping selects it")
            XCTAssertEqual([model.profile.style.shadowOffsetX, model.profile.style.shadowOffsetY,
                            model.profile.style.shadowBlur], [0, 2, 4], name)
        }
        let model = try makeModel(store: makeStore())
        model.selectShadow(.hard)
        model.applyCustomShadowColor(model.profile.style.shadowColor.withOpacity(0.4))
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2 picker opacity keeps the preset")
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

    /// 71.5: custom parameters and colors reach disk at once, a fresh store
    /// reads them, and nothing out of range is stored.
    func testParametersSurviveAFreshStoreAndExtremesAreClamped() throws {
        let store = try makeStore()
        let model = try makeModel(store: store) { $0.shadowOffsetX = 5; $0.shadowOffsetY = -6; $0.shadowBlur = 11 }
        // TASK-113: a swatch would reset the alpha to 60%; the picker sets both.
        model.applyCustomShadowColor(try XCTUnwrap(OverlayColor(hex: "#336699")).withOpacity(0.35))
        var style = try XCTUnwrap(makeStore().load().first).style
        XCTAssertEqual([style.shadowOffsetX, style.shadowOffsetY, style.shadowBlur], [5, -6, 11])
        XCTAssertEqual(model.profile.style.shadowOpacity, 0.35, accuracy: 0.003)
        XCTAssertEqual(style.shadowColor, model.profile.style.shadowColor.quantized, "stored alpha is the 8-bit quantized value")
        XCTAssertEqual(Int((style.shadowColor.opacity * 100).rounded()), 35)
        XCTAssertNil(style.shadowPreset)

        for alpha in [0.0, 0.01, 0.04, 1.0] {
            model.applyCustomShadowColor(OverlayColor(red: 0.2, green: 0.4, blue: 0.6, opacity: alpha))
        }
        style = try XCTUnwrap(makeStore().load().first).style
        XCTAssertTrue(style.hasValidOutlineParameters)
        XCTAssertEqual([style.shadowOffsetX, style.shadowOffsetY, style.shadowBlur], [5, -6, 11], "color edits keep the shape")
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
