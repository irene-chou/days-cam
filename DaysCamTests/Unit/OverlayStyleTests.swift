import UIKit
import XCTest
@testable import DaysCam

/// Covers TASK-17 17.1, 17.2 and 17.9 ... 17.12: the style model, its fonts
/// and the `OverlayColor` additions it relies on (PRD 0.2 §4.2, FR-10).
final class OverlayStyleTests: XCTestCase {

    private func hex(_ string: String, file: StaticString = #filePath, line: UInt = #line) throws -> OverlayColor {
        try XCTUnwrap(OverlayColor(hex: string), "bad fixture \(string)", file: file, line: line)
    }

    // MARK: - Fonts

    func testFontDisplayNamesAreInPanelOrder() {
        XCTAssertEqual(OverlayFontID.allCases.map(\.displayName),
                       ["SF Rounded", "SF Pro", "SF Mono", "New York", "Avenir Next",
                        "Futura", "Georgia", "Typewriter", "Didot", "Snell Roundhand"],
                       "17.1")
    }

    func testSystemFontsHaveNoPostScriptName() {
        let systemFonts = OverlayFontID.allCases.filter { $0.postScriptName == nil }
        XCTAssertEqual(systemFonts, [.sfRounded, .sfPro, .sfMono, .newYork])
    }

    /// 17.12 (replaces 0.1 5.11): every named font ships with iOS. If this
    /// fails, the font is removed from the list and reported — never swapped
    /// for another one (PRD 0.2 A-6).
    func testEveryPostScriptFontExistsOnThisOS() {
        for font in OverlayFontID.allCases {
            guard let name = font.postScriptName else { continue }
            XCTAssertNotNil(UIFont(name: name, size: 17), "17.12: \(font) (\(name)) missing")
        }
    }

    func testUnknownFontIDDecodesAsSFRounded() throws {
        let decoded = try JSONDecoder().decode([OverlayFontID].self, from: Data(#"["comicSans","didot"]"#.utf8))
        XCTAssertEqual(decoded, [.sfRounded, .didot], "17.5")
    }

    // MARK: - Defaults

    func testDefaultStyleMatchesClassicWhite() throws {
        let style = OverlayStyle()
        XCTAssertEqual(style.fontID, .sfRounded, "17.2")
        XCTAssertEqual(style.textColor, try hex("#FFFFFF"), "17.2")
        XCTAssertEqual(style.outline, .none, "17.2")
        XCTAssertNil(style.outlineColor, "17.2")
        XCTAssertEqual(style.shadow, .soft, "17.2")
        XCTAssertEqual(style.sizeScale, 100, "17.2")
    }

    func testSwatchesAreTheSevenPresetColorsInOrder() {
        XCTAssertEqual(OverlayStyle.swatches.map(\.hexString),
                       ["#FFFFFF", "#1C1C1E", "#FF9500", "#FFC27A", "#FF6B9D", "#FFD60A", "#0A84FF"])
    }

    func testSizeScaleValidity() {
        for scale in [70, 75, 100, 155, 160] {
            XCTAssertTrue(OverlayStyle(sizeScale: scale).hasValidSizeScale, "\(scale)")
        }
        for scale in [0, 65, 69, 72, 161, 165] {
            XCTAssertFalse(OverlayStyle(sizeScale: scale).hasValidSizeScale, "\(scale)")
        }
    }

    // MARK: - Contrast

    func testAutoContrastColor() throws {
        let cases: [(text: String, expected: String)] = [
            ("#FFFFFF", "#1C1C1E"),
            ("#1C1C1E", "#FFFFFF"),
            ("#FF6B9D", "#FFFFFF"),
            ("#FFD60A", "#1C1C1E")
        ]
        for (text, expected) in cases {
            XCTAssertEqual(try hex(text).autoContrastColor, try hex(expected), "17.9 \(text)")
        }
    }

    func testRelativeLuminanceEndpoints() {
        XCTAssertEqual(OverlayColor.white.relativeLuminance, 1.0, accuracy: 1e-9)
        XCTAssertEqual(OverlayColor.black.relativeLuminance, 0.0, accuracy: 1e-9)
    }

    func testResolvedOutlineColor() throws {
        var style = OverlayStyle(textColor: try hex("#FF6B9D"))
        XCTAssertEqual(style.resolvedOutlineColor, style.textColor.autoContrastColor, "17.10 nil")

        style.outlineColor = try hex("#0A84FF")
        XCTAssertEqual(style.resolvedOutlineColor, try hex("#0A84FF"), "17.10 explicit")
    }

    // MARK: - Hex coding

    func testColorEncodesAsHexStringAndRoundTrips() throws {
        let orange = OverlayColor(red8: 0xFF, green8: 0x95, blue8: 0x00)
        let data = try JSONEncoder().encode([orange])
        XCTAssertEqual(String(data: data, encoding: .utf8), ##"["#FF9500"]"##, "17.11")
        XCTAssertEqual(try JSONDecoder().decode([OverlayColor].self, from: data), [orange], "17.11")
    }

    func testHexParsingRejectsMalformedStrings() {
        for bad in ["FF9500", "#FF950", "#FF95000", "#GG9500", "", "#"] {
            XCTAssertNil(OverlayColor(hex: bad), bad)
        }
        XCTAssertEqual(OverlayColor(hex: "#ff9500"), OverlayColor(red8: 0xFF, green8: 0x95, blue8: 0x00))
        XCTAssertThrowsError(try JSONDecoder().decode([OverlayColor].self, from: Data(#"["red"]"#.utf8)))
    }

    func testStyleRoundTripsThroughJSON() throws {
        let style = OverlayStyle(fontID: .snellRoundhand,
                                 textColor: try hex("#123456"),
                                 outline: .thickStroke,
                                 outlineColor: try hex("#0A84FF"),
                                 shadow: .hard,
                                 sizeScale: 70)
        let data = try JSONEncoder().encode(style)
        XCTAssertEqual(try JSONDecoder().decode(OverlayStyle.self, from: data), style)
    }

    // MARK: - Placement coding

    func testPlacementRoundTripsThroughJSON() throws {
        let placements: [OverlayPlacement] = [.anchor(.topLeading), .custom(x: 0.1, y: 0.9)]
        let data = try JSONEncoder().encode(placements)
        XCTAssertEqual(try JSONDecoder().decode([OverlayPlacement].self, from: data), placements)
    }
}
