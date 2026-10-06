import Foundation

/// Drives the overlay panel's 內容 (content) tab: a text sub-tab row
/// 格式｜天數規則 (TASK-38, 0.3). Holds only the in-memory selection; the
/// settings themselves live in `FormatTabModel` and `RulesTabModel`.
@MainActor
final class ContentTabModel: ObservableObject {
    /// The second layer: 格式｜天數規則, in display order.
    enum SubTab: CaseIterable {
        case format
        case rules

        /// Visible label (plain text, like 0.2 FR-8.5's text second layer).
        var title: String {
            switch self {
            case .format: return "格式"
            case .rules: return "天數規則"
            }
        }
    }

    /// Which sub-tab is selected. In-memory only: a new model (app relaunch)
    /// starts on 格式, like 0.2 A-4.
    @Published var selectedSubTab: SubTab = .format
}
