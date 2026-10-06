import UIKit
import XCTest
@testable import DaysCam

/// The fixed-look option previews of the style tab (#155): Y.4 (previews do
/// not follow the text color), Y.3 (one clean stroke, not stacked copies).
final class StyleSwatchPreviewTests: XCTestCase {
    func testFixedStyleIgnoresCurrentTextColorButKeepsFont() {
        var style = OverlayStyle()
        style.textColor = .white
        style.outlineColor = OverlayColor(red8: 0xFF, green8: 0x00, blue8: 0x00)
        style.fontID = .iansui
        let fixed = StyleSwatchPreview.fixedStyle(from: style)
        XCTAssertEqual(fixed.textColor, StyleSwatchPreview.textColor)
        XCTAssertEqual(fixed.resolvedOutlineColor, StyleSwatchPreview.accentGray)
        XCTAssertEqual(fixed.fontID, .iansui)
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

    func testEveryShadowIsGray() {
        for shadow in OverlayShadow.allCases where shadow != .none {
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
        let image = StyleSwatchPreview.strokedText("Aa", font: font,
                                                   fill: StyleSwatchPreview.textColor,
                                                   stroke: StyleSwatchPreview.accentGray,
                                                   strokeWidth: 2)
        let plain = ("Aa" as NSString).size(withAttributes: [.font: font])
        XCTAssertGreaterThan(image.size.width, plain.width)
        XCTAssertGreaterThan(image.size.height, plain.height)
    }
}
