import Foundation

/// How a day-only count is written (#582, design option A).
///
/// Applies only when `displayUnits == [.day]`; once any of year, month or
/// week is checked the count keeps the Chinese unit wording of PRD 0.2 §4.5
/// and this setting plays no part.
///
/// - `ordinal`: 第 N 天 (the wording before #582).
/// - `plain`: N 天.
/// - `dayN`: Day N.
/// - `dDay`: D+N after the start date, D-Day on it, D-N before it. Ignores
///   the counting rule: by convention the start date itself is D-Day.
enum DayCountFormat: String, Codable, CaseIterable {
    case ordinal
    case plain
    case dayN
    case dDay

    /// The wording a new profile, an old profile file, or an unrecognized
    /// stored value gets.
    static let `default`: DayCountFormat = .ordinal

    /// Decodes a stored wording, falling back to `default` for a string no
    /// version of the app wrote, so one bad value never loses a profile.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DayCountFormat(rawValue: raw) ?? .default
    }

    /// Whether `count` follows the profile's counting rule. Only `dDay`
    /// counts from the raw difference, so the start date is always D-Day.
    var usesCountingRule: Bool {
        self != .dDay
    }

    /// The elapsed day count, `count ≥ 0`, in this wording.
    func elapsedText(count: Int) -> String {
        switch self {
        case .ordinal: return "第 \(count) 天"
        case .plain: return "\(count) 天"
        case .dayN: return "Day \(count)"
        case .dDay: return count == 0 ? "D-Day" : "D+\(count)"
        }
    }

    /// The days left before a future start date, `daysUntilStart ≥ 1`, in
    /// this wording. `ordinal` and `plain` share `還有 N 天` with
    /// `TemplateRenderer.notStartedText(daysUntilStart:)`.
    func countdownText(daysUntilStart: Int) -> String {
        switch self {
        case .ordinal, .plain: return "還有 \(daysUntilStart) 天"
        case .dayN: return "\(daysUntilStart) days to go"
        case .dDay: return "D-\(daysUntilStart)"
        }
    }
}
