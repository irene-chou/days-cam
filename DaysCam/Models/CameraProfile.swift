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
    ///
    /// Not reachable through `validatedForPersistence(calendar:)`:
    /// `normalized()` repairs that one case by turning `showDayCount` on
    /// (TASK-107, #426), so no profile is dropped for it.
    case displaySwitchesAllOff
    /// `displayUnits` is empty (PRD 0.2 §4.1, replacing 0.1 invariant 4).
    case displayUnitsEmpty
    /// `style.sizeScale` is outside 70...160 or not a multiple of 5 (PRD 0.2 §4.1).
    case sizeScaleOutOfRange(Int)
    /// `position` is `.custom` with `x` or `y` outside 0...1 (PRD 0.2 §4.1).
    case customPositionOutOfRange(x: Double, y: Double)
    /// `style.textColor`, `style.outlineColor` or `style.shadowColor` has an
    /// RGB component outside 0...1, or one of them or
    /// `style.autoOutlineOpacity` has an opacity outside
    /// `OverlayColor.minimumStorableOpacity`...1 (PRD 0.2 §4.1 as amended by
    /// TASK-69, TASK-70 and TASK-71).
    case colorNotStorable
    /// `style.strokeWidth` or `style.boxPadding` is outside its range
    /// (TASK-70).
    case outlineParameterOutOfRange
    /// `style.shadowOffsetX`, `style.shadowOffsetY` or `style.shadowBlur` is
    /// outside its range (TASK-71).
    case shadowParameterOutOfRange
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
    ///
    /// Always `true` once persisted: the day count is always shown (#226 R-13)
    /// and `normalized()` turns a `false` on. The field stays so that
    /// `profiles.json` keeps its format.
    var showDayCount: Bool
    /// Whether the capture date is printed.
    var showDate: Bool
    /// Whether `name` is printed ahead of the rest of the overlay.
    var showName: Bool
    /// Which units the elapsed amount is broken into: any non-empty subset
    /// of year, month, week and day (PRD 0.2 §4.5). Printed in that order.
    var displayUnits: Set<DisplayUnit>
    /// Whether years are printed as ages. Only valid when `displayUnits` has `.year`.
    var useAgeWording: Bool
    /// How a day-only count is written (#582). Ignored unless
    /// `displayUnits == [.day]`.
    var dayCountFormat: DayCountFormat
    /// Where the overlay is drawn: a grid anchor or a custom center point.
    var position: OverlayPlacement
    /// How the overlay looks (PRD 0.2 §4.2).
    var style: OverlayStyle
    /// Whether a film date stamp is printed in a corner, independent of
    /// `showDate` and outside the "day count or date" rule (TASK-151 #520).
    var showFilmDate: Bool
    /// The corner the film date stamp is printed in.
    var filmDateCorner: FilmDateCorner
    /// Local identifier of the photo album bound to this profile; nil when none
    /// (PRD 2.0 §4.1). Stored as-is: whether the album still exists is the
    /// album layer's concern, not a validation error.
    var albumIdentifier: String?
    /// Asset identifiers the profile may read when album access is limited
    /// (PRD 2.0 §4.1).
    var fallbackAssetIDs: [String]
    /// How photos of this profile are exported.
    var exportFormat: ExportFormat
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
         displayUnits: Set<DisplayUnit> = [.day],
         useAgeWording: Bool = false,
         dayCountFormat: DayCountFormat = .default,
         position: OverlayPlacement = .default,
         style: OverlayStyle = OverlayStyle(),
         showFilmDate: Bool = false,
         filmDateCorner: FilmDateCorner = .default,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         albumIdentifier: String? = nil,
         fallbackAssetIDs: [String] = [],
         exportFormat: ExportFormat = .overlay) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.countingRule = countingRule
        self.showDayCount = showDayCount
        self.showDate = showDate
        self.showName = showName
        self.displayUnits = displayUnits
        self.useAgeWording = useAgeWording
        self.dayCountFormat = dayCountFormat
        self.position = position
        self.style = style
        self.showFilmDate = showFilmDate
        self.filmDateCorner = filmDateCorner
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.albumIdentifier = albumIdentifier
        self.fallbackAssetIDs = fallbackAssetIDs
        self.exportFormat = exportFormat
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
    ///
    /// Turns `showDayCount` on only when both it and `showDate` are off
    /// (invariant 3): such a record should not exist, but it is repaired
    /// rather than rejected, so no profile is lost (107.7). A date-only
    /// profile (`showDayCount == false`, `showDate == true`) is kept as it is
    /// — TASK-107 (#426) reverses TASK-47's forcing of the day count on.
    ///
    /// Rounds the style colors to 8 bits per component, alpha included
    /// (TASK-69), and `style.autoOutlineOpacity` to the same 8-bit steps
    /// (TASK-70), so the saved profile equals the one read back. The shadow
    /// color too (TASK-71).
    func normalized() -> CameraProfile {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !showDayCount && !showDate {
            copy.showDayCount = true
        }
        var stripped = DateComponents()
        stripped.year = startDate.year
        stripped.month = startDate.month
        stripped.day = startDate.day
        copy.startDate = stripped
        // What is validated and written is exactly what reads back (TASK-69).
        copy.style.textColor = style.textColor.quantized
        copy.style.outlineColor = style.outlineColor?.quantized
        copy.style.autoOutlineOpacity = (style.autoOutlineOpacity * 255).rounded() / 255
        copy.style.shadowColor = style.shadowColor.quantized
        return copy
    }

    /// Throws if this profile violates any of the five invariants of PRD §4.1,
    /// or the style and position invariants added by PRD 0.2 §4.1.
    ///
    /// Does not repair anything: a profile carrying a `timeZone` in `startDate`
    /// fails here. Call `normalized()` first to strip what can be stripped.
    func validate(calendar: Calendar = .autoupdatingCurrent) throws {
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

        if displayUnits.isEmpty {
            throw CameraProfileValidationError.displayUnitsEmpty
        }

        // `useAgeWording` without `.year` is valid: the switch only renames
        // the year unit and is independent of it (TASK-139 #486, dropping
        // 0.1 invariant 5).

        guard style.hasValidSizeScale else {
            throw CameraProfileValidationError.sizeScaleOutOfRange(style.sizeScale)
        }

        if case let .custom(x, y) = position, !position.isInRange {
            throw CameraProfileValidationError.customPositionOutOfRange(x: x, y: y)
        }

        guard style.textColor.isStorable, style.outlineColor?.isStorable ?? true, style.shadowColor.isStorable,
              (OverlayColor.minimumStorableOpacity...1.0).contains(style.autoOutlineOpacity) else {
            throw CameraProfileValidationError.colorNotStorable
        }

        guard style.hasValidOutlineParameters else {
            throw CameraProfileValidationError.outlineParameterOutOfRange
        }

        guard style.hasValidShadowParameters else {
            throw CameraProfileValidationError.shadowParameterOutOfRange
        }
    }

    /// The normalized profile, or an error describing why it cannot be saved.
    ///
    /// This is the single entry point the persistence layer uses on both the
    /// write path (reject the write) and the read path (discard the record).
    func validatedForPersistence(calendar: Calendar = .autoupdatingCurrent) throws -> CameraProfile {
        let candidate = normalized()
        try candidate.validate(calendar: calendar)
        return candidate
    }
}

// MARK: - Decoding, including 0.1 files

extension CameraProfile {
    private enum CodingKeys: String, CodingKey {
        case id, name, startDate, countingRule, showDayCount, showDate, showName
        case displayUnits, useAgeWording, position, style, createdAt, updatedAt
        case showFilmDate, filmDateCorner
        case dayCountFormat
        case albumIdentifier, fallbackAssetIDs, exportFormat
    }

    /// Keys that only 0.1 files carry. Read, never written.
    private enum LegacyCodingKeys: String, CodingKey {
        // 0.1 stored a preset theme name here; `style` replaces it.
        case themeID
        // 0.1 stored a unit range here; `displayUnits` replaces it.
        case largestUnit
        case smallestUnit
    }

    /// The 0.1 unit tracks, largest unit first (0.1 PRD §3.2). Used only to
    /// convert a 0.1 `(largestUnit, smallestUnit)` range (PRD 0.2 §4.3).
    private static func legacyTrack(largest: DisplayUnit) -> [DisplayUnit] {
        switch largest {
        case .year: return [.year, .month, .day]
        case .month: return [.month, .day]
        case .week: return [.week, .day]
        case .day: return [.day]
        }
    }

    /// The units of a 0.1 `(largestUnit, smallestUnit)` range: its track from
    /// the largest down to the smallest, inclusive, e.g. `(year, day)` →
    /// `[.year, .month, .day]` and `(week, day)` → `[.week, .day]`.
    ///
    /// A pair 0.1 would have rejected (smallest not on the track) keeps just
    /// the largest unit, so the profile is kept rather than dropped.
    private static func legacyDisplayUnits(largest: DisplayUnit, smallest: DisplayUnit) -> Set<DisplayUnit> {
        let track = legacyTrack(largest: largest)
        guard let end = track.firstIndex(of: smallest) else { return [largest] }
        return Set(track[...end])
    }

    /// Encodes the 0.2 format. `displayUnits` is written in year → day order
    /// so the file does not churn with `Set`'s unstable iteration order.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(countingRule, forKey: .countingRule)
        try container.encode(showDayCount, forKey: .showDayCount)
        try container.encode(showDate, forKey: .showDate)
        try container.encode(showName, forKey: .showName)
        try container.encode(DisplayUnit.allCases.filter(displayUnits.contains), forKey: .displayUnits)
        try container.encode(useAgeWording, forKey: .useAgeWording)
        try container.encode(dayCountFormat, forKey: .dayCountFormat)
        try container.encode(position, forKey: .position)
        try container.encode(style, forKey: .style)
        try container.encode(showFilmDate, forKey: .showFilmDate)
        try container.encode(filmDateCorner, forKey: .filmDateCorner)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(albumIdentifier, forKey: .albumIdentifier)
        try container.encode(fallbackAssetIDs, forKey: .fallbackAssetIDs)
        try container.encode(exportFormat, forKey: .exportFormat)
    }

    /// Decodes a profile in the 0.2 format or the 0.1 format (PRD 0.2 §4.3).
    ///
    /// A 0.1 record is converted rather than dropped: its `themeID` becomes the
    /// closest `style`, its unit range becomes `displayUnits` and its bare
    /// `position` string becomes `.anchor`. The next write stores the new
    /// format, since encoding never emits the 0.1 keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startDate = try container.decode(DateComponents.self, forKey: .startDate)
        countingRule = try container.decode(CountingRule.self, forKey: .countingRule)
        showDayCount = try container.decode(Bool.self, forKey: .showDayCount)
        showDate = try container.decode(Bool.self, forKey: .showDate)
        showName = try container.decode(Bool.self, forKey: .showName)
        useAgeWording = try container.decode(Bool.self, forKey: .useAgeWording)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // Added by TASK-151: files written before it lack both keys. A corner
        // that cannot be read at all falls back too, rather than losing the
        // profile (PRD 0.2 §4.3).
        showFilmDate = try container.decodeIfPresent(Bool.self, forKey: .showFilmDate) ?? false
        filmDateCorner = (try? container.decodeIfPresent(FilmDateCorner.self, forKey: .filmDateCorner)) ?? .default
        // Added by #582: older files lack it, and an unreadable value falls
        // back too, so the profile is kept.
        dayCountFormat = (try? container.decodeIfPresent(DayCountFormat.self, forKey: .dayCountFormat)) ?? .default
        // Added by 2.0 (#614): older files lack all three, and an unreadable
        // value falls back too, so the profile is kept.
        albumIdentifier = (try? container.decodeIfPresent(String.self, forKey: .albumIdentifier)) ?? nil
        fallbackAssetIDs = (try? container.decodeIfPresent([String].self, forKey: .fallbackAssetIDs)) ?? []
        exportFormat = (try? container.decodeIfPresent(ExportFormat.self, forKey: .exportFormat)) ?? .overlay

        // 0.1 wrote `position` as a bare string such as "bottomTrailing".
        if let legacyPosition = try? container.decode(OverlayPosition.self, forKey: .position) {
            position = .anchor(legacyPosition)
        } else {
            position = try container.decode(OverlayPlacement.self, forKey: .position)
        }

        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        if let decodedUnits = try container.decodeIfPresent([DisplayUnit].self, forKey: .displayUnits) {
            displayUnits = Set(decodedUnits)
        } else {
            // 0.1 migration: the (largestUnit, smallestUnit) range becomes the
            // same units as a set, which renders the same text (PRD 0.2 §4.3, §4.5).
            let largest = try legacy.decode(DisplayUnit.self, forKey: .largestUnit)
            let smallest = try legacy.decode(DisplayUnit.self, forKey: .smallestUnit)
            displayUnits = Self.legacyDisplayUnits(largest: largest, smallest: smallest)
        }

        if let decodedStyle = try container.decodeIfPresent(OverlayStyle.self, forKey: .style) {
            style = decodedStyle
        } else {
            // 0.1 migration: map the preset theme name to its closest style.
            // An unrecognized or missing name gets the default style instead of
            // losing the profile (PRD 0.2 §4.3: never discard a profile).
            let legacyName = try? legacy.decodeIfPresent(String.self, forKey: .themeID)
            style = legacyName.flatMap(ThemeID.init(rawValue:)).map(OverlayStyle.init(legacyTheme:))
                ?? OverlayStyle()
        }
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
