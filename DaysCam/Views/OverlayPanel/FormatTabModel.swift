import Combine
import Foundation

/// Drives the overlay panel's 格式 (format) tab: display content and
/// day-count format (PRD 0.2 FR-11).
///
/// Both segments reuse `DisplaySettingsModel`'s interlock logic — the
/// showDayCount/showDate lock (FR-2.4) and the `displayUnits` toggling
/// (FR-11.3, FR-11.4) — rather than reimplementing it, so there is exactly
/// one place that logic lives. This model only adds the format-specific
/// hidden-section hint (FR-11.5). The old 顯示內容｜天數格式 second layer was
/// removed in TASK-38: both sections share one page.
@MainActor
final class FormatTabModel: ObservableObject {
    /// Shown under 天數格式 once the day count itself is off (FR-11.5).
    static let dayCountFormatHiddenHintMessage = "天數未顯示，格式設定暫不作用"

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
