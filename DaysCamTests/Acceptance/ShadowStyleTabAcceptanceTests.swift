import XCTest
@testable import DaysCam

/// TASK-86 independent QA for the ui-panel half (#364), 86.1 to 86.4, through
/// `StyleTabModel` with colors and sequences the PR's own tests do not use:
/// a color picked from the custom picker at alpha 0.25, interleaved actions,
/// and what is handed to the persistence layer.
@MainActor
final class ShadowStyleTabAcceptanceTests: XCTestCase {
    private var defaults = UserDefaults.standard
    private var suiteName = ""
    private var saved: [CameraProfile] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "ShadowStyleTabAcceptance-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        saved = []
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeModel() -> StyleTabModel {
        StyleTabModel(profile: CameraProfile(name: "qa", startDate: DateComponents(year: 2026, month: 1, day: 1)),
                      recentColorsStore: RecentColorsStore(defaults: defaults),
                      applyFont: { _, _ in },
                      allProfiles: { [] },
                      updateProfile: { [unowned self] in saved.append($0) })
    }

    private let teal = OverlayColor(red8: 0x00, green8: 0x96, blue8: 0x88)
    private let shapes: [OverlayShadowPreset: [Double]] = [
        .soft: [0, 2, 4], .hard: [2, 2, 0], .glow: [0, 0, 8]
    ]

    private func shape(_ style: OverlayStyle) -> [Double] {
        [style.shadowOffsetX, style.shadowOffsetY, style.shadowBlur]
    }

    /// 86.1 and 86.2 with a picker color at alpha 0.25, interleaved with
    /// type, color source and opacity changes.
    func test86InterleavedActionsNeverResetTheOtherAxis() throws {
        let model = makeModel()
        model.applyCustomShadowColor(teal.withOpacity(0.25))
        model.selectShadow(.glow)
        let picked = model.profile.style.shadowColor
        XCTAssertEqual(model.profile.style.shadowOpacity, picked.opacity)
        for preset in [OverlayShadowPreset.hard, .soft, .glow, .hard] {
            model.selectShadow(preset)
            XCTAssertEqual(model.profile.style.shadowColor, picked, "86.1 \(preset)")
            XCTAssertEqual(model.profile.style.shadowColorSource, .custom)
            XCTAssertEqual(shape(model.profile.style), try XCTUnwrap(shapes[preset]))
            XCTAssertEqual(model.profile.style.shadowPreset, preset)
        }
        // Color changes keep the type.
        model.selectShadowColor(OverlayStyle.swatches[1])
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2")
        model.selectShadowColor(nil)
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2")
        model.applyCustomShadowColor(teal)
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2")
        model.applyCustomShadowColor(teal.withOpacity(0.77))
        XCTAssertEqual(model.profile.style.shadowPreset, .hard, "86.2")
        // The picker opacity survives a type switch (86.1); a color-source flip
        // resets it to the default 60% (TASK-113, 113.5).
        model.selectShadow(.soft)
        XCTAssertEqual(model.profile.style.shadowOpacity, 0.77, accuracy: 0.003, "86.1")
        model.selectShadow(.glow)
        XCTAssertEqual(model.profile.style.shadowOpacity, 0.77, accuracy: 0.003, "86.1")
        model.selectShadowColor(nil)
        XCTAssertEqual(model.profile.style.shadowOpacity, StyleTabModel.swatchShadowOpacity, accuracy: 0.003, "113.5")
        XCTAssertEqual(model.profile.style.shadowColorSource, .textColor)
        model.selectShadow(.hard)
        XCTAssertEqual(model.profile.style.shadowOpacity, StyleTabModel.swatchShadowOpacity, accuracy: 0.003, "113.8")
    }

    /// 86.3 with custom parameters: no preset is selected, and the geometry
    /// alone decides which one is.
    func test863CustomGeometryShowsNoPresetUntilItMatchesOne() throws {
        var profile = CameraProfile(name: "qa", startDate: DateComponents(year: 2026, month: 1, day: 1))
        profile.style.shadowBlur = 3
        let model = StyleTabModel(profile: profile,
                                  recentColorsStore: RecentColorsStore(defaults: defaults),
                                  applyFont: { _, _ in },
                                  allProfiles: { [] },
                                  updateProfile: { [unowned self] in saved.append($0) })
        XCTAssertNil(model.profile.style.shadowPreset)
        model.selectShadow(.hard)
        XCTAssertEqual(model.profile.style.shadowPreset, .hard)
        // Opacity and color tweaks never create or hide the selection.
        model.applyCustomShadowColor(teal.withOpacity(0.1))
        model.selectShadowColor(teal)
        XCTAssertEqual(model.profile.style.shadowPreset, .hard)
    }

    /// 86.4 with persistence: the profile handed to the store keeps the color
    /// after 無, and the next type reuses it.
    func test864NoneThenTypeReusesColorAndIsPersisted() throws {
        let model = makeModel()
        model.applyCustomShadowColor(teal.withOpacity(0.25))
        model.selectShadow(.hard)
        let picked = model.profile.style.shadowColor
        model.selectShadow(.none)
        let off = try XCTUnwrap(saved.last).style
        XCTAssertFalse(off.showsShadow)
        XCTAssertEqual(off.shadowColor, picked)
        XCTAssertEqual(shape(off), try XCTUnwrap(shapes[.hard]), "shape kept while off")
        XCTAssertTrue(model.isShadowColorDisabled)
        model.selectShadow(.glow)
        let on = try XCTUnwrap(saved.last).style
        XCTAssertTrue(on.showsShadow)
        XCTAssertEqual(on.shadowColor, picked)
        XCTAssertEqual(on.shadowColorSource, .custom)
        XCTAssertEqual(shape(on), try XCTUnwrap(shapes[.glow]))
        XCTAssertFalse(model.isShadowColorDisabled)
    }

    /// Color or opacity edits while 無 is selected do not turn the shadow on
    /// nor lose the choice for later.
    func test864ColorEditWhileOffStaysOffAndIsKept() throws {
        let model = makeModel()
        model.selectShadow(.soft)
        model.selectShadow(.none)
        model.applyCustomShadowColor(teal.withOpacity(0.3))
        XCTAssertFalse(model.profile.style.showsShadow)
        XCTAssertEqual(model.profile.style.shadowPreset, OverlayShadowPreset.none)
        model.selectShadow(.hard)
        XCTAssertEqual(model.profile.style.shadowOpacity, 0.3, accuracy: 0.003)
        XCTAssertEqual(model.profile.style.shadowColorSource, .custom)
        XCTAssertTrue(StyleTabModel.hasSameRGB(model.profile.style.shadowColor, teal))
    }
}
