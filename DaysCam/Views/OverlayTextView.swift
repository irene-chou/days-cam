import SwiftUI

/// Renders already-computed overlay text styled and placed by an
/// `OverlayStyle`/`OverlayPlacement` (PRD 0.2 §4.1–§4.2).
///
/// Deliberately takes a finished string rather than a `CameraProfile`: what to
/// print is decided by the caller (`TemplateRenderer`'s output), this view
/// only lays it out. Font size, margin, shrink-to-fit and placement all go
/// through `OverlayMetrics` — the same functions the baking path
/// (`OverlayRenderer`) calls — so the viewfinder and the saved photo agree
/// (PRD FR-6.1, FR-4.7, FR-4.8; 0.2 FR-5.10, FR-12). No decoration constant
/// is defined here; they all live in `OverlayTheme` (TASK-18 18.11).
///
/// Never intercepts touches (PRD FR-6.4) *unless* `onDragChanged`/
/// `onDragEnded` are supplied (TASK-24, PRD 0.2 FR-12.1) — with neither set
/// (the default) it behaves exactly as before and never blocks the shutter
/// or camera controls underneath it.
struct OverlayTextView: View {
    /// The text to draw. An empty string draws nothing.
    let text: String
    /// The look (font, colors, outline, shadow, size) to draw `text` with.
    let style: OverlayStyle
    /// Where to draw `text`: a nine-point anchor or a custom center (PRD 0.2 §4.1).
    let placement: OverlayPlacement
    /// The face to draw with, already resolved on the main actor
    /// (`OverlayMetrics.resolvedFont(for:availability:)`, PRD 0.3 FR-5.14).
    /// Measured and drawn with this one value, and part of the render cache
    /// key so a font changing state always redraws.
    let font: ResolvedOverlayFont
    /// The size of the frame the overlay is positioned within — the
    /// viewfinder's bounds live, the photo's pixel size when baking. Margin
    /// and base font size scale off its short edge (PRD FR-4.3, FR-4.7).
    let frameSize: CGSize
    /// Called continuously while the block is dragged, with the block's own
    /// on-screen center (already kept inside the 4% margin, same as a
    /// settled `.custom` position — see `Self.clampedDragCenter`) and this
    /// view's `frameSize` (TASK-24, #68, PRD 0.2 FR-12.1–FR-12.3). `nil` (the
    /// default) makes the block non-interactive: see `isInteractive`.
    ///
    /// A *center point*, not a raw translation (#68's fix): a translation
    /// alone can't be turned back into a `.custom` fraction without knowing
    /// where the block started, and only this view knows that (`placement`
    /// plus its own measured `blockSize`). Deliberately still not where
    /// *persisting* happens — this view only reports where the block
    /// currently is; writing that back to a profile is the position model's
    /// job (`OverlayDragHandling`, owned by ui-panel).
    var onDragChanged: ((CGPoint, CGSize) -> Void)?
    /// Called once when the drag ends, with the same two values as
    /// `onDragChanged`'s final call.
    var onDragEnded: ((CGPoint, CGSize) -> Void)?
    /// Called for a tap on the block while it is not draggable (TASK-105,
    /// #420): the camera screen opens the overlay panel with it. While
    /// non-nil the block also swallows taps that would otherwise fall through
    /// to the viewfinder (focus, FR-8.7 collapse), so pass an empty closure
    /// to keep the block tappable-but-inert.
    var onTap: (() -> Void)?
    /// Bumped by `OverlayPanelModel` each time the panel goes from closed to
    /// open (#599); every new value flashes the dashed frame once as a "this
    /// can be dragged" hint. `0` (the initial value) never flashes.
    var dragHintSerial: Int = 0

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether a finger is currently down on the draggable block (#599).
    @State private var isPressed = false
    /// Whether the open-time hint flash is currently showing (#599).
    @State private var isHintShowing = false
    /// Memoizes pixels independently of placement and gesture state.
    @State private var renderCache = OverlayTextRenderCache()

    /// The block's settled (non-dragging) center, captured the instant the
    /// current gesture began — `nil` between gestures. `DragGesture`'s
    /// `translation` is always measured from wherever the touch started, so
    /// this is the one fixed reference point every `onChanged`/`onEnded`
    /// call of one continuous gesture adds that translation to (#68: reusing
    /// `placement`/`blockSize` fresh on every callback would be wrong once
    /// the block has already visually moved away from its settled position).
    @State private var dragStartCenter: CGPoint?

    /// The block's live center while a drag is in progress — `nil` between
    /// gestures, in which case the settled `placement`-derived origin is
    /// used instead (see `body`). This is what actually makes the block
    /// track the finger (#68): without it, `placement` (and so the rendered
    /// position) never changes until the drag ends and a new `.custom`
    /// position round-trips all the way back from `ProfileStore`.
    @State private var liveDragCenter: CGPoint?

    /// The center the block was released at, while waiting for the saved
    /// position to round-trip back into `placement` (#605). `liveDragCenter`
    /// stays set meanwhile so the block does not move.
    @State private var pendingReleaseCenter: CGPoint?

    /// Creates a view. `frameSize` and everything before it are the settled
    /// public shape from TASK-18; `onDragChanged`/`onDragEnded` are TASK-24's
    /// addition, both defaulting to `nil` so every pre-existing call site
    /// (`CameraScreen` while the panel is closed, `StyleSwatchPreview`'s little
    /// preview swatches) keeps compiling and keeps being non-interactive
    /// without changing a single call site.
    init(text: String,
         style: OverlayStyle,
         placement: OverlayPlacement,
         frameSize: CGSize,
         font: ResolvedOverlayFont = .pingFang,
         onDragChanged: ((CGPoint, CGSize) -> Void)? = nil,
         onDragEnded: ((CGPoint, CGSize) -> Void)? = nil,
         onTap: (() -> Void)? = nil,
         dragHintSerial: Int = 0) {
        self.text = text
        self.style = style
        self.placement = placement
        self.frameSize = frameSize
        self.font = font
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onTap = onTap
        self.dragHintSerial = dragHintSerial
    }

    /// How long the open-time hint frame stays before fading out (#599).
    static let hintDuration: Duration = .seconds(1)
    /// Fade-in / fade-out durations of the dashed frame (#599).
    static let frameFadeInDuration: Double = 0.15
    static let frameFadeOutDuration: Double = 0.3

    /// Whether the dashed frame is drawn (#599): only on a draggable block,
    /// and only while a finger is down or the open-time hint is flashing.
    static func isFrameVisible(isInteractive: Bool, isPressed: Bool, isHintShowing: Bool) -> Bool {
        isInteractive && (isPressed || isHintShowing)
    }

    /// How far a touch may travel and still count as a tap on the block
    /// (TASK-105); anything longer is a drag, which does nothing while the
    /// block is not draggable.
    static let tapTranslationLimit: CGFloat = 10

    /// Whether this instance should accept drags at all. `CameraScreen` is
    /// expected to only ever pass non-nil closures while
    /// `OverlayPanelModel.isOverlayDraggable` is true (FR-12.1's own
    /// wording: "面板打開時啟用，allowsHitTesting 僅此時為 true"), but this
    /// is computed from the closures themselves rather than trusting the
    /// caller, so a stray non-nil closure can never leave the block
    /// draggable when the caller forgot to gate it.
    private var isInteractive: Bool {
        onDragChanged != nil || onDragEnded != nil
    }

    private var isFrameShowing: Bool {
        Self.isFrameVisible(isInteractive: isInteractive, isPressed: isPressed, isHintShowing: isHintShowing)
    }

    var body: some View {
        if let rendered = renderCache.image(text: text, style: style, font: font,
                                            frameSize: frameSize, displayScale: displayScale) {
            let blockSize = rendered.blockSize
            let settledOrigin = Self.origin(forBlockSize: blockSize, frameSize: frameSize, placement: placement)
            // While a drag is live, its center overrides the settled,
            // `placement`-derived origin (#68) — this is what makes the
            // block track the finger instead of only jumping once the drag
            // ends and a new `.custom` position comes back through `placement`.
            let displayOrigin = liveDragCenter.map { center in
                CGPoint(x: center.x - blockSize.width / 2, y: center.y - blockSize.height / 2)
            } ?? settledOrigin

            Color.clear
                .frame(width: blockSize.width, height: blockSize.height)
                .overlay(alignment: .topLeading) {
                    Image(uiImage: rendered.image)
                        .resizable()
                        .frame(width: rendered.image.size.width, height: rendered.image.size.height)
                        .offset(x: -rendered.textInsets.left, y: -rendered.textInsets.top)
                        .allowsHitTesting(false)
                }
                .overlay {
                    // The fade is scoped to this overlay only (#605): an
                    // `.animation(value:)` further out would also animate the
                    // block's `.position` the moment a drag is released.
                    ZStack {
                        if isFrameShowing {
                            Rectangle()
                                .strokeBorder(.white, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : (isFrameShowing ? .easeOut(duration: Self.frameFadeInDuration)
                                                                    : .easeIn(duration: Self.frameFadeOutDuration)),
                               value: isFrameShowing)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
                // The dashed frame is not in the accessibility tree and only
                // shows on press / hint (#599); UI tests (#568) tell
                // "draggable" apart by this identifier instead.
                .accessibilityIdentifier(isInteractive ? "overlayTextDraggable" : "overlayText")
                .position(x: displayOrigin.x + blockSize.width / 2, y: displayOrigin.y + blockSize.height / 2)
                // Where the block sits, in the viewfinder's coordinates, for
                // the camera screen to keep tap-to-focus off it (TASK-105).
                .preference(key: OverlayTextBlockFrameKey.self,
                            value: CGRect(origin: settledOrigin, size: blockSize))
                .allowsHitTesting(isInteractive || onTap != nil)
                .onChange(of: isInteractive) { _, interactive in
                    // A pinch or panel close can take the gesture away without
                    // an `onEnded`; never leave the press state stuck.
                    if !interactive {
                        isPressed = false
                        clearDragState()
                    }
                }
                // The saved position has round-tripped back: `settledOrigin`
                // now equals the released center, so handing display back to
                // `placement` does not move anything (#605).
                .onChange(of: placement) { _, _ in
                    if pendingReleaseCenter != nil { clearDragState() }
                }
                // Safety net when the write-back never arrives (save failed):
                // fall back to the stored position, as before.
                .task(id: pendingReleaseCenter) {
                    guard pendingReleaseCenter != nil else { return }
                    try? await Task.sleep(for: Self.releaseSettleTimeout)
                    guard !Task.isCancelled else { return }
                    clearDragState()
                }
                .task(id: dragHintSerial) {
                    guard dragHintSerial > 0, isInteractive else { return }
                    isHintShowing = true
                    try? await Task.sleep(for: Self.hintDuration)
                    guard !Task.isCancelled else { return }
                    isHintShowing = false
                }
                .gesture(
                    // Always attached, never conditionally — `allowsHitTesting`
                    // above is the single switch that decides whether this can
                    // ever actually receive a touch, so there is no second place
                    // "draggable or not" has to stay in sync. The same
                    // zero-distance drag is also the tap (TASK-105): while the
                    // block is not draggable, a touch that ends within
                    // `tapTranslationLimit` of where it began is `onTap`.
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isInteractive else { return }
                            isPressed = true
                            // A new touch during the post-release wait starts from
                            // where the block is shown, not the stale `placement`.
                            if dragStartCenter == nil {
                                dragStartCenter = Self.dragStartCenter(pendingReleaseCenter: pendingReleaseCenter,
                                                                       settledOrigin: settledOrigin, blockSize: blockSize)
                            }
                            pendingReleaseCenter = nil
                            let center = dragCenter(forTranslation: value.translation, settledOrigin: settledOrigin, blockSize: blockSize)
                            liveDragCenter = center
                            onDragChanged?(center, frameSize)
                        }
                        .onEnded { value in
                            isPressed = false
                            guard isInteractive else {
                                if Self.isTap(translation: value.translation) { onTap?() }
                                return
                            }
                            // A tap while draggable is swallowed: it must not
                            // turn an anchor into `.custom` (#568).
                            guard Self.shouldPersistDrag(translation: value.translation) else {
                                clearDragState()
                                return
                            }
                            let center = dragCenter(forTranslation: value.translation, settledOrigin: settledOrigin, blockSize: blockSize)
                            onDragEnded?(center, frameSize)
                            // `placement` only changes after the position model
                            // writes the profile and `ProfileStore` publishes it,
                            // which is not in this update. Keep showing the
                            // released center until then (`onChange(of: placement)`
                            // or the timeout hands display back), otherwise the
                            // block would jump to its old settled origin first (#605).
                            let releasedOrigin = CGPoint(x: center.x - blockSize.width / 2, y: center.y - blockSize.height / 2)
                            if Self.shouldSettle(settledOrigin: settledOrigin, releasedOrigin: releasedOrigin) {
                                clearDragState()
                            } else {
                                dragStartCenter = nil
                                pendingReleaseCenter = center
                            }
                        }
                )
        }
    }

    /// How long a released block keeps showing its released center while
    /// waiting for the saved position to come back (#605).
    static let releaseSettleTimeout: Duration = .milliseconds(500)

    /// Whether the released position already equals the settled one, so
    /// there is nothing to wait for (#605).
    static func shouldSettle(settledOrigin: CGPoint, releasedOrigin: CGPoint, tolerance: CGFloat = 0.5) -> Bool {
        hypot(settledOrigin.x - releasedOrigin.x, settledOrigin.y - releasedOrigin.y) < tolerance
    }

    /// Where a new drag starts from: the block's displayed center, which is the
    /// released center while a save is still pending, else the settled one.
    static func dragStartCenter(pendingReleaseCenter: CGPoint?, settledOrigin: CGPoint, blockSize: CGSize) -> CGPoint {
        pendingReleaseCenter ?? CGPoint(x: settledOrigin.x + blockSize.width / 2,
                                        y: settledOrigin.y + blockSize.height / 2)
    }

    private func clearDragState() {
        dragStartCenter = nil
        liveDragCenter = nil
        pendingReleaseCenter = nil
    }

    /// Whether a finished touch on a draggable block moved far enough to be a
    /// drag worth saving. The bound is the same `tapTranslationLimit` (10pt)
    /// that separates a tap from a drag while closed: one threshold for "did
    /// the finger move", and about the jitter of a still fingertip.
    static func shouldPersistDrag(translation: CGSize) -> Bool {
        !isTap(translation: translation)
    }

    /// Whether a finished touch moved little enough to be a tap (TASK-105).
    static func isTap(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) <= tapTranslationLimit
    }

    /// `Self.clampedDragCenter`, filling in this gesture's start center —
    /// captured once, from `settledOrigin`, on the first callback of the
    /// gesture, and reused for every later callback of the same one (see
    /// `dragStartCenter`'s own doc comment).
    private func dragCenter(forTranslation translation: CGSize, settledOrigin: CGPoint, blockSize: CGSize) -> CGPoint {
        let start = dragStartCenter ?? Self.dragStartCenter(pendingReleaseCenter: pendingReleaseCenter,
                                                            settledOrigin: settledOrigin, blockSize: blockSize)
        dragStartCenter = start
        return Self.clampedDragCenter(start: start, translation: translation, frameSize: frameSize, blockSize: blockSize)
    }

    // MARK: - Shared layout (mirrors `OverlayRenderer`'s private `OverlayLayout`)

    /// The font size this view draws `text` at for `frameSize`, after
    /// `style.sizeScale` and shrink-to-fit — the same value the baking path
    /// computes for the same inputs (PRD FR-6.1, 0.2 FR-5.10, FR-10.9).
    /// Exposed (rather than left as a body-local `let`) so
    /// `OverlayTextViewTests` can confirm it, without a hosting controller,
    /// against `OverlayMetrics` directly.
    static func fittedFontSize(for text: String, style: OverlayStyle, frameSize: CGSize,
                               font: ResolvedOverlayFont = .pingFang) -> CGFloat {
        OverlayRenderer.fittedFontSize(for: text, style: style, frameSize: frameSize, font: font)
    }

    /// The top-left corner this view places a block of `blockSize` at for
    /// `frameSize`/`placement` — a thin pass-through to
    /// `OverlayMetrics.origin(forBlockSize:in:placement:)`, the same call the
    /// baking path makes, so `.custom`'s margin-clamping (PRD 0.2 FR-12.2,
    /// FR-12.6) can never drift between preview and photo.
    static func origin(forBlockSize blockSize: CGSize,
                       frameSize: CGSize,
                       placement: OverlayPlacement) -> CGPoint {
        OverlayMetrics.origin(forBlockSize: blockSize, in: frameSize, placement: placement)
    }

    // MARK: - Drag (TASK-24, #68)

    /// `start + translation`, kept inside the 4% margin the same way a
    /// settled `.custom` position already is (PRD FR-12.2, #68's D.1–D.4).
    ///
    /// Routes through `Self.origin(forBlockSize:frameSize:placement:)` —
    /// the same clamp `OverlayMetrics.origin` applies to any `.custom`
    /// placement — by converting the raw candidate center to a fraction of
    /// `frameSize` and reading the clamped origin straight back out. Two
    /// things fall out of reusing that one function instead of duplicating
    /// its margin math here:
    ///
    /// - The block stays inside the margin band *while dragging*, not only
    ///   once a drag ends and gets clamped on the way back in through a
    ///   freshly stored `.custom` fraction (D.4 — the previous version only
    ///   clamped at that point, so mid-drag the block could visibly leave
    ///   the margin before snapping back).
    /// - Starting a drag from an `.anchor` and releasing with zero
    ///   translation reproduces that exact anchor's origin (D.1, D.2): an
    ///   anchor's origin already satisfies the margin band by construction,
    ///   so converting its real (non-zero) `blockSize`-based center to a
    ///   fraction and back through this same clamp is a no-op. The
    ///   `#67`/`PositionDragAdapter` version of this used
    ///   `OverlayMetrics.origin(forBlockSize: .zero, …)` as a stand-in
    ///   reference point, which is only actually the block's center for
    ///   `.custom` (PRD A-1's own definition) — for an anchor it lands on
    ///   the anchor's margin *corner* instead, off by half the block's size
    ///   on each axis it hugs. Using the view's own real `blockSize` here
    ///   fixes that at the source instead of leaving `PositionDragAdapter`
    ///   to guess it.
    static func clampedDragCenter(start: CGPoint, translation: CGSize, frameSize: CGSize, blockSize: CGSize) -> CGPoint {
        guard frameSize.width > 0, frameSize.height > 0 else { return start }
        let rawCenter = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        let fractionX = Double(rawCenter.x / frameSize.width)
        let fractionY = Double(rawCenter.y / frameSize.height)
        let clampedOrigin = origin(forBlockSize: blockSize, frameSize: frameSize, placement: .custom(x: fractionX, y: fractionY))
        return CGPoint(x: clampedOrigin.x + blockSize.width / 2, y: clampedOrigin.y + blockSize.height / 2)
    }

}

/// A per-view, single-entry pixel cache. Placement is intentionally absent:
/// anchor changes and drag callbacks reuse the same image and block metrics.
/// This memoizes a derived value without publishing changes during View.body.
@MainActor
final class OverlayTextRenderCache {
    private struct Key: Equatable {
        let text: String
        let style: OverlayStyle
        /// The resolved face (PRD 0.3 FR-5.14): a state change that changes
        /// the face must never reuse the previous picture.
        let font: ResolvedOverlayFont
        let frameSize: CGSize
        let displayScale: CGFloat
    }

    private var key: Key?
    private var rendered: RenderedOverlayText?
    private let render: (String, OverlayStyle, CGFloat, CGFloat, ResolvedOverlayFont) -> RenderedOverlayText?

    init(render: @escaping (String, OverlayStyle, CGFloat, CGFloat, ResolvedOverlayFont) -> RenderedOverlayText? = {
        OverlayRenderer().renderText($0, style: $1, fontSize: $2, displayScale: $3, font: $4)
    }) {
        self.render = render
    }

    /// Returns pixels at the current screen scale, redrawing only for new inputs.
    func image(text: String, style: OverlayStyle, font: ResolvedOverlayFont = .pingFang, frameSize: CGSize,
               displayScale: CGFloat) -> RenderedOverlayText? {
        let next = Key(text: text, style: style, font: font, frameSize: frameSize, displayScale: displayScale)
        if key == next { return rendered }
        key = next
        guard !text.isEmpty, frameSize.width.isFinite, frameSize.height.isFinite,
              frameSize.width > 0, frameSize.height > 0,
              displayScale.isFinite, displayScale > 0 else {
            rendered = nil
            return nil
        }
        rendered = render(text, style,
                          OverlayRenderer.fittedFontSize(for: text, style: style, frameSize: frameSize, font: font),
                          displayScale, font)
        return rendered
    }
}

#Preview("Nine anchors") {
    ZStack {
        Color.gray
        ForEach(OverlayPosition.allCases, id: \.self) { position in
            OverlayTextView(text: position.rawValue,
                             style: OverlayStyle(),
                             placement: .anchor(position),
                             frameSize: CGSize(width: 300, height: 400))
        }
    }
    .frame(width: 300, height: 400)
}

#Preview("Custom placement, clamped into the margin") {
    ZStack {
        Color.gray
        OverlayTextView(text: "自訂位置",
                         style: OverlayStyle(outline: .stroke, shadow: .soft),
                         placement: .custom(x: 1.0, y: 1.0),
                         frameSize: CGSize(width: 300, height: 400))
    }
    .frame(width: 300, height: 400)
}

#Preview("Every outline and shadow, bottom trailing") {
    let outlines: [OverlayOutline] = [.none, .stroke, .box]
    let shadows: [OverlayShadowPreset] = [.none, .soft, .hard, .glow]
    return ZStack {
        Color(white: 0.5)
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(Array(outlines.enumerated()), id: \.offset) { _, outline in
                HStack(spacing: 8) {
                    ForEach(Array(shadows.enumerated()), id: \.offset) { _, shadow in
                        OverlayTextView(text: "Aa",
                                         style: OverlayStyle(outline: outline, shadow: shadow),
                                         placement: .anchor(.middleCenter),
                                         frameSize: CGSize(width: 44, height: 44))
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
    }
    .frame(width: 300, height: 400)
}

#Preview("Every font") {
    ZStack {
        Color.white
        VStack(spacing: 6) {
            ForEach(OverlayFontID.allCases, id: \.self) { fontID in
                OverlayTextView(text: fontID.displayName,
                                 style: OverlayStyle(fontID: fontID, textColor: .autoContrastDark, shadow: .none),
                                 placement: .anchor(.middleCenter),
                                 frameSize: CGSize(width: 280, height: 32),
                                 font: OverlayMetrics.resolvedFont(state: .available,
                                                                   postScriptName: fontID.postScriptName))
                    .frame(width: 280, height: 32)
            }
        }
    }
    .frame(width: 300, height: 400)
}

#Preview("sizeScale 70 vs 160") {
    ZStack {
        Color.white
        OverlayTextView(text: "70%",
                         style: OverlayStyle(textColor: .autoContrastDark, sizeScale: 70),
                         placement: .anchor(.topLeading),
                         frameSize: CGSize(width: 300, height: 400))
        OverlayTextView(text: "160%",
                         style: OverlayStyle(textColor: .autoContrastDark, sizeScale: 160),
                         placement: .anchor(.bottomTrailing),
                         frameSize: CGSize(width: 300, height: 400))
    }
    .frame(width: 300, height: 400)
}

#Preview("Long text shrinks") {
    ZStack {
        Color.white
        OverlayTextView(text: "小寶 2026.03.20　1 年 2 個月 5 天",
                         style: OverlayStyle(outline: .box, shadow: .none),
                         placement: .anchor(.bottomTrailing),
                         frameSize: CGSize(width: 300, height: 400))
    }
    .frame(width: 300, height: 400)
}

/// The overlay text block's frame in the viewfinder's coordinates
/// (TASK-105, #420), `.null` while nothing is drawn.
struct OverlayTextBlockFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull { value = next }
    }
}
