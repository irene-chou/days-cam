import SwiftUI

/// The app's only launch destination (PRD S-1).
///
/// Composes the viewfinder, the live overlay text, the permission guidance
/// screen, the camera toolbar, the profile switcher, the shutter, the
/// save-confirmation toast and the data-recovery alert (PRD §7.3). All state
/// and decisions live in `CameraScreenModel`; this view only lays it out.
///
/// Fixed light theme (PRD 0.2 FR-14.1): the screen never follows the
/// system's Light/Dark Mode setting, so every color here comes from
/// `CameraTheme`'s Asset Catalog entries (which themselves carry no dark
/// variant) plus `.preferredColorScheme(.light)` at the root, which also
/// forces system chrome (this screen's own `.alert`s) light. The one
/// exception is `PermissionGuidanceView` (human decision 2026-09-27), which
/// clears that preference back to `nil` for its own subtree so it can
/// follow the system appearance instead.
struct CameraScreen: View {
    @ObservedObject var model: CameraScreenModel

    var body: some View {
        content
            .background(CameraTheme.background.ignoresSafeArea())
            .preferredColorScheme(.light)
            .onAppear { model.onAppear() }
            .onDisappear { model.onDisappear() }
            .sheet(isPresented: $model.isProfileListPresented) {
                NavigationStack {
                    ProfileListView(model: model.profileListModel)
                }
            }
            .overlay(alignment: .bottomLeading) { toastOverlay }
            .alert("設定檔讀取失敗，已重設。", isPresented: corruptionAlertBinding) {
                Button("好") { model.dismissCorruptionRecoveredAlert() }
            }
            .alert("無法完成拍照", isPresented: captureErrorBinding, presenting: model.captureError) { error in
                if error.showsSettingsAction {
                    Button("前往設定") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
                Button("好", role: .cancel) { model.dismissCaptureError() }
            } message: { error in
                Text(error.message)
            }
    }

    /// Picks between the two layouts PRD 0.2 FR-7.8 describes: 9:16 is full
    /// bleed with floating chrome, 3:4/1:1 keep the toolbar and bottom bar in
    /// normal flow around a fixed-ratio box.
    @ViewBuilder
    private var content: some View {
        if isFullBleed {
            fullBleedLayout
        } else {
            standardLayout
        }
    }

    private var isFullBleed: Bool {
        model.captureSettingsStore.captureAspectRatio == .nineBySixteen
    }

    // MARK: - 3:4 / 1:1 layout

    /// The toolbar sits in normal flow above the viewfinder box (matching
    /// D-1's own column layout — it is not an overlay floating over the
    /// live picture at this ratio; 9:16 is the one case that does that).
    ///
    /// The box itself is always 3:4 (PRD 0.2 FR-7.8), so the toolbar and
    /// bottom bar never move when switching ratios — only what's *inside*
    /// shrinks: at 1:1 the inner square centers vertically for free, since a
    /// `ZStack` centers a smaller child by default. While the overlay panel
    /// is open (PRD 0.2 FR-8.2), the *whole box* additionally scales to 80%
    /// width (height following, since the box keeps its 3:4 shape) and
    /// centers horizontally — the panel then fills the vertical space that
    /// frees up between it and the bottom bar, exactly the way a plain
    /// `VStack` hands unclaimed height to a flexible sibling.
    private var standardLayout: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                CameraToolbar(model: model)

                viewfinderBox(containerWidth: proxy.size.width)
                    .frame(maxWidth: .infinity)
                    .animation(CameraTheme.spring, value: model.panelModel.isOpen)

                if model.panelModel.isOpen {
                    OverlayPanelView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }

                bottomBar
            }
        }
    }

    /// The viewfinder box sized for a `containerWidth`-wide screen: full
    /// width normally, 80% and centered while the panel is open (FR-8.2).
    /// Height always follows from width to keep the box's 3:4 shape.
    private func viewfinderBox(containerWidth: CGFloat) -> some View {
        let boxWidth = model.panelModel.isOpen ? containerWidth * 0.8 : containerWidth
        let boxHeight = boxWidth * 4.0 / 3.0
        let vfSize = viewfinderSize(boxWidth: boxWidth, boxHeight: boxHeight)
        return ZStack {
            viewfinderContent(frameSize: vfSize)
                .frame(width: vfSize.width, height: vfSize.height)
                .clipped()
        }
        .frame(width: boxWidth, height: boxHeight)
    }

    /// The on-screen size of the viewfinder itself within a box that is
    /// always 3:4 (PRD 0.2 FR-7.8): unchanged for 3:4, the full box width
    /// squared for 1:1. Never called for 9:16 — that ratio uses
    /// `fullBleedLayout` instead, not this box.
    private func viewfinderSize(boxWidth: CGFloat, boxHeight: CGFloat) -> CGSize {
        switch model.captureSettingsStore.captureAspectRatio {
        case .threeByFour:
            return CGSize(width: boxWidth, height: boxHeight)
        case .oneByOne:
            return CGSize(width: boxWidth, height: boxWidth)
        case .nineBySixteen:
            return CGSize(width: boxWidth, height: boxHeight)
        }
    }

    // MARK: - 9:16 layout

    /// Fills the screen edge to edge; the toolbar and bottom bar float over
    /// it, each behind a gradient fading to `CameraTheme.background` so they
    /// stay legible over whatever the camera is pointed at (PRD 0.2 FR-7.8,
    /// D-1).
    ///
    /// Assumption: PRD 0.2 FR-8.2/D-2 only ever show the panel against a 3:4
    /// viewfinder; opening it while at 9:16 has no documented layout. Rather
    /// than shrink an already-full-bleed viewfinder (which would need its
    /// own bespoke centering rules nothing describes), the panel simply
    /// floats over the bottom bar at a fixed height here — flagged in this
    /// PR's description for a human/B′ call on whether that is good enough.
    private var fullBleedLayout: some View {
        GeometryReader { proxy in
            viewfinderContent(frameSize: proxy.size)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    CameraToolbar(model: model)
                        .background(topFadeGradient.ignoresSafeArea(edges: .top))
                }
                .overlay(alignment: .bottom) {
                    VStack(spacing: 0) {
                        if model.panelModel.isOpen {
                            OverlayPanelView(model: model)
                                .frame(height: 220)
                                .transition(.opacity)
                        }
                        bottomBar
                    }
                    .background(bottomFadeGradient.ignoresSafeArea(edges: .bottom))
                    .animation(CameraTheme.spring, value: model.panelModel.isOpen)
                }
        }
    }

    private var topFadeGradient: some View {
        LinearGradient(colors: [CameraTheme.background.opacity(0.85), .clear],
                       startPoint: .top, endPoint: .bottom)
    }

    private var bottomFadeGradient: some View {
        LinearGradient(colors: [.clear, CameraTheme.background.opacity(0.9)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Viewfinder contents (shared by both layouts)

    /// Everything drawn inside the viewfinder box, sized to `frameSize`: the
    /// live preview (or placeholder), the optional three-by-three grid
    /// (PRD 0.2 FR-7.9, never baked into the photo), the overlay text, the
    /// countdown's big number (FR-7.6), the transient status message and the
    /// permission guidance screen.
    @ViewBuilder
    private func viewfinderContent(frameSize: CGSize) -> some View {
        ZStack {
            if model.showsPlaceholder {
                placeholderBackground
            } else {
                // Deliberately not `.ignoresSafeArea()` here (that is applied
                // once, at the outer layout level, for the 9:16 case only):
                // this container is already sized to exactly `frameSize`,
                // and letting the preview layer grow beyond it would make it
                // taller than what `OverlayTextView` below measures — the
                // overlay would sit against a boundary the picture doesn't
                // actually end at (code review finding carried over from
                // 0.1, PRD FR-6.1/6.3).
                CameraPreviewView(session: model.cameraService.session)
            }

            if model.captureSettingsStore.showsGrid {
                GridLinesView()
            }

            // Overlay text tracks the viewfinder's own size (not the
            // screen's), matching FR-6.1's requirement that the preview and
            // the eventual baked photo agree. Draggable only while the panel
            // is open on the 位置 tab (PRD 0.2 FR-12.1, TASK-24's interface —
            // see `OverlayPanelModel.overlayDragHandler`'s own doc comment);
            // the closures forward straight through and never interpret the
            // values themselves.
            OverlayTextView(text: model.overlayText,
                            style: model.overlayStyle,
                            placement: model.overlayPlacement,
                            frameSize: frameSize,
                            onDragChanged: model.panelModel.isOverlayDraggable ? { center, size in
                                model.panelModel.overlayDragHandler?.overlayDragChanged(center: center, viewfinderSize: size)
                            } : nil,
                            onDragEnded: model.panelModel.isOverlayDraggable ? { center, size in
                                model.panelModel.overlayDragHandler?.overlayDragEnded(center: center, viewfinderSize: size)
                            } : nil)

            if let countdownRemaining = model.countdownRemaining {
                Text("\(countdownRemaining)")
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                    .allowsHitTesting(false)
            }

            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule())
            }

            if model.needsPermissionGuidance {
                // PRD 0.2 FR-14.1's sole exception (human decision
                // 2026-09-27): this one screen follows the system
                // appearance. `.preferredColorScheme(nil)` clears the
                // `.light` preference the screen's root sets below, letting
                // this subtree read the real system setting again — every
                // other view here stays fixed-light.
                PermissionGuidanceView()
                    .preferredColorScheme(nil)
            }
        }
        // PRD 0.2 FR-8.7: tapping the viewfinder outside the overlay text
        // collapses the panel, only while it is open. `OverlayTextView`
        // itself claims its own hit-testing area only while draggable
        // (position tab), so a tap that starts there reaches its drag
        // gesture instead of this one — never both.
        .onTapGesture {
            if model.panelModel.isOpen {
                model.panelModel.close()
            }
        }
    }

    /// The simulator/placeholder background (PRD §2.4): a solid color plus a
    /// label so it is unmistakably not a live picture.
    private var placeholderBackground: some View {
        ZStack {
            Color(white: 0.15)
            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                Text(CameraScreenModel.simulatorPlaceholderText)
                    .font(.subheadline)
            }
            .foregroundColor(.white.opacity(0.8))
        }
    }

    // MARK: - Bottom bar (PRD 0.2 FR-7.3, FR-8.3)

    /// Left/center/right switch with the panel (PRD 0.2 FR-8.3, acceptance
    /// 22.5): closed is TASK-21's thumbnail／shutter／Aa; open is manage-
    /// profiles／shrunk shutter／collapse. The shutter stays tappable either
    /// way (FR-8.3: "快門照常可拍"). No text labels, no background — every
    /// button is just an icon (FR-14.2).
    private var bottomBar: some View {
        ZStack {
            HStack {
                Spacer()
                shutterButton
                Spacer()
            }
            HStack {
                leftBottomBarButton
                Spacer()
                rightBottomBarButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, model.panelModel.isOpen ? 12 : 24)
    }

    @ViewBuilder
    private var leftBottomBarButton: some View {
        switch model.panelModel.leftBottomBarAction {
        case .latestPhoto:
            thumbnailButton
        case .manageProfiles:
            iconButton(systemName: "list.bullet", accessibilityLabel: "管理設定檔") {
                model.presentProfileManagement()
            }
        }
    }

    @ViewBuilder
    private var rightBottomBarButton: some View {
        switch model.panelModel.rightBottomBarAction {
        case .openOverlayPanel:
            // `pencil.tip.crop.circle`, not `textformat`: the style tab's
            // own 字型 sub-tab already uses `textformat` (PRD FR-10.1), and
            // having both on screen at once while the panel is open reads
            // as the same button twice (human decision, 2026-09-27, #84).
            iconButton(systemName: "pencil.tip.crop.circle", accessibilityLabel: "疊字設定") {
                model.panelModel.open()
            }
        case .collapse:
            iconButton(systemName: "chevron.down", accessibilityLabel: "收起面板") {
                model.panelModel.close()
            }
        }
    }

    private func iconButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(CameraTheme.ink)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    /// Left key while closed: the newest DaysCam photo, or a placeholder
    /// icon (PRD 0.2 FR-15.2). Tapping it does nothing yet — TASK-29 wires
    /// up requesting read access and opening the gallery.
    private var thumbnailButton: some View {
        Button {
            // TASK-29: request read access, then open the gallery.
        } label: {
            Group {
                if let image = model.latestThumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(CameraTheme.ink)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityLabel("查看已拍照片")
    }

    /// Center: the shutter — the one place PRD 0.2 FR-14.2 allows a filled
    /// background (the `accent` circle) plus a ring, matching D-1. Shrinks
    /// to 64pt while the panel is open (PRD 0.2 FR-8.3) but stays exactly as
    /// tappable (acceptance 22.4: capturing while the panel is open must
    /// work normally and must not close it).
    private var shutterButton: some View {
        let diameter: CGFloat = model.panelModel.isOpen ? 64 : 76
        let ringWidth: CGFloat = model.panelModel.isOpen ? 3 : 4
        return Button(action: model.capturePhoto) {
            ZStack {
                Circle()
                    .strokeBorder(CameraTheme.shutterRing, lineWidth: ringWidth)
                Circle()
                    .fill(CameraTheme.accent)
                    .padding(ringWidth)
            }
            .frame(width: diameter, height: diameter)
        }
        .disabled(model.isShutterDisabled)
        .opacity(model.isShutterDisabled ? 0.4 : 1)
        .accessibilityLabel("快門")
    }

    // MARK: - Bindings

    /// `model.showsCorruptionRecoveredAlert` as a `Binding` for `.alert`, same
    /// dismiss-clears-model-state pattern as `ProfileListView.editorBinding`.
    private var corruptionAlertBinding: Binding<Bool> {
        Binding(get: { model.showsCorruptionRecoveredAlert },
                set: { isPresented in if !isPresented { model.dismissCorruptionRecoveredAlert() } })
    }

    /// `model.captureError` as a `Binding<Bool>` for `.alert(isPresented:presenting:)`.
    private var captureErrorBinding: Binding<Bool> {
        Binding(get: { model.captureError != nil },
                set: { isPresented in if !isPresented { model.dismissCaptureError() } })
    }

    /// "已儲存"／"已取消" toast (PRD FR-5.4, 0.2 FR-7.6). Positioned above the
    /// bottom bar rather than inside the viewfinder, so it never competes
    /// with the overlay text for the same bottom-leading corner.
    @ViewBuilder
    private var toastOverlay: some View {
        if let toastState = model.toastState {
            ToastView(state: toastState)
                .padding(.leading, 16)
                .padding(.bottom, 96)
                .transition(.opacity)
                .animation(.easeInOut, value: toastState.id)
        }
    }
}

/// A three-by-three grid drawn over the viewfinder (PRD 0.2 FR-7.9) — display
/// only, never baked into the photo (`OverlayRenderer` never draws this).
private struct GridLinesView: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                for step in 1...2 {
                    let x = width * CGFloat(step) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                    let y = height * CGFloat(step) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.45), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

#Preview("3:4") {
    let store = ProfileStore()
    store.load()
    return CameraScreen(model: CameraScreenModel(cameraService: CameraService(), profileStore: store))
}

#Preview("1:1") {
    let store = ProfileStore()
    store.load()
    let settings = CaptureSettingsStore(defaults: UserDefaults(suiteName: "CameraScreen.preview.1x1") ?? .standard)
    settings.setAspectRatio(.oneByOne)
    let model = CameraScreenModel(cameraService: CameraService(),
                                  profileStore: store,
                                  captureSettingsStore: settings)
    return CameraScreen(model: model)
}

#Preview("9:16") {
    let store = ProfileStore()
    store.load()
    let settings = CaptureSettingsStore(defaults: UserDefaults(suiteName: "CameraScreen.preview.9x16") ?? .standard)
    settings.setAspectRatio(.nineBySixteen)
    let model = CameraScreenModel(cameraService: CameraService(),
                                  profileStore: store,
                                  captureSettingsStore: settings)
    return CameraScreen(model: model)
}

#Preview("疊字面板打開（22.6，對照 D-2）") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    model.panelModel.open()
    return CameraScreen(model: model)
}

#Preview("疊字面板打開・天數規則分頁") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    model.panelModel.open()
    model.panelModel.selectedTab = .rules
    return CameraScreen(model: model)
}
