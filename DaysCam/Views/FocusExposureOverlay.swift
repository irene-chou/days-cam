import SwiftUI

/// The focus square, the exposure sun beside it and the AE/AF lock label
/// (issue #303). Draws only; `ViewfinderFocusModel` decides what shows. Takes
/// no touches: the viewfinder's own gesture does all the work.
struct FocusExposureOverlay: View {
    @ObservedObject var focus: ViewfinderFocusModel
    let frameSize: CGSize

    static let squareSize: CGFloat = 70
    private static let sunSize: CGFloat = 22
    private static let sunGap: CGFloat = 14
    private static let yellow = Color(red: 1, green: 0.84, blue: 0.04)

    var body: some View {
        ZStack(alignment: .top) {
            if let reticle = focus.reticle {
                reticleView(reticle)
                    .transition(.opacity)
            }
            if focus.isLocked {
                Text("AE/AF 鎖定")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Self.yellow, in: Capsule())
                    .padding(.top, 12)
                    .transition(.opacity)
                    .accessibilityIdentifier("focusLockLabel")
            }
        }
        .frame(width: frameSize.width, height: frameSize.height, alignment: .top)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: focus.reticle?.id)
        .animation(.easeOut(duration: 0.2), value: focus.isLocked)
    }

    @ViewBuilder
    private func reticleView(_ reticle: ViewfinderFocusModel.Reticle) -> some View {
        let half = Self.squareSize / 2
        // Beside the square on the right, or on the left near that edge.
        let sunOnRight = reticle.layerPoint.x + half + Self.sunGap + Self.sunSize + 24 < frameSize.width
        let sunOffset = (half + Self.sunGap + Self.sunSize / 2) * (sunOnRight ? 1 : -1)
        ReticleSquare()
            .stroke(Self.yellow, lineWidth: 1.5)
            .frame(width: Self.squareSize, height: Self.squareSize)
            .modifier(ReticleEntrance())
            .id(reticle.id)
            .accessibilityElement()
            .accessibilityLabel("對焦點")
            .accessibilityIdentifier("focusReticle")
            .position(x: reticle.layerPoint.x, y: reticle.layerPoint.y)
            .opacity(focus.isReticleDimmed ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.4), value: focus.isReticleDimmed)

        VStack(spacing: 2) {
            Image(systemName: "sun.max")
                .font(.system(size: Self.sunSize, weight: .regular))
                .foregroundColor(Self.yellow)
                .accessibilityHidden(true)
            if let text = ViewfinderFocusModel.biasText(for: focus.displayedBias) {
                Text(text)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(Self.yellow)
                    .fixedSize()
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("曝光補償")
        .accessibilityValue(ViewfinderFocusModel.biasText(for: focus.displayedBias) ?? "0")
        .accessibilityIdentifier("focusSun")
        .position(x: reticle.layerPoint.x + sunOffset, y: reticle.layerPoint.y)
        .opacity(focus.isReticleDimmed ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.4), value: focus.isReticleDimmed)
    }
}

/// A square with a short tick at the middle of each side, as the system
/// camera draws its focus box.
private struct ReticleSquare: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let tick: CGFloat = 5
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + tick))
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - tick))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + tick, y: rect.midY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - tick, y: rect.midY))
        return path
    }
}

/// The square lands from 1.5x down to 1x each time a new reticle starts.
private struct ReticleEntrance: ViewModifier {
    @State private var landed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(landed ? 1 : 1.5)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { landed = true }
            }
    }
}
