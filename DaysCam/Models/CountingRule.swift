import Foundation

/// Whether the start date itself counts as day one or day zero.
///
/// Applies only to the day and week unit tracks; the year and month tracks
/// use a raw calendar difference and never add one (see PRD FR-2.11).
enum CountingRule: String, Codable, CaseIterable {
    /// The start date is day 1.
    case dayOne
    /// The start date is day 0.
    case dayZero
}
