import XCTest
@testable import DaysCam

/// TASK-70 ui-panel independent QA (70.1, 70.3 model side, 70.4 UI part):
/// the 粗細／留白 sliders write through a real `ProfileStore`, survive a fresh
/// store (app restart), and never store an out-of-range value.
@MainActor
final class OutlineSliderAcceptanceTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OutlineSliderAcceptance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "OutlineSliderAcceptance-\(UUID().uuidString)"
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

    /// 70.1: exactly 無／描邊／底框, in that order.
    func testOnlyThreeOutlineOptions() throws {
        let model = try makeModel(store: makeStore())
        XCTAssertEqual(model.outlineOptions, [.none, .stroke, .box])
    }

    /// Slider range and default equal core #312 (stroke 1...6 default 2, box 0...24 default 12),
    /// and the model steps stay inside them.
    func testRangesAndDefaultsMatchCore() {
        XCTAssertEqual(OverlayStyle.strokeWidthRange, 1.0...6.0)
        XCTAssertEqual(OverlayStyle.boxPaddingRange, 0.0...24.0)
        XCTAssertEqual(OverlayStyle.defaultStrokeWidth, 2)
        XCTAssertEqual(OverlayStyle.defaultBoxPadding, 12)
        XCTAssertEqual(OverlayStyle().strokeWidth, 2)
        XCTAssertEqual(OverlayStyle().boxPadding, 12)
        for bound in [OverlayStyle.strokeWidthRange.lowerBound, OverlayStyle.strokeWidthRange.upperBound] {
            XCTAssertEqual(bound.truncatingRemainder(dividingBy: StyleTabModel.strokeWidthStep), 0)
        }
        for bound in [OverlayStyle.boxPaddingRange.lowerBound, OverlayStyle.boxPaddingRange.upperBound] {
            XCTAssertEqual(bound.truncatingRemainder(dividingBy: StyleTabModel.boxPaddingStep), 0)
        }
    }

    /// 70.4: each slider change reaches disk at once and a brand-new store reads it back.
    func testSliderValuesSurviveAFreshStore() throws {
        let store = try makeStore()
        let model = try makeModel(store: store)
        model.selectOutline(.stroke)
        model.setStrokeWidth(4.5)
        model.selectOutline(.box)
        model.setBoxPadding(20)

        let reopened = try makeStore()
        let style = try XCTUnwrap(reopened.load().first).style
        XCTAssertEqual(style.outline, .box)
        XCTAssertEqual(style.strokeWidth, 4.5, "kept while another outline is chosen")
        XCTAssertEqual(style.boxPadding, 20)
    }

    /// 70.4: whatever the slider reports, the stored value is in range, and the file never holds one outside.
    func testExtremeSliderInputsNeverStoreOutOfRange() throws {
        let store = try makeStore()
        let model = try makeModel(store: store)
        for raw in [-1e9, -1, 0, 0.74, 1, 6, 6.26, 7, 1e9, .infinity, -.infinity] {
            model.setStrokeWidth(raw)
            model.setBoxPadding(raw)
            let style = model.profile.style
            XCTAssertTrue(OverlayStyle.strokeWidthRange.contains(style.strokeWidth), "stroke \(raw)")
            XCTAssertTrue(OverlayStyle.boxPaddingRange.contains(style.boxPadding), "padding \(raw)")
            XCTAssertTrue(style.hasValidOutlineParameters)
        }
        let stored = try XCTUnwrap(makeStore().load().first).style
        XCTAssertTrue(stored.hasValidOutlineParameters)
        XCTAssertEqual(stored.strokeWidth, model.profile.style.strokeWidth)
        XCTAssertEqual(stored.boxPadding, model.profile.style.boxPadding)
    }

    /// Slider steps land only on the 0.5pt / 1pt grid.
    func testValuesSnapToStep() throws {
        let model = try makeModel(store: makeStore())
        var raw = 1.0
        while raw <= 6.0 {
            model.setStrokeWidth(raw)
            XCTAssertEqual(model.profile.style.strokeWidth.truncatingRemainder(dividingBy: 0.5), 0, "stroke \(raw)")
            raw += 0.13
        }
        raw = 0
        while raw <= 24 {
            model.setBoxPadding(raw)
            XCTAssertEqual(model.profile.style.boxPadding.truncatingRemainder(dividingBy: 1), 0, "padding \(raw)")
            raw += 0.37
        }
    }

    /// #314: choosing an outline or moving a slider leaves the shadow preset alone, and applying a
    /// shadow preset leaves the outline parameters alone.
    func testOutlineAndShadowPresetsDoNotInterfere() throws {
        let store = try makeStore()
        let model = try makeModel(store: store)
        model.selectShadow(.glow)
        let shadowBefore = model.profile.style
        model.selectOutline(.stroke)
        model.setStrokeWidth(5)
        model.selectOutline(.box)
        model.setBoxPadding(18)
        var style = model.profile.style
        XCTAssertEqual(style.showsShadow, shadowBefore.showsShadow)
        XCTAssertEqual(style.shadowColor, shadowBefore.shadowColor)
        XCTAssertEqual(style.shadowBlur, shadowBefore.shadowBlur)
        XCTAssertEqual(style.shadowOffsetX, shadowBefore.shadowOffsetX)
        XCTAssertEqual(style.shadowOffsetY, shadowBefore.shadowOffsetY)

        var preview = style
        preview.applyShadowPreset(.none)
        XCTAssertEqual(preview.strokeWidth, 5)
        XCTAssertEqual(preview.boxPadding, 18)
        XCTAssertEqual(preview.outline, .box)
        style.applyShadowPreset(.hard)
        XCTAssertEqual(style.strokeWidth, 5)
        XCTAssertEqual(style.boxPadding, 18)
        XCTAssertEqual(style.outline, .box)

        let reopened = try XCTUnwrap(makeStore().load().first).style
        XCTAssertEqual(reopened.showsShadow, shadowBefore.showsShadow)
        XCTAssertEqual(reopened.outline, .box)
    }
}
