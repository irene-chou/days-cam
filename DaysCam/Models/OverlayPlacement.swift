import Foundation

/// Where the overlay sits in the photo (PRD 0.2 §4.1).
///
/// `.anchor` snaps to one of the nine grid points with the 0.1 alignment rules
/// (FR-12.5). `.custom` stores the center of the overlay box as a fraction of
/// the photo's width and height, 0...1 (A-1); the renderer clamps the box into
/// the 4% margin without changing the stored values (FR-12.6).
enum OverlayPlacement: Equatable, Hashable, Codable {
    case anchor(OverlayPosition)
    case custom(x: Double, y: Double)

    /// The default placement of a new profile.
    static let `default`: OverlayPlacement = .anchor(.bottomTrailing)

    /// Whether a `.custom` center lies inside 0...1 on both axes. Always true
    /// for `.anchor`.
    var isInRange: Bool {
        switch self {
        case .anchor:
            return true
        case let .custom(x, y):
            let unit = 0.0...1.0
            return unit.contains(x) && unit.contains(y)
        }
    }

    // Encoded as `{"anchor": "bottomTrailing"}` or `{"x": 0.5, "y": 0.5}`,
    // which reads better in `profiles.json` than the synthesized `_0` form.
    private enum CodingKeys: String, CodingKey {
        case anchor
        case x
        case y
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let position = try container.decodeIfPresent(OverlayPosition.self, forKey: .anchor) {
            self = .anchor(position)
        } else {
            self = .custom(x: try container.decode(Double.self, forKey: .x),
                           y: try container.decode(Double.self, forKey: .y))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .anchor(position):
            try container.encode(position, forKey: .anchor)
        case let .custom(x, y):
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        }
    }
}
