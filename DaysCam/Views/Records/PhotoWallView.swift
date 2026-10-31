import SwiftUI

/// The photo wall of one record (PRD 2.0 FR-17, D-7 screen 2).
///
/// The record's photos by month, oldest to newest, opened at the newest, each
/// square marked with its day count. The bottom bar adds photos from the
/// library or opens the camera; in selection mode it exports or removes the
/// ticked photos (FR-17.11–17.15).
struct PhotoWallView: View {
    @StateObject private var model: PhotoWallModel
    @ObservedObject var listModel: RecordListModel
    let styleCenter: StyleEditingCenter
    let makeCameraModel: @MainActor (UUID) -> CameraScreenModel
    @State private var viewerPhotoID: String?
    @Environment(\.scenePhase) private var scenePhase
    /// The open camera, built when it opens and dropped when it closes
    /// (#621).
    @State private var camera: CameraSession?
    /// The record the camera's switcher had selected when it closed.
    @State private var cameraReturnRecordID: UUID?
    @State private var showsPicker = false
    /// The remove-or-delete dialog is up (FR-17.14).
    @State private var showsRemoveOrDelete = false
    /// Cell frames and the finger for slide selection; not view state.
    @State private var slide = WallSlideTracker()
    /// A slide selection holds the finger; the wall stops scrolling under it.
    @State private var isSliding = false

    static let columnSpacing: CGFloat = 2
    static let columnCount = 3

    init(profileID: UUID,
         listModel: RecordListModel,
         styleCenter: StyleEditingCenter,
         makeCameraModel: @escaping @MainActor (UUID) -> CameraScreenModel) {
        _model = StateObject(wrappedValue: listModel.photoWallModel(for: profileID, resolveFont: { [styleCenter] style in
            OverlayMetrics.resolvedFont(for: style, availability: styleCenter.fontLibrary)
        }))
        self.listModel = listModel
        self.styleCenter = styleCenter
        self.makeCameraModel = makeCameraModel
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.showsLimitedNotice && showsBottomBar { limitedBanner }
            content
            if model.isSelecting {
                selectionBar
            } else if showsBottomBar {
                bottomBar
            }
        }
        .background(CameraTheme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { toastOverlay }
        .navigationBarTitleDisplayMode(.inline)
        // 全選 takes the back button's place while selecting (FR-17.11).
        .navigationBarBackButtonHidden(model.isSelecting)
        .toolbar {
            if model.isSelecting {
                ToolbarItem(placement: .topBarLeading) { selectAllButton }
                ToolbarItem(placement: .principal) { selectionTitleView }
                ToolbarItem(placement: .topBarTrailing) { cancelSelectionButton }
            } else {
                ToolbarItem(placement: .principal) { titleView }
                ToolbarItem(placement: .topBarTrailing) { selectButton }
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) { moreMenu }
            }
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
        // Closing the camera returns to the record its switcher has
        // selected (FR-20.11): another record's wall replaces this one;
        // otherwise this wall re-reads the record for new photos and a newly
        // bound album (FR-20.4).
        .fullScreenCover(item: $camera, onDismiss: cameraDidClose) { session in
            CameraScreen(model: session.model) {
                cameraReturnRecordID = session.model.selectedProfileID
                camera = nil
            }
        }
        .navigationDestination(item: $viewerPhotoID) { photoID in
            PhotoDetailView(model: listModel.photoDetailModel(
                for: model.profileID, startingAt: photoID,
                resolveFont: { [styleCenter] style in
                    OverlayMetrics.resolvedFont(for: style, availability: styleCenter.fontLibrary)
                }),
                makeExportModel: { [listModel, styleCenter, profileID = model.profileID] photo in
                    listModel.exportModel(for: profileID, photo: photo, styleCenter: styleCenter)
                })
        }
        .sheet(item: batchExportBinding) { batch in
            BatchExportSheet(model: batch) { [listModel, styleCenter, profileID = model.profileID] photo in
                listModel.exportModel(for: profileID, photo: photo, styleCenter: styleCenter)
            }
        }
        .onChange(of: model.photoIDs) { _, _ in openNewestIfRequested() }
        .alert(model.errorTitle, isPresented: errorBinding) {
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

    /// 選取, left of ⋯; off for an empty record (FR-17.9, FR-17.10).
    private var selectButton: some View {
        Button("選取") { model.beginSelecting() }
            .font(.system(size: 14, weight: .semibold))
            .disabled(!model.canSelect)
            .accessibilityIdentifier("wallSelectButton")
    }

    private var selectAllButton: some View {
        Button(model.isAllSelected ? "取消全選" : "全選") {
            if model.isAllSelected { model.deselectAll() } else { model.selectAll() }
        }
        .font(.system(size: 14, weight: .semibold))
        .accessibilityIdentifier("wallSelectAllButton")
    }

    /// "已選 N 張" (or "選取照片") over the record's name.
    private var selectionTitleView: some View {
        VStack(spacing: 1) {
            Text(model.selectionTitle)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundColor(CameraTheme.ink)
                .lineLimit(1)
            Text(model.title)
                .font(.system(size: 11.5))
                .foregroundColor(CameraTheme.inkTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wallTitle")
    }

    private var cancelSelectionButton: some View {
        Button("取消") { model.endSelecting() }
            .font(.system(size: 14, weight: .semibold))
            .accessibilityIdentifier("wallCancelSelectionButton")
    }

    /// 編輯紀錄 / 刪除紀錄 and nothing else (FR-17.9).
    private var moreMenu: some View {
        Menu {
            Button {
                listModel.editFromWall(id: model.profileID)
            } label: {
                Label("編輯紀錄", systemImage: "pencil")
            }
            if model.isLimited {
                Button {
                    model.openLimitedAccessSettings()
                } label: {
                    Label("設定照片權限", systemImage: "photo.on.rectangle.angled")
                }
                .accessibilityIdentifier("wallAllowAllPhotosItem")
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
            ScrollViewReader { scroller in
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
                                    PhotoWallCell(cell: cell, side: side, library: listModel.library,
                                                  isSelecting: model.isSelecting,
                                                  isSelected: model.selectedIDs.contains(cell.id)) {
                                        if model.isSelecting { model.toggle(cell.id) } else { viewerPhotoID = cell.id }
                                    }
                                    .id(cell.id)
                                    .onGeometryChange(for: CGRect.self) {
                                        $0.frame(in: .named(Self.viewportSpace))
                                    } action: { frame in
                                        slide.frames[cell.id] = frame
                                    }
                                    .onDisappear { slide.frames[cell.id] = nil }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Self.columnSpacing)
                    .padding(.bottom, 8)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .gesture(WallSlideGesture(isEnabled: model.isSelecting, space: .named(Self.viewportSpace)) { phase in
                        handleSlide(phase, height: proxy.size.height, scroller: scroller)
                    })
                }
                .defaultScrollAnchor(.bottom)
                // A slide owns the finger: the wall moves only by the edge
                // auto-scroll until it ends.
                .scrollDisabled(isSliding)
            }
            .onAppear { preheat(side: side) }
            .accessibilityIdentifier("photoWall")
        }
        .coordinateSpace(.named(Self.viewportSpace))
    }

    private static let viewportSpace = "photoWallViewport"

    // MARK: - Slide selection (FR-17.12)

    /// Ticks the range the finger slides over. Only a slide that starts
    /// sideways selects (the gesture declines vertical starts, which scroll),
    /// the way 「照片」 does. Near the top or bottom edge the wall scrolls a row
    /// at a time and the range follows the finger.
    private func handleSlide(_ phase: WallSlideGesture.Phase, height: CGFloat, scroller: ScrollViewProxy) {
        switch phase {
        case let .began(point):
            guard let index = slide.index(at: point, in: model.photoIDs) else { return }
            isSliding = true
            slide.finger = point
            model.beginDrag(at: index)
            slide.startAutoScroll { [model] in
                autoScroll(height: height, scroller: scroller, model: model)
            }
        case let .moved(point):
            guard isSliding else { return }
            slide.finger = point
            if let index = slide.index(at: point, in: model.photoIDs) { model.dragSelection(to: index) }
        case .ended:
            guard isSliding else { return }
            isSliding = false
            slide.stop()
            model.endDrag()
        }
    }

    /// One auto-scroll step: with the finger within `edge` of the top or
    /// bottom, brings the next row into view, then re-reads the finger.
    private func autoScroll(height: CGFloat, scroller: ScrollViewProxy, model: PhotoWallModel) {
        let edge: CGFloat = 60
        guard let finger = slide.finger else { return }
        let ids = model.photoIDs
        let visible = ids.indices.filter { index in
            guard let frame = slide.frames[ids[index]] else { return false }
            return frame.maxY > 0 && frame.minY < height
        }
        if finger.y > height - edge, let last = visible.last, last + 1 < ids.count {
            let target = min(last + Self.columnCount, ids.count - 1)
            withAnimation(.linear(duration: WallSlideTracker.step)) { scroller.scrollTo(ids[target], anchor: .bottom) }
        } else if finger.y < edge, let first = visible.first, first > 0 {
            let target = max(first - Self.columnCount, 0)
            withAnimation(.linear(duration: WallSlideTracker.step)) { scroller.scrollTo(ids[target], anchor: .top) }
        } else {
            return
        }
        if let index = slide.index(at: finger, in: ids) { model.dragSelection(to: index) }
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

    /// "前往設定 ›" joined with word joiners so it never breaks across lines.
    private static let settingsLinkText = "前往設定 ›".map(String.init).joined(separator: "\u{2060}")

    /// Limited access notice on top of the wall: the text opens Settings,
    /// the xmark dismisses (§7.3).
    private var limitedBanner: some View {
        HStack(spacing: 0) {
            Button { model.openLimitedAccessSettings() } label: {
                (Text("目前沒有開放完整權限，照片不會和原生相簿同步。")
                    .foregroundColor(CameraTheme.inkSecondary)
                    + Text(Self.settingsLinkText)
                    .foregroundColor(CameraTheme.active))
                    .font(.system(size: 12.5))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("limitedAccessBannerSettings")
            Button { model.dismissLimitedNotice() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CameraTheme.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("關閉提示")
            .accessibilityIdentifier("limitedAccessBannerDismiss")
        }
        .accessibilityElement(children: .contain)
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

    // MARK: - Selection bar (FR-17.13)

    /// 匯出｜刪除 in place of the bottom bar; both off with nothing ticked,
    /// 匯出 also off when every ticked photo is 日期不明.
    private var selectionBar: some View {
        HStack(spacing: 0) {
            selectionAction("匯出", systemImage: "square.and.arrow.up", color: CameraTheme.ink) {
                model.beginBatchExport()
            }
            .disabled(!model.canExportSelection)
            .accessibilityIdentifier("wallExportButton")
            selectionAction("刪除", systemImage: "trash", color: Self.destructive) {
                showsRemoveOrDelete = true
            }
            .disabled(model.selectedIDs.isEmpty)
            .accessibilityIdentifier("wallDeleteButton")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(CameraTheme.ink.opacity(0.08)).frame(height: 1)
        }
        .removeOrDeleteDialog(isPresented: $showsRemoveOrDelete,
                              title: RemoveOrDeleteDialog.title(recordName: model.title,
                                                                count: model.selectedIDs.count),
                              recordName: model.title,
                              count: model.selectedIDs.count,
                              onRemove: { Task { await model.removeSelected() } },
                              onDelete: { Task { await model.deleteSelected() } })
    }

    /// D8's #D2422C for 刪除.
    private static let destructive = Color(red: 0xD2 / 255, green: 0x42 / 255, blue: 0x2C / 255)

    private func selectionAction(_ title: String, systemImage: String, color: Color,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 19))
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(SelectionActionStyle())
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toastState = model.toastState {
            ToastView(state: toastState)
                .padding(.bottom, 90)
                .transition(.opacity)
                .animation(.easeInOut, value: toastState.id)
                .accessibilityIdentifier("wallToast")
        }
    }

    // MARK: - Bottom bar (FR-17.6)

    private var bottomBar: some View {
        HStack {
            Button {
                if model.beginAddingPhotos() { showsPicker = true }
            } label: {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 22))
                    .foregroundColor(CameraTheme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("加入照片")
            .accessibilityIdentifier("addPhotosButton")
            Spacer()
            Button {
                camera = CameraSession(model: makeCameraModel(model.profileID))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera")
                        .font(.system(size: 17, weight: .semibold))
                    Text("拍照")
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundColor(CameraTheme.inkOnAccent)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(CameraTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wallCameraButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func cameraDidClose() {
        let selected = cameraReturnRecordID ?? model.profileID
        cameraReturnRecordID = nil
        if !listModel.cameraDidClose(openedFrom: model.profileID, selected: selected) {
            model.reload()
        }
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

    /// Swiping the preview away is 取消; the other phases cannot be swiped.
    private var batchExportBinding: Binding<BatchExportModel?> {
        Binding(get: { model.batchExport }, set: { if $0 == nil { model.batchExport?.cancel() } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

/// One opening of the camera: its model lives exactly as long as the cover.
private struct CameraSession: Identifiable {
    let id = UUID()
    let model: CameraScreenModel
}

/// One square of the wall: the photo's thumbnail, aspect-filled, with its day
/// mark at the lower left (FR-17.3, FR-17.4).
private struct PhotoWallCell: View {
    let cell: PhotoWallModel.Cell
    let side: CGFloat
    let library: any RecordAlbumLibrary
    var isSelecting = false
    var isSelected = false
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
                // A ticked photo shrinks inside a tinted square (D8 ②).
                .scaleEffect(isSelected ? 0.9 : 1)
                .frame(width: side, height: side)
                .background(isSelected ? CameraTheme.active.opacity(0.12) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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

            if isSelecting { checkmark }
        }
        .frame(width: side, height: side)
        // Cancelled when the cell scrolls away, which cancels the request.
        .task(id: cell.id) {
            let pixels = side * displayScale
            thumbnail = await library.thumbnail(id: cell.id, targetSize: CGSize(width: pixels, height: pixels))
        }
    }

    /// "照片" normally; "第 N 天" or "第 N 天，已選取" while selecting (FR-17.12).
    private var accessibilityLabel: String {
        guard isSelecting else { return "照片" }
        return isSelected ? "\(cell.dayText)，已選取" : cell.dayText
    }

    /// The tick at the lower right: an empty ring, or a filled check.
    private var checkmark: some View {
        ZStack {
            if isSelected {
                Circle().fill(Color.white)
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundColor(CameraTheme.active)
            } else {
                Circle().fill(Color.black.opacity(0.18))
                Circle().strokeBorder(Color.white, lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Dims a selection-bar action while pressed or disabled.
private struct SelectionActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.35)
    }
}

/// What slide selection needs outside view state: each visible cell's frame
/// in the wall's viewport, the finger, and the auto-scroll loop. Writing
/// frames here does not redraw the wall.
@MainActor
private final class WallSlideTracker {
    /// Seconds between auto-scroll steps.
    static let step: TimeInterval = 0.12

    var frames: [String: CGRect] = [:]
    var finger: CGPoint?
    private var autoScrollTask: Task<Void, Never>?

    /// The wall index of the cell under `point`, if any.
    func index(at point: CGPoint, in ids: [String]) -> Int? {
        guard let id = frames.first(where: { $0.value.contains(point) })?.key else { return nil }
        return ids.firstIndex(of: id)
    }

    func startAutoScroll(_ tick: @escaping @MainActor () -> Void) {
        autoScrollTask?.cancel()
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.step))
                guard !Task.isCancelled else { return }
                tick()
            }
        }
    }

    func stop() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        finger = nil
    }
}

/// A pan that only begins sideways, so vertical drags still scroll the wall
/// (FR-17.12). Reports locations in `space`.
private struct WallSlideGesture: UIGestureRecognizerRepresentable {
    enum Phase {
        case began(CGPoint)
        case moved(CGPoint)
        case ended
    }

    var isEnabled: Bool
    var space: NamedCoordinateSpace
    var onChange: (Phase) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let point = context.converter.location(in: space)
        switch recognizer.state {
        case .began:
            // Start from where the finger first went down, not where the pan
            // was recognized, so the first photo is the one touched.
            let moved = recognizer.translation(in: recognizer.view)
            onChange(.began(CGPoint(x: point.x - moved.x, y: point.y - moved.y)))
            onChange(.moved(point))
        case .changed:
            onChange(.moved(point))
        case .ended, .cancelled, .failed:
            onChange(.ended)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
