import SwiftUI

/// The camera (PRD 2.0 FR-20, D9), full screen over the photo wall that
/// opened it.
///
/// Composes the viewfinder, the permission guidance screen, the top bar
/// with the record switcher and its menu, the shutter, the newest-photo
/// button (「返回圖庫」) and the failure alert. No overlay is drawn yet (the
/// preview is #656): the photo is saved as taken and the overlay is added
/// only on export (§6.3). All state and decisions live in
/// `CameraScreenModel`; this view only lays it out.
///
/// Fixed light theme (PRD 0.2 FR-14.1): every color here comes from
/// `CameraTheme`, plus `.preferredColorScheme(.light)` at the root. The one
/// exception is `PermissionGuidanceView`, which follows the system
/// appearance itself (see its own doc comment).
struct CameraScreen: View {
    @ObservedObject var model: CameraScreenModel
    /// Back to the photo wall (FR-20.1, FR-20.11): the newest-photo button
    /// and a swipe down both call it. The caller reads
    /// `model.selectedProfileID` to know which record's wall to show.
    var onClose: () -> Void

    /// The viewfinder always shows the sensor's own 3:4 picture: nothing is
    /// cropped any more, so the user sees all of what is saved (#621).
    static let viewfinderRatio: CaptureAspectRatio = .threeByFour

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// What the thumbnail button currently shows; follows
    /// `model.latestThumbnailImage` (see `showThumbnail`).
    @State private var shownThumbnail: UIImage?

    /// The viewfinder's white shutter flash (issue #148): 0 → 90% → 0 over
    /// ~0.15s, softer under Reduce Motion.
    @State private var flashOpacity: Double = 0

    /// True while a finger is down on the viewfinder; SwiftUI resets it when a
    /// gesture is cancelled too, which `onEnded` does not report (issue #303).
    @GestureState private var isViewfinderTouched = false

    /// How far a swipe down to close has pulled the screen (FR-20.11).
    @GestureState private var dismissDragOffset: CGFloat = 0

    var body: some View {
        content
            .background(CameraTheme.background.ignoresSafeArea())
            .preferredColorScheme(.light)
            .onChange(of: model.captureTriggerCount) { _, _ in playShutterFlash() }
            // Light haptic on the same trigger (issue #148); the simulator
            // has no haptics, so this call site is the thing to check.
            .sensoryFeedback(.impact(weight: .light), trigger: model.captureTriggerCount)
            .onAppear { model.onAppear() }
            .task { await model.loadLatestThumbnail() }
            .onChange(of: scenePhase) { _, phase in
                // The camera is back to continuous auto (issue #303).
                if phase == .active { model.focusModel.hideReticle() }
            }
            // #621-9: closing the camera really stops the session.
            .onDisappear { model.onDisappear() }
            .overlay(alignment: .bottomLeading) { toastOverlay }
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
    /// `CameraScreenLayoutMetrics` (issue #101).
    ///
    /// The reader deliberately gets the reduced-size-plus-insets pairing
    /// (nothing in its ancestor chain ignores the safe area) and adds the
    /// insets back to reconstruct the full screen size; `.ignoresSafeArea()`
    /// is applied only to the `ZStack` it returns, so the content still
    /// extends full-bleed without affecting what the reader measured (#101,
    /// `CameraScreenSafeAreaLayoutTests`).
    private var content: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let screenSize = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                    height: proxy.size.height + insets.top + insets.bottom)
            let metrics = CameraScreenLayoutMetrics(screenSize: screenSize, safeAreaInsets: insets)
            ZStack(alignment: .topLeading) {
                tapOutsideLayer(metrics: metrics)

                viewfinderBox(metrics: metrics)

                zoomPresetBar(metrics: metrics)

                headerBar(metrics: metrics)

                footer(metrics: metrics)

                toolsCapsule(metrics: metrics)

                recordMenu(metrics: metrics)

                captureFlights(metrics: metrics)
            }
            .ignoresSafeArea()
            .offset(y: dismissDragOffset)
            .animation(CameraTheme.spring, value: model.isCameraToolsExpanded)
            .animation(CameraTheme.spring, value: model.isRecordMenuOpen)
        }
    }

    /// The bottom-most layer: a tap on blank space closes the capsules and
    /// the record menu; a swipe down from it closes the camera. Hidden from
    /// VoiceOver.
    private func tapOutsideLayer(metrics: CameraScreenLayoutMetrics) -> some View {
        Color.clear
            .frame(width: metrics.screenSize.width, height: metrics.screenSize.height)
            .contentShape(Rectangle())
            .onTapGesture { model.handleViewfinderTap() }
            .simultaneousGesture(dismissDrag)
            .accessibilityHidden(true)
    }

    // MARK: - Swipe down to close (FR-20.11)

    /// A swipe down that starts outside the viewfinder (the top bar, the
    /// bottom bar or blank space) closes the camera like the newest-photo
    /// button. The viewfinder has none, so its tap, exposure drag and pinch
    /// never close anything. Measured globally: the screen follows the
    /// finger down while it moves.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: CameraScreenLayoutMetrics.dismissSwipeMinimumDistance,
                    coordinateSpace: .global)
            .updating($dismissDragOffset) { value, offset, _ in
                offset = max(0, value.translation.height)
            }
            .onEnded { value in
                if CameraScreenLayoutMetrics.isDismissSwipe(translation: value.translation,
                                                            predictedEndTranslation: value.predictedEndTranslation) {
                    onClose()
                }
            }
    }

    // MARK: - Viewfinder box

    /// The picture's rectangle in screen coordinates — where a capture flight
    /// starts (issue #148).
    private func viewfinderFrame(metrics: CameraScreenLayoutMetrics) -> CGRect {
        metrics.viewfinderFrame(for: Self.viewfinderRatio, boxWidth: metrics.screenSize.width)
    }

    private func viewfinderBox(metrics: CameraScreenLayoutMetrics) -> some View {
        let frame = viewfinderFrame(metrics: metrics)
        return viewfinderContent(frameSize: frame.size)
            .frame(width: frame.width, height: frame.height)
            .overlay(
                CameraTheme.shutterFlash
                    .opacity(flashOpacity)
                    .allowsHitTesting(false)
            )
            .clipped()
            .offset(x: frame.minX, y: frame.minY)
    }

    // MARK: - Header

    /// The toolbar, vertically centered within the header region below the
    /// status bar; the record switcher sits in its middle (FR-20.7). A swipe
    /// down from here closes the camera.
    private func headerBar(metrics: CameraScreenLayoutMetrics) -> some View {
        let isOnPhoto = metrics.isViewfinderBehindHeader(ratio: Self.viewfinderRatio, isPanelOpen: false)
        return VStack(spacing: 0) {
            Spacer().frame(height: metrics.topInset)
            CameraToolbar(model: model, isOnPhoto: isOnPhoto)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: metrics.screenSize.width, height: metrics.headerBottom, alignment: .top)
        .contentShape(Rectangle())
        .simultaneousGesture(dismissDrag)
    }

    // MARK: - Shutter flash (issue #148)

    private func playShutterFlash() {
        let peak = reduceMotion ? 0.35 : 0.9
        let rise = reduceMotion ? 0.1 : 0.04
        withAnimation(.easeOut(duration: rise)) { flashOpacity = peak }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(rise * 1_000_000_000))
            withAnimation(.easeIn(duration: 0.11)) { flashOpacity = 0 }
        }
    }

    // MARK: - Capture flights (issue #148)

    /// Topmost layer: each captured photo lifts off the viewfinder and flies
    /// into the newest-photo button. Never takes touches.
    private func captureFlights(metrics: CameraScreenLayoutMetrics) -> some View {
        let start = viewfinderFrame(metrics: metrics)
        let target = metrics.leftFooterButtonCenter
        let end = CGRect(x: target.x - Self.footerButtonSize / 2, y: target.y - Self.footerButtonSize / 2,
                         width: Self.footerButtonSize, height: Self.footerButtonSize)
        return ZStack(alignment: .topLeading) {
            ForEach(model.captureFlights) { flight in
                CaptureFlightView(flight: flight, start: start, end: end, skipsFlightWhenPanelOpen: false,
                                  onLanded: { model.flightDidLand(id: flight.id) },
                                  onFinished: { model.removeCaptureFlight(id: flight.id) })
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Tools capsule (issue #135)

    /// Floats above the viewfinder, right-aligned with the toggle button
    /// (inside the flip button at the top right) and 4pt below it (FR-20.7,
    /// D9).
    @ViewBuilder
    private func toolsCapsule(metrics: CameraScreenLayoutMetrics) -> some View {
        if model.isCameraToolsExpanded {
            let inset = CameraScreenLayoutMetrics.toolbarHorizontalInset
            let trailing = CameraScreenLayoutMetrics.toolsCapsuleTrailingInset
            CameraToolsCapsule(model: model)
                .frame(width: metrics.screenSize.width - inset - trailing, alignment: .trailing)
                .offset(x: inset, y: metrics.toolsCapsuleTop)
                .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    // MARK: - Record menu (FR-20.8)

    /// The record switcher's menu, centered under it, 4pt below the top
    /// bar's buttons (D9).
    @ViewBuilder
    private func recordMenu(metrics: CameraScreenLayoutMetrics) -> some View {
        if model.isRecordMenuOpen {
            let width = RecordSwitcherMenu.width(forScreenWidth: metrics.screenSize.width)
            RecordSwitcherMenu(model: model)
                .frame(width: width)
                .offset(x: (metrics.screenSize.width - width) / 2, y: metrics.toolsCapsuleTop)
                .transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
        }
    }

    // MARK: - Footer

    /// The bottom bar, anchored to the bottom of the region between
    /// `metrics.footerRegionTop` and `metrics.footerBase` (issue #101 rule
    /// ③). Always a transparent background (issue #121). A swipe down from
    /// here closes the camera.
    private func footer(metrics: CameraScreenLayoutMetrics) -> some View {
        let isOnPhoto = metrics.isViewfinderBehindFooter(ratio: Self.viewfinderRatio, isPanelOpen: false)
        return bottomBar(metrics: metrics, isOnPhoto: isOnPhoto)
            .frame(width: metrics.screenSize.width,
                   height: metrics.footerBase - metrics.footerRegionTop,
                   alignment: .bottom)
            .contentShape(Rectangle())
            .simultaneousGesture(dismissDrag)
            .offset(x: 0, y: metrics.footerRegionTop)
    }

    // MARK: - Viewfinder contents

    /// Everything drawn inside the viewfinder box, sized to `frameSize`: the
    /// live preview (or placeholder), the optional grid (never saved), the
    /// focus reticle, the countdown's big number (FR-7.6), the transient
    /// status message and the permission guidance screen. No overlay text,
    /// no film date (FR-20.2).
    @ViewBuilder
    private func viewfinderContent(frameSize: CGSize) -> some View {
        let rotation = model.viewfinderRotation
        ZStack {
            if model.showsPlaceholder {
                placeholderBackground
            } else {
                // Sized to exactly `frameSize`; never `.ignoresSafeArea()`.
                CameraPreviewView(session: model.cameraService.session, bridge: model.focusModel.previewBridge)
            }

            if model.captureSettingsStore.showsGrid {
                GridLinesView()
            }

            // Tap-to-focus reticle, exposure sun and AE/AF lock label
            // (issue #303); never takes touches.
            FocusExposureOverlay(focus: model.focusModel, frameSize: frameSize, rotation: rotation)

            if let countdownRemaining = model.countdownRemaining {
                Text("\(countdownRemaining)")
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                    .rotationEffect(.degrees(rotation.degrees))
                    .animation(reduceMotion ? nil : CameraTheme.spring, value: rotation)
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
        .frame(width: frameSize.width, height: frameSize.height)
        .contentShape(Rectangle())
        .onTapGesture {
            model.handleViewfinderTap()
        }
        // Tap to focus, drag up/down for exposure, hold to lock AE/AF (issue
        // #303). One zero-distance drag tracks the finger and the model
        // tells the three apart; it ignores touches while a capsule is open
        // and while two fingers pinch. Simultaneous, so the pinch and the
        // tap above keep working.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isViewfinderTouched) { _, state, _ in state = true }
                .onChanged {
                    model.focusModel.touchChanged(startLocation: $0.startLocation, location: $0.location,
                                                  viewfinderSize: frameSize)
                }
                .onEnded { _ in model.focusModel.touchEnded() }
        )
        .onChange(of: isViewfinderTouched) { _, touched in
            if !touched { model.focusModel.touchCancelled() }
        }
        // Pinch to zoom (TASK-61, #274).
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { model.zoomModel.pinchChanged(magnification: $0.magnification) }
                .onEnded { _ in model.zoomModel.pinchEnded() }
        )
    }

    // MARK: - Zoom presets (issue #279)

    /// The quick-zoom round button in the picture's bottom-right corner;
    /// hidden while the camera offers no preset.
    private func zoomPresetBar(metrics: CameraScreenLayoutMetrics) -> some View {
        ZoomPresetBar(zoom: model.zoomModel,
                      expansion: model.zoomExpansion,
                      presets: model.zoomPresets,
                      isVisible: !model.zoomPresets.isEmpty,
                      pictureFrame: viewfinderFrame(metrics: metrics),
                      rotation: model.viewfinderRotation)
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

    // MARK: - Bottom bar (FR-20.5, FR-20.11)

    /// Newest photo with 「返回圖庫」 under it at the left, the shutter in the
    /// middle, nothing at the right (FR-20.7, D9). No background (PRD 0.2
    /// FR-14.2).
    ///
    /// The thumbnail's center sits `footerSideButtonCenterInset` from the
    /// left edge, level with the shutter's; the row sits 16pt above the
    /// bottom of the footer region.
    private func bottomBar(metrics: CameraScreenLayoutMetrics, isOnPhoto: Bool) -> some View {
        let sideInset = metrics.footerSideButtonCenterInset - Self.footerButtonSize / 2
        return ZStack {
            shutterButton
            HStack {
                thumbnailButton(isOnPhoto: isOnPhoto)
                Spacer()
            }
            .padding(.horizontal, sideInset)
        }
        .padding(.bottom, CameraScreenLayoutMetrics.closedFooterBottomPadding)
    }

    /// Tap target and size of the newest-photo button (FR-20.5).
    private static let footerButtonSize: CGFloat = 44

    /// Icon point size of the placeholder (issue #239).
    private static let footerIconSize: CGFloat = 24

    /// Left key: the selected record's newest photo, or a placeholder icon
    /// before it has one, with 「返回圖庫」 under it. Tapping either goes back
    /// to the photo wall (FR-20.11). The label hangs below the 44pt tile so
    /// the tile stays level with the shutter, where flights land.
    private func thumbnailButton(isOnPhoto: Bool) -> some View {
        Button(action: onClose) {
            Group {
                if let image = shownThumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: Self.footerIconSize, weight: .medium))
                        .foregroundColor(isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink)
                        .legibleOverPhoto(isOnPhoto)
                }
            }
            .frame(width: Self.footerButtonSize, height: Self.footerButtonSize)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .rotatedChrome(model.viewfinderRotation)
            // Only Reduce Motion crossfades the swap (issue #148 S.8); an
            // animated if/else left the old icon fading out behind the photo.
            .onAppear { shownThumbnail = model.latestThumbnailImage }
            .onChange(of: model.latestThumbnailImage) { _, image in showThumbnail(image) }
            .overlay(alignment: .bottom) {
                Text("返回圖庫")
                    .font(CameraTheme.toolFont(.caption2))
                    .foregroundColor(isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.inkSecondary)
                    .legibleOverPhoto(isOnPhoto)
                    .fixedSize()
                    .alignmentGuide(.bottom) { $0[.top] - Self.backLabelGap }
            }
        }
        .modifier(ThumbnailLandingEffect(landingCount: model.thumbnailLandingCount))
        .accessibilityLabel("返回圖庫")
        .accessibilityIdentifier("cameraLatestThumbnail")
    }

    /// Gap between the thumbnail and 「返回圖庫」 under it (D9).
    private static let backLabelGap: CGFloat = 4

    private func showThumbnail(_ image: UIImage?) {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { shownThumbnail = image }
        } else {
            shownThumbnail = image
        }
    }

    /// Center: the shutter — the one place PRD 0.2 FR-14.2 allows a filled
    /// background (the `accent` circle) plus a ring.
    private var shutterButton: some View {
        let diameter: CGFloat = 76
        let ringWidth: CGFloat = 4
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

    /// `model.captureError` as a `Binding<Bool>` for `.alert(isPresented:presenting:)`.
    private var captureErrorBinding: Binding<Bool> {
        Binding(get: { model.captureError != nil },
                set: { isPresented in if !isPresented { model.dismissCaptureError() } })
    }

    /// "已取消" (0.2 FR-7.6) and "改存到「…」" (FR-20.8) toasts, above the
    /// bottom bar.
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
/// only, never saved.
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

@MainActor
private func previewCameraModel() -> CameraScreenModel {
    let store = ProfileStore()
    store.load()
    let id = store.profiles.first?.id ?? UUID()
    return CameraScreenModel(cameraService: CameraService(), profileStore: store, profileID: id)
}

#Preview("相機") {
    CameraScreen(model: previewCameraModel(), onClose: {})
}

/// 驗收 C.2（issue #135）：膠囊展開。
#Preview("相機設定膠囊展開") {
    let model = previewCameraModel()
    model.toggleCameraTools()
    return CameraScreen(model: model, onClose: {})
}
