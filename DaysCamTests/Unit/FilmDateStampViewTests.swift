import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// TASK-153 (#522) 153.5: the viewfinder stamp and the baked stamp land in the
/// same place at the same size, measured on pixels, for the three ratios and
/// every corner. The viewfinder is rendered the way the screen draws it
/// (`FilmDateStampView` at a phone's point size, 3x) and the photo with
/// `OverlayRenderer.bake`; both are measured as a fraction of the short edge.
@MainActor
final class FilmDateStampViewTests: XCTestCase {
    private let text = "'25 10 12"
    /// Viewfinder boxes of a 393pt-wide phone (iPhone 16) for 1:1, 3:4, 9:16.
    private let boxes: [(name: String, size: CGSize)] = [
        ("1x1", CGSize(width: 393, height: 393)),
        ("3x4", CGSize(width: 393, height: 524)),
        ("9x16", CGSize(width: 393, height: 699)),
    ]

    func test_153_5_previewAndBakedStampAgreeWithinHalfAPercentOfTheShortEdge() throws {
        for box in boxes {
            for corner in FilmDateCorner.allCases {
                let stamp = FilmDateStamp(text: text, corner: corner)
                let preview = try XCTUnwrap(inkBox(inPreview: stamp, size: box.size), "\(box.name) \(corner)")
                // The photo: same aspect ratio, 12MP-ish, crop = the whole image.
                let scale = 3024 / min(box.size.width, box.size.height)
                let photoSize = CGSize(width: (box.size.width * scale).rounded(),
                                       height: (box.size.height * scale).rounded())
                let baked = try XCTUnwrap(inkBox(inBaked: stamp, size: photoSize), "\(box.name) \(corner)")

                let previewShort = min(box.size.width, box.size.height)
                let bakedShort = min(photoSize.width, photoSize.height)
                let label = "\(box.name) \(corner) preview \(preview) baked \(baked)"
                XCTAssertEqual(preview.minX / previewShort, baked.minX / bakedShort, accuracy: 0.005, label)
                XCTAssertEqual(preview.minY / previewShort, baked.minY / bakedShort, accuracy: 0.005, label)
                XCTAssertEqual(preview.width / previewShort, baked.width / bakedShort, accuracy: 0.005, label)
                XCTAssertEqual(preview.height / previewShort, baked.height / bakedShort, accuracy: 0.005, label)
            }
        }
    }

    /// 153.1: no stamp, nothing drawn.
    func test_153_1_noStampDrawsNothing() throws {
        XCTAssertNil(try inkBox(inPreview: nil, size: CGSize(width: 393, height: 524)))
    }

    /// 153.8: one finished photo with the main text and the left-bottom
    /// vertical stamp, written to `DAYSCAM_UI_SHOT_DIR` when it is set.
    func test_153_8_writeBakedPhotoWithMainTextAndStamp() throws {
        let size = CGSize(width: 1512, height: 2016)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let photo = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(red: 0.25, green: 0.4, blue: 0.55, alpha: 1).cgColor,
                          UIColor(red: 0.85, green: 0.75, blue: 0.6, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                         locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero,
                                                     end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
        let stamp = FilmDateStamp(text: text, corner: .bottomLeading)
        let baked = try XCTUnwrap(OverlayRenderer().bake(image: photo, text: "第 100 天", style: OverlayStyle(),
                                                         placement: .default, font: .pingFang,
                                                         cropRect: nil, filmDate: stamp))
        guard let path = ProcessInfo.processInfo.environment["DAYSCAM_UI_SHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(baked.pngData()).write(to: directory.appendingPathComponent("153.8_baked-photo.png"))
    }

    // MARK: - Measuring

    private static let gray: CGFloat = 0.5

    private func inkBox(inPreview stamp: FilmDateStamp?, size: CGSize) throws -> CGRect? {
        let view = FilmDateStampView(stamp: stamp, frameSize: size)
            .background(Color(white: Self.gray))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        let box = try ink(in: image)
        // Pixels at 3x → points.
        return box.map { CGRect(x: $0.minX / 3, y: $0.minY / 3, width: $0.width / 3, height: $0.height / 3) }
    }

    private func inkBox(inBaked stamp: FilmDateStamp, size: CGSize) throws -> CGRect? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let photo = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: Self.gray, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let baked = try XCTUnwrap(OverlayRenderer().bake(image: photo, text: "", style: OverlayStyle(),
                                                         placement: .default, font: .pingFang,
                                                         cropRect: nil, filmDate: stamp))
        return try ink(in: baked)
    }

    /// The box of the solid orange pixels (the glyph cores, not the glow).
    private func ink(in image: UIImage) throws -> CGRect? {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        let context = try XCTUnwrap(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: try XCTUnwrap(space),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                // Core ink: close to #FF8A1E; gray/glow blends have a blue near their red.
                if data[i] > 230, data[i + 1] > 110, data[i + 1] < 165, data[i + 2] < 70 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
