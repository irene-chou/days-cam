import CoreGraphics
import CoreText
import UIKit

/// Vector outline geometry shared by the photo renderer and style swatches.
/// Coordinates match `NSString.draw(at:withAttributes:)` in a UIKit context.
/// Bitmap glyphs (such as emoji) have no outline; callers keep their original
/// text fill drawing to preserve them, including their colors and shaping.
struct OverlayStrokeGeometry {
    let fillPath: CGPath
    let outlinePath: CGPath
    let exteriorPath: CGPath

    /// Builds a round outline with `width` points visible outside the glyphs.
    init(text: String, font: UIFont, width: CGFloat) {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let size = (text as NSString).size(withAttributes: [.font: font])
        // NSString drawing uses TextKit's fallback metrics and baselines.
        // A tight Core Text frame can reject a line whose fallback ascent is
        // taller than NSString's measured height, so do not use a CTFrame.
        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, size.width + 1),
                                                      height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let range = layout.glyphRange(for: container)
        var fill: CGPath = CGMutablePath()
        var expanded: CGPath = CGMutablePath()
        layout.enumerateLineFragments(forGlyphRange: range) { rect, _, _, glyphRange, _ in
            guard glyphRange.length > 0 else { return }
            let characters = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let line = CTLineCreateWithAttributedString(attributed.attributedSubstring(from: characters))
            let baseline = rect.minY + font.ascender
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                // Core Text supplies the actual fallback font for each run.
                let runFont = attributes[kCTFontAttributeName] as! CTFont
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                for index in 0..<count {
                    guard let path = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                        tx: rect.minX + positions[index].x,
                        ty: baseline - positions[index].y)
                    guard let positioned = path.copy(using: &transform) else { continue }
                    let glyph = positioned.normalized(using: .winding)
                    fill = fill.union(glyph, using: .winding)
                    // Stroke each curve separately: a closed stroked contour can
                    // reverse winding when its inner offset crosses itself.
                    let segments = CGMutablePath()
                    var current = CGPoint.zero
                    var first = CGPoint.zero
                    positioned.applyWithBlock { pointer in
                        let element = pointer.pointee
                        let segment = CGMutablePath()
                        segment.move(to: current)
                        switch element.type {
                        case .moveToPoint:
                            current = element.points[0]
                            first = current
                            return
                        case .addLineToPoint:
                            segment.addLine(to: element.points[0])
                            current = element.points[0]
                        case .addQuadCurveToPoint:
                            segment.addQuadCurve(to: element.points[1], control: element.points[0])
                            current = element.points[1]
                        case .addCurveToPoint:
                            segment.addCurve(to: element.points[2], control1: element.points[0], control2: element.points[1])
                            current = element.points[2]
                        case .closeSubpath:
                            segment.addLine(to: first)
                            current = first
                        @unknown default: return
                        }
                        let stroke = segment.copy(strokingWithWidth: max(0, width) * 2,
                                                  lineCap: .round, lineJoin: .round, miterLimit: 10)
                        segments.addPath(stroke)
                    }
                    expanded = expanded.union(segments.normalized(using: .winding).union(glyph, using: .winding), using: .winding)
                }
            }
        }
        fillPath = fill
        outlinePath = expanded
        exteriorPath = expanded.subtracting(fill, using: .winding)
    }

    /// Draws one solid, nonzero-winding outline; callers apply opacity once.
    /// Exclude the fill for translucent text so its interior stays undarkened.
    func draw(in context: CGContext, at origin: CGPoint, color: UIColor, excludingFill: Bool) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.setFillColor(color.cgColor)
        context.addPath(excludingFill ? exteriorPath : outlinePath)
        context.fillPath(using: .winding)
        context.restoreGState()
    }
}
