import SwiftUI

/// The overlay panel's shell (PRD 0.2 FR-8): the first-level segmented
/// control (樣式｜內容｜位置, TASK-37), whichever tab's content is currently
/// selected, and the floating collapse button in the bottom-right corner
/// (TASK-99, #404, design option D — it replaced TASK-92's pull-to-dismiss
/// strip, which the user found awkward).
///
/// Expanding/collapsing the panel and resizing the viewfinder are
/// `CameraScreen`'s job (it owns the layout the panel appears inside of);
/// this view only lays out the segmented control, the tab body and the
/// collapse button, and asks for the collapse through `onCollapse` — it
/// never closes `OverlayPanelModel` directly.
///
/// The segmented control (not the tab body below it) is the one exception
/// to PRD 0.2 §10's "無框線、無底色": comp A of `D3-tab-options.html` (the
/// finalized first-layer style, superseding `D2-overlay-panel.html`'s
/// borderless "v6" this file originally shipped with — #75) states plainly
/// that "分段控制本身有底色，是『非必要不加框』的例外" — an iOS segmented
/// control's own gray track, matching PRD FR-8.4's own wording.
struct OverlayPanelView: View {
    @ObservedObject var model: CameraScreenModel

    /// The usable scrolling area's fixed height below the segmented control
    /// (issue #128, `CameraScreenLayoutMetrics.panelContentHeight`); taller
    /// tab content scrolls inside it.
    var contentHeight: CGFloat = 244

    /// The segmented control's height, scaled with Dynamic Type by
    /// `CameraScreen` so the panel's total height accounts for it (#139).
    var tabBarHeight: CGFloat = CameraScreenLayoutMetrics.defaultPanelTabBarHeight

    /// The home-indicator band below `contentHeight` (TASK-92): the scroll
    /// view runs on through it so content is seen there, faded out, but
    /// nothing in it can be tapped (92.7). 0 on a 4.7-inch screen: no band,
    /// no fade (92.12).
    var bottomSafeAreaInset: CGFloat = 0

    /// Collapse the panel: the collapse button, or VoiceOver's escape (99.8).
    var onCollapse: () -> Void = {}

    /// Diameter of the collapse button's white disc (TASK-99, #404).
    static let collapseButtonDiameter: CGFloat = 40
    /// The collapse button's tap target.
    static let collapseButtonTapSide: CGFloat = 44
    /// Distance from the button's right edge to the screen's right edge, and
    /// from its bottom edge to `footerBase` (the home indicator's top edge).
    static let collapseButtonInset: CGFloat = 12
    /// Room every tab leaves under its last row so it can scroll up above
    /// the button (99.6): the band, the button's inset and tap target, and
    /// 8pt of clearance.
    static func bottomContentInset(bottomSafeAreaInset: CGFloat) -> CGFloat {
        bottomSafeAreaInset + collapseButtonInset + collapseButtonTapSide + 8
    }

    /// What every tab keeps clear under its last row (99.6).
    private var bottomContentInset: CGFloat {
        Self.bottomContentInset(bottomSafeAreaInset: bottomSafeAreaInset)
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentedControl
            // The tab body scrolls within whatever space is left, rather
            // than growing the panel or getting clipped, on a tab whose
            // content is taller than the panel (#75, T.8) — e.g. the format
            // tab on a narrow phone.
            //
            // No padding here (#105/#111 coordination, Lead 2026-09-27):
            // D-2's `.tabbody{padding:12px 14px}` looked like this
            // container's job, but each tab already applies its own
            // D-3/D-4-specific inset (e.g. the style tab's `.tabbody{
            // padding:4px 10px 6px}`, PR #111) — adding a second, generic
            // one here would double it up on every tab.
            //
            // The tab body is `contentHeight` of usable area plus the
            // home-indicator band (TASK-92): the scroll view spans both, so
            // content shows through the band, under `safeAreaFade`. The
            // collapse button floats over the bottom-right corner (TASK-99).
            Group {
                if model.panelModel.selectedTab == .style, let styleTabModel = model.styleTabModel {
                    // The style tab owns its scrolling (fixed sub-tab row above
                    // its own scroll view, TASK-66), so it is not wrapped here;
                    // it keeps the band and the button clear under its last
                    // row itself.
                    StyleTabView(model: styleTabModel, availableHeight: contentHeight,
                                 bottomContentInset: bottomContentInset)
                } else {
                    ScrollView {
                        tabContent
                            // Room for the last row to scroll up above the
                            // band and the collapse button (99.6).
                            .padding(.bottom, bottomContentInset)
                    }
                    // Fades at the edges with more content, and one flash of the
                    // indicator per tab (TASK-58b).
                    .scrollEdgeHint(flashTrigger: model.panelModel.selectedTab)
                    // Every first-level tab starts at the top (TASK-66).
                    .id(model.panelModel.selectedTab)
                }
            }
            .frame(height: contentHeight + bottomSafeAreaInset)
            .overlay(alignment: .bottom) { safeAreaFade }
            .overlay(alignment: .bottomTrailing) { collapseButton }
        }
        // Pinned top-aligned so the segmented control's y position stays
        // identical across every tab (#75, T.7).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // No surface of its own (PRD FR-8.8 as restored by TASK-99): the
        // panel sits straight on the camera background — no shadow, corner
        // or border — and runs off the bottom of the screen.
        .background(CameraTheme.background.ignoresSafeArea(edges: .bottom))
        // The whole panel answers the escape gesture (99.8); the collapse
        // button is the visible control.
        .accessibilityAction(.escape) { onCollapse() }
    }

    // MARK: - Collapse button (TASK-99, #404, design option D)

    /// A 40pt white disc with a soft shadow and a `chevron.down`, floating
    /// over the list in the panel's bottom-right corner: 12pt in from the
    /// screen's right edge and 12pt above `footerBase` (the band below the
    /// usable area is `bottomSafeAreaInset` tall), inside a 44×44 tap target.
    /// It never scrolls and never moves between tabs (99.5). The disc and
    /// its shadow are a FR-14.2 exception — a button floating over a list
    /// needs a surface to be seen.
    private var collapseButton: some View {
        let targetOverhang = (Self.collapseButtonTapSide - Self.collapseButtonDiameter) / 2
        return Button(action: onCollapse) {
            ZStack {
                Circle()
                    .fill(CameraTheme.popoverBackground)
                    .shadow(color: CameraTheme.popoverShadow, radius: 12, x: 0, y: 4)
                    .frame(width: Self.collapseButtonDiameter, height: Self.collapseButtonDiameter)
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CameraTheme.ink)
            }
            .frame(width: Self.collapseButtonTapSide, height: Self.collapseButtonTapSide)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, Self.collapseButtonInset - targetOverhang)
        .padding(.bottom, bottomSafeAreaInset + Self.collapseButtonInset - targetOverhang)
        .accessibilityLabel("收合面板")
        .accessibilityIdentifier("panelCollapseButton")
    }

    /// The home-indicator band (TASK-92): content scrolling through it
    /// fades into the panel background, and the band swallows touches so
    /// nothing seen there can be operated (92.7) — the usable area ends at
    /// `contentHeight`. Nothing on a 4.7-inch screen (92.12).
    @ViewBuilder
    private var safeAreaFade: some View {
        if bottomSafeAreaInset > 0 {
            LinearGradient(colors: [CameraTheme.background.opacity(0), CameraTheme.background],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: bottomSafeAreaInset)
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)
        }
    }

    // MARK: - First layer (FR-8.4, comp A)

    /// The gray track (`rgba(42,38,34,.07)` — `CameraTheme.fill`, already
    /// documented there for exactly this use), corner radius 10, 2pt inset
    /// on every side (`D3-tab-options.html:68`, `.A .seg`).
    ///
    /// #105 re-checked this against `D2-overlay-panel.html`'s own `.tabs`/
    /// `.tab` rules (`padding:8px 10px`/`6px 4px`, no background, a bottom
    /// hairline) and left it unchanged: those numbers describe the exact
    /// borderless style `D3-tab-options.html` superseded per the doc comment
    /// above (#75) — `D2-overlay-panel.html` itself never got that follow-up
    /// edit, so its numbers are stale for this one element, not a gap #105
    /// should close.
    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(OverlayPanelModel.Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(2)
        .frame(height: tabBarHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CameraTheme.fill)
        )
        .padding(.horizontal, 2)
    }

    /// The selected-segment shadow (`rgba(60,40,20,.15)`,
    /// `D3-tab-options.html:70`) — stated directly, like
    /// `CameraTheme.shutterRing`, since it is used in exactly one place.
    private static let selectedSegmentShadow = Color(red: 60 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.15)

    /// One of the three equal-width segments (`.A .seg button`): selected
    /// gets a white, rounded, drop-shadowed chip; unselected stays plain
    /// text on the shared gray track — no dot, no per-segment border.
    private func tabButton(_ tab: OverlayPanelModel.Tab) -> some View {
        let isSelected = model.panelModel.selectedTab == tab
        return Button {
            model.panelModel.selectedTab = tab
        } label: {
            Text(tab.title)
                .font(CameraTheme.toolFont(.footnote))
                // One line that shrinks rather than wraps or overflows at
                // large Dynamic Type sizes (#139).
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(isSelected ? CameraTheme.ink : CameraTheme.inkSecondary)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.white : Color.clear)
                        .shadow(color: isSelected ? Self.selectedSegmentShadow : .clear, radius: 3, x: 0, y: 1)
                )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Second layer: tab bodies

    /// Every tab's model is built by `CameraScreenModel` once a profile is
    /// selected (TASK-22/23/24, #65) — the brief `nil` window before that
    /// (PRD FR-1.8 guarantees it never happens once the app has actually
    /// launched) falls back to the same plain placeholder this file used
    /// before TASK-23/24 landed.
    @ViewBuilder
    private var tabContent: some View {
        switch model.panelModel.selectedTab {
        case .style:
            if let styleTabModel = model.styleTabModel {
                StyleTabView(model: styleTabModel, availableHeight: contentHeight)
            } else {
                placeholderTab(title: "樣式", subtitle: "尚未選取設定檔")
            }
        case .content:
            if let formatTabModel = model.formatTabModel {
                ContentTabView(formatTabModel: formatTabModel)
            } else {
                placeholderTab(title: "內容", subtitle: "尚未選取設定檔")
            }
        case .position:
            if let positionTabModel = model.positionTabModel {
                PositionTabView(model: positionTabModel, availableHeight: contentHeight)
            } else {
                placeholderTab(title: "位置", subtitle: "尚未選取設定檔")
            }
        }
    }

    private func placeholderTab(title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(CameraTheme.toolFont(.subheadline))
                .foregroundColor(CameraTheme.ink)
            Text(subtitle)
                .font(.footnote)
                .foregroundColor(CameraTheme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

#Preview("樣式（StyleTabView 已接上）") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    return ZStack {
        CameraTheme.background.ignoresSafeArea()
        OverlayPanelView(model: model)
    }
}

#Preview("內容分頁") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    model.panelModel.selectedTab = .content
    return ZStack {
        CameraTheme.background.ignoresSafeArea()
        OverlayPanelView(model: model)
    }
}

#Preview("位置（PositionTabView 已接上）") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    model.panelModel.selectedTab = .position
    return ZStack {
        CameraTheme.background.ignoresSafeArea()
        OverlayPanelView(model: model)
    }
}
