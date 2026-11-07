import SwiftUI

/// The photo viewer of one record (PRD 2.0 FR-18, D-7 screen 3).
///
/// Each photo is shown at its own aspect ratio with the record's overlay
/// baked on as a preview (`PhotoDetailModel.pageImage`); swiping moves
/// through the wall's order. The bottom bar is the wall's selection bar
/// (#679): 匯出 opens the export sheet the batch export uses, with just this
/// photo, and 刪除 asks remove-or-delete (FR-18.6). The first visit points
/// the overlay out (FR-18.8).
struct PhotoDetailView: View {
    @StateObject private var model: PhotoDetailModel
    @Environment(\.dismiss) private var dismiss
    /// The photo whose 文字樣式 page is up; only `-UITestOpenExport` opens it
    /// from here, otherwise it is reached from the export sheet.
    @State private var stylingPhoto: RecordPhoto?
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
            actionBar
        }
        .background(CameraTheme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { toastOverlay }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoDetail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { titleView }
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
        // Progress and failures stay on the sheet, which cannot be swiped
        // away then, so the viewer cannot be used until it ends.
        .sheet(item: exportBinding) { export in
            BatchExportSheet(model: export, makeExportModel: makeExportModel)
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

    // MARK: - Bottom bar (#679)

    /// 匯出｜刪除, the wall's selection bar. 匯出 is off for a photo without
    /// a date (§6.1.3); 刪除 asks remove-or-delete, its popover pointing at it.
    private var actionBar: some View {
        SelectionActionBar {
            SelectionActionButton(title: "匯出", systemImage: "square.and.arrow.up", color: CameraTheme.ink) {
                model.beginExport()
            }
            .disabled(!model.canStartExport)
            .accessibilityIdentifier("photoDetailExportButton")
            SelectionActionButton(title: "刪除", systemImage: "trash", color: SelectionActionButton.destructive) {
                showsRemoveOrDelete = true
            }
            .disabled(model.currentPhoto == nil)
            .accessibilityIdentifier("photoDetailDeleteButton")
            .removeOrDeleteDialog(isPresented: $showsRemoveOrDelete,
                                  title: RemoveOrDeleteDialog.title(recordName: model.recordName),
                                  recordName: model.recordName,
                                  onRemove: { Task { await model.removeFromRecord() } },
                                  onDelete: { Task { await model.deletePhoto() } })
        }
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

    /// Swiping the preview away is 取消.
    private var exportBinding: Binding<BatchExportModel?> {
        Binding(get: { model.export }, set: { if $0 == nil { model.export?.cancel() } })
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
            Text("照片本身不會改；按「匯出」才會另存一張印上這行字的新照片。想換字型、顏色或位置，在匯出時按「調整文字樣式」。")
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
