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
        // TASK-37 (37.4): regular screens' content area is 212 (was 160), so
        // the open-panel box is 52pt shorter than the 0.2 values; the small
        // screen keeps 120 and is unchanged.
        [Device(width: 375, height: 667, top: 20, bottom: 0, viewfinderHeight: 389, boxWidth: 291.75),
         Device(width: 375, height: 812, top: 50, bottom: 34, viewfinderHeight: 361.3, boxWidth: 271),
         Device(width: 393, height: 852, top: 59, bottom: 34, viewfinderHeight: 392.7, boxWidth: 294.5),
         Device(width: 402, height: 874, top: 62, bottom: 34, viewfinderHeight: 408.7, boxWidth: 306.5),
         Device(width: 440, height: 956, top: 59, bottom: 34, viewfinderHeight: 476, boxWidth: 357)]
    }

    /// 98.3 (TASK-98, #402): 3:4 while open is exactly where #128's shared
    /// box put it — height = the area, width = 3/4 of it, top at the header,
    /// centered, the gap above the panel intact.
    func testPanelOpenThreeByFourMatchesReferenceValuesOnEveryDevice() {
        for device in devices {
            let metrics = makeMetrics(width: device.width, height: device.height, top: device.top, bottom: device.bottom)
            let box = metrics.panelOpenViewfinderFrame(for: .threeByFour)
            XCTAssertEqual(box.minY, metrics.headerBottom, accuracy: accuracy)
            XCTAssertEqual(box.height, device.viewfinderHeight, accuracy: 1)
            XCTAssertEqual(box.width, device.boxWidth, accuracy: 1)
            XCTAssertEqual(box.midX, device.width / 2, accuracy: accuracy)
            // Gap above the panel, and the panel never overlaps the box.
            XCTAssertEqual(metrics.panelTop - box.maxY, metrics.panelGapAboveBox, accuracy: 1)
        }
    }

    /// 98.1 (TASK-98, #402) on iPhone SE, iPhone 16 and 16 Pro Max (and the
    /// other reference devices): each ratio fitted to the area on its own.
    func testPanelOpenFramesFitEachRatioOnEveryDevice() {
        for device in devices {
            let metrics = makeMetrics(width: device.width, height: device.height, top: device.top, bottom: device.bottom)
            let area = metrics.panelOpenViewfinderArea
            let width = device.width
            let height = metrics.panelOpenViewfinderAreaHeight
            XCTAssertEqual(area, CGRect(x: 0, y: metrics.headerBottom, width: width, height: height))

            let square = metrics.panelOpenViewfinderFrame(for: .oneByOne)
            let side = min(width, height)
            XCTAssertEqual(square.width, side, accuracy: accuracy, "1:1 is W×W when H ≥ W, else H×H (\(device.width)×\(device.height))")
            XCTAssertEqual(square.height, side, accuracy: accuracy)

            let threeByFour = metrics.panelOpenViewfinderFrame(for: .threeByFour)
            XCTAssertEqual(threeByFour.width, min(width, height * 3 / 4), accuracy: accuracy)
            XCTAssertEqual(threeByFour.height, threeByFour.width * 4 / 3, accuracy: accuracy)

            let tall = metrics.panelOpenViewfinderFrame(for: .nineBySixteen)
            XCTAssertEqual(tall.width, min(width, height * 9 / 16), accuracy: accuracy)
            XCTAssertEqual(tall.height, tall.width * 16 / 9, accuracy: accuracy)
            if height * 9 / 16 <= width {
                XCTAssertEqual(tall.height, height, accuracy: accuracy, "9:16 is as tall as the area")
            }

            for ratio in CaptureAspectRatio.allCases {
                let frame = metrics.panelOpenViewfinderFrame(for: ratio)
                XCTAssertEqual(frame.midX, width / 2, accuracy: accuracy, "\(ratio) centered")
                XCTAssertGreaterThanOrEqual(frame.minY, area.minY - accuracy, "\(ratio) below the header")
                XCTAssertLessThanOrEqual(frame.maxY, area.maxY + accuracy, "\(ratio) above the gap")
                XCTAssertEqual(frame.midY, area.midY, accuracy: accuracy, "\(ratio) vertically centered in the area")
                let content = metrics.viewfinderContentSize(for: ratio, boxSize: frame.size, isPanelOpen: true)
                XCTAssertEqual(content, frame.size, "\(ratio) fills its own fitted frame")
            }
        }
    }

    /// 98.2: on iPhone 16 the open 1:1 picture is the full 393pt wide —
    /// #128's shared box made it ≈294.5.
    func testPanelOpenSquareOnIPhone16IsFullWidth() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        let square = metrics.panelOpenViewfinderFrame(for: .oneByOne)
        XCTAssertEqual(square.width, 393, accuracy: accuracy)
        XCTAssertEqual(square.height, 393, accuracy: accuracy)
        XCTAssertGreaterThan(square.width, 294.5 + 90)
        let closed = metrics.viewfinderPlacement(for: .oneByOne, isPanelOpen: false)
        let open = metrics.viewfinderPlacement(for: .oneByOne, isPanelOpen: true)
        XCTAssertEqual(open.scale.width, 1, accuracy: 0.001, "a picture that fits is not scaled")
        XCTAssertEqual(open.scale.height, 1, accuracy: 0.001)
        XCTAssertEqual(open.layoutSize, closed.layoutSize)
    }

    /// 98.3: 9:16 while open is unchanged too — as tall as the area, 9/16 of
    /// that wide, top at the header, centered.
    func testPanelOpenNineBySixteenMatchesReferenceValuesOnEveryDevice() {
        for device in devices {
            let metrics = makeMetrics(width: device.width, height: device.height, top: device.top, bottom: device.bottom)
            let tall = metrics.panelOpenViewfinderFrame(for: .nineBySixteen)
            XCTAssertEqual(tall.minY, metrics.headerBottom, accuracy: accuracy)
            XCTAssertEqual(tall.height, device.viewfinderHeight, accuracy: 1)
            XCTAssertEqual(tall.width, device.viewfinderHeight * 9 / 16, accuracy: 1)
            XCTAssertEqual(tall.midX, device.width / 2, accuracy: accuracy)
        }
    }

    func testPanelHeightsAndSmallScreenBoundary() {
        let regular = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        XCTAssertFalse(regular.isSmallScreen)
        // TASK-92: 224 + the 44pt open footer row and gaps − the 24pt grabber.
        XCTAssertEqual(regular.panelContentHeight, 244, "92.2")
        XCTAssertEqual(regular.panelHeight, 24 + 32 + 244)
        XCTAssertEqual(regular.panelVisibleHeight, regular.panelHeight + 34, "92.1: on through the home-indicator band")
        XCTAssertEqual(regular.panelGapAboveBox, 6)

        let small = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        XCTAssertTrue(small.isSmallScreen)
        XCTAssertEqual(small.panelContentHeight, 152, "92.2")
        XCTAssertEqual(small.panelHeight, 24 + 32 + 152)
        XCTAssertEqual(small.panelVisibleHeight, small.panelHeight, "92.12: no band on 4.7-inch")
        XCTAssertEqual(small.panelGapAboveBox, 4)

        XCTAssertTrue(makeMetrics(width: 375, height: 699, top: 20, bottom: 0).isSmallScreen)
        XCTAssertFalse(makeMetrics(width: 375, height: 700, top: 20, bottom: 0).isSmallScreen)
    }

    /// `OverlayPanelView` passes `panelContentHeight` straight to
    /// `PositionTabView(availableHeight:)` (no measurement), so the grid fits
    /// without scrolling: iPhone SE (132) gets 96 with the compact 8pt inset, and the box plus its insets never exceeds the content height on either class.
    @MainActor
    func testPositionGridFitsPanelContentHeight() {
        let small = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        let smallSide = PositionTabModel.gridBoxSide(forAvailableHeight: small.panelContentHeight)
        XCTAssertEqual(smallSide, 96, accuracy: accuracy)
        XCTAssertLessThanOrEqual(smallSide + PositionTabModel.gridBoxVerticalInset(forAvailableHeight: small.panelContentHeight) * 2, small.panelContentHeight)

        let regular = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        let regularSide = PositionTabModel.gridBoxSide(forAvailableHeight: regular.panelContentHeight)
        XCTAssertEqual(regularSide, 96, accuracy: accuracy, "37.6: the grid stays 96 in the taller area")
        XCTAssertLessThanOrEqual(regularSide + PositionTabModel.gridBoxVerticalInset(forAvailableHeight: regular.panelContentHeight) * 2, regular.panelContentHeight)
    }

    /// A taller tab bar (large Dynamic Type) grows the panel and shrinks the
    /// viewfinder by the same amount; the content area stays 224 (#139, D.5).
    func testTallerTabBarShrinksViewfinderNotContent() {
        let size = CGSize(width: 393, height: 852)
        let insets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        let normal = CameraScreenLayoutMetrics(screenSize: size, safeAreaInsets: insets, panelTabBarHeight: 32)
        let large = CameraScreenLayoutMetrics(screenSize: size, safeAreaInsets: insets, panelTabBarHeight: 38)
        XCTAssertEqual(normal.panelHeight, 300, accuracy: accuracy)
        XCTAssertEqual(large.panelHeight, 306, accuracy: accuracy)
        XCTAssertEqual(large.panelContentHeight, 244)
        XCTAssertEqual(large.panelBottom, normal.panelBottom, accuracy: accuracy)
        XCTAssertEqual(large.panelOpenViewfinderAreaHeight, normal.panelOpenViewfinderAreaHeight - 6, accuracy: accuracy)
        XCTAssertEqual(large.panelOpenViewfinderFrame(for: .threeByFour).minY, large.headerBottom, accuracy: accuracy)
        XCTAssertLessThanOrEqual(large.panelOpenViewfinderFrame(for: .threeByFour).maxY + large.panelGapAboveBox, large.panelTop + accuracy)
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
        // footerBase 818: the panel's usable area now ends right there
        // (TASK-92 removed the 8pt + 32pt row + 4pt below it), and the 44pt
        // went into the content area minus the 24pt grabber — so the top edge
        // stays exactly where TASK-55 left it (518).
        XCTAssertEqual(metrics.panelBottom, 818, accuracy: accuracy, "92.1")
        XCTAssertEqual(metrics.panelTop, 518, accuracy: accuracy, "92.2 (was 55.2)")
    }

    /// 92.2: `panelTop` — and with it the open-panel viewfinder — is the same
    /// as before TASK-92 on every device: the pre-92 stack was footerBase −
    /// 8 − 32 − 4 − (tab bar + 224 ／ 132).
    func testPanelTopIsUnchangedByTheGrabberOnEveryDevice() {
        for device in devices {
            let metrics = makeMetrics(width: device.width, height: device.height, top: device.top, bottom: device.bottom)
            let footerBase = device.height - device.bottom
            let pre92ContentHeight: CGFloat = device.height < 700 ? 132 : 224
            let pre92PanelTop = footerBase - 8 - 32 - 4 - (32 + pre92ContentHeight)
            XCTAssertEqual(metrics.panelTop, pre92PanelTop, accuracy: accuracy, "92.2 \(device.width)×\(device.height)")
            XCTAssertEqual(metrics.panelBottom, footerBase, accuracy: accuracy, "92.1 usable area ends at the home indicator")
            XCTAssertEqual(metrics.panelTop + metrics.panelVisibleHeight, device.height, accuracy: accuracy,
                           "92.1 the panel reaches the screen's bottom edge")
            XCTAssertEqual(metrics.panelVisibleHeight - metrics.panelHeight, device.bottom, accuracy: accuracy,
                           "92.7／92.12 the band below the usable area is exactly the bottom inset")
        }
    }

    /// 92.14: the open panel is full width (no 6pt side inset), with the
    /// design's 18pt top corners and an upward-only shadow.
    func testPanelIsFullWidthWithTopRoundedCornersAndUpwardShadow() {
        for device in [(w: 393.0, h: 852.0, t: 59.0, b: 34.0), (w: 375.0, h: 667.0, t: 20.0, b: 0.0),
                       (w: 430.0, h: 932.0, t: 59.0, b: 34.0)] {
            let metrics = makeMetrics(width: device.w, height: device.h, top: device.t, bottom: device.b)
            XCTAssertEqual(metrics.panelWidth, device.w, "92.14 \(device.w)")
        }
        XCTAssertEqual(CameraScreenLayoutMetrics.panelTopCornerRadius, 18, "92.14")
        XCTAssertEqual(CameraScreenLayoutMetrics.panelShadowRadius, 18, "92.14")
        XCTAssertLessThan(CameraScreenLayoutMetrics.panelShadowYOffset, 0, "92.14: the shadow rises")
    }

    func testFooterSideButtonCenterInset() {
        XCTAssertEqual(makeMetrics(width: 393, height: 852, top: 59, bottom: 34).footerSideButtonCenterInset, 71.25, accuracy: 0.05)
        XCTAssertEqual(makeMetrics(width: 375, height: 667, top: 20, bottom: 0).footerSideButtonCenterInset, 66.75, accuracy: 0.05)
        XCTAssertEqual(makeMetrics(width: 430, height: 932, top: 59, bottom: 34).footerSideButtonCenterInset, 80.5, accuracy: 0.05)
        XCTAssertEqual(makeMetrics(width: 440, height: 956, top: 59, bottom: 34).footerSideButtonCenterInset, 83, accuracy: 0.05)
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

    /// 92.11: the closed footer's thumbnail (a capture flight's landing
    /// spot) is where it always was; there is no open-panel variant any more
    /// (TASK-92 removed that footer row).
    func testLeftFooterButtonCenter() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        // footerBase 818: 16pt padding + half the 76pt shutter row.
        let closed = metrics.leftFooterButtonCenter
        XCTAssertEqual(closed.x, 71.25, accuracy: 0.05)
        XCTAssertEqual(closed.y, 818 - 16 - 38, accuracy: 0.05)
    }

    // MARK: - Tools capsule (issue #135)

    func testToolsCapsuleSitsFourPointsBelowTheCenteredToggle() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        // The 44pt toggle is centered in the header content below the top inset.
        XCTAssertEqual(metrics.toolsCapsuleTop, 59 + (60.333 - 44) / 2 + 44 + 4, accuracy: 0.05)
        let se = makeMetrics(width: 375, height: 667, top: 20, bottom: 0)
        XCTAssertEqual(se.toolsCapsuleTop, 20 + (46 - 44) / 2 + 44 + 4, accuracy: 0.05)
    }

    // MARK: - Viewfinder placement (issue #153)

    func testPlacementClosedIsUnscaledAndCenteredOnTheBox() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        for ratio in CaptureAspectRatio.allCases {
            let placement = metrics.viewfinderPlacement(for: ratio, isPanelOpen: false)
            let box = metrics.viewfinderFrame(for: ratio, boxWidth: 393)
            XCTAssertEqual(placement.scale.width, 1, accuracy: 0.0001, "\(ratio)")
            XCTAssertEqual(placement.scale.height, 1, accuracy: 0.0001, "\(ratio)")
            XCTAssertEqual(placement.center.x, box.midX, accuracy: 0.05, "\(ratio)")
            XCTAssertEqual(placement.center.y, box.midY, accuracy: 0.05, "\(ratio)")
        }
    }

    /// The layout size never changes with the panel; only scale and center do,
    /// so the content stays horizontally centered at every instant of the
    /// animation (Z.1/Z.2) and its open size equals the old frame size.
    func testPlacementOpenKeepsLayoutSizeAndScalesAboutACenteredPoint() {
        for device in devices {
            let metrics = makeMetrics(width: device.width, height: device.height, top: device.top, bottom: device.bottom)
            for ratio in CaptureAspectRatio.allCases {
                let closed = metrics.viewfinderPlacement(for: ratio, isPanelOpen: false)
                let open = metrics.viewfinderPlacement(for: ratio, isPanelOpen: true)
                XCTAssertEqual(open.layoutSize, closed.layoutSize)
                XCTAssertEqual(open.center.x, device.width / 2, accuracy: 0.05, "\(ratio)")
                let box = metrics.panelOpenViewfinderFrame(for: ratio)
                let expected = metrics.viewfinderContentSize(for: ratio, boxSize: box.size, isPanelOpen: true)
                XCTAssertEqual(open.layoutSize.width * open.scale.width, expected.width, accuracy: 0.05, "\(ratio)")
                XCTAssertEqual(open.layoutSize.height * open.scale.height, expected.height, accuracy: 0.05, "\(ratio)")
                XCTAssertLessThan(open.scale.width, 1.0001)
            }
        }
    }

    /// Same aspect ratio open and closed (the premise of a uniform scale) on
    /// the non-fallback devices.
    func testPlacementScaleIsUniformWhereTheAspectRatioIsShared() {
        let metrics = makeMetrics(width: 393, height: 852, top: 59, bottom: 34)
        for ratio in [CaptureAspectRatio.threeByFour, .oneByOne] {
            let open = metrics.viewfinderPlacement(for: ratio, isPanelOpen: true)
            XCTAssertEqual(open.scale.width, open.scale.height, accuracy: 0.001, "\(ratio)")
        }
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
