import CoreText
import UIKit
import XCTest
@testable import DaysCam

/// TASK-89: exact-face resolution, old-profile pixels and persisted weights.
@MainActor
final class FontWeightRenderingTests: XCTestCase {
    private struct Availability: FontAvailabilityProviding {
        func state(for fontID: OverlayFontID) -> FontState { .available }
        func state(for fontID: OverlayFontID, weightID: String?) -> FontState { .available }
    }

    func testMissingWeightBakesExactlyTheLegacyPixelsForEveryFont() throws {
        let renderer = OverlayRenderer()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 200)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 200))
        }
        for entry in FontCatalog.entries {
            let legacy = OverlayStyle(fontID: entry.fontID)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
            json.removeValue(forKey: "fontWeight")
            let decoded = try JSONDecoder().decode(OverlayStyle.self, from: JSONSerialization.data(withJSONObject: json))
            // Same pre-TASK-89 resolution policy, including unavailable-face fallback.
            let beforeFont = OverlayMetrics.resolvedFont(state: .available, postScriptName: entry.postScriptName)
            let afterFont = OverlayMetrics.resolvedFont(for: decoded, availability: Availability())
            XCTAssertEqual(afterFont, beforeFont, entry.fontID.rawValue)
            let before = try XCTUnwrap(renderer.bake(image: image, text: "第 10 天", style: legacy,
                                                     placement: .anchor(.bottomTrailing), font: beforeFont)?.cgImage)
            let after = try XCTUnwrap(renderer.bake(image: image, text: "第 10 天", style: decoded,
                                                    placement: .anchor(.bottomTrailing), font: afterFont)?.cgImage)
            XCTAssertEqual(before.width, after.width)
            XCTAssertEqual(before.height, after.height)
            XCTAssertEqual(try XCTUnwrap(before.dataProvider?.data) as Data,
                           try XCTUnwrap(after.dataProvider?.data) as Data, entry.fontID.rawValue)
        }
    }

    func testBuiltInWeightsResolveToExactPostScriptNames() {
        for (id, name) in [("light", "PingFangTC-Light"), ("regular", "PingFangTC-Regular"),
                           ("semibold", "PingFangTC-Semibold")] {
            let font = OverlayMetrics.resolvedFont(for: OverlayStyle(fontWeight: id), availability: Availability())
            XCTAssertEqual(font.postScriptName, name)
        }
    }

    func testNotoWeightsRenderExactRegisteredFacesAndSurviveProfileRoundTrip() throws {
        guard let path = ProcessInfo.processInfo.environment["DAYSCAM_FONT_FIXTURES"] else {
            throw XCTSkip("Set DAYSCAM_FONT_FIXTURES to the verified font fixture directory")
        }
        let entry = FontCatalog.entry(for: .notoSerifTC)
        var images: [String: Data] = [:]
        for weight in entry.weights {
            let asset = try XCTUnwrap(weight.openSource)
            let url = URL(fileURLWithPath: path).appendingPathComponent(asset.fileName)
            XCTAssertTrue(FontFileVerifier.isValid(fileAt: url, for: asset))
            XCTAssertTrue(CoreTextFontRegistrar().register(fontAt: url))
            defer { CoreTextFontRegistrar().unregister(fontAt: url) }
            var profile = CameraProfile(name: "字重", startDate: DateComponents(year: 2026, month: 1, day: 1))
            profile.style = OverlayStyle(fontID: .notoSerifTC, fontWeight: weight.id)
            let reopened = try JSONDecoder().decode(CameraProfile.self, from: JSONEncoder().encode(profile))
            XCTAssertEqual(reopened.style.fontWeight, weight.id)
            let resolved = OverlayMetrics.resolvedFont(for: reopened.style, availability: Availability())
            XCTAssertEqual(resolved.postScriptName, weight.postScriptName)
            XCTAssertEqual(resolved.font(ofSize: 24).fontName, weight.postScriptName)
            let rendered = try XCTUnwrap(OverlayRenderer().renderText("第 10 天", style: reopened.style,
                                                                      fontSize: 24, displayScale: 2, font: resolved))
            XCTAssertGreaterThan(rendered.image.size.width, 0)
            images[weight.id] = try XCTUnwrap(rendered.image.pngData())
        }
        XCTAssertNotEqual(images["regular"], images["bold"])
        XCTAssertNotEqual(images["bold"], images["black"])
    }

    func testLegacyAvailabilityDoesNotClaimOtherDownloadedFacesAreAvailable() {
        struct Legacy: FontAvailabilityProviding {
            func state(for fontID: OverlayFontID) -> FontState { .available }
        }
        let resolved = OverlayMetrics.resolvedFont(for: OverlayStyle(fontID: .notoSerifTC, fontWeight: "regular"),
                                                    availability: Legacy())
        XCTAssertEqual(resolved, .pingFang)
    }
}
