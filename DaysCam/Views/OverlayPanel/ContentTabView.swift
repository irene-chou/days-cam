import SwiftUI

/// The 內容 (content) tab of the overlay panel (TASK-38, 0.3): a fixed
/// sub-tab row 格式｜天數規則 above the matching page.
///
/// Stands alone until TASK-37 (`ui-shell`) wires it into the panel's
/// first-layer control. It applies the 12/14 outer inset once, so both
/// sub-tabs share it and the sub-tab row never moves when switching.
struct ContentTabView: View {
    @ObservedObject var model: ContentTabModel
    @ObservedObject var formatTabModel: FormatTabModel
    @ObservedObject var rulesTabModel: RulesTabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            subTabRow
            switch model.selectedSubTab {
            case .format:
                FormatTabView(model: formatTabModel, appliesOuterPadding: false)
            case .rules:
                RulesTabView(model: rulesTabModel, appliesOuterPadding: false)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private var subTabRow: some View {
        // FR-8.5 look: left-aligned, gap 14, selected `active`, others tertiary.
        HStack(spacing: 14) {
            ForEach(ContentTabModel.SubTab.allCases, id: \.self) { subTab in
                let isSelected = model.selectedSubTab == subTab
                Button {
                    model.selectedSubTab = subTab
                } label: {
                    Text(subTab.title)
                        .font(CameraTheme.toolFont(.subheadline))
                        .foregroundColor(isSelected ? CameraTheme.active : CameraTheme.inkTertiary)
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Preview

@MainActor
private func previewModels(subTab: ContentTabModel.SubTab = .format)
    -> (ContentTabModel, FormatTabModel, RulesTabModel) {
    let profile = CameraProfile(name: "小寶",
                               startDate: DateComponents(year: 2026, month: 1, day: 1),
                               displayUnits: [.day])
    let content = ContentTabModel()
    content.selectedSubTab = subTab
    let format = FormatTabModel(displaySettings: DisplaySettingsModel(profile: profile) { _ in })
    let rules = RulesTabModel(profile: profile) { _ in }
    return (content, format, rules)
}

#Preview("格式子分頁 · iPhone SE 寬度 (375pt)") {
    let m = previewModels()
    return ContentTabView(model: m.0, formatTabModel: m.1, rulesTabModel: m.2)
        .frame(width: 375)
        .background(Color(.systemBackground))
}

#Preview("天數規則子分頁 · iPhone SE 寬度 (375pt)") {
    let m = previewModels(subTab: .rules)
    return ContentTabView(model: m.0, formatTabModel: m.1, rulesTabModel: m.2)
        .frame(width: 375)
        .background(Color(.systemBackground))
}
