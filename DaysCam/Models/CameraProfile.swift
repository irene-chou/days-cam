import Foundation

/// A way in which a `CameraProfile` can violate the invariants of PRD §4.1.
enum CameraProfileValidationError: Error, Equatable {
    /// `name` is empty after trimming whitespace (invariant 1).
    case nameEmpty
    /// `name` is longer than 20 characters after trimming (invariant 1).
    case nameTooLong(length: Int)
    /// `startDate` is missing one of `year`, `month` or `day` (invariant 2).
    case startDateMissingComponents
    /// `startDate` carries components other than `year`, `month` and `day`,
    /// such as `hour`, `timeZone` or `calendar` (invariant 2).
    case startDateHasExtraComponents
    /// `startDate` names a day that does not exist, such as `2026-02-30`
    /// or `month: 13` (invariant 2).
    case startDateNotARealDate
    /// Both `showDayCount` and `showDate` are off (invariant 3).
    case displaySwitchesAllOff
    /// `smallestUnit` is not on `largestUnit`'s track (invariant 4).
    case unitPairNotOnSameTrack(largest: DisplayUnit, smallest: DisplayUnit)
    /// `useAgeWording` is on while `largestUnit` is not `.year` (invariant 5).
    case ageWordingRequiresYearUnit
}

/// One saved set of overlay settings: what to print, how to count and how it looks.
///
/// The memberwise initializer deliberately performs **no** validation, so an
/// invalid profile can be constructed — tests need that, and an editing screen
/// holds a half-finished profile while the user types. The invariants of
/// PRD §4.1 are enforced by the persistence layer, which calls
/// `validatedForPersistence(calendar:)` on every write and every read.
struct CameraProfile: Identifiable, Equatable, Codable {
    /// Maximum length of `name` after trimming (PRD FR-1.6).
    static let maximumNameLength = 20

    /// Stable identity, assigned once at creation.
    let id: UUID
    /// User-facing name. Required, 1...20 characters after trimming.
    var name: String
    /// The day the count starts from, holding `year`, `month` and `day` only.
    ///
    /// Stored as `DateComponents` rather than `Date` on purpose: a start date is
    /// a mark on a calendar, not an instant, and storing an instant makes it
    /// drift by a day when the user changes time zone (PRD §9).
    var startDate: DateComponents
    /// Whether the start date itself is day 1 or day 0.
    var countingRule: CountingRule
    /// Whether the elapsed amount is printed.
    var showDayCount: Bool
    /// Whether the capture date is printed.
    var showDate: Bool
    /// Whether `name` is printed ahead of the rest of the overlay.
    var showName: Bool
    /// Largest unit of the elapsed amount; also picks the unit track.
    var largestUnit: DisplayUnit
    /// Smallest unit of the elapsed amount; must sit on `largestUnit`'s track.
    var smallestUnit: DisplayUnit
    /// Whether years are printed as ages. Only valid when `largestUnit` is `.year`.
    var useAgeWording: Bool
    /// Which of the nine anchor points the overlay is drawn at.
    var position: OverlayPosition
    /// Which preset theme the overlay is drawn with.
    var themeID: ThemeID
    /// When this profile was created.
    var createdAt: Date
    /// When this profile was last modified.
    var updatedAt: Date

    /// Creates a profile without validating it.
    ///
    /// Defaults follow PRD FR-1.9. Validation is the persistence layer's job, so
    /// this initializer accepts states that could never be saved.
    init(id: UUID = UUID(),
         name: String,
         startDate: DateComponents,
         countingRule: CountingRule = .dayOne,
         showDayCount: Bool = true,
         showDate: Bool = false,
         showName: Bool = false,
         largestUnit: DisplayUnit = .day,
         smallestUnit: DisplayUnit = .day,
         useAgeWording: Bool = false,
         position: OverlayPosition = .bottomTrailing,
         themeID: ThemeID = .classicWhite,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.countingRule = countingRule
        self.showDayCount = showDayCount
        self.showDate = showDate
        self.showName = showName
        self.largestUnit = largestUnit
        self.smallestUnit = smallestUnit
        self.useAgeWording = useAgeWording
        self.position = position
        self.themeID = themeID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Invariants

extension CameraProfile {
    /// A copy with the repairable deviations of PRD §4.1 corrected.
    ///
    /// Trims `name`, and rebuilds `startDate` from its `year`, `month` and `day`
    /// so that stray components — `hour`, `minute`, `second`, `timeZone`,
    /// `calendar` and the rest — are dropped. Values that are simply wrong, such
    /// as `month: 13`, are left alone for `validate(calendar:)` to reject.
    func normalized() -> CameraProfile {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var stripped = DateComponents()
        stripped.year = startDate.year
        stripped.month = startDate.month
        stripped.day = startDate.day
        copy.startDate = stripped
        return copy
    }

    /// Throws if this profile violates any of the five invariants of PRD §4.1.
    ///
    /// Does not repair anything: a profile carrying a `timeZone` in `startDate`
    /// fails here. Call `normalized()` first to strip what can be stripped.
    func validate(calendar: Calendar = .current) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw CameraProfileValidationError.nameEmpty
        }
        if trimmedName.count > Self.maximumNameLength {
            throw CameraProfileValidationError.nameTooLong(length: trimmedName.count)
        }

        guard startDate.carriesOnlyYearMonthDay else {
            throw CameraProfileValidationError.startDateHasExtraComponents
        }
        guard let year = startDate.year,
              let month = startDate.month,
              let day = startDate.day else {
            throw CameraProfileValidationError.startDateMissingComponents
        }
        // `Calendar.date(from:)` happily rolls invalid input over — `month: 13`
        // becomes the next January, `2026-02-30` becomes March 2 — so the only
        // reliable check is to convert and convert back.
        var probe = DateComponents()
        probe.year = year
        probe.month = month
        probe.day = day
        guard let resolved = calendar.date(from: probe) else {
            throw CameraProfileValidationError.startDateNotARealDate
        }
        let roundTripped = calendar.dateComponents([.year, .month, .day], from: resolved)
        guard roundTripped.year == year,
              roundTripped.month == month,
              roundTripped.day == day else {
            throw CameraProfileValidationError.startDateNotARealDate
        }

        if !showDayCount && !showDate {
            throw CameraProfileValidationError.displaySwitchesAllOff
        }

        guard DisplayUnitTrack.isLegalPair(largest: largestUnit, smallest: smallestUnit) else {
            throw CameraProfileValidationError.unitPairNotOnSameTrack(largest: largestUnit,
                                                                     smallest: smallestUnit)
        }

        if useAgeWording && largestUnit != .year {
            throw CameraProfileValidationError.ageWordingRequiresYearUnit
        }
    }

    /// The normalized profile, or an error describing why it cannot be saved.
    ///
    /// This is the single entry point the persistence layer uses on both the
    /// write path (reject the write) and the read path (discard the record).
    func validatedForPersistence(calendar: Calendar = .current) throws -> CameraProfile {
        let candidate = normalized()
        try candidate.validate(calendar: calendar)
        return candidate
    }
}

extension DateComponents {
    /// Whether only `year`, `month` and `day` carry values.
    ///
    /// `DateComponents` is a loose bag, and two of its other properties are
    /// actively dangerous on a stored start date: a `timeZone` makes
    /// `Calendar.date(from:)` resolve the date in that zone instead of the
    /// device's, shifting it by a day, and a `calendar` makes the `date`
    /// property resolve in that calendar — a Buddhist one is off by 543 years
    /// (PRD §4.1).
    var carriesOnlyYearMonthDay: Bool {
        era == nil
            && hour == nil
            && minute == nil
            && second == nil
            && nanosecond == nil
            && weekday == nil
            && weekdayOrdinal == nil
            && quarter == nil
            && weekOfMonth == nil
            && weekOfYear == nil
            && yearForWeekOfYear == nil
            && timeZone == nil
            && calendar == nil
    }
}
