import CryptoKit
import UIKit
import XCTest
@testable import DaysCam

/// TASK-89 independent QA (89.2): dumps a pixel fingerprint of the baked
/// photo for a legacy style (no `fontWeight` key) for every font, so the same
/// file can run against `origin/main` and the PR and the two outputs be diffed.
/// Uses only APIs that exist on both sides. Skipped unless
/// `DAYSCAM_PIXEL_OUT` is set (pass it as `TEST_RUNNER_DAYSCAM_PIXEL_OUT`).
/// `DAYSCAM_FONT_FIXTURES` optionally points at a folder of .otf/.ttf files
/// that are registered first, so the open-source fonts draw for real.
@MainActor
final class FontWeightPixelBaselineAcceptanceTests: XCTestCase {
    private struct Availability: FontAvailabilityProviding {
        let state: FontState
        func state(for fontID: OverlayFontID) -> FontState { state }
    }

    func test_acceptance_89_2_dumpLegacyBakeFingerprints() throws {
        guard let outPath = ProcessInfo.processInfo.environment["DAYSCAM_PIXEL_OUT"] else {
            throw XCTSkip("Set DAYSCAM_PIXEL_OUT to dump fingerprints")
        }
        if let fixtures = ProcessInfo.processInfo.environment["DAYSCAM_FONT_FIXTURES"] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: fixtures)) ?? []
            for name in names.sorted() where name.hasSuffix(".otf") || name.hasSuffix(".ttf") {
                var error: Unmanaged<CFError>?
                let url = URL(fileURLWithPath: fixtures).appendingPathComponent(name) as CFURL
                _ = CTFontManagerRegisterFontsForURL(url, .process, &error)
            }
        }
        let canvas = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320)).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
        }
        var lines: [String] = []
        for fontID in OverlayFontID.allCases {
            for (label, state) in [("available", FontState.available), ("missing", FontState.notDownloaded)] {
                var style = OverlayStyle(fontID: fontID, outline: .stroke, shadow: .soft)
                var json = try XCTUnwrap(JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(style)) as? [String: Any])
                json.removeValue(forKey: "fontWeight")
                style = try JSONDecoder().decode(OverlayStyle.self,
                                                 from: JSONSerialization.data(withJSONObject: json))
                let font = OverlayMetrics.resolvedFont(for: fontID, availability: Availability(state: state))
                let baked = try XCTUnwrap(OverlayRenderer().bake(
                    image: canvas, text: "第 10 天", style: style,
                    placement: .anchor(.bottomTrailing), font: font)?.cgImage)
                let data = try XCTUnwrap(baked.dataProvider?.data) as Data
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                lines.append("\(fontID.rawValue) \(label) ps=\(font.postScriptName) "
                    + "\(baked.width)x\(baked.height) \(digest)")
            }
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
        XCTAssertEqual(lines.count, OverlayFontID.allCases.count * 2)
    }
}
