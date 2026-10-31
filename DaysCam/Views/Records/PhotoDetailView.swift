import SwiftUI

/// The photo viewer of one record (PRD 2.0 FR-18, D-7 screen 3).
///
/// Each photo is shown at its own aspect ratio with the record's overlay
/// baked on as a preview (`PhotoDetailModel.pageImage`); swiping moves
/// through the wall's order. The two buttons at the bottom open the 文字樣式
/// page (FR-19) and export the photo on screen with the record's current
/// style (FR-18.5, FR-22.2). The first visit points the overlay out
/// (FR-18.8), the first export shows a comparison first (FR-22.3).
struct PhotoDetailView: View {
    @StateObject private var model: PhotoDetailModel
    @Environment(\.dismiss) private var dismiss
    /// The photo whose 文字樣式 page is up.
    @State private var stylingPhoto: RecordPhoto?
    /// 先調整文字樣式 was chosen on the comparison sheet; the page opens once
    /// the sheet is gone.
    @State private var opensStyleAfterIntro = false
    /// The remove-or-delete dialog is up.
    @State private var showsRemoveOrDelete = false
    /// Builds the 文字樣式 page's model for a photo of this record.
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
            // No swiping to another photo while one is being exported (FR-22.2).
            .scrollDisabled(model.isExporting)
            actionBar
                // Anchored here, not to the toolbar's ⋯, so it comes up as the
                // bottom action sheet.
                .removeOrDeleteDialog(isPresented: $showsRemoveOrDelete,
                                      title: RemoveOrDeleteDialog.title(recordName: model.recordName),
                                      recordName: model.recordName,
                                      onRemove: { Task { await model.removeFromRecord() } },
                                      onDelete: { Task { await model.deletePhoto() } })
        }
        .background(CameraTheme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { toastOverlay }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoDetail")
        .navigationBarTitleDisplayMode(.inline)
        // Leaving now would orphan the export's toast and error (#633).
        .navigationBarBackButtonHidden(model.isExporting)
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
        .fullScreenCover(item: $stylingPhoto) { photo in
            ExportView(model: makeExportModel(photo))
        }
        .sheet(isPresented: $model.showsExportIntro, onDismiss: {
            if opensStyleAfterIntro {
                opensStyleAfterIntro = false
                stylingPhoto = model.currentPhoto
            }
        }) {
            ExportIntroSheet(model: model) { opensStyleAfterIntro = true }
        }
        .alert("無法匯出", isPresented: exportErrorBinding, presenting: model.exportError) { error in
            if error.showsSettingsAction {
                Button("前往設定") {
                    model.dismissExportError()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Button("好", role: .cancel) { model.dismissExportError() }
        } message: { error in
            Text(error.message)
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

    /// 刪除… (FR-18.6): one item, which asks whether to remove the photo
    /// from the record or delete it from 「照片」.
    private var moreMenu: some View {
        Menu {
            Button(role: .destructive) {
                showsRemoveOrDelete = true
            } label: {
                Label("刪除…", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteMenuButton")
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多")
        .accessibilityIdentifier("photoDetailMoreButton")
    }

    // MARK: - Bottom buttons (FR-18.5)

    /// 文字樣式 on the left, 匯出 on the right; both disabled for a photo
    /// without a date (§6.1.3), both while an export runs.
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                stylingPhoto = model.currentPhoto
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paintbrush")
                        .font(.system(size: 16, weight: .semibold))
                    Text("文字樣式")
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundColor(CameraTheme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(CameraTheme.fill))
            }
            .buttonStyle(.plain)
            .disabled(!model.canStartExport)
            .opacity(model.canStartExport ? 1 : 0.4)
            .accessibilityIdentifier("styleButton")
            Button {
                Task { await model.requestExport() }
            } label: {
                HStack(spacing: 6) {
                    if model.isExporting {
                        ProgressView(value: model.exportProgress)
                            .progressViewStyle(.circular)
                            .tint(CameraTheme.inkOnAccent)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Text(model.isExporting ? "匯出中" : "匯出")
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundColor(CameraTheme.inkOnAccent)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(CameraTheme.accent))
            }
            .buttonStyle(.plain)
            .disabled(!model.canStartExport)
            .opacity(canExportCurrentPhoto ? 1 : 0.4)
            .accessibilityLabel(model.isExporting ? "匯出中" : "匯出")
            .accessibilityIdentifier("exportButton")
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var canExportCurrentPhoto: Bool {
        model.currentPhoto.map(model.canExport) ?? false
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

    private var exportErrorBinding: Binding<Bool> {
        Binding(get: { model.exportError != nil }, set: { if !$0 { model.dismissExportError() } })
    }

    /// Debug UI tests: `-UITestOpenExport` opens the 文字樣式 page of the photo
    /// on screen once per launch (#620).
    private func openExportIfRequested() {
        #if DEBUG
        guard UITestExportLaunch.consumeExport(), let photo = model.currentPhoto else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { stylingPhoto = photo }
        #endif
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

/// One page: the photo with its overlay (FR-18.2), and the pointer bubble on
/// the first visit (FR-18.8).
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
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("photoDetailImage")
                }
                if let image, photo.id == model.selectedID, model.showsCoach,
                   let target = coachTarget(imageSize: image.size, in: proxy.size) {
                    ViewerCoach(target: target, container: proxy.size) { model.dismissCoach() }
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
    }

    /// The overlay's frame in the page, where the image is drawn aspect-fit.
    private func coachTarget(imageSize: CGSize, in container: CGSize) -> CGRect? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        guard let block = model.overlayFrame(for: photo, imageSize: fitted) else { return nil }
        let origin = CGPoint(x: (container.width - fitted.width) / 2, y: (container.height - fitted.height) / 2)
        return block.offsetBy(dx: origin.x, dy: origin.y)
    }
}

/// The first-visit pointer (FR-18.8, D8 ③): a ring around the overlay and a
/// dark bubble above or below it, with 知道了.
private struct ViewerCoach: View {
    /// The overlay's frame in the container.
    let target: CGRect
    let container: CGSize
    var onDismiss: () -> Void

    private static let ringInset: CGFloat = 6
    private static let gap: CGFloat = 12
    private static let bubbleColor = Color(red: 0x2A / 255, green: 0x26 / 255, blue: 0x22 / 255)

    var body: some View {
        let ring = target.insetBy(dx: -Self.ringInset, dy: -Self.ringInset)
        let above = ring.midY > container.height / 2
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CameraTheme.accent, lineWidth: 2)
                .frame(width: ring.width, height: ring.height)
                .offset(x: ring.minX, y: ring.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            bubble(arrowX: min(max(ring.midX - 24, 28), container.width - 24 - 28 - 14), pointsDown: above)
                .frame(width: container.width - 48)
                .frame(maxHeight: .infinity, alignment: above ? .bottom : .top)
                .padding(.bottom, above ? container.height - ring.minY + Self.gap : 0)
                .padding(.top, above ? 0 : ring.maxY + Self.gap)
                .padding(.leading, 24)
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
    }

    private func bubble(arrowX: CGFloat, pointsDown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("這是 DaysCam 加上的天數")
                .font(.system(size: 13, weight: .bold))
            Text("照片本身不會改；按「匯出」才會另存一張印上這行字的新照片。想換字型、顏色或位置，按「文字樣式」。")
                .font(.system(size: 13))
                .lineSpacing(2)
            Button(action: onDismiss) {
                Text("知道了")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(CameraTheme.inkOnAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(CameraTheme.accent))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
            .accessibilityIdentifier("viewerCoachOkButton")
        }
        .multilineTextAlignment(.leading)
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.bubbleColor))
        .overlay(alignment: pointsDown ? .bottomLeading : .topLeading) {
            Rectangle()
                .fill(Self.bubbleColor)
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(45))
                .offset(x: arrowX, y: pointsDown ? 7 : -7)
                .accessibilityHidden(true)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewerCoach")
    }
}

/// The first-export comparison (FR-22.3, D8 ③): the original next to the
/// new photo with the overlay, then 匯出 or 先調整文字樣式. Either button
/// counts as seen; swiping the sheet away does not, and exports nothing.
private struct ExportIntroSheet: View {
    @ObservedObject var model: PhotoDetailModel
    /// Called when 先調整文字樣式 is chosen, before the sheet closes.
    var onStyleFirst: () -> Void

    @State private var original: UIImage?
    @State private var exported: UIImage?
    @Environment(\.displayScale) private var displayScale

    private static let side: CGFloat = 150

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("匯出會另存一張新照片")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(CameraTheme.ink)
                Text("原圖不動，新照片印上天數，存到「最近項目」。")
                    .font(.system(size: 13.5))
                    .foregroundColor(CameraTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(alignment: .top, spacing: 14) {
                figure(original, caption: "原圖（不變）")
                figure(exported, caption: "匯出的新照片")
            }
            Button {
                Task { await model.confirmExportIntro() }
            } label: {
                Text("匯出")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(CameraTheme.inkOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(CameraTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exportIntroExportButton")
            Button {
                onStyleFirst()
                model.skipExportIntroForStyle()
            } label: {
                Text("先調整文字樣式")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(CameraTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(CameraTheme.fill))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exportIntroStyleButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CameraTheme.background.ignoresSafeArea())
        .presentationDetents([.fraction(0.75)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exportIntroSheet")
        .task {
            guard let photo = model.currentPhoto else { return }
            let pixels = CGSize(width: Self.side * displayScale * 2, height: Self.side * displayScale * 2)
            original = await model.plainImage(for: photo, targetSize: pixels)
            exported = await model.pageImage(for: photo, targetSize: pixels)
        }
    }

    private func figure(_ image: UIImage?, caption: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.08))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.side * 1.25)
            Text(caption)
                .font(.system(size: 12))
                .foregroundColor(CameraTheme.inkSecondary)
        }
    }
}
