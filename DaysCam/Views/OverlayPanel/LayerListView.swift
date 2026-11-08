import SwiftUI

/// The one-line summaries under the layer list's two rows (#718).
enum LayerSummary {
    /// 「<樣式名> · <勾選的內容> · <位置>」; the content part is 「無內容」 with
    /// 天數／日期／名稱 all off, the style 「自訂」 when it matches none of the
    /// ten looks.
    static func overlay(styleName: String?, showDayCount: Bool, showDate: Bool, showName: Bool,
                        positionName: String) -> String {
        let contents = [(showDayCount, "天數"), (showDate, "日期"), (showName, "名稱")]
            .filter(\.0).map(\.1)
        return [styleName ?? "自訂", contents.isEmpty ? "無內容" : contents.joined(separator: "、"), positionName]
            .joined(separator: " · ")
    }

    /// 「<角落>角」, e.g. 左下角.
    static func filmDate(corner: FilmDateCorner) -> String {
        "\(corner.displayName)角"
    }
}

/// The panel's first page (#718): what is on the photo, one row per layer —
/// 疊字 and 底片日期 — each with its own switch and a push into its settings.
/// Observes the three tab models so a drag on the preview or a change in a
/// pushed page shows in the summaries on the way back.
struct LayerListView: View {
    @ObservedObject var formatModel: FormatTabModel
    @ObservedObject var styleModel: StyleTabModel
    @ObservedObject var positionModel: PositionTabModel
    /// Pushes one layer's page.
    var onOpen: (OverlayPanelModel.Route) -> Void

    private var profile: CameraProfile { formatModel.displaySettings.profile }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                row(icon: "text.below.photo", title: "疊字",
                    summary: LayerSummary.overlay(styleName: styleModel.selectedPreset?.displayName,
                                                  showDayCount: profile.showDayCount,
                                                  showDate: profile.showDate,
                                                  showName: profile.showName,
                                                  positionName: positionModel.positionName),
                    isOn: profile.showOverlay,
                    rowIdentifier: "layerRowOverlay", toggleIdentifier: "layerToggleOverlay",
                    route: .overlay) { formatModel.displaySettings.setShowOverlay($0) }
                Rectangle().fill(CameraTheme.ink.opacity(0.1)).frame(height: 1)
                row(icon: "calendar", title: "底片日期",
                    summary: LayerSummary.filmDate(corner: profile.filmDateCorner),
                    isOn: profile.showFilmDate,
                    rowIdentifier: "layerRowFilmDate", toggleIdentifier: "layerToggleFilmDate",
                    route: .filmDate) { formatModel.displaySettings.setShowFilmDate($0) }
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("layerList")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .alert("無法儲存", isPresented: Binding(get: { formatModel.displaySettings.lastError != nil },
                                             set: { if !$0 { formatModel.displaySettings.lastError = nil } })) {
            Button("好") { formatModel.displaySettings.lastError = nil }
        } message: {
            Text("請再試一次。")
        }
    }

    /// One layer: the push (icon, name, summary) on the left, the switch and
    /// the chevron at the end. At least 44pt tall.
    private func row(icon: String, title: String, summary: String, isOn: Bool,
                     rowIdentifier: String, toggleIdentifier: String, route: OverlayPanelModel.Route,
                     setOn: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            Button { onOpen(route) } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundColor(CameraTheme.ink)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline)
                            .foregroundColor(CameraTheme.ink)
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundColor(CameraTheme.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)，\(summary)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(rowIdentifier)
            // #F0A64A, not the system default green (PRD FR-14, #114).
            Toggle(title, isOn: Binding(get: { isOn }, set: setOn))
                .tint(CameraTheme.accentControl)
                .labelsHidden()
                .accessibilityIdentifier(toggleIdentifier)
            Button { onOpen(route) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CameraTheme.inkTertiary)
                    .frame(width: 24, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }
}

/// The line on top of a layer page that is switched off (#718): why the page
/// is grey, and the one key that turns the layer on.
struct LayerHiddenNotice: View {
    var onShow: () -> Void

    /// The row's height.
    static let height: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 14))
                .foregroundColor(CameraTheme.inkSecondary)
            Text("已隱藏，設定會保留")
                .font(.system(size: 14))
                .foregroundColor(CameraTheme.inkSecondary)
            Spacer(minLength: 0)
            Button(action: onShow) {
                Text("顯示")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CameraTheme.active)
                    .padding(.horizontal, 10)
                    .frame(minHeight: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("layerShowButton")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: Self.height)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("layerHiddenNotice")
    }
}
