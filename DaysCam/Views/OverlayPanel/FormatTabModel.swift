import Combine
import Foundation

/// Drives the overlay panel's 格式 (format) tab: display content and
/// day-count format (PRD 0.2 FR-11).
///
/// Both segments reuse `DisplaySettingsModel`'s interlock logic — the
/// showDayCount/showDate lock (FR-2.4) and the `displayUnits` toggling
/// (FR-11.3, FR-11.4) — rather than reimplementing it, so there is exactly
/// one place that logic lives. This model only adds the second-layer
/// navigation state (FR-8.5: plain text here, unlike the style tab's icons)
/// and the format-specific hidden-section hint (FR-11.5).
@MainActor
final class FormatTabModel: ObservableObject {
    /// Shown under 天數格式 once the day count itself is off (FR-11.5).
    static let dayCountFormatHiddenHintMessage = "天數未顯示，格式設定暫不作用"

    /// The second layer: 顯示內容｜天數格式, in display order (24.1).
    enum SubTab: CaseIterable {
        case displayContent
        case dayCountFormat

        /// Visible label — this tab's second layer is plain text (FR-8.5),
        /// unlike the style tab's icon-only row.
        var title: String {
            switch self {
            case .displayContent: return "顯示內容"
            case .dayCountFormat: return "天數格式"
            }
        }
    }

    /// Which second-layer item is selected. In-memory only, like the style
    /// tab's `selectedSubTab`.
    @Published var selectedSubTab: SubTab = .displayContent

    /// The shared display-settings logic this tab presents. Owned by the
    /// caller: TASK-22's panel shell is expected to build one
    /// `DisplaySettingsModel` per active profile and can hand the same
    /// instance to this tab and, until TASK-26 removes it, the legacy 0.1
    /// sheet — both then agree on every interlock by construction.
    let displaySettings: DisplaySettingsModel

    private var cancellables: Set<AnyCancellable> = []

    init(displaySettings: DisplaySettingsModel) {
        self.displaySettings = displaySettings
        // Forward so a view observing only this model still redraws when
        // `displaySettings.profile` changes.
        displaySettings.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
