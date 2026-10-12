import CoreText
import XCTest
@testable import DaysCam

/// TASK-80: compare outlines against an independently dilated glyph mask.
final class OverlayRendererStrokeTests: XCTestCase {
    private let origin = CGPoint(x: 65, y: 80)
    private let size = CGSize(width: 600, height: 400)
    private var fontSize: CGFloat = 68

    private func fonts() throws -> [UIFont] {
        for (resource, ext) in [("IansuiStrokeSubset", "ttf"), ("ChenYuluoyanStrokeSubset", "ttf"),
                                ("NotoSerifStrokeSubset", "otf")] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: resource, withExtension: ext))
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return try ["PingFangTC-Semibold", "PingFangTC-Thin", "AvenirNext-Regular",
                    "AvenirNext-Bold", "Task80Iansui", "Task80Thin", "Task80Serif"].map {
            try XCTUnwrap(UIFont(name: $0, size: fontSize), $0)
        }
    }

    private func image(_ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    private func rgba(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(data: raw.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: 0, y: CGFloat(cg.height))
            context.scaleBy(x: 1, y: -1)
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return bytes
    }

    private func alpha(_ image: UIImage) throws -> [UInt8] {
        let bytes = try rgba(image)
        return stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
    }

    private func rendered(_ text: String, font: UIFont, width: Double) throws -> UIImage {
        let resolved = OverlayMetrics.resolvedFont(state: .available, postScriptName: font.fontName)
        let style = OverlayStyle(textColor: .black, outline: .stroke, outlineColor: .white,
                                 strokeWidth: width, shadow: .none)
        let overlay = try XCTUnwrap(OverlayRenderer().renderText(text, style: style, fontSize: fontSize,
                                                                displayScale: 1, font: resolved))
        return image { _ in overlay.image.draw(in: overlay.imageFrame(forBlockOrigin: origin)) }
    }

    /// Whether Core Text has an outline path for any glyph `text` shapes to
    /// in `font` (after font fallback); bitmap emoji have none.
    private func hasOutlineGlyph(_ text: String, font: UIFont) -> Bool {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            if glyphs.contains(where: { CTFontCreatePathForGlyph(runFont, $0, nil) != nil }) { return true }
        }
        return false
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test80_1MaximumOutlineHasNoHolesWithinGlyphDilation() throws {
        for pointSize: CGFloat in [17, 68, 166] {
            fontSize = pointSize
            let radius = max(1, Int(6 * fontSize / 17) - 2) // Exclude raster hinting and the antialiased outside boundary (up to 2px).
            // Explicit types: the untyped closure pair times out the type
            // checker on Xcode 26.3 (Intel simulator host).
            let radiusSquared: Int = radius * radius
            let offsets: [(Int, Int)] = (-radius...radius).flatMap { (y: Int) -> [(Int, Int)] in
                (-radius...radius).compactMap { (x: Int) -> (Int, Int)? in
                    (x * x + y * y <= radiusSquared) ? (x, y) : nil
                }
            }
            for font in try fonts() {
                for text in ["0", "8", "日", "囍", "&", "fi &"] {
                    let plain = image { _ in
                        (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor.white])
                    }
                    let mask = try alpha(plain)
                    XCTAssertTrue(mask.contains { $0 > 0 }, "fixture has no ink")
                    let outlined = try rendered(text, font: font, width: 6)
                    let actual = try alpha(outlined)
                    var expected = mask.map { $0 > 0 }
                    for y in 0..<Int(size.height) {
                        for x in 1..<(Int(size.width) - 1) where y > 0 && y < Int(size.height) - 1 && mask[y * Int(size.width) + x] > 0 {
                            let i = y * Int(size.width) + x
                            guard mask[i - 1] == 0 || mask[i + 1] == 0 || mask[i - Int(size.width)] == 0 || mask[i + Int(size.width)] == 0 else { continue }
                            for (dx, dy) in offsets {
                                let xx = x + dx, yy = y + dy
                                if xx >= 0, xx < Int(size.width), yy >= 0, yy < Int(size.height) {
                                    expected[yy * Int(size.width) + xx] = true
                                }
                            }
                        }
                    }
                    let holes = expected.indices.filter { expected[$0] && actual[$0] < 240 }.count
                    print("TASK80 \(pointSize)pt \(font.fontName) \(text): missing pixels=\(holes)")
                    if pointSize == 68 { attach(outlined, name: "80.1-\(font.fontName)-\(text)") }
                    if holes > 0, pointSize == 68 {
                        let diagnostic = image { context in
                            outlined.draw(at: .zero)
                            context.setFillColor(UIColor.red.cgColor)
                            for i in expected.indices where expected[i] && actual[i] < 240 {
                                context.fill(CGRect(x: i % Int(size.width), y: Int(size.height) - 1 - i / Int(size.width), width: 1, height: 1))
                            }
                        }
                        attach(diagnostic, name: "80.1-missing-\(font.fontName)-\(text)")
                    }
                    XCTAssertEqual(holes, 0, "\(pointSize)pt \(font.fontName) \(text)")
                }
            }
        }
    }

    /// Fully covered glyph pixels, including the rim, retain only text alpha.
    func test80_3KnockoutMatchesTextRasterizationAtGlyphEdges() throws {
        let text = "88 00 回 田 @"
        for font in try fonts() {
            let plain = try alpha(image { _ in
                (text as NSString).draw(at: origin, withAttributes: [
                    .font: font, .foregroundColor: UIColor.black
                ])
            })
            let style = OverlayStyle(textColor: OverlayColor.black.withOpacity(0.5),
                                     outline: .stroke, outlineColor: OverlayColor.white.withOpacity(0.6),
                                     strokeWidth: 6, shadow: .none)
            let resolved = OverlayMetrics.resolvedFont(state: .available, postScriptName: font.fontName)
            let overlay = try XCTUnwrap(OverlayRenderer().renderText(text, style: style,
                fontSize: fontSize, displayScale: 1, font: resolved))
            let actual = try alpha(image { _ in
                overlay.image.draw(in: overlay.imageFrame(forBlockOrigin: origin))
            })
            let covered = plain.indices.filter { plain[$0] == 255 }
            XCTAssertGreaterThan(covered.count, 100, font.fontName)
            XCTAssertEqual(covered.filter { abs(Int(actual[$0]) - 128) > 4 }.count, 0,
                           "inner stroke remains at glyph edge: \(font.fontName)")
        }
    }

    func test80_5TwelveMegapixelBakeTiming() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 3024, height: 4032), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3024, height: 4032))
        }
        for font in try fonts() {
            let resolved = OverlayMetrics.resolvedFont(state: .available, postScriptName: font.fontName)
            let style = OverlayStyle(textColor: .white, outline: .stroke, outlineColor: .black,
                                     strokeWidth: 6, shadow: .none)
            var times: [Double] = []
            for iteration in 0..<6 {
                try autoreleasepool {
                    let start = CACurrentMediaTime()
                    let result = try XCTUnwrap(OverlayRenderer().bake(image: photo, text: "0 8 日 囍 &",
                        style: style, placement: .anchor(.middleCenter), font: resolved))
                    XCTAssertEqual(result.cgImage?.width, 3024)
                    if iteration > 0 { times.append((CACurrentMediaTime() - start) * 1000) }
                }
            }
            print("TASK80 12MP \(font.fontName): median=\(times.sorted()[times.count / 2])ms samples=\(times)")
        }
    }

    private func legacy(_ text: String, font: UIFont, width: Double) -> UIImage {
        image { context in
            context.setLineJoin(.round)
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .strokeColor: UIColor.white,
                .strokeWidth: width * 2 / 17 * 100])
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor.black])
        }
    }

    func test80_2ThinOutlineMatchesLegacyWithinAntialiasing() throws {
        for font in try fonts() {
            let old = try alpha(legacy("0 8 日 囍 & fi", font: font, width: 1))
            let current = try alpha(rendered("0 8 日 囍 & fi", font: font, width: 1))
            var total = 0, ink = 0
            for i in old.indices where old[i] > 0 || current[i] > 0 {
                total += abs(Int(old[i]) - Int(current[i]))
                ink += 1
            }
            let difference = Double(total) / Double(max(1, ink)) / 255
            print("TASK80 thin \(font.fontName): mean alpha difference=\(difference)")
            XCTAssertLessThan(difference, 0.04, font.fontName)
            attach(legacy("0 8 日 囍 & fi", font: font, width: 6), name: "80.1-before-\(font.fontName)")
            attach(try rendered("0 8 日 囍 & fi", font: font, width: 6), name: "80.1-after-\(font.fontName)")
        }
    }

    func test80_4EmojiRetainsOriginalBitmapFill() throws {
        let font = try XCTUnwrap(UIFont(name: "PingFangTC-Semibold", size: fontSize))
        let text = "👨‍👩‍👧‍👦"
        // The renderer leaves a glyph alone when Core Text has no outline for
        // it. Some simulator runtimes (the iOS 26.3 Intel one) ship an
        // Apple Color Emoji without the pictures: every emoji falls back to
        // one outlined placeholder glyph, which is not a bitmap and gets a
        // stroke like any other outline. Skip there (#427).
        try XCTSkipIf(hasOutlineGlyph(text, font: font), "this simulator's emoji font has no bitmap for \(text)")
        let plain = image { _ in
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
        XCTAssertTrue(try rgba(plain) == rgba(rendered(text, font: font, width: 6)), "bitmap emoji changed")
    }

    func test80_4StyleSwatchMatchesRendererOutline() throws {
        fontSize = 68
        let font = try XCTUnwrap(try fonts().first { $0.fontName == "Task80Thin" })
        let text = "0 8 日 囍 &"
        let width: CGFloat = 24 // 6 × 68 / 17, matching the renderer's scale.
        let swatch = StyleSwatchPreview.strokedText(text, font: font, fill: .black,
                                                   stroke: .white, strokeWidth: width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = swatch.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let composed = renderer.image { _ in
            swatch.draw(at: CGPoint(x: origin.x - ceil(width * 2), y: origin.y - ceil(width * 2)))
        }
        let resolved = OverlayMetrics.resolvedFont(state: .available, postScriptName: font.fontName)
        let style = OverlayStyle(textColor: .black, outline: .stroke, outlineColor: .white,
                                 strokeWidth: 6, shadow: .none)
        let overlay = try XCTUnwrap(OverlayRenderer().renderText(text, style: style, fontSize: fontSize,
                                                                displayScale: format.scale, font: resolved))
        let rendered = renderer.image { _ in
            overlay.image.draw(in: overlay.imageFrame(forBlockOrigin: origin))
        }
        let expected = try alpha(rendered)
        let actual = try alpha(composed)
        let ink = expected.indices.filter { expected[$0] > 0 || actual[$0] > 0 }
        let difference = Double(ink.reduce(0) { $0 + abs(Int(expected[$1]) - Int(actual[$1])) })
            / Double(max(1, ink.count)) / 255
        XCTAssertLessThan(difference, 0.01, "swatch differs beyond scale resampling tolerance")
        attach(composed, name: "80.4-style-swatch")
        attach(rendered, name: "80.4-renderer")
    }

    func test80_4PreviewAndBakeShareTheOutline() throws {
        let font = try XCTUnwrap(try fonts().first { $0.fontName == "Task80Thin" })
        let resolved = OverlayMetrics.resolvedFont(state: .available, postScriptName: font.fontName)
        let style = OverlayStyle(textColor: .white, outline: .stroke, outlineColor: .black,
                                 strokeWidth: 6, shadow: .none)
        let text = "0 8 日 囍 &"
        let canvas = CGSize(width: 1200, height: 1600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let photo = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.lightGray.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
        }
        let pointSize = OverlayRenderer.fittedFontSize(for: text, style: style, frameSize: canvas, font: resolved)
        let overlay = try XCTUnwrap(OverlayRenderer().renderText(text, style: style, fontSize: pointSize,
                                                               displayScale: 1, font: resolved))
        // An integer block origin avoids resampling the preview at a fractional pixel.
        let placement = OverlayPlacement.anchor(.topLeading)
        let blockOrigin = OverlayMetrics.origin(forBlockSize: overlay.blockSize, in: canvas, placement: placement)
        let preview = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            photo.draw(at: .zero)
            overlay.image.draw(in: overlay.imageFrame(forBlockOrigin: blockOrigin))
        }
        let baked = try XCTUnwrap(OverlayRenderer().bake(image: photo, text: text, style: style,
                                                        placement: placement, font: resolved))
        let first = try rgba(preview), second = try rgba(baked)
        let region = overlay.imageFrame(forBlockOrigin: blockOrigin).integral
        var total = 0, count = 0
        for y in max(0, Int(region.minY))..<min(Int(canvas.height), Int(region.maxY)) {
            for x in max(0, Int(region.minX))..<min(Int(canvas.width), Int(region.maxX)) {
                let offset = (y * Int(canvas.width) + x) * 4
                for channel in 0..<3 {
                    total += abs(Int(first[offset + channel]) - Int(second[offset + channel]))
                    count += 1
                }
            }
        }
        let difference = Double(total) / Double(count) / 255
        print("TASK80 preview/bake mean RGB difference=\(difference)")
        XCTAssertLessThan(difference, 0.005, "preview raster resampling exceeded antialias tolerance")
        attach(preview, name: "80.4-preview")
        attach(baked, name: "80.4-bake")
    }

}
