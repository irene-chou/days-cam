import SwiftUI

/// The comparison sheet (#725, #740, D-11 §3): the preview with its photos
/// side by side or stacked, each a button that swaps its photo, the hint line,
/// the export panel's text options, then 匯出／取消.
struct ComparisonSheet: View {
    @ObservedObject var model: ComparisonModel
    let library: any RecordAlbumLibrary
    /// The 文字樣式 page for a photo (FR-19), opened from 調整文字樣式.
    let makeExportModel: (RecordPhoto) -> ExportModel

    @State private var pickingSide: ComparisonModel.Side?
    @State private var stylingPhoto: RecordPhoto?

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $pickingSide) { side in
                    ComparisonPhotoPicker(model: model, side: side, library: library) {
                        pickingSide = nil
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(!model.canDismiss)
        .preferredColorScheme(.light)
        .fullScreenCover(item: $stylingPhoto) { photo in
            ExportView(model: makeExportModel(photo))
        }
        .alert("無法匯出", isPresented: errorBinding, presenting: model.exportError) { error in
            if error.showsSettingsAction {
                Button("前往設定") { model.openPhotoSettings() }
            }
            Button("好", role: .cancel) { model.exportError = nil }
        } message: { error in
            Text(error.message)
        }
    }

    private var content: some View {
        VStack(spacing: 10) {
            Text("對比圖")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(CameraTheme.ink)
                .accessibilityAddTraits(.isHeader)
            preview
            Text("點任一張可換成牆上別的照片 · 天數字樣用這本相簿的文字樣式")
                .font(.system(size: 11.5))
                .foregroundColor(CameraTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ExportTextOptions(hidesText: model.hidesText, recordHidesText: model.recordHidesText,
                              hidesTextChoice: model.hidesTextChoice,
                              hideIdentifier: "comparisonHideTextButton", styleIdentifier: "comparisonStyleLink",
                              onToggle: { model.toggleHidesText() },
                              onStyle: { stylingPhoto = model.leftPhoto })
                .disabled(model.isExporting)
            ExportPrimaryButton(title: model.isExporting ? "匯出中" : "匯出",
                                identifier: "comparisonExportButton", isBusy: model.isExporting) {
                Task { await model.export() }
            }
            .disabled(model.isExporting)
            ExportSecondaryButton(title: "取消", identifier: "comparisonCancelButton") { model.cancel() }
                .disabled(model.isExporting)
                .opacity(model.isExporting ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CameraTheme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comparisonSheet")
    }

    // MARK: - Preview

    /// The composed image, made off the main thread; each half swaps its photo.
    /// It takes the room the sheet leaves and keeps the image's own shape.
    private var preview: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                previewImage
                    .aspectRatio(previewAspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("comparisonPreview")
            .task(id: model.previewKey) { await model.makePreview() }
    }

    private var previewAspect: CGFloat {
        guard let size = model.previewImage?.size, size.height > 0 else { return 2 }
        return size.width / size.height
    }

    private var previewImage: some View {
        ZStack {
            CameraTheme.fill
            if let image = model.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .accessibilityLabel("對比圖產生中")
            }
            switch model.arrangement {
            case .sideBySide:
                HStack(spacing: 0) {
                    tileButton(.left, identifier: "comparisonLeftTile")
                    tileButton(.right, identifier: "comparisonRightTile")
                }
            case .stacked:
                VStack(spacing: 0) {
                    tileButton(.left, identifier: "comparisonLeftTile")
                    tileButton(.right, identifier: "comparisonRightTile")
                }
            }
        }
    }

    private func tileButton(_ side: ComparisonModel.Side, identifier: String) -> some View {
        Button { pickingSide = side } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isExporting)
        .accessibilityLabel(model.tileAccessibilityLabel(side))
        .accessibilityIdentifier(identifier)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.exportError != nil }, set: { if !$0 { model.exportError = nil } })
    }
}

/// Picks the photo for one half of the comparison: the wall's three-column
/// grid of dated photos from the start date on, the current one ticked. One
/// tap chooses and goes back.
struct ComparisonPhotoPicker: View {
    @ObservedObject var model: ComparisonModel
    let side: ComparisonModel.Side
    let library: any RecordAlbumLibrary
    let onDone: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let cellSide = PhotoWallView.cellSide(forWidth: proxy.size.width)
            let current = model.photoID(on: side)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.pickerSections) { section in
                        Text(section.title)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(CameraTheme.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSide), spacing: PhotoWallView.columnSpacing),
                                                 count: PhotoWallView.columnCount),
                                  spacing: PhotoWallView.columnSpacing) {
                            ForEach(section.cells) { cell in
                                PhotoWallCell(cell: cell, side: cellSide, library: library,
                                              isSelected: cell.id == current, labelsDayText: true) {
                                    model.choose(cell.id, for: side)
                                    onDone()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, PhotoWallView.columnSpacing)
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom)
        }
        .background(CameraTheme.background.ignoresSafeArea())
        .navigationTitle("換\(model.name(of: side))照片")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comparisonPicker")
    }
}

/// A square thumbnail of the comparison card, rounded on one side.
struct ComparisonThumbnail: View {
    let photoID: String
    let side: CGFloat
    let library: any RecordAlbumLibrary
    let corners: RectangleCornerRadii

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            CameraTheme.fill
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
            }
        }
        .frame(width: side, height: side)
        .clipShape(UnevenRoundedRectangle(cornerRadii: corners, style: .continuous))
        .task(id: photoID) {
            let pixels = side * displayScale
            image = await library.thumbnail(id: photoID, targetSize: CGSize(width: pixels, height: pixels))
        }
    }
}
