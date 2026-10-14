import SwiftUI

/// A system `Slider` that also jumps to a tapped point on its track
/// (TASK-114). Dragging is the system slider's own; a recognized tap seeks
/// to that point, snapped to `step`, and calls `onChange` once. The tap is a
/// `SpatialTapGesture`, which fails once the touch moves, so it never takes
/// over the slider's drag tracking (#551).
struct TapSeekSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    var isDisabled = false
    let onChange: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trackWidth: CGFloat = 0

    /// Half of the system slider's 27pt thumb (`UISlider` default thumb
    /// image), rounded up: the track's usable length excludes a thumb radius
    /// at each end, which is how the system maps a drag to a value.
    static let thumbRadius: CGFloat = 14

    var body: some View {
        Slider(value: Binding(get: { value }, set: onChange), in: range, step: step)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { trackWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in trackWidth = width }
                }
            )
            // Simultaneous, so the slider's own drag still works; a tap on the
            // thumb seeks to where the thumb already is and changes nothing.
            .simultaneousGesture(seekGesture)
    }

    private var seekGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .onEnded { tap in
                guard !isDisabled, trackWidth > 0 else { return }
                // A tap on the thumb itself is not a seek: at the thumb's
                // edge the tapped point could otherwise be a step away.
                guard !Self.isOnThumb(x: tap.location.x, value: value, trackWidth: trackWidth,
                                      thumbRadius: Self.thumbRadius, range: range) else { return }
                let target = Self.value(atX: tap.location.x, trackWidth: trackWidth,
                                        thumbRadius: Self.thumbRadius, range: range, step: step)
                guard target != value else { return }
                if reduceMotion {
                    onChange(target)
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) { onChange(target) }
                }
            }
    }

    /// The x of the thumb's centre for `value`: the inverse of `value(atX:)`.
    static func thumbCenterX(for value: Double, trackWidth: CGFloat, thumbRadius: CGFloat,
                             range: ClosedRange<Double>) -> CGFloat {
        let usable = max(1, trackWidth - thumbRadius * 2)
        let span = range.upperBound - range.lowerBound
        let fraction = span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
        return thumbRadius + CGFloat(fraction) * usable
    }

    /// Whether a tap at `x` lands on the thumb drawn for `value`.
    static func isOnThumb(x: CGFloat, value: Double, trackWidth: CGFloat, thumbRadius: CGFloat,
                          range: ClosedRange<Double>) -> Bool {
        abs(x - thumbCenterX(for: value, trackWidth: trackWidth, thumbRadius: thumbRadius, range: range)) <= thumbRadius
    }

    /// The value a tap at `x` (in the slider's own coordinates) seeks to: the
    /// track between the two thumb-radius end zones maps linearly onto
    /// `range`, the end zones give the bounds, and the result is snapped to
    /// `step` from the lower bound and clamped.
    static func value(atX x: CGFloat, trackWidth: CGFloat, thumbRadius: CGFloat,
                      range: ClosedRange<Double>, step: Double) -> Double {
        let usable = max(1, trackWidth - thumbRadius * 2)
        let fraction = min(max((x - thumbRadius) / usable, 0), 1)
        let raw = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
        let snapped = step > 0 ? range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step : raw
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}
