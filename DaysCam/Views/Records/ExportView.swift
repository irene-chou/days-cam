import SwiftUI

/// The 文字樣式 page of one photo (PRD 2.0 FR-19, D8 ④): the page that used
/// to be the export page, now only styling; nothing is exported here.
///
/// Top bar `xmark`｜紀錄名 (back to where the page opened from); a preview
/// about 52% of the width at the photo's own aspect ratio, with the record's
/// overlay drawn by the same `OverlayTextView`／`FilmDateStampView` the bake
/// matches; below it the camera's 文字樣式 sheet (`StylePanelSheet`, #718),
/// always open, whose checkmark also goes back.
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
    /// Where the sheet says changes are saved (FR-19.8).
    static let note = "改動直接存到這個紀錄，回檢視頁再匯出"
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
            let tabBarHeight = CameraScreenLayoutMetrics.defaultPanelTabBarHeight
            let sheetChrome = StylePanelSheet<ExportModel>.chromeHeight(tabBarHeight: tabBarHeight)
            let room = proxy.size.height - Self.headerHeight - previewSize.height
                - Self.previewTopPadding - Self.previewBottomPadding - sheetChrome
            let contentHeight = max(0, min(room, Self.maxPanelContentHeight))
            VStack(spacing: 0) {
                header
                // Space the sheet does not need goes around the preview, so
                // the panel keeps the camera's height (the 樣式 tab centers
                // its pages in it).
                preview(size: previewSize)
                    .padding(.top, Self.previewTopPadding)
                    .padding(.bottom, Self.previewBottomPadding)
                    .frame(maxHeight: .infinity)
                StylePanelSheet(model: model,
                                contentHeight: contentHeight,
                                tabBarHeight: tabBarHeight,
                                note: Self.note,
                                onDone: { dismiss() })
                    .frame(height: contentHeight + sheetChrome)
            }
        }
        .background(CameraTheme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exportView")
        .preferredColorScheme(.light)
        .task(id: displayScale) {
            let side = UIScreen.main.bounds.width * Self.previewWidthRatio * displayScale * 2
            previewImage = await model.previewImage(targetSize: CGSize(width: side, height: side))
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

    /// `xmark` and the record's name; 文字樣式 and the checkmark are the
    /// sheet's (#718).
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
        }
        // The name stays centered, clear of the key, and never takes its taps.
        .overlay {
            Text(model.subtitle)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundColor(CameraTheme.inkSecondary)
                .lineLimit(1)
                .padding(.horizontal, PanelBackButton.reservedWidth)
                .allowsHitTesting(false)
                .accessibilityIdentifier("exportSubtitle")
        }
        .padding(.horizontal, 8)
        .frame(height: Self.headerHeight)
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
}
