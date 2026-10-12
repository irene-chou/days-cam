import XCTest
@testable import DaysCam

/// Independent QA for TASK-69 ui-panel half (#297, PR #310), updated by
/// TASK-113: opacity is set only in the color picker (the sliders are gone)
/// and persisted through a real `ProfileStore` file.
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

    /// 69.3 (TASK-113: set through the color picker, the only opacity entry):
    /// every 5% step survives encode -> decode of the profile file within the
    /// 8-bit quantization.
    func testEveryPickerAlphaSurvivesAFileRoundTrip() throws {
        for step in 1...20 {
            let alpha = Double(step) / 20
            var saved = makeProfile()
            let model = makeModel(makeProfile()) { saved = $0 }
            model.applyCustomTextColor(OverlayColor(red: 0.2, green: 0.4, blue: 0.6, opacity: alpha))
            model.selectOutline(.stroke)
            model.applyCustomOutlineColor(OverlayColor(red: 0.6, green: 0.4, blue: 0.2, opacity: alpha))
            let data = try JSONEncoder().encode(saved)
            let reloaded = try JSONDecoder().decode(CameraProfile.self, from: data)
            let reopened = makeModel(reloaded)
            XCTAssertEqual(reopened.profile.style.textColor.opacity, alpha, accuracy: 0.003, "text \(alpha)")
            XCTAssertEqual(reopened.profile.style.outlineColor?.opacity ?? -1, alpha, accuracy: 0.003, "outline \(alpha)")
        }
    }

    /// 69.4: picker alpha never produces < 5%, and 100% stays 100%.
    func testOutOfRangePickerAlphaClampsToFivePercent() {
        let model = makeModel(makeProfile())
        for alpha in [0.0, 0.01, 0.049] {
            model.applyCustomTextColor(OverlayColor(red: 0.2, green: 0.4, blue: 0.6, opacity: alpha))
            XCTAssertEqual(model.profile.style.textColor.opacity, OverlayColor.minimumStorableOpacity, "picker \(alpha)")
            XCTAssertTrue(model.profile.style.textColor.isStorable)
            model.applyCustomOutlineColor(OverlayColor(red: 0.2, green: 0.4, blue: 0.6, opacity: alpha))
            XCTAssertEqual(model.profile.style.outlineColor?.opacity, OverlayColor.minimumStorableOpacity, "picker \(alpha)")
            XCTAssertTrue(model.profile.style.outlineColor?.isStorable ?? false)
        }
        model.applyCustomTextColor(OverlayColor(red: 1, green: 1, blue: 1, opacity: 1))
        XCTAssertEqual(model.profile.style.textColor.opacity, 1)
    }

    /// 113.3 / 113.4: swatch and recent taps make both targets fully opaque
    /// whatever the picker had set; the recent row stores RGB only.
    func testSwatchAndRecentResetAlphaAndRecentIsOpaque() throws {
        let model = makeModel(makeProfile())
        model.applyCustomTextColor(OverlayColor(red: 0.1, green: 0.5, blue: 0.9, opacity: 0.4))
        model.selectOutline(.stroke)
        model.applyCustomOutlineColor(OverlayColor(red: 0.1, green: 0.5, blue: 0.9, opacity: 0.6))
        let custom = OverlayColor(red: 0.1, green: 0.5, blue: 0.9, opacity: 0.3)
        model.commitCustomColor(custom)
        let recent = try XCTUnwrap(model.recentColors.first)
        XCTAssertEqual(recent.opacity, 1, accuracy: 0.0001)
        model.selectTextColor(recent)
        model.selectOutlineColor(recent)
        XCTAssertEqual(model.profile.style.textColor.opacity, 1, "113.3 最近使用")
        XCTAssertEqual(model.profile.style.outlineColor?.opacity, 1, "113.4 最近使用")
        for swatch in model.textColorSwatches {
            model.applyCustomTextColor(swatch.withOpacity(0.5))
            model.selectTextColor(swatch)
            XCTAssertEqual(model.profile.style.textColor.opacity, 1, "113.3 色票")
            XCTAssertTrue(StyleTabModel.hasSameRGB(model.profile.style.textColor, swatch))
        }
        for swatch in model.outlineColorSwatches {
            model.applyCustomOutlineColor(swatch.withOpacity(0.5))
            model.selectOutlineColor(swatch)
            XCTAssertEqual(model.profile.style.outlineColor?.opacity, 1, "113.4 色票")
        }
        // Selection ring compares RGB only.
        XCTAssertTrue(StyleTabModel.hasSameRGB(custom, recent))
        XCTAssertFalse(StyleTabModel.hasSameRGB(custom, model.textColorSwatches[0]))
    }

    /// Automatic outline: a picker color pins an explicit color (with its
    /// alpha); tapping automatic goes back to nil, which is opaque (113.4).
    func testAutomaticOutlineBecomesExplicitThenReturnsToAutomatic() {
        var profile = makeProfile()
        profile.style.textColor = OverlayColor(red: 1, green: 1, blue: 1, opacity: 1)
        profile.style.outline = .stroke
        profile.style.outlineColor = nil
        let model = makeModel(profile)
        XCTAssertEqual(model.profile.style.resolvedOutlineColor.opacity, 1)
        let resolved = model.profile.style.resolvedOutlineColor
        model.applyCustomOutlineColor(resolved.withOpacity(0.5))
        let pinned = model.profile.style.outlineColor
        XCTAssertNotNil(pinned)
        XCTAssertTrue(StyleTabModel.hasSameRGB(pinned ?? resolved, resolved))
        XCTAssertEqual(pinned?.opacity ?? 0, 0.5, accuracy: 0.003)
        // Text color change no longer flips the outline.
        model.selectTextColor(OverlayColor(red: 0, green: 0, blue: 0, opacity: 1))
        XCTAssertTrue(StyleTabModel.hasSameRGB(model.profile.style.outlineColor ?? resolved, resolved))
        model.selectOutlineColor(nil)
        XCTAssertNil(model.profile.style.outlineColor)
        XCTAssertEqual(model.profile.style.resolvedOutlineColor.opacity, 1, "113.4 自動不透明")
    }

    /// Outline "none" disables the whole color section.
    func testOutlineNoneDisablesColorSection() {
        let model = makeModel(makeProfile())
        model.selectOutline(.none)
        XCTAssertTrue(model.isOutlineColorSectionDisabled)
        model.selectOutline(.stroke)
        XCTAssertFalse(model.isOutlineColorSectionDisabled)
    }
}
