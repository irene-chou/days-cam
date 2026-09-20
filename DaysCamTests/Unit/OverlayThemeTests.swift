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

    func testFontDesignsAndWeightsMatchTheSpecification() {
        XCTAssertEqual(OverlayTheme.theme(for: .classicWhite).fontDesign, .rounded)
        XCTAssertEqual(OverlayTheme.theme(for: .classicWhite).fontWeight, .bold)
        XCTAssertEqual(OverlayTheme.theme(for: .retroOrange).fontDesign, .monospaced)
        XCTAssertEqual(OverlayTheme.theme(for: .filmStrip).fontDesign, .monospaced)
        XCTAssertEqual(OverlayTheme.theme(for: .minimalDark).fontDesign, .system)
        XCTAssertEqual(OverlayTheme.theme(for: .minimalDark).fontWeight, .semibold)
        XCTAssertEqual(OverlayTheme.theme(for: .softPink).fontDesign, .rounded)
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
