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

    /// Creates a position tab model for `profile`.
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

    /// Upper bound for the nine-point grid box's side: 132pt, matching
    /// #108's own acceptance table (P.3: "在 96～132 之間").
    ///
    /// The ticket's rationale for 132 is "每格 44pt,剛好達到 iOS 點擊範圍"
    /// (`132 / 3`), but that arithmetic does not account for
    /// `PositionTabView`'s own 4pt inner padding on each side of the grid
    /// (`.pgrid`'s `padding:4px`, #108 goal 5): the actual 3×3 grid area at
    /// this max is `(132 - 4*2) / 3` ≈ 41.3pt per cell, not exactly 44pt.
    /// Kept at 132 rather than raised to 140 (the value that *would* yield
    /// an exact 44pt after that padding) since 132 is P.3's own explicit
    /// upper bound, not something this file should silently change —
    /// flagged to Lead/human instead (bot review on #111, 2026-09-28).
    static let gridBoxMaxSide: CGFloat = 132

    /// Vertical clearance the box's side is derived to leave above and below
    /// itself within the panel's tab-content scroll viewport, matching
    /// `.tabbody`'s own top/bottom padding (`D4-format-position-rules.html`,
    /// `.tabbody{padding:12px 14px}`) so the box never claims more height
    /// than that padding leaves it (#108).
    static let gridBoxVerticalInset: CGFloat = 12

    /// The square nine-point grid box's side, derived from `availableHeight`
    /// — the panel's tab-content scroll viewport height — instead of a fixed
    /// constant (FR-12.4, #108).
    ///
    /// Capped at `gridBoxMaxSide`. Deliberately has no hard floor: per the
    /// human's 2026-09-27 call (#108's "假設 1"), a genuinely short viewport
    /// (e.g. iPhone SE) shrinks the box further rather than clipping it, even
    /// below the 96pt the ticket otherwise names as a target minimum.
    ///
    /// `availableHeight` being non-finite (`.infinity`, `PositionTabView`'s
    /// "not measured yet" default before `ui-shell` wires up real
    /// measurement — see that view's doc comment) resolves to the max, so
    /// every caller renders sensibly before that lands.
    static func gridBoxSide(forAvailableHeight availableHeight: CGFloat) -> CGFloat {
        guard availableHeight.isFinite else { return gridBoxMaxSide }
        let side = availableHeight - gridBoxVerticalInset * 2
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
