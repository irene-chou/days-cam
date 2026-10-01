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

    // MARK: - Panel-open layout (issue #128)

    private struct Device {
        let width: CGFloat, height: CGFloat, top: CGFloat, bottom: CGFloat
        let viewfinderHeight: CGFloat, boxWidth: CGFloat
    }

    /// 375×667, 375×812, 393×852, 440×956 with the expected 3:4 box (H.12).
    /// Box values derived from the issue's formulas; reference table is ±6pt.
    private var devices: [Device] {
        [Device(width: 375, height: 667, top: 20, bottom: 0, viewfinderHeight: 405, boxWidth: 303.75),
         Device(width: 375, height: 812, top: 50, bottom: 34, viewfinderHeight: 453.3, boxWidth: 340),
         Device(width: 393, height: 852, top: 59, bottom: 34, viewfinderHeight: 484.7, boxWidth: 363.5),
         Device(width: 440, height: 956, top: 59, bottom: 34, viewfinderHeight: 568, boxWidth: 426)]
    }

    func testPanelOpenBoxMatchesReferenceValuesOnEveryDevice() {
        for device in devices {
            let metrics = makeMetrics(width: device.width, height: device.height, top: device.top, bottom: device.bottom)
            let box = metrics.panelOpenViewfinderFrame
            XCTAssertEqual(box.minY, metrics.headerBottom, accuracy: accuracy)
            XCTAssertEqual(box.height, device.viewfinderHeight, accuracy: 1)
            XCTAssertEqual(box.width, device.boxWidth, accuracy: 1)
            XCTAssertEqual(box.midX, device.width / 2, accuracy: accuracy)
            // Gap above the panel, and the panel never overlaps the box.
            XCTAssertEqual(metrics.panelTop - box.maxY, metrics.panelGapAboveBox, accuracy: 1)
        }
    }

    func testPanelOpenContentSizePerRatioOnEveryDevice() {
        for device in devices {
            let metrics = makeMetrics(width: device.width, height: device.height, top: device.top, bottom: device.bottom)
            let box = metrics.panelOpenViewfinderFrame
            let threeByFour = metrics.viewfinderContentSize(for: .threeByFour, boxSize: box.size, isPanelOpen: true)
            XCTAssertEqual(threeByFour, box.size)
            let square = metrics.viewfinderContentSize(for: .oneByOne, boxSize: box.size, isPanelOpen: true)
            XCTAssertEqual(square.width, box.width, accuracy: accuracy)
            XCTAssertEqual(square.height, box.width, accuracy: accuracy)
            let tall = metrics.viewfinderContentSize(for: .nineBySixteen, boxSize: box.size, isPanelOpen: true)
            XCTAssertEqual(tall.height, box.height, accuracy: accuracy)
            XCTAssertEqual(tall.width, box.height * 9 / 16, accuracy: accuracy)
        }
    }

    func testPanelHeightsAndSmallScreenBoundary() {
        let regular = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        XCTAssertFalse(regular.isSmallScreen)
        XCTAssertEqual(regular.panelContentHeight, 120)
        XCTAssertEqual(regular.panelHeight, 152)
        XCTAssertEqual(regular.panelGapAboveBox, 6)

        let small = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        XCTAssertTrue(small.isSmallScreen)
        XCTAssertEqual(small.panelContentHeight, 104)
        XCTAssertEqual(small.panelHeight, 136)
        XCTAssertEqual(small.panelGapAboveBox, 4)

        XCTAssertTrue(makeMetrics(width: 375, height: 699, top: 20, bottom: 0).isSmallScreen)
        XCTAssertFalse(makeMetrics(width: 375, height: 700, top: 20, bottom: 0).isSmallScreen)
    }

    /// `OverlayPanelView` passes `panelContentHeight` straight to
    /// `PositionTabView(availableHeight:)` (no measurement), so the grid fits
    /// without scrolling: iPhone SE (104) gets 88 with the compact 8pt inset, and the box plus its insets never exceeds the content height on either class.
    @MainActor
    func testPositionGridFitsPanelContentHeight() {
        let small = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        let smallSide = PositionTabModel.gridBoxSide(forAvailableHeight: small.panelContentHeight)
        XCTAssertEqual(smallSide, 88, accuracy: accuracy)
        XCTAssertLessThanOrEqual(smallSide + PositionTabModel.gridBoxVerticalInset(forAvailableHeight: small.panelContentHeight) * 2, small.panelContentHeight)

        let regular = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        let regularSide = PositionTabModel.gridBoxSide(forAvailableHeight: regular.panelContentHeight)
        XCTAssertLessThanOrEqual(regularSide + PositionTabModel.gridBoxVerticalInset(forAvailableHeight: regular.panelContentHeight) * 2, regular.panelContentHeight)
    }

    /// A taller tab bar (large Dynamic Type) grows the panel and shrinks the
    /// viewfinder by the same amount; the content area stays 120 (#139, D.5).
    func testTallerTabBarShrinksViewfinderNotContent() {
        let size = CGSize(width: 393, height: 852)
        let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let normal = CameraScreenLayoutMetrics(screenSize: size, safeAreaInsets: insets, panelTabBarHeight: 32)
        let large = CameraScreenLayoutMetrics(screenSize: size, safeAreaInsets: insets, panelTabBarHeight: 38)
        XCTAssertEqual(normal.panelHeight, 152, accuracy: accuracy)
        XCTAssertEqual(large.panelHeight, 158, accuracy: accuracy)
        XCTAssertEqual(large.panelContentHeight, 120)
        XCTAssertEqual(large.panelBottom, normal.panelBottom, accuracy: accuracy)
        XCTAssertEqual(large.panelOpenViewfinderAreaHeight, normal.panelOpenViewfinderAreaHeight - 6, accuracy: accuracy)
        XCTAssertEqual(large.panelOpenViewfinderFrame.minY, large.headerBottom, accuracy: accuracy)
        XCTAssertLessThanOrEqual(large.panelOpenViewfinderFrame.maxY + large.panelGapAboveBox, large.panelTop + accuracy)
    }

    /// Never smaller than the default, so default Dynamic Type matches #134.
    func testTabBarHeightIsNeverBelowDefault() {
        let metrics = CameraScreenLayoutMetrics(screenSize: CGSize(width: 393, height: 852),
                                                safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
                                                panelTabBarHeight: 20)
        XCTAssertEqual(metrics.panelTabBarHeight, 32)
    }

    func testPanelStackingFromFooterBase() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        // footerBase 818: 8pt, 44pt row, 4pt gap, then the panel.
        XCTAssertEqual(metrics.panelBottom, 762, accuracy: accuracy)
        XCTAssertEqual(metrics.panelTop, 610, accuracy: accuracy)
    }

    func testFooterSideButtonCenterInset() {
        XCTAssertEqual(makeMetrics(width: 393, height: 852, top: 59, bottom: 34).footerSideButtonCenterInset, 79.25, accuracy: 0.05)
        XCTAssertEqual(makeMetrics(width: 375, height: 667, top: 20, bottom: 0).footerSideButtonCenterInset, 74.75, accuracy: 0.05)
        XCTAssertEqual(makeMetrics(width: 440, height: 956, top: 59, bottom: 34).footerSideButtonCenterInset, 91, accuracy: 0.05)
    }

    /// Closed, 9:16's box already *is* the 9:16 shape (from
    /// `viewfinderFrame(for: .nineBySixteen, boxWidth:)`), so content fills
    /// it as-is — `isPanelOpen: false` must not re-fit it as if it were the
    /// shared 3:4 box.
    func testNineBySixteenContentSizeFillsItsOwnBoxWhenPanelIsClosed() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        let box = metrics.viewfinderFrame(for: .nineBySixteen, boxWidth: 393)
        let content = metrics.viewfinderContentSize(for: .nineBySixteen, boxSize: box.size, isPanelOpen: false)
        XCTAssertEqual(content.width, box.size.width, accuracy: accuracy)
        XCTAssertEqual(content.height, box.size.height, accuracy: accuracy)
    }

    /// 3:4/1:1 are unaffected by `isPanelOpen` — only 9:16 branches on it.
    func testThreeByFourAndOneByOneContentSizeIgnorePanelOpenFlag() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        let boxSize = CGSize(width: 314.4, height: 419.2)
        for isPanelOpen in [true, false] {
            let threeByFour = metrics.viewfinderContentSize(for: .threeByFour, boxSize: boxSize, isPanelOpen: isPanelOpen)
            XCTAssertEqual(threeByFour.width, boxSize.width, accuracy: accuracy)
            XCTAssertEqual(threeByFour.height, boxSize.height, accuracy: accuracy)

            let oneByOne = metrics.viewfinderContentSize(for: .oneByOne, boxSize: boxSize, isPanelOpen: isPanelOpen)
            XCTAssertEqual(oneByOne.width, boxSize.width, accuracy: accuracy)
            XCTAssertEqual(oneByOne.height, boxSize.width, accuracy: accuracy)
        }
    }

    // MARK: - Chrome-over-photo (issue #121)

    /// 3:4/1:1 never have the viewfinder behind the header/footer, open or
    /// closed panel alike — only 9:16 ever does.
    func testThreeByFourAndOneByOneAreNeverBehindHeaderOrFooter() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        for ratio: CaptureAspectRatio in [.threeByFour, .oneByOne] {
            for isPanelOpen in [true, false] {
                XCTAssertFalse(metrics.isViewfinderBehindHeader(ratio: ratio, isPanelOpen: isPanelOpen))
                XCTAssertFalse(metrics.isViewfinderBehindFooter(ratio: ratio, isPanelOpen: isPanelOpen))
            }
        }
    }

    /// iPhone 16 (non-fallback): closed-panel 9:16 fills the screen behind
    /// the footer (rule ③, its viewfinder reaches `footerBase`) but not the
    /// header (`headerBottom` is comfortably below the formula's minimum,
    /// issue #101 assumption 2's fallback never triggers).
    func testIPhone16NineBySixteenClosedPanelIsBehindFooterOnlyNotHeader() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        XCTAssertFalse(metrics.isViewfinderBehindHeader(ratio: .nineBySixteen, isPanelOpen: false))
        XCTAssertTrue(metrics.isViewfinderBehindFooter(ratio: .nineBySixteen, isPanelOpen: false))
    }

    /// iPhone SE (fallback, issue #101 assumption 2): closed-panel 9:16
    /// reverts to full-bleed edge to edge, so it is behind *both* the
    /// header and the footer.
    func testSENineBySixteenClosedPanelIsBehindBothHeaderAndFooter() {
        let metrics = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        XCTAssertTrue(metrics.isFallback)
        XCTAssertTrue(metrics.isViewfinderBehindHeader(ratio: .nineBySixteen, isPanelOpen: false))
        XCTAssertTrue(metrics.isViewfinderBehindFooter(ratio: .nineBySixteen, isPanelOpen: false))
    }

    /// Issue #120 put 9:16's panel-open viewfinder above the panel like
    /// every other ratio — behind neither the header nor the footer, on
    /// both a non-fallback (iPhone 16) and a fallback (iPhone SE) screen.
    func testNineBySixteenIsNeverBehindHeaderOrFooterWhilePanelIsOpen() {
        let iPhone16 = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        XCTAssertFalse(iPhone16.isViewfinderBehindHeader(ratio: .nineBySixteen, isPanelOpen: true))
        XCTAssertFalse(iPhone16.isViewfinderBehindFooter(ratio: .nineBySixteen, isPanelOpen: true))

        let se = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        XCTAssertFalse(se.isViewfinderBehindHeader(ratio: .nineBySixteen, isPanelOpen: true))
        XCTAssertFalse(se.isViewfinderBehindFooter(ratio: .nineBySixteen, isPanelOpen: true))
    }

    // MARK: - Capture flight landing spot (issue #148)

    func testLeftFooterButtonCenterClosedAndOpen() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        // footerBase 818: closed, 16pt padding + half the 76pt shutter row.
        let closed = metrics.leftFooterButtonCenter(isPanelOpen: false)
        XCTAssertEqual(closed.x, 79.25, accuracy: 0.05)
        XCTAssertEqual(closed.y, 818 - 16 - 38, accuracy: 0.05)
        // Open, 8pt gap + half the 44pt row; same x so the button never shifts.
        let open = metrics.leftFooterButtonCenter(isPanelOpen: true)
        XCTAssertEqual(open.x, closed.x, accuracy: 0.05)
        XCTAssertEqual(open.y, 818 - 8 - 22, accuracy: 0.05)
    }

    // MARK: - Tools capsule (issue #135)

    func testToolsCapsuleSitsFourPointsBelowTheCenteredToggle() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        // The 44pt toggle is centered in the header content below the top inset.
        XCTAssertEqual(metrics.toolsCapsuleTop, 59 + (60.333 - 44) / 2 + 44 + 4, accuracy: 0.05)
        let se = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        XCTAssertEqual(se.toolsCapsuleTop, 20 + (46 - 44) / 2 + 44 + 4, accuracy: 0.05)
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
