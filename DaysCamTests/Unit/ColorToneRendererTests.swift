import CoreGraphics
import XCTest
@testable import DaysCam

/// Covers #589 acceptance 1–3: what each tone step does to plain colors.
///
/// Colors are read back by drawing the output into an 8-bit sRGB bitmap, so
/// a P3 output is compared in the same terms as an sRGB one.
final class ColorToneRendererTests: XCTestCase {

    private let side = 200

    // MARK: - 1

    func test_589_1_standardReturnsTheSameImage() throws {
        let gray = try makeImage(red: 0.5, green: 0.5, blue: 0.5)

        let output = try XCTUnwrap(ColorToneRenderer.apply(.standard, to: gray))

        XCTAssertTrue(output === gray, "standard must hand back the very same CGImage")
    }

    // MARK: - 2

    func test_589_2_warm2WarmsAndCool2CoolsAGrayImage() throws {
        let gray = try makeImage(red: 0.5, green: 0.5, blue: 0.5)

        let warm = try center(of: tone(.warm2, gray))
        let cool = try center(of: tone(.cool2, gray))

        XCTAssertGreaterThan(warm.red - warm.blue, 0.06, "warm2 \(warm)")
        XCTAssertGreaterThan(cool.blue - cool.red, 0.06, "cool2 \(cool)")
    }

    func test_589_2_redMinusBlueRisesStrictlyThroughTheFiveSteps() throws {
        let gray = try makeImage(red: 0.5, green: 0.5, blue: 0.5)

        let spreads = try ColorTone.allCases.map { tone -> Double in
            let color = try center(of: self.tone(tone, gray))
            return color.red - color.blue
        }

        XCTAssertEqual(ColorTone.allCases, [.cool2, .cool1, .standard, .warm1, .warm2], "fixture order")
        for index in spreads.indices.dropFirst() {
            XCTAssertLessThan(spreads[index - 1], spreads[index],
                              "\(ColorTone.allCases[index - 1]) → \(ColorTone.allCases[index]): \(spreads)")
        }
    }

    func test_589_2_warm2ChangesColorNotBrightness() throws {
        let gray = try makeImage(red: 0.5, green: 0.5, blue: 0.5)

        let before = try center(of: gray)
        let after = try center(of: tone(.warm2, gray))

        XCTAssertLessThan(abs(after.brightness - before.brightness), 0.05, "\(before) → \(after)")
    }

    // MARK: - 3

    func test_589_3_pureRedStaysRedThroughWarm2() throws {
        let red = try makeImage(red: 1, green: 0, blue: 0)

        let output = try center(of: tone(.warm2, red))

        XCTAssertGreaterThanOrEqual(output.red, 0.98, "\(output)")
    }

    func test_589_3_outputKeepsTheInputColorSpaceAndSize() throws {
        for name in [CGColorSpace.displayP3, CGColorSpace.sRGB] {
            let input = try makeImage(red: 0.5, green: 0.5, blue: 0.5, colorSpace: name)
            for tone in ColorTone.allCases where tone != .standard {
                let output = try self.tone(tone, input)
                XCTAssertEqual(output.colorSpace?.name, name, "\(tone)")
                XCTAssertEqual(output.width, side)
                XCTAssertEqual(output.height, side)
                XCTAssertEqual(output.bitsPerComponent, 8, "\(tone)")
            }
        }
    }

    // MARK: - Helpers

    private struct Color: CustomStringConvertible {
        let red: Double
        let green: Double
        let blue: Double

        var brightness: Double { (red + green + blue) / 3 }
        var description: String { String(format: "(%.3f, %.3f, %.3f)", red, green, blue) }
    }

    private func tone(_ tone: ColorTone, _ image: CGImage,
                      file: StaticString = #filePath, line: UInt = #line) throws -> CGImage {
        try XCTUnwrap(ColorToneRenderer.apply(tone, to: image), "apply returned nil", file: file, line: line)
    }

    /// The center pixel, read back in 8-bit sRGB.
    private func center(of image: CGImage) throws -> Color {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [UInt8](repeating: 0, count: 4)
        let drew = pixel.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            // Draw the image so its middle pixel lands on the 1x1 canvas.
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2,
                                           width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(drew, "could not read the pixel back")
        return Color(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    /// A solid `side` x `side` image in `colorSpace`.
    private func makeImage(red: CGFloat, green: CGFloat, blue: CGFloat,
                           colorSpace name: CFString = CGColorSpace.sRGB) throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(name: name))
        let context = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [red, green, blue, 1])))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return try XCTUnwrap(context.makeImage())
    }
}
