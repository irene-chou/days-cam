import UIKit

/// Chooses the two photos of a comparison card and the caption under it.
///
/// Pure functions over already-read dates; nothing here touches Photos. The
/// capture moment is always the one the caller hands in (PRD-2.0 §6.1).
enum ComparisonPicker {
    /// A photo that may take part in a comparison.
    struct Candidate: Equatable {
        /// Stable identifier, for example `PHAsset.localIdentifier`.
        let id: String
        /// The capture moment (`PHAsset.creationDate`).
        let creationDate: Date
    }

    /// Minimum calendar-day gap between the earliest and latest photo.
    static let minimumGapDays = 7

    /// The earliest and latest photos taken on or after the start date, or
    /// `nil` when fewer than two different photos qualify or they are less than
    /// seven calendar days apart. Ties keep input order: first is earliest,
    /// last is latest.
    static func defaultPair(_ candidates: [Candidate],
                            profile: CameraProfile,
                            calendar: Calendar) -> (earliest: Candidate, latest: Candidate)? {
        let eligible = candidates.filter { candidate in
            DayCountCalculator(calendar: calendar, now: { candidate.creationDate })
                .rawDayDifference(from: profile.startDate) >= 0
        }
        guard var earliest = eligible.first, var latest = eligible.first else { return nil }
        for candidate in eligible {
            if candidate.creationDate < earliest.creationDate { earliest = candidate }
            if candidate.creationDate >= latest.creationDate { latest = candidate }
        }
        guard earliest.id != latest.id else { return nil }
        let gap = calendar.dateComponents([.day],
                                          from: calendar.startOfDay(for: earliest.creationDate),
                                          to: calendar.startOfDay(for: latest.creationDate)).day ?? 0
        guard gap >= minimumGapDays else { return nil }
        return (earliest, latest)
    }

    /// A milestone caption for the latest photo's calendar day, or `nil`.
    /// Priority: whole year, then a multiple of 100 days, then whole month
    /// (only when the profile counts months).
    static func milestoneSubtitle(latest: Date,
                                  profile: CameraProfile,
                                  calendar: Calendar) -> String? {
        guard let startYear = profile.startDate.year,
              let startMonth = profile.startDate.month,
              let startDay = profile.startDate.day else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: latest)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }

        let yearGap = year - startYear
        if month == startMonth, day == startDay, yearGap >= 1 {
            return profile.useAgeWording ? "滿 \(yearGap) 歲了" : "滿 \(yearGap) 年了"
        }
        let count = DayCountCalculator(calendar: calendar, now: { latest })
            .dayCount(from: profile.startDate, rule: profile.countingRule)
        if count >= 100, count % 100 == 0 {
            return "滿 \(count) 天了"
        }
        let monthGap = yearGap * 12 + month - startMonth
        if profile.displayUnits.contains(.month), day == startDay, monthGap >= 1 {
            return "滿 \(monthGap) 個月了"
        }
        return nil
    }
}

/// Lays two photos side by side as one new image.
///
/// This is the first user of the PRD-2.0 §2.4 seam: a canvas is laid out
/// outside `bake`, and `bake` is called once per tile on that tile's own square.
struct ComparisonRenderer {
    /// One half of the comparison.
    struct Tile {
        /// The source photo, any size or orientation.
        let image: UIImage
        /// The text to print on this tile; empty prints nothing.
        let text: String
        /// Optional film date stamp for this tile.
        let filmDate: FilmDateStamp?
    }

    /// Creates a renderer.
    init() {}

    /// Center-crops each tile to a square on its short side, bakes the overlay
    /// on it, and joins them into a `2 * side` by `side` opaque image with no
    /// gap or border. `side` is the smaller of both tiles' sizes, each capped at
    /// `tileSide`. Returns `nil` if any step fails. Pure; the caller picks the queue.
    func compose(left: Tile, right: Tile, style: OverlayStyle, placement: OverlayPlacement,
                 font: ResolvedOverlayFont, tileSide: CGFloat = 1080) -> UIImage? {
        let sides = [left, right].map { side(of: $0.image, cap: tileSide) }
        guard let side = sides.min(), side >= 1 else { return nil }
        guard let leftBaked = bakedSquare(left, side: side, style: style, placement: placement, font: font)
        else { return nil }
        // The left tile is released before the right source is touched.
        guard let rightBaked = bakedSquare(right, side: side, style: style, placement: placement, font: font)
        else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: side * 2, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            leftBaked.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            rightBaked.draw(in: CGRect(x: side, y: 0, width: side, height: side))
        }
    }

    private func side(of image: UIImage, cap: CGFloat) -> CGFloat {
        let shortSide = min(image.size.width * image.scale, image.size.height * image.scale)
        return min(cap, shortSide).rounded(.down)
    }

    /// Crops to a centered square and scales to `side` pixels in one draw, then bakes.
    private func bakedSquare(_ tile: Tile, side: CGFloat, style: OverlayStyle,
                             placement: OverlayPlacement, font: ResolvedOverlayFont) -> UIImage? {
        let width = tile.image.size.width * tile.image.scale
        let height = tile.image.size.height * tile.image.scale
        guard width >= 1, height >= 1 else { return nil }
        let shortSide = min(width, height)
        let factor = side / shortSide
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let drawn = CGSize(width: width * factor, height: height * factor)
            tile.image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                       width: drawn.width, height: drawn.height))
        }
        return OverlayRenderer().bake(image: square, text: tile.text, style: style,
                                      placement: placement, font: font, cropRect: nil,
                                      filmDate: tile.filmDate, tone: .standard)
    }
}
