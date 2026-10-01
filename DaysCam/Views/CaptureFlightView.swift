import SwiftUI

/// One captured photo lifting off the viewfinder and flying into the
/// thumbnail button (issue #148): it appears exactly over the viewfinder,
/// lifts (96%, shadow, rounded corners) for 0.12s, then flies and shrinks to
/// the thumbnail's frame over 0.35s. Pure presentation — `CameraScreenModel`
/// owns the flight's state and decides when the thumbnail actually changes.
struct CaptureFlightView: View {
    private enum Phase {
        case resting, lifted, flown
    }

    let flight: CaptureFlight
    /// The picture's frame in screen coordinates, captured when the flight
    /// appears (what the user was just looking at).
    let start: CGRect
    /// The thumbnail button's frame; read live so a panel toggled mid-flight
    /// still lands on the right spot.
    let end: CGRect
    /// True when there is nothing to fly to (the panel is open, so the left
    /// button is not the thumbnail): no flight, the thumbnail just updates.
    let skipsFlightWhenPanelOpen: Bool
    /// Reached the thumbnail button.
    let onLanded: () -> Void
    /// Failure fade-out finished; the flight can be dropped.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .resting
    @State private var isFadedOut = false
    /// Whether to skip the flight, decided once when the flight appears.
    @State private var skipsFlight: Bool

    init(flight: CaptureFlight, start: CGRect, end: CGRect, skipsFlightWhenPanelOpen: Bool,
         onLanded: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.flight = flight
        self.start = start
        self.end = end
        self.skipsFlightWhenPanelOpen = skipsFlightWhenPanelOpen
        self.onLanded = onLanded
        self.onFinished = onFinished
        _skipsFlight = State(initialValue: skipsFlightWhenPanelOpen)
    }

    private static let liftDuration: TimeInterval = 0.12
    private static let flightDuration: TimeInterval = 0.35

    var body: some View {
        let frame = currentFrame
        Image(uiImage: flight.image)
            .resizable()
            .scaledToFill()
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: CameraTheme.flightShadow, radius: phase == .lifted ? 16 : 0, x: 0, y: phase == .lifted ? 6 : 0)
            .position(x: frame.midX, y: frame.midY)
            .opacity(isHidden ? 0 : 1)
            .task { await play() }
            .onChange(of: flight.status) { _, status in
                if status == .failed { Task { await fadeOutAfterFailure() } }
            }
    }

    private var isHidden: Bool {
        reduceMotion || skipsFlight || isFadedOut
    }

    private var currentFrame: CGRect {
        switch phase {
        case .resting:
            return start
        case .lifted:
            let scale: CGFloat = 0.96
            let size = CGSize(width: start.width * scale, height: start.height * scale)
            return CGRect(x: start.midX - size.width / 2, y: start.midY - size.height / 2,
                          width: size.width, height: size.height)
        case .flown:
            return end
        }
    }

    private var cornerRadius: CGFloat {
        switch phase {
        case .resting: return 0
        case .lifted: return 12
        case .flown: return 10
        }
    }

    private func play() async {
        guard !reduceMotion, !skipsFlight else {
            // No flight: the thumbnail just updates once saved (the button
            // fades itself under Reduce Motion).
            onLanded()
            return
        }
        withAnimation(.easeOut(duration: Self.liftDuration)) { phase = .lifted }
        try? await Task.sleep(nanoseconds: UInt64(Self.liftDuration * 1_000_000_000))
        withAnimation(CameraTheme.spring) { phase = .flown }
        try? await Task.sleep(nanoseconds: UInt64(Self.flightDuration * 1_000_000_000))
        // The model waits for the save: this view stays parked on the
        // thumbnail until it removes the flight (saved) or flags it failed
        // (the fade-out above).
        onLanded()
    }

    private func fadeOutAfterFailure() async {
        withAnimation(.easeOut(duration: 0.2)) { isFadedOut = true }
        try? await Task.sleep(nanoseconds: 250_000_000)
        onFinished()
    }
}

/// The thumbnail button's small bounce (scale 1 → 1.12 → 1, ~0.2s) when a
/// flight lands (issue #148). Does nothing under Reduce Motion; the new photo
/// just fades in.
struct ThumbnailLandingEffect: ViewModifier {
    let landingCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: landingCount) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.1)) { scale = 1.12 }
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    withAnimation(.easeIn(duration: 0.1)) { scale = 1 }
                }
            }
    }
}
