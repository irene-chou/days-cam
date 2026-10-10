import Combine
import Foundation

/// Drives the overlay panel's 格式 (format) tab: display content and
/// day-count format (PRD 0.2 FR-11).
///
/// Both segments reuse `DisplaySettingsModel`'s `displayUnits` toggling
/// (FR-11.3, FR-11.4) and display switches rather than reimplementing them,
/// so there is exactly one place that logic lives. The day count is always
/// shown (0.4 R-13), so there is no hidden-section state. The old
/// 顯示內容｜天數格式 second layer was removed in TASK-38: both sections
/// share one page.
@MainActor
final class FormatTabModel: ObservableObject {
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
