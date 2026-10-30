import SwiftUI

/// The photo viewer of one record (PRD 2.0 FR-18, D-7 screen 3).
///
/// Each photo is shown at its own aspect ratio with the record's overlay
/// baked on as a preview (`PhotoDetailModel.pageImage`); swiping moves
/// through the wall's order. The 匯出 button at the bottom opens the export
/// page of the photo on screen (FR-18.5, #620).
struct PhotoDetailView: View {
    @StateObject private var model: PhotoDetailModel
    @Environment(\.dismiss) private var dismiss
    /// The photo whose export page is up.
    @State private var exportingPhoto: RecordPhoto?
    /// Builds the export page's model for a photo of this record.
    private let makeExportModel: (RecordPhoto) -> ExportModel

    init(model: PhotoDetailModel, makeExportModel: @escaping (RecordPhoto) -> ExportModel) {
        _model = StateObject(wrappedValue: model)
        self.makeExportModel = makeExportModel
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $model.selectedID) {
                ForEach(model.photos) { photo in
                    PhotoDetailPage(model: model, photo: photo)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            exportBar
        }
        .background(CameraTheme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoDetail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { titleView }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .tint(CameraTheme.active)
        .onAppear {
            model.reload()
            model.startObservingLibrary()
            openExportIfRequested()
        }
        .onDisappear { model.stopObservingLibrary() }
        .fullScreenCover(item: $exportingPhoto) { photo in
            ExportView(model: makeExportModel(photo))
        }
        .onChange(of: model.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .alert("無法完成", isPresented: errorBinding) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Header (FR-18.1)

    private var titleView: some View {
        VStack(spacing: 1) {
            if let photo = model.currentPhoto {
                Text(model.title(for: photo))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(CameraTheme.ink)
                    .lineLimit(1)
                if let line = model.dateLine(for: photo) {
                    Text(line)
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundColor(CameraTheme.inkTertiary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("photoDetailTitle")
    }

    /// 從紀錄移除 and 刪除照片 (FR-18.6).
    private var moreMenu: some View {
        Menu {
            Button {
                Task { await model.removeFromRecord() }
            } label: {
                Label("從「\(model.recordName)」移除（照片仍在相簿）", systemImage: "minus.circle")
            }
            .accessibilityIdentifier("removeFromRecordButton")
            Button(role: .destructive) {
                Task { await model.deletePhoto() }
            } label: {
                Label("刪除照片", systemImage: "trash")
            }
            .accessibilityIdentifier("deletePhotoButton")
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多")
        .accessibilityIdentifier("photoDetailMoreButton")
    }

    // MARK: - Export (FR-18.5)

    /// The 匯出 capsule, centered; disabled for a photo without a date
    /// (§6.1.3).
    private var exportBar: some View {
        Button {
            exportingPhoto = model.currentPhoto
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                Text("匯出")
                    .font(.system(size: 14, weight: .heavy))
            }
            .foregroundColor(CameraTheme.inkOnAccent)
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(CameraTheme.accent))
        }
        .buttonStyle(.plain)
        .disabled(!canExportCurrentPhoto)
        .opacity(canExportCurrentPhoto ? 1 : 0.4)
        .accessibilityIdentifier("exportButton")
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var canExportCurrentPhoto: Bool {
        model.currentPhoto.map(model.canExport) ?? false
    }

    /// Debug UI tests: `-UITestOpenExport` opens the export page of the photo
    /// on screen once per launch (#620).
    private func openExportIfRequested() {
        #if DEBUG
        guard UITestExportLaunch.consumeExport(), let photo = model.currentPhoto else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { exportingPhoto = photo }
        #endif
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

/// One page: the photo with its overlay, then the caption (FR-18.2, FR-18.4).
private struct PhotoDetailPage: View {
    @ObservedObject var model: PhotoDetailModel
    let photo: RecordPhoto

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    /// What the image depends on; a change reloads it.
    private struct Key: Equatable {
        let photoID: String
        let profile: CameraProfile?
        let size: CGSize
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("photoDetailImage")
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .task(id: Key(photoID: photo.id, profile: model.profile, size: proxy.size)) {
                    let pixels = CGSize(width: proxy.size.width * displayScale,
                                        height: proxy.size.height * displayScale)
                    guard pixels.width > 0, pixels.height > 0 else { return }
                    if let loaded = await model.pageImage(for: photo, targetSize: pixels) {
                        image = loaded
                    }
                }
            }
            Text("疊字只是預覽，照片本身沒有改動")
                .font(.system(size: 12.5))
                .foregroundColor(CameraTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .accessibilityIdentifier("photoDetailCaption")
        }
    }
}
