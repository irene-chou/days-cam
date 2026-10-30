import SwiftUI

/// The photo wall of one record (PRD 2.0 FR-17, D-7 screen 2).
///
/// The record's photos by month, oldest to newest, opened at the newest, each
/// square marked with its day count. The bottom bar adds photos from the
/// library or opens the camera.
struct PhotoWallView: View {
    @StateObject private var model: PhotoWallModel
    @ObservedObject var listModel: RecordListModel
    @ObservedObject var cameraModel: CameraScreenModel
    @State private var viewerPhotoID: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsCamera = false
    @State private var showsPicker = false

    static let columnSpacing: CGFloat = 2
    static let columnCount = 3

    init(profileID: UUID,
         listModel: RecordListModel,
         cameraModel: CameraScreenModel) {
        _model = StateObject(wrappedValue: listModel.photoWallModel(for: profileID))
        self.listModel = listModel
        self.cameraModel = cameraModel
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isLimited && showsBottomBar { limitedBanner }
            content
            if showsBottomBar { bottomBar }
        }
        .background(CameraTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { titleView }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .tint(CameraTheme.active)
        .task { await model.prepare() }
        .onAppear {
            model.reload()
            model.startObservingLibrary()
            openNewestIfRequested()
        }
        .onDisappear { model.stopObservingLibrary() }
        // Back from Settings the status may have changed (§7.4).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
        .sheet(isPresented: $showsPicker) {
            PhotoPicker { ids in
                showsPicker = false
                Task { await model.addPhotos(ids: ids) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraScreen(model: cameraModel) { showsCamera = false }
        }
        .navigationDestination(item: $viewerPhotoID) { photoID in
            PhotoDetailView(model: listModel.photoDetailModel(
                for: model.profileID, startingAt: photoID,
                resolveFont: { [cameraModel] style in
                    OverlayMetrics.resolvedFont(for: style, availability: cameraModel.fontLibrary)
                }),
                makeExportModel: { [listModel, cameraModel, profileID = model.profileID] photo in
                    listModel.exportModel(for: profileID, photo: photo, cameraModel: cameraModel)
                })
        }
        .onChange(of: model.photoIDs) { _, _ in openNewestIfRequested() }
        .alert("無法加入照片", isPresented: errorBinding) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var titleView: some View {
        VStack(spacing: 1) {
            Text(model.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(CameraTheme.ink)
                .lineLimit(1)
            Text(model.subtitle)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundColor(CameraTheme.inkTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wallTitle")
    }

    /// 編輯紀錄 / 刪除紀錄 and nothing else (FR-17.9).
    private var moreMenu: some View {
        Menu {
            Button {
                listModel.editFromWall(id: model.profileID)
            } label: {
                Label("編輯紀錄", systemImage: "pencil")
            }
            Button(role: .destructive) {
                listModel.requestDeletion(of: model.profileID)
            } label: {
                Label("刪除紀錄", systemImage: "trash")
            }
            .disabled(!listModel.canDelete)
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多")
        .accessibilityIdentifier("wallMoreButton")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .photos: wall
        case .empty: emptyState
        case .needsPermission: PhotoAccessView()
        case .waiting: Color.clear
        }
    }

    private var showsBottomBar: Bool {
        model.content == .photos || model.content == .empty
    }

    private var wall: some View {
        GeometryReader { proxy in
            let side = Self.cellSide(forWidth: proxy.size.width)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.sections) { section in
                        Text(section.title)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(CameraTheme.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: Self.columnSpacing),
                                                 count: Self.columnCount),
                                  spacing: Self.columnSpacing) {
                            ForEach(section.cells) { cell in
                                PhotoWallCell(cell: cell, side: side, library: listModel.library) {
                                    viewerPhotoID = cell.id
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Self.columnSpacing)
                .padding(.bottom, 8)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .defaultScrollAnchor(.bottom)
            .onAppear { preheat(side: side) }
            .accessibilityIdentifier("photoWall")
        }
    }

    /// The square side that fits three columns in `width` (FR-17.3).
    static func cellSide(forWidth width: CGFloat) -> CGFloat {
        let gaps = columnSpacing * CGFloat(columnCount - 1) + columnSpacing * 2
        return max(1, floor((width - gaps) / CGFloat(columnCount)))
    }

    /// Warms the newest thumbnails, the ones the wall opens on.
    private func preheat(side: CGFloat) {
        let scale = UIScreen.main.scale
        listModel.library.startCaching(ids: Array(model.photoIDs.suffix(60)),
                                       targetSize: CGSize(width: side * scale, height: side * scale))
    }

    /// Limited access notice, always on top of the wall (§7.3).
    private var limitedBanner: some View {
        Text("限制取用中，不會與「照片」App 的相簿同步")
            .font(.system(size: 12.5))
            .foregroundColor(CameraTheme.inkSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("limitedAccessBanner")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("還沒有照片")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(CameraTheme.ink)
            Text("從相簿加入，或用相機拍一張")
                .font(.system(size: 13))
                .foregroundColor(CameraTheme.inkSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallEmptyState")
    }

    // MARK: - Bottom bar (FR-17.6)

    private var bottomBar: some View {
        HStack {
            Button {
                if model.beginAddingPhotos() { showsPicker = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 17, weight: .semibold))
                    Text("加入照片")
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundColor(CameraTheme.inkOnAccent)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(CameraTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addPhotosButton")
            Spacer()
            Button {
                cameraModel.selectProfile(id: model.profileID)
                showsCamera = true
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 22))
                    .foregroundColor(CameraTheme.ink)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("拍一張")
            .accessibilityIdentifier("wallCameraButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    /// Debug UI tests: `-UITestOpenExport` opens the newest photo once per
    /// launch, whose viewer then opens its export page (#620).
    private func openNewestIfRequested() {
        #if DEBUG
        guard let newest = model.photoIDs.last, UITestExportLaunch.consumeViewer() else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { viewerPhotoID = newest }
        #endif
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

/// One square of the wall: the photo's thumbnail, aspect-filled, with its day
/// mark at the lower left (FR-17.3, FR-17.4).
private struct PhotoWallCell: View {
    let cell: PhotoWallModel.Cell
    let side: CGFloat
    let library: any RecordAlbumLibrary
    var onSelect: () -> Void

    @State private var thumbnail: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button(action: onSelect) {
                ZStack {
                    CameraTheme.fill
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: side, height: side)
                    }
                }
                .frame(width: side, height: side)
                .clipped()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("照片")
            .accessibilityIdentifier("photoCell")

            Text(cell.dayText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundColor(cell.isBeforeStart ? CameraTheme.inkOnPhotoBeforeStart : CameraTheme.inkOnPhoto)
                .shadow(color: .black.opacity(0.6), radius: 2)
                .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                .padding(.leading, 6)
                .padding(.bottom, 5)
                .allowsHitTesting(false)
                .accessibilityIdentifier("photoDayLabel")
        }
        .frame(width: side, height: side)
        // Cancelled when the cell scrolls away, which cancels the request.
        .task(id: cell.id) {
            let pixels = side * displayScale
            thumbnail = await library.thumbnail(id: cell.id, targetSize: CGSize(width: pixels, height: pixels))
        }
    }
}
