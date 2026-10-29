import SwiftUI

/// The photo viewer of one record (PRD 2.0 FR-18, D-7 screen 3).
///
/// Each photo is shown at its own aspect ratio with the record's overlay
/// baked on as a preview (`PhotoDetailModel.pageImage`); swiping moves
/// through the wall's order. The export button comes with #620.
struct PhotoDetailView: View {
    @StateObject private var model: PhotoDetailModel
    @Environment(\.dismiss) private var dismiss

    init(model: PhotoDetailModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        TabView(selection: $model.selectedID) {
            ForEach(model.photos) { photo in
                PhotoDetailPage(model: model, photo: photo)
                    .tag(photo.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
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
        }
        .onDisappear { model.stopObservingLibrary() }
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
