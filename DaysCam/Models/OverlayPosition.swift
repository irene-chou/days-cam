import Foundation

/// One of nine anchor points for the overlay text within the frame.
enum OverlayPosition: String, Codable, CaseIterable {
    case topLeading
    case topCenter
    case topTrailing
    case middleLeading
    case middleCenter
    case middleTrailing
    case bottomLeading
    case bottomCenter
    case bottomTrailing
}
