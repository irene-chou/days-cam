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

    /// The segmented control's height (issue #139): `defaultPanelTabBarHeight`
    /// scaled with Dynamic Type by the caller. Grows the panel's total
    /// height, never its content area, so the viewfinder gives up the extra.
    let panelTabBarHeight: CGFloat

    init(screenSize: CGSize, safeAreaInsets: EdgeInsets,
         panelTabBarHeight: CGFloat = CameraScreenLayoutMetrics.defaultPanelTabBarHeight) {
        self.panelTabBarHeight = max(panelTabBarHeight, Self.defaultPanelTabBarHeight)
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

    /// Where the footer region starts while the panel is closed — the
    /// full-width 3:4 box's own bottom edge. Fixed regardless of aspect
    /// ratio; header and footer never move switching ratios (issue #101
    /// rule). While the panel is open the footer region is laid out from
    /// the bottom instead (`panelTop`, issue #128).
    var footerRegionTop: CGFloat {
        headerBottom + screenSize.width * 4 / 3
    }

    // MARK: - Panel-open layout (issue #128)

    /// Screens shorter than this (iPhone SE, 667pt) use the compact panel.
    static let smallScreenHeightThreshold: CGFloat = 700

    /// The segmented control's height at the default Dynamic Type size.
    static let defaultPanelTabBarHeight: CGFloat = 32

    /// Top corner radius of the open panel's shape (PRD FR-8.8, design option
    /// 2 "同色底加陰影", restored by the user's request on PR #451); the bottom
    /// corners are square since the panel runs off the screen's bottom edge.
    static let panelTopCornerRadius: CGFloat = 18

    /// Blur radius and vertical offset of the upward shadow along the
    /// panel's top edge (`CameraTheme.popoverShadow`); negative y = up.
    static let panelShadowRadius: CGFloat = 18
    static let panelShadowYOffset: CGFloat = -6

    /// Space between the panel's rounded top edge and the segmented row, so
    /// the row does not touch the edge or the rounded corners (PR #455, user
    /// 2026-10-12 「面板須留 padding」). Taken out of the content area, so
    /// `panelTop` and the viewfinder stay where they were.
    static let panelTopPadding: CGFloat = 10

    /// Radius of the closed-panel shutter (76pt), used to place the side buttons.
    static let shutterRadius: CGFloat = 38

    /// Gap between the footer row and `footerBase` while the panel is closed.
    static let closedFooterBottomPadding: CGFloat = 16

    /// How far above `footerBase` the closed footer's side buttons are
    /// centered: the 16pt padding plus half the 76pt shutter row (54pt).
    static var closedFooterButtonCenterAboveBase: CGFloat {
        closedFooterBottomPadding + shutterRadius
    }

    /// Where the closed footer's left button (the thumbnail) is centered —
    /// the landing spot for a capture flight (issue #148); the 76pt shutter
    /// sets the row height. There is no footer row while the panel is open
    /// (TASK-92), so a flight taken then has nowhere to land and is skipped
    /// (`CaptureFlightView.skipsFlightWhenPanelOpen`).
    var leftFooterButtonCenter: CGPoint {
        CGPoint(x: footerSideButtonCenterInset,
                y: footerBase - Self.closedFooterButtonCenterAboveBase)
    }

    /// True for iPhone SE-class heights (< 700pt).
    var isSmallScreen: Bool {
        screenSize.height < Self.smallScreenHeightThreshold
    }

    /// The usable scrolling area's height below the tab bar — fixed per
    /// screen class, independent of which tab is selected. Its bottom edge
    /// is `footerBase`; the scroll view itself runs on down to the screen's
    /// physical bottom (`bottomInset` more), where content shows faded out
    /// but is not tappable (TASK-92, 92.7).
    ///
    /// TASK-92: the open-panel footer row (32pt) and its two gaps (4 + 8)
    /// went away and their 44pt came here, minus a 24pt grabber strip;
    /// TASK-99 (#404) removed the grabber and gave its 24pt back — 268
    /// regular, 176 small — so `panelTop` is unchanged throughout.
    ///
    /// PR #455: `panelTopPadding` (10pt) above the segmented row comes out
    /// of this — 258 regular, 166 small.
    var panelContentHeight: CGFloat {
        (isSmallScreen ? 176 : 268) - Self.panelTopPadding
    }

    /// Top padding, tab bar and usable content area — `panelTop` to `panelBottom`
    /// (`footerBase`). Not the panel's visible height, which continues to
    /// the screen's bottom edge (`panelVisibleHeight`).
    var panelHeight: CGFloat {
        Self.panelTopPadding + panelTabBarHeight + panelContentHeight
    }

    /// `panelTop` to the screen's physical bottom edge: the panel ignores
    /// the bottom safe area (TASK-92), so this is `panelHeight` plus
    /// `bottomInset` (0 on a 4.7-inch screen, where the two coincide).
    var panelVisibleHeight: CGFloat {
        screenSize.height - panelTop
    }

    /// The open panel spans the full screen width (TASK-92 / 92.14): no side
    /// inset (TASK-99 removed the shadow; the width stays).
    var panelWidth: CGFloat {
        screenSize.width
    }

    /// Gap between the viewfinder box's bottom edge and the panel's top.
    var panelGapAboveBox: CGFloat {
        isSmallScreen ? 4 : 6
    }

    /// The bottom edge of the panel's usable area (screen y, top-down): the
    /// home indicator's top edge, `footerBase`, since the footer row below
    /// the panel is gone (TASK-92).
    var panelBottom: CGFloat {
        footerBase
    }

    /// The panel's top edge.
    var panelTop: CGFloat {
        panelBottom - panelHeight
    }

    /// Height available to the viewfinder while the panel is open: header
    /// bottom to the gap above the panel.
    var panelOpenViewfinderAreaHeight: CGFloat {
        panelTop - panelGapAboveBox - headerBottom
    }

    /// The area the viewfinder may use while the panel is open (TASK-98,
    /// #402): the full screen width, from the header's bottom edge down to
    /// the gap above the panel.
    var panelOpenViewfinderArea: CGRect {
        CGRect(x: 0, y: headerBottom, width: screenSize.width, height: max(panelOpenViewfinderAreaHeight, 0))
    }

    /// Where `ratio`'s picture sits while the panel is open (TASK-98, #402;
    /// PRD 0.2 FR-8.2 as amended 2026-10-10). Each ratio is fitted to
    /// `panelOpenViewfinderArea` on its own — width = min(W, H × aspect),
    /// height = width ÷ aspect — so a picture whose closed size already fits
    /// (1:1 whenever H ≥ W) is not shrunk at all, and one that does not is
    /// scaled down until its height is H. Horizontally centered, vertically
    /// centered in the area; a picture exactly H tall therefore starts at the
    /// header's bottom edge, which is where #128's shared 3:4 box put 3:4 and
    /// 9:16, so those two come out unchanged. The fitted height never
    /// exceeds H (width ≤ H × aspect), so nothing ever overlaps the panel.
    func panelOpenViewfinderFrame(for ratio: CaptureAspectRatio) -> CGRect {
        let area = panelOpenViewfinderArea
        let aspect = ratio.shortToLongRatio
        let width = min(area.width, area.height * aspect)
        let height = width / aspect
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    /// Distance from each screen edge to the center of the footer's side
    /// buttons: midway between the edge and the shutter's edge, moved 8pt
    /// outward (TASK-50), so the buttons stay put whether or not the
    /// shutter is shown.
    var footerSideButtonCenterInset: CGFloat {
        (screenSize.width / 2 - Self.shutterRadius) / 2 - 8
    }

    // MARK: - Tools capsule (issue #135)

    /// The toolbar's left/right inset (`CameraToolbar`'s horizontal padding).
    static let toolbarHorizontalInset: CGFloat = 12

    /// The toolbar's icon button height.
    static let toolbarButtonHeight: CGFloat = 44

    /// Top edge of the tools capsule: the toggle button is vertically
    /// centered in the header region below the top inset; the capsule sits
    /// 4pt under it.
    var toolsCapsuleTop: CGFloat {
        let contentHeight = headerBottom - topInset
        return topInset + (contentHeight - Self.toolbarButtonHeight) / 2 + Self.toolbarButtonHeight + 4
    }

    /// The viewfinder box's frame for `ratio`, given the on-screen width it
    /// should render at (`boxWidth` — full screen width; ignored for `.nineBySixteen`, which is never shrunk).
    ///
    /// Closed-panel 3:4 and 1:1 both report a box shaped like 3:4 (`boxWidth` ×
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

    /// The viewfinder's own on-screen content size within a `boxSize`-sized
    /// box: 3:4 fills the box as-is; 1:1 is the box's width squared; both
    /// center for free inside a taller/wider box via a `ZStack`'s default
    /// alignment (PRD 0.2 FR-8.2 rule ②).
    ///
    /// Open (TASK-98, #402), `boxSize` is already the ratio's own fitted
    /// frame from `panelOpenViewfinderFrame(for:)`, so every ratio fills it
    /// as-is — there is no shared box to center inside any more (that was
    /// #120/#128's rule, superseded 2026-10-10). Closed, 9:16's `boxSize`
    /// already *is* the 9:16 shape from `viewfinderFrame(for:
    /// .nineBySixteen, boxWidth:)`, so it fills that too.
    func viewfinderContentSize(for ratio: CaptureAspectRatio, boxSize: CGSize, isPanelOpen: Bool) -> CGSize {
        guard !isPanelOpen else { return boxSize }
        switch ratio {
        case .threeByFour, .nineBySixteen:
            return boxSize
        case .oneByOne:
            return CGSize(width: boxSize.width, height: boxSize.width)
        }
    }

    // MARK: - Viewfinder placement (issue #153)

    /// Where the viewfinder's content sits for `ratio`: it is always laid
    /// out at its panel-closed size (`layoutSize`) and only *scaled* about
    /// its own center (`scale`) and moved (`center`) while the panel is open.
    /// Resizing the frame instead made a UIKit-backed camera preview jump to
    /// its final size, pinned to the top-left, while SwiftUI's spring was
    /// still running (issue #153); a `scaleEffect` also scales that layer.
    struct ViewfinderPlacement: Equatable {
        /// Size the content is laid out at (always the panel-closed size).
        var layoutSize: CGSize
        /// Scale applied about the content's center.
        var scale: CGSize
        /// The content's center in screen coordinates.
        var center: CGPoint
    }

    func viewfinderPlacement(for ratio: CaptureAspectRatio, isPanelOpen: Bool) -> ViewfinderPlacement {
        let closedBox = viewfinderFrame(for: ratio, boxWidth: screenSize.width)
        let layoutSize = viewfinderContentSize(for: ratio, boxSize: closedBox.size, isPanelOpen: false)
        let box = isPanelOpen ? panelOpenViewfinderFrame(for: ratio) : closedBox
        let size = viewfinderContentSize(for: ratio, boxSize: box.size, isPanelOpen: isPanelOpen)
        let scale = CGSize(width: layoutSize.width > 0 ? size.width / layoutSize.width : 1,
                           height: layoutSize.height > 0 ? size.height / layoutSize.height : 1)
        return ViewfinderPlacement(layoutSize: layoutSize, scale: scale, center: CGPoint(x: box.midX, y: box.midY))
    }

    // MARK: - Chrome-over-photo (issue #121)

    /// True when the viewfinder currently renders *behind* the header —
    /// only the 9:16 small-screen fallback while the panel is closed
    /// (`isFallback`, issue #101 assumption 2): that viewfinder fills the
    /// whole screen edge to edge, with the header floating over the top of
    /// it. Every other combination has the header sitting above either an
    /// empty area (nothing behind it) or, once the panel is open, the
    /// ratio's fitted panel-open viewfinder (TASK-98), which sits inside
    /// `panelOpenViewfinderArea` below the header regardless of ratio. `CameraScreen` reads this to decide
    /// between `CameraTheme.ink`/`inkOnPhoto` for the toolbar rather than
    /// hard-coding "9:16 means light chrome" itself, so the two stay in
    /// sync as this layout's own rules evolve (a real risk: issue #120
    /// already changed what "9:16, panel open" means once).
    func isViewfinderBehindHeader(ratio: CaptureAspectRatio, isPanelOpen: Bool) -> Bool {
        guard ratio == .nineBySixteen, !isPanelOpen else { return false }
        return isFallback
    }

    /// True when the viewfinder currently renders *behind* the footer —
    /// 9:16 while the panel is closed, fallback or not: its viewfinder
    /// always reaches down to (fallback) or past (rule ③, non-fallback)
    /// `footerRegionTop` either way. Once the panel is open, #120's shared
    /// panel-open viewfinder never reaches the footer regardless of ratio.
    func isViewfinderBehindFooter(ratio: CaptureAspectRatio, isPanelOpen: Bool) -> Bool {
        ratio == .nineBySixteen && !isPanelOpen
    }
}
