import CoreGraphics
import XCTest
@testable import DaysCam

/// Confirms `OverlayTextView`'s own layout math — not just `OverlayMetrics`
/// directly — agrees with what the baking path (`OverlayRenderer`) computes
/// for the same `style`/`placement`/frame, so the viewfinder and the saved
/// photo can never desync (PRD FR-6.1). TASK-18's `OverlayTextView` half.
final class OverlayTextViewTests: XCTestCase {

    // MARK: - Font size: `style.sizeScale` reaches the view (18.5/18.6, through the view)

    /// Same number `OverlayMetricsTests.testBaseFontSizeAppliesTheSizeScale`
    /// (18.5) pins for the baking path: short text isn't shrunk, so the
    /// fitted size is exactly the scaled base size.
    func testFittedFontSizeAppliesSizeScaleLikeTheBakingPath() {
        let frameSize = CGSize(width: 3024, height: 4032)
        let style = OverlayStyle(sizeScale: 160)
        let fitted = OverlayTextView.fittedFontSize(for: "第 1 天", style: style, frameSize: frameSize)
        XCTAssertEqual(fitted, 266.11, accuracy: 0.01)
    }

    /// The view must not invent its own arithmetic: for the same text, style
    /// and frame, its fitted size equals calling `OverlayMetrics` directly
    /// the way `OverlayRenderer` does.
    func testFittedFontSizeMatchesOverlayMetricsForTheSameInputs() {
        let frameSize = CGSize(width: 3024, height: 4032)
        let style = OverlayStyle(fontID: .sfMono, sizeScale: 70)
        let text = String(repeating: "第 10 天 ", count: 40)

        let viaView = OverlayTextView.fittedFontSize(for: text, style: style, frameSize: frameSize)

        let shortEdge = min(frameSize.width, frameSize.height)
        let margin = OverlayMetrics.margin(forShortEdge: shortEdge)
        let base = OverlayMetrics.baseFontSize(forShortEdge: shortEdge, sizeScale: style.sizeScale)
        let expected = OverlayMetrics.fittedFontSize(for: text,
                                                     theme: OverlayTheme(style: style),
                                                     baseFontSize: base,
                                                     availableWidth: frameSize.width - margin * 2)
        XCTAssertEqual(viaView, expected, accuracy: 0.0001)
    }

    func testShortTextKeepsTheScaledBaseFontSize() {
        let frameSize = CGSize(width: 300, height: 400)
        let style = OverlayStyle(sizeScale: 100)
        let fitted = OverlayTextView.fittedFontSize(for: "第 1 天", style: style, frameSize: frameSize)
        let base = OverlayMetrics.baseFontSize(forShortEdge: 300, sizeScale: 100)
        XCTAssertEqual(fitted, base, accuracy: 0.0001)
    }

    // MARK: - Placement: `.anchor` and `.custom` share `OverlayMetrics.origin`

    /// The view must place an anchor exactly where `OverlayMetrics.origin`
    /// (the same call the baking path makes) says to.
    func testOriginForAnchorPlacementMatchesOverlayMetrics() {
        let frame = CGSize(width: 300, height: 400)
        let block = CGSize(width: 80, height: 24)
        let viaView = OverlayTextView.origin(forBlockSize: block, frameSize: frame, placement: .anchor(.bottomTrailing))
        let expected = OverlayMetrics.origin(forBlockSize: block, in: frame, placement: .anchor(.bottomTrailing))
        XCTAssertEqual(viaView, expected)
    }

    /// 18.8-equivalent for the view: a `.custom` corner is clamped into the
    /// 4% margin, not drawn past the frame edge.
    func testOriginForCustomPlacementClampsIntoTheMargin() {
        let frame = CGSize(width: 300, height: 400)
        let block = CGSize(width: 80, height: 24)
        let margin = OverlayMetrics.margin(forShortEdge: 300)
        let origin = OverlayTextView.origin(forBlockSize: block, frameSize: frame, placement: .custom(x: 1, y: 1))
        XCTAssertEqual(origin.x, 300 - margin - 80, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 400 - margin - 24, accuracy: 0.0001)
    }

    /// The preview (a ~400pt frame) and the photo (a 3024x4032 frame) must
    /// place the same `.custom` fraction at the same relative spot — otherwise
    /// dragging the overlay in the viewfinder would not match where it lands
    /// in the saved photo (PRD FR-12.6).
    func testOriginIsResolutionIndependentLikeThePhoto() {
        let placement = OverlayPlacement.custom(x: 0.3, y: 0.6)
        let scale: CGFloat = 10.08 // 3024/300 == 4032/400
        let previewOrigin = OverlayTextView.origin(forBlockSize: CGSize(width: 30, height: 10),
                                                   frameSize: CGSize(width: 300, height: 400),
                                                   placement: placement)
        let photoOrigin = OverlayTextView.origin(forBlockSize: CGSize(width: 30 * scale, height: 10 * scale),
                                                 frameSize: CGSize(width: 300 * scale, height: 400 * scale),
                                                 placement: placement)
        XCTAssertEqual(photoOrigin.x, previewOrigin.x * scale, accuracy: 0.01)
        XCTAssertEqual(photoOrigin.y, previewOrigin.y * scale, accuracy: 0.01)
    }
}
