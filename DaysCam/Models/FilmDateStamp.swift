import CoreGraphics
import Foundation

/// The corner of the finished photo a film date stamp is printed in
/// (TASK-151 #520).
enum FilmDateCorner: String, Codable, CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    /// The corner a new profile, an old profile file, or an unrecognized
    /// stored value gets.
    static let `default`: FilmDateCorner = .bottomLeading

    /// How far the stamp is turned, in degrees, clockwise as seen on the
    /// photo. Only 0, 90 and -90 occur (TASK-151 §7, rule A with top-leading
    /// kept upright).
    ///
    /// - bottom-leading: 90, read top to bottom, glyph tops facing inward.
    /// - top-trailing: -90, read bottom to top.
    /// - top-leading and bottom-trailing: 0, read left to right.
    var rotation: Int {
        switch self {
        case .bottomLeading: return 90
        case .topTrailing: return -90
        case .topLeading, .bottomTrailing: return 0
        }
    }

    /// Decodes a stored corner, falling back to `default` for a string no
    /// version of the app wrote, so one bad value never loses a profile.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FilmDateCorner(rawValue: raw) ?? .default
    }
}

/// A film-camera style date printed in one corner of the photo, separate
/// from the main overlay text (TASK-151 #520).
///
/// Its look is fixed: seven-segment digits drawn as paths, film orange, a
/// soft glow. Only the corner is user-configurable. The same `Metrics` and
/// `glyphPath` drive the baked photo and the viewfinder preview.
struct FilmDateStamp: Equatable {
    /// The text to print, normally `text(for:)` of the capture date.
    var text: String
    /// Where the stamp sits on the photo.
    var corner: FilmDateCorner

    /// Creates a stamp. No validation: characters other than digits, `'`
    /// and space are drawn as blanks.
    init(text: String, corner: FilmDateCorner) {
        self.text = text
        self.corner = corner
    }

    /// The `'YY MM DD` text for a calendar date, e.g. `'25 10 12`.
    ///
    /// The year is cut to its last two digits; month and day are padded to
    /// two. Pass `DayCountCalculator(now: { capturedAt }).currentDateComponents()`
    /// so the date is the capture moment's, never the clock's or a file's.
    static func text(for components: DateComponents) -> String {
        let year = ((components.year ?? 0) % 100 + 100) % 100
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "'%02d %02d %02d", year, month, day)
    }
}

// MARK: - Metrics

extension FilmDateStamp {
    /// Every fixed number of the stamp's look, shared by the renderer and the
    /// viewfinder preview. Lengths are fractions of the photo's short edge or
    /// of the glyph height, so the stamp scales with the photo.
    enum Metrics {
        /// Film orange `#FF8A1E`, as sRGB components 0...1.
        static let red: CGFloat = 0xFF / 255
        static let green: CGFloat = 0x8A / 255
        static let blue: CGFloat = 0x1E / 255

        /// Glyph height as a fraction of the photo's short edge.
        static let heightRatio: CGFloat = 0.035
        /// Distance from the glyph box to each of its two photo edges, as a
        /// fraction of the short edge. Measured to the glyph box, not to the
        /// glow around it.
        static let marginRatio: CGFloat = 0.045
        /// Glow blur radius as a fraction of the glyph height.
        static let glowRadiusRatio: CGFloat = 0.15
        /// Opacity of the glow under the glyphs.
        static let glowOpacity: CGFloat = 0.85
        /// The slight blur of the glyphs themselves, mimicking ink bleed:
        /// about 0.3pt on 18pt glyphs.
        static let bleedRadiusRatio: CGFloat = 0.3 / 18
        /// How far the glyphs lean right, in degrees.
        static let slantDegrees: CGFloat = 7

        /// Digit width, as a fraction of the glyph height.
        static let digitWidthRatio: CGFloat = 0.56
        /// Segment thickness, as a fraction of the glyph height.
        static let segmentThicknessRatio: CGFloat = 0.13
        /// Gap between neighbouring segments, as a fraction of the glyph height.
        static let segmentGapRatio: CGFloat = 0.025
        /// Space between two characters, as a fraction of the glyph height.
        static let characterSpacingRatio: CGFloat = 0.2
        /// Width of a blank, as a fraction of the glyph height.
        static let spaceWidthRatio: CGFloat = 0.32
        /// Apostrophe width and height, as fractions of the glyph height.
        static let apostropheWidthRatio: CGFloat = 0.13
        static let apostropheHeightRatio: CGFloat = 0.3
    }
}

// MARK: - Geometry

extension FilmDateStamp {
    /// The glyph height for a photo (or crop window) of `canvasSize`.
    static func glyphHeight(forCanvasSize canvasSize: CGSize) -> CGFloat {
        min(canvasSize.width, canvasSize.height) * Metrics.heightRatio
    }

    /// The upright, slanted outline of `text` at glyph height `height`.
    ///
    /// The path's box runs from `x == 0` at its leftmost ink to its rightmost
    /// ink, and from `y == 0` (glyph top) to `y == height` (glyph bottom),
    /// y pointing down. `size` is that box.
    static func glyphPath(for text: String, height: CGFloat) -> (path: CGPath, size: CGSize) {
        let path = CGMutablePath()
        guard height > 0 else { return (path, .zero) }
        var cursor: CGFloat = 0
        var isFirst = true
        for character in text {
            if !isFirst { cursor += Metrics.characterSpacingRatio * height }
            isFirst = false
            cursor += addGlyph(character, at: cursor, height: height, to: path)
        }

        // Lean right: the top moves right by height × tan(slant), the
        // bottom stays put.
        let shear = tan(Metrics.slantDegrees * .pi / 180)
        var slant = CGAffineTransform(a: 1, b: 0, c: -shear, d: 1, tx: shear * height, ty: 0)
        guard let slanted = path.copy(using: &slant), !slanted.isEmpty else { return (path, .zero) }
        let ink = slanted.boundingBoxOfPath
        var shift = CGAffineTransform(translationX: -ink.minX, y: 0)
        let placed = slanted.copy(using: &shift) ?? slanted
        return (placed, CGSize(width: ink.width, height: height))
    }

    /// The box the stamp's glyphs occupy on a canvas of `canvasSize`, after
    /// rotation: in `corner`, `Metrics.marginRatio` of the short edge in from
    /// its two edges.
    func frame(inCanvasSize canvasSize: CGSize) -> CGRect {
        let height = Self.glyphHeight(forCanvasSize: canvasSize)
        let upright = Self.glyphPath(for: text, height: height).size
        let size = corner.rotation == 0 ? upright : CGSize(width: upright.height, height: upright.width)
        let margin = min(canvasSize.width, canvasSize.height) * Metrics.marginRatio
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeading:
            x = margin
            y = margin
        case .topTrailing:
            x = canvasSize.width - margin - size.width
            y = margin
        case .bottomLeading:
            x = margin
            y = canvasSize.height - margin - size.height
        case .bottomTrailing:
            x = canvasSize.width - margin - size.width
            y = canvasSize.height - margin - size.height
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// The transform taking `glyphPath`'s coordinates onto a canvas of
    /// `canvasSize` (y down): rotated by `corner.rotation` and placed at
    /// `frame(inCanvasSize:)`.
    func glyphTransform(inCanvasSize canvasSize: CGSize) -> CGAffineTransform {
        let height = Self.glyphHeight(forCanvasSize: canvasSize)
        let upright = Self.glyphPath(for: text, height: height).size
        let frame = frame(inCanvasSize: canvasSize)
        let angle = CGFloat(corner.rotation) * .pi / 180
        return CGAffineTransform(translationX: -upright.width / 2, y: -upright.height / 2)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: frame.midX, y: frame.midY))
    }

    // MARK: Glyphs

    /// Adds one character's outline with its left edge at `x`, unslanted, and
    /// returns its advance width.
    private static func addGlyph(_ character: Character, at x: CGFloat, height: CGFloat,
                                 to path: CGMutablePath) -> CGFloat {
        if character == "'" {
            let width = Metrics.apostropheWidthRatio * height
            let tall = Metrics.apostropheHeightRatio * height
            path.addRect(CGRect(x: x, y: 0, width: width, height: tall))
            return width
        }
        let width = Metrics.digitWidthRatio * height
        guard let digit = character.wholeNumberValue, (0...9).contains(digit) else {
            return Metrics.spaceWidthRatio * height
        }
        for segment in segments(forDigit: digit) {
            addSegment(segment, at: x, width: width, height: height, to: path)
        }
        return width
    }

    /// The seven segments, named the usual way: a top, b top right,
    /// c bottom right, d bottom, e bottom left, f top left, g middle.
    private enum Segment { case a, b, c, d, e, f, g }

    private static func segments(forDigit digit: Int) -> [Segment] {
        switch digit {
        case 0: return [.a, .b, .c, .d, .e, .f]
        case 1: return [.b, .c]
        case 2: return [.a, .b, .g, .e, .d]
        case 3: return [.a, .b, .g, .c, .d]
        case 4: return [.f, .g, .b, .c]
        case 5: return [.a, .f, .g, .c, .d]
        case 6: return [.a, .f, .g, .e, .c, .d]
        case 7: return [.a, .b, .c]
        case 8: return [.a, .b, .c, .d, .e, .f, .g]
        default: return [.a, .b, .c, .d, .f, .g]
        }
    }

    /// Adds one segment as a hexagonal bar with pointed ends.
    private static func addSegment(_ segment: Segment, at x: CGFloat, width: CGFloat, height: CGFloat,
                                   to path: CGMutablePath) {
        let thickness = Metrics.segmentThicknessRatio * height
        let half = thickness / 2
        let gap = Metrics.segmentGapRatio * height
        let left = x + half
        let right = x + width - half
        let top = half
        let middle = height / 2
        let bottom = height - half

        func horizontal(_ y: CGFloat) {
            let start = left + gap
            let end = right - gap
            path.addLines(between: [CGPoint(x: start, y: y),
                                    CGPoint(x: start + half, y: y - half),
                                    CGPoint(x: end - half, y: y - half),
                                    CGPoint(x: end, y: y),
                                    CGPoint(x: end - half, y: y + half),
                                    CGPoint(x: start + half, y: y + half)])
            path.closeSubpath()
        }
        func vertical(_ x: CGFloat, from y0: CGFloat, to y1: CGFloat) {
            let start = y0 + gap
            let end = y1 - gap
            path.addLines(between: [CGPoint(x: x, y: start),
                                    CGPoint(x: x + half, y: start + half),
                                    CGPoint(x: x + half, y: end - half),
                                    CGPoint(x: x, y: end),
                                    CGPoint(x: x - half, y: end - half),
                                    CGPoint(x: x - half, y: start + half)])
            path.closeSubpath()
        }

        switch segment {
        case .a: horizontal(top)
        case .g: horizontal(middle)
        case .d: horizontal(bottom)
        case .f: vertical(left, from: top, to: middle)
        case .b: vertical(right, from: top, to: middle)
        case .e: vertical(left, from: middle, to: bottom)
        case .c: vertical(right, from: middle, to: bottom)
        }
    }
}
