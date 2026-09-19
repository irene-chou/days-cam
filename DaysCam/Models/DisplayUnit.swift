import Foundation

/// A unit used to express the elapsed amount in the overlay text.
///
/// A profile picks a largest and a smallest unit; the units in between are
/// filled in automatically. Weeks form their own track and are never mixed
/// with years or months (see PRD FR-2.8).
enum DisplayUnit: String, Codable, CaseIterable {
    case year
    case month
    case week
    case day
}
