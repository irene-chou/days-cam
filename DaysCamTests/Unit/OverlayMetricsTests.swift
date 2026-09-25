import UIKit
import XCTest
@testable import DaysCam

/// Covers the TASK-05 metrics acceptance rows (5.6 ... 5.9).
///
/// These numbers are shared by the viewfinder and the baking path, so a change
/// here silently desyncs preview from print.
final class OverlayMetricsTests: XCTestCase {

    /// 5.6 — 3024 x 0.055
    func testBaseFontSizeIsFivePointFivePercentOfTheShortEdge() {
        XCTAssertEqual(OverlayMetrics.baseFontSize(forShortEdge: 3024), 166.32, accuracy: 0.01)
        XCTAssertEqual(OverlayMetrics.baseFontSize(forShortEdge: 1000), 55.0, accuracy: 0.01)
    }

    /// 5.7 — 3024 x 0.04
    func testMarginIsFourPercentOfTheShortEdge() {
        XCTAssertEqual(OverlayMetrics.margin(forShortEdge: 3024), 120.96, accuracy: 0.01)
        XCTAssertEqual(OverlayMetrics.margin(forShortEdge: 1000), 40.0, accuracy: 0.01)
    }

    /// The preview and the photo must agree, so the ratios have to be pure
    /// functions of the short edge rather than per-call-site constants.
    func testMetricsScaleProportionallyBetweenPreviewAndPhoto() {
        let preview = OverlayMetrics.baseFontSize(forShortEdge: 390)
        let photo = OverlayMetrics.baseFontSize(forShortEdge: 3024)
        XCTAssertEqual(photo / preview, 3024.0 / 390.0, accuracy: 0.0001)
    }

    // MARK: - Shrink to fit, measured with an injected ruler

    /// A ruler where every character is exactly one font size wide, so the
    /// expected numbers are arithmetic rather than font-dependent.
    private let oneUnitPerCharacter: (String, CGFloat) -> CGFloat = { text, size in
        CGFloat(text.count) * size
    }

    /// 5.9 — short text is not shrunk at all.
    func testShortTextKeepsTheBaseFontSizeExactly() {
        let fitted = OverlayMetrics.fittedFontSize(for: "第 1 天",
                                                   baseFontSize: 100,
                                                   availableWidth: 10_000,
                                                   measure: oneUnitPerCharacter)
        XCTAssertEqual(fitted, 100, accuracy: 0.0001)
    }

    /// 5.8 — long text shrinks, but never past 60% of the base size.
    func testOverlongTextShrinksWithinTheAllowedRange() {
        let base: CGFloat = 100
        let text = String(repeating: "天", count: 20)
        let fitted = OverlayMetrics.fittedFontSize(for: text,
                                                   baseFontSize: base,
                                                   availableWidth: 1500,
                                                   measure: oneUnitPerCharacter)
        XCTAssertLessThan(fitted, base)
        XCTAssertGreaterThanOrEqual(fitted, base * OverlayMetrics.minimumFontScale)
        // 20 characters must fit 1500pt, so the size is 75.
        XCTAssertEqual(fitted, 75, accuracy: 0.0001)
    }

    func testShrinkingStopsAtSixtyPercentEvenWhenTextStillOverflows() {
        let base: CGFloat = 100
        let text = String(repeating: "天", count: 200)
        let fitted = OverlayMetrics.fittedFontSize(for: text,
                                                   baseFontSize: base,
                                                   availableWidth: 1000,
                                                   measure: oneUnitPerCharacter)
        XCTAssertEqual(fitted, base * 0.6, accuracy: 0.0001,
                       "Below the floor the text is allowed to run into the margin instead")
    }

    func testTextExactlyFillingTheWidthIsNotShrunk() {
        let fitted = OverlayMetrics.fittedFontSize(for: "abcd",
                                                   baseFontSize: 100,
                                                   availableWidth: 400,
                                                   measure: oneUnitPerCharacter)
        XCTAssertEqual(fitted, 100, accuracy: 0.0001)
    }

    func testEmptyTextReturnsTheBaseFontSize() {
        let fitted = OverlayMetrics.fittedFontSize(for: "",
                                                   baseFontSize: 100,
                                                   availableWidth: 1,
                                                   measure: oneUnitPerCharacter)
        XCTAssertEqual(fitted, 100, accuracy: 0.0001)
    }

    // MARK: - Shrink to fit through the real font

    /// The convenience both `OverlayTextView` and `OverlayRenderer` call. 5.8
    /// and 5.9 again, this time measured with the font the text is drawn in.
    func testFittedFontSizeThroughTheRealFontObeysTheSameBounds() {
        let theme = OverlayTheme.theme(for: .classicWhite)
        let base = OverlayMetrics.baseFontSize(forShortEdge: 3024)

        let shortText = OverlayMetrics.fittedFontSize(for: "第 1 天",
                                                      theme: theme,
                                                      baseFontSize: base,
                                                      availableWidth: 3024)
        XCTAssertEqual(shortText, base, accuracy: 0.0001)

        let longText = OverlayMetrics.fittedFontSize(for: "小寶 2026.03.20　1 年 2 個月 5 天",
                                                     theme: theme,
                                                     baseFontSize: base,
                                                     availableWidth: 800)
        XCTAssertLessThan(longText, base)
        XCTAssertGreaterThanOrEqual(longText, base * OverlayMetrics.minimumFontScale)
    }

    func testEveryThemeResolvesToASystemFont() {
        for theme in OverlayTheme.all {
            let font = OverlayMetrics.font(for: theme, size: 40)
            XCTAssertEqual(font.pointSize, 40, accuracy: 0.0001, "\(theme.id)")
            XCTAssertGreaterThan(OverlayMetrics.textWidth(of: "第 430 天", theme: theme, fontSize: 40), 0,
                                 "\(theme.id) must measure to a real width")
        }
    }

    func testDecorationScaleTracksTheFontSize() {
        XCTAssertEqual(OverlayMetrics.decorationScale(forFontSize: OverlayMetrics.referenceFontSize), 1.0,
                       accuracy: 0.0001)
        XCTAssertEqual(OverlayMetrics.decorationScale(forFontSize: OverlayMetrics.referenceFontSize * 4), 4.0,
                       accuracy: 0.0001)
    }

    // MARK: - TASK-18: size scale, fonts, custom placement

    func testBaseFontSizeAppliesTheSizeScale() {
        XCTAssertEqual(OverlayMetrics.baseFontSize(forShortEdge: 3024, sizeScale: 160), 266.11, accuracy: 0.01, "18.5")
        XCTAssertEqual(OverlayMetrics.baseFontSize(forShortEdge: 3024, sizeScale: 100),
                       OverlayMetrics.baseFontSize(forShortEdge: 3024), accuracy: 0.0001)
    }

    /// 18.6: the shrink floor is 60% of the *scaled* base size.
    func testShrinkFloorIsSixtyPercentOfTheScaledSize() {
        let base = OverlayMetrics.baseFontSize(forShortEdge: 3024, sizeScale: 70)
        let fitted = OverlayMetrics.fittedFontSize(for: String(repeating: "第 10 天 ", count: 40),
                                                   theme: OverlayTheme(style: OverlayStyle(sizeScale: 70)),
                                                   baseFontSize: base,
                                                   availableWidth: 3024 - 2 * OverlayMetrics.margin(forShortEdge: 3024))
        XCTAssertGreaterThanOrEqual(fitted, 69.85, "18.6")
        XCTAssertEqual(fitted, 3024 * 0.055 * 0.7 * 0.6, accuracy: 0.01, "18.6: overlong text sits on the floor")
    }

    func testEveryFontIDResolvesAtTheRequestedSize() {
        for fontID in OverlayFontID.allCases {
            let font = OverlayMetrics.font(for: fontID, size: 40)
            XCTAssertEqual(font.pointSize, 40, accuracy: 0.0001, "\(fontID)")
            if let name = fontID.postScriptName {
                XCTAssertEqual(font.fontName, name, "\(fontID) must load the named face, not the fallback")
            }
        }
    }

    func testSystemFontDesignsDiffer() {
        let rounded = OverlayMetrics.font(for: .sfRounded, size: 40).fontDescriptor
        let serif = OverlayMetrics.font(for: .newYork, size: 40).fontDescriptor
        XCTAssertNotEqual(rounded.postscriptName, serif.postscriptName)
        XCTAssertNotEqual(OverlayMetrics.font(for: .sfPro, size: 40).fontName,
                          OverlayMetrics.font(for: .sfMono, size: 40).fontName)
    }

    func testCustomPlacementCentersTheBlockOnThePoint() {
        let origin = OverlayMetrics.origin(forBlockSize: CGSize(width: 200, height: 50),
                                           in: CGSize(width: 1000, height: 2000),
                                           placement: .custom(x: 0.5, y: 0.25))
        XCTAssertEqual(origin.x, 400, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 475, accuracy: 0.0001)
    }

    func testCustomPlacementClampsTheWholeBlockIntoTheMargin() {
        let frame = CGSize(width: 1000, height: 2000)
        let block = CGSize(width: 200, height: 50)
        let margin = OverlayMetrics.margin(forShortEdge: 1000)
        let farCorner = OverlayMetrics.origin(forBlockSize: block, in: frame, placement: .custom(x: 1, y: 1))
        XCTAssertEqual(farCorner.x, 1000 - margin - 200, accuracy: 0.0001)
        XCTAssertEqual(farCorner.y, 2000 - margin - 50, accuracy: 0.0001)
        let nearCorner = OverlayMetrics.origin(forBlockSize: block, in: frame, placement: .custom(x: 0, y: 0))
        XCTAssertEqual(nearCorner.x, margin, accuracy: 0.0001)
        XCTAssertEqual(nearCorner.y, margin, accuracy: 0.0001)
    }

    /// FR-12.6: the same fractions land in the same relative spot at any size.
    func testCustomPlacementIsResolutionIndependent() {
        let placement = OverlayPlacement.custom(x: 0.3, y: 0.6)
        let small = OverlayMetrics.origin(forBlockSize: CGSize(width: 40, height: 10),
                                          in: CGSize(width: 400, height: 300), placement: placement)
        let large = OverlayMetrics.origin(forBlockSize: CGSize(width: 400, height: 100),
                                          in: CGSize(width: 4000, height: 3000), placement: placement)
        XCTAssertEqual(large.x, small.x * 10, accuracy: 0.001)
        XCTAssertEqual(large.y, small.y * 10, accuracy: 0.001)
    }

    func testBlockWiderThanTheMarginsIsCenteredOnThatAxis() {
        let origin = OverlayMetrics.origin(forBlockSize: CGSize(width: 980, height: 50),
                                           in: CGSize(width: 1000, height: 2000),
                                           placement: .custom(x: 0.9, y: 0.5))
        XCTAssertEqual(origin.x, 10, accuracy: 0.0001)
    }

    func testAnchorPlacementMatchesTheNineGridRule() {
        let frame = CGSize(width: 1000, height: 2000)
        let block = CGSize(width: 200, height: 50)
        let margin = OverlayMetrics.margin(forShortEdge: 1000)
        let bottomTrailing = OverlayMetrics.origin(forBlockSize: block, in: frame, placement: .anchor(.bottomTrailing))
        XCTAssertEqual(bottomTrailing, CGPoint(x: 1000 - margin - 200, y: 2000 - margin - 50))
        let center = OverlayMetrics.origin(forBlockSize: block, in: frame, placement: .anchor(.middleCenter))
        XCTAssertEqual(center, CGPoint(x: 400, y: 975))
    }
}
