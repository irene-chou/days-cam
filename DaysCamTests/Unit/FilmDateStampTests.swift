import CoreGraphics
import UIKit
import XCTest
@testable import DaysCam

/// Covers TASK-151 (#520) acceptance 151.1–151.9: the `'YY MM DD` text, the
/// profile fields and their decoding, and the baked stamp's colour, size,
/// corner, direction and crop handling. The colour, size and glyph checks
/// follow the three-layer look of #578 (halo, body, core).
final class FilmDateStampTests: XCTestCase {

    // MARK: - 151.1 / 151.2 text

    func test_151_1_textIsApostropheTwoDigitYearPaddedMonthAndDay() {
        XCTAssertEqual(FilmDateStamp.text(for: DateFixture.components(2025, 10, 12)), "'25 10 12")
        XCTAssertEqual(FilmDateStamp.text(for: DateFixture.components(2026, 1, 5)), "'26 01 05")
        XCTAssertEqual(FilmDateStamp.text(for: DateFixture.components(2000, 2, 29)), "'00 02 29")
    }

    func test_151_2_textComesFromTheInjectedCaptureMomentAcrossMidnight() throws {
        let beforeMidnight = try XCTUnwrap(DateFixture.date(2025, 10, 12, hour: 23, minute: 59, second: 59))
        let atMidnight = try XCTUnwrap(DateFixture.date(2025, 10, 13))
        let before = DayCountCalculator(calendar: DateFixture.taipei, now: { beforeMidnight })
        let after = DayCountCalculator(calendar: DateFixture.taipei, now: { atMidnight })
        XCTAssertEqual(FilmDateStamp.text(for: before.currentDateComponents()), "'25 10 12")
        XCTAssertEqual(FilmDateStamp.text(for: after.currentDateComponents()), "'25 10 13")
    }

    // MARK: - 151.3 / 151.4 profile fields

    private func sampleProfile() -> CameraProfile {
        CameraProfile(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
                      name: "小寶",
                      startDate: DateFixture.components(2024, 3, 9),
                      countingRule: .dayZero,
                      showDayCount: true,
                      showDate: true,
                      showName: true,
                      displayUnits: [.year, .month],
                      useAgeWording: true,
                      position: .custom(x: 0.3, y: 0.7),
                      style: OverlayStyle(legacyTheme: .softPink),
                      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                      updatedAt: Date(timeIntervalSince1970: 1_700_000_500))
    }

    private func jsonObject(_ profile: CameraProfile) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> CameraProfile {
        try JSONDecoder().decode(CameraProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func test_151_3_profileWithoutTheFieldsDecodesWithDefaultsAndKeepsEverythingElse() throws {
        let original = sampleProfile()
        var json = try jsonObject(original)
        XCTAssertNotNil(json.removeValue(forKey: "showFilmDate"))
        XCTAssertNotNil(json.removeValue(forKey: "filmDateCorner"))

        let decoded = try decode(json)

        XCTAssertFalse(decoded.showFilmDate)
        XCTAssertEqual(decoded.filmDateCorner, .bottomLeading)
        XCTAssertEqual(decoded, original)
    }

    func test_151_3_newProfileDefaultsToOffAndBottomLeading() {
        let profile = CameraProfile(name: "新", startDate: DateFixture.components(2025, 1, 1))
        XCTAssertFalse(profile.showFilmDate)
        XCTAssertEqual(profile.filmDateCorner, .bottomLeading)
    }

    func test_151_4_everyCornerSurvivesARoundTrip() throws {
        for corner in FilmDateCorner.allCases {
            var profile = sampleProfile()
            profile.showFilmDate = true
            profile.filmDateCorner = corner
            let decoded = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(profile))
            XCTAssertEqual(decoded, profile, "\(corner)")
            XCTAssertNoThrow(try decoded.validatedForPersistence(calendar: DateFixture.taipei))
        }
    }

    func test_151_4_unknownCornerFallsBackWithoutLosingTheProfile() throws {
        var original = sampleProfile()
        original.showFilmDate = true
        original.filmDateCorner = .topTrailing
        for bad in ["center", "", 3] as [Any] {
            var json = try jsonObject(original)
            json["filmDateCorner"] = bad
            let decoded = try decode(json)
            XCTAssertEqual(decoded.filmDateCorner, .bottomLeading, "\(bad)")
            XCTAssertTrue(decoded.showFilmDate)
            XCTAssertEqual(decoded.name, original.name)
            XCTAssertEqual(decoded.style, original.style)
        }
    }

    func test_151_4_duplicatingAProfileKeepsTheFilmDate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "FilmDateStampTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let instant = Date(timeIntervalSince1970: 1_760_000_000)
        let store = ProfileStore(directory: directory, calendar: DateFixture.taipei, now: { instant },
                                 defaults: defaults, scheduler: ProfileStore.immediateScheduler)
        var profile = sampleProfile()
        profile.showFilmDate = true
        profile.filmDateCorner = .topLeading
        let added = try store.add(profile)

        let copy = try store.duplicate(id: added.id)

        XCTAssertTrue(copy.showFilmDate)
        XCTAssertEqual(copy.filmDateCorner, .topLeading)
    }

    // MARK: - Rotation table (§7)

    func test_rotationFollowsTheCornerTable() {
        XCTAssertEqual(FilmDateCorner.bottomLeading.rotation, 90)
        XCTAssertEqual(FilmDateCorner.topLeading.rotation, 0)
        XCTAssertEqual(FilmDateCorner.topTrailing.rotation, -90)
        XCTAssertEqual(FilmDateCorner.bottomTrailing.rotation, 0)
    }

    // MARK: - Baking

    private let renderer = OverlayRenderer()
    private let style = OverlayStyle(legacyTheme: .classicWhite)
    private let stampText = "'25 10 12"
    private static let gray: CGFloat = 0.5

    private func grayPhoto(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(white: Self.gray, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// RGBA8 pixels of an image, row-major from the top.
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: UIImage) throws {
            let cgImage = try XCTUnwrap(image.cgImage)
            width = cgImage.width
            height = cgImage.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data: raw.baseAddress, width: cgImage.width, height: cgImage.height,
                                              bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                return true
            }
            XCTAssertTrue(drew)
            bytes = buffer
        }

        func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let index = (y * width + x) * 4
            return (Double(bytes[index]) / 255, Double(bytes[index + 1]) / 255, Double(bytes[index + 2]) / 255)
        }

        /// How far a pixel has moved from gray towards film orange, judged
        /// on red minus blue (gray 0, body orange 0.88). The yellow-white
        /// core scores about half, so it never reads as a hole.
        func orangeness(_ x: Int, _ y: Int) -> Double {
            let (red, _, blue) = rgb(x, y)
            return (red - blue) / Double(FilmDateStamp.Metrics.red - FilmDateStamp.Metrics.blue)
        }

        /// The rightmost run of ink (orangeness ≥ 0.5) on row `y` within
        /// `minX..<maxX`, as its first and last column.
        func rightmostInkRun(row y: Int, minX: Int, maxX: Int) -> (first: Int, last: Int)? {
            var x = maxX - 1
            while x >= minX, orangeness(x, y) < 0.5 { x -= 1 }
            guard x >= minX else { return nil }
            let last = x
            while x - 1 >= minX, orangeness(x - 1, y) >= 0.5 { x -= 1 }
            return (x, last)
        }

        /// The bounding box of pixels at least `threshold` orange inside `region`.
        func inkBox(in region: CGRect, threshold: Double = 0.5) -> CGRect? {
            var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
            let clipped = region.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
            for y in Int(clipped.minY)..<Int(clipped.maxY) {
                for x in Int(clipped.minX)..<Int(clipped.maxX) where orangeness(x, y) >= threshold {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard minX <= maxX else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }

    /// CIE76 ΔE between two sRGB colours.
    private func deltaE(_ first: (Double, Double, Double), _ second: (Double, Double, Double)) -> Double {
        func lab(_ rgb: (Double, Double, Double)) -> (Double, Double, Double) {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            let r = linear(rgb.0), g = linear(rgb.1), b = linear(rgb.2)
            let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
            func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
            return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
        }
        let a = lab(first), b = lab(second)
        return sqrt(pow(a.0 - b.0, 2) + pow(a.1 - b.1, 2) + pow(a.2 - b.2, 2))
    }

    private func bake(_ photo: UIImage, text: String = "", corner: FilmDateCorner?,
                      placement: OverlayPlacement = .anchor(.bottomTrailing),
                      cropRect: CGRect? = nil) throws -> UIImage {
        try XCTUnwrap(renderer.bake(image: photo, text: text, style: style, placement: placement,
                                    font: .pingFang, cropRect: cropRect,
                                    filmDate: corner.map { FilmDateStamp(text: stampText, corner: $0) }))
    }

    /// A generous search window around where the stamp should be.
    private func searchRegion(around frame: CGRect) -> CGRect {
        frame.insetBy(dx: -frame.height * 0.5 - 40, dy: -frame.width * 0.2 - 40)
            .union(frame.insetBy(dx: -frame.width * 0.2 - 40, dy: -frame.height * 0.5 - 40))
    }

    func test_151_5_bottomTrailingStampIsFilmOrangeSizedAndPlaced() throws {
        let photo = grayPhoto(width: 4000, height: 3000)
        let baked = try bake(photo, corner: .bottomTrailing)
        let pixels = try Pixels(baked)
        let shortEdge = 3000.0

        // Soft edges: the box is measured to ±3px (#578).
        let box = try XCTUnwrap(pixels.inkBox(in: CGRect(x: 2000, y: 1500, width: 2000, height: 1500)))
        let rightMargin = 4000 - box.maxX
        let bottomMargin = 3000 - box.maxY
        XCTAssertEqual(rightMargin, shortEdge * 0.045, accuracy: 3, "box \(box)")
        XCTAssertEqual(bottomMargin, shortEdge * 0.045, accuracy: 3, "box \(box)")
        XCTAssertEqual(box.height, shortEdge * 0.042, accuracy: 3, "box \(box)")

        // The last digit (2) ends in a bottom segment and has no bottom-right
        // one, so the rightmost ink on the bottom segment's centre row is
        // that segment, tip to tip; its middle is the segment centre.
        let height = FilmDateStamp.glyphHeight(forCanvasSize: CGSize(width: 4000, height: 3000))
        let thickness = FilmDateStamp.Metrics.segmentThicknessRatio * height
        let centreY = Int((box.maxY - thickness / 2).rounded())
        let run = try XCTUnwrap(pixels.rightmostInkRun(row: centreY, minX: Int(box.minX), maxX: Int(box.maxX) + 1))
        let centre = (x: (run.first + run.last) / 2, y: centreY)

        // Segment centre: the yellow-white core. The core bar is thinner than
        // its own blur, so the centre is a blend leaning to the core colour,
        // never pure #FFD089 (the design mockup has the same physics).
        let core = (Double(FilmDateStamp.Metrics.coreRed), Double(FilmDateStamp.Metrics.coreGreen),
                    Double(FilmDateStamp.Metrics.coreBlue))
        let body = (Double(FilmDateStamp.Metrics.red), Double(FilmDateStamp.Metrics.green),
                    Double(FilmDateStamp.Metrics.blue))
        let centrePixel = pixels.rgb(centre.x, centre.y)
        XCTAssertLessThan(deltaE(centrePixel, core), 18, "pixel \(centrePixel) at \(centre)")
        XCTAssertLessThan(deltaE(centrePixel, core), deltaE(centrePixel, body), "pixel \(centrePixel) at \(centre)")

        // Between core and edge (0.3 × thickness off the centre line): the
        // film-orange body, still red and less blue than the core.
        let bodyPoint = (x: centre.x, y: centre.y - Int((thickness * 0.3).rounded()))
        let bodyPixel = pixels.rgb(bodyPoint.x, bodyPoint.y)
        XCTAssertGreaterThan(bodyPixel.0, 0.85, "pixel \(bodyPixel) at \(bodyPoint)")
        XCTAssertLessThan(bodyPixel.2, centrePixel.2, "body \(bodyPixel) vs core \(centrePixel)")

        // Just outside the glyph box (0.1 × height below the bottom segment):
        // the halo tints the gray orange. Less 3 levels for the round trip
        // through `bake`'s 8-bit Display P3 canvas (#586).
        let haloPoint = (x: centre.x, y: Int(box.maxY) + Int((height * 0.1).rounded()))
        let haloPixel = pixels.rgb(haloPoint.x, haloPoint.y)
        XCTAssertGreaterThan(haloPixel.0 - haloPixel.2, 0.04 - 3.0 / 255, "pixel \(haloPixel) at \(haloPoint)")

        // Well outside (0.8 × height below): still the gray photo.
        let gray = (Double(Self.gray), Double(Self.gray), Double(Self.gray))
        let farPoint = (x: centre.x, y: Int(box.maxY) + Int((height * 0.8).rounded()))
        let farPixel = pixels.rgb(farPoint.x, farPoint.y)
        XCTAssertLessThan(deltaE(farPixel, gray), 2, "pixel \(farPixel) at \(farPoint)")

        // Far corner untouched.
        let reference = pixels.rgb(0, 0)
        var changed = 0
        for y in 0..<1000 {
            for x in 0..<1500 where pixels.rgb(x, y) != reference {
                changed += 1
            }
        }
        XCTAssertEqual(changed, 0)
        XCTAssertEqual(reference.0, Self.gray, accuracy: 1.0 / 255)
    }

    // MARK: - Core glyph path (#578)

    /// The closed subpaths of `path`, in drawing order, as their boxes.
    private func subpathBoxes(_ path: CGPath) -> [CGRect] {
        var boxes: [CGRect] = []
        var current: [CGPoint] = []
        func flush() {
            guard let first = current.first else { return }
            var box = CGRect(origin: first, size: .zero)
            for point in current.dropFirst() {
                box = box.union(CGRect(origin: point, size: .zero))
            }
            boxes.append(box)
            current = []
        }
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint:
                flush()
                current = [element.pointee.points[0]]
            case .addLineToPoint:
                current.append(element.pointee.points[0])
            case .closeSubpath:
                flush()
            default:
                break
            }
        }
        flush()
        return boxes
    }

    func test_578_coreGlyphPathIsConcentricWithTheBodyAndKeepsItsBox() {
        let height: CGFloat = 126
        let body = FilmDateStamp.glyphPath(for: stampText, height: height)
        let core = FilmDateStamp.glyphPath(for: stampText, height: height,
                                           thicknessRatio: FilmDateStamp.Metrics.segmentThicknessRatio
                                               * FilmDateStamp.Metrics.coreThicknessFraction)
        XCTAssertEqual(core.size, body.size)

        let bodyBoxes = subpathBoxes(body.path)
        let coreBoxes = subpathBoxes(core.path)
        XCTAssertEqual(bodyBoxes.count, coreBoxes.count)
        XCTAssertGreaterThan(bodyBoxes.count, 20, "nine characters' segments")
        for (index, (outer, inner)) in zip(bodyBoxes, coreBoxes).enumerated() {
            XCTAssertTrue(outer.insetBy(dx: -0.01, dy: -0.01).contains(inner), "segment \(index): \(inner) in \(outer)")
            XCTAssertLessThan(abs(outer.midX - inner.midX), 0.5, "segment \(index)")
            XCTAssertLessThan(abs(outer.midY - inner.midY), 0.5, "segment \(index)")
            XCTAssertLessThan(inner.width * inner.height, outer.width * outer.height, "segment \(index)")
        }
    }

    func test_151_6_eachCornerPlacesAndTurnsTheStampPerTheTable() throws {
        let canvas = CGSize(width: 4000, height: 3000)
        let photo = grayPhoto(width: 4000, height: 3000)
        let height = FilmDateStamp.glyphHeight(forCanvasSize: canvas)
        // The leading strip along the reading direction holds the apostrophe
        // only, which sits at the glyph top.
        let strip = height * 0.12

        for corner in FilmDateCorner.allCases {
            let expected = FilmDateStamp(text: stampText, corner: corner).frame(inCanvasSize: canvas)
            let pixels = try Pixels(try bake(photo, corner: corner))
            let box = try XCTUnwrap(pixels.inkBox(in: searchRegion(around: expected)), "\(corner)")

            // Soft edges: ±3px (#578).
            XCTAssertEqual(box.minX, expected.minX, accuracy: 3, "\(corner) \(box) vs \(expected)")
            XCTAssertEqual(box.minY, expected.minY, accuracy: 3, "\(corner) \(box) vs \(expected)")
            XCTAssertEqual(box.maxX, expected.maxX, accuracy: 3, "\(corner) \(box) vs \(expected)")
            XCTAssertEqual(box.maxY, expected.maxY, accuracy: 3, "\(corner) \(box) vs \(expected)")
            XCTAssertEqual(box.minX < canvas.width / 2, corner == .topLeading || corner == .bottomLeading, "\(corner)")
            XCTAssertEqual(box.minY < canvas.height / 2, corner == .topLeading || corner == .topTrailing, "\(corner)")

            let leadingStrip: CGRect
            let headSide: (CGRect) -> Bool
            switch corner.rotation {
            case 90:
                // Read top to bottom; glyph tops face right (inward).
                XCTAssertGreaterThan(box.height, box.width * 3, "\(corner)")
                leadingStrip = CGRect(x: box.minX, y: box.minY, width: box.width, height: strip)
                headSide = { $0.minX >= box.midX }
            case -90:
                // Read bottom to top; glyph tops face left (inward).
                XCTAssertGreaterThan(box.height, box.width * 3, "\(corner)")
                leadingStrip = CGRect(x: box.minX, y: box.maxY - strip, width: box.width, height: strip)
                headSide = { $0.maxX <= box.midX }
            default:
                XCTAssertGreaterThan(box.width, box.height * 3, "\(corner)")
                leadingStrip = CGRect(x: box.minX, y: box.minY, width: strip, height: box.height)
                headSide = { $0.maxY <= box.midY }
            }
            let first = try XCTUnwrap(pixels.inkBox(in: leadingStrip), "\(corner)")
            XCTAssertTrue(headSide(first), "\(corner): first character at \(first) in \(box)")
        }
    }

    func test_151_7_cropWindowIsTheCanvasForMarginsAndSize() throws {
        let photo = grayPhoto(width: 3000, height: 4000)
        let crop = CGRect(x: 375, y: 0, width: 2250, height: 4000)
        let baked = try bake(photo, corner: .bottomLeading, cropRect: crop)
        XCTAssertEqual(baked.size, crop.size)

        let canvas = crop.size
        let expected = FilmDateStamp(text: stampText, corner: .bottomLeading).frame(inCanvasSize: canvas)
        let pixels = try Pixels(baked)
        let box = try XCTUnwrap(pixels.inkBox(in: searchRegion(around: expected)))
        XCTAssertEqual(box.minX, 2250 * 0.045, accuracy: 3, "\(box)")
        XCTAssertEqual(4000 - box.maxY, 2250 * 0.045, accuracy: 3, "\(box)")
        XCTAssertEqual(box.width, 2250 * 0.042, accuracy: 3, "\(box)")
    }

    func test_151_8_nilFilmDateIsPixelIdenticalAndEmptyTextStillPrintsTheStamp() throws {
        let photo = grayPhoto(width: 1200, height: 900)
        let withoutParameter = try XCTUnwrap(renderer.bake(image: photo, text: "第 10 天", style: style,
                                                            placement: .anchor(.bottomTrailing), font: .pingFang))
        let withNil = try bake(photo, text: "第 10 天", corner: nil)
        XCTAssertEqual(try Pixels(withoutParameter).bytes, try Pixels(withNil).bytes)

        let untouched = try bake(photo, corner: nil)
        XCTAssertTrue(untouched === photo, "nothing to print returns the input as is")

        let stampOnly = try bake(photo, corner: .bottomLeading)
        XCTAssertFalse(stampOnly === photo)
        let expected = FilmDateStamp(text: stampText, corner: .bottomLeading)
            .frame(inCanvasSize: CGSize(width: 1200, height: 900))
        XCTAssertNotNil(try Pixels(stampOnly).inkBox(in: searchRegion(around: expected)))
    }

    func test_151_9_mainTextAndStampInTheSameCornerAreBothDrawn() throws {
        let photo = grayPhoto(width: 1200, height: 900)
        let both = try Pixels(try bake(photo, text: "第 10 天", corner: .bottomTrailing))
        let textOnly = try Pixels(try bake(photo, text: "第 10 天", corner: nil))
        let stampOnly = try Pixels(try bake(photo, corner: .bottomTrailing))
        XCTAssertNotEqual(both.bytes, textOnly.bytes)
        XCTAssertNotEqual(both.bytes, stampOnly.bytes)
        let expected = FilmDateStamp(text: stampText, corner: .bottomTrailing)
            .frame(inCanvasSize: CGSize(width: 1200, height: 900))
        XCTAssertNotNil(both.inkBox(in: searchRegion(around: expected)))
    }
}
