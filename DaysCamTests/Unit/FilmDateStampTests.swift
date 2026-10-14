import CoreGraphics
import UIKit
import XCTest
@testable import DaysCam

/// Covers TASK-151 (#520) acceptance 151.1–151.9: the `'YY MM DD` text, the
/// profile fields and their decoding, and the baked stamp's colour, size,
/// corner, direction and crop handling.
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
        /// on the blue channel (gray 0.5, orange 0.12).
        func orangeness(_ x: Int, _ y: Int) -> Double {
            let blue = rgb(x, y).2
            return (FilmDateStampTests.gray - blue) / (FilmDateStampTests.gray - Double(FilmDateStamp.Metrics.blue))
        }

        /// The bounding box of pixels at least `threshold` orange inside `region`.
        func inkBox(in region: CGRect, threshold: Double = 0.7) -> CGRect? {
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

        let box = try XCTUnwrap(pixels.inkBox(in: CGRect(x: 2000, y: 1500, width: 2000, height: 1500)))
        let rightMargin = 4000 - box.maxX
        let bottomMargin = 3000 - box.maxY
        XCTAssertEqual(rightMargin, shortEdge * 0.045, accuracy: 2, "box \(box)")
        XCTAssertEqual(bottomMargin, shortEdge * 0.045, accuracy: 2, "box \(box)")
        XCTAssertEqual(box.height, shortEdge * 0.035, accuracy: 2, "box \(box)")

        // The middle of the last digit's bottom segment is solid ink.
        let height = FilmDateStamp.glyphHeight(forCanvasSize: CGSize(width: 4000, height: 3000))
        let thickness = FilmDateStamp.Metrics.segmentThicknessRatio * height
        let digitWidth = FilmDateStamp.Metrics.digitWidthRatio * height
        let centre = (x: Int(box.maxX - digitWidth / 2 - thickness * 0.2), y: Int(box.maxY - thickness / 2))
        let orange = (Double(FilmDateStamp.Metrics.red), Double(FilmDateStamp.Metrics.green),
                      Double(FilmDateStamp.Metrics.blue))
        let difference = deltaE(pixels.rgb(centre.x, centre.y), orange)
        XCTAssertLessThan(difference, 10, "pixel \(pixels.rgb(centre.x, centre.y)) at \(centre)")

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

            XCTAssertEqual(box.minX, expected.minX, accuracy: 2, "\(corner) \(box) vs \(expected)")
            XCTAssertEqual(box.minY, expected.minY, accuracy: 2, "\(corner) \(box) vs \(expected)")
            XCTAssertEqual(box.maxX, expected.maxX, accuracy: 2, "\(corner) \(box) vs \(expected)")
            XCTAssertEqual(box.maxY, expected.maxY, accuracy: 2, "\(corner) \(box) vs \(expected)")
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
        XCTAssertEqual(box.minX, 2250 * 0.045, accuracy: 2, "\(box)")
        XCTAssertEqual(4000 - box.maxY, 2250 * 0.045, accuracy: 2, "\(box)")
        XCTAssertEqual(box.width, 2250 * 0.035, accuracy: 2, "\(box)")
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
