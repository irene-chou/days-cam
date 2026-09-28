import SwiftUI

/// The 位置 (position) tab of the overlay panel (PRD 0.2 FR-12, D-4).
///
/// Stands alone on purpose, like the other panel tabs: the panel shell and
/// its first-layer segmented control are `ui-shell`'s (TASK-22), which had
/// not landed when this was written. Once it does, `ui-shell` drops this
/// view into the panel body for the 位置 segment.
///
/// Left: a square, fixed-1:1 light box with the nine-point quick-align grid
/// (overturning this file's own earlier 3:4 "photo-shaped" box — #108, the
/// human's 2026-09-27 call: the box is a quick-align control, not a photo
/// preview, so it does not follow the capture aspect ratio), selected point
/// in the active color (FR-12.4). Right: only the position's name — no
/// caption text, overturning this screen's earlier `D-4` draft (FR-12.4 is
/// explicit: "不加說明文字"; PRD wins over the design note here). The two
/// together are centered as one group within the tab's content width
/// (`D4-format-position-rules.html`'s `.posw`), so the box shifts left/right
/// with the name's length while the group's own center never moves (#108
/// P.1, P.5). The free-drag gesture itself lives on `CameraScreen`
/// (`ui-shell`); this view only reflects whatever `model.profile.position`
/// currently is.
struct PositionTabView: View {
    @ObservedObject var model: PositionTabModel

    /// The panel's tab-content scroll viewport height, as measured by
    /// `OverlayPanelView` (`ui-shell`) via a `GeometryReader` on its
    /// `ScrollView` and threaded down through this parameter — this view
    /// cannot measure it itself: a `GeometryReader` placed anywhere inside
    /// that `ScrollView`'s content (i.e. inside this view, however it is
    /// wrapped) is proposed an unbounded height and reports an arbitrary,
    /// not-actually-representative size instead (confirmed empirically for
    /// #108 with a `UIHostingController` test), so only something *outside*
    /// the `ScrollView` can read its real viewport height.
    ///
    /// `.infinity` — the default, and what every `#Preview` below uses — is
    /// the "not measured yet" sentinel `PositionTabModel.gridBoxSide`
    /// resolves to its max, so this view renders sensibly on its own before
    /// `ui-shell` wires the real measurement through (flagged to them, #108).
    var availableHeight: CGFloat = .infinity

    /// The square grid box's side, derived from `availableHeight` rather
    /// than fixed (#108 P.2, P.3).
    private var gridBoxSide: CGFloat {
        PositionTabModel.gridBoxSide(forAvailableHeight: availableHeight)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            grid
                .padding(4)
                .frame(width: gridBoxSide, height: gridBoxSide)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CameraTheme.fill)
                )
            Text(model.positionName)
                .font(CameraTheme.toolFont(.headline))
                .foregroundColor(CameraTheme.ink)
        }
        // Centers the box+name group as one unit within the full content
        // width (#108 P.1) rather than pinning it to the leading edge with a
        // trailing `Spacer` the way this view did before.
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .alert("無法儲存", isPresented: Binding(get: { model.lastError != nil },
                                             set: { if !$0 { model.lastError = nil } })) {
            Button("好") { model.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
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
    /// regression test, `PositionTabViewGridFillTests`) that `LazyVGrid`
    /// reliably stretches its *columns* to fill an imposed width but does
    /// **not** stretch its *rows* to fill an imposed height, even when every
    /// cell declares `.frame(maxHeight: .infinity)`: each row instead
    /// collapses to its content's tiny intrinsic height (the dots ended up
    /// clustered in roughly a quarter of the box, in real testing), leaving
    /// blank space in whatever remained of `gridBoxSide`. Plain `VStack`/
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

// MARK: - Preview

private func previewProfile(position: OverlayPlacement = .anchor(.bottomTrailing)) -> CameraProfile {
    CameraProfile(name: "小寶",
                 startDate: DateComponents(year: 2026, month: 1, day: 1),
                 position: position)
}

@MainActor
private func previewModel(position: OverlayPlacement = .anchor(.bottomTrailing)) -> PositionTabModel {
    PositionTabModel(profile: previewProfile(position: position)) { _ in }
}

#Preview("九宮格：右下（預設） · iPhone SE 寬度 (375pt)") {
    PositionTabView(model: previewModel())
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("九宮格：左上") {
    PositionTabView(model: previewModel(position: .anchor(.topLeading)))
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("自訂位置（拖曳後）") {
    PositionTabView(model: previewModel(position: .custom(x: 0.5, y: 0.5)))
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}

#Preview("可用高度受限（模擬 SE 上小框收縮，#108 假設 1）") {
    PositionTabView(model: previewModel(), availableHeight: 80)
        .frame(width: 375)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
}
