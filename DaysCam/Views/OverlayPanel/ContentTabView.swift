import SwiftUI

/// The 內容 (content) tab of the overlay panel (0.4 TASK-45, #226 R-11):
/// the day-count format and the 顯示內容 switches, with no sub-tabs.
///
/// Name, start date and counting rule live on the profile edit page now.
/// It applies the 12/14 outer inset once, so the layout matches TASK-38's
/// 格式 page minus the sub-tab row.
struct ContentTabView: View {
    @ObservedObject var formatTabModel: FormatTabModel

    var body: some View {
        FormatTabView(model: formatTabModel, appliesOuterPadding: false)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
    }
}

// MARK: - Preview

#Preview("內容分頁 · iPhone SE 寬度 (375pt)") {
    let profile = CameraProfile(name: "小寶",
                               startDate: DateComponents(year: 2026, month: 1, day: 1),
                               displayUnits: [.day])
    let format = FormatTabModel(displaySettings: DisplaySettingsModel(profile: profile) { _ in })
    return ContentTabView(formatTabModel: format)
        .frame(width: 375)
        .background(Color(.systemBackground))
}
