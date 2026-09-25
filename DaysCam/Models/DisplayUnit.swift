import Foundation

/// A unit used to express the elapsed amount in the overlay text.
///
/// A profile checks any non-empty set of these; they are always printed in
/// declaration order, year to day (PRD 0.2 §4.5).
enum DisplayUnit: String, Codable, CaseIterable {
    case year
    case month
    case week
    case day
}
