import UIKit
import XCTest
@testable import DaysCam

/// Covers TASK-17 17.2 and 17.9 ... 17.11, and TASK-32 32.1/32.2 for the font
/// IDs: the style model, its fonts and the `OverlayColor` additions it relies
/// on (PRD 0.2 §4.2, FR-10; PRD 0.3 §4.1).
final class OverlayStyleTests: XCTestCase {

    private func hex(_ string: String, file: StaticString = #filePath, line: UInt = #line) throws -> OverlayColor {
        try XCTUnwrap(OverlayColor(hex: string), "bad fixture \(string)", file: file, line: line)
    }

    // MARK: - Fonts

    // 0.2's 17.1 (ten Latin names) and 17.12 (every 0.2 font ships with iOS)
    // are replaced by TASK-32 32.1 in `FontCatalogTests` (TASKS-0.3 事先預告 1).

    /// 32.1 / 40.1: the raw values, in PRD 0.3 §4.1 order plus TASK-40's
    /// `chenyuluoyan`, are what files store.
    func testFontIDsAreTheTwentyTwoInOrder() {
        XCTAssertEqual(OverlayFontID.allCases.map(\.rawValue),
                       ["pingFang", "huninn", "notoSerifTC", "iansui", "chenyuluoyan", "lantinghei", "liHei", "hiraginoSans",
                        "yuanti", "songti", "liSong", "kaiti", "biauKai", "hanziPen", "hannotate", "lingWai",
                        "xingkai", "weibei", "libian", "baoli", "wawa", "yuppy"],
                       "32.1 / 40.1")
    }

    /// 40.4: a stored `chenyuluoyan` reads back as itself.
    func testChenyuluoyanRoundTrips() throws {
        let decoded = try JSONDecoder().decode([OverlayFontID].self, from: Data(#"["chenyuluoyan"]"#.utf8))
        XCTAssertEqual(decoded, [.chenyuluoyan], "40.4")
        var style = OverlayStyle()
        style.fontID = .chenyuluoyan
        let data = try JSONEncoder().encode(style)
        XCTAssertEqual(try JSONDecoder().decode(OverlayStyle.self, from: data).fontID, .chenyuluoyan, "40.4")
    }

    /// 32.2: the 0.2 fonts and any unknown value decode as PingFang; known
    /// 0.3 values decode as themselves.
    func testRemovedAndUnknownFontIDsDecodeAsPingFang() throws {
        let json = #"["futura","sfRounded","不存在","comicSans","songti"]"#
        let decoded = try JSONDecoder().decode([OverlayFontID].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, [.pingFang, .pingFang, .pingFang, .pingFang, .songti], "32.2")
        XCTAssertEqual(OverlayFontID.fallback, .pingFang)
    }

    /// The TEMP aliases are not cases: they never round-trip as a 0.2 name.
    func testRemovedFontNamesAreNotCases() {
        for name in ["sfRounded", "sfPro", "sfMono", "newYork", "avenirNext",
                     "futura", "georgia", "americanTypewriter", "didot", "snellRoundhand"] {
            XCTAssertNil(OverlayFontID(rawValue: name), name)
        }
    }

    // MARK: - Defaults

    func testDefaultStyleMatchesClassicWhite() throws {
        let style = OverlayStyle()
        XCTAssertEqual(style.fontID, .pingFang, "17.2 / PRD 0.3 §4.1")
        XCTAssertEqual(style.textColor, try hex("#FFFFFF"), "17.2")
        XCTAssertEqual(style.outline, .none, "17.2")
        XCTAssertNil(style.outlineColor, "17.2")
        XCTAssertEqual(style.shadow, .soft, "17.2")
        XCTAssertEqual(style.sizeScale, 100, "17.2")
    }

    func testSwatchesAreTheNinePresetColorsInOrder() {
        XCTAssertEqual(OverlayStyle.swatches.map(\.hexString),
                       ["#FFFFFF", "#000000", "#3897F0", "#70C050", "#FDCB5C",
                        "#FD8D32", "#ED4956", "#D10869", "#A307BA"])
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

    // MARK: - Opacity (TASK-69)

    /// 69.1: `#RRGGBB` reads as fully opaque, and an opaque color still
    /// writes six digits, so pre-TASK-69 files read and write unchanged.
    func testSixDigitHexIsOpaqueAndOpaqueColorsStillWriteSixDigits() throws {
        let color = try hex("#123456")
        XCTAssertEqual(color.opacity, 1, "69.1")
        XCTAssertEqual(color.hexString, "#123456", "69.1")
        XCTAssertEqual(OverlayColor.white.withOpacity(0.999).hexString, "#FFFFFF", "rounds to opaque")
    }

    /// 69.3: `#RRGGBBAA` parses, writes back the same, and round-trips
    /// through JSON.
    func testEightDigitHexCarriesAlphaAndRoundTrips() throws {
        let color = try hex("#ff95004d")
        XCTAssertEqual(color, OverlayColor(red8: 0xFF, green8: 0x95, blue8: 0x00, opacity: 0x4D / 255.0), "69.3")
        XCTAssertEqual(color.hexString, "#FF95004D", "69.3")
        XCTAssertEqual(OverlayColor.white.withOpacity(0.5).hexString, "#FFFFFF80", "69.3: 0.5 → 0x80")

        let data = try JSONEncoder().encode([color])
        XCTAssertEqual(String(data: data, encoding: .utf8), ##"["#FF95004D"]"##, "69.3")
        XCTAssertEqual(try JSONDecoder().decode([OverlayColor].self, from: data), [color], "69.3")
    }

    func testEightDigitHexRejectsMalformedStrings() {
        for bad in ["FF950080", "#FF95008G", "#FF9500800", "#FF95 080"] {
            XCTAssertNil(OverlayColor(hex: bad), bad)
        }
    }

    /// 69.4: an alpha below the minimum read from a file is raised to the
    /// smallest storable 8-bit step instead of discarding anything.
    func testTooFaintAlphaIsRaisedToTheMinimumOnRead() throws {
        for string in ["#FFFFFF00", "#FFFFFF0C"] {
            let color = try hex(string)
            XCTAssertEqual(color.opacity, 13.0 / 255, "69.4 \(string)")
            XCTAssertTrue(color.isStorable, "69.4 \(string)")
        }
        XCTAssertEqual(try hex("#FFFFFF0D").opacity, 13.0 / 255, "the first storable step is kept")
    }

    /// 69.4: storable means RGB in 0...1 and opacity in 0.05...1.
    func testStorableOpacityRange() {
        XCTAssertEqual(OverlayColor.minimumStorableOpacity, 0.05)
        for opacity in [0.05, 13.0 / 255, 0.5, 1] {
            XCTAssertTrue(OverlayColor.white.withOpacity(opacity).isStorable, "69.4 \(opacity)")
        }
        for opacity in [0, 0.049, 12.0 / 255, 1.0001, -1, .nan, .infinity] {
            XCTAssertFalse(OverlayColor.white.withOpacity(opacity).isStorable, "69.4 \(opacity)")
        }
    }

    /// Every storable opacity still is after 8-bit rounding, so validating
    /// before or after `quantized` cannot disagree at the lower bound.
    func testQuantizedRoundsEveryComponentWithoutClamping() {
        let color = OverlayColor(red: 0.1234, green: 0.5, blue: 1.2, opacity: 0.05)
        let quantized = color.quantized
        XCTAssertEqual(quantized.red, 31.0 / 255)
        XCTAssertEqual(quantized.green, 128.0 / 255)
        XCTAssertEqual(quantized.blue, 306.0 / 255, "out of range stays out of range")
        XCTAssertEqual(quantized.opacity, 13.0 / 255)
        XCTAssertTrue(OverlayColor.white.withOpacity(0.05).quantized.isStorable)
        XCTAssertEqual(OverlayStyle.swatches.map(\.quantized), OverlayStyle.swatches, "8-bit colors are fixed points")
    }

    func testWithOpacityKeepsTheRGBComponents() {
        let orange = OverlayColor(red8: 0xFF, green8: 0x95, blue8: 0x00)
        let faded = orange.withOpacity(0.4)
        XCTAssertEqual(faded.red, orange.red)
        XCTAssertEqual(faded.green, orange.green)
        XCTAssertEqual(faded.blue, orange.blue)
        XCTAssertEqual(faded.opacity, 0.4)
        XCTAssertEqual(faded.withOpacity(1), orange)
    }

    func testStyleRoundTripsThroughJSON() throws {
        let style = OverlayStyle(fontID: .xingkai,
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
