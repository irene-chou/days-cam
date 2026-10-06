import CoreText
import UIKit
import XCTest
@testable import DaysCam

/// Covers the TASK-05 metrics acceptance rows (5.6 ... 5.9).
///
/// These numbers are shared by the viewfinder and the baking path, so a change
/// here silently desyncs preview from print.
final class OverlayMetricsTests: XCTestCase {

    /// 5.6 — 3024 x 0.055
    func testBaseFontSizeIsFivePointFivePercentOfTheShortEdge() {
        XCTAssertEqual(OverlayMetrics.baseFontSize(forShortEdge: 3024), 166.32, accuracy: 0.01)
        XCTAssertEqual(OverlayMetrics.baseFontSize(forShortEdge: 1000), 55.0, accuracy: 0.01)
    }

    /// 5.7 — 3024 x 0.04
    func testMarginIsFourPercentOfTheShortEdge() {
        XCTAssertEqual(OverlayMetrics.margin(forShortEdge: 3024), 120.96, accuracy: 0.01)
        XCTAssertEqual(OverlayMetrics.margin(forShortEdge: 1000), 40.0, accuracy: 0.01)
    }

    /// The preview and the photo must agree, so the ratios have to be pure
    /// functions of the short edge rather than per-call-site constants.
    func testMetricsScaleProportionallyBetweenPreviewAndPhoto() {
        let preview = OverlayMetrics.baseFontSize(forShortEdge: 390)
        let photo = OverlayMetrics.baseFontSize(forShortEdge: 3024)
        XCTAssertEqual(photo / preview, 3024.0 / 390.0, accuracy: 0.0001)
    }

    // MARK: - Shrink to fit, measured with an injected ruler

    /// A ruler where every character is exactly one font size wide, so the
    /// expected numbers are arithmetic rather than font-dependent.
    private let oneUnitPerCharacter: (String, CGFloat) -> CGFloat = { text, size in
        CGFloat(text.count) * size
    }

    /// 5.9 — short text is not shrunk at all.
    func testShortTextKeepsTheBaseFontSizeExactly() {
        let fitted = OverlayMetrics.fittedFontSize(for: "第 1 天",
                                                   baseFontSize: 100,
                                                   availableWidth: 10_000,
                                                   measure: oneUnitPerCharacter)
        XCTAssertEqual(fitted, 100, accuracy: 0.0001)
    }

    /// 5.8 — long text shrinks, but never past 60% of the base size.
    func testOverlongTextShrinksWithinTheAllowedRange() {
        let base: CGFloat = 100
        let text = String(repeating: "天", count: 20)
        let fitted = OverlayMetrics.fittedFontSize(for: text,
                                                   baseFontSize: base,
                                                   availableWidth: 1500,
                                                   measure: oneUnitPerCharacter)
        XCTAssertLessThan(fitted, base)
        XCTAssertGreaterThanOrEqual(fitted, base * OverlayMetrics.minimumFontScale)
        // 20 characters must fit 1500pt, so the size is 75.
        XCTAssertEqual(fitted, 75, accuracy: 0.0001)
    }

    func testShrinkingStopsAtSixtyPercentEvenWhenTextStillOverflows() {
        let base: CGFloat = 100
        let text = String(repeating: "天", count: 200)
        let fitted = OverlayMetrics.fittedFontSize(for: text,
                                                   baseFontSize: base,
                                                   availableWidth: 1000,
                                                   measure: oneUnitPerCharacter)
        XCTAssertEqual(fitted, base * 0.6, accuracy: 0.0001,
                       "Below the floor the text is allowed to run into the margin instead")
    }

    func testTextExactlyFillingTheWidthIsNotShrunk() {
        let fitted = OverlayMetrics.fittedFontSize(for: "abcd",
                                                   baseFontSize: 100,
                                                   availableWidth: 400,
                                                   measure: oneUnitPerCharacter)
        XCTAssertEqual(fitted, 100, accuracy: 0.0001)
    }

    func testEmptyTextReturnsTheBaseFontSize() {
        let fitted = OverlayMetrics.fittedFontSize(for: "",
                                                   baseFontSize: 100,
                                                   availableWidth: 1,
                                                   measure: oneUnitPerCharacter)
        XCTAssertEqual(fitted, 100, accuracy: 0.0001)
    }

    // MARK: - Shrink to fit through the real font

    /// The convenience both `OverlayTextView` and `OverlayRenderer` call. 5.8
    /// and 5.9 again, this time measured with the font the text is drawn in.
    func testFittedFontSizeThroughTheRealFontObeysTheSameBounds() {
        let base = OverlayMetrics.baseFontSize(forShortEdge: 3024)

        let shortText = OverlayMetrics.fittedFontSize(for: "第 1 天",
                                                      font: .pingFang,
                                                      baseFontSize: base,
                                                      availableWidth: 3024)
        XCTAssertEqual(shortText, base, accuracy: 0.0001)

        let longText = OverlayMetrics.fittedFontSize(for: "小寶 2026.03.20　1 年 2 個月 5 天",
                                                     font: .pingFang,
                                                     baseFontSize: base,
                                                     availableWidth: 800)
        XCTAssertLessThan(longText, base)
        XCTAssertGreaterThanOrEqual(longText, base * OverlayMetrics.minimumFontScale)
    }

    func testPingFangMeasuresToARealWidth() {
        XCTAssertGreaterThan(OverlayMetrics.textWidth(of: "第 430 天", font: .pingFang, fontSize: 40), 0)
    }

    func testDecorationScaleTracksTheFontSize() {
        XCTAssertEqual(OverlayMetrics.decorationScale(forFontSize: OverlayMetrics.referenceFontSize), 1.0,
                       accuracy: 0.0001)
        XCTAssertEqual(OverlayMetrics.decorationScale(forFontSize: OverlayMetrics.referenceFontSize * 4), 4.0,
                       accuracy: 0.0001)
    }

    // MARK: - TASK-18: size scale, fonts, custom placement

    func testBaseFontSizeAppliesTheSizeScale() {
        XCTAssertEqual(OverlayMetrics.baseFontSize(forShortEdge: 3024, sizeScale: 160), 266.11, accuracy: 0.01, "18.5")
        XCTAssertEqual(OverlayMetrics.baseFontSize(forShortEdge: 3024, sizeScale: 100),
                       OverlayMetrics.baseFontSize(forShortEdge: 3024), accuracy: 0.0001)
    }

    /// 18.6: the shrink floor is 60% of the *scaled* base size.
    func testShrinkFloorIsSixtyPercentOfTheScaledSize() {
        let base = OverlayMetrics.baseFontSize(forShortEdge: 3024, sizeScale: 70)
        let fitted = OverlayMetrics.fittedFontSize(for: String(repeating: "第 10 天 ", count: 40),
                                                   font: .pingFang,
                                                   baseFontSize: base,
                                                   availableWidth: 3024 - 2 * OverlayMetrics.margin(forShortEdge: 3024))
        XCTAssertGreaterThanOrEqual(fitted, 69.85, "18.6")
        XCTAssertEqual(fitted, 3024 * 0.055 * 0.7 * 0.6, accuracy: 0.01, "18.6: overlong text sits on the floor")
    }

    @MainActor
    func testEveryFontIDResolvesAtTheRequestedSize() {
        for fontID in OverlayFontID.allCases {
            let font = OverlayMetrics.font(for: fontID, size: 40, availability: FontAvailabilitySpy())
            XCTAssertEqual(font.pointSize, 40, accuracy: 0.0001, "\(fontID)")
        }
    }

    func testCustomPlacementCentersTheBlockOnThePoint() {
        let origin = OverlayMetrics.origin(forBlockSize: CGSize(width: 200, height: 50),
                                           in: CGSize(width: 1000, height: 2000),
                                           placement: .custom(x: 0.5, y: 0.25))
        XCTAssertEqual(origin.x, 400, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 475, accuracy: 0.0001)
    }

    func testCustomPlacementClampsTheWholeBlockIntoTheMargin() {
        let frame = CGSize(width: 1000, height: 2000)
        let block = CGSize(width: 200, height: 50)
        let margin = OverlayMetrics.margin(forShortEdge: 1000)
        let farCorner = OverlayMetrics.origin(forBlockSize: block, in: frame, placement: .custom(x: 1, y: 1))
        XCTAssertEqual(farCorner.x, 1000 - margin - 200, accuracy: 0.0001)
        XCTAssertEqual(farCorner.y, 2000 - margin - 50, accuracy: 0.0001)
        let nearCorner = OverlayMetrics.origin(forBlockSize: block, in: frame, placement: .custom(x: 0, y: 0))
        XCTAssertEqual(nearCorner.x, margin, accuracy: 0.0001)
        XCTAssertEqual(nearCorner.y, margin, accuracy: 0.0001)
    }

    /// FR-12.6: the same fractions land in the same relative spot at any size.
    func testCustomPlacementIsResolutionIndependent() {
        let placement = OverlayPlacement.custom(x: 0.3, y: 0.6)
        let small = OverlayMetrics.origin(forBlockSize: CGSize(width: 40, height: 10),
                                          in: CGSize(width: 400, height: 300), placement: placement)
        let large = OverlayMetrics.origin(forBlockSize: CGSize(width: 400, height: 100),
                                          in: CGSize(width: 4000, height: 3000), placement: placement)
        XCTAssertEqual(large.x, small.x * 10, accuracy: 0.001)
        XCTAssertEqual(large.y, small.y * 10, accuracy: 0.001)
    }

    func testBlockWiderThanTheMarginsIsCenteredOnThatAxis() {
        let origin = OverlayMetrics.origin(forBlockSize: CGSize(width: 980, height: 50),
                                           in: CGSize(width: 1000, height: 2000),
                                           placement: .custom(x: 0.9, y: 0.5))
        XCTAssertEqual(origin.x, 10, accuracy: 0.0001)
    }

    func testAnchorPlacementMatchesTheNineGridRule() {
        let frame = CGSize(width: 1000, height: 2000)
        let block = CGSize(width: 200, height: 50)
        let margin = OverlayMetrics.margin(forShortEdge: 1000)
        let bottomTrailing = OverlayMetrics.origin(forBlockSize: block, in: frame, placement: .anchor(.bottomTrailing))
        XCTAssertEqual(bottomTrailing, CGPoint(x: 1000 - margin - 200, y: 2000 - margin - 50))
        let center = OverlayMetrics.origin(forBlockSize: block, in: frame, placement: .anchor(.middleCenter))
        XCTAssertEqual(center, CGPoint(x: 400, y: 975))
    }
}

// MARK: - Font resolution (TASK-32 32.5 ... 32.8, PRD 0.3 FR-5.14)

/// Availability that answers from a table and records every question.
@MainActor
final class FontAvailabilitySpy: FontAvailabilityProviding {
    var states: [OverlayFontID: FontState]
    private(set) var asked: [OverlayFontID] = []

    init(_ states: [OverlayFontID: FontState] = [:]) {
        self.states = states
    }

    func state(for fontID: OverlayFontID) -> FontState {
        asked.append(fontID)
        return states[fontID] ?? .notDownloaded
    }
}

/// Covers TASK-32 32.5 ... 32.8: `available` resolves to the font itself,
/// anything else to PingFang, and PingFang needs no availability at all.
///
/// The 20 downloadable fonts are not on a test simulator, so where a font
/// must really load, a face that ships with iOS stands in for it through
/// `resolvedFont(state:postScriptName:)` — the rule
/// `resolvedFont(for:availability:)` applies after looking the name up in
/// `FontCatalog`.
@MainActor
final class OverlayFontResolutionTests: XCTestCase {
    /// A face that ships with iOS, standing in for a downloaded font.
    private let standIn = "Georgia-Bold"
    private let notAvailable: [FontState] = [.notDownloaded, .preparing, .downloading(progress: 0.4),
                                              .failed(.noNetwork), .failed(.other)]

    /// 32.8: PingFang is PingFangTC-Semibold and never asks availability.
    func testPingFangResolvesWithoutAskingAvailability() {
        let spy = FontAvailabilitySpy([.pingFang: .failed(.other)])
        let resolved = OverlayMetrics.resolvedFont(for: .pingFang, availability: spy)
        XCTAssertEqual(resolved, .pingFang, "32.8")
        XCTAssertEqual(resolved.font(ofSize: 20).fontName, "PingFangTC-Semibold", "32.8")
        XCTAssertEqual(ResolvedOverlayFont.pingFang.font(ofSize: 20).fontName, "PingFangTC-Semibold", "32.8")
        XCTAssertEqual(OverlayMetrics.font(for: .pingFang, size: 20, availability: spy).fontName,
                       "PingFangTC-Semibold", "32.8")
        XCTAssertTrue(spy.asked.isEmpty, "32.8: PingFang must not depend on availability")
    }

    /// 32.5: an `available` font resolves to its own PostScript name.
    func testAvailableFontResolvesToItself() {
        let resolved = OverlayMetrics.resolvedFont(state: .available, postScriptName: standIn)
        XCTAssertEqual(resolved.postScriptName, standIn, "32.5")
        XCTAssertEqual(resolved.font(ofSize: 30).fontName, standIn, "32.5")
        XCTAssertEqual(resolved.font(ofSize: 30).pointSize, 30, accuracy: 0.0001)
    }

    /// 32.5 with the real files: set `DAYSCAM_FONT_FIXTURES` (pass it as
    /// `TEST_RUNNER_DAYSCAM_FONT_FIXTURES`) to a folder holding the three
    /// open-source font files from `irene-chou/dayscam-fonts@v1`. Each is
    /// registered for this process only and resolved through `FontCatalog`.
    /// Skipped without the variable: the files are not in the repo.
    func testRegisteredOpenSourceFontsResolveThroughTheCatalog() throws {
        guard let path = ProcessInfo.processInfo.environment["DAYSCAM_FONT_FIXTURES"] else {
            throw XCTSkip("DAYSCAM_FONT_FIXTURES not set; the open-source font files are not in the repo")
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        for entry in FontCatalog.entries {
            guard let asset = entry.openSource else { continue }
            let url = folder.appendingPathComponent(asset.fileName)
            var error: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            XCTAssertTrue(registered, "32.5: could not register \(asset.fileName): \(String(describing: error))")
            defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }

            let spy = FontAvailabilitySpy([entry.fontID: .available])
            let font = OverlayMetrics.font(for: entry.fontID, size: 24, availability: spy)
            XCTAssertEqual(font.fontName, entry.postScriptName, "32.5 \(entry.fontID)")
            XCTAssertEqual(spy.asked, [entry.fontID])
        }
    }

    /// 32.6: every other state resolves to PingFang, for every catalog font
    /// and for a face that would load.
    func testEveryStateButAvailableResolvesToPingFang() {
        for state in notAvailable {
            XCTAssertEqual(OverlayMetrics.resolvedFont(state: state, postScriptName: standIn), .pingFang,
                           "32.6 \(state)")
            for fontID in OverlayFontID.allCases where fontID != .pingFang {
                let spy = FontAvailabilitySpy([fontID: state])
                XCTAssertEqual(OverlayMetrics.font(for: fontID, size: 20, availability: spy).fontName,
                               "PingFangTC-Semibold", "32.6 \(fontID) \(state)")
                XCTAssertEqual(spy.asked, [fontID], "32.6: asks about the style's own font, once")
            }
        }
    }

    /// 32.7a: reported `failed` although iOS can already load the face — a
    /// match that completed after its timeout. Still PingFang.
    func testFailedFontThatWouldLoadStillResolvesToPingFang() {
        XCTAssertNotNil(UIFont(name: standIn, size: 20), "fixture sanity: the face does load")
        XCTAssertEqual(OverlayMetrics.resolvedFont(state: .failed(.other), postScriptName: standIn), .pingFang,
                       "32.7a")
    }

    /// Reported `available` but the face does not load (dropped by iOS, say):
    /// PingFang, never some other face.
    func testAvailableButUnloadableResolvesToPingFang() {
        XCTAssertEqual(OverlayMetrics.resolvedFont(state: .available, postScriptName: "NoSuchFont-Bold"), .pingFang)
    }
}
