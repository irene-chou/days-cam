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

    /// 32.1: the raw values, in PRD 0.3 §4.1 order, are what files store.
    func testFontIDsAreTheTwentyOneOfPRD03InOrder() {
        XCTAssertEqual(OverlayFontID.allCases.map(\.rawValue),
                       ["pingFang", "huninn", "notoSerifTC", "iansui", "lantinghei", "liHei", "hiraginoSans",
                        "yuanti", "songti", "liSong", "kaiti", "biauKai", "hanziPen", "hannotate", "lingWai",
                        "xingkai", "weibei", "libian", "baoli", "wawa", "yuppy"],
                       "32.1")
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
