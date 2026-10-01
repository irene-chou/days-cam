import SwiftUI

/// The overlay panel's shell (PRD 0.2 FR-8): the first-level segmented
/// control (樣式｜格式｜位置｜天數規則, FR-8.4) plus whichever tab's content is
/// currently selected.
///
/// Expanding/collapsing the panel and shrinking the viewfinder to 80% are
/// `CameraScreen`'s job (it owns the layout the panel appears inside of);
/// this view only lays out the segmented control and the tab body.
///
/// The segmented control (not the tab body below it) is the one exception
/// to PRD 0.2 §10's "無框線、無底色": comp A of `D3-tab-options.html` (the
/// finalized first-layer style, superseding `D2-overlay-panel.html`'s
/// borderless "v6" this file originally shipped with — #75) states plainly
/// that "分段控制本身有底色，是『非必要不加框』的例外" — an iOS segmented
/// control's own gray track, matching PRD FR-8.4's own wording.
struct OverlayPanelView: View {
    @ObservedObject var model: CameraScreenModel

    /// The scrolling area's fixed height below the segmented control
    /// (issue #128); taller tab content scrolls inside it.
    var contentHeight: CGFloat = 120

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
            ScrollView {
                tabContent
            }
            .frame(height: contentHeight)
            .overlay(alignment: .bottom) { scrollFade }
        }
        // Pinned top-aligned so the segmented control's y position stays
        // identical across every tab (#75, T.7).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CameraTheme.fill)
        )
        .padding(.horizontal, 2)
        .frame(height: CameraScreenLayoutMetrics.panelTabBarHeight)
    }

    /// 16pt fade from transparent to the panel's own background at the
    /// content area's bottom edge, hinting that it scrolls (issue #128).
    private var scrollFade: some View {
        LinearGradient(colors: [CameraTheme.background.opacity(0), CameraTheme.background],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 16)
            .allowsHitTesting(false)
    }

    /// The selected-segment shadow (`rgba(60,40,20,.15)`,
    /// `D3-tab-options.html:70`) — stated directly, like
    /// `CameraTheme.shutterRing`, since it is used in exactly one place.
    private static let selectedSegmentShadow = Color(red: 60 / 255, green: 40 / 255, blue: 20 / 255).opacity(0.15)

    /// One of the four equal-width segments (`.A .seg button`): selected
    /// gets a white, rounded, drop-shadowed chip; unselected stays plain
    /// text on the shared gray track — no dot, no per-segment border.
    private func tabButton(_ tab: OverlayPanelModel.Tab) -> some View {
        let isSelected = model.panelModel.selectedTab == tab
        return Button {
            model.panelModel.selectedTab = tab
        } label: {
            Text(tab.title)
                .font(CameraTheme.toolFont(.footnote))
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
                StyleTabView(model: styleTabModel)
            } else {
                placeholderTab(title: "樣式", subtitle: "尚未選取設定檔")
            }
        case .format:
            if let formatTabModel = model.formatTabModel {
                FormatTabView(model: formatTabModel)
            } else {
                placeholderTab(title: "格式", subtitle: "尚未選取設定檔")
            }
        case .position:
            if let positionTabModel = model.positionTabModel {
                PositionTabView(model: positionTabModel, availableHeight: contentHeight)
            } else {
                placeholderTab(title: "位置", subtitle: "尚未選取設定檔")
            }
        case .rules:
            if let rulesTabModel = model.rulesTabModel {
                RulesTabView(model: rulesTabModel)
            } else {
                placeholderTab(title: "天數規則", subtitle: "尚未選取設定檔")
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

#Preview("格式（FormatTabView 已接上）") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    model.panelModel.selectedTab = .format
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

#Preview("天數規則（RulesTabView 已接上）") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    model.panelModel.selectedTab = .rules
    return ZStack {
        CameraTheme.background.ignoresSafeArea()
        OverlayPanelView(model: model)
    }
}
