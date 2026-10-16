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
/// in the active color (FR-12.4). Right: the position's name with a one-line
/// hint below it (`PositionTabModel.dragHintMessage`, up to two lines) that
/// says the overlay can also be dragged on the viewfinder (#140, the
/// human's 2026-09-30 call, reversing FR-12.4's earlier "不加說明文字"; the
/// ticket wins over that old PRD text). The two
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

    /// Top/bottom clearance around the box, from the same rule as its side.
    private var gridBoxVerticalInset: CGFloat {
        PositionTabModel.gridBoxVerticalInset(forAvailableHeight: availableHeight)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            PositionGridView(model: model, side: gridBoxSide)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.positionName)
                    .font(CameraTheme.toolFont(.headline))
                    .foregroundColor(CameraTheme.ink)
                // Always shown, even after the user has dragged once (#140).
                Text(PositionTabModel.dragHintMessage)
                    .font(.caption)
                    .foregroundColor(CameraTheme.inkSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    // Wraps within the width left beside the box instead of
                    // being clipped to one line.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Centers the box+name group as one unit within the full content
        // width (#108 P.1) rather than pinning it to the leading edge with a
        // trailing `Spacer` the way this view did before.
        .frame(maxWidth: .infinity)
        // This tab's own `.tabbody` outer inset — the generic D-4 value
        // (`.tabbody{padding:12px 14px}`, #106 R2, the human's 2026-09-27
        // call: each tab owns its own `.tabbody` padding rather than a
        // generic one shared by all four — `ui-shell` is dropping the panel
        // container's own generic inset in #105 to avoid stacking both).
        // Was a flat `.padding(.horizontal, 16)` with no vertical inset.
        .padding(.vertical, gridBoxVerticalInset)
        .padding(.horizontal, 14)
        // Centers the whole group vertically within the content area
        // (TASK-54), like the style tab's short pages; the inset above stays
        // as the minimum clearance when the area is short.
        .frame(maxWidth: .infinity,
               minHeight: availableHeight.isFinite ? availableHeight : nil,
               alignment: .center)
        .alert("無法儲存", isPresented: Binding(get: { model.lastError != nil },
                                             set: { if !$0 { model.lastError = nil } })) {
            Button("好") { model.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
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

#Preview("提示文字 · iPhone SE（內容區 104pt）") {
    PositionTabView(model: previewModel(position: .custom(x: 0.5, y: 0.5)), availableHeight: 104)
        .frame(width: 375, height: 104)
        .background(CameraTheme.background)
}
