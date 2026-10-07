import UIKit
import XCTest
@testable import DaysCam

/// The fixed-look option previews of the style tab (#155, TASK-49): Y.4
/// (previews do not follow the text color), Y.3 (one clean stroke, not stacked
/// copies), 49.6/49.7 (opaque gray glyph, glow in the glyph color, fixed font).
final class StyleSwatchPreviewTests: XCTestCase {
    func testFixedStyleIgnoresCurrentTextColor() {
        var style = OverlayStyle()
        style.textColor = .white
        style.outlineColor = OverlayColor(red8: 0xFF, green8: 0x00, blue8: 0x00)
        let fixed = StyleSwatchPreview.fixedStyle(from: style)
        XCTAssertEqual(fixed.textColor, StyleSwatchPreview.textColor)
        XCTAssertEqual(fixed.resolvedOutlineColor, StyleSwatchPreview.accentGray)
        XCTAssertEqual(StyleSwatchPreview.textColor.opacity, 1, "49.6 不透明")
    }

    /// 49.7: the preview glyph is SF Rounded Semibold regardless of the font.
    func testPreviewFontIsRoundedSemibold() {
        let font = StyleSwatchPreview.previewFont(ofSize: 25)
        XCTAssertEqual(font.pointSize, 25)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? CGFloat) ?? 0
        XCTAssertEqual(weight, UIFont.Weight.semibold.rawValue, accuracy: 0.01)
        XCTAssertTrue(font.fontName.lowercased().contains("rounded"), font.fontName)
    }

    func testFixedStyleIsTheSameForWhiteBlackAndYellowText() {
        let colors: [OverlayColor] = [.white, .black, OverlayColor(red8: 0xFF, green8: 0xE0, blue8: 0x00)]
        let fixed = colors.map { color -> OverlayStyle in
            var style = OverlayStyle()
            style.textColor = color
            return StyleSwatchPreview.fixedStyle(from: style)
        }
        XCTAssertEqual(Set(fixed).count, 1, "Y.4")
    }

    /// 49.6: glow spreads in the glyph color; the other shadows are gray.
    func testGlowUsesTextColorAndOthersAreGray() {
        var style = OverlayStyle()
        style.shadow = .glow
        let glow = StyleSwatchPreview.decorations(for: StyleSwatchPreview.fixedStyle(from: style))
        guard case let .shadow(offset, _, _, color) = glow[0] else { return XCTFail("no shadow") }
        XCTAssertEqual(offset, .zero)
        XCTAssertEqual(color, StyleSwatchPreview.textColor)
        for shadow in [OverlayShadow.soft, .hard] {
            var style = OverlayStyle()
            style.shadow = shadow
            let decorations = StyleSwatchPreview.decorations(for: StyleSwatchPreview.fixedStyle(from: style))
            let colors = decorations.compactMap { decoration -> OverlayColor? in
                if case let .shadow(_, _, _, color) = decoration { return color }
                return nil
            }
            XCTAssertEqual(colors, [StyleSwatchPreview.accentGray], "\(shadow)")
        }
    }

    func testStrokedTextImageIsNonEmptyAndLargerThanPlainText() {
        let font = UIFont.systemFont(ofSize: 15)
        let image = StyleSwatchPreview.strokedText("A", font: font,
                                                   fill: StyleSwatchPreview.textColor,
                                                   stroke: StyleSwatchPreview.accentGray,
                                                   strokeWidth: 2)
        let plain = ("A" as NSString).size(withAttributes: [.font: font])
        XCTAssertGreaterThan(image.size.width, plain.width)
        XCTAssertGreaterThan(image.size.height, plain.height)
    }
}
