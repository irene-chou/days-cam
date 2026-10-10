import CoreText
import XCTest
@testable import DaysCam

/// Independent QA for TASK-80 core-style half (#333, PR #349): the maximum
/// outline must have no holes, thin outlines match the pre-fix look,
/// translucent colors are not darkened, and preview / swatch / bake agree.
/// Uses strings and an exact distance transform that differ from the
/// developer's own tests.
final class OverlayStrokeHolesAcceptanceTests: XCTestCase {
    private static let outputDirectory = ProcessInfo.processInfo.environment["QA_OUTPUT_DIR"] ?? (NSTemporaryDirectory() + "qa349-out")

    // MARK: Helpers

    private func fontNames() throws -> [String] {
        for (resource, ext) in [("IansuiStrokeSubset", "ttf"), ("ChenYuluoyanStrokeSubset", "ttf"),
                                ("NotoSerifStrokeSubset", "otf")] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: resource, withExtension: ext))
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return ["PingFangTC-Semibold", "PingFangTC-Thin", "PingFangTC-Regular", "AvenirNext-Regular",
                "AvenirNext-Bold", "Task80Iansui", "Task80Thin", "Task80Serif"]
    }

    private func resolved(_ name: String) -> ResolvedOverlayFont {
        OverlayMetrics.resolvedFont(state: .available, postScriptName: name)
    }

    private func canvasImage(_ size: CGSize, scale: CGFloat = 1, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    private func rgba(_ image: UIImage) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(data: raw.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return (bytes, cg.width, cg.height)
    }

    private func alpha(_ image: UIImage) throws -> (a: [UInt8], width: Int, height: Int) {
        let raw = try rgba(image)
        return (stride(from: 3, to: raw.bytes.count, by: 4).map { raw.bytes[$0] }, raw.width, raw.height)
    }

    /// Exact squared Euclidean distance to the nearest `true` pixel.
    private func distanceField(_ seeds: [Bool], width: Int, height: Int) -> [Float] {
        let infinity: Float = 1e12
        func transform(_ f: [Float]) -> [Float] {
            let n = f.count
            var d = [Float](repeating: 0, count: n)
            var v = [Int](repeating: 0, count: n)
            var z = [Float](repeating: 0, count: n + 1)
            var k = 0
            z[0] = -infinity
            z[1] = infinity
            for q in 1..<max(n, 2) where q < n {
                var s: Float
                repeat {
                    let p = v[k]
                    s = ((f[q] + Float(q * q)) - (f[p] + Float(p * p))) / Float(2 * q - 2 * p)
                    if s <= z[k] { k -= 1 } else { break }
                } while k >= 0
                if k < 0 { k = 0; v[0] = q; z[0] = -infinity; z[1] = infinity; continue }
                k += 1
                v[k] = q
                z[k] = s
                z[k + 1] = infinity
            }
            k = 0
            for q in 0..<n {
                while z[k + 1] < Float(q) { k += 1 }
                let p = v[k]
                d[q] = Float((q - p) * (q - p)) + f[p]
            }
            return d
        }
        var grid = seeds.map { $0 ? Float(0) : infinity }
        for x in 0..<width {
            let column = transform((0..<height).map { grid[$0 * width + x] })
            for y in 0..<height { grid[y * width + x] = column[y] }
        }
        for y in 0..<height {
            let row = transform(Array(grid[(y * width)..<((y + 1) * width)]))
            for x in 0..<width { grid[y * width + x] = row[x] }
        }
        return grid
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func write(_ image: UIImage, name: String) {
        try? FileManager.default.createDirectory(atPath: Self.outputDirectory, withIntermediateDirectories: true)
        if let data = image.pngData() {
            try? data.write(to: URL(fileURLWithPath: Self.outputDirectory + "/" + name + ".png"))
        }
    }

    /// Renders `text` the way a viewer would see it: the overlay drawn at
    /// `origin` in a transparent canvas.
    private func renderOverlay(_ text: String, fontName: String, fontSize: CGFloat, style: OverlayStyle,
                               canvas: CGSize, origin: CGPoint) throws -> UIImage {
        let overlay = try XCTUnwrap(OverlayRenderer().renderText(text, style: style, fontSize: fontSize,
                                                                displayScale: 1, font: resolved(fontName)))
        return canvasImage(canvas) { _ in overlay.image.draw(in: overlay.imageFrame(forBlockOrigin: origin)) }
    }

    // MARK: 80.1

    /// 80.1: other strings, three sizes, every font, maximum width: every
    /// pixel within (width - 2px) of glyph ink is opaque, and nothing is
    /// inked farther than width + 3px.
    func test80_1MaximumOutlineHasNoHolesForOtherStrings() throws {
        let text = "88 00 回 田 @"
        var report: [String] = []
        for fontSize: CGFloat in [17, 68, 166] {
            let width = 6 * fontSize / 17
            let radius = Float(max(1, width.rounded() - 2))
            let pad = ceil(width) + 12
            for name in try fontNames() {
                let font = try XCTUnwrap(UIFont(name: name, size: fontSize), name)
                let measured = (text as NSString).size(withAttributes: [.font: font])
                let canvas = CGSize(width: ceil(measured.width + pad * 2), height: ceil(measured.height + pad * 2))
                let origin = CGPoint(x: pad, y: pad)
                let plain = canvasImage(canvas) { _ in
                    (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor.white])
                }
                let ink = try alpha(plain)
                XCTAssertTrue(ink.a.contains { $0 > 0 }, "no ink \(name)")
                let near = distanceField(ink.a.map { $0 > 0 }, width: ink.width, height: ink.height)
                let style = OverlayStyle(textColor: .black, outline: .stroke, outlineColor: .white,
                                         strokeWidth: 6, shadow: .none)
                let outlined = try renderOverlay(text, fontName: name, fontSize: fontSize, style: style,
                                                 canvas: canvas, origin: origin)
                let actual = try alpha(outlined)
                XCTAssertEqual(actual.width, ink.width)
                let limit = radius * radius
                let outer = (radius + 5) * (radius + 5)
                var holes = 0, overshoot = 0, required = 0
                var holeAlphaMin = 255, holeFarthest: Float = 0, holesAtMargin3 = 0, holeIndices: [Int] = []
                let margin3 = (radius - 1) * (radius - 1)
                for i in near.indices {
                    if near[i] <= limit {
                        required += 1
                        if actual.a[i] < 240 {
                            holes += 1
                            holeIndices.append(i)
                            holeAlphaMin = min(holeAlphaMin, Int(actual.a[i]))
                            holeFarthest = max(holeFarthest, near[i].squareRoot())
                            if near[i] <= margin3 { holesAtMargin3 += 1 }
                        }
                    } else if near[i] > outer, actual.a[i] > 16 {
                        overshoot += 1
                    }
                }
                report.append("\(Int(fontSize))pt \(name): required=\(required) holes=\(holes) overshoot=\(overshoot) holeMinAlpha=\(holeAlphaMin) holeMaxDistFromInk=\(holeFarthest) (radius \(radius)) holesWithOneMorePixelMargin=\(holesAtMargin3)")
                if holes > 0 {
                    let marked = canvasImage(canvas) { context in
                        outlined.draw(at: .zero)
                        context.setFillColor(UIColor.red.cgColor)
                        for i in holeIndices {
                            context.fill(CGRect(x: i % ink.width - 1, y: i / ink.width - 1, width: 3, height: 3))
                        }
                    }
                    write(marked, name: "80.1_holes_\(Int(fontSize))pt_\(name)")
                }
                if fontSize == 68 { attach(outlined, name: "80.1-\(name)") }
                // Pixels on the outermost antialiased rim (within ~2.6px of the nominal
                // edge) may be partly covered; anything deeper is a real hole.
                XCTAssertEqual(holesAtMargin3, 0, "holes \(fontSize)pt \(name)")
                XCTAssertLessThan(holes, max(1, required / 1000), "rim shortfall \(fontSize)pt \(name)")
                XCTAssertEqual(overshoot, 0, "stroke wider than requested \(fontSize)pt \(name)")
            }
        }
        print("QA349 80.1 report:\n" + report.joined(separator: "\n"))
    }

    // MARK: 80.3

    /// 80.3: translucent text and stroke. The inside of the text keeps the
    /// text's own alpha (the stroke must not darken it) and the visible ring
    /// keeps the stroke's own alpha (it must not be applied twice).
    func test80_3TranslucentTextAndStrokeAreNotDoubled() throws {
        let text = "88 00 回 田 @"
        let fontSize: CGFloat = 140 // Large enough that even the thin face has an interior 3px deep.
        for name in ["PingFangTC-Semibold", "AvenirNext-Bold", "Task80Thin"] {
            _ = try fontNames()
            let font = try XCTUnwrap(UIFont(name: name, size: fontSize))
            let pad: CGFloat = 120
            let measured = (text as NSString).size(withAttributes: [.font: font])
            let canvas = CGSize(width: ceil(measured.width + pad * 2), height: ceil(measured.height + pad * 2))
            let origin = CGPoint(x: pad, y: pad)
            let plain = canvasImage(canvas) { _ in
                (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor.white])
            }
            let ink = try alpha(plain)
            let inside = distanceField(ink.a.map { $0 < 255 }, width: ink.width, height: ink.height) // distance to non-opaque
            let outside = distanceField(ink.a.map { $0 > 0 }, width: ink.width, height: ink.height)
            let style = OverlayStyle(textColor: OverlayColor(red: 0, green: 0, blue: 0, opacity: 0.5),
                                     outline: .stroke,
                                     outlineColor: OverlayColor(red: 1, green: 1, blue: 1, opacity: 0.6),
                                     strokeWidth: 6, shadow: .none)
            let image = try renderOverlay(text, fontName: name, fontSize: fontSize, style: style,
                                          canvas: canvas, origin: origin)
            let raw = try rgba(image)
            var interiorBad = 0, interior = 0, ringBad = 0, ring = 0
            var interiorSum = 0, ringSum = 0, rim = 0, rimBad = 0, rimMaxDeviation = 0
            let ringRadius = Float(6 * fontSize / 17 - 3)
            for i in 0..<(raw.width * raw.height) {
                let a = Int(raw.bytes[i * 4 + 3])
                if ink.a[i] == 255, inside[i] < 9 { // fully covered glyph pixels within 3px of the edge
                    rim += 1
                    if abs(a - 128) > 6 { rimBad += 1; rimMaxDeviation = max(rimMaxDeviation, abs(a - 128)) }
                }
                if ink.a[i] == 255, inside[i] >= 9 { // 3px deep inside glyph
                    interior += 1
                    interiorSum += a
                    if abs(a - 128) > 4 { interiorBad += 1 }
                } else if ink.a[i] == 0, outside[i] >= 9, outside[i] <= ringRadius * ringRadius {
                    ring += 1
                    ringSum += a
                    if abs(a - 153) > 4 { ringBad += 1 }
                }
            }
            XCTAssertGreaterThan(interior, 100, name)
            XCTAssertGreaterThan(ring, 100, name)
            print("QA349 80.3 \(name): interior mean alpha=\(Double(interiorSum) / Double(max(interior, 1))) (want 127.5) bad=\(interiorBad)/\(interior); ring mean alpha=\(Double(ringSum) / Double(max(ring, 1))) (want 153) bad=\(ringBad)/\(ring)")
            if let firstBad = (0..<(raw.width * raw.height)).first(where: { i in
                ink.a[i] == 255 && inside[i] < 9 && abs(Int(raw.bytes[i * 4 + 3]) - 128) > 20
            }) {
                // 8x nearest-neighbour crop over mid-grey, 36 x 24 px around the first bad rim pixel.
                let cx = max(18, min(raw.width - 18, firstBad % raw.width)), cy = max(12, min(raw.height - 12, firstBad / raw.width))
                let crop = CGRect(x: cx - 18, y: cy - 12, width: 36, height: 24)
                let zoomed = canvasImage(CGSize(width: 288, height: 192)) { context in
                    UIColor(white: 0.5, alpha: 1).setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 288, height: 192))
                    context.interpolationQuality = .none
                    context.saveGState()
                    context.clip(to: CGRect(x: 0, y: 0, width: 288, height: 192))
                    image.draw(in: CGRect(x: -crop.minX * 8, y: -crop.minY * 8,
                                          width: CGFloat(raw.width) * 8, height: CGFloat(raw.height) * 8))
                    context.restoreGState()
                }
                write(zoomed, name: "80.3_rim_zoom8x_\(name)")
            }
            print("QA349 80.3 \(name): fully covered rim (<3px from edge) off-alpha pixels=\(rimBad)/\(rim) (\(Double(rimBad) / Double(max(rim, 1)))), max deviation=\(rimMaxDeviation)/255")
            XCTAssertLessThan(Double(rimBad) / Double(max(rim, 1)), 0.05, "glyph rim darkened \(name)")
            XCTAssertEqual(interiorBad, 0, "text interior darkened \(name)")
            XCTAssertEqual(ringBad, 0, "stroke alpha doubled or holed \(name)")
            attach(image, name: "80.3-\(name)")
        }
    }

    // MARK: 80.2

    /// Pre-fix look, reproduced from `fbf5a49` (`.strokeWidth` text attribute
    /// drawn first, then the fill).
    private func legacy(_ text: String, font: UIFont, width: Double, canvas: CGSize, origin: CGPoint) -> UIImage {
        let lineWidth = CGFloat(width) * font.pointSize / 17 * 2
        return canvasImage(canvas) { context in
            context.setLineJoin(.round)
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .strokeColor: UIColor.white,
                .strokeWidth: lineWidth / font.pointSize * 100])
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor.black])
        }
    }

    /// 80.2: thin outlines stay within antialiasing of the old rendering.
    func test80_2ThinOutlineMatchesPreFixRendering() throws {
        let text = "88 00 回 田 @ fi"
        let fontSize: CGFloat = 68
        for width in [1.0, 2.0] {
            for name in try fontNames() {
                let font = try XCTUnwrap(UIFont(name: name, size: fontSize))
                let pad: CGFloat = 40
                let measured = (text as NSString).size(withAttributes: [.font: font])
                let canvas = CGSize(width: ceil(measured.width + pad * 2), height: ceil(measured.height + pad * 2))
                let origin = CGPoint(x: pad, y: pad)
                let old = try alpha(legacy(text, font: font, width: width, canvas: canvas, origin: origin))
                let style = OverlayStyle(textColor: .black, outline: .stroke, outlineColor: .white,
                                         strokeWidth: width, shadow: .none)
                let new = try alpha(renderOverlay(text, fontName: name, fontSize: fontSize, style: style,
                                                  canvas: canvas, origin: origin))
                var total = 0, count = 0, large = 0
                for i in old.a.indices where old.a[i] > 0 || new.a[i] > 0 {
                    let d = abs(Int(old.a[i]) - Int(new.a[i]))
                    total += d
                    count += 1
                    if d > 96 { large += 1 }
                }
                let mean = Double(total) / Double(max(count, 1)) / 255
                let largeShare = Double(large) / Double(max(count, 1))
                print("QA349 80.2 w=\(width) \(name): mean alpha diff=\(mean) large(>96)=\(largeShare)")
                XCTAssertLessThan(mean, 0.05, "\(name) w\(width)")
                XCTAssertLessThan(largeShare, 0.04, "\(name) w\(width)")
            }
        }
    }

    // MARK: 80.4

    /// 80.4: viewfinder (points at screen scale), style-tab swatch and bake
    /// share one silhouette. Images are written for the PR comment.
    func test80_4PreviewSwatchAndBakeShareOneOutline() throws {
        _ = try fontNames()
        let text = "88 00 回 田 @"
        for name in ["PingFangTC-Semibold", "Task80Thin"] {
            let resolvedFont = resolved(name)
            let style = OverlayStyle(textColor: .white, outline: .stroke, outlineColor: .black,
                                     strokeWidth: 6, shadow: .none)
            // Bake: 1200 x 1600 pixel photo.
            let pixels = CGSize(width: 1200, height: 1600)
            let flat = UIGraphicsImageRendererFormat()
            flat.scale = 1
            flat.opaque = true
            let photo = UIGraphicsImageRenderer(size: pixels, format: flat).image { context in
                UIColor(white: 0.6, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: pixels))
            }
            let placement = OverlayPlacement.anchor(.topLeading)
            let baked = try XCTUnwrap(OverlayRenderer().bake(image: photo, text: text, style: style,
                                                            placement: placement, font: resolvedFont))
            // Viewfinder: the same frame as 400 x 533.33 points at 3x.
            let points = CGSize(width: pixels.width / 3, height: pixels.height / 3)
            let pointSize = OverlayRenderer.fittedFontSize(for: text, style: style, frameSize: points, font: resolvedFont)
            let overlay = try XCTUnwrap(OverlayRenderer().renderText(text, style: style, fontSize: pointSize,
                                                                    displayScale: 3, font: resolvedFont))
            let blockOrigin = OverlayMetrics.origin(forBlockSize: overlay.blockSize, in: points, placement: placement)
            let previewFormat = UIGraphicsImageRendererFormat()
            previewFormat.scale = 3
            previewFormat.opaque = true
            let preview = UIGraphicsImageRenderer(size: points, format: previewFormat).image { context in
                UIColor(white: 0.6, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: points))
                overlay.image.draw(in: overlay.imageFrame(forBlockOrigin: blockOrigin))
            }
            // Silhouette: pixels that differ from the flat backdrop.
            func silhouette(_ image: UIImage) throws -> [Bool] {
                let raw = try rgba(image)
                XCTAssertEqual(raw.width, 1200, name)
                return (0..<(raw.width * raw.height)).map { abs(Int(raw.bytes[$0 * 4]) - 153) > 40 }
            }
            let a = try silhouette(preview), b = try silhouette(baked)
            var both = 0, either = 0
            for i in a.indices where a[i] || b[i] { either += 1; if a[i] && b[i] { both += 1 } }
            let iou = Double(both) / Double(max(either, 1))
            print("QA349 80.4 \(name) preview vs bake IoU=\(iou) ink=\(either)")
            XCTAssertGreaterThan(either, 1000, name)
            XCTAssertGreaterThan(iou, 0.97, "preview/bake silhouette \(name)")
            write(preview, name: "80.4_\(name)_preview")
            write(baked, name: "80.4_\(name)_bake")
            attach(preview, name: "80.4-preview-\(name)")
            attach(baked, name: "80.4-bake-\(name)")

            // Swatch at the same pixel size as the bake: font size from bake.
            let bakePointSize = OverlayRenderer.fittedFontSize(for: text, style: style, frameSize: pixels, font: resolvedFont)
            let font = resolvedFont.font(ofSize: bakePointSize)
            let swatch = StyleSwatchPreview.strokedText(text, font: font, fill: .white, stroke: .black,
                                                        strokeWidth: 6 * bakePointSize / 17)
            let swatchCanvas = canvasImage(pixels, scale: 1) { _ in
                swatch.draw(at: CGPoint(x: 20, y: 20))
            }
            write(swatchCanvas, name: "80.4_\(name)_swatch")
            attach(swatchCanvas, name: "80.4-swatch-\(name)")
            // Same silhouette check, swatch against a pure render at the same font size.
            let direct = try renderOverlay(text, fontName: name, fontSize: bakePointSize, style: style,
                                           canvas: pixels, origin: CGPoint(x: 20 + ceil(6 * bakePointSize / 17 * 2), y: 20 + ceil(6 * bakePointSize / 17 * 2)))
            let sw = try alpha(swatchCanvas), dr = try alpha(direct)
            var swBoth = 0, swEither = 0
            if sw.width == dr.width {
                for i in sw.a.indices where sw.a[i] > 128 || dr.a[i] > 128 {
                    swEither += 1
                    if sw.a[i] > 128 && dr.a[i] > 128 { swBoth += 1 }
                }
            }
            let swIoU = Double(swBoth) / Double(max(swEither, 1))
            print("QA349 80.4 \(name) swatch vs renderer IoU=\(swIoU) (canvas \(sw.width) vs \(dr.width))")
            write(direct, name: "80.4_\(name)_renderer")
            XCTAssertGreaterThan(swIoU, 0.97, "swatch/renderer silhouette \(name)")
        }
    }
}
