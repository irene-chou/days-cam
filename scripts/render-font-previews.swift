// Renders each 0.3 font's own name, in that real font, into a template image
// set under DaysCam/Assets.xcassets/FontPreviews (PRD 0.3 FR-16.4).
//
// Usage (macOS, from the repo root):
//   swift scripts/render-font-previews.swift <dir with the four open-source font files>
//
// The open-source files are the ones in irene-chou/dayscam-fonts@v2. Apple's
// downloadable fonts are matched (and downloaded if needed) through CoreText.
// The script exits non-zero if any font resolves to a PostScript name other
// than the one in PRD 0.3 §4.1, so a missing font can never fall back to
// PingFang silently (acceptance 31.2a / 31.2b).

import AppKit
import CoreText
import CryptoKit

struct Entry {
    let fontID: String
    let name: String
    let postScriptName: String
    let file: String?
    /// SHA-256 from docs/fonts-manifest.md, checked before drawing.
    var sha256: String? = nil
}

let entries: [Entry] = [
    Entry(fontID: "pingFang", name: "蘋方", postScriptName: "PingFangTC-Semibold", file: nil),
    Entry(fontID: "huninn", name: "粉圓", postScriptName: "jf-openhuninn-2.1", file: "jf-openhuninn-2.1.ttf",
          sha256: "9d5bf4932d31fe94c18cd8cfddc98bc1b14ce10f4e354c682179db290a99c825"),
    Entry(fontID: "notoSerifTC", name: "思源宋體", postScriptName: "NotoSerifTC-Bold", file: "NotoSerifTC-Bold.otf",
          sha256: "3ca2b3294ec84b795d0a45695e78e3612a44dce50f9fc776cd40206340a5768d"),
    Entry(fontID: "iansui", name: "芫荽", postScriptName: "Iansui-Regular", file: "Iansui-Regular.ttf",
          sha256: "7f1aa62e9dcbf40d0ce41a5d3f1e5ea602e66c295778ac6fefb6b84d8ed08bd5"),
    Entry(fontID: "chenyuluoyan", name: "辰宇落雁體", postScriptName: "ChenYuluoyan-2.0-Thin",
          file: "ChenYuluoyan-2.0-Thin.ttf",
          sha256: "1289e42a6d1ec995d0cb23aee89efc69fc95749fbd54a610057a3e992dc453db"),
    Entry(fontID: "lantinghei", name: "蘭亭黑", postScriptName: "FZLTZHB--B51-0", file: nil),
    Entry(fontID: "liHei", name: "儷黑", postScriptName: "LiHeiPro", file: nil),
    Entry(fontID: "hiraginoSans", name: "冬青黑體", postScriptName: "HiraginoSansTC-W6", file: nil),
    Entry(fontID: "yuanti", name: "圓體", postScriptName: "STYuanti-TC-Bold", file: nil),
    Entry(fontID: "songti", name: "宋體", postScriptName: "STSongti-TC-Bold", file: nil),
    Entry(fontID: "liSong", name: "儷宋", postScriptName: "LiSongPro", file: nil),
    Entry(fontID: "kaiti", name: "楷體", postScriptName: "STKaitiTC-Bold", file: nil),
    Entry(fontID: "biauKai", name: "標楷體", postScriptName: "BiauKaiTC-Regular", file: nil),
    Entry(fontID: "hanziPen", name: "翩翩體", postScriptName: "HanziPenTC-W5", file: nil),
    Entry(fontID: "hannotate", name: "手札體", postScriptName: "HannotateTC-W7", file: nil),
    Entry(fontID: "lingWai", name: "凌慧體", postScriptName: "MLingWaiMedium-TC", file: nil),
    Entry(fontID: "xingkai", name: "行楷", postScriptName: "STXingkaiTC-Bold", file: nil),
    Entry(fontID: "weibei", name: "魏碑", postScriptName: "WeibeiTC-Bold", file: nil),
    Entry(fontID: "libian", name: "隸變", postScriptName: "STLibianTC-Regular", file: nil),
    Entry(fontID: "baoli", name: "報隸", postScriptName: "STBaoliTC-Regular", file: nil),
    Entry(fontID: "wawa", name: "娃娃體", postScriptName: "DFWaWaTC-W5", file: nil),
    Entry(fontID: "yuppy", name: "雅痞", postScriptName: "YuppyTC-Regular", file: nil),
]

let pointSize: CGFloat = 17
let outputDir = URL(fileURLWithPath: "DaysCam/Assets.xcassets/FontPreviews")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: swift scripts/render-font-previews.swift <open-source font dir>")
}
let fontDir = URL(fileURLWithPath: CommandLine.arguments[1])

/// Returns the font to draw with. Open-source fonts are built straight from
/// the manifest file (hash-checked), so a same-named font installed on this
/// Mac can never be drawn instead; Apple fonts are matched through CoreText.
func resolve(_ entry: Entry) -> NSFont {
    if let file = entry.file {
        let url = fontDir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { fail("missing file \(url.path)") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == entry.sha256 else { fail("\(entry.fontID): \(file) SHA-256 \(digest) does not match the manifest") }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { fail("\(entry.fontID): cannot read \(file)") }
        return CTFontCreateWithFontDescriptor(descriptor, pointSize, nil) as NSFont
    }
    if NSFont(name: entry.postScriptName, size: pointSize) == nil {
        let done = DispatchSemaphore(value: 0)
        let descriptor = CTFontDescriptorCreateWithNameAndSize(entry.postScriptName as CFString, pointSize)
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler([descriptor] as CFArray, nil) { state, _ in
            if state == .didFinish { done.signal() }
            return true
        }
        if done.wait(timeout: .now() + 300) == .timedOut { fail("timed out matching \(entry.postScriptName)") }
    }
    guard let font = NSFont(name: entry.postScriptName, size: pointSize) else {
        fail("\(entry.fontID): font \(entry.postScriptName) is not available")
    }
    return font
}

func render(_ text: String, font: NSFont, scale: CGFloat) -> Data {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    let padding: CGFloat = 1
    let width = Int(ceil((size.width + padding * 2) * scale))
    let height = Int(ceil((size.height + padding * 2) * scale))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fail("cannot allocate bitmap for \(text)")
    }
    rep.size = NSSize(width: size.width + padding * 2, height: size.height + padding * 2)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    string.draw(at: NSPoint(x: padding, y: padding))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("cannot encode \(text)") }
    return png
}

let contentsJSON = """
{
  "images" : [
    { "filename" : "%@@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "%@@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}

"""

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
try! """
{
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: outputDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

for entry in entries {
    let font = resolve(entry)
    guard font.fontName == entry.postScriptName else {
        fail("\(entry.fontID): resolved to \(font.fontName), expected \(entry.postScriptName)")
    }
    let set = outputDir.appendingPathComponent("\(entry.fontID).imageset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for scale in [2, 3] {
        let data = render(entry.name, font: font, scale: CGFloat(scale))
        try! data.write(to: set.appendingPathComponent("\(entry.fontID)@\(scale)x.png"))
    }
    try! String(format: contentsJSON, entry.fontID, entry.fontID)
        .write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("\(entry.fontID) → \(font.fontName)")
}
