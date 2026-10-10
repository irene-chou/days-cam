import XCTest
@testable import DaysCam

/// Independent QA for TASK-69 ui-panel half (#297, PR #310): opacity rows of
/// the style tab, persisted through a real `ProfileStore` file.
@MainActor
final class StyleOpacityAcceptanceTests: XCTestCase {
    private var defaults = UserDefaults.standard
    private var suiteName = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "StyleOpacityAcceptanceTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeProfile() -> CameraProfile {
        CameraProfile(name: "QA", startDate: DateComponents(year: 2026, month: 1, day: 1))
    }

    private func makeModel(_ profile: CameraProfile, onUpdate: @escaping (CameraProfile) -> Void = { _ in }) -> StyleTabModel {
        StyleTabModel(profile: profile, recentColorsStore: RecentColorsStore(defaults: defaults),
                      applyFont: { _, _ in }, allProfiles: { [] }, updateProfile: { onUpdate($0) })
    }

    /// 69.3: every slider percent survives encode -> decode of the profile file
    /// and shows the same percent again (8-bit quantization must not shift it).
    func testEveryPercentSurvivesAFileRoundTripAsTheSamePercent() throws {
        for percent in StyleTabModel.opacityPercentRange {
            var saved = makeProfile()
            let model = makeModel(makeProfile()) { saved = $0 }
            model.setTextOpacityPercent(percent)
            model.selectOutline(.stroke)
            model.setOutlineOpacityPercent(percent)
            let data = try JSONEncoder().encode(saved)
            let reloaded = try JSONDecoder().decode(CameraProfile.self, from: data)
            let reopened = makeModel(reloaded)
            XCTAssertEqual(reopened.textOpacityPercent, percent, "text \(percent)")
            XCTAssertEqual(reopened.outlineOpacityPercent, percent, "outline \(percent)")
        }
    }

    /// 69.4: out-of-range slider input and picker alpha never produce < 5%.
    func testOutOfRangeInputsClampToFivePercent() {
        let model = makeModel(makeProfile())
        for value in [-10, 0, 1, 4] {
            model.setTextOpacityPercent(value)
            XCTAssertEqual(model.textOpacityPercent, 5, "\(value)")
            XCTAssertGreaterThanOrEqual(model.profile.style.textColor.opacity, OverlayColor.minimumStorableOpacity)
        }
        model.setTextOpacityPercent(999)
        XCTAssertEqual(model.textOpacityPercent, 100)
        for alpha in [0.0, 0.01, 0.049] {
            model.applyCustomTextColor(OverlayColor(red: 0.2, green: 0.4, blue: 0.6, opacity: alpha))
            XCTAssertEqual(model.textOpacityPercent, 5, "picker \(alpha)")
            XCTAssertTrue(model.profile.style.textColor.isStorable)
            model.applyCustomOutlineColor(OverlayColor(red: 0.2, green: 0.4, blue: 0.6, opacity: alpha))
            XCTAssertTrue(model.profile.style.outlineColor?.isStorable ?? false)
        }
        // Picker alpha above 1 stays storable (NaN-free).
        model.applyCustomTextColor(OverlayColor(red: 1, green: 1, blue: 1, opacity: 1))
        XCTAssertEqual(model.textOpacityPercent, 100)
    }

    /// Swatch / recent taps keep alpha for both targets; the recent row stores RGB only.
    func testSwatchAndRecentKeepAlphaAndRecentIsOpaque() throws {
        let model = makeModel(makeProfile())
        model.setTextOpacityPercent(40)
        model.selectOutline(.stroke)
        model.setOutlineOpacityPercent(60)
        let custom = OverlayColor(red: 0.1, green: 0.5, blue: 0.9, opacity: 0.3)
        model.commitCustomColor(custom)
        let recent = try XCTUnwrap(model.recentColors.first)
        XCTAssertEqual(recent.opacity, 1, accuracy: 0.0001)
        model.selectTextColor(recent)
        model.selectOutlineColor(recent)
        XCTAssertEqual(model.textOpacityPercent, 40)
        XCTAssertEqual(model.outlineOpacityPercent, 60)
        for swatch in model.textColorSwatches {
            model.selectTextColor(swatch)
            XCTAssertEqual(model.textOpacityPercent, 40)
            XCTAssertTrue(StyleTabModel.hasSameRGB(model.profile.style.textColor, swatch))
        }
        // Selection ring compares RGB only.
        XCTAssertTrue(StyleTabModel.hasSameRGB(custom, recent))
        XCTAssertFalse(StyleTabModel.hasSameRGB(custom, model.textColorSwatches[0]))
    }

    /// Automatic outline: adjusting opacity pins the explicit contrast color;
    /// tapping automatic goes back to nil (opaque).
    func testAutomaticOutlineBecomesExplicitThenReturnsToAutomatic() {
        var profile = makeProfile()
        profile.style.textColor = OverlayColor(red: 1, green: 1, blue: 1, opacity: 1)
        profile.style.outline = .stroke
        profile.style.outlineColor = nil
        let model = makeModel(profile)
        XCTAssertEqual(model.outlineOpacityPercent, 100)
        let resolved = model.profile.style.resolvedOutlineColor
        model.setOutlineOpacityPercent(50)
        let pinned = model.profile.style.outlineColor
        XCTAssertNotNil(pinned)
        XCTAssertTrue(StyleTabModel.hasSameRGB(pinned ?? resolved, resolved))
        XCTAssertEqual(model.outlineOpacityPercent, 50)
        // Text color change no longer flips the outline.
        model.selectTextColor(OverlayColor(red: 0, green: 0, blue: 0, opacity: 1))
        XCTAssertTrue(StyleTabModel.hasSameRGB(model.profile.style.outlineColor ?? resolved, resolved))
        model.selectOutlineColor(nil)
        XCTAssertNil(model.profile.style.outlineColor)
        XCTAssertEqual(model.outlineOpacityPercent, 100)
    }

    /// Outline "none" disables the whole color section (the opacity row follows it).
    func testOutlineNoneDisablesColorSection() {
        let model = makeModel(makeProfile())
        model.selectOutline(.none)
        XCTAssertTrue(model.isOutlineColorSectionDisabled)
        model.selectOutline(.stroke)
        XCTAssertFalse(model.isOutlineColorSectionDisabled)
    }
}
