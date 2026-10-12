import Combine
import Foundation

/// The two-step first-launch spotlight (TASK-96, #400): which step is on
/// screen, when it may start, and the one `UserDefaults` record that says
/// whether it is still due. Pure state — `OnboardingSpotlightView` draws it
/// and `CameraScreenModel` wires the camera permission, the fresh-install
/// check and the two targets to it.
///
/// Rules (issue #400, 2026-10-10): the tour is for **fresh installs only**.
/// The first launch that finds no record decides once — the profile store
/// seeded because there was no file → `pending`; anything else (profiles
/// already there, or re-seeded after corruption) → `done`, never shown.
/// While `pending`, it starts once the camera permission prompt has been
/// answered (granted or denied alike); it becomes `done` when step 2's
/// 知道了 is tapped, when either highlighted target is tapped, or on the
/// VoiceOver escape — never on step 1's 下一步 alone, so quitting during step
/// 1 shows step 1 again next launch (96.7).
///
/// Not `@MainActor`: `CameraScreenModel` creates it as a default argument
/// (a nonisolated context); every call still comes from the main queue.
final class OnboardingSpotlightModel: ObservableObject {
    /// One step of the tour, with its final copy (#400, not to be edited).
    enum Step: Int, CaseIterable, Equatable {
        case startDate = 1
        case overlayStyle = 2

        /// "1 / 2", "2 / 2".
        var stepLabel: String { "\(rawValue) / \(Step.allCases.count)" }

        var title: String {
            switch self {
            case .startDate: return "設定日期"
            case .overlayStyle: return "設定疊字樣式"
            }
        }

        var message: String {
            switch self {
            case .startDate: return "點這裡設定要記錄的日子。"
            case .overlayStyle: return "點這裡調整照片上的文字：字型、顏色、位置等等。"
            }
        }

        var buttonTitle: String {
            switch self {
            case .startDate: return "下一步"
            case .overlayStyle: return "知道了"
            }
        }

        /// The button this step highlights and lets through.
        var target: OnboardingTarget {
            switch self {
            case .startDate: return .profileChip
            case .overlayStyle: return .overlayPanelButton
            }
        }

        /// A second, look-only cut-out: step 2 also lights up the overlay
        /// text on the viewfinder (#400 外觀, design step 2 B), which stays
        /// non-interactive (96.19).
        var secondaryTarget: OnboardingTarget? {
            self == .overlayStyle ? .overlayText : nil
        }
    }

    /// The stored record: `pending` (due), `done` (finished, or never due).
    /// No record means the fresh-install decision has not been made yet.
    enum State: String, Equatable {
        case pending
        case done
    }

    /// The `UserDefaults` key; app-level, never part of a profile (96.12).
    static let stateKey = "onboardingSpotlightState"

    /// The step on screen, or `nil` while the tour is not showing.
    @Published private(set) var step: Step?

    private let defaults: UserDefaults
    /// `-UITestSkipOnboarding`: this launch neither shows the tour nor
    /// touches the stored record.
    private let isSkippedForThisLaunch: Bool

    /// - Parameters:
    ///   - defaults: where the record lives; `.standard` in the app.
    ///   - arguments: launch arguments. Debug builds honor
    ///     `-UITestSkipOnboarding` (never show, write nothing) and
    ///     `-UITestResetOnboarding` (set the record to `pending`, so the
    ///     tour shows again); release builds ignore both.
    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        var skipped = false
        #if DEBUG
        skipped = arguments.contains("-UITestSkipOnboarding")
        if arguments.contains("-UITestResetOnboarding") {
            defaults.set(State.pending.rawValue, forKey: Self.stateKey)
        }
        #endif
        isSkippedForThisLaunch = skipped
    }

    /// The stored record, or `nil` before the first decision.
    var state: State? {
        defaults.string(forKey: Self.stateKey).flatMap(State.init(rawValue:))
    }

    /// Whether the tour is finished or was never due on this install.
    var isDone: Bool { state == .done }

    /// Whether the tour is on screen.
    var isActive: Bool { step != nil }

    /// The one-time fresh-install decision (#400 行為): with no record yet, a
    /// launch whose profile store seeded because there was no file becomes
    /// `pending`; any other launch becomes `done` (96.16, 96.17). A record
    /// that already exists is left alone, so a `pending` tour survives being
    /// quit during step 1 (96.7). A skipped launch writes nothing.
    func decideIfNeeded(isFreshInstall: Bool) {
        guard state == nil, !isSkippedForThisLaunch else { return }
        defaults.set((isFreshInstall ? State.pending : .done).rawValue, forKey: Self.stateKey)
    }

    /// Called whenever the camera permission changes. The first time it is
    /// anything but `.notDetermined` — the system prompt has been answered,
    /// or was answered on an earlier launch — a `pending` tour starts at
    /// step 1, unless this launch skips it (96.8).
    func cameraPermissionDidChange(_ permission: CameraPermission) {
        guard permission != .notDetermined, step == nil, state == .pending, !isSkippedForThisLaunch else { return }
        step = .startDate
    }

    /// The bubble's button: 下一步 moves to step 2, 知道了 ends the tour.
    func advance() {
        switch step {
        case .startDate: step = .overlayStyle
        case .overlayStyle: finish()
        case nil: break
        }
    }

    /// The highlighted target was tapped: the tour ends (and the caller
    /// performs the target's own action) — step 2 never shows after a
    /// step-1 target tap (96.4, 96.5).
    func targetTapped() {
        finish()
    }

    /// Ends the tour and records it as done; a no-op while not showing.
    func finish() {
        guard step != nil else { return }
        defaults.set(State.done.rawValue, forKey: Self.stateKey)
        step = nil
    }
}

/// What the tour points at; `CameraToolbar`, `CameraScreen` and
/// `OverlayTextView` publish their frames under these keys.
enum OnboardingTarget: Hashable {
    case profileChip
    case overlayPanelButton
    /// The day-count text on the viewfinder — lit up on step 2, never
    /// interactive (#400, 96.19).
    case overlayText
}
