import SwiftUI

/// Where the tour's targets are on screen (TASK-96, #400): the profile chip
/// in `CameraToolbar`, the panel button in `CameraScreen` and the overlay
/// text in `OverlayTextView` publish their bounds here, and `CameraScreen`
/// resolves them for the overlay, so every hole follows the real view — no
/// hard-coded coordinates, and a day-count text the user has already moved
/// is lit up where it actually is.
struct OnboardingTargetKey: PreferenceKey {
    static let defaultValue: [OnboardingTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [OnboardingTarget: Anchor<CGRect>],
                       nextValue: () -> [OnboardingTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this view's bounds as one of the tour's targets.
    func onboardingTarget(_ target: OnboardingTarget) -> some View {
        anchorPreference(key: OnboardingTargetKey.self, value: .bounds) { [target: $0] }
    }
}

/// The geometry of one step, computed from the targets' frames so the view
/// (and the unit tests) share one set of numbers (#400 外觀).
struct OnboardingSpotlightGeometry: Equatable {
    /// Which edge of the bubble the arrow sits on, pointing at the target.
    enum ArrowEdge: Equatable {
        /// Bubble below the target (step 1).
        case top
        /// Bubble above the target (step 2's narrow-screen fallback).
        case bottom
        /// Bubble left of the target, arrow pointing right (step 2).
        case trailing
    }

    /// The interactive cut-out: a capsule around the profile chip, a 44pt
    /// circle around the panel button.
    let hole: CGRect
    /// Step 2's look-only cut-out around the day-count text: the text's
    /// frame plus ~6pt, corner radius 8; `nil` on step 1 or when the text
    /// has no frame yet.
    let secondaryHole: CGRect?
    /// The bubble's frame, excluding its arrow.
    let bubble: CGRect
    /// The arrow's center along its edge, in the bubble's own coordinates
    /// (x for `.top`/`.bottom`, y for `.trailing`).
    let arrowOffset: CGFloat
    let arrowEdge: ArrowEdge

    static let screenMargin: CGFloat = 16
    static let arrowHeight: CGFloat = 8
    static let gap: CGFloat = 6
    static let maximumBubbleWidth: CGFloat = 300
    /// Narrower than this and the bubble moves above the button instead.
    static let minimumBubbleWidth: CGFloat = 170
    static let circleSide: CGFloat = 44
    static let chipOutset: CGFloat = 3
    static let overlayTextOutset: CGFloat = 6
    static let overlayTextCornerRadius: CGFloat = 8

    /// - Parameters:
    ///   - target: the highlighted button's frame in screen coordinates.
    ///   - secondaryTarget: step 2's day-count text frame, if known.
    ///   - bubbleHeight: the bubble's measured height (its text may wrap).
    init(step: OnboardingSpotlightModel.Step, target: CGRect, secondaryTarget: CGRect? = nil,
         screenSize: CGSize, bubbleHeight: CGFloat) {
        let margin = Self.screenMargin
        let lead = Self.gap + Self.arrowHeight
        switch step {
        case .startDate:
            hole = target.insetBy(dx: -Self.chipOutset, dy: -Self.chipOutset)
            secondaryHole = nil
            let width = min(Self.maximumBubbleWidth, screenSize.width - 2 * margin)
            let x = min(max(hole.midX - width / 2, margin), max(margin, screenSize.width - margin - width))
            bubble = CGRect(x: x, y: hole.maxY + lead, width: width, height: bubbleHeight)
            arrowEdge = .top
            arrowOffset = min(max(hole.midX - x, 20), width - 20)

        case .overlayStyle:
            let side = max(Self.circleSide, max(target.width, target.height))
            let circle = CGRect(x: target.midX - side / 2, y: target.midY - side / 2, width: side, height: side)
            hole = circle
            let text = secondaryTarget.flatMap { frame -> CGRect? in
                guard frame.width > 0, frame.height > 0 else { return nil }
                return frame.insetBy(dx: -Self.overlayTextOutset, dy: -Self.overlayTextOutset)
            }
            secondaryHole = text

            // Preferred: left of the button, centered on it, arrow pointing
            // right; pushed down (never up) if it would cover the text hole,
            // and kept above the screen's bottom margin.
            let sideWidth = min(Self.maximumBubbleWidth, circle.minX - lead - margin)
            let bottomLimit = screenSize.height - margin
            var placedBeside: CGRect?
            if sideWidth >= Self.minimumBubbleWidth {
                let x = circle.minX - lead - sideWidth
                var y = min(circle.midY - bubbleHeight / 2, bottomLimit - bubbleHeight)
                var candidate = CGRect(x: x, y: y, width: sideWidth, height: bubbleHeight)
                if let text, candidate.intersects(text) {
                    y = text.maxY + Self.gap
                    candidate.origin.y = y
                }
                if candidate.maxY <= bottomLimit, text.map({ !candidate.intersects($0) }) ?? true {
                    placedBeside = candidate
                }
            }

            if let beside = placedBeside {
                bubble = beside
                arrowEdge = .trailing
                arrowOffset = min(max(circle.midY - beside.minY, 20), max(20, bubbleHeight - 20))
            } else {
                // Fallback: above the button (and above the text hole), flush
                // with the screen's right margin, arrow pointing down.
                let width = min(Self.maximumBubbleWidth, screenSize.width - 2 * margin)
                let x = min(max(circle.maxX + margin - width, margin), max(margin, screenSize.width - margin - width))
                let ceiling = min(circle.minY, text?.minY ?? circle.minY)
                bubble = CGRect(x: x, y: ceiling - lead - bubbleHeight, width: width, height: bubbleHeight)
                arrowEdge = .bottom
                arrowOffset = min(max(circle.midX - x, 20), width - 20)
            }
        }
    }
}

/// The spotlight overlay itself (TASK-96, #400): a 45% ink mask with one or
/// two holes, an accent ring around each, and the bubble with the step's
/// copy. Covers the whole screen and swallows every touch outside the
/// interactive hole (96.6) — the day-count text's hole included (96.19); the
/// interactive hole is a proxy button carrying the real button's
/// accessibility label, so tapping (or activating with VoiceOver) the
/// highlighted button still does what it always does (96.4, 96.5, 96.10).
struct OnboardingSpotlightView: View {
    let step: OnboardingSpotlightModel.Step
    /// The highlighted button's frame in this view's coordinates.
    let targetFrame: CGRect
    /// The day-count text's frame, for step 2's second hole; `nil` when
    /// unknown.
    var overlayTextFrame: CGRect? = nil
    let screenSize: CGSize
    /// The real button's accessibility label, repeated on the proxy.
    let targetLabel: String
    var onAdvance: () -> Void
    var onTargetTap: () -> Void
    var onEscape: () -> Void

    @State private var bubbleHeight: CGFloat = 120
    @AccessibilityFocusState private var isBubbleFocused: Bool

    static let maskOpacity: Double = 0.45
    static let ringWidth: CGFloat = 2

    var body: some View {
        let geometry = OnboardingSpotlightGeometry(step: step, target: targetFrame, secondaryTarget: overlayTextFrame,
                                                   screenSize: screenSize, bubbleHeight: bubbleHeight)
        let secondary = geometry.secondaryHole
            ?? CGRect(x: geometry.hole.midX, y: geometry.hole.midY, width: 0, height: 0)
        ZStack(alignment: .topLeading) {
            // The mask with the holes punched out. `contentShape` makes the
            // whole rectangle — holes included — hit-testable, so nothing
            // underneath (shutter, viewfinder gestures, the day-count text)
            // ever gets a touch; the proxy button below sits over the
            // interactive hole and is the one way through (96.6, 96.19).
            SpotlightMaskShape(primary: geometry.hole, secondary: secondary)
                .fill(CameraTheme.ink.opacity(Self.maskOpacity), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

            ring(around: geometry.hole, cornerRadius: min(geometry.hole.width, geometry.hole.height) / 2)

            ring(around: secondary, cornerRadius: OnboardingSpotlightGeometry.overlayTextCornerRadius)
                .opacity(geometry.secondaryHole == nil ? 0 : 1)

            Button(action: onTargetTap) {
                Color.clear
                    .frame(width: geometry.hole.width, height: geometry.hole.height)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .position(x: geometry.hole.midX, y: geometry.hole.midY)
            .accessibilityLabel(targetLabel)
            .accessibilityIdentifier("onboardingTarget")

            bubble(geometry: geometry)
        }
        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboardingSpotlight")
        .accessibilityAction(.escape) { onEscape() }
        .onAppear { isBubbleFocused = true }
        .onChange(of: step) { _, _ in isBubbleFocused = true }
    }

    /// The accent outline just outside a hole.
    private func ring(around hole: CGRect, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(CameraTheme.accent, lineWidth: Self.ringWidth)
            .frame(width: hole.width, height: hole.height)
            .position(x: hole.midX, y: hole.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func bubble(geometry: OnboardingSpotlightGeometry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.stepLabel)
                .font(.caption.monospacedDigit())
                .foregroundColor(CameraTheme.inkSecondary)
                .accessibilityIdentifier("onboardingStep")
                .accessibilityFocused($isBubbleFocused)
            Text(step.title)
                .font(.headline)
                .foregroundColor(CameraTheme.ink)
                .accessibilityIdentifier("onboardingTitle")
            Text(step.message)
                .font(.subheadline)
                .foregroundColor(CameraTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboardingMessage")
            HStack {
                Spacer()
                Button(action: onAdvance) {
                    Text(step.buttonTitle)
                        .font(CameraTheme.toolFont(.subheadline))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(CameraTheme.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboardingAdvance")
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(width: geometry.bubble.width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CameraTheme.popoverBackground)
                .shadow(color: CameraTheme.popoverShadow, radius: 12, x: 0, y: 6)
        )
        .overlay(alignment: arrowAlignment(geometry.arrowEdge)) {
            arrow(geometry: geometry)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: BubbleHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(BubbleHeightKey.self) { height in
            if height > 0 { bubbleHeight = height }
        }
        .offset(x: geometry.bubble.minX, y: geometry.bubble.minY)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboardingBubble")
    }

    private func arrowAlignment(_ edge: OnboardingSpotlightGeometry.ArrowEdge) -> Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .trailing: return .trailing
        }
    }

    /// The little pointer on the bubble's edge, aimed at the target.
    private func arrow(geometry: OnboardingSpotlightGeometry) -> some View {
        let h = OnboardingSpotlightGeometry.arrowHeight
        let w = geometry.bubble.width
        return Group {
            switch geometry.arrowEdge {
            case .top:
                BubbleArrow(edge: .top).fill(CameraTheme.popoverBackground)
                    .frame(width: 16, height: h)
                    .offset(x: geometry.arrowOffset - w / 2, y: -h)
            case .bottom:
                BubbleArrow(edge: .bottom).fill(CameraTheme.popoverBackground)
                    .frame(width: 16, height: h)
                    .offset(x: geometry.arrowOffset - w / 2, y: h)
            case .trailing:
                BubbleArrow(edge: .trailing).fill(CameraTheme.popoverBackground)
                    .frame(width: h, height: 16)
                    .offset(x: h, y: geometry.arrowOffset - bubbleHeight / 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The screen rectangle minus one or two rounded holes (even-odd fill).
/// Animatable, so the holes slide from the chip to the panel button and the
/// day-count text on the step change. `secondary` may be empty (zero size),
/// which draws nothing.
struct SpotlightMaskShape: Shape {
    var primary: CGRect
    var secondary: CGRect

    typealias RectData = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>

    var animatableData: AnimatablePair<RectData, RectData> {
        get { AnimatablePair(Self.data(primary), Self.data(secondary)) }
        set {
            primary = Self.rect(newValue.first)
            secondary = Self.rect(newValue.second)
        }
    }

    private static func data(_ rect: CGRect) -> RectData {
        AnimatablePair(AnimatablePair(rect.minX, rect.minY), AnimatablePair(rect.width, rect.height))
    }

    private static func rect(_ data: RectData) -> CGRect {
        CGRect(x: data.first.first, y: data.first.second, width: data.second.first, height: data.second.second)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let radius = min(primary.width, primary.height) / 2
        path.addRoundedRect(in: primary, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        if secondary.width > 0, secondary.height > 0 {
            let r = min(OnboardingSpotlightGeometry.overlayTextCornerRadius, min(secondary.width, secondary.height) / 2)
            path.addRoundedRect(in: secondary, cornerSize: CGSize(width: r, height: r), style: .continuous)
        }
        return path
    }
}

/// The bubble's little pointer, drawn to point away from `edge`.
private struct BubbleArrow: Shape {
    let edge: OnboardingSpotlightGeometry.ArrowEdge

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch edge {
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottom:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .trailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

private struct BubbleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

#Preview("第 1 步（96.1）") {
    ZStack {
        CameraTheme.background.ignoresSafeArea()
        OnboardingSpotlightView(step: .startDate,
                                targetFrame: CGRect(x: 150, y: 70, width: 92, height: 34),
                                screenSize: CGSize(width: 393, height: 852),
                                targetLabel: "設定檔：小寶",
                                onAdvance: {}, onTargetTap: {}, onEscape: {})
    }
    .ignoresSafeArea()
}

#Preview("第 2 步（96.2，按鈕＋天數文字）") {
    ZStack {
        CameraTheme.background.ignoresSafeArea()
        OnboardingSpotlightView(step: .overlayStyle,
                                targetFrame: CGRect(x: 319, y: 760, width: 44, height: 44),
                                overlayTextFrame: CGRect(x: 280, y: 580, width: 90, height: 34),
                                screenSize: CGSize(width: 393, height: 852),
                                targetLabel: "疊字設定",
                                onAdvance: {}, onTargetTap: {}, onEscape: {})
    }
    .ignoresSafeArea()
}
