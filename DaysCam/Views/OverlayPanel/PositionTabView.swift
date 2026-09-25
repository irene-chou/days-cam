import SwiftUI

/// The 位置 (position) tab of the overlay panel (PRD 0.2 FR-12, D-4).
///
/// Stands alone on purpose, like the other panel tabs: the panel shell and
/// its first-layer segmented control are `ui-shell`'s (TASK-22), which had
/// not landed when this was written. Once it does, `ui-shell` drops this
/// view into the panel body for the 位置 segment.
///
/// Left: a photo-shaped light box with the nine-point quick-align grid,
/// selected point in the active color (FR-12.4). Right: only the position's
/// name — no caption text, overturning this screen's earlier `D-4` draft
/// (FR-12.4 is explicit: "不加說明文字"; PRD wins over the design note here).
/// The free-drag gesture itself lives on `CameraScreen` (`ui-shell`); this
/// view only reflects whatever `model.profile.position` currently is.
struct PositionTabView: View {
    @ObservedObject var model: PositionTabModel

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            grid
                .padding(14)
                .frame(width: 120, height: 160)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CameraTheme.fill)
                )
            Text(model.positionName)
                .font(CameraTheme.toolFont(.headline))
                .foregroundColor(CameraTheme.ink)
            Spacer(minLength: 0)
        }
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
    /// 3-column grid (FR-12.4, FR-12.5).
    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(OverlayPosition.allCases, id: \.self) { position in
                let isSelected = model.profile.position == .anchor(position)
                Button {
                    model.selectAnchor(position)
                } label: {
                    Circle()
                        .fill(isSelected ? CameraTheme.active : CameraTheme.inkTertiary)
                        .frame(width: isSelected ? 14 : 8, height: isSelected ? 14 : 8)
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel(PositionTabModel.anchorName(position))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
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
