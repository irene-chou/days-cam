import CoreText
import XCTest
@testable import DaysCam

/// TASK-80: compare outlines against an independently dilated opaque glyph mask.
final class OverlayRendererStrokeTests: XCTestCase {
    private let origin = CGPoint(x: 65, y: 35)
    private let size = CGSize(width: 600, height: 230)
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
        let offsets = (-radius...radius).flatMap { y in
            (-radius...radius).compactMap { x in x*x + y*y <= radius*radius ? (x, y) : nil }
        }
        for font in try fonts() {
            for text in ["0", "8", "日", "囍", "&", "fi &"] {
                let plain = image { _ in
                    (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor.white])
                }
                let mask = try alpha(plain)
                XCTAssertTrue(mask.contains(255), "fixture has no opaque ink")
                let outlined = try rendered(text, font: font, width: 6)
                let actual = try alpha(outlined)
                var expected = mask.map { $0 == 255 }
                for y in 0..<Int(size.height) {
                    for x in 1..<(Int(size.width) - 1) where y > 0 && y < Int(size.height) - 1 && mask[y * Int(size.width) + x] == 255 {
                        let i = y * Int(size.width) + x
                        guard mask[i - 1] < 255 || mask[i + 1] < 255 || mask[i - Int(size.width)] < 255 || mask[i + Int(size.width)] < 255 else { continue }
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
        let plain = image { _ in
            (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
        XCTAssertTrue(try rgba(plain) == rgba(rendered(text, font: font, width: 6)), "bitmap emoji changed")
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

    func test80_DiagnoseMaximumOutlineBounds() throws {
        for font in try fonts() where font.fontName == "Task80Thin" || font.fontName == "PingFangTC-Thin" {
            let text = font.fontName == "Task80Thin" ? "0" : "fi &"
            let geometry = OverlayStrokeGeometry(text: text, font: font, width: 24)
            let direct = image { context in
                geometry.draw(in: context, at: origin, color: .white, excludingFill: false)
                (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: UIColor.black])
            }
            let resolved = OverlayMetrics.resolvedFont(state: .available, postScriptName: font.fontName)
            let overlay = try XCTUnwrap(OverlayRenderer().renderText(text, style: OverlayStyle(textColor: .black,
                outline: .stroke, outlineColor: .white, strokeWidth: 6, shadow: .none), fontSize: fontSize,
                displayScale: 1, font: resolved))
            print("TASK80 bounds \(font.fontName): fill=\(geometry.fillPath.boundingBoxOfPath) outline=\(geometry.outlinePath.boundingBoxOfPath) image=\(overlay.image.size) insets=\(overlay.textInsets)")
            let rasterStroke = image { context in
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y)
                context.setFillColor(UIColor.white.cgColor)
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(48)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.addPath(geometry.fillPath)
                context.drawPath(using: .fillStroke)
                context.restoreGState()
            }
            let segmented = image { context in
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y)
                context.setFillColor(UIColor.white.cgColor)
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(48)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.addPath(geometry.fillPath)
                context.fillPath()
                var current = CGPoint.zero, start = CGPoint.zero
                geometry.fillPath.applyWithBlock { pointer in
                    let element = pointer.pointee
                    context.beginPath()
                    context.move(to: current)
                    switch element.type {
                    case .moveToPoint: current = element.points[0]; start = current
                    case .addLineToPoint: context.addLine(to: element.points[0]); current = element.points[0]
                    case .addQuadCurveToPoint:
                        context.addQuadCurve(to: element.points[1], control: element.points[0]); current = element.points[1]
                    case .addCurveToPoint:
                        context.addCurve(to: element.points[2], control1: element.points[0], control2: element.points[1]); current = element.points[2]
                    case .closeSubpath: context.addLine(to: start); current = start
                    @unknown default: break
                    }
                    context.strokePath()
                }
                context.restoreGState()
            }
            attach(segmented, name: "80-diagnostic-segmented-\(font.fontName)")
            attach(rasterStroke, name: "80-diagnostic-rasterStroke-\(font.fontName)")
            attach(direct, name: "80-diagnostic-direct-\(font.fontName)")
            attach(try rendered(text, font: font, width: 6), name: "80-diagnostic-renderer-\(font.fontName)")
        }
    }

}
