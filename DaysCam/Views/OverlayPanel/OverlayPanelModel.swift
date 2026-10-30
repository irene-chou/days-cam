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
    /// The panel's first-level tabs (#584: 樣式｜內容, renamed from #568's name), in display order.
    /// 內容 is what gets printed, how it is written and where it goes: the
    /// display switches, the 位置 row, day-count units and the film date.
    enum Tab: CaseIterable, Equatable, Hashable {
        case style, content

        /// The segmented control's label (PRD 0.2 FR-8.4).
        var title: String {
            switch self {
            case .style: return "樣式"
            case .content: return "內容"
            }
        }
    }

    /// Whether the panel is expanded (PRD 0.2 FR-8.1).
    @Published private(set) var isOpen = false
    /// Which tab is selected. Starts at `.style`; once changed, keeps its
    /// value across `close()`/`open()` for the rest of this launch (A-4).
    @Published var selectedTab: Tab = .style

    /// Bumps each time the panel goes from closed to open, so the viewfinder's
    /// overlay text flashes its dashed frame once as a drag hint (#599).
    /// Re-opening while open, closing and switching tabs never bump it.
    @Published private(set) var dragHintSerial = 0

    /// The position model's drag adapter (`CameraScreenModel` assigns it).
    /// `nil` until then, so the overlay is simply not draggable yet — see
    /// `CameraScreen`'s use of this alongside `isOverlayDraggable`.
    weak var overlayDragHandler: OverlayDragHandling?

    init() {}

    /// Expands the panel (PRD 0.2 FR-8.1).
    func open() {
        if !isOpen { dragHintSerial += 1 }
        isOpen = true
    }

    /// Collapses the panel — the grabber at its top edge (tap or pull down,
    /// TASK-92; it replaced the footer's "收起" key), or tapping the
    /// viewfinder outside the overlay text while open (PRD 0.2 FR-8.3,
    /// FR-8.7). Does not reset `selectedTab` (acceptance 22.2).
    func close() {
        isOpen = false
    }
}

// MARK: - Overlay drag interface (PRD 0.2 FR-12.1–FR-12.3, TASK-24)

/// Whoever owns the position model (ui-panel, TASK-24) conforms to this and
/// assigns itself to `OverlayPanelModel.overlayDragHandler`.
///
/// This is the "接口" TASK-22 is asked to open: `CameraScreen` attaches the
/// drag gesture to the overlay text and reports through here, but never
/// persists a position itself — writing the new `.custom(x:y:)` fraction is
/// entirely the position model's job (PRD 0.2 FR-12.3).
///
/// `center` is already clamped into the 4% margin by `OverlayTextView`
/// itself (#68, PRD FR-12.2) — the same `blockSize`-aware clamp a settled
/// `.custom` position gets from `OverlayMetrics.origin` — so a conformer
/// here never needs to reapply that margin logic; it only needs to convert
/// `center` into a stored fraction (`PositionTabModel.applyDrag`).
protocol OverlayDragHandling: AnyObject {
    /// Called continuously while the overlay text is being dragged, with the
    /// block's current on-screen center and the viewfinder's current
    /// on-screen size (already the 80%-scaled size while the panel is open,
    /// per FR-8.2 — never the full screen size).
    func overlayDragChanged(center: CGPoint, viewfinderSize: CGSize)
    /// Called once when the drag ends, with the same two values at their
    /// final state. This is expected to be where a real handler persists the
    /// new `.custom` position.
    func overlayDragEnded(center: CGPoint, viewfinderSize: CGSize)
}

extension OverlayPanelModel {
    /// Whether the overlay text should currently accept drags: whenever the
    /// panel is open, on either tab (#568; it used to be the 位置 tab only,
    /// PRD 0.2 FR-12.1). `CameraScreen` also gates `OverlayTextView`'s
    /// `allowsHitTesting` on this.
    var isOverlayDraggable: Bool {
        isOpen
    }
}

// MARK: - Panel host (#620)

/// What `OverlayPanelView` reads its state from: the shell state and the
/// tab models of the record being edited. `CameraScreenModel` hosts the panel
/// for the selected profile (until #621); `ExportModel` hosts it for the
/// record being exported (PRD 2.0 FR-19.3). Both build their tab models with
/// `ProfileStyleEditor`, so the panel behaves the same in either place.
///
/// A host forwards `panelModel`'s changes to its own `objectWillChange`, so
/// a view observing only the host redraws when the tab or open state changes.
@MainActor
protocol OverlayPanelHosting: ObservableObject {
    /// Open state and selected tab.
    var panelModel: OverlayPanelModel { get }
    /// The 樣式 tab's model; `nil` until a profile is there to edit.
    var styleTabModel: StyleTabModel? { get }
    /// The 內容 tab's model; `nil` until a profile is there to edit.
    var formatTabModel: FormatTabModel? { get }
    /// The 位置 row's model; `nil` until a profile is there to edit.
    var positionTabModel: PositionTabModel? { get }
}
