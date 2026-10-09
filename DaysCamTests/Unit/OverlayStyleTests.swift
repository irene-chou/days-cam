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

    /// TASK-81 81.3–81.5: changing box shape keeps all stored parameters.
    func testBoxShapesPreserveParametersAndRoundTrip() throws {
        for outline in [OverlayOutline.none, .stroke, .box, .squareBox] {
            var style = OverlayStyle(outline: .box,
                                     outlineColor: .black.withOpacity(128.0 / 255),
                                     boxPadding: 20, shadow: .none)
            style.outline = outline
            XCTAssertEqual(style.boxPadding, 20)
            XCTAssertEqual(style.outlineOpacity, 128.0 / 255)
            XCTAssertEqual(style.resolvedOutlineColor, .black.withOpacity(128.0 / 255))
            XCTAssertTrue(style.hasValidOutlineParameters)
            let data = try JSONEncoder().encode(style)
            XCTAssertEqual(try JSONDecoder().decode(OverlayStyle.self, from: data), style, "81.4")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["outline"] as? String, outline.rawValue)
        }
        XCTAssertTrue(OverlayOutline.box.isBox)
        XCTAssertTrue(OverlayOutline.squareBox.isBox)
        XCTAssertFalse(OverlayOutline.none.isBox)
        XCTAssertFalse(OverlayOutline.stroke.isBox)
    }

    func testSquareBoxProfileRoundTripsAndValidates() throws {
        var profile = CameraProfile(name: "小寶", startDate: DateComponents(year: 2026, month: 1, day: 1),
                                    style: OverlayStyle(outline: .squareBox, boxPadding: 24))
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CameraProfile.self, from: data)
        XCTAssertEqual(decoded, profile, "81.4 reload preserves the profile")
        XCTAssertNoThrow(try decoded.validate())
        profile.style.boxPadding = 25
        XCTAssertThrowsError(try profile.validate())
    }

    func testUnknownOutlineRawValueStillThrowsDataCorrupted() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(OverlayOutline.self, from: Data(#""futureBox""#.utf8))) {
            guard case DecodingError.dataCorrupted = $0 else {
                return XCTFail("Expected dataCorrupted, got \($0)")
            }
        }
        let data = try JSONEncoder().encode(OverlayStyle())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["outline"] = "futureBox"
        let unknown = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(OverlayStyle.self, from: unknown)) {
            guard case DecodingError.dataCorrupted(let context) = $0 else {
                return XCTFail("Expected dataCorrupted, got \($0)")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "outline")
        }
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
        XCTAssertEqual(style.autoOutlineOpacity, 1, "TASK-70")
        XCTAssertEqual(style.strokeWidth, 2, "TASK-70")
        XCTAssertEqual(style.boxPadding, 12, "TASK-70")
        XCTAssertEqual(style.shadowPreset, .soft, "17.2")
        XCTAssertTrue(style.showsShadow, "17.2")
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
                                 outline: .stroke,
                                 outlineColor: try hex("#0A84FF"),
                                 autoOutlineOpacity: 0.4,
                                 strokeWidth: 4.5,
                                 boxPadding: 3,
                                 shadow: .hard,
                                 sizeScale: 70)
        let data = try JSONEncoder().encode(style)
        XCTAssertEqual(try JSONDecoder().decode(OverlayStyle.self, from: data), style)

        var custom = style
        custom.showsShadow = false
        custom.shadowColorSource = .textColor
        custom.shadowColor = try hex("#ED495666")
        custom.shadowOffsetX = -7.5
        custom.shadowOffsetY = 8
        custom.shadowBlur = 12.25
        let customData = try JSONEncoder().encode(custom)
        XCTAssertEqual(try JSONDecoder().decode(OverlayStyle.self, from: customData), custom, "71.5")
    }

    // MARK: - Outline (TASK-70)

    /// 70.1 / 81.5: the four raw values stored in profiles.
    func testOutlinesIncludeSquareBox() {
        XCTAssertEqual(OverlayOutline.allCases.map(\.rawValue), ["none", "stroke", "box", "squareBox"], "70.1 / 81.5")
    }

    func testOutlineParameterRanges() {
        XCTAssertEqual(OverlayStyle.strokeWidthRange, 1...6)
        XCTAssertEqual(OverlayStyle.boxPaddingRange, 0...24)
        for (width, valid) in [(1.0, true), (6, true), (0.99, false), (6.01, false), (0, false), (.nan, false)] {
            XCTAssertEqual(OverlayStyle(strokeWidth: width).hasValidOutlineParameters, valid, "70.4 width \(width)")
        }
        for (padding, valid) in [(0.0, true), (24, true), (-0.01, false), (24.01, false), (.infinity, false)] {
            XCTAssertEqual(OverlayStyle(boxPadding: padding).hasValidOutlineParameters, valid, "70.4 padding \(padding)")
        }
    }

    /// 70.4: both parameters survive switching the outline away and back.
    func testParametersAreKeptWhileAnotherOutlineIsChosen() throws {
        var style = OverlayStyle(outline: .stroke, strokeWidth: 5, boxPadding: 20)
        style.outline = .box
        style.outline = .none
        let decoded = try JSONDecoder().decode(OverlayStyle.self, from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded.strokeWidth, 5)
        XCTAssertEqual(decoded.boxPadding, 20)
    }

    /// `outlineOpacity` edits whichever alpha is drawn: the chosen color's,
    /// or the automatic color's.
    func testOutlineOpacityFollowsTheDrawnColor() throws {
        var auto = OverlayStyle(textColor: .white)
        XCTAssertEqual(auto.outlineOpacity, 1)
        auto.outlineOpacity = 0.3
        XCTAssertNil(auto.outlineColor, "automatic stays automatic")
        XCTAssertEqual(auto.autoOutlineOpacity, 0.3)
        XCTAssertEqual(auto.resolvedOutlineColor, OverlayColor.autoContrastDark.withOpacity(0.3))

        let blue = try hex("#0A84FF")
        var chosen = OverlayStyle(outlineColor: blue)
        chosen.outlineOpacity = 0.6
        XCTAssertEqual(chosen.outlineColor, blue.withOpacity(0.6))
        XCTAssertEqual(chosen.autoOutlineOpacity, 1, "the automatic alpha is untouched")
        XCTAssertEqual(chosen.outlineOpacity, 0.6)
    }

    private func decodeStyle(outline: String, outlineColor: String?, extra: String = "") throws -> OverlayStyle {
        let color = outlineColor.map { #","outlineColor":"\#($0)""# } ?? ""
        let json = ##"{"fontID":"songti","textColor":"#FF6B9D","outline":"\##(outline)"\##(color),"shadow":"hard","sizeScale":115\##(extra)}"##
        return try JSONDecoder().decode(OverlayStyle.self, from: Data(json.utf8))
    }

    /// 70.2 / 70.5: the migration table, with an automatic and a chosen
    /// outline color. Nothing else in the style changes.
    func testLegacyOutlinesMigrate() throws {
        let blue = try hex("#0A84FF")
        typealias Expected = (outline: OverlayOutline, width: Double, padding: Double, alpha: Double)
        let table: [(String, Expected)] = [
            ("thinStroke", (.stroke, 2, 12, 1)),
            ("thickStroke", (.stroke, 4, 12, 1)),
            ("translucentBox", (.box, 2, 12, 0.5)),
            ("solidBox", (.box, 2, 12, 1))
        ]
        for (legacy, expected) in table {
            for outlineColor in [nil, "#0A84FF"] {
                let style = try decodeStyle(outline: legacy, outlineColor: outlineColor)
                let label = "70.2 \(legacy) \(outlineColor ?? "auto")"
                XCTAssertEqual(style.outline, expected.outline, label)
                XCTAssertEqual(style.strokeWidth, expected.width, label)
                XCTAssertEqual(style.boxPadding, expected.padding, label)
                XCTAssertEqual(style.outlineOpacity, expected.alpha, label)
                if outlineColor == nil {
                    XCTAssertNil(style.outlineColor, "\(label): automatic is kept")
                } else {
                    XCTAssertEqual(style.outlineColor, blue.withOpacity(expected.alpha), label)
                    XCTAssertEqual(style.autoOutlineOpacity, 1, label)
                }
                XCTAssertEqual(style.fontID, .songti, label)
                XCTAssertEqual(style.textColor, try hex("#FF6B9D"), label)
                XCTAssertEqual(style.shadowPreset, .hard, label)
                XCTAssertEqual(style.sizeScale, 115, label)
            }
        }
    }

    /// A translucent box over an already translucent color multiplies the
    /// two, as 0.5 drew it; below the storable minimum it is raised to it.
    func testTranslucentBoxHalvesAnAlreadyTranslucentColor() throws {
        let style = try decodeStyle(outline: "translucentBox", outlineColor: "#0A84FF80")
        XCTAssertEqual(style.outlineOpacity, 128.0 / 255 * 0.5, accuracy: 1e-12)
        let faint = try decodeStyle(outline: "translucentBox", outlineColor: "#0A84FF0D")
        XCTAssertEqual(faint.outlineOpacity, OverlayColor.minimumStorableOpacity)
    }

    /// The migrated style is written in the new format and reads back equal.
    func testLegacyOutlineIsWrittenInTheNewFormat() throws {
        let migrated = try decodeStyle(outline: "translucentBox", outlineColor: nil)
        let data = try JSONEncoder().encode(migrated)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["outline"] as? String, "box")
        XCTAssertEqual(object["boxPadding"] as? Double, 12)
        XCTAssertEqual(object["autoOutlineOpacity"] as? Double, 0.5)
        XCTAssertEqual(try JSONDecoder().decode(OverlayStyle.self, from: data), migrated)
    }

    /// Out-of-range parameters in a file are clamped, so the profile is kept
    /// (writing them is rejected; see `CameraProfileOutlineTests`).
    func testOutOfRangeParametersInAFileAreClamped() throws {
        let style = try decodeStyle(outline: "stroke", outlineColor: nil,
                                    extra: #","strokeWidth":40,"boxPadding":-3,"autoOutlineOpacity":0"#)
        XCTAssertEqual(style.strokeWidth, 6)
        XCTAssertEqual(style.boxPadding, 0)
        XCTAssertEqual(style.autoOutlineOpacity, OverlayColor.minimumStorableOpacity)
        XCTAssertTrue(style.hasValidOutlineParameters)
    }

    func testUnknownOutlineIsRejected() {
        XCTAssertThrowsError(try decodeStyle(outline: "glitter", outlineColor: nil))
    }

    // MARK: - Shadow (TASK-71)

    /// 86: new presets share black at 60%; only geometry differs.
    func testShadowPresetsHaveGeometryAndCommonDefaultColor() {
        XCTAssertEqual(OverlayShadowPreset.allCases.map(\.rawValue), ["none", "soft", "hard", "glow"])
        let table: [(OverlayShadowPreset, OverlayShadowColorSource, Double, Double, Double, Double)] = [
            (.soft, .custom, 0.6, 0, 2, 4),
            (.hard, .custom, 0.6, 2, 2, 0),
            (.glow, .custom, 0.6, 0, 0, 8)
        ]
        for (preset, source, opacity, x, y, blur) in table {
            let style = OverlayStyle(shadow: preset)
            XCTAssertTrue(style.showsShadow, "\(preset)")
            XCTAssertEqual(style.shadowColorSource, source, "\(preset)")
            XCTAssertEqual(style.shadowOpacity, opacity, accuracy: 0.5 / 255, "\(preset)")
            XCTAssertEqual(style.shadowColor, style.shadowColor.quantized, "\(preset) is stored as is")
            XCTAssertEqual(style.shadowOffsetX, x, "\(preset)")
            XCTAssertEqual(style.shadowOffsetY, y, "\(preset)")
            XCTAssertEqual(style.shadowBlur, blur, "\(preset)")
            if source == .custom {
                XCTAssertEqual(style.resolvedShadowColor, OverlayColor.black.withOpacity(style.shadowOpacity))
            }
        }
        XCTAssertFalse(OverlayStyle(shadow: .none).showsShadow)
    }

    /// 86.1 / 86.4: every type preserves exact color, including unquantized alpha.
    func testChangingShadowTypePreservesColorAndSource() throws {
        for source in OverlayShadowColorSource.allCases {
            var style = OverlayStyle()
            style.shadowColorSource = source
            style.shadowColor = try hex("#FF0000").withOpacity(0.371)
            let color = style.shadowColor
            for preset in [OverlayShadowPreset.soft, .hard, .glow, .none, .hard] {
                let before = style
                style.applyShadowPreset(preset)
                XCTAssertEqual(style.shadowColor, color)
                XCTAssertEqual(style.shadowColorSource, source)
                XCTAssertEqual(style.shadowPreset, preset)
                if preset == .none {
                    XCTAssertEqual(style.shadowOffsetX, before.shadowOffsetX)
                    XCTAssertEqual(style.shadowOffsetY, before.shadowOffsetY)
                    XCTAssertEqual(style.shadowBlur, before.shadowBlur)
                }
            }
        }
    }

    func testShadowParameterRanges() {
        XCTAssertEqual(OverlayStyle.shadowOffsetRange, -8...8)
        XCTAssertEqual(OverlayStyle.shadowBlurRange, 0...16)
        let offsets: [(Double, Bool)] = [(-8, true), (8, true), (0, true), (-8.01, false), (8.01, false), (.nan, false)]
        for (offset, valid) in offsets {
            var x = OverlayStyle()
            x.shadowOffsetX = offset
            XCTAssertEqual(x.hasValidShadowParameters, valid, "71.5 x \(offset)")
            var y = OverlayStyle()
            y.shadowOffsetY = offset
            XCTAssertEqual(y.hasValidShadowParameters, valid, "71.5 y \(offset)")
        }
        for (blur, valid) in [(0.0, true), (16, true), (-0.01, false), (16.01, false), (.infinity, false)] {
            var style = OverlayStyle()
            style.shadowBlur = blur
            XCTAssertEqual(style.hasValidShadowParameters, valid, "71.5 blur \(blur)")
        }
    }

    /// 71.3: applying a preset fills in its parameters, and the style names
    /// that preset until a parameter moves away from it.
    func testShadowPresetIsAppliedAndRecognized() throws {
        for preset in OverlayShadowPreset.allCases {
            var style = OverlayStyle(textColor: try hex("#FF6B9D80"), shadow: .soft)
            style.shadowOffsetX = 5
            style.applyShadowPreset(preset)
            XCTAssertEqual(style.shadowPreset, preset, "71.3 \(preset)")
            let reloaded = try JSONDecoder().decode(OverlayStyle.self, from: JSONEncoder().encode(style))
            XCTAssertEqual(reloaded.shadowPreset, preset, "71.3 \(preset) after a restart")
        }

        let edits: [(String, (inout OverlayStyle) -> Void)] = [
            ("x", { $0.shadowOffsetX = 1 }),
            ("y", { $0.shadowOffsetY = 3 }),
            ("blur", { $0.shadowBlur = 4.5 })
        ]
        for (name, edit) in edits {
            var style = OverlayStyle(shadow: .soft)
            edit(&style)
            XCTAssertNil(style.shadowPreset, "86.3: \(name)")
            style.applyShadowPreset(.soft)
            XCTAssertEqual(style.shadowPreset, .soft)
        }
        let colorEdits: [(String, (inout OverlayStyle) -> Void)] = [
            ("alpha", { $0.shadowOpacity = 0.5 }),
            ("color", { $0.shadowColor = OverlayColor.white.withOpacity($0.shadowOpacity) }),
            ("source", { $0.shadowColorSource = .textColor })
        ]
        for (name, edit) in colorEdits {
            var style = OverlayStyle(shadow: .soft)
            edit(&style)
            XCTAssertEqual(style.shadowPreset, .soft, "86.2: \(name)")
        }
    }

    /// 86.2: preset selection ignores RGB; any disabled shadow is none.
    func testShadowPresetIgnoresWhatIsNotDrawn() throws {
        var glow = OverlayStyle(shadow: .glow)
        glow.shadowColor = try hex("#0A84FF").withOpacity(glow.shadowOpacity)
        XCTAssertEqual(glow.shadowPreset, .glow)

        var off = OverlayStyle(shadow: .hard)
        off.shadowBlur = 11
        off.showsShadow = false
        XCTAssertEqual(off.shadowPreset, OverlayShadowPreset.none)
    }

    /// Turning the shadow off keeps its parameters for turning it back on.
    func testNonePresetKeepsTheParameters() {
        var style = OverlayStyle(shadow: .hard)
        style.shadowBlur = 3
        let before = style
        style.applyShadowPreset(.none)
        XCTAssertFalse(style.showsShadow)
        XCTAssertEqual(style.shadowBlur, 3)
        style.showsShadow = true
        XCTAssertEqual(style, before)
    }

    /// 71.4: following the text color, the shadow takes each new text color's
    /// RGB, at the shadow's own alpha.
    func testTextColorShadowFollowsTheTextColor() throws {
        var style = OverlayStyle(textColor: try hex("#FF6B9D"), shadow: .glow)
        style.shadowColorSource = .textColor
        style.shadowOpacity = 230.0 / 255
        XCTAssertEqual(style.resolvedShadowColor, try hex("#FF6B9D").withOpacity(230.0 / 255), "71.4")
        style.textColor = try hex("#3897F080")
        XCTAssertEqual(style.resolvedShadowColor, try hex("#3897F0").withOpacity(230.0 / 255), "71.4")

        style.shadowColorSource = .custom
        XCTAssertEqual(style.resolvedShadowColor, style.shadowColor, "custom draws the stored color")
    }

    func testShadowOpacityIsTheShadowColorAlpha() throws {
        var style = OverlayStyle(shadow: .soft)
        style.shadowOpacity = 0.3
        XCTAssertEqual(style.shadowColor, OverlayColor.black.withOpacity(0.3))
        style.shadowColorSource = .textColor
        XCTAssertEqual(style.resolvedShadowColor.opacity, 0.3)
    }

    private func decodeShadow(_ shadow: String, textColor: String = "#FF6B9D") throws -> OverlayStyle {
        let json = ##"{"fontID":"songti","textColor":"\##(textColor)","outline":"stroke","strokeWidth":3,"shadow":"\##(shadow)","sizeScale":115}"##
        return try JSONDecoder().decode(OverlayStyle.self, from: Data(json.utf8))
    }

    /// 71.2 / 71.5: each 0.5 shadow becomes its preset's parameters; the off
    /// one keeps the soft parameters. Nothing else in the style changes.
    func testLegacyShadowsMigrate() throws {
        for preset in OverlayShadowPreset.allCases {
            let style = try decodeShadow(preset.rawValue)
            let label = "71.2 \(preset)"
            var expected = OverlayStyle(fontID: .songti, textColor: try hex("#FF6B9D"), outline: .stroke,
                                        strokeWidth: 3, shadow: preset, sizeScale: 115)
            if preset == .hard { expected.shadowOpacity = 191.0 / 255 }
            if preset == .glow {
                expected.shadowColorSource = .textColor
                expected.shadowOpacity = 230.0 / 255
            }
            XCTAssertEqual(style, expected, label)
            XCTAssertEqual(style.shadowPreset, preset, label)
            if preset == .none {
                var on = style
                on.showsShadow = true
                XCTAssertEqual(on.shadowPreset, .soft, "\(label): off, with the soft parameters")
            }
        }
    }

    /// The migrated style is written in the new format, without `shadow`,
    /// and reads back equal.
    func testLegacyShadowIsWrittenInTheNewFormat() throws {
        let migrated = try decodeShadow("glow")
        let data = try JSONEncoder().encode(migrated)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["shadow"], "the 0.5 name is never written")
        XCTAssertEqual(object["showsShadow"] as? Bool, true)
        XCTAssertEqual(object["shadowColorSource"] as? String, "textColor")
        XCTAssertEqual(object["shadowColor"] as? String, "#000000E6")
        XCTAssertEqual(object["shadowOffsetX"] as? Double, 0)
        XCTAssertEqual(object["shadowOffsetY"] as? Double, 0)
        XCTAssertEqual(object["shadowBlur"] as? Double, 8)
        XCTAssertEqual(try JSONDecoder().decode(OverlayStyle.self, from: data), migrated)
    }

    /// A file that has the new keys ignores a leftover `shadow`; a missing
    /// parameter falls back to the soft one.
    func testNewShadowKeysWin() throws {
        let json = ##"{"fontID":"songti","textColor":"#FF6B9D","outline":"none","shadow":"glow","showsShadow":true,"shadowBlur":9,"sizeScale":100}"##
        let style = try JSONDecoder().decode(OverlayStyle.self, from: Data(json.utf8))
        XCTAssertEqual(style.shadowColorSource, .custom)
        XCTAssertEqual(style.shadowColor, OverlayStyle(shadow: .soft).shadowColor)
        XCTAssertEqual(style.shadowOffsetY, 2)
        XCTAssertEqual(style.shadowBlur, 9)
    }

    /// 71.5: out-of-range shadow parameters in a file are clamped, so the
    /// profile is kept (writing them is rejected; see
    /// `CameraProfileShadowTests`).
    func testOutOfRangeShadowParametersInAFileAreClamped() throws {
        let json = ##"{"fontID":"songti","textColor":"#FF6B9D","outline":"none","showsShadow":true,"shadowColorSource":"custom","shadowColor":"#ED495600","shadowOffsetX":-20,"shadowOffsetY":9,"shadowBlur":-1,"sizeScale":100}"##
        let style = try JSONDecoder().decode(OverlayStyle.self, from: Data(json.utf8))
        XCTAssertEqual(style.shadowOffsetX, -8)
        XCTAssertEqual(style.shadowOffsetY, 8)
        XCTAssertEqual(style.shadowBlur, 0)
        XCTAssertEqual(style.shadowOpacity, 13.0 / 255, "raised to the storable minimum")
        XCTAssertTrue(style.hasValidShadowParameters)
        let wide = ##"{"fontID":"songti","textColor":"#FF6B9D","outline":"none","showsShadow":false,"shadowBlur":40,"sizeScale":100}"##
        XCTAssertEqual(try JSONDecoder().decode(OverlayStyle.self, from: Data(wide.utf8)).shadowBlur, 16)
    }

    func testUnknownShadowIsRejected() {
        XCTAssertThrowsError(try decodeShadow("neon"))
        let badSource = ##"{"fontID":"songti","textColor":"#FF6B9D","outline":"none","showsShadow":true,"shadowColorSource":"photo","sizeScale":100}"##
        XCTAssertThrowsError(try JSONDecoder().decode(OverlayStyle.self, from: Data(badSource.utf8)))
    }

    // MARK: - Placement coding

    func testPlacementRoundTripsThroughJSON() throws {
        let placements: [OverlayPlacement] = [.anchor(.topLeading), .custom(x: 0.1, y: 0.9)]
        let data = try JSONEncoder().encode(placements)
        XCTAssertEqual(try JSONDecoder().decode([OverlayPlacement].self, from: data), placements)
    }
}
