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

/// Lays two photos out as one new image (#740): side by side or stacked, each
/// cropped to a shared ratio when needed (`ComparisonLayout`).
///
/// This is the first user of the PRD-2.0 §2.4 seam: a canvas is laid out
/// outside `bake`, and `bake` is called once per tile on that tile's own pixels.
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

    /// Lays `left` (first, earlier) and `right` out by `ComparisonLayout.plan`:
    /// both landscape stack, anything else sits side by side. The photo that
    /// needs a crop is cut around `focus` (centered when it finds nothing),
    /// each tile is scaled to the shared height or width, baked on its own
    /// pixels and joined with no gap or border. The longer side of the row or
    /// column is at most `maxSide`. Returns `nil` if any step fails. Pure;
    /// the caller picks the queue.
    func compose(left: Tile, right: Tile, style: OverlayStyle, placement: OverlayPlacement,
                 font: ResolvedOverlayFont, maxSide: CGFloat = ComparisonLayout.exportMaxSide,
                 focus: ComparisonLayout.Focus = ComparisonLayout.saliencyFocus) -> UIImage? {
        let leftSize = pixelSize(left.image)
        let rightSize = pixelSize(right.image)
        guard leftSize.width >= 1, leftSize.height >= 1, rightSize.width >= 1, rightSize.height >= 1 else { return nil }
        let plan = ComparisonLayout.plan(first: leftSize, second: rightSize)
        let leftCrop = crop(left.image, size: leftSize, ratio: plan.firstCrop, focus: focus)
        let rightCrop = crop(right.image, size: rightSize, ratio: plan.secondCrop, focus: focus)
        let sizes = ComparisonLayout.tileSizes(first: leftCrop.size, second: rightCrop.size,
                                               arrangement: plan.arrangement, maxSide: maxSide)
        guard let leftBaked = baked(left, crop: leftCrop, size: sizes.first, style: style,
                                    placement: placement, font: font) else { return nil }
        // The first tile is released before the second source is touched.
        guard let rightBaked = baked(right, crop: rightCrop, size: sizes.second, style: style,
                                     placement: placement, font: font) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        switch plan.arrangement {
        case .sideBySide:
            let size = CGSize(width: sizes.first.width + sizes.second.width, height: sizes.first.height)
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                leftBaked.draw(in: CGRect(origin: .zero, size: sizes.first))
                rightBaked.draw(in: CGRect(origin: CGPoint(x: sizes.first.width, y: 0), size: sizes.second))
            }
        case .stacked:
            let size = CGSize(width: sizes.first.width, height: sizes.first.height + sizes.second.height)
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                leftBaked.draw(in: CGRect(origin: .zero, size: sizes.first))
                rightBaked.draw(in: CGRect(origin: CGPoint(x: 0, y: sizes.first.height), size: sizes.second))
            }
        }
    }

    private func pixelSize(_ image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    /// The pixel rect kept of a photo: all of it, or the focused crop to `ratio`.
    private func crop(_ image: UIImage, size: CGSize, ratio: CGFloat?, focus: ComparisonLayout.Focus) -> CGRect {
        guard let ratio else { return CGRect(origin: .zero, size: size) }
        return ComparisonLayout.cropRect(size: size, ratio: ratio, focus: focus(image))
    }

    /// Draws the cropped part scaled to `size` in one pass, then bakes.
    private func baked(_ tile: Tile, crop: CGRect, size: CGSize, style: OverlayStyle,
                       placement: OverlayPlacement, font: ResolvedOverlayFont) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scaleX = size.width / crop.width
        let scaleY = size.height / crop.height
        let image = tile.image
        let fullSize = pixelSize(image)
        let cropped = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * scaleX, y: -crop.minY * scaleY,
                                  width: fullSize.width * scaleX, height: fullSize.height * scaleY))
        }
        return OverlayRenderer().bake(image: cropped, text: tile.text, style: style,
                                      placement: placement, font: font, cropRect: nil,
                                      filmDate: tile.filmDate, tone: .standard)
    }
}
