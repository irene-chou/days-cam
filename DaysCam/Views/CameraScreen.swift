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
/// forces system chrome (this screen's own `.alert`s) light.
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

    /// Header, viewfinder box and footer, positioned from
    /// `CameraScreenLayoutMetrics` (issue #101): header and footer sit at
    /// fixed screen coordinates that never move when the aspect ratio (or
    /// the overlay panel) changes — only the viewfinder box between them
    /// does. `.ignoresSafeArea()` here (and nowhere else in this file) is
    /// what makes `proxy.size`/`proxy.safeAreaInsets` below describe the
    /// *whole* screen rather than an already safe-area-reduced one, which
    /// is exactly what `CameraScreenLayoutMetrics`'s formulas expect.
    private var content: some View {
        GeometryReader { proxy in
            let metrics = CameraScreenLayoutMetrics(screenSize: proxy.size, safeAreaInsets: proxy.safeAreaInsets)
            ZStack(alignment: .topLeading) {
                viewfinderBox(metrics: metrics)
                    .animation(CameraTheme.spring, value: model.panelModel.isOpen)

                headerBar(metrics: metrics)

                footerColumn(metrics: metrics)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Viewfinder box

    /// The viewfinder box's frame comes straight from `metrics`: 3:4 and
    /// 9:16 both start at the header's bottom edge (issue #101 rule ①); 1:1
    /// reuses the exact same 3:4-shaped box and lets its smaller square
    /// content center inside for free, since a `ZStack` centers a smaller
    /// child by default (rule ②, unchanged from before #101). While the
    /// overlay panel is open (PRD 0.2 FR-8.2), 3:4/1:1's box additionally
    /// scales to 80% width (height following, since the box keeps its 3:4
    /// shape) and centers horizontally — 9:16 is never shrunk (see
    /// `footerColumn`'s doc comment for why opening the panel at 9:16 is a
    /// separate, pre-existing special case, unchanged by this issue).
    private func viewfinderBox(metrics: CameraScreenLayoutMetrics) -> some View {
        let ratio = model.captureSettingsStore.captureAspectRatio
        let boxWidth = viewfinderBoxWidth(metrics: metrics, ratio: ratio)
        let rect = metrics.viewfinderFrame(for: ratio, boxWidth: boxWidth)
        let vfSize = viewfinderContentSize(for: ratio, boxSize: rect.size)
        return ZStack {
            viewfinderContent(frameSize: vfSize)
                .frame(width: vfSize.width, height: vfSize.height)
                .clipped()
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
    }

    /// The viewfinder box's on-screen width: shrunk to 80% while the panel
    /// is open (PRD 0.2 FR-8.2), full screen width otherwise. 9:16 is never
    /// shrunk. Shared by `viewfinderBox` and `footerColumn` — both need the
    /// exact same value, since `footerColumn` has to start right where the
    /// (possibly shrunk) box actually ends, not at the closed-panel box's
    /// unscaled bottom edge (code review finding on #101/#110: with the box
    /// shrunk to 80% width — and height following it, since the box stays
    /// 3:4-shaped — its bottom edge moves up by 20% of its height; anchoring
    /// the panel/bottom bar to the closed-panel `metrics.footerRegionTop`
    /// instead left a gap between the shrunk box and the panel).
    private func viewfinderBoxWidth(metrics: CameraScreenLayoutMetrics, ratio: CaptureAspectRatio) -> CGFloat {
        let fullWidth = metrics.screenSize.width
        return (ratio != .nineBySixteen && model.panelModel.isOpen) ? fullWidth * 0.8 : fullWidth
    }

    /// The on-screen size of the viewfinder itself within `boxSize` (which
    /// is always 3:4-shaped for 3:4/1:1, PRD 0.2 FR-7.8): unchanged for 3:4
    /// and 9:16, the box's width squared for 1:1.
    private func viewfinderContentSize(for ratio: CaptureAspectRatio, boxSize: CGSize) -> CGSize {
        switch ratio {
        case .threeByFour, .nineBySixteen:
            return boxSize
        case .oneByOne:
            return CGSize(width: boxSize.width, height: boxSize.width)
        }
    }

    // MARK: - Header

    /// The toolbar, vertically centered within the header region below the
    /// status bar (issue #101's own suggested approach — exact padding is
    /// #105's job). Solid background in every case except the one where the
    /// viewfinder still runs *behind* the header: 9:16's small-screen
    /// fallback (`metrics.isFallback`, issue #101 assumption 2), which
    /// reverts to the pre-#101 full-bleed look and needs the header legible
    /// over a live picture instead of `CameraTheme.background`.
    private func headerBar(metrics: CameraScreenLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: metrics.topInset)
            CameraToolbar(model: model)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: metrics.screenSize.width, height: metrics.headerBottom, alignment: .top)
        .background(headerBackground(metrics: metrics))
    }

    @ViewBuilder
    private func headerBackground(metrics: CameraScreenLayoutMetrics) -> some View {
        if isNineBySixteenFallback(metrics: metrics) {
            topFadeGradient
        } else {
            CameraTheme.background
        }
    }

    // MARK: - Footer

    /// Panel (if open) and the bottom bar, anchored to the bottom of a
    /// region that starts right where the viewfinder box's own bottom edge
    /// is and ends at `metrics.footerBase` (issue #101 rule ③ — the
    /// footer's own bottom edge is the home indicator's top, not the
    /// screen's physical bottom). Closed, that start is
    /// `metrics.footerRegionTop` (the *unscaled* 3:4 box's bottom) exactly
    /// as issue #101 fixed it — header/footer never move switching ratios,
    /// only the viewfinder does. Open, 3:4/1:1's box has shrunk to 80% width
    /// (`viewfinderBoxWidth`), and this region's start shrinks up right
    /// along with it (`footerRegionTop(boxWidth:)`) so the panel still
    /// starts flush against the box instead of leaving a gap (code review
    /// finding, #110) — 9:16's box is never shrunk, so its start never
    /// moves either way. Transparent for 3:4/1:1 (nothing draws behind it
    /// there — `CameraScreen`'s own root background already shows through);
    /// 9:16 floats this whole column over the viewfinder's bottom sliver
    /// behind a gradient, same as before #101 (PRD 0.2 FR-7.8).
    ///
    /// Assumption (carried over from before #101, out of this issue's
    /// scope per its own assumption 3): PRD 0.2 FR-8.2/D-2 only ever show
    /// the panel against a 3:4 viewfinder; opening it while at 9:16 has no
    /// documented layout, so it keeps floating over the bottom bar at a
    /// fixed height here rather than filling this region like 3:4/1:1 do.
    private func footerColumn(metrics: CameraScreenLayoutMetrics) -> some View {
        let ratio = model.captureSettingsStore.captureAspectRatio
        let isNineBySixteen = ratio == .nineBySixteen
        let boxWidth = viewfinderBoxWidth(metrics: metrics, ratio: ratio)
        let regionTop = metrics.footerRegionTop(boxWidth: boxWidth)
        return VStack(spacing: 0) {
            if model.panelModel.isOpen {
                if isNineBySixteen {
                    OverlayPanelView(model: model)
                        .frame(height: 220)
                        .transition(.opacity)
                } else {
                    OverlayPanelView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            bottomBar
        }
        .frame(width: metrics.screenSize.width,
               height: metrics.footerBase - regionTop,
               alignment: .bottom)
        .background(isNineBySixteen ? AnyView(bottomFadeGradient) : AnyView(Color.clear))
        .offset(x: 0, y: regionTop)
        .animation(CameraTheme.spring, value: model.panelModel.isOpen)
    }

    private func isNineBySixteenFallback(metrics: CameraScreenLayoutMetrics) -> Bool {
        model.captureSettingsStore.captureAspectRatio == .nineBySixteen && metrics.isFallback
    }

    private var topFadeGradient: some View {
        LinearGradient(colors: [CameraTheme.background.opacity(0.85), .clear],
                       startPoint: .top, endPoint: .bottom)
    }

    private var bottomFadeGradient: some View {
        LinearGradient(colors: [.clear, CameraTheme.background.opacity(0.9)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Viewfinder contents

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
                PermissionGuidanceView()
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

/// 驗收 L.7（issue #101）：iPhone 16 Pro Max 上規則同樣成立，header 下緣 ≈ 139.8。
#Preview("iPhone 16 Pro Max・3:4（L.7）") {
    let store = ProfileStore()
    store.load()
    return CameraScreen(model: CameraScreenModel(cameraService: CameraService(), profileStore: store))
        .previewDevice("iPhone 16 Pro Max")
}

/// 驗收 L.8（issue #101）：iPhone SE 退回最小 header 高度（66pt），不破版。
#Preview("iPhone SE・3:4（L.8，假設 2 退回）") {
    let store = ProfileStore()
    store.load()
    return CameraScreen(model: CameraScreenModel(cameraService: CameraService(), profileStore: store))
        .previewDevice("iPhone SE (3rd generation)")
}

/// 驗收 L.8：iPhone SE 的 9:16 退回現況（鋪滿、header 浮在上面）。
#Preview("iPhone SE・9:16（L.8，假設 2 退回）") {
    let store = ProfileStore()
    store.load()
    let settings = CaptureSettingsStore(defaults: UserDefaults(suiteName: "CameraScreen.preview.se.9x16") ?? .standard)
    settings.setAspectRatio(.nineBySixteen)
    let model = CameraScreenModel(cameraService: CameraService(),
                                  profileStore: store,
                                  captureSettingsStore: settings)
    return CameraScreen(model: model)
        .previewDevice("iPhone SE (3rd generation)")
}
