import XCTest
@testable import DaysCam

/// The theme a migrated 0.1 profile draws with (PRD 0.2 §4.3).
private func legacyTheme(_ id: ThemeID) -> OverlayTheme {
    OverlayTheme(style: OverlayStyle(legacyTheme: id))
}

/// Covers the TASK-05 acceptance table for the five preset themes.
final class OverlayThemeTests: XCTestCase {

    /// 5.3 — every theme needs a shadow, box or stroke so the text stays legible
    /// on a pure white and a pure black photo alike (PRD FR-4.6).
    func testEveryThemeCarriesAtLeastOneDecoration() {
        for id in ThemeID.allCases {
            XCTAssertFalse(legacyTheme(id).decorations.isEmpty, "\(id) has no decoration")
        }
    }

    /// The array is not decorative: softPink needs both a stroke and a shadow,
    /// which a single-valued field could not hold.
    func testSoftPinkCarriesBothAStrokeAndAShadow() {
        let softPink = legacyTheme(.softPink)
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
        let color = legacyTheme(.classicWhite).textColor
        XCTAssertEqual(color.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.green, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.opacity, 1.0, accuracy: 0.01)
    }

    /// 5.5 — #FF9500
    func testRetroOrangeTextColorMatchesItsHexValue() {
        let color = legacyTheme(.retroOrange).textColor
        XCTAssertEqual(color.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.green, 0.584, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0.0, accuracy: 0.01)
        XCTAssertEqual(color.opacity, 1.0, accuracy: 0.01)
    }

    func testRemainingThemeColorsMatchTheirHexValues() {
        let filmStrip = legacyTheme(.filmStrip).textColor
        XCTAssertEqual(filmStrip, .white)

        // #1C1C1E
        let minimalDark = legacyTheme(.minimalDark).textColor
        XCTAssertEqual(minimalDark.red, 28.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(minimalDark.green, 28.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(minimalDark.blue, 30.0 / 255.0, accuracy: 0.01)

        // #FF6B9D
        let softPink = legacyTheme(.softPink).textColor
        XCTAssertEqual(softPink.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(softPink.green, 107.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(softPink.blue, 157.0 / 255.0, accuracy: 0.01)
    }

    /// 0.3 §4.3 (replacing 0.2 §4.3's font column): the five 0.1 themes all
    /// draw in PingFang (32.4).
    func testLegacyThemeFontsFollowTheMigrationTable() {
        for themeID in ThemeID.allCases {
            XCTAssertEqual(legacyTheme(themeID).fontID, .pingFang, "32.4 \(themeID)")
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

    /// The 0.5 opacities stored on 8-bit steps (TASK-71): 0.6 is exact,
    /// 0.75 and 0.9 become 191/255 and 230/255.
    private let softShadow = OverlayDecoration.shadow(offset: CGSize(width: 0, height: 2), blur: 4,
                                                      opacity: 153.0 / 255, color: .black)
    private let dark = OverlayColor(red8: 0x1C, green8: 0x1C, blue8: 0x1E)
    private let blue = OverlayColor(red8: 0x0A, green8: 0x84, blue8: 0xFF)
    private let insets = OverlayInsets(horizontal: 12, vertical: 6)

    /// TASK-81: both box shapes share geometry and alpha, except radius.
    func testSquareBoxSharesPaddingColorOpacityWithRoundedBox() {
        for padding in [0.0, 7, 12, 24] {
            for color in [Optional<OverlayColor>.none, blue.withOpacity(0.5)] {
                var style = OverlayStyle(outline: .box, outlineColor: color,
                                         autoOutlineOpacity: 0.5, boxPadding: padding, shadow: .none)
                style.outline = .squareBox
                let square = OverlayTheme(style: style)
                XCTAssertEqual(square.decorations, [.backgroundBox(
                    color: style.resolvedOutlineColor, opacity: 1, cornerRadius: 0,
                    insets: OverlayInsets(horizontal: padding, vertical: padding / 2))], "81.5")
            }
        }
    }

    func testDefaultStyleHasExactlyTheSoftShadow() {
        XCTAssertEqual(OverlayTheme(style: OverlayStyle()).decorations, [softShadow], "18.1")
    }

    func testSolidBoxWithAutomaticColorUsesTheContrastColor() {
        let style = OverlayStyle(textColor: .white, outline: .box, outlineColor: nil, shadow: .none)
        XCTAssertEqual(OverlayTheme(style: style).decorations,
                       [.backgroundBox(color: dark, opacity: 1.0, cornerRadius: 8, insets: insets)], "18.2")
    }

    func testSolidBoxWithExplicitColorUsesIt() {
        let style = OverlayStyle(textColor: .white, outline: .box, outlineColor: blue, shadow: .none)
        XCTAssertEqual(OverlayTheme(style: style).decorations,
                       [.backgroundBox(color: blue, opacity: 1.0, cornerRadius: 8, insets: insets)], "18.3")
    }

    func testNoOutlineAndNoShadowHasNoDecorations() {
        XCTAssertTrue(OverlayTheme(style: OverlayStyle(outline: .none, shadow: .none)).decorations.isEmpty, "18.4")
    }

    func testEveryOutlineMatchesTheConstantTable() {
        let expected: [OverlayOutline: OverlayDecoration] = [
            .stroke: .stroke(color: blue, width: 2),
            .box: .backgroundBox(color: blue, opacity: 1.0, cornerRadius: 8, insets: insets),
            .squareBox: .backgroundBox(color: blue, opacity: 1.0, cornerRadius: 0, insets: insets)
        ]
        for outline in OverlayOutline.allCases {
            let theme = OverlayTheme(style: OverlayStyle(outline: outline, outlineColor: blue, shadow: .none))
            XCTAssertEqual(theme.decorations.first, expected[outline], "\(outline)")
        }
    }

    /// TASK-70: the stroke width and box padding come from the style, as
    /// 17pt values; the vertical padding is half the horizontal and the
    /// corner radius stays 8.
    func testOutlineParametersReachTheDecorations() {
        for width in [1.0, 2.5, 4, 6] {
            let theme = OverlayTheme(style: OverlayStyle(outline: .stroke, outlineColor: blue,
                                                         strokeWidth: width, shadow: .none))
            XCTAssertEqual(theme.decorations, [.stroke(color: blue, width: width)], "70.3 stroke \(width)")
        }
        for padding in [0.0, 7, 12, 24] {
            let theme = OverlayTheme(style: OverlayStyle(outline: .box, outlineColor: blue,
                                                         boxPadding: padding, shadow: .none))
            let expected = OverlayInsets(horizontal: padding, vertical: padding / 2)
            XCTAssertEqual(theme.decorations,
                           [.backgroundBox(color: blue, opacity: 1, cornerRadius: 8, insets: expected)],
                           "70.3 box \(padding)")
        }
        XCTAssertEqual(OverlayTheme.boxInsets(padding: 12), insets, "the 0.5 boxes' 12x6")
    }

    /// TASK-70: a box's transparency is the outline alpha alone — of the
    /// chosen color, or `autoOutlineOpacity` on the automatic one.
    func testBoxTransparencyIsTheOutlineAlpha() {
        let auto = OverlayTheme(style: OverlayStyle(textColor: .white, outline: .box,
                                                    autoOutlineOpacity: 0.5, shadow: .none))
        XCTAssertEqual(auto.decorations,
                       [.backgroundBox(color: dark.withOpacity(0.5), opacity: 1, cornerRadius: 8, insets: insets)])
        let opaqueAuto = OverlayTheme(style: OverlayStyle(textColor: .white, outline: .stroke, shadow: .none))
        XCTAssertEqual(opaqueAuto.decorations, [.stroke(color: dark, width: 2)], "automatic stays opaque by default")
    }

    /// TASK-86: a preset applied to a new style sets only the geometry; every
    /// preset shares the default black at 60%, and none follows the text colour
    /// unless the source is chosen explicitly.
    func testEveryShadowMatchesTheConstantTable() {
        let pink = OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D)
        let expected: [OverlayShadowPreset: OverlayDecoration] = [
            .soft: softShadow,
            .hard: .shadow(offset: CGSize(width: 2, height: 2), blur: 0, opacity: 153.0 / 255, color: .black),
            .glow: .shadow(offset: .zero, blur: 8, opacity: 153.0 / 255, color: .black)
        ]
        for shadow in OverlayShadowPreset.allCases {
            let theme = OverlayTheme(style: OverlayStyle(textColor: pink, outline: .none, shadow: shadow))
            XCTAssertEqual(theme.decorations.first, expected[shadow], "\(shadow)")
        }
    }

    /// TASK-69: the glow is cast by the text's ink, which already carries the
    /// text alpha, so its color is the opaque text color — the alpha is
    /// applied once, not squared. Outline colors keep their alpha.
    func testTranslucentColorsReachTheDecorations() {
        let pink = OverlayColor(red8: 0xFF, green8: 0x6B, blue8: 0x9D)
        var glowStyle = OverlayStyle(textColor: pink.withOpacity(0.5), outline: .none, shadow: .glow)
        glowStyle.shadowColorSource = .textColor // TASK-86: following the text is an explicit choice
        glowStyle.shadowOpacity = 230.0 / 255
        let glow = OverlayTheme(style: glowStyle)
        XCTAssertEqual(glow.textColor.opacity, 0.5)
        XCTAssertEqual(glow.decorations, [.shadow(offset: .zero, blur: 8, opacity: 230.0 / 255, color: pink)], "69.2")

        let faded = blue.withOpacity(0.4)
        let stroke = OverlayTheme(style: OverlayStyle(outline: .stroke, outlineColor: faded, shadow: .none))
        XCTAssertEqual(stroke.decorations, [.stroke(color: faded, width: 2)], "69.5")
        let box = OverlayTheme(style: OverlayStyle(outline: .box, outlineColor: faded, shadow: .none))
        XCTAssertEqual(box.decorations, [.backgroundBox(color: faded, opacity: 1, cornerRadius: 8, insets: insets)],
                       "69.5: the box is drawn in the color's alpha")
    }

    /// TASK-71 71.1: the offsets and blur come from the style as 17pt values;
    /// the color goes in opaque with its alpha as `opacity`, so the alpha is
    /// applied once.
    func testShadowParametersReachTheDecoration() {
        var style = OverlayStyle(textColor: blue, outline: .none)
        style.shadowColor = OverlayColor(red8: 0xED, green8: 0x49, blue8: 0x56, opacity: 0.4)
        style.shadowOffsetX = -8
        style.shadowOffsetY = 5.5
        style.shadowBlur = 16
        XCTAssertEqual(OverlayTheme(style: style).decorations,
                       [.shadow(offset: CGSize(width: -8, height: 5.5), blur: 16, opacity: 0.4,
                                color: OverlayColor(red8: 0xED, green8: 0x49, blue8: 0x56))], "71.1")

        style.shadowColorSource = .textColor
        style.textColor = blue.withOpacity(0.5)
        XCTAssertEqual(OverlayTheme(style: style).decorations,
                       [.shadow(offset: CGSize(width: -8, height: 5.5), blur: 16, opacity: 0.4, color: blue)],
                       "71.4: the text color's RGB at the shadow's own alpha")

        style.showsShadow = false
        XCTAssertTrue(OverlayTheme(style: style).decorations.isEmpty, "off draws no shadow")
    }

    /// The outline comes first so the shadow is cast by the outlined text.
    func testOutlineIsAppliedBeforeShadow() {
        let theme = OverlayTheme(style: OverlayStyle(outline: .stroke, shadow: .soft))
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
