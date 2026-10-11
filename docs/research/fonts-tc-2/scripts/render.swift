// Render a font comparison sheet with CoreText and report which font draws each glyph run.
// Usage: swift render.swift <list.tsv> <out.png> <report.tsv> [title]
// list.tsv columns: category, label, fontPath, postScriptName
import AppKit
import CoreText
import Foundation

let args = CommandLine.arguments
guard args.count >= 4 else { fatalError("usage: render.swift list.tsv out.png report.tsv [title]") }
let rows: [[String]] = (try? String(contentsOfFile: args[1], encoding: .utf8))?
    .split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    .filter { $0.count >= 4 } ?? []
let title = args.count > 4 ? args[4] : "DaysCam 字型比較稿"

let sample = "2026.10.11 我的紀錄 第 128 天"
let overlay = "1 歲又 3 個月 2 週　尚未開始"
let glyphCheck = "戶骨說溫黃真直角次吳"
let width: CGFloat = 2200
let rowHeight: CGFloat = 150
let headerHeight: CGFloat = 70
let titleHeight: CGFloat = 90

var registered = Set<String>()
func register(_ path: String) {
    guard !registered.contains(path) else { return }
    var error: Unmanaged<CFError>?
    if !CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, &error) {
        FileHandle.standardError.write("register failed \(path): \(String(describing: error?.takeRetainedValue()))\n".data(using: .utf8)!)
    }
    registered.insert(path)
}

func line(_ text: String, font: CTFont) -> CTLine {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black.cgColor]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
}

func runFonts(_ line: CTLine) -> [String] {
    let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
    return runs.map { run in
        let attrs = CTRunGetAttributes(run) as NSDictionary
        let font = attrs[kCTFontAttributeName as String] as! CTFont // swiftlint:disable:this force_cast
        return CTFontCopyPostScriptName(font) as String
    }
}

var categories: [String] = []
for row in rows where !categories.contains(row[0]) { categories.append(row[0]) }
let height = titleHeight + CGFloat(categories.count) * headerHeight + CGFloat(rows.count) * rowHeight + 40

let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, // swiftlint:disable:this force_unwrapping
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)! // swiftlint:disable:this force_unwrapping
var report = "category\tlabel\tpostScript\tresolved\tsampleRuns\toverlayRuns\tglyphRuns\tfallback\n"
ctx.setFillColor(NSColor.white.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
ctx.textMatrix = .identity

let labelFont = CTFontCreateWithName("PingFangTC-Semibold" as CFString, 30, nil)
let headerFont = CTFontCreateWithName("PingFangTC-Semibold" as CFString, 40, nil)
let smallFont = CTFontCreateWithName("PingFangTC-Regular" as CFString, 20, nil)

func draw(_ l: CTLine, x: CGFloat, yTop: CGFloat, ascent: CGFloat) {
    ctx.textPosition = CGPoint(x: x, y: height - yTop - ascent)
    CTLineDraw(l, ctx)
}

var y: CGFloat = 20
draw(line(title + "（每套用最粗字重；右欄為字形檢查字）", font: headerFont), x: 30, yTop: y, ascent: 44)
y = titleHeight
for category in categories {
    ctx.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: height - y - headerHeight + 8, width: width, height: headerHeight - 16))
    draw(line(category, font: headerFont), x: 30, yTop: y + 12, ascent: 42)
    y += headerHeight
    for row in rows where row[0] == category {
        register(row[2])
        let font = CTFontCreateWithName(row[3] as CFString, 64, nil)
        let resolved = CTFontCopyPostScriptName(font) as String
        let sampleLine = line(sample, font: font)
        let overlayLine = line(overlay, font: CTFontCreateWithName(row[3] as CFString, 30, nil))
        let glyphLine = line(glyphCheck, font: CTFontCreateWithName(row[3] as CFString, 48, nil))
        draw(line(row[1], font: labelFont), x: 30, yTop: y + 20, ascent: 32)
        draw(line(row[3], font: smallFont), x: 30, yTop: y + 70, ascent: 22)
        draw(sampleLine, x: 480, yTop: y + 6, ascent: 70)
        draw(overlayLine, x: 480, yTop: y + 92, ascent: 32)
        draw(glyphLine, x: 1620, yTop: y + 30, ascent: 52)
        let s = runFonts(sampleLine), o = runFonts(overlayLine), g = runFonts(glyphLine)
        let fallback = (s + o + g).contains { $0 != row[3] }
        report += "\(row[0])\t\(row[1])\t\(row[3])\t\(resolved)\t\(s.joined(separator: ","))\t\(o.joined(separator: ","))\t\(g.joined(separator: ","))\t\(fallback ? "FALLBACK" : "ok")\n"
        ctx.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 30, y: height - y - rowHeight, width: width - 60, height: 1))
        y += rowHeight
    }
}
guard let cgImage = ctx.makeImage(), case let rep = NSBitmapImageRep(cgImage: cgImage),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode failed") }
try png.write(to: URL(fileURLWithPath: args[2]))
try report.write(toFile: args[3], atomically: true, encoding: .utf8)
print(report)
