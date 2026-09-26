import CoreText
import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// Research probes for Issue #73 (Traditional Chinese font sources); the
/// findings live in `docs/research/fonts-tc.md`.
///
/// Not part of the regular suite: every test skips unless the test process
/// sees `DAYSCAM_FONT_RESEARCH=1`. They need the network (Apple's font
/// catalog) and font files that are deliberately not in the repo. Pass the
/// variables with the `TEST_RUNNER_` prefix, which `xcodebuild` strips:
///
///     TEST_RUNNER_DAYSCAM_FONT_RESEARCH=1 \
///     TEST_RUNNER_DAYSCAM_FONT_RESEARCH_FONTS=/path/to/fonts \
///     TEST_RUNNER_DAYSCAM_FONT_RESEARCH_OUT=/path/to/output \
///     xcodebuild ... test -only-testing:DaysCamTests/FontsTCResearchTests
///
/// Results are printed as `RESEARCH|...` lines; baked images go to the
/// output directory. Nothing here touches the App target.
final class FontsTCResearchTests: XCTestCase {

    /// iOS downloadable fonts with Traditional Chinese glyphs, by PostScript
    /// name. Names come from `test_A1_listDownloadableChineseFonts`.
    static let downloadableCandidates: [String] = {
        let environment = ProcessInfo.processInfo.environment
        if let list = environment["DAYSCAM_FONT_RESEARCH_NAMES"], !list.isEmpty {
            return list.split(separator: ",").map(String.init)
        }
        return []
    }()

    /// Text exercising every character the overlay itself can print, plus a
    /// few common name characters.
    static let sampleText = "第 128 天\u{3000}2026.09.27 小明 1 歲又 3 個月 2 週"

    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        try XCTSkipUnless(environment["DAYSCAM_FONT_RESEARCH"] == "1",
                          "Research probe for Issue #73; set DAYSCAM_FONT_RESEARCH=1 to run")
    }

    // MARK: - A. System downloadable fonts

    /// Lists every downloadable font in Apple's catalog whose language list
    /// includes Traditional Chinese.
    func test_A1_listDownloadableChineseFonts() throws {
        let query = CTFontDescriptorCreateWithAttributes([kCTFontDownloadableAttribute: true] as CFDictionary)
        let matches = CTFontDescriptorCreateMatchingFontDescriptors(query, nil) as? [CTFontDescriptor] ?? []
        report("A1", "catalogCount=\(matches.count)")
        for descriptor in matches {
            let name = attribute(descriptor, kCTFontNameAttribute) ?? "?"
            let family = attribute(descriptor, kCTFontFamilyNameAttribute) ?? "?"
            let display = attribute(descriptor, kCTFontDisplayNameAttribute) ?? "?"
            let languages = CTFontDescriptorCopyAttribute(descriptor, kCTFontLanguagesAttribute) as? [String] ?? []
            let chinese = languages.filter { $0.hasPrefix("zh") }
            // The catalog's language lists come back empty on the simulator, so
            // also keep anything whose display name contains a Han character.
            let hasHanName = display.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            guard !chinese.isEmpty || hasHanName else { continue }
            let installed = UIFont(name: name, size: 17) != nil
            report("A1", "name=\(name)|family=\(family)|display=\(display)|languages=\(chinese.joined(separator: " "))|loadedInProcess=\(installed)")
        }
    }

    /// Downloads each candidate and reports size, time and outcome.
    func test_A2_downloadCandidates() throws {
        XCTAssertFalse(Self.downloadableCandidates.isEmpty, "set DAYSCAM_FONT_RESEARCH_NAMES")
        for name in Self.downloadableCandidates {
            let before = UIFont(name: name, size: 17) != nil
            let result = match(postScriptName: name)
            let after = UIFont(name: name, size: 17) != nil
            report("A2", "name=\(name)|availableBefore=\(before)|\(result)|availableAfter=\(after)|\(fileAndCoverage(of: name))")
        }
    }

    /// Run in a fresh process after `test_A2`: is a downloaded font usable
    /// straight away, and does matching it again download anything?
    func test_A3_afterRelaunch() throws {
        XCTAssertFalse(Self.downloadableCandidates.isEmpty, "set DAYSCAM_FONT_RESEARCH_NAMES")
        for name in Self.downloadableCandidates {
            let before = UIFont(name: name, size: 17) != nil
            let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, 0)
            let matched = CTFontDescriptorCreateMatchingFontDescriptor(descriptor, nil)
            let matchedName = matched.flatMap { attribute($0, kCTFontNameAttribute) } ?? "nil"
            let result = match(postScriptName: name)
            let after = UIFont(name: name, size: 17) != nil
            report("A3", "name=\(name)|uiFontBeforeMatching=\(before)|plainMatch=\(matchedName)|\(result)|uiFontAfterMatching=\(after)")
        }
    }

    // MARK: - B. Bundled open-source fonts

    /// Registers each font file for this process and reports its names.
    func test_B1_registerBundledCandidates() throws {
        for (file, name) in try registerBundledFonts() {
            let font = UIFont(name: name, size: 17)
            report("B1", "file=\(file)|postScriptName=\(name)|loadable=\(font != nil)|family=\(font?.familyName ?? "nil")")
        }
    }

    // MARK: - C. Baking

    /// Bakes `sampleText` with each font the way `OverlayRenderer` draws text
    /// and reports which font CoreText actually used for every run.
    ///
    /// `OverlayRenderer.bake` only accepts an `OverlayFontID`, which has no
    /// Chinese font yet, so the fonts under test cannot be passed to it without
    /// changing product code. This test draws with the same primitive the
    /// renderer uses (`NSString.draw(at:withAttributes:)` with `.font`) at the
    /// same size `OverlayMetrics` gives a 1200 x 1600 photo. The last case
    /// runs the real renderer with Futura as the baseline.
    @MainActor
    func test_C1_bakeAndIdentifyUsedFonts() throws {
        let bundled = try registerBundledFonts().map(\.postScriptName)
        for name in Self.downloadableCandidates {
            _ = match(postScriptName: name)
        }
        let names = (environment["DAYSCAM_FONT_RESEARCH_BAKE"] ?? "")
            .split(separator: ",").map(String.init)
        let fontSize = OverlayMetrics.baseFontSize(forShortEdge: 1200)
        let pingFangStrip = bake(font: pingFang(size: fontSize))
        let pingFangWidth = inkWidth(of: pingFangStrip)
        var sheet: [UIImage] = [pingFangStrip]

        for name in names {
            guard let font = UIFont(name: name, size: fontSize) else {
                report("C1", "name=\(name)|loadable=false|bundled=\(bundled.contains(name))")
                continue
            }
            let image = bake(font: font)
            save(image, as: "C1-\(name).png")
            sheet.append(image)
            let runs = usedFonts(for: Self.sampleText, font: font)
            let preview = previewImage(font: font)
            save(preview, as: "C1-\(name)-preview.png")
            let bakedWidth = inkWidth(of: image)
            let previewWidth = inkWidth(of: preview)
            report("C1", "name=\(name)|runs=\(runs)|bakedInkWidth=\(bakedWidth)|previewInkWidth=\(previewWidth)|pingFangInkWidth=\(pingFangWidth)")
            XCTAssertEqual(Set(runs.map(\.font)), [name], "\(name) should draw every character itself")
        }

        save(stacked(sheet), as: "C1-sheet.png")

        // Baseline: today's renderer with a Latin-only font.
        let baseline = try XCTUnwrap(OverlayRenderer().bake(image: blankPhoto(),
                                                            text: Self.sampleText,
                                                            style: OverlayStyle(fontID: .futura, shadow: .none),
                                                            placement: .anchor(.bottomTrailing)))
        save(baseline, as: "C1-baseline-futura.png")
        let futura = OverlayMetrics.font(for: .futura, size: fontSize)
        report("C1", "name=baseline-OverlayRenderer-futura|runs=\(usedFonts(for: Self.sampleText, font: futura))")
    }

    // MARK: - Helpers

    private func report(_ section: String, _ line: String) {
        print("RESEARCH|\(section)|\(line)")
    }

    private func attribute(_ descriptor: CTFontDescriptor, _ key: CFString) -> String? {
        CTFontDescriptorCopyAttribute(descriptor, key) as? String
    }

    /// Runs `CTFontDescriptorMatchFontDescriptorsWithProgressHandler` for one
    /// PostScript name and summarises what happened.
    private func match(postScriptName name: String) -> String {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: name] as CFDictionary)
        let done = expectation(description: "match \(name)")
        let start = Date()
        var states: [String] = []
        var totalSize: Int64 = 0
        var errorText = "none"
        var matchedName = "nil"
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler([descriptor] as CFArray, nil) { state, parameters in
            let info = parameters as NSDictionary
            if let size = info[kCTFontDescriptorMatchingTotalAssetSize] as? NSNumber {
                totalSize = max(totalSize, size.int64Value)
            }
            switch state {
            case .didBegin: states.append("didBegin")
            case .willBeginDownloading: states.append("willBeginDownloading")
            case .downloading: if states.last != "downloading" { states.append("downloading") }
            case .didFinishDownloading: states.append("didFinishDownloading")
            case .didMatch:
                states.append("didMatch")
                if let result = info[kCTFontDescriptorMatchingResult] as? [CTFontDescriptor],
                   let first = result.first {
                    matchedName = self.attribute(first, kCTFontNameAttribute) ?? "?"
                }
            case .didFailWithError:
                states.append("didFail")
                if let error = info[kCTFontDescriptorMatchingError] as? NSError {
                    errorText = "\(error.domain)#\(error.code)"
                }
            case .didFinish:
                states.append("didFinish")
                done.fulfill()
            default:
                states.append("state\(state.rawValue)")
            }
            return true
        }
        wait(for: [done], timeout: 600)
        let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
        return "states=\(states.joined(separator: ">"))|totalAssetBytes=\(totalSize)|seconds=\(seconds)|matched=\(matchedName)|error=\(errorText)"
    }

    /// The installed file's size and how many of the 4808 standard characters
    /// (file at `DAYSCAM_FONT_RESEARCH_CHARS`, one per line) the font maps.
    private func fileAndCoverage(of name: String) -> String {
        let font = CTFontCreateWithName(name as CFString, 17, nil)
        guard CTFontCopyPostScriptName(font) as String == name else { return "file=notLoaded" }
        let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL
        let bytes = url.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int } ?? -1
        var coverage = "coverage=skipped"
        if let path = environment["DAYSCAM_FONT_RESEARCH_CHARS"],
           let list = try? String(contentsOfFile: path, encoding: .utf8) {
            let characters = list.split(whereSeparator: \.isNewline).compactMap { $0.first }
            var missing: [Character] = []
            for character in characters {
                var utf16 = Array(String(character).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
                if !CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count) { missing.append(character) }
            }
            coverage = "coverage=\(characters.count - missing.count)/\(characters.count)|missing=\(String(missing.prefix(30)))"
        }
        return "fileBytes=\(bytes)|file=\(url?.lastPathComponent ?? "nil")|\(coverage)"
    }

    /// Registers every font file in `DAYSCAM_FONT_RESEARCH_FONTS` for this
    /// process only and returns (file name, PostScript name) pairs.
    private func registerBundledFonts() throws -> [(file: String, postScriptName: String)] {
        guard let path = environment["DAYSCAM_FONT_RESEARCH_FONTS"] else { return [] }
        let directory = URL(fileURLWithPath: path)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.compactMap { url in
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let first = descriptors.first,
                  let name = attribute(first, kCTFontNameAttribute) else { return nil }
            if UIFont(name: name, size: 17) == nil {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            }
            return (url.lastPathComponent, name)
        }
    }

    /// The font CoreText picks for each run of `text` drawn in `font`.
    private func usedFonts(for text: String, font: UIFont) -> [(text: String, font: String)] {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let string = text as NSString
        return runs.map { run in
            let range = CTRunGetStringRange(run)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            // CTFont is toll-free bridged to UIFont.
            let postScriptName = (attributes[kCTFontAttributeName] as? UIFont)?.fontName ?? "?"
            return (string.substring(with: NSRange(location: range.location, length: range.length)), postScriptName)
        }
    }

    private func pingFang(size: CGFloat) -> UIFont {
        UIFont(name: "PingFangTC-Semibold", size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
    }

    private func blankPhoto() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600), format: format).image { context in
            UIColor(white: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
        }
    }

    /// Draws `sampleText` in `font` onto a dark strip just wide enough, with the
    /// call `OverlayRenderer` uses for the text fill.
    private func bake(font: UIFont) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let textWidth = (Self.sampleText as NSString).size(withAttributes: [.font: font]).width
        let size = CGSize(width: ceil(textWidth) + 40, height: ceil(font.lineHeight * 1.6))
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            (Self.sampleText as NSString).draw(at: CGPoint(x: 20, y: font.lineHeight * 0.3),
                                               withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
    }

    /// The viewfinder's way of drawing: SwiftUI `Text` with `Font(uiFont)`,
    /// as `OverlayTextView` does.
    @MainActor
    private func previewImage(font: UIFont) -> UIImage {
        let content = Text(Self.sampleText)
            .font(Font(font))
            .foregroundColor(.white)
            .fixedSize()
            .padding(20)
            .background(Color.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.uiImage ?? UIImage()
    }

    /// `images` one below the other, left-aligned, for a single overview.
    private func stacked(_ images: [UIImage]) -> UIImage {
        let width = images.map(\.size.width).max() ?? 1
        let height = images.map(\.size.height).reduce(0, +)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: max(height, 1)), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var y: CGFloat = 0
            for image in images {
                image.draw(at: CGPoint(x: 0, y: y))
                y += image.size.height
            }
        }
    }

    /// Width of the bounding box of all bright pixels, a font-dependent
    /// fingerprint that is independent of the canvas.
    private func inkWidth(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return -1 }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width
        var maxX = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4] > 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        return maxX >= minX ? maxX - minX + 1 : 0
    }

    private func save(_ image: UIImage, as fileName: String) {
        guard let path = environment["DAYSCAM_FONT_RESEARCH_OUT"], let data = image.pngData() else { return }
        let directory = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(fileName))
    }
}
