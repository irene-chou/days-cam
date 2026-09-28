import SwiftUI
import XCTest
@testable import DaysCam

/// Covers `CameraScreenLayoutMetrics`'s formulas against the values the
/// human confirmed in issue #101 (assumption 1 = 解讀 B, assumption 2 = the
/// small-screen fallback), across the three device sizes the issue calls
/// out: iPhone 16, iPhone 16 Pro Max and iPhone SE (3rd generation).
final class CameraScreenLayoutMetricsTests: XCTestCase {
    private let accuracy: CGFloat = 0.05

    // MARK: - iPhone 16 (393×852, top 59, bottom 34)

    func testIPhone16HeaderBottom() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        XCTAssertFalse(metrics.isFallback)
        XCTAssertEqual(metrics.headerBottom, 119.333, accuracy: accuracy)
    }

    func testIPhone16ThreeByFourFrame() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        let frame = metrics.viewfinderFrame(for: .threeByFour, boxWidth: 393)
        XCTAssertEqual(frame.minY, 119.333, accuracy: accuracy)
        XCTAssertEqual(frame.maxY, 643.333, accuracy: accuracy)
        XCTAssertEqual(frame.minX, 0, accuracy: accuracy)
        XCTAssertEqual(frame.width, 393, accuracy: accuracy)
    }

    /// Rule ② (1:1 centers inside 3:4) is achieved by construction, not by
    /// `viewfinderFrame` reporting a different box for `.oneByOne`: it
    /// returns the *exact same* 3:4-shaped rect either way, and
    /// `CameraScreen` draws the smaller square content inside that box via
    /// a plain `ZStack` (which centers a smaller child by default) —
    /// `viewfinderContentSize(for:boxSize:)`, not this type, decides the
    /// square's own side length. So the meaningful assertion here is frame
    /// equality, not a re-derivation of `ZStack`'s own centering (code
    /// review finding on an earlier, always-true version of this test).
    func testIPhone16OneByOneFrameEqualsThreeByFourFrame() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        let threeByFour = metrics.viewfinderFrame(for: .threeByFour, boxWidth: 393)
        let oneByOne = metrics.viewfinderFrame(for: .oneByOne, boxWidth: 393)
        assertRectsEqual(oneByOne, threeByFour)
    }

    func testIPhone16NineBySixteenFrame() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        let frame = metrics.viewfinderFrame(for: .nineBySixteen, boxWidth: 393)
        XCTAssertFalse(metrics.isFallback)
        XCTAssertEqual(frame.minY, 119.333, accuracy: accuracy)
        XCTAssertEqual(frame.maxY, 818.0, accuracy: accuracy)
    }

    func testIPhone16FooterRegion() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        XCTAssertEqual(metrics.footerRegionTop, 643.333, accuracy: accuracy)
        XCTAssertEqual(metrics.footerBase, 818.0, accuracy: accuracy)
    }

    /// Code review finding on #101/#110: while the overlay panel is open,
    /// 3:4/1:1's box shrinks to 80% width (PRD 0.2 FR-8.2) — and height
    /// with it, since the box stays 3:4-shaped — so the footer/panel region
    /// has to start further up too, or it leaves a gap below the shrunk
    /// box. `footerRegionTop(boxWidth:)` is what `CameraScreen.footerColumn`
    /// calls with that shrunk width to track it.
    func testIPhone16FooterRegionTopTracksAShrunkBoxWidth() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        let shrunkWidth: CGFloat = 393 * 0.8
        let regionTop = metrics.footerRegionTop(boxWidth: shrunkWidth)
        // Bottom edge of an 0.8×-width, still-3:4-shaped box starting at
        // headerBottom — strictly above (smaller y than) the full-width
        // regionTop, since the shrunk box is shorter.
        XCTAssertEqual(regionTop, metrics.headerBottom + shrunkWidth * 4 / 3, accuracy: accuracy)
        XCTAssertLessThan(regionTop, metrics.footerRegionTop)
    }

    // MARK: - iPhone 16 Pro Max (440×956, top 59, bottom 34)

    func testProMaxHeaderBottom() {
        let metrics = makeMetrics(width: 440, height: 956, top: 59, bottom: 34)
        XCTAssertFalse(metrics.isFallback)
        XCTAssertEqual(metrics.headerBottom, 139.778, accuracy: accuracy)
    }

    func testProMaxThreeByFourAndOneByOneFrames() {
        let metrics = makeMetrics(width: 440, height: 956, top: 59, bottom: 34)
        let threeByFour = metrics.viewfinderFrame(for: .threeByFour, boxWidth: 440)
        XCTAssertEqual(threeByFour.minY, 139.778, accuracy: accuracy)
        XCTAssertEqual(threeByFour.maxY, 726.444, accuracy: accuracy)

        let oneByOne = metrics.viewfinderFrame(for: .oneByOne, boxWidth: 440)
        assertRectsEqual(oneByOne, threeByFour)
    }

    func testProMaxNineBySixteenFrame() {
        let metrics = makeMetrics(width: 440, height: 956, top: 59, bottom: 34)
        let frame = metrics.viewfinderFrame(for: .nineBySixteen, boxWidth: 440)
        XCTAssertEqual(frame.minY, 139.778, accuracy: accuracy)
        XCTAssertEqual(frame.maxY, 922.0, accuracy: accuracy)
    }

    // MARK: - iPhone SE 3rd gen (375×667, top 20, bottom 0) — assumption 2 fallback

    func testSEFallsBackToMinimumHeaderHeight() {
        let metrics = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        XCTAssertTrue(metrics.isFallback)
        // Minimum = top safe area (20) + toolbar minimum (46) = 66.
        XCTAssertEqual(metrics.headerBottom, 66.0, accuracy: accuracy)
    }

    func testSEThreeByFourAndOneByOneFrames() {
        let metrics = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        let threeByFour = metrics.viewfinderFrame(for: .threeByFour, boxWidth: 375)
        XCTAssertEqual(threeByFour.minY, 66.0, accuracy: accuracy)
        XCTAssertEqual(threeByFour.maxY, 566.0, accuracy: accuracy)

        let oneByOne = metrics.viewfinderFrame(for: .oneByOne, boxWidth: 375)
        assertRectsEqual(oneByOne, threeByFour)
    }

    func testSEFooterHeight() {
        let metrics = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        XCTAssertEqual(metrics.footerBase - metrics.footerRegionTop, 101.0, accuracy: accuracy)
    }

    /// Assumption 2: the 9:16 viewfinder itself reverts to the pre-#101
    /// full-bleed behavior on a fallback screen, rather than stopping at
    /// `headerBottom`/`footerBase` like the non-fallback devices above.
    func testSENineBySixteenFallsBackToFullBleed() {
        let metrics = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        let frame = metrics.viewfinderFrame(for: .nineBySixteen, boxWidth: 375)
        assertRectsEqual(frame, CGRect(x: 0, y: 0, width: 375, height: 667))
    }

    // MARK: - Helpers

    private func makeMetrics(width: CGFloat, height: CGFloat, top: CGFloat, bottom: CGFloat) -> CameraScreenLayoutMetrics {
        CameraScreenLayoutMetrics(screenSize: CGSize(width: width, height: height),
                                  safeAreaInsets: EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
    }
}

/// A `CGRect`-shaped `XCTAssertEqual` with tolerance, since these frames come
/// from floating-point division (`16W/9` etc.) and are never expected to
/// match bit-for-bit.
private func assertRectsEqual(_ lhs: CGRect, _ rhs: CGRect, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(lhs.origin.x, rhs.origin.x, accuracy: 0.05, file: file, line: line)
    XCTAssertEqual(lhs.origin.y, rhs.origin.y, accuracy: 0.05, file: file, line: line)
    XCTAssertEqual(lhs.size.width, rhs.size.width, accuracy: 0.05, file: file, line: line)
    XCTAssertEqual(lhs.size.height, rhs.size.height, accuracy: 0.05, file: file, line: line)
}
