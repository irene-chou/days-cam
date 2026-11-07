import SwiftUI

/// The level's line in the middle of the viewfinder (#687-4): three short
/// segments, the middle one tilting with the phone, which join into one
/// `accent` line when level. Draws only; `ViewfinderLevelModel` decides what
/// shows. Takes no touches.
struct LevelIndicatorView: View {
    let display: LevelDisplay
    /// Turns the whole line to follow how the phone is held.
    var rotation: ViewfinderRotation = .portrait

    static let thickness: CGFloat = 1
    static let sideLength: CGFloat = 36
    static let middleLength: CGFloat = 96
    static let gap: CGFloat = 8
    static let levelLength = sideLength * 2 + middleLength + gap * 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if display != .hidden {
                line
                    .rotatedChrome(rotation)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: display == .hidden)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var line: some View {
        let isLevel = display == .level
        Group {
            if isLevel {
                segment(Self.levelLength)
            } else {
                HStack(spacing: Self.gap) {
                    segment(Self.sideLength)
                    segment(Self.middleLength)
                        // The line stays on the horizon, so it turns against the tilt.
                        .rotationEffect(.degrees(-angle))
                    segment(Self.sideLength)
                }
            }
        }
        .foregroundColor(isLevel ? CameraTheme.accent : .white.opacity(0.8))
        .shadow(color: .black.opacity(0.35), radius: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("水平儀")
        .accessibilityValue(isLevel ? "水平" : "\(Int(angle.rounded())) 度")
        .accessibilityIdentifier("levelIndicator")
        // Purely visual; the UI tests read it in debug builds.
        .accessibilityHidden(!Self.exposesToTests)
    }

    private var angle: Double {
        if case .visible(let angle) = display { return angle }
        return 0
    }

    private func segment(_ length: CGFloat) -> some View {
        Capsule().frame(width: length, height: Self.thickness)
    }

    private static var exposesToTests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITestLevelAngle")
        #else
        false
        #endif
    }
}

/// Observes the model so only the line redraws at sensor rate.
struct ViewfinderLevelOverlay: View {
    @ObservedObject var level: ViewfinderLevelModel
    let rotation: ViewfinderRotation

    var body: some View {
        LevelIndicatorView(display: level.display, rotation: rotation)
    }
}
