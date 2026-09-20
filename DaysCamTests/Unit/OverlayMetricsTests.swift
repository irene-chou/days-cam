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
}
