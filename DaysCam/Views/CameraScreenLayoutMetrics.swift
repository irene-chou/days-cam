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

    /// Footer row height while the panel is open (two 44×44 buttons).
    static let panelOpenFooterRowHeight: CGFloat = 44

    /// Gap between the panel's bottom edge and the footer row.
    static let panelToFooterGap: CGFloat = 4

    /// Gap between the footer row and `footerBase`.
    static let footerToBaseGap: CGFloat = 8

    /// Radius of the closed-panel shutter (76pt), used to place the side buttons.
    static let shutterRadius: CGFloat = 38

    /// Gap between the footer row and `footerBase` while the panel is closed.
    static let closedFooterBottomPadding: CGFloat = 16

    /// Where the footer's left button (thumbnail, or manage-profiles while
    /// the panel is open) is centered — the landing spot for a capture
    /// flight (issue #148). Closed, the 76pt shutter sets the row height.
    func leftFooterButtonCenter(isPanelOpen: Bool) -> CGPoint {
        let rowCenterFromBase = isPanelOpen
            ? Self.footerToBaseGap + Self.panelOpenFooterRowHeight / 2
            : Self.closedFooterBottomPadding + Self.shutterRadius
        return CGPoint(x: footerSideButtonCenterInset, y: footerBase - rowCenterFromBase)
    }

    /// True for iPhone SE-class heights (< 700pt).
    var isSmallScreen: Bool {
        screenSize.height < Self.smallScreenHeightThreshold
    }

    /// The scrolling area's height below the tab bar — fixed per screen
    /// class, independent of which tab is selected.
    var panelContentHeight: CGFloat {
        isSmallScreen ? 104 : 120
    }

    /// Tab bar plus content area.
    var panelHeight: CGFloat {
        panelTabBarHeight + panelContentHeight
    }

    /// Gap between the viewfinder box's bottom edge and the panel's top.
    var panelGapAboveBox: CGFloat {
        isSmallScreen ? 4 : 6
    }

    /// The panel's bottom edge (screen y, top-down).
    var panelBottom: CGFloat {
        footerBase - Self.footerToBaseGap - Self.panelOpenFooterRowHeight - Self.panelToFooterGap
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

    /// The shared 3:4 box every ratio uses while the panel is open: height
    /// = the available area, width = 3/4 of it; capped to the screen width
    /// (then height follows). Top-aligned to the header, horizontally centered.
    var panelOpenViewfinderFrame: CGRect {
        let areaHeight = max(panelOpenViewfinderAreaHeight, 0)
        var width = areaHeight * 3 / 4
        var height = areaHeight
        if width > screenSize.width {
            width = screenSize.width
            height = width * 4 / 3
        }
        return CGRect(x: (screenSize.width - width) / 2, y: headerBottom, width: width, height: height)
    }

    /// Distance from each screen edge to the center of the footer's side
    /// buttons: midway between the edge and the shutter's edge, so the
    /// buttons stay put whether or not the shutter is shown.
    var footerSideButtonCenterInset: CGFloat {
        (screenSize.width / 2 - Self.shutterRadius) / 2
    }

    // MARK: - Tools capsule (issue #135)

    /// The toolbar's left/right inset (`CameraToolbar`'s horizontal padding).
    static let toolbarHorizontalInset: CGFloat = 12

    /// The toolbar's icon button height.
    static let toolbarButtonHeight: CGFloat = 38

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
    /// 9:16 depends on `isPanelOpen` (issue #120): closed, `boxSize` already
    /// *is* the 9:16 shape from `viewfinderFrame(for: .nineBySixteen,
    /// boxWidth:)`, so content fills it as-is, same as 3:4. Open, callers
    /// pass the *shared* panel-open box instead — the exact same 80%-width,
    /// 3:4-shaped box 3:4/1:1 use (`viewfinderFrame(for: .threeByFour,
    /// boxWidth:)`, PRD 0.2 FR-8.2) — because PRD 0.2 FR-7.8's own full-bleed
    /// 9:16 has no defined position once the panel covers part of the
    /// screen (issue #120's own background: the overlay text landed
    /// underneath the panel with no way to drag it out). Fitting a 9:16
    /// rectangle to that box's *height* and letting it center horizontally
    /// the same way 1:1 centers vertically keeps the whole photo above the
    /// panel, fully draggable, on every ratio the same size/position rules
    /// (issue #120's whole point).
    func viewfinderContentSize(for ratio: CaptureAspectRatio, boxSize: CGSize, isPanelOpen: Bool) -> CGSize {
        switch ratio {
        case .threeByFour:
            return boxSize
        case .oneByOne:
            return CGSize(width: boxSize.width, height: boxSize.width)
        case .nineBySixteen:
            guard isPanelOpen else { return boxSize }
            let height = boxSize.height
            return CGSize(width: height * 9 / 16, height: height)
        }
    }

    // MARK: - Chrome-over-photo (issue #121)

    /// True when the viewfinder currently renders *behind* the header —
    /// only the 9:16 small-screen fallback while the panel is closed
    /// (`isFallback`, issue #101 assumption 2): that viewfinder fills the
    /// whole screen edge to edge, with the header floating over the top of
    /// it. Every other combination has the header sitting above either an
    /// empty area (nothing behind it) or, once the panel is open, #120's
    /// shared panel-open viewfinder, which never reaches up behind the
    /// header regardless of ratio. `CameraScreen` reads this to decide
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
