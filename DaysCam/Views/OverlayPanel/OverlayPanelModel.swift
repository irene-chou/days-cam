import Foundation

/// The overlay panel's shell state (PRD 0.2 FR-8): whether it is open, and
/// which first-level tab is currently selected.
///
/// Pure state, no service dependency, owned by `CameraScreenModel` the same
/// way `profileListModel` is (TASK-22). `selectedTab` deliberately is *not*
/// persisted to disk: PRD 0.2 A-4 only wants it remembered while the app
/// stays open — surviving `close()`/`open()` within the same launch
/// (acceptance 22.2) — not across relaunches, so a freshly constructed
/// instance always starts at `.style` (acceptance 22.3).
final class OverlayPanelModel: ObservableObject {
    /// The panel's first-level tabs (PRD 0.2 FR-8.4), in display order.
    enum Tab: CaseIterable, Equatable, Hashable {
        case style, format, position, rules

        /// The segmented control's label (PRD 0.2 FR-8.4).
        var title: String {
            switch self {
            case .style: return "樣式"
            case .format: return "格式"
            case .position: return "位置"
            case .rules: return "天數規則"
            }
        }
    }

    /// Whether the panel is expanded (PRD 0.2 FR-8.1).
    @Published private(set) var isOpen = false
    /// Which tab is selected. Starts at `.style`; once changed, keeps its
    /// value across `close()`/`open()` for the rest of this launch (A-4).
    @Published var selectedTab: Tab = .style

    /// TASK-24's position-tab model, once ui-panel wires one in. `nil` until
    /// then, so the overlay is simply not draggable yet — see
    /// `CameraScreen`'s use of this alongside `isOverlayDraggable`. Whoever
    /// builds the position tab's model is expected to assign itself here
    /// while its tab is on screen (this file does not know that type yet).
    weak var overlayDragHandler: OverlayDragHandling?

    init() {}

    /// Expands the panel (PRD 0.2 FR-8.1).
    func open() {
        isOpen = true
    }

    /// Collapses the panel — the "收起" key, or tapping the viewfinder
    /// outside the overlay text while open (PRD 0.2 FR-8.3, FR-8.7). Does
    /// not reset `selectedTab` (acceptance 22.2).
    func close() {
        isOpen = false
    }
}

// MARK: - Bottom bar (PRD 0.2 FR-7.3, FR-8.3, acceptance 22.5)

extension OverlayPanelModel {
    /// What the bottom bar's left key does right now.
    enum LeftBottomBarAction: Equatable {
        /// Panel open: opens PRD S-6, the management panel (TASK-26).
        case manageProfiles
        /// Panel closed: TASK-21's photo thumbnail / gallery entry (FR-15.2).
        case latestPhoto
    }

    /// What the bottom bar's right key does right now.
    enum RightBottomBarAction: Equatable {
        /// Panel open: collapses it.
        case collapse
        /// Panel closed: expands it.
        case openOverlayPanel
    }

    var leftBottomBarAction: LeftBottomBarAction {
        isOpen ? .manageProfiles : .latestPhoto
    }

    var rightBottomBarAction: RightBottomBarAction {
        isOpen ? .collapse : .openOverlayPanel
    }
}

// MARK: - Overlay drag interface (PRD 0.2 FR-12.1–FR-12.3, TASK-24)

/// Whoever owns the position tab's model (ui-panel, TASK-24) conforms to
/// this and assigns itself to `OverlayPanelModel.overlayDragHandler` while
/// its tab is showing.
///
/// This is the "接口" TASK-22 is asked to open: `CameraScreen` attaches the
/// drag gesture to the overlay text and reports through here, but never
/// clamps, normalizes or persists a position itself — that conversion (drag
/// translation → a stored `.custom(x:y:)` fraction, clamped into the 4%
/// margin) is entirely the position tab's job (PRD 0.2 FR-12.2, FR-12.6).
protocol OverlayDragHandling: AnyObject {
    /// Called continuously while the overlay text is being dragged, with the
    /// drag's translation from its start point and the viewfinder's current
    /// on-screen size (already the 80%-scaled size while the panel is open,
    /// per FR-8.2 — never the full screen size).
    func overlayDragChanged(translation: CGSize, viewfinderSize: CGSize)
    /// Called once when the drag ends, with the same two values at their
    /// final state. This is expected to be where a real handler converts,
    /// clamps and persists the new `.custom` position.
    func overlayDragEnded(translation: CGSize, viewfinderSize: CGSize)
}

extension OverlayPanelModel {
    /// Whether the overlay text should currently accept drags: only while
    /// the panel is open *and* the 位置 (position) tab is selected (PRD 0.2
    /// FR-12.1). `CameraScreen` also gates `OverlayTextView`'s
    /// `allowsHitTesting` on this, per FR-12.1's own wording.
    var isOverlayDraggable: Bool {
        isOpen && selectedTab == .position
    }
}
