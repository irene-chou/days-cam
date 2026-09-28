import CoreGraphics
import SwiftUI

/// Pure geometry for `CameraScreen`'s header／viewfinder／footer split
/// (PRD 0.2 FR-7.8, issue #101).
///
/// Human decision 2026-09-27 fixed three rules: ① the 3:4 and 9:16
/// viewfinders both start right at the header's bottom edge, ② the 1:1
/// viewfinder centers vertically inside the 3:4 one, ③ the 9:16 viewfinder's
/// bottom edge lands on the footer's own bottom edge — which is defined as
/// the home indicator's *top* edge ("解讀 B", not the screen's physical
/// bottom). Header and footer therefore never move when the aspect ratio
/// (or the overlay panel) changes; only the viewfinder inside them does.
///
/// `screenSize`/`safeAreaInsets` describe the *whole device screen*
/// (matching "S"/"W" in issue #101's formulas), not a safe-area-reduced
/// frame — the call site reads them from a `GeometryReader` that the
/// content is then laid out under with `.ignoresSafeArea()`, exactly like
/// this type expects.
struct CameraScreenLayoutMetrics {
    /// The toolbar's own minimum usable height (issue #101, assumption 2) —
    /// independent of device size, used only when the formula below would
    /// otherwise leave less room than this for the header.
    static let minimumHeaderContentHeight: CGFloat = 46

    let screenSize: CGSize
    let topInset: CGFloat
    let bottomInset: CGFloat

    /// The header's bottom edge, in screen coordinates (y, top-down):
    /// `S − bottomInset − 16W/9`, unless that leaves less than
    /// `minimumHeaderContentHeight` below the top safe area — small screens
    /// (iPhone SE) fall back to the minimum instead (`isFallback`).
    let headerBottom: CGFloat

    /// True once `headerBottom` had to fall back to the minimum height.
    /// Only `nineBySixteenFrame` reads this — it signals reverting the 9:16
    /// viewfinder to the pre-#101 full-bleed behavior (screen edge to edge,
    /// header/footer floating over it) rather than stopping at
    /// `headerBottom`/`footerBase`.
    let isFallback: Bool

    init(screenSize: CGSize, safeAreaInsets: EdgeInsets) {
        self.screenSize = screenSize
        self.topInset = safeAreaInsets.top
        self.bottomInset = safeAreaInsets.bottom

        let footerBase = screenSize.height - safeAreaInsets.bottom
        let nineBySixteenHeight = 16 * screenSize.width / 9
        let unclamped = footerBase - nineBySixteenHeight
        let minimum = safeAreaInsets.top + Self.minimumHeaderContentHeight
        if unclamped < minimum {
            headerBottom = minimum
            isFallback = true
        } else {
            headerBottom = unclamped
            isFallback = false
        }
    }

    /// The home indicator's top edge — the footer's own bottom edge
    /// (assumption 1, "解讀 B") and the non-fallback 9:16 viewfinder's
    /// bottom edge.
    var footerBase: CGFloat {
        screenSize.height - bottomInset
    }

    /// The 3:4 viewfinder's height at the screen's own width.
    var threeByFourHeight: CGFloat {
        screenSize.width * 4 / 3
    }

    /// Where the footer region starts when the viewfinder box is full
    /// screen width — the 3:4 box's own bottom edge there. Fixed regardless
    /// of aspect ratio; header and footer never move switching ratios
    /// (issue #101 rule). Equivalent to `footerRegionTop(boxWidth:
    /// screenSize.width)`; while the overlay panel is open, 3:4/1:1's box
    /// shrinks (PRD 0.2 FR-8.2) and callers should use that overload with
    /// the shrunk width instead — this property alone is only correct for
    /// a full-width box (panel closed, or any 9:16 box, which is never
    /// shrunk).
    var footerRegionTop: CGFloat {
        footerRegionTop(boxWidth: screenSize.width)
    }

    /// Where the footer region starts for a viewfinder box that is
    /// `boxWidth` wide (and therefore `boxWidth * 4/3` tall, since the box
    /// is always 3:4-shaped, PRD 0.2 FR-7.8) — the box's own bottom edge.
    /// Passing the panel-open-shrunk width here keeps the footer/panel
    /// region starting flush against a shrunk box (code review finding,
    /// #110) instead of leaving a gap at the full-width position.
    func footerRegionTop(boxWidth: CGFloat) -> CGFloat {
        headerBottom + boxWidth * 4 / 3
    }

    /// The viewfinder box's frame for `ratio`, given the on-screen width it
    /// should render at (`boxWidth` — full screen width normally, 80% and
    /// horizontally centered while the overlay panel is open, PRD 0.2
    /// FR-8.2; ignored for `.nineBySixteen`, which is never shrunk).
    ///
    /// 3:4 and 1:1 both report a box shaped like 3:4 (`boxWidth` ×
    /// `boxWidth * 4/3`) — 1:1's *content* is the inner square centered
    /// inside it, matching FR-8.2's "1:1 在 3:4 範圍內垂直置中" (rule ②):
    /// callers draw the smaller square via `viewfinderContentSize(for:)`
    /// inside this frame rather than resizing the frame itself, the same
    /// split `CameraScreen` already keeps between its box and its content.
    func viewfinderFrame(for ratio: CaptureAspectRatio, boxWidth: CGFloat) -> CGRect {
        switch ratio {
        case .threeByFour, .oneByOne:
            let boxHeight = boxWidth * 4 / 3
            return CGRect(x: (screenSize.width - boxWidth) / 2, y: headerBottom,
                          width: boxWidth, height: boxHeight)
        case .nineBySixteen:
            if isFallback {
                return CGRect(origin: .zero, size: screenSize)
            }
            return CGRect(x: 0, y: headerBottom, width: screenSize.width, height: footerBase - headerBottom)
        }
    }
}
