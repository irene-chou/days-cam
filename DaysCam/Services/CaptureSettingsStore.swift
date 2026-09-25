import Foundation

/// Holds the camera tools' state (PRD 0.2 §4.4).
///
/// `captureAspectRatio` and `showsGrid` survive a relaunch via `UserDefaults`;
/// `flashMode` and `timerSeconds` deliberately do not — leaving either one on
/// by accident is worse than the inconvenience of it resetting, since it
/// would fire on every photo until noticed rather than just this one.
///
/// This type owns no camera or file-system code: it is the one place the
/// camera toolbar's state lives, independent of any particular profile
/// (switching profiles never changes it).
final class CaptureSettingsStore: ObservableObject {
    private enum Keys {
        static let captureAspectRatio = "captureAspectRatio"
        static let showsGrid = "showsGrid"
    }

    /// Persisted across launches (PRD 0.2 §4.4).
    @Published private(set) var captureAspectRatio: CaptureAspectRatio
    /// Persisted across launches (PRD 0.2 §4.4).
    @Published private(set) var showsGrid: Bool

    /// In-memory only: always starts at `.off` for a freshly created store,
    /// i.e. every app launch (PRD 0.2 §4.4).
    @Published private(set) var flashMode: FlashMode = .off
    /// In-memory only: always starts at `.off` (0 seconds) for a freshly
    /// created store (PRD 0.2 §4.4).
    @Published private(set) var timerSeconds: TimerSetting = .off

    private let defaults: UserDefaults

    /// Creates a store, restoring `captureAspectRatio` and `showsGrid` from
    /// `defaults` if present.
    ///
    /// - Parameter defaults: where the persisted fields live. Defaults to
    ///   `.standard`; tests pass an isolated suite so restarts can be
    ///   simulated by constructing a second store against the same instance.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Keys.captureAspectRatio),
           let ratio = CaptureAspectRatio(rawValue: stored) {
            captureAspectRatio = ratio
        } else {
            captureAspectRatio = .threeByFour
        }
        showsGrid = defaults.bool(forKey: Keys.showsGrid)
    }

    /// Sets the capture aspect ratio (PRD 0.2 FR-7.7) and persists it.
    func setAspectRatio(_ ratio: CaptureAspectRatio) {
        captureAspectRatio = ratio
        defaults.set(ratio.rawValue, forKey: Keys.captureAspectRatio)
    }

    /// Flips the grid overlay (PRD 0.2 FR-7.9) and persists it.
    func toggleGrid() {
        showsGrid.toggle()
        defaults.set(showsGrid, forKey: Keys.showsGrid)
    }

    /// Advances the flash mode 關 → 自動 → 開 → 關 (PRD 0.2 FR-7.4). Not
    /// persisted, by design.
    func cycleFlash() {
        flashMode = flashMode.next
    }

    /// Advances the timer 關 → 3 秒 → 10 秒 → 關 (PRD 0.2 FR-7.5). Not
    /// persisted, by design.
    func cycleTimer() {
        timerSeconds = timerSeconds.next
    }
}
