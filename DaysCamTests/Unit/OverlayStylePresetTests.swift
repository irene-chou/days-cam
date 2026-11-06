import XCTest
@testable import DaysCam

/// Covers #676 (D-10): the ten looks, applying them, recognizing them and the
/// box button's three states.
final class OverlayStylePresetTests: XCTestCase {
    private let blue = OverlayColor(red8: 0x38, green8: 0x97, blue8: 0xF0)

    // 1
    func testApplyingEachPresetFromDefaultSelectsItAtBaseInItsColor() {
        for preset in OverlayStylePreset.allCases {
            var style = OverlayStyle()
            style.apply(preset)
            XCTAssertEqual(style.preset, preset)
            XCTAssertEqual(style.boxState(for: preset), .base, "\(preset)")
            XCTAssertEqual(style.textColor, preset.defaultTextColor, "\(preset)")
        }
    }

    func testPresetTable() {
        let classic = OverlayStylePreset.classic.style
        XCTAssertEqual(classic, OverlayStyle())
        let caption = OverlayStylePreset.caption.style
        XCTAssertEqual(caption.outline, .box)
        XCTAssertEqual(caption.autoOutlineOpacity, 0.45)
        XCTAssertFalse(caption.showsShadow)
        let poster = OverlayStylePreset.poster.style
        XCTAssertEqual(poster.outline, .squareBox)
        XCTAssertEqual(poster.autoOutlineOpacity, 1.0)
        XCTAssertEqual(poster.boxPadding, 12)
        XCTAssertEqual(OverlayStylePreset.outline.style.strokeWidth, 3)
        XCTAssertEqual(OverlayStylePreset.note.style.autoOutlineOpacity, 0.88)
        XCTAssertEqual(OverlayStylePreset.note.defaultTextColor.hexString, "#1C1C1E")
        let cute = OverlayStylePreset.cute.style
        XCTAssertEqual(cute.outline, .stroke)
        XCTAssertEqual(cute.strokeWidth, 2)
        XCTAssertEqual(cute.shadowPreset, .soft)
        XCTAssertEqual(cute.shadowColor.opacity, 0.35, accuracy: 0.5 / 255)
        XCTAssertEqual(cute.textColor.hexString, "#FF6B9D")
        for preset in [OverlayStylePreset.neon, .retro] {
            let style = preset.style
            XCTAssertEqual(style.shadowPreset, .glow)
            XCTAssertEqual(style.shadowColorSource, .textColor)
            XCTAssertEqual(style.shadowColor.opacity, 230.0 / 255)
            XCTAssertEqual(style.outline, OverlayOutline.none)
        }
        XCTAssertEqual(OverlayStylePreset.neon.defaultTextColor.hexString, "#FFD1E3")
        XCTAssertEqual(OverlayStylePreset.retro.defaultTextColor.hexString, "#FF8A1E")
        for preset in OverlayStylePreset.allCases {
            XCTAssertNil(preset.style.outlineColor, "\(preset)")
            XCTAssertEqual(preset.style.sizeScale, 100, "\(preset)")
        }
        XCTAssertEqual(OverlayStylePreset.allCases.map(\.displayName),
                       ["經典", "字幕", "海報", "描邊", "雜誌", "手寫", "便條", "可愛", "霓虹", "復古"])
    }

    // 2
    func testEveryPresetWeightIsAKnownFace() {
        let expected: [OverlayStylePreset: (OverlayFontID, String)] = [
            .classic: (.pingFang, "semibold"), .caption: (.pingFang, "semibold"),
            .poster: (.notoSansTC, "black"), .outline: (.notoSansTC, "black"),
            .magazine: (.notoSerifTC, "bold"), .handwriting: (.chenyuluoyan, "thin"),
            .note: (.iansui, "regular"), .cute: (.huninn, "regular"),
            .neon: (.huninn, "regular"), .retro: (.pingFang, "semibold")
        ]
        for preset in OverlayStylePreset.allCases {
            var style = OverlayStyle()
            style.apply(preset)
            let entry = FontCatalog.entry(for: style.fontID)
            XCTAssertTrue(entry.weights.contains { $0.id == style.fontWeight }, "\(preset)")
            XCTAssertEqual(style.fontID, expected[preset]?.0, "\(preset)")
            XCTAssertEqual(style.fontWeight, expected[preset]?.1, "\(preset)")
            XCTAssertEqual(style.resolvedFontWeight.id, expected[preset]?.1, "\(preset)")
        }
    }

    // 3 (as amended: the soft shadow keeps classic's translucent box from being caption)
    func testClassicCyclesThroughItsOwnStates() {
        var style = OverlayStyle()
        style.cycleBoxState(for: .classic)
        XCTAssertEqual(style.preset, .classic)
        XCTAssertEqual(style.boxState(for: .classic), .solid)
        style.cycleBoxState(for: .classic)
        XCTAssertEqual(style.preset, .classic)
        XCTAssertEqual(style.boxState(for: .classic), .translucent)
        style.cycleBoxState(for: .classic)
        XCTAssertEqual(style.preset, .classic)
        XCTAssertEqual(style.boxState(for: .classic), .base)
        XCTAssertEqual(style, OverlayStyle())
    }

    func testOwnOutlineWinsOverAnotherPresetsBoxState() {
        // Caption's own box is classic's translucent box; with caption's font
        // and shadow it shows as caption.
        var style = OverlayStyle()
        style.apply(.caption)
        XCTAssertEqual(style.preset, .caption)
        XCTAssertEqual(style.boxState(for: .caption), .base)
        XCTAssertEqual(style.boxState(for: .classic), .translucent)
    }

    // 4
    func testPosterAndOutlineCycleBackToTheirOwnOutline() {
        var poster = OverlayStyle()
        poster.apply(.poster)
        poster.cycleBoxState(for: .poster)
        XCTAssertEqual(poster.outline, .box)
        XCTAssertEqual(poster.autoOutlineOpacity, 1.0)
        XCTAssertEqual(poster.boxState(for: .poster), .solid)
        XCTAssertEqual(poster.preset, .poster)
        poster.cycleBoxState(for: .poster)
        XCTAssertEqual(poster.outline, .box)
        XCTAssertEqual(poster.autoOutlineOpacity, 0.45)
        XCTAssertEqual(poster.boxState(for: .poster), .translucent)
        XCTAssertEqual(poster.preset, .poster)
        poster.cycleBoxState(for: .poster)
        XCTAssertEqual(poster.outline, .squareBox)
        XCTAssertEqual(poster.autoOutlineOpacity, 1.0)
        XCTAssertEqual(poster.boxState(for: .poster), .base)

        var outline = OverlayStyle()
        outline.apply(.outline)
        let states: [(OverlayOutline, OverlayBoxState)] = [(.box, .solid), (.box, .translucent), (.stroke, .base)]
        for (expectedOutline, expectedState) in states {
            outline.cycleBoxState(for: .outline)
            XCTAssertEqual(outline.outline, expectedOutline)
            XCTAssertEqual(outline.boxState(for: .outline), expectedState)
            XCTAssertEqual(outline.preset, .outline)
        }
        XCTAssertEqual(outline.strokeWidth, 3)
        XCTAssertEqual(outline, OverlayStylePreset.outline.style)
    }

    // 5
    func testCyclingKeepsFontColorSizeAndShadow() {
        for preset in OverlayStylePreset.allCases {
            var style = OverlayStyle()
            style.apply(preset)
            style.textColor = blue
            style.sizeScale = 130
            let before = style
            for _ in 0..<3 {
                style.cycleBoxState(for: preset)
                XCTAssertEqual(style.fontID, before.fontID)
                XCTAssertEqual(style.fontWeight, before.fontWeight)
                XCTAssertEqual(style.textColor, before.textColor)
                XCTAssertEqual(style.sizeScale, before.sizeScale)
                XCTAssertEqual(style.showsShadow, before.showsShadow)
                XCTAssertEqual(style.shadowColorSource, before.shadowColorSource)
                XCTAssertEqual(style.shadowColor, before.shadowColor)
                XCTAssertEqual(style.shadowOffsetX, before.shadowOffsetX)
                XCTAssertEqual(style.shadowOffsetY, before.shadowOffsetY)
                XCTAssertEqual(style.shadowBlur, before.shadowBlur)
                XCTAssertEqual(style.preset, preset, "\(preset)")
            }
            // Caption's own box is its translucent state, so it has two.
            if preset != .caption { XCTAssertEqual(style, before, "\(preset)") }
        }
    }

    func testCaptionCyclesBetweenItsBoxAndASolidOne() {
        var style = OverlayStyle()
        style.apply(.caption)
        style.cycleBoxState(for: .caption)
        XCTAssertEqual(style.boxState(for: .caption), .solid)
        style.cycleBoxState(for: .caption)
        XCTAssertEqual(style, OverlayStylePreset.caption.style)
        XCTAssertEqual(style.boxState(for: .caption), .base)
    }

    func testCyclingACustomStyleDoesNothing() {
        var style = OverlayStyle(outline: .stroke, strokeWidth: 4, shadow: .hard)
        let before = style
        style.cycleBoxState(for: .classic)
        XCTAssertEqual(style, before)
    }

    // 6
    func testColorFollowsOnlyAnUntouchedPresetColor() {
        var style = OverlayStyle()
        style.apply(.cute)
        style.apply(.classic)
        XCTAssertEqual(style.textColor, .white)

        style.apply(.cute)
        style.textColor = blue
        style.apply(.classic)
        XCTAssertEqual(style.textColor, blue)

        for preset in OverlayStylePreset.allCases {
            var custom = OverlayStyle(shadow: .hard)
            XCTAssertNil(custom.preset)
            custom.apply(preset)
            XCTAssertEqual(custom.textColor, .white, "\(preset)")
            var pink = OverlayStyle(textColor: OverlayStylePreset.cute.defaultTextColor, shadow: .hard)
            pink.apply(preset)
            XCTAssertEqual(pink.textColor, OverlayStylePreset.cute.defaultTextColor, "\(preset)")
        }
    }

    func testApplyingFromABoxStateStillSwapsAnUntouchedColor() {
        var style = OverlayStyle()
        style.apply(.cute)
        style.cycleBoxState(for: .cute)
        XCTAssertEqual(style.preset, .cute)
        style.apply(.neon)
        XCTAssertEqual(style.textColor, OverlayStylePreset.neon.defaultTextColor)
        XCTAssertEqual(style.boxState(for: .neon), .base)
    }

    // 7
    func testApplyingKeepsSize() {
        for preset in OverlayStylePreset.allCases {
            var style = OverlayStyle(sizeScale: 130)
            style.apply(preset)
            XCTAssertEqual(style.sizeScale, 130)
        }
    }

    // 8
    func testDefaultIsClassicAndOldFreeformStylesAreCustom() {
        XCTAssertEqual(OverlayStyle().preset, .classic)
        var thickStroke = OverlayStyle()
        thickStroke.apply(.outline)
        thickStroke.strokeWidth = 4
        XCTAssertNil(thickStroke.preset)
        XCTAssertNil(OverlayStyle(shadow: .hard).preset)
        XCTAssertNil(OverlayStyle(fontID: .lxgwWenKai).preset)
        XCTAssertNil(OverlayStyle(fontID: .notoSerifTC, fontWeight: "black").preset)
        XCTAssertNil(OverlayStyle(outline: .box, autoOutlineOpacity: 0.6).preset)
        for theme in ThemeID.allCases where theme != .classicWhite {
            // 0.1 themes kept their own opacities (A-2), so none is a look.
            let style = OverlayStyle(legacyTheme: theme)
            if theme == .retroOrange { XCTAssertEqual(style.preset, .classic) } else { XCTAssertNil(style.preset) }
        }
    }

    func testTextColorSizeAndShadowRGBDoNotAffectSelection() {
        var style = OverlayStyle()
        style.apply(.neon)
        style.textColor = blue
        style.sizeScale = 70
        style.shadowColor = OverlayColor(red8: 0x12, green8: 0x34, blue8: 0x56, opacity: 230.0 / 255)
        XCTAssertEqual(style.preset, .neon)
    }

    // 9
    func testAppliedStylesRoundTripAndKeepTheirPreset() throws {
        for preset in OverlayStylePreset.allCases {
            for presses in 0..<3 {
                var style = OverlayStyle(sizeScale: 115)
                style.apply(preset)
                for _ in 0..<presses { style.cycleBoxState(for: preset) }
                let decoded = try JSONDecoder().decode(OverlayStyle.self, from: JSONEncoder().encode(style))
                XCTAssertEqual(decoded, style, "\(preset) \(presses)")
                XCTAssertEqual(decoded.preset, preset, "\(preset) \(presses)")
            }
        }
    }

    func testEncodingWritesNoNewKeys() throws {
        var style = OverlayStyle()
        style.apply(.poster)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(style)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), [
            "fontID", "fontWeight", "textColor", "outline", "autoOutlineOpacity", "strokeWidth", "boxPadding",
            "showsShadow", "shadowColorSource", "shadowColor", "shadowOffsetX", "shadowOffsetY", "shadowBlur",
            "sizeScale"
        ])
    }

    func testOldProfilesStillDecode() throws {
        // 0.2–0.5 format: outline and shadow names, no shadow parameters.
        let legacy = Data("""
        {"fontID":"pingFang","textColor":"#FFFFFF","outline":"translucentBox","shadow":"soft","sizeScale":100}
        """.utf8)
        let decoded = try JSONDecoder().decode(OverlayStyle.self, from: legacy)
        XCTAssertEqual(decoded.outline, .box)
        // 0.5's translucent box was drawn at 0.5, not 0.45: a custom style.
        XCTAssertEqual(decoded.autoOutlineOpacity, 0.5)
        XCTAssertNil(decoded.preset)
        XCTAssertNil(decoded.boxState(for: .classic))
        let current = Data("""
        {"fontID":"notoSansTC","fontWeight":"black","textColor":"#FFFFFF","outline":"stroke","autoOutlineOpacity":1,
        "strokeWidth":3,"boxPadding":12,"showsShadow":false,"shadowColorSource":"custom","shadowColor":"#00000099",
        "shadowOffsetX":0,"shadowOffsetY":2,"shadowBlur":4,"sizeScale":100}
        """.utf8)
        XCTAssertEqual(try JSONDecoder().decode(OverlayStyle.self, from: current).preset, .outline)
    }
}
