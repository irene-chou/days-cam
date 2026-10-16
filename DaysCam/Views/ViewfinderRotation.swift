import SwiftUI

/// How the phone is held, as far as the viewfinder's overlay layer and the
/// camera chrome icons are concerned (#572). The interface itself stays
/// portrait; only the overlay layer (text, film date, countdown) and the
/// icons turn, so they match what the baked photo will show.
enum ViewfinderRotation: Equatable {
    case portrait
    /// Landscape, the phone's top edge pointing left (capture angle 0).
    case landscapeTopLeft
    /// Landscape, the phone's top edge pointing right (capture angle 180).
    case landscapeTopRight
    case upsideDown

    /// Maps `CameraService.captureRotationAngle` (0, 90, 180 or 270) to a
    /// rotation. Any other value counts as portrait.
    init(captureAngle: CGFloat) {
        switch captureAngle {
        case 0: self = .landscapeTopLeft
        case 180: self = .landscapeTopRight
        case 270: self = .upsideDown
        default: self = .portrait
        }
    }

    /// The `rotationEffect` angle in degrees, `90 - captureAngle`.
    var degrees: Double {
        switch self {
        case .portrait: return 0
        case .landscapeTopLeft: return 90
        case .landscapeTopRight: return -90
        case .upsideDown: return 180
        }
    }

    /// Whether the baked photo is landscape for this rotation.
    var isLandscape: Bool {
        self == .landscapeTopLeft || self == .landscapeTopRight
    }

    /// The size the overlay layer lays out in: the photo's own width and
    /// height. Landscape swaps the viewfinder box's sides.
    func frameSize(for box: CGSize) -> CGSize {
        isLandscape ? CGSize(width: box.height, height: box.width) : box
    }

    /// Converts a rectangle in the rotated layer's coordinates to the
    /// viewfinder box's coordinates (the layer turns about the box's center).
    /// A null rectangle stays null.
    func boxRect(fromRotatedRect rect: CGRect, box: CGSize) -> CGRect {
        guard !rect.isNull else { return rect }
        guard self != .portrait else { return rect }
        let layer = frameSize(for: box)
        let radians = degrees * .pi / 180
        let cosine = CGFloat(cos(radians)), sine = CGFloat(sin(radians))
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        let mapped = corners.map { point -> CGPoint in
            let dx = point.x - layer.width / 2, dy = point.y - layer.height / 2
            return CGPoint(x: box.width / 2 + dx * cosine - dy * sine,
                           y: box.height / 2 + dx * sine + dy * cosine)
        }
        let xs = mapped.map(\.x), ys = mapped.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return rect }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Turns a label in place, with the spring unless Reduce Motion is on.
private struct RotatedChrome: ViewModifier {
    let rotation: ViewfinderRotation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation.degrees))
            .animation(reduceMotion ? nil : CameraTheme.spring, value: rotation)
    }
}

extension View {
    /// Turns this label upright for the way the phone is held. Apply it to a
    /// button's label, never to the button, so the touch area, accessibility
    /// label and identifier stay put.
    func rotatedChrome(_ rotation: ViewfinderRotation) -> some View {
        modifier(RotatedChrome(rotation: rotation))
    }
}
