import XCTest
@testable import DaysCam

/// Covers the TASK-05 acceptance table for the five preset themes.
final class OverlayThemeTests: XCTestCase {

    /// 5.1
    func testThereAreExactlyFiveThemes() {
        XCTAssertEqual(OverlayTheme.all.count, 5)
    }

    /// 5.2 — order is the PRD §3.4 table order, which the picker relies on.
    func testThemeOrderMatchesTheSpecification() {
        XCTAssertEqual(OverlayTheme.all.map(\.id),
                       [.classicWhite, .retroOrange, .filmStrip, .minimalDark, .softPink])
    }

    /// 5.3 — every theme needs a shadow, box or stroke so the text stays legible
    /// on a pure white and a pure black photo alike (PRD FR-4.6).
    func testEveryThemeCarriesAtLeastOneDecoration() {
        for theme in OverlayTheme.all {
            XCTAssertFalse(theme.decorations.isEmpty, "\(theme.id) has no decoration")
        }
    }

    /// The array is not decorative: softPink needs both a stroke and a shadow,
    /// which a single-valued field could not hold.
    func testSoftPinkCarriesBothAStrokeAndAShadow() {
        let softPink = OverlayTheme.theme(for: .softPink)
        let hasStroke = softPink.decorations.contains { decoration in
            if case .stroke = decoration { return true }
            return false
        }
        let hasShadow = softPink.decorations.contains { decoration in
            if case .shadow = decoration { return true }
            return false
        }
        XCTAssertTrue(hasStroke)
        XCTAssertTrue(hasShadow)
        XCTAssertEqual(softPink.decorations.count, 2)
    }

    /// 5.4
    func testClassicWhiteTextColorIsPureWhite() {
        let color = OverlayTheme.theme(for: .classicWhite).textColor
        XCTAssertEqual(color.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.green, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.opacity, 1.0, accuracy: 0.01)
    }

    /// 5.5 — #FF9500
    func testRetroOrangeTextColorMatchesItsHexValue() {
        let color = OverlayTheme.theme(for: .retroOrange).textColor
        XCTAssertEqual(color.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.green, 0.584, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0.0, accuracy: 0.01)
        XCTAssertEqual(color.opacity, 1.0, accuracy: 0.01)
    }

    func testRemainingThemeColorsMatchTheirHexValues() {
        let filmStrip = OverlayTheme.theme(for: .filmStrip).textColor
        XCTAssertEqual(filmStrip, .white)

        // #1C1C1E
        let minimalDark = OverlayTheme.theme(for: .minimalDark).textColor
        XCTAssertEqual(minimalDark.red, 28.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(minimalDark.green, 28.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(minimalDark.blue, 30.0 / 255.0, accuracy: 0.01)

        // #FF6B9D
        let softPink = OverlayTheme.theme(for: .softPink).textColor
        XCTAssertEqual(softPink.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(softPink.green, 107.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(softPink.blue, 157.0 / 255.0, accuracy: 0.01)
    }

    /// 0.3 §4.3 (replacing 0.2 §4.3's font column): the five 0.1 themes all
    /// draw in PingFang (32.4).
    func testLegacyThemeFontsFollowTheMigrationTable() {
        for themeID in ThemeID.allCases {
            XCTAssertEqual(OverlayTheme.theme(for: themeID).fontID, .pingFang, "32.4 \(themeID)")
        }
    }

    func testLookupCoversEveryThemeIdentifier() {
        for id in ThemeID.allCases {
            XCTAssertEqual(OverlayTheme.theme(for: id).id, id)
        }
    }

    func testEightBitColorInitializerMatchesFractionalComponents() {
        let orange = OverlayColor(red8: 255, green8: 149, blue8: 0)
        XCTAssertEqual(orange.red, 1.0, accuracy: 0.0001)
        XCTAssertEqual(orange.green, 149.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(orange.blue, 0.0, accuracy: 0.0001)
        XCTAssertEqual(orange.opacity, 1.0, accuracy: 0.0001)
    }
}

/// Covers TASK-18 18.1 ... 18.4 (decorations half): `OverlayTheme(style:)`
/// against the PRD 0.2 FR-10 decoration table.
final class OverlayThemeStyleTests: XCTestCase {

    private let softShadow = OverlayDecoration.shadow(offset: CGSize(width: 0, height: 2), blur: 4,
                                                      opacity: 0.6, color: .black)
    private let dark = OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E)
    private let blue = OverlayColor(red8: 0x0A, green8: 0x84, blue8: 0xFF)
    private let insets = OverlayInsets(horizontal: 12, vertical: 6)

    func testDefaultStyleHasExactlyTheSoftShadow() {
        XCTAssertEqual(OverlayTheme(style: OverlayStyle()).decorations, [softShadow], "18.1")
    }

    func testSolidBoxWithAutomaticColorUsesTheContrastColor() {
        let style = OverlayStyle(textColor: .white, outline: .solidBox, outlineColor: nil, shadow: .none)
        XCTAssertEqual(OverlayTheme(style: style).decorations,
                       [.backgroundBox(color: dark, opacity: 1.0, cornerRadius: 8, insets: insets)], "18.2")
    }

    func testSolidBoxWithExplicitColorUsesIt() {
        let style = OverlayStyle(textColor: .white, outline: .solidBox, outlineColor: blue, shadow: .none)
        XCTAssertEqual(OverlayTheme(style: style).decorations,
                       [.backgroundBox(color: blue, opacity: 1.0, cornerRadius: 8, insets: insets)], "18.3")
    }

    func testNoOutlineAndNoShadowHasNoDecorations() {
        XCTAssertTrue(OverlayTheme(style: OverlayStyle(outline: .none, shadow: .none)).decorations.isEmpty, "18.4")
    }

    func testEveryOutlineMatchesTheConstantTable() {
        let expected: [OverlayOutline: OverlayDecoration] = [
            .thinStroke: .stroke(color: blue, width: 2),
            .thickStroke: .stroke(color: blue, width: 4),
            .translucentBox: .backgroundBox(color: blue, opacity: 0.5, cornerRadius: 8, insets: insets),
            .solidBox: .backgroundBox(color: blue, opacity: 1.0, cornerRadius: 8, insets: insets)
        ]
        for outline in OverlayOutline.allCases {
            let theme = OverlayTheme(style: OverlayStyle(outline: outline, outlineColor: blue, shadow: .none))
            XCTAssertEqual(theme.decorations.first, expected[outline], "\(outline)")
        }
    }

    func testEveryShadowMatchesTheConstantTable() {
        let pink = OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D)
        let expected: [OverlayShadow: OverlayDecoration] = [
            .soft: softShadow,
            .hard: .shadow(offset: CGSize(width: 2, height: 2), blur: 0, opacity: 0.75, color: .black),
            .glow: .shadow(offset: .zero, blur: 8, opacity: 0.9, color: pink)
        ]
        for shadow in OverlayShadow.allCases {
            let theme = OverlayTheme(style: OverlayStyle(textColor: pink, outline: .none, shadow: shadow))
            XCTAssertEqual(theme.decorations.first, expected[shadow], "\(shadow)")
        }
    }

    /// The outline comes first so the shadow is cast by the outlined text.
    func testOutlineIsAppliedBeforeShadow() {
        let theme = OverlayTheme(style: OverlayStyle(outline: .thinStroke, shadow: .soft))
        XCTAssertEqual(theme.decorations.count, 2)
        XCTAssertEqual(theme.decorations.last, softShadow)
    }

    func testThemeCarriesFontAndTextColorFromTheStyle() {
        let style = OverlayStyle(fontID: .songti, textColor: blue)
        let theme = OverlayTheme(style: style)
        XCTAssertEqual(theme.fontID, .songti)
        XCTAssertEqual(theme.textColor, blue)
        XCTAssertEqual(theme.style, style)
    }
}
