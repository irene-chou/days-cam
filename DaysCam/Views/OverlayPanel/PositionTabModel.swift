import CoreGraphics
import Foundation

/// Drives the overlay panel's 位置 (position) tab: the nine-point quick-align
/// grid and the free-drag "custom position" (PRD 0.2 FR-12).
///
/// Follows `StyleTabModel`/`RulesTabModel`'s shape: a working copy of one
/// `CameraProfile` plus an injected `updateProfile` closure, so it is
/// constructible and unit-testable without a real `ProfileStore` or panel
/// shell.
///
/// The actual drag gesture and `allowsHitTesting` toggle live on
/// `CameraScreen` — `ui-shell`'s territory (TASK-22) — which has not landed
/// yet as this was written. This model only owns the *conversion*: turning a
/// reported drag center and viewfinder size into the `.custom(x, y)` fraction
/// PRD FR-12.3 stores (`customPosition(forDragCenter:viewfinderSize:)`), so
/// that conversion is fully covered by unit tests (24.8, 24.9) ahead of the
/// gesture being wired up.
@MainActor
final class PositionTabModel: ObservableObject {
    /// The profile as currently configured. Read-only from outside: every
    /// change goes through one of this model's setters so it is always
    /// persisted (FR-8.6).
    @Published private(set) var profile: CameraProfile
    /// The most recent `updateProfile` failure, if any, for the view to surface.
    @Published var lastError: Error?

    private let updateProfile: (CameraProfile) throws -> Void

    /// Creates a position model for `profile`.
    ///
    /// - Parameter updateProfile: Forwarded to the real persistence layer by
    ///   the caller, called after every change. Throws to report a failure;
    ///   this model does not interpret the error, it only surfaces it.
    init(profile: CameraProfile,
         updateProfile: @escaping (CameraProfile) throws -> Void) {
        self.profile = profile
        self.updateProfile = updateProfile
    }

    private func mutate(_ change: (inout CameraProfile) -> Void) {
        change(&profile)
        do {
            try updateProfile(profile)
        } catch {
            lastError = error
        }
    }
}

// MARK: - 九宮格快速對齊 (FR-12.4, FR-12.5)

extension PositionTabModel {
    /// Selects one of the nine anchor points and persists (FR-12.5).
    func selectAnchor(_ position: OverlayPosition) {
        let newPlacement = OverlayPlacement.anchor(position)
        guard newPlacement != profile.position else { return }
        mutate { $0.position = newPlacement }
    }

    /// The name shown next to the grid: one of the nine anchor names, or
    /// "自訂位置" once a drag has set a `.custom` position (FR-12.4).
    var positionName: String {
        switch profile.position {
        case let .anchor(position):
            return Self.anchorName(position)
        case .custom:
            return "自訂位置"
        }
    }

    /// Chinese name for one of the nine anchors, matching the naming already
    /// established for the 0.1 position picker (`DisplaySettingsSheet`).
    static func anchorName(_ position: OverlayPosition) -> String {
        switch position {
        case .topLeading: return "左上"
        case .topCenter: return "中上"
        case .topTrailing: return "右上"
        case .middleLeading: return "左中"
        case .middleCenter: return "正中"
        case .middleTrailing: return "右中"
        case .bottomLeading: return "左下"
        case .bottomCenter: return "中下"
        case .bottomTrailing: return "右下"
        }
    }

    /// Hint shown under the position name (#140; copy from design D-4).
    static let dragHintMessage = "直接在觀景窗上拖曳疊字，或點左邊快速對齊"

    /// Upper bound for the nine-point grid box's side: 96pt (human's
    /// 2026-09-30 call, #126). The nine-point grid must not scroll inside the
    /// fixed-height panel (#120/#128), and 96pt fits the regular 120pt
    /// content area with `gridBoxRegularInset` above and below.
    static let gridBoxMaxSide: CGFloat = 96

    /// Vertical clearance above and below the box when the content area is
    /// at least `gridBoxRegularHeight` tall.
    static let gridBoxRegularInset: CGFloat = 12

    /// Tighter clearance used on short content areas (iPhone SE's 104pt), so
    /// the box stays at 88pt rather than 80pt (#126).
    static let gridBoxCompactInset: CGFloat = 8

    /// Content height from which `gridBoxRegularInset` applies.
    static let gridBoxRegularHeight: CGFloat = 120

    /// Vertical clearance the box leaves above and below itself: 12pt when
    /// `availableHeight` is at least 120pt (or not measured yet), else 8pt.
    /// The old position page padded with this same value, so the box side and the
    /// padding can never disagree.
    static func gridBoxVerticalInset(forAvailableHeight availableHeight: CGFloat) -> CGFloat {
        guard availableHeight.isFinite else { return gridBoxRegularInset }
        return availableHeight >= gridBoxRegularHeight ? gridBoxRegularInset : gridBoxCompactInset
    }

    /// The square nine-point grid box's side, derived from `availableHeight`
    /// — the panel's tab-content scroll viewport height — instead of a fixed
    /// constant (FR-12.4, #108).
    ///
    /// Capped at `gridBoxMaxSide`. Deliberately has no hard floor: a
    /// genuinely short viewport shrinks the box rather than clipping it
    /// (#108's "假設 1"). Expected values: 120 -> 96, 104 -> 88.
    ///
    /// `availableHeight` being non-finite (`.infinity`, the old position page's
    /// "not measured yet" default before `ui-shell` wires up real
    /// measurement — see that view's doc comment) resolves to the max, so
    /// every caller renders sensibly before that lands.
    static func gridBoxSide(forAvailableHeight availableHeight: CGFloat) -> CGFloat {
        guard availableHeight.isFinite else { return gridBoxMaxSide }
        let side = availableHeight - gridBoxVerticalInset(forAvailableHeight: availableHeight) * 2
        return max(0, min(side, gridBoxMaxSide))
    }
}

// MARK: - 觀景窗拖曳換算 (FR-12.1–FR-12.3, FR-12.6)

extension PositionTabModel {
    /// Converts a drag's reported center point (in the viewfinder's own point
    /// space, already shrunk to the panel-open 80% size) into the `.custom`
    /// fraction PRD FR-12.3 stores, and applies it (FR-12.2, FR-12.3).
    ///
    /// A pure function (`customPosition(forDragCenter:viewfinderSize:)`) does
    /// the actual math so it can be unit-tested (24.8, 24.9) independently of
    /// `ui-shell`'s drag gesture, which had not landed when this was written.
    func applyDrag(center: CGPoint, viewfinderSize: CGSize) {
        let (x, y) = Self.customPosition(forDragCenter: center, viewfinderSize: viewfinderSize)
        mutate { $0.position = .custom(x: x, y: y) }
    }

    /// Fraction of the short edge kept clear on every side, matching the
    /// render layer's own margin (`OverlayMetrics.marginRatio`, PRD FR-4.3) —
    /// kept in sync with that constant rather than restated, since both
    /// exist to enforce the same 4% margin (FR-12.2).
    static var marginRatio: Double { Double(OverlayMetrics.marginRatio) }

    /// Converts a drag center point into the `.custom(x, y)` fraction stored
    /// for it, clamping each axis to `marginRatio...(1 - marginRatio)` so a
    /// drag released outside the viewfinder (or right at its edge) never
    /// stores a position whose overlay would already start outside the 4%
    /// margin (FR-12.2, 24.9). A point inside the margin band converts
    /// straight through with no adjustment (24.8).
    ///
    /// `viewfinderSize` is the viewfinder's actual on-screen size while the
    /// panel is open — already shrunk to 80% (FR-8.2) — not the full-screen
    /// size, so the same drag position always yields the same stored
    /// fraction regardless of when in the interaction it is read.
    static func customPosition(forDragCenter point: CGPoint, viewfinderSize: CGSize) -> (x: Double, y: Double) {
        guard viewfinderSize.width > 0, viewfinderSize.height > 0 else { return (0.5, 0.5) }
        let x = Double(point.x / viewfinderSize.width)
        let y = Double(point.y / viewfinderSize.height)
        return (x: clampToMarginBand(x), y: clampToMarginBand(y))
    }

    private static func clampToMarginBand(_ value: Double) -> Double {
        min(max(value, marginRatio), 1 - marginRatio)
    }
}
