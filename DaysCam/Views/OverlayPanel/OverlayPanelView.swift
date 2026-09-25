import SwiftUI

/// The overlay panel's shell (PRD 0.2 FR-8): the first-level segmented
/// control (樣式｜格式｜位置｜天數規則, FR-8.4) plus whichever tab's content is
/// currently selected.
///
/// Expanding/collapsing the panel and shrinking the viewfinder to 80% are
/// `CameraScreen`'s job (it owns the layout the panel appears inside of);
/// this view only lays out the segmented control and the tab body. No
/// background, no border (FR-8.8) — it sits directly on `CameraTheme
/// .background`.
struct OverlayPanelView: View {
    @ObservedObject var model: CameraScreenModel

    var body: some View {
        VStack(spacing: 10) {
            segmentedControl
            tabContent
        }
        .padding(.top, 4)
    }

    // MARK: - First layer (FR-8.4)

    /// Borderless by design (PRD 0.2 §10 "按鈕 | 無框線、無底色"): the
    /// selected tab is only distinguished by darker text plus a small
    /// `active`-colored dot underneath, matching D-2's final ("v6") revision
    /// — not a filled segmented-control track.
    private var segmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(OverlayPanelModel.Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
    }

    private func tabButton(_ tab: OverlayPanelModel.Tab) -> some View {
        let isSelected = model.panelModel.selectedTab == tab
        return Button {
            model.panelModel.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Text(tab.title)
                    .font(CameraTheme.toolFont(.footnote))
                    .foregroundColor(isSelected ? CameraTheme.ink : CameraTheme.inkSecondary)
                Circle()
                    .fill(isSelected ? CameraTheme.active : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Second layer: tab bodies

    /// TASK-23（樣式）／TASK-24（格式／位置）fill these in as their own PRs
    /// land; TASK-25（天數規則）already has — see `RulesTabView`. Until then
    /// the still-missing tabs show a plain placeholder so the panel is at
    /// least navigable end to end (PRD 0.2 TASK-22 scope: "各分頁先放空白佔位").
    @ViewBuilder
    private var tabContent: some View {
        switch model.panelModel.selectedTab {
        case .style:
            // TEMP(TASK-22→23): `StyleTabView`/`StyleTabModel` exist (PR #53)
            // but were not yet merged when this was written (still working
            // through required bot-review changes) — placeholder until they
            // land; see this file's own PR description for the swap-in note.
            placeholderTab(title: "樣式", subtitle: "字型、顏色、外框、陰影、字級")
        case .format:
            placeholderTab(title: "格式", subtitle: "顯示內容、天數格式")
        case .position:
            placeholderTab(title: "位置", subtitle: "九宮格快速對齊、拖曳自訂位置")
        case .rules:
            if let rulesTabModel = model.rulesTabModel {
                RulesTabView(model: rulesTabModel)
            } else {
                // Only reachable in the brief window before any profile is
                // selected (PRD FR-1.8 guarantees this never happens once
                // the app has actually launched).
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

#Preview("樣式（佔位）") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
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
