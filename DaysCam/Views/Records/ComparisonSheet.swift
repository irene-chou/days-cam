import SwiftUI

/// The comparison sheet (#725, D-11 §3): the side-by-side preview, each half
/// a button that swaps its photo, the hint line, then 匯出／取消.
struct ComparisonSheet: View {
    @ObservedObject var model: ComparisonModel
    let library: any RecordAlbumLibrary

    @State private var pickingSide: ComparisonModel.Side?

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
        VStack(spacing: 14) {
            Text("對比圖")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(CameraTheme.ink)
                .accessibilityAddTraits(.isHeader)
            preview
            Text("點任一張可換成牆上別的照片 · 天數字樣用這個紀錄的文字樣式")
                .font(.system(size: 11.5))
                .foregroundColor(CameraTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            exportButton
            cancelButton
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
    private var preview: some View {
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
            HStack(spacing: 0) {
                tileButton(.left, identifier: "comparisonLeftTile")
                tileButton(.right, identifier: "comparisonRightTile")
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comparisonPreview")
        .task(id: model.previewKey) { await model.makePreview() }
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

    // MARK: - Buttons

    private var exportButton: some View {
        Button { Task { await model.export() } } label: {
            HStack(spacing: 8) {
                if model.isExporting {
                    ProgressView().tint(CameraTheme.inkOnAccent)
                }
                Text(model.isExporting ? "匯出中" : "匯出")
                    .font(.system(size: 15, weight: .heavy))
            }
            .foregroundColor(CameraTheme.inkOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(CameraTheme.accent))
        }
        .buttonStyle(.plain)
        .disabled(model.isExporting)
        .accessibilityIdentifier("comparisonExportButton")
    }

    private var cancelButton: some View {
        Button { model.cancel() } label: {
            Text("取消")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(CameraTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(CameraTheme.fill))
        }
        .buttonStyle(.plain)
        .disabled(model.isExporting)
        .opacity(model.isExporting ? 0.5 : 1)
        .accessibilityIdentifier("comparisonCancelButton")
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
        .navigationTitle(side == .left ? "換左邊照片" : "換右邊照片")
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
