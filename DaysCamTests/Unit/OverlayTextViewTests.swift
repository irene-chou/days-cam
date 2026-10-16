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
        let style = OverlayStyle(fontID: .notoSerifTC, sizeScale: 70)
        let text = String(repeating: "第 10 天 ", count: 40)

        let viaView = OverlayTextView.fittedFontSize(for: text, style: style, frameSize: frameSize,
                                                     font: .pingFang)

        let shortEdge = min(frameSize.width, frameSize.height)
        let margin = OverlayMetrics.margin(forShortEdge: shortEdge)
        let base = OverlayMetrics.baseFontSize(forShortEdge: shortEdge, sizeScale: style.sizeScale)
        let expected = OverlayMetrics.fittedFontSize(for: text,
                                                     font: .pingFang,
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

    // MARK: - Drag: `clampedDragCenter` (#68, D.1–D.4)

    private let dragFrameSize = CGSize(width: 288, height: 384)
    private let dragBlockSize = CGSize(width: 80, height: 24)

    /// The origin a stored `.custom` fraction derived from `center` would
    /// render at — the same round trip `PositionDragAdapter.overlayDragEnded`
    /// triggers via `PositionTabModel.applyDrag`, without depending on that
    /// ui-panel type: `PositionTabModel.customPosition` only re-clamps when a
    /// fraction falls outside the margin band, which every `center` used
    /// below (already clamped by `clampedDragCenter` itself) never does.
    private func renderedOrigin(forCenter center: CGPoint, frameSize: CGSize, blockSize: CGSize) -> CGPoint {
        let fraction = OverlayPlacement.custom(x: Double(center.x / frameSize.width),
                                               y: Double(center.y / frameSize.height))
        return OverlayTextView.origin(forBlockSize: blockSize, frameSize: frameSize, placement: fraction)
    }

    /// D.1: releasing a drag with zero translation must land back exactly
    /// where it started — starting from `.anchor(.topLeading)`, not
    /// `.custom`, is the case #68 fixes (the old `PositionDragAdapter` used a
    /// zero-size reference point, which only happens to equal `.custom`'s own
    /// center; for an anchor it lands on the anchor's margin corner instead).
    func testZeroTranslationFromAnAnchorReproducesItsOwnOrigin() {
        let originalOrigin = OverlayTextView.origin(forBlockSize: dragBlockSize, frameSize: dragFrameSize, placement: .anchor(.topLeading))
        let start = CGPoint(x: originalOrigin.x + dragBlockSize.width / 2, y: originalOrigin.y + dragBlockSize.height / 2)

        let center = OverlayTextView.clampedDragCenter(start: start, translation: .zero, frameSize: dragFrameSize, blockSize: dragBlockSize)
        let roundTrippedOrigin = renderedOrigin(forCenter: center, frameSize: dragFrameSize, blockSize: dragBlockSize)

        XCTAssertEqual(roundTrippedOrigin.x, originalOrigin.x, accuracy: 0.5, "D.1")
        XCTAssertEqual(roundTrippedOrigin.y, originalOrigin.y, accuracy: 0.5, "D.1")
    }

    /// D.2: same as D.1, for every one of the nine anchors.
    func testZeroTranslationReproducesEveryAnchorsOwnOrigin() {
        for position in OverlayPosition.allCases {
            let placement = OverlayPlacement.anchor(position)
            let originalOrigin = OverlayTextView.origin(forBlockSize: dragBlockSize, frameSize: dragFrameSize, placement: placement)
            let start = CGPoint(x: originalOrigin.x + dragBlockSize.width / 2, y: originalOrigin.y + dragBlockSize.height / 2)

            let center = OverlayTextView.clampedDragCenter(start: start, translation: .zero, frameSize: dragFrameSize, blockSize: dragBlockSize)
            let roundTrippedOrigin = renderedOrigin(forCenter: center, frameSize: dragFrameSize, blockSize: dragBlockSize)

            XCTAssertEqual(roundTrippedOrigin.x, originalOrigin.x, accuracy: 0.5, "D.2: \(position)")
            XCTAssertEqual(roundTrippedOrigin.y, originalOrigin.y, accuracy: 0.5, "D.2: \(position)")
        }
    }

    /// D.3: a translation that keeps the block inside the margin band moves
    /// the origin by exactly that translation.
    func testTranslationFromAnAnchorMovesTheOriginByTheSameAmount() {
        let originalOrigin = OverlayTextView.origin(forBlockSize: dragBlockSize, frameSize: dragFrameSize, placement: .anchor(.bottomTrailing))
        let start = CGPoint(x: originalOrigin.x + dragBlockSize.width / 2, y: originalOrigin.y + dragBlockSize.height / 2)
        let translation = CGSize(width: -50, height: -80)

        let center = OverlayTextView.clampedDragCenter(start: start, translation: translation, frameSize: dragFrameSize, blockSize: dragBlockSize)
        let roundTrippedOrigin = renderedOrigin(forCenter: center, frameSize: dragFrameSize, blockSize: dragBlockSize)

        XCTAssertEqual(roundTrippedOrigin.x, originalOrigin.x + translation.width, accuracy: 0.5, "D.3")
        XCTAssertEqual(roundTrippedOrigin.y, originalOrigin.y + translation.height, accuracy: 0.5, "D.3")
    }

    /// D.4: a translation that would carry the block past the viewfinder's
    /// edge is kept inside the 4% margin band *at drag time* — not only once
    /// the drag ends — by `clampedDragCenter` itself, matching the margin a
    /// settled `.custom` position already gets from `OverlayMetrics.origin`.
    func testDraggingPastTheEdgeStaysInsideTheMargin() {
        let start = CGPoint(x: dragFrameSize.width / 2, y: dragFrameSize.height / 2)
        let farOutsideTranslation = CGSize(width: 10_000, height: 10_000)

        let center = OverlayTextView.clampedDragCenter(start: start, translation: farOutsideTranslation, frameSize: dragFrameSize, blockSize: dragBlockSize)
        let origin = OverlayTextView.origin(forBlockSize: dragBlockSize, frameSize: dragFrameSize,
                                            placement: .custom(x: Double(center.x / dragFrameSize.width), y: Double(center.y / dragFrameSize.height)))
        let margin = OverlayMetrics.margin(forShortEdge: min(dragFrameSize.width, dragFrameSize.height))

        XCTAssertEqual(origin.x, dragFrameSize.width - margin - dragBlockSize.width, accuracy: 0.0001, "D.4")
        XCTAssertEqual(origin.y, dragFrameSize.height - margin - dragBlockSize.height, accuracy: 0.0001, "D.4")
    }

    // MARK: - #568: a tap on a draggable block is not a drag

    func testATapSizedTouchIsNotPersistedAsADrag() {
        XCTAssertFalse(OverlayTextView.shouldPersistDrag(translation: .zero))
        XCTAssertFalse(OverlayTextView.shouldPersistDrag(translation: CGSize(width: 6, height: 8)), "10pt exactly is still a tap")
        XCTAssertTrue(OverlayTextView.shouldPersistDrag(translation: CGSize(width: 11, height: 0)))
    }
}
