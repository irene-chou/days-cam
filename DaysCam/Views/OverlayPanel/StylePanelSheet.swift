import SwiftUI

/// The 文字樣式 sheet from the bottom (#718 option A): its title row (‹ on a
/// layer's page, the checkmark), the layer panel flat on the sheet's one
/// surface, and on the layer list a line saying where changes are saved.
/// The camera and a photo's style page both show it; the host sizes and
/// places it.
struct StylePanelSheet<Host: OverlayPanelHosting>: View {
    @ObservedObject private var model: Host
    @ObservedObject private var panelModel: OverlayPanelModel
    private let contentHeight: CGFloat
    private let tabBarHeight: CGFloat
    private let note: String
    private let onDone: () -> Void

    /// `contentHeight` is the panel's on the layer list; a layer's page also
    /// takes the note's row. `note` says where changes are saved; `onDone`
    /// is the checkmark.
    init(model: Host, contentHeight: CGFloat, tabBarHeight: CGFloat, note: String, onDone: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        _panelModel = ObservedObject(wrappedValue: model.panelModel)
        self.contentHeight = contentHeight
        self.tabBarHeight = tabBarHeight
        self.note = note
        self.onDone = onDone
    }

    /// The sheet's rows other than the panel's content: the title row, the
    /// panel's top padding and segmented row, and the note.
    static func chromeHeight(tabBarHeight: CGFloat) -> CGFloat {
        CameraScreenLayoutMetrics.styleSheetHeaderHeight + CameraScreenLayoutMetrics.panelTopPadding
            + tabBarHeight + CameraScreenLayoutMetrics.styleSheetNoteHeight
    }

    var body: some View {
        let chrome = CameraScreenLayoutMetrics.panelTopPadding + tabBarHeight
        // The note is the layer list's foot only; a layer's page takes its
        // room (#718 option A ②③).
        let showsNote = panelModel.route == .root
        let panelContentHeight = contentHeight + (showsNote ? 0 : CameraScreenLayoutMetrics.styleSheetNoteHeight)
        VStack(spacing: 0) {
            header
                .background(CameraTheme.background)
                .zIndex(1)
            OverlayPanelView(model: model,
                             contentHeight: panelContentHeight,
                             tabBarHeight: tabBarHeight,
                             bottomSafeAreaInset: 0,
                             showsCollapseButton: false,
                             drawsSurface: false)
                .frame(height: panelContentHeight + chrome)
            if showsNote {
                noteRow
            }
            Spacer(minLength: 0)
        }
        .background(surface.ignoresSafeArea(edges: .bottom))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stylePanel")
    }

    private var header: some View {
        ZStack {
            Text(panelModel.route.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(CameraTheme.ink)
                .lineLimit(1)
                .padding(.horizontal, PanelBackButton.reservedWidth)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("stylePanelTitle")
            HStack {
                // A pushed layer page goes back to the layer list (#718).
                if panelModel.route != .root {
                    PanelBackButton { panelModel.goBack() }
                }
                Spacer()
                Button(action: onDone) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(CameraTheme.active)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("完成")
                .accessibilityIdentifier("stylePanelDoneButton")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: CameraScreenLayoutMetrics.styleSheetHeaderHeight)
    }

    private var noteRow: some View {
        Text(note)
            .font(.system(size: 11.5))
            .foregroundColor(CameraTheme.inkTertiary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: CameraScreenLayoutMetrics.styleSheetNoteHeight)
            .accessibilityIdentifier("stylePanelNote")
    }

    /// The camera background, top corners rounded, a soft shadow along the
    /// top edge.
    private var surface: some View {
        let radius = CameraScreenLayoutMetrics.panelTopCornerRadius
        return UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: 0,
                                      bottomTrailingRadius: 0, topTrailingRadius: radius, style: .continuous)
            .fill(CameraTheme.background)
            .shadow(color: CameraTheme.popoverShadow, radius: CameraScreenLayoutMetrics.panelShadowRadius,
                    x: 0, y: CameraScreenLayoutMetrics.panelShadowYOffset)
    }
}
