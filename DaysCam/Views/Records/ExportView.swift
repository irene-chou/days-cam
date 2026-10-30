import SwiftUI

/// The export page of one photo (PRD 2.0 FR-19, D-7 screen 4).
///
/// Top bar `xmark`｜匯出 + 第 N 天｜`checkmark`; a preview about 52% of the
/// width at the photo's own aspect ratio, with the record's overlay drawn by
/// the same `OverlayTextView`／`FilmDateStampView` the bake matches; the
/// overlay panel (樣式｜內容) below it, always open; one line at the bottom.
/// The output-form switch (疊字／拍立得) is not drawn in the first phase: there
/// is only one form (§2.4).
struct ExportView: View {
    @StateObject private var model: ExportModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var previewImage: UIImage?

    /// The preview's share of the screen width (FR-19.2).
    static let previewWidthRatio: CGFloat = 0.52
    /// The preview never takes more than this share of the height, so a tall
    /// photo leaves the panel room.
    static let previewMaxHeightRatio: CGFloat = 0.42
    /// The panel's usable height on a large phone's camera screen (268 less
    /// the top padding); taller tab content scrolls, as it does there.
    static let maxPanelContentHeight: CGFloat = 260
    static let headerHeight: CGFloat = 44
    static let noteHeight: CGFloat = 34
    /// Space above and below the preview (`.pv{padding:4px 0 6px}`).
    static let previewTopPadding: CGFloat = 4
    static let previewBottomPadding: CGFloat = 6

    /// `model` is built once, when the page first appears.
    init(model: @autoclosure @escaping () -> ExportModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        GeometryReader { proxy in
            let previewSize = Self.previewSize(in: proxy.size, imageSize: previewImage?.size)
            let panelChrome = CameraScreenLayoutMetrics.panelTopPadding + CameraScreenLayoutMetrics.defaultPanelTabBarHeight
            let room = proxy.size.height - Self.headerHeight - previewSize.height
                - Self.previewTopPadding - Self.previewBottomPadding - Self.noteHeight
            let contentHeight = max(0, min(room - panelChrome, Self.maxPanelContentHeight))
            VStack(spacing: 0) {
                header
                // Space the panel does not need goes around the preview, so
                // the panel keeps the camera's height (the 樣式 tab centers
                // its pages in it).
                preview(size: previewSize)
                    .padding(.top, Self.previewTopPadding)
                    .padding(.bottom, Self.previewBottomPadding)
                    .frame(maxHeight: .infinity)
                OverlayPanelView(model: model,
                                 contentHeight: contentHeight,
                                 tabBarHeight: CameraScreenLayoutMetrics.defaultPanelTabBarHeight,
                                 bottomSafeAreaInset: 0,
                                 showsCollapseButton: false)
                    .frame(height: contentHeight + panelChrome)
                    // Nothing changes while exporting (FR-19.7).
                    .disabled(!model.isEditable)
                note
            }
        }
        .background(CameraTheme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { toastOverlay }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exportView")
        .preferredColorScheme(.light)
        .task(id: displayScale) {
            let side = UIScreen.main.bounds.width * Self.previewWidthRatio * displayScale * 2
            previewImage = await model.previewImage(targetSize: CGSize(width: side, height: side))
        }
        .onChange(of: model.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .alert("無法匯出", isPresented: errorBinding, presenting: model.exportError) { error in
            if error.showsSettingsAction {
                Button("前往設定") {
                    model.dismissError()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Button("好", role: .cancel) { model.dismissError() }
        } message: { error in
            Text(error.message)
        }
    }

    /// The preview's size: 52% of the width at the image's aspect ratio
    /// (3:4 until it loads), shrunk to fit `previewMaxHeightRatio`.
    static func previewSize(in container: CGSize, imageSize: CGSize?) -> CGSize {
        let aspect: CGFloat
        if let imageSize, imageSize.width > 0, imageSize.height > 0 {
            aspect = imageSize.width / imageSize.height
        } else {
            aspect = 3.0 / 4.0
        }
        var width = container.width * previewWidthRatio
        var height = width / aspect
        let maxHeight = container.height * previewMaxHeightRatio
        if height > maxHeight, maxHeight > 0 {
            height = maxHeight
            width = height * aspect
        }
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    // MARK: - Header (FR-19.1)

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(CameraTheme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消")
            .accessibilityIdentifier("exportCancelButton")
            Spacer()
            VStack(spacing: 1) {
                Text("匯出")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(CameraTheme.ink)
                Text(model.dayTitle)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundColor(CameraTheme.inkTertiary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("exportTitle")
            Spacer()
            confirmButton
        }
        .padding(.horizontal, 8)
        .frame(height: Self.headerHeight)
    }

    /// The checkmark; a spinner with the download progress while exporting
    /// (FR-19.7).
    private var confirmButton: some View {
        Button {
            Task { await model.export() }
        } label: {
            ZStack {
                if model.isExporting {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.circular)
                        .tint(CameraTheme.active)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(model.canExport ? CameraTheme.active : CameraTheme.inkTertiary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canExport)
        .accessibilityLabel(model.isExporting ? "匯出中" : "完成")
        .accessibilityIdentifier("exportConfirmButton")
    }

    // MARK: - Preview (FR-19.2, FR-19.3)

    /// The photo with the overlay drawn live, so a panel change shows at once
    /// and the text can be dragged here (FR-19.3).
    private func preview(size: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.8)
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
            if let profile = model.profile, let text = model.overlayText {
                OverlayTextView(text: text,
                                style: profile.style,
                                placement: profile.position,
                                frameSize: size,
                                font: model.overlayFont,
                                onDragChanged: model.isOverlayDraggable ? { center, frameSize in
                                    model.overlayDragChanged(center: center, frameSize: frameSize)
                                } : nil,
                                onDragEnded: model.isOverlayDraggable ? { center, frameSize in
                                    model.overlayDragEnded(center: center, frameSize: frameSize)
                                } : nil,
                                dragHintSerial: model.panelModel.dragHintSerial)
                FilmDateStampView(stamp: model.filmDateStamp, frameSize: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exportPreview")
    }

    // MARK: - Bottom (FR-19.8, FR-19.6)

    private var note: some View {
        Text("存成新照片到「最近項目」，原圖不動")
            .font(.system(size: 11.5))
            .foregroundColor(CameraTheme.inkTertiary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: Self.noteHeight)
            .accessibilityIdentifier("exportNote")
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toastState = model.toastState {
            ToastView(state: toastState)
                .padding(.bottom, 90)
                .transition(.opacity)
                .animation(.easeInOut, value: toastState.id)
                .accessibilityIdentifier("exportToast")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.exportError != nil }, set: { if !$0 { model.dismissError() } })
    }
}
