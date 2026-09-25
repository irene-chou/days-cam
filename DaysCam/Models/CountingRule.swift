import Foundation

/// Whether the start date itself counts as day one or day zero.
///
/// Applies only when neither year nor month is displayed; once either is, the
/// amount is a raw calendar difference and never adds one (PRD 0.2 §4.5 U-3, U-4).
enum CountingRule: String, Codable, CaseIterable {
    /// The start date is day 1.
    case dayOne
    /// The start date is day 0.
    case dayZero
}
