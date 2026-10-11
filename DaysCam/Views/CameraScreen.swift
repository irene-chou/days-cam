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
/// exception is `PermissionGuidanceView` (human decision 2026-09-27),
/// which follows the system appearance instead — it does *not* try to
/// escape this root's `.preferredColorScheme(.light)` by setting it back
/// to `nil` on itself, since that does not actually cancel an ancestor's
/// value (confirmed in `ColorSchemeEscapeTests`, PR #103 review); instead
/// it reads the real system appearance itself and applies it as an
/// `Environment(\.colorScheme)` override, which does reliably escape.
struct CameraScreen: View {
    @ObservedObject var model: CameraScreenModel

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

    /// The panel's segmented control height, scaled with Dynamic Type
    /// (issue #139); fed to the layout metrics so the viewfinder yields the
    /// extra height.
    @ScaledMetric(relativeTo: .footnote) private var panelTabBarHeight = CameraScreenLayoutMetrics.defaultPanelTabBarHeight

    var body: some View {
        content
            .background(CameraTheme.background.ignoresSafeArea())
            .preferredColorScheme(.light)
            .onChange(of: model.captureTriggerCount) { _, _ in playShutterFlash() }
            // Light haptic on the same trigger (issue #148); the simulator
            // has no haptics, so this call site is the thing to check.
            .sensoryFeedback(.impact(weight: .light), trigger: model.captureTriggerCount)
            .onAppear { model.onAppear() }
            // FR-15.2 second branch: only reads when access is already granted.
            .task { await model.loadLaunchThumbnail() }
            // PRD 0.3 FR-5.15: settle the fonts on the device, the current
            // profile's first; the shutter waits for it (at most 3 seconds).
            .task { await model.prepareFontsAtLaunch() }
            // FR-16.11: downloads do not continue in the background.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.sceneDidEnterBackground() }
                // The camera is back to continuous auto (issue #303).
                if phase == .active { model.focusModel.hideReticle() }
            }
            .onChange(of: model.panelModel.isOpen) { _, isOpen in
                if isOpen { model.focusModel.hideReticle() }
            }
            .onDisappear { model.onDisappear() }
            // TASK-101 (#410): no close key — swiping the sheet down or tapping
            // outside it is the way out, so the model's dismiss runs from
            // `onDismiss` (the same thing the key used to call).
            .sheet(isPresented: $model.isProfileManagerPresented, onDismiss: { model.dismissProfileManagement() }) {
                ProfileManagerView(model: model.profileManagerModel) {
                    model.dismissProfileManagement()
                }
                .presentationDetents([.fraction(0.68)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                // TASK-103 (#412): drags inside the content scroll the list
                // (and reach the rows' swipe actions) instead of resizing or
                // dismissing the sheet; the sheet still comes down from its
                // drag indicator, or from the list once it is at the top.
                .presentationContentInteraction(.scrolls)
            }
            .fullScreenCover(isPresented: $model.isGalleryPresented) {
                if let galleryModel = model.galleryModel {
                    GalleryView(model: galleryModel) { model.dismissGallery() }
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
    /// does.
    ///
    /// Regression fix, #101 reopened after qa found it live on every real
    /// device tested: a `GeometryReader` that has `.ignoresSafeArea()`
    /// applied *anywhere in its own ancestor chain* — directly on it, or on
    /// any view wrapping it, not just a descendant — reports its own
    /// `proxy.safeAreaInsets` as zero (it now considers the safe area its
    /// own responsibility to have already handled) *and* its `proxy.size`
    /// grows to the full screen. A `GeometryReader` that instead has
    /// nothing in its ancestor chain ignoring the safe area gets the
    /// opposite pairing: a `proxy.size` already *reduced* by the safe area,
    /// alongside the real, non-zero insets that were subtracted from it.
    /// Neither pairing alone gives what `CameraScreenLayoutMetrics` needs —
    /// a full-screen size *and* the real insets, together — so this reader
    /// deliberately takes the second (reduced-size) pairing and adds the
    /// insets back to reconstruct the full screen size itself
    /// (`screenSize` below); `.ignoresSafeArea()` is applied only to the
    /// `ZStack` this reader's own closure returns, a descendant with no
    /// further descendants of its own reading `GeometryProxy`, so it can
    /// still visually extend full-bleed without affecting what this reader
    /// itself measured. (In the simulator/preview this went unnoticed —
    /// `CameraScreenLayoutMetricsTests` covers the formulas directly with
    /// hand-supplied insets, not this wiring — but on a real device/full
    /// app run the header ended up 34pt/20pt too low on every size tested,
    /// dropping the iPhone 16 shutter into the home indicator's gesture
    /// area. `CameraScreenSafeAreaLayoutTests` now hosts real views in a
    /// real `UIWindow` to catch this class of bug, including this exact
    /// reduced-size-plus-insets reconstruction.)
    private var content: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let screenSize = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                    height: proxy.size.height + insets.top + insets.bottom)
            let metrics = CameraScreenLayoutMetrics(screenSize: screenSize, safeAreaInsets: insets,
                                                  panelTabBarHeight: panelTabBarHeight)
            ZStack(alignment: .topLeading) {
                tapOutsidePanelLayer(metrics: metrics)

                viewfinderBox(metrics: metrics)
                    .animation(CameraTheme.spring, value: model.panelModel.isOpen)

                zoomPresetBar(metrics: metrics)

                headerBar(metrics: metrics)

                footerColumn(metrics: metrics)

                toolsCapsule(metrics: metrics)

                captureFlights(metrics: metrics)
            }
            .ignoresSafeArea()
            .animation(CameraTheme.spring, value: model.isCameraToolsExpanded)
            // TASK-96: the tour overlay below declares itself modal, so while
            // it is up VoiceOver skips everything under its mask (96.10).
            // (An `.accessibilityHidden(isActive)` here instead — even while
            // false — made the viewfinder's focus/exposure accessibility
            // values stop updating, breaking FocusExposureUITests.)
            .overlayPreferenceValue(OnboardingTargetKey.self) { anchors in
                onboardingOverlay(anchors: anchors, metrics: metrics)
            }
        }
    }

    // MARK: - First-launch spotlight (TASK-96, #400)

    /// The two-step tour over everything else, on a fresh install once the
    /// camera permission prompt has been answered (`OnboardingSpotlightModel`
    /// decides when). The holes follow the published bounds of the
    /// highlighted button and, on step 2, the day-count text; the step
    /// change moves them with `CameraTheme.spring`, or instantly under
    /// Reduce Motion (96.11).
    @ViewBuilder
    private func onboardingOverlay(anchors: [OnboardingTarget: Anchor<CGRect>],
                                   metrics: CameraScreenLayoutMetrics) -> some View {
        if let step = model.onboarding.step {
            GeometryReader { proxy in
                let frame = anchors[step.target].map { proxy[$0] } ?? .zero
                let secondary = step.secondaryTarget.flatMap { anchors[$0] }.map { proxy[$0] }
                OnboardingSpotlightView(step: step,
                                        targetFrame: frame,
                                        overlayTextFrame: secondary,
                                        screenSize: metrics.screenSize,
                                        targetLabel: onboardingTargetLabel(step.target),
                                        onAdvance: {
                                            withAnimation(reduceMotion ? nil : CameraTheme.spring) {
                                                model.onboarding.advance()
                                            }
                                        },
                                        onTargetTap: { model.onboardingTargetTapped(step.target) },
                                        onEscape: { model.onboarding.finish() })
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    /// The real button's accessibility label, repeated on the tour's proxy
    /// over it so VoiceOver reads the same thing (96.10).
    private func onboardingTargetLabel(_ target: OnboardingTarget) -> String {
        switch target {
        case .profileChip: return "設定檔：\(model.currentProfileName)"
        case .overlayPanelButton: return "疊字設定"
        case .overlayText: return model.overlayText
        }
    }

    // MARK: - Tap outside the panel (TASK-97, #401)

    /// The bottom-most layer while the panel is open: a full-screen, invisible
    /// tap target, so a tap on any blank space — beside the viewfinder, in
    /// the gap above the panel, between the toolbar's buttons — collapses
    /// the panel the way a tap on the viewfinder does (PRD 0.2 FR-8.7).
    /// Everything with its own hit area (the viewfinder and its overlay
    /// text, the toolbar's buttons, the panel) sits above it and wins, so
    /// those keep their own behavior; nothing is here while the panel is
    /// closed (97.9). Hidden from VoiceOver (97.10).
    @ViewBuilder
    private func tapOutsidePanelLayer(metrics: CameraScreenLayoutMetrics) -> some View {
        if model.panelModel.isOpen {
            Color.clear
                .frame(width: metrics.screenSize.width, height: metrics.screenSize.height)
                .contentShape(Rectangle())
                .onTapGesture { model.handleTapOutsidePanel() }
                .accessibilityHidden(true)
        }
    }

    // MARK: - Viewfinder box

    /// The box's frame in screen coordinates for the current ratio/panel state.
    private func viewfinderBoxFrame(metrics: CameraScreenLayoutMetrics) -> CGRect {
        model.panelModel.isOpen
            ? metrics.panelOpenViewfinderFrame(for: model.captureSettingsStore.captureAspectRatio)
            : metrics.viewfinderFrame(for: model.captureSettingsStore.captureAspectRatio, boxWidth: metrics.screenSize.width)
    }

    /// The picture's own rectangle (the content centered in the box) in screen
    /// coordinates — where a capture flight starts (issue #148).
    private func viewfinderContentFrame(metrics: CameraScreenLayoutMetrics) -> CGRect {
        let box = viewfinderBoxFrame(metrics: metrics)
        let size = metrics.viewfinderContentSize(for: model.captureSettingsStore.captureAspectRatio,
                                                 boxSize: box.size,
                                                 isPanelOpen: model.panelModel.isOpen)
        return CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Closed, the box's frame comes straight from `metrics`: 3:4 and 9:16
    /// both start at the header's bottom edge (issue #101 rule ①); 1:1 reuses
    /// the same 3:4-shaped box and its smaller square content centers inside
    /// (rule ②). Open (TASK-98, #402, superseding #128's shared 3:4 box),
    /// each ratio gets its own frame fitted to the area between the header
    /// and the panel (`metrics.panelOpenViewfinderFrame(for:)`): a picture
    /// that already fits keeps its closed size, the rest shrink until their
    /// height is the area's; 3:4 and 9:16 land where they always did.
    ///
    /// Issue #153: the content is always laid out at its panel-closed size and
    /// only scaled about its own center (and moved) while the panel is open,
    /// so the camera preview's UIKit layer scales with it instead of jumping
    /// to the final size, pinned top-left, while the spring still runs. A
    /// picture that fits keeps scale 1 and only moves.
    private func viewfinderBox(metrics: CameraScreenLayoutMetrics) -> some View {
        let placement = metrics.viewfinderPlacement(for: model.captureSettingsStore.captureAspectRatio,
                                                    isPanelOpen: model.panelModel.isOpen)
        let size = placement.layoutSize
        return viewfinderContent(frameSize: size)
            .frame(width: size.width, height: size.height)
            .overlay(
                CameraTheme.shutterFlash
                    .opacity(flashOpacity)
                    .allowsHitTesting(false)
            )
            .clipped()
            .scaleEffect(x: placement.scale.width, y: placement.scale.height, anchor: .center)
            .offset(x: placement.center.x - size.width / 2, y: placement.center.y - size.height / 2)
    }

    // MARK: - Header

    /// The toolbar, vertically centered within the header region below the
    /// status bar (issue #101's own suggested approach — exact padding is
    /// #105's job). Always a transparent background (issue #121 — this used
    /// to fade to `CameraTheme.background` behind the one case where the
    /// viewfinder runs behind the header, 9:16's small-screen fallback,
    /// `metrics.isFallback`; human decision 2026-09-28 dropped every such
    /// gradient in favor of the toolbar's own icons simply switching to a
    /// light color when they need to stay legible over a photo instead,
    /// via `CameraScreenLayoutMetrics.isViewfinderBehindHeader` —
    /// `CameraToolbar.isOnPhoto` below).
    private func headerBar(metrics: CameraScreenLayoutMetrics) -> some View {
        let isOnPhoto = metrics.isViewfinderBehindHeader(ratio: model.captureSettingsStore.captureAspectRatio,
                                                         isPanelOpen: model.panelModel.isOpen)
        return VStack(spacing: 0) {
            Spacer().frame(height: metrics.topInset)
            CameraToolbar(model: model, isOnPhoto: isOnPhoto)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: metrics.screenSize.width, height: metrics.headerBottom, alignment: .top)
        .background(Color.clear)
        .animation(CameraTheme.spring, value: isOnPhoto)
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
    /// into the thumbnail button. Never takes touches. While the panel is
    /// open there is no footer row to land on (TASK-92), so the flight is
    /// skipped (`skipsFlightWhenPanelOpen`) and the thumbnail just updates;
    /// `end` is the closed footer's thumbnail either way.
    private func captureFlights(metrics: CameraScreenLayoutMetrics) -> some View {
        let isOpen = model.panelModel.isOpen
        let start = viewfinderContentFrame(metrics: metrics)
        let target = metrics.leftFooterButtonCenter
        let end = CGRect(x: target.x - Self.footerButtonSize / 2, y: target.y - Self.footerButtonSize / 2,
                         width: Self.footerButtonSize, height: Self.footerButtonSize)
        return ZStack(alignment: .topLeading) {
            ForEach(model.captureFlights) { flight in
                CaptureFlightView(flight: flight, start: start, end: end, skipsFlightWhenPanelOpen: isOpen,
                                  onLanded: { model.flightDidLand(id: flight.id) },
                                  onFinished: { model.removeCaptureFlight(id: flight.id) })
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Tools capsule (issue #135)

    /// Floats above the viewfinder, left-aligned with the toolbar's own
    /// inset and 4pt below the toggle button.
    @ViewBuilder
    private func toolsCapsule(metrics: CameraScreenLayoutMetrics) -> some View {
        if model.isCameraToolsExpanded {
            CameraToolsCapsule(model: model)
                .offset(x: CameraScreenLayoutMetrics.toolbarHorizontalInset, y: metrics.toolsCapsuleTop)
                .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
        }
    }

    // MARK: - Footer

    /// Bottom bar while the panel is closed, or the panel while open,
    /// anchored to the bottom of a region that starts at
    /// `metrics.footerRegionTop` / `metrics.panelTop` (issue #101 rule ③,
    /// issue #128). Closed, the region ends at `metrics.footerBase` (the
    /// home indicator's top edge) and holds just the bottom bar. Open
    /// (TASK-92), it runs on to the screen's physical bottom edge: the
    /// panel's usable area ends at `footerBase`, its scroll view continues
    /// under the home indicator (seen, faded, not tappable), and there is no
    /// footer row beneath it — the floating button in its bottom-right
    /// corner collapses it (TASK-99).
    ///
    /// Always a transparent background (issue #121): the bottom bar's icons
    /// switch to a light color over a photo instead, via
    /// `CameraScreenLayoutMetrics.isViewfinderBehindFooter`.
    private func footerColumn(metrics: CameraScreenLayoutMetrics) -> some View {
        let ratio = model.captureSettingsStore.captureAspectRatio
        let isOpen = model.panelModel.isOpen
        let regionTop = isOpen ? metrics.panelTop : metrics.footerRegionTop
        let regionBottom = isOpen ? metrics.screenSize.height : metrics.footerBase
        let isOnPhoto = metrics.isViewfinderBehindFooter(ratio: ratio, isPanelOpen: isOpen)
        return ZStack(alignment: .bottom) {
            if isOpen {
                overlayPanel(metrics: metrics)
                    .transition(.opacity)
            } else {
                bottomBar(metrics: metrics, isOnPhoto: isOnPhoto)
                    .transition(.opacity)
            }
        }
        .frame(width: metrics.screenSize.width,
               height: regionBottom - regionTop,
               alignment: .bottom)
        .background(Color.clear)
        .offset(x: 0, y: regionTop)
        .animation(CameraTheme.spring, value: model.panelModel.isOpen)
        .animation(CameraTheme.spring, value: isOnPhoto)
    }

    /// The open panel (TASK-92／TASK-99): `metrics.panelVisibleHeight` tall —
    /// tab bar, usable content down to `footerBase`, then the home-indicator
    /// band — full width (`panelWidth`, no side inset), straight on the
    /// camera background with no surface of its own. Its collapse button
    /// (#404) sits where the「疊字設定」key that opened it was
    /// (`panelCollapseButtonCenter`, 2026-10-11) and closes it with the same
    /// fade every other collapse uses; the segmented control keeps the same
    /// margin at the sides as the gap above the panel.
    private func overlayPanel(metrics: CameraScreenLayoutMetrics) -> some View {
        OverlayPanelView(model: model,
                         contentHeight: metrics.panelContentHeight,
                         tabBarHeight: metrics.panelTabBarHeight,
                         bottomSafeAreaInset: metrics.bottomInset,
                         onCollapse: { model.closeOverlayPanel() },
                         tabBarHorizontalInset: metrics.panelGapAboveBox,
                         collapseButtonCenterTrailingInset: metrics.footerSideButtonCenterInset)
            .frame(width: metrics.panelWidth, height: metrics.panelVisibleHeight)
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
                CameraPreviewView(session: model.cameraService.session, bridge: model.focusModel.previewBridge)
            }

            if model.captureSettingsStore.showsGrid {
                GridLinesView()
            }

            // Tap-to-focus reticle, exposure sun and AE/AF lock label
            // (issue #303); below the overlay text, never takes touches.
            FocusExposureOverlay(focus: model.focusModel, frameSize: frameSize)

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
                            font: model.overlayFont,
                            onDragChanged: model.panelModel.isOverlayDraggable && !model.zoomModel.isPinching ? { center, size in
                                model.panelModel.overlayDragHandler?.overlayDragChanged(center: center, viewfinderSize: size)
                            } : nil,
                            onDragEnded: model.panelModel.isOverlayDraggable && !model.zoomModel.isPinching ? { center, size in
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
                // appearance — every other view here stays fixed-light.
                // `PermissionGuidanceView` handles escaping this screen's
                // `.preferredColorScheme(.light)` (set below) itself; see
                // its own doc comment for why `.preferredColorScheme(nil)`
                // here would not have worked.
                PermissionGuidanceView()
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .contentShape(Rectangle())
        // PRD 0.2 FR-8.7: tapping the viewfinder outside the overlay text
        // collapses the panel, only while it is open. `OverlayTextView`
        // itself claims its own hit-testing area only while draggable
        // (position tab), so a tap that starts there reaches its drag
        // gesture instead of this one — never both.
        .onTapGesture {
            model.handleViewfinderTap()
        }
        // Tap to focus, drag up/down for exposure, hold to lock AE/AF (issue
        // #303). One zero-distance drag tracks the finger and the model
        // tells the three apart; it ignores touches while the panel or a
        // capsule is open and while two fingers pinch. Simultaneous, so the
        // pinch and the tap above keep working.
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
        // Pinch to zoom (TASK-61, #274). Simultaneous so the overlay text's
        // own drag keeps working with one finger; once two fingers are down
        // `isPinching` turns that drag off (see the closures above).
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { model.zoomModel.pinchChanged(magnification: $0.magnification) }
                .onEnded { _ in model.zoomModel.pinchEnded() }
        )
    }

    // MARK: - Zoom presets (issue #279)

    /// The quick-zoom round button in the picture's bottom-right corner; hidden while the panel
    /// is open, and while the camera offers no preset.
    private func zoomPresetBar(metrics: CameraScreenLayoutMetrics) -> some View {
        ZoomPresetBar(zoom: model.zoomModel,
                      expansion: model.zoomExpansion,
                      presets: model.zoomPresets,
                      isVisible: !model.panelModel.isOpen && !model.zoomPresets.isEmpty,
                      pictureFrame: viewfinderContentFrame(metrics: metrics))
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

    /// Only while the panel is closed (TASK-92; it used to switch to
    /// manage-profiles／(nothing)／collapse while open): thumbnail／shutter／
    /// Aa. No text labels, no background — every button is just an icon
    /// (FR-14.2).
    ///
    /// The side buttons' centers sit `footerSideButtonCenterInset` from the
    /// screen edge (midway to the shutter's edge, minus 8pt); the row sits
    /// 16pt above the bottom of the footer region.
    private func bottomBar(metrics: CameraScreenLayoutMetrics, isOnPhoto: Bool) -> some View {
        let sideInset = metrics.footerSideButtonCenterInset - Self.footerButtonSize / 2
        return ZStack {
            shutterButton
            HStack {
                thumbnailButton(isOnPhoto: isOnPhoto)
                Spacer()
                openPanelButton(isOnPhoto: isOnPhoto)
            }
            .padding(.horizontal, sideInset)
        }
        .padding(.bottom, CameraScreenLayoutMetrics.closedFooterBottomPadding)
    }

    /// Tap target of every footer side button, and the thumbnail's size
    /// (issue #128).
    private static let footerButtonSize: CGFloat = 44

    /// Icon point size of the footer side buttons (TASK-50 made it 28; human
    /// decision 2026-10-08 settled on 24, issue #239).
    private static let footerIconSize: CGFloat = 24

    /// Right key: opens the panel. `character.textbox` (human decision,
    /// 2026-10-07, #221; it replaced `pencil.tip.crop.circle` from #84). Not
    /// `textformat` or other T-style icons: the style tab's font icon
    /// `t.square` (#215) and the outline icon `character.square.fill` would
    /// read as the same button twice while the panel is open.
    ///
    /// 44×44 tap target (`footerButtonSize`, issue #128). `isOnPhoto` picks
    /// `CameraTheme.ink`/`inkOnPhoto` the same way `CameraToolbar`'s own
    /// icons do (issue #121): 9:16 with the panel closed has the viewfinder
    /// behind this row.
    private func openPanelButton(isOnPhoto: Bool) -> some View {
        Button {
            model.openOverlayPanel()
        } label: {
            Image(systemName: "character.textbox")
                // Latin glyph regardless of the app's 繁中 locale (TASK-100).
                .latinSymbol()
                .font(.system(size: Self.footerIconSize, weight: .medium))
                .foregroundColor(isOnPhoto ? CameraTheme.inkOnPhoto : CameraTheme.ink)
                .frame(width: Self.footerButtonSize, height: Self.footerButtonSize)
                .legibleOverPhoto(isOnPhoto)
        }
        .accessibilityLabel("疊字設定")
        // TASK-96: the first-launch tour's step 2 points here.
        .onboardingTarget(.overlayPanelButton)
    }

    /// Left key while closed: the newest DaysCam photo, or a placeholder
    /// icon (PRD 0.2 FR-15.2). Tapping it requests read access the first
    /// time and opens the gallery (FR-15.3). `isOnPhoto` only
    /// ever affects the placeholder icon (issue #121) — an actual thumbnail
    /// image is unaffected either way (assumption 4).
    private func thumbnailButton(isOnPhoto: Bool) -> some View {
        Button {
            model.openGallery()
        } label: {
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
            // Only Reduce Motion crossfades the swap (0.2s, issue #148 S.8),
            // via an explicit `withAnimation` in `showThumbnail`; otherwise
            // the new photo replaces the icon instantly — an animated if/else
            // left the old icon fading out behind the new photo, which showed
            // as a flicker right after landing.
            .onAppear { shownThumbnail = model.latestThumbnailImage }
            .onChange(of: model.latestThumbnailImage) { _, image in showThumbnail(image) }
        }
        .modifier(ThumbnailLandingEffect(landingCount: model.thumbnailLandingCount))
        .accessibilityLabel("查看已拍照片")
    }

    private func showThumbnail(_ image: UIImage?) {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { shownThumbnail = image }
        } else {
            shownThumbnail = image
        }
    }

    /// Center: the shutter — the one place PRD 0.2 FR-14.2 allows a filled
    /// background (the `accent` circle) plus a ring, matching D-1. Only
    /// shown while the panel is closed (issue #128), like the whole bar.
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

    /// `model.showsCorruptionRecoveredAlert` as a `Binding` for `.alert`, same
    /// dismiss-clears-model-state pattern as the other alert bindings here.
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

#Preview("疊字面板打開（22.6；TASK-92 拖桿、延伸到底）") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    model.panelModel.open()
    return CameraScreen(model: model)
}

#Preview("疊字面板打開・內容分頁") {
    let store = ProfileStore()
    store.load()
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store)
    model.panelModel.open()
    model.panelModel.selectedTab = .content
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

// MARK: - Issue #120 (panel-open viewfinder, position tab, qa screenshots for G.9)

@MainActor
private func panelOpenPositionTabPreviewModel(ratio: CaptureAspectRatio, suiteSuffix: String) -> CameraScreenModel {
    let store = ProfileStore()
    store.load()
    let settings = CaptureSettingsStore(defaults: UserDefaults(suiteName: "CameraScreen.preview.\(suiteSuffix)") ?? .standard)
    settings.setAspectRatio(ratio)
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store, captureSettingsStore: settings)
    model.panelModel.open()
    model.panelModel.selectedTab = .position
    return model
}

/// 驗收 G.1/G.5（issue #120）：3:4 開面板・位置分頁，作為跟 9:16 比較的基準畫面。
#Preview("3:4 疊字面板打開・位置分頁（G.1 基準）") {
    CameraScreen(model: panelOpenPositionTabPreviewModel(ratio: .threeByFour, suiteSuffix: "g120.34"))
}

/// 驗收 G.5：1:1 開面板・位置分頁，跟 3:4/9:16 共用同一個開面板觀景區。
#Preview("1:1 疊字面板打開・位置分頁（G.5）") {
    CameraScreen(model: panelOpenPositionTabPreviewModel(ratio: .oneByOne, suiteSuffix: "g120.11"))
}

/// 驗收 G.1（issue #120）：整張 9:16 觀景窗都在面板上方，不再被面板／底部列蓋住，
/// 疊字（預設右下）拖得到、看得到。iPhone 16 參考值：觀景窗 ≈236×419，水平置中。
#Preview("9:16 疊字面板打開・位置分頁（G.1）") {
    CameraScreen(model: panelOpenPositionTabPreviewModel(ratio: .nineBySixteen, suiteSuffix: "g120.916"))
}

/// 驗收 G.7：iPhone SE 上重跑 G.1，開面板觀景區、9:16 內容都不重疊、不裁切。
#Preview("iPhone SE・3:4 疊字面板打開・位置分頁（G.7 基準）") {
    CameraScreen(model: panelOpenPositionTabPreviewModel(ratio: .threeByFour, suiteSuffix: "g120.se.34"))
        .previewDevice("iPhone SE (3rd generation)")
}

/// 驗收 G.7：iPhone SE、1:1。
#Preview("iPhone SE・1:1 疊字面板打開・位置分頁（G.7）") {
    CameraScreen(model: panelOpenPositionTabPreviewModel(ratio: .oneByOne, suiteSuffix: "g120.se.11"))
        .previewDevice("iPhone SE (3rd generation)")
}

/// 驗收 G.7：iPhone SE、9:16——小螢幕也走 #120 的規則（跟面板收起時的「假設 2」退回
/// 行為是分開的兩件事：退回只影響面板收起時的 9:16，見 #101）。
#Preview("iPhone SE・9:16 疊字面板打開・位置分頁（G.7）") {
    CameraScreen(model: panelOpenPositionTabPreviewModel(ratio: .nineBySixteen, suiteSuffix: "g120.se.916"))
        .previewDevice("iPhone SE (3rd generation)")
}

// MARK: - Issue #135 (tools capsule)

/// 驗收 C.2/C.12（issue #135）：膠囊展開，閃光燈開、計時 3 秒。
#Preview("相機設定膠囊展開（C.2）") {
    let store = ProfileStore()
    store.load()
    let settings = CaptureSettingsStore(defaults: UserDefaults(suiteName: "CameraScreen.preview.c135") ?? .standard)
    let model = CameraScreenModel(cameraService: CameraService(), profileStore: store, captureSettingsStore: settings)
    settings.cycleFlash()
    settings.cycleTimer()
    model.toggleCameraTools()
    return CameraScreen(model: model)
}
