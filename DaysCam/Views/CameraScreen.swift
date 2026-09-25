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
            .sheet(isPresented: displaySettingsBinding) {
                // `model.displaySettingsModel` is the instance cached when the
                // sheet opened, not rebuilt on every access — see its own doc
                // comment for why that matters.
                //
                // TEMP(TASK-21→22): this is 0.1's display-settings sheet,
                // reused as a placeholder for the bottom bar's "Aa" key —
                // TASK-22 replaces it with the real overlay panel (PRD 0.2
                // FR-8). Kept only so the key does *something* in the
                // meantime; its own theme (system default, not `CameraTheme`)
                // is intentionally left alone since it is being deleted, not
                // restyled.
                if let displaySettingsModel = model.displaySettingsModel {
                    DisplaySettingsSheet(model: displaySettingsModel)
                }
            }
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

    /// The viewfinder sits in a box fixed to 3:4 regardless of the selected
    /// ratio, so the toolbar and bottom bar never move when switching ratios
    /// (only what's *inside* the box changes). At 1:1 the inner square
    /// centers vertically within that box (PRD 0.2 FR-7.8) — for free, since
    /// a `ZStack` centers a smaller child by default.
    private var standardLayout: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let vfSize = viewfinderSize(in: proxy.size)
                ZStack {
                    viewfinderContent(frameSize: vfSize)
                        .frame(width: vfSize.width, height: vfSize.height)
                        .clipped()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { CameraToolbar(model: model) }

            bottomBar
        }
    }

    /// The on-screen size of the viewfinder itself within a `containerSize`
    /// box that is always 3:4 (PRD 0.2 FR-7.8): unchanged for 3:4, the full
    /// width squared for 1:1. Never called for 9:16 — that ratio uses
    /// `fullBleedLayout` instead, not this box.
    private func viewfinderSize(in containerSize: CGSize) -> CGSize {
        switch model.captureSettingsStore.captureAspectRatio {
        case .threeByFour:
            return containerSize
        case .oneByOne:
            return CGSize(width: containerSize.width, height: containerSize.width)
        case .nineBySixteen:
            return containerSize
        }
    }

    // MARK: - 9:16 layout

    /// Fills the screen edge to edge; the toolbar and bottom bar float over
    /// it, each behind a gradient fading to `CameraTheme.background` so they
    /// stay legible over whatever the camera is pointed at (PRD 0.2 FR-7.8,
    /// D-1).
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
                    bottomBar
                        .background(bottomFadeGradient.ignoresSafeArea(edges: .bottom))
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
            // the eventual baked photo agree.
            OverlayTextView(text: model.overlayText,
                            style: model.overlayStyle,
                            placement: model.overlayPlacement,
                            frameSize: frameSize)

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

    // MARK: - Bottom bar (PRD 0.2 FR-7.3)

    /// Left: latest-photo thumbnail (FR-15.2). Center: shutter. Right: "Aa"
    /// overlay key. No text labels, no background — every button is just an
    /// icon (FR-14.2).
    private var bottomBar: some View {
        ZStack {
            HStack {
                Spacer()
                shutterButton
                Spacer()
            }
            HStack {
                thumbnailButton
                Spacer()
                overlayKeyButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    /// Left key: the newest DaysCam photo, or a placeholder icon (PRD 0.2
    /// FR-15.2). Tapping it does nothing yet — TASK-29 wires up requesting
    /// read access and opening the gallery.
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
    /// background (the `accent` circle) plus a ring, matching D-1.
    private var shutterButton: some View {
        Button(action: model.capturePhoto) {
            ZStack {
                Circle()
                    .strokeBorder(CameraTheme.shutterRing, lineWidth: 4)
                Circle()
                    .fill(CameraTheme.accent)
                    .padding(4)
            }
            .frame(width: 76, height: 76)
        }
        .disabled(model.isShutterDisabled)
        .opacity(model.isShutterDisabled ? 0.4 : 1)
        .accessibilityLabel("快門")
    }

    /// Right key: opens the overlay entry point. Still 0.1's display-settings
    /// sheet until TASK-22 lands the real panel — see the `TEMP` note on the
    /// `.sheet` above.
    private var overlayKeyButton: some View {
        Button {
            model.presentDisplaySettings()
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(CameraTheme.ink)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("疊字設定")
    }

    // MARK: - Bindings

    /// `model.isDisplaySettingsPresented` as a `Binding` for `.sheet`:
    /// dismissing the sheet (swipe-down, tapping outside) must also clear the
    /// model's state, not just the SwiftUI-owned presentation flag — same
    /// pattern as `ProfileListView.editorBinding`.
    private var displaySettingsBinding: Binding<Bool> {
        Binding(get: { model.isDisplaySettingsPresented },
                set: { isPresented in if !isPresented { model.dismissDisplaySettings() } })
    }

    /// `model.showsCorruptionRecoveredAlert` as a `Binding` for `.alert`, same
    /// dismiss-clears-model-state pattern as `displaySettingsBinding`.
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
