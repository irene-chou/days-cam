import SwiftUI

/// The nine-point quick-align grid in its light square box (PRD 0.2 FR-12.4),
/// selected point in the active color.
///
/// Used by the 位置 row on the 版面 tab (#567, #568), reads the VoiceOver labels
/// and writes through `PositionTabModel.selectAnchor`.
struct PositionGridView: View {
    @ObservedObject var model: PositionTabModel
    /// The box's side. The 位置 row fixes it.
    let side: CGFloat

    var body: some View {
        grid
            .padding(4)
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CameraTheme.fill)
            )
    }

    /// The nine points, in `OverlayPosition.allCases`' order — top row then
    /// middle row then bottom row, which is exactly row-major order for a
    /// 3-column grid (FR-12.4, FR-12.5). No inter-cell spacing: the box's
    /// area is split evenly into nine equal cells (`D4-format-position-rules.html`'s
    /// `.pgrid`, #108 goal 5), each fully tappable via `contentShape` rather
    /// than only its visible dot (#108 goal 4, P.4).
    ///
    /// A plain `VStack` of `HStack` rows, not `LazyVGrid` — confirmed
    /// empirically (#108, real-device QA report + a `UIHostingController`
    /// regression test, `PositionGridViewFillTests`) that `LazyVGrid`
    /// reliably stretches its *columns* to fill an imposed width but does
    /// **not** stretch its *rows* to fill an imposed height, even when every
    /// cell declares `.frame(maxHeight: .infinity)`: each row instead
    /// collapses to its content's tiny intrinsic height (the dots ended up
    /// clustered in roughly a quarter of the box, in real testing), leaving
    /// blank space in whatever remained of the box. Plain `VStack`/
    /// `HStack` reliably divides an imposed size evenly among flexible
    /// children — the ordinary, well-established behavior `LazyVGrid`
    /// (designed for large/scrolling collections, not a fixed 3×3 layout)
    /// turned out not to share here.
    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { column in
                        gridCell(OverlayPosition.allCases[row * 3 + column])
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func gridCell(_ position: OverlayPosition) -> some View {
        let isSelected = model.profile.position == .anchor(position)
        return Button {
            model.selectAnchor(position)
        } label: {
            Circle()
                .fill(isSelected ? CameraTheme.active : CameraTheme.inkTertiary)
                .frame(width: isSelected ? 14 : 7, height: isSelected ? 14 : 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(PositionTabModel.anchorName(position))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
