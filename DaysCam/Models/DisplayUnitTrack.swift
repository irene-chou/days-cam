import Foundation

/// A legal `(largestUnit, smallestUnit)` pairing for the overlay's elapsed amount.
///
/// Exactly eight pairs are legal (PRD §4.1 invariant 4). Weeks form their own
/// track and are never mixed with years or months, because "1 year 2 months
/// 3 weeks and 4 days" does not read sensibly.
struct DisplayUnitPair: Equatable, Hashable {
    let largest: DisplayUnit
    let smallest: DisplayUnit

    init(largest: DisplayUnit, smallest: DisplayUnit) {
        self.largest = largest
        self.smallest = smallest
    }
}

/// The unit tracks that govern which `(largest, smallest)` unit pairs are legal.
///
/// A track is identified by its largest unit. Picking a largest unit fixes the
/// track; the smallest unit must then be one of the units on that same track
/// (PRD §3.2 and FR-2.8).
///
/// | Largest | Track            | Value source                             |
/// |---------|------------------|------------------------------------------|
/// | year    | year, month, day | calendar difference (year, month, day)   |
/// | month   | month, day       | calendar difference (month, day)          |
/// | week    | week, day        | `q = n / 7`, `r = n % 7`                  |
/// | day     | day              | `n`                                       |
///
/// This lives in its own file rather than in `DisplayUnit.swift` so that the
/// shared enum keeps exactly its four cases.
enum DisplayUnitTrack {
    /// The units of the track led by `largestUnit`, ordered largest to smallest.
    static func units(forLargest largestUnit: DisplayUnit) -> [DisplayUnit] {
        switch largestUnit {
        case .year:
            return [.year, .month, .day]
        case .month:
            return [.month, .day]
        case .week:
            return [.week, .day]
        case .day:
            return [.day]
        }
    }

    /// The smallest units that may be paired with `largestUnit`.
    ///
    /// Identical to `units(forLargest:)`: every unit on a track may also be the
    /// track's smallest unit. Exposed under its own name because that is what
    /// the picker in the display settings panel needs.
    static func allowedSmallestUnits(forLargest largestUnit: DisplayUnit) -> [DisplayUnit] {
        units(forLargest: largestUnit)
    }

    /// Whether `smallest` sits on `largest`'s track and is not larger than it.
    static func isLegalPair(largest: DisplayUnit, smallest: DisplayUnit) -> Bool {
        units(forLargest: largest).contains(smallest)
    }

    /// Every legal pair, ordered by largest unit and then by smallest unit.
    ///
    /// Exactly eight entries (PRD §4.1 invariant 4).
    static let legalPairs: [DisplayUnitPair] = DisplayUnit.allCases.flatMap { largest in
        units(forLargest: largest).map { DisplayUnitPair(largest: largest, smallest: $0) }
    }

    /// The units actually rendered for a pair, ordered largest to smallest.
    ///
    /// Returns the slice of the track running from `largest` down to `smallest`
    /// inclusive, or an empty array when the pair is not legal. For example
    /// `(year, month)` yields `[.year, .month]`, dropping the day.
    static func units(largest: DisplayUnit, smallest: DisplayUnit) -> [DisplayUnit] {
        let track = units(forLargest: largest)
        guard let end = track.firstIndex(of: smallest) else { return [] }
        return Array(track[track.startIndex...end])
    }
}
