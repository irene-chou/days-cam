import SwiftUI

/// The overlay panel's shell (PRD 0.2 FR-8): the first-level segmented
/// control (樣式｜內容｜位置, TASK-37), whichever tab's content is currently
/// selected, and the collapse chevron at the end of the segmented row
/// (TASK-116, #447, design option A — it replaced TASK-99's floating
/// button; a downward swipe on that row collapses too).
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

    /// Collapse the panel: the chevron, a downward swipe on the segmented
    /// row, or VoiceOver's escape.
    var onCollapse: () -> Void = {}

    /// The segmented control's distance from each screen edge. `CameraScreen`
    /// passes `CameraScreenLayoutMetrics.panelGapAboveBox` (6, small screens
    /// 4) so the track's side margin equals the gap between the viewfinder
    /// and the panel above it (human decision 2026-10-11; it was a fixed 2).
    var tabBarHorizontalInset: CGFloat = 6

    /// A downward drag this far (pt) on the segmented row collapses.
    static let collapseSwipeDistance: CGFloat = 30
    /// A fast flick whose predicted end travels this far also collapses.
    static let collapseSwipePredictedDistance: CGFloat = 80
    /// The chevron's tap target (TASK-116, 116.2).
    static let collapseButtonTapSide: CGFloat = 44
    /// Gap between the gray track and the chevron.
    static let collapseButtonGap: CGFloat = 4

    /// Whether a drag that ended on the segmented row should collapse the
    /// panel (116.3／116.4): downward past 30pt, or predicted to travel 80pt,
    /// and more vertical than horizontal. Up, sideways and short drags do
    /// nothing.
    static func shouldCollapse(translation: CGSize, predictedEndTranslation: CGSize) -> Bool {
        guard translation.height > 0, abs(translation.height) > abs(translation.width) else { return false }
        return translation.height >= collapseSwipeDistance
            || predictedEndTranslation.height >= collapseSwipePredictedDistance
    }

    /// Room every tab leaves under its last row (116.8): the band plus 8pt.
    static func bottomContentInset(bottomSafeAreaInset: CGFloat) -> CGFloat {
        bottomSafeAreaInset + 8
    }

    /// What every tab keeps clear under its last row.
    private var bottomContentInset: CGFloat {
        Self.bottomContentInset(bottomSafeAreaInset: bottomSafeAreaInset)
    }

    /// The chevron grows with Dynamic Type, capped at 22pt.
    @ScaledMetric(relativeTo: .footnote) private var chevronSize: CGFloat = 17

    var body: some View {
        VStack(spacing: 0) {
            segmentedControl
                // Clear of the rounded top edge (PR #455).
                .padding(.top, CameraScreenLayoutMetrics.panelTopPadding)
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
            // content shows through the band, under `safeAreaFade`.
            Group {
                if model.panelModel.selectedTab == .style, let styleTabModel = model.styleTabModel {
                    // The style tab owns its scrolling (fixed sub-tab row above
                    // its own scroll view, TASK-66), so it is not wrapped here;
                    // it keeps the band clear under its last
                    // row itself.
                    StyleTabView(model: styleTabModel, availableHeight: contentHeight,
                                 bottomContentInset: bottomContentInset)
                } else {
                    ScrollView {
                        tabContent
                            // Room for the last row to scroll up above the
                            // band (116.8).
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
        }
        // Pinned top-aligned so the segmented control's y position stays
        // identical across every tab (#75, T.7).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Same-color surface with an upward shadow along its top edge
        // (restored on PR #451 at the user's request); it runs off the
        // bottom of the screen.
        .background(panelBackground)
        // The whole panel answers the escape gesture; the chevron is the
        // visible control.
        .accessibilityAction(.escape) { onCollapse() }
    }

    // MARK: - Panel surface (FR-8.8, design option 2)

    /// The panel's own surface: the camera background color, top corners
    /// rounded, with a soft shadow along the top edge only. The shadow is
    /// masked to a 100pt band at the top so it never shows at the sides or
    /// below; the fill is drawn again on top without the shadow. No border.
    private var panelBackground: some View {
        let cornerRadius = CameraScreenLayoutMetrics.panelTopCornerRadius
        let shape = UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0,
                                           bottomTrailingRadius: 0, topTrailingRadius: cornerRadius,
                                           style: .continuous)
        return ZStack {
            shape
                .fill(CameraTheme.background)
                .shadow(color: CameraTheme.popoverShadow,
                        radius: CameraScreenLayoutMetrics.panelShadowRadius,
                        x: 0, y: CameraScreenLayoutMetrics.panelShadowYOffset)
                .mask(alignment: .top) {
                    Rectangle()
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .offset(y: cornerRadius - 100)
                }
            shape.fill(CameraTheme.background)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Collapse button (TASK-116, #447, design option A)

    /// A bare `chevron.down` at the end of the segmented row: no disc, no
    /// shadow. Its 44pt tap target extends above and below the row without
    /// changing the row's height.
    private var collapseButton: some View {
        let side = Self.collapseButtonTapSide
        return Button(action: onCollapse) {
            Image(systemName: "chevron.down")
                .font(.system(size: min(chevronSize, 22), weight: .semibold))
                .foregroundColor(CameraTheme.ink)
                .frame(width: side, height: max(side, tabBarHeight))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: side, height: tabBarHeight)
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
        HStack(spacing: Self.collapseButtonGap) {
            segmentTrack
            collapseButton
        }
        // The chevron's right edge sits the same distance from the screen
        // edge as the track's left edge (2026-10-11 margin, TASK-116).
        .padding(.horizontal, tabBarHorizontalInset)
        .contentShape(Rectangle())
        // A downward swipe on this row collapses on release; the panel does
        // not follow the finger (116.6) and the list below never sees it.
        .simultaneousGesture(
            DragGesture(minimumDistance: 10).onEnded { value in
                if Self.shouldCollapse(translation: value.translation,
                                       predictedEndTranslation: value.predictedEndTranslation) {
                    onCollapse()
                }
            }
        )
    }

    private var segmentTrack: some View {
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
