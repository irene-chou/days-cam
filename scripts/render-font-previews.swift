// Renders each 0.3 font's short Chinese name (`displayName`, TASK-148), in that
// real font, into a template image set under DaysCam/Assets.xcassets/FontPreviews (PRD 0.3 FR-16.4).
//
// Usage (macOS, from the repo root):
//   swift scripts/render-font-previews.swift <dir with the open-source font files> [fontID ...]
//
// The open-source files are the default faces in irene-chou/dayscam-fonts@v4
// (the four fonts of v2 and the 30 families of TASK-142), all in one folder. Apple's
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
    Entry(fontID: "notoSansTC", name: "思源黑體", postScriptName: "NotoSansTC-Bold", file: "NotoSansTC-Bold.otf",
          sha256: "55420b259eb119bf5f2a0aadba10cf9d736c12d64ab93e78546d69ef5f43558b"),
    Entry(fontID: "taipeiSans", name: "台北黑體", postScriptName: "TaipeiSansTCBeta-Bold", file: "TaipeiSansTCBeta-Bold.ttf",
          sha256: "5249d3bdda9c9f4c62840e804b4d2530b7f4dfab6d68fb508c120b0e7e600419"),
    Entry(fontID: "genSeki", name: "源石黑體", postScriptName: "GenSekiGothic2TW-B", file: "GenSekiGothic2TW-B.otf",
          sha256: "911bc231c346f1e377796ccd1b85959184a547d1fce356da882a2f1abb9bfaa4"),
    Entry(fontID: "chironHei", name: "昭源黑體", postScriptName: "ChironHeiHK-Bold", file: "ChironHeiHK-B.otf",
          sha256: "51a6c39f8dd0a4522a7c5d366d77e9e52aebe4280d9b16ed95f03288c802e821"),
    Entry(fontID: "chocolateSans", name: "朱古力黑體", postScriptName: "ChocolateClassicalSans-Regular", file: "ChocolateClassicalSans-Regular.ttf",
          sha256: "e6345f3d92c7a9b7044c31a87d9b61f50220b08c0f1dcc2736e94c2aa587ce03"),
    Entry(fontID: "glowSans", name: "未來熒黑", postScriptName: "GlowSansTC-Normal-Bold", file: "GlowSansTC-Normal-Bold.otf",
          sha256: "8005c40f3777c540ec10ed352793f2a53363a13ec41bc0eeaf18d28e9c8c4312"),
    Entry(fontID: "genSen", name: "源泉圓體", postScriptName: "GenSenRounded2TW-B", file: "GenSenRounded2TW-B.otf",
          sha256: "050f9ebf394faab3c0ba59092ae3e4b6686b349eadb3018d76d385c5829a1267"),
    Entry(fontID: "sweiGothic", name: "獅尾圓體", postScriptName: "SweiGothicCJKtc-Bold", file: "SweiGothicCJKtc-Bold.ttf",
          sha256: "d3f03ebd366966c1967879d1b5760e96784e9f7b9bac6e4b5dd364db00a9c128"),
    Entry(fontID: "chironGoRound", name: "昭源環方", postScriptName: "ChironGoRoundTC-Bold", file: "ChironGoRoundTC-700B.otf",
          sha256: "5ed043b3d1048e4d7868909c6d6fbba2d0cb50773d394003f4fb077a18e2b3fb"),
    Entry(fontID: "genWan", name: "源雲明體", postScriptName: "GenWanMin2TW-SB", file: "GenWanMin2TW-SB.otf",
          sha256: "86cc4abaec4151b5ad9ac6d39f635c974a2dc4155fe041e6a4fa9730114487d1"),
    Entry(fontID: "genRyu", name: "源流明體", postScriptName: "GenRyuMin2TW-B", file: "GenRyuMin2TW-B.otf",
          sha256: "5e7d2c11cf9860c94ac7d1fba742329f6015f7042c736232e1e69eb8ab12d5da"),
    Entry(fontID: "sweiSpring", name: "獅尾四季春", postScriptName: "SweiSpringCJKtc-Bold", file: "SweiSpringCJKtc-Bold.ttf",
          sha256: "2bf4d16b849c4a87242c3f38817f18d45cf2a04d244fc3420dd5771d78b078fb"),
    Entry(fontID: "sweiSugar", name: "獅尾加糖宋體", postScriptName: "SweiSugarCJKtc-Bold", file: "SweiSugarCJKtc-Bold.ttf",
          sha256: "c71c1d5196e49211c5232df39210df2c6fbea0b60245cb8ef9fc7edd37a1a30c"),
    Entry(fontID: "chironSung", name: "昭源宋體", postScriptName: "ChironSungHK-Bold", file: "ChironSungHK-B.otf",
          sha256: "bc3f911227c98ae45caf31147201c29dd3cf14fc2c84af72936f4ef6067b397d"),
    Entry(fontID: "cactusSerif", name: "仙人掌明體", postScriptName: "CactusClassicalSerif-Regular", file: "CactusClassicalSerif-Regular.ttf",
          sha256: "ecbd58961db922392d7fecfafa3681fefaeec0c399b860ab6940ba700f7da055"),
    Entry(fontID: "twSung", name: "全字庫正宋體", postScriptName: "TW-Sung-98_1", file: "TW-Sung-98_1.ttf",
          sha256: "9a3b74fe1a69fe1b3470b5ed780bf678c42a25cef93a13f280a5f31f795f0c56"),
    Entry(fontID: "thenKhung", name: "宇文天穹", postScriptName: "UoqMunThenKhung-Regular", file: "UoqMunThenKhung-Regular.ttf",
          sha256: "943a23eb10d40ca85ee08491c0e3fb3adbc4bd111ef1f93526a4f766a8e66fbd"),
    Entry(fontID: "lxgwWenKai", name: "霞鶩文楷 TC", postScriptName: "LXGWWenKaiTC-Medium", file: "LXGWWenKaiTC-Medium.ttf",
          sha256: "94ca2870022fb8e4f90e2887524603690598142d17b620dfae318f1818ba8e17"),
    Entry(fontID: "twKai", name: "全字庫正楷體", postScriptName: "TW-Kai-98_1", file: "TW-Kai-98_1.ttf",
          sha256: "d5e8d7d8743c5cf816bdeb393a443f65105a8130266a04c19560e1d3401b28f0"),
    Entry(fontID: "eduKai", name: "教育部標準楷書", postScriptName: "TW-MOE-Std-Kai", file: "edukai-5.0.ttf",
          sha256: "99ae11cc1ba0ee14d43da5336f2c555b17a3bf551f7203f42da4f7fbdfcf7b7b"),
    Entry(fontID: "arphicUKai", name: "文鼎 PL 中楷", postScriptName: "UKaiTW", file: "ukai.ttc",
          sha256: "cfc758e69386a21bade8cb3b373fda20d7f2fac6e8904ced2ded98588b63e274"),
    Entry(fontID: "naikai", name: "內海字體", postScriptName: "NaikaiFont-Bold", file: "NaikaiFont-Bold.ttf",
          sha256: "43a3822eedd0d7d5fe464fc462c799f5ff2de8eaeabc0825ba09607b1035b621"),
    Entry(fontID: "xiaolai", name: "小賴字體", postScriptName: "Xiaolai", file: "Xiaolai-Regular.ttf",
          sha256: "e2f68daf0e72777a8cf58bc83de1b98634b251e537ddbfca24b0ae50d1802da2"),
    Entry(fontID: "yozai", name: "悠哉字體", postScriptName: "Yozai-Medium", file: "Yozai-Medium.ttf",
          sha256: "05f50f252b45197d0d6148a4abc3e37c7cd4cfdf03c955b57c25d53d924f835f"),
    Entry(fontID: "nani", name: "何某手寫體", postScriptName: "NaniFont-Bold", file: "NaniFont-Bold.ttf",
          sha256: "1b5da5077665309289ba3e62c2fe4b1b788c800dd638af8113bff9fed96b588e"),
    Entry(fontID: "lxgwMarker", name: "霞鶩漫黑", postScriptName: "LXGWMarkerGothic-Regular", file: "LXGWMarkerGothic-Regular.ttf",
          sha256: "9a1e46379442856b9fc64de1d9bd4120903780990e28d99fd6415cadee78a47d"),
    Entry(fontID: "kurewa", name: "苦累蛙圓體", postScriptName: "KurewaGothicCjkTc-Bold", file: "KurewaGothicCjkTc-Bold.ttf",
          sha256: "f3c77d55c30ebf113c1e9375ac500df23082dc76221e3299d9ba581eb54bf515"),
    Entry(fontID: "popGothic", name: "大波浪圓體", postScriptName: "PopGothicCjkTc-Bold", file: "PopGothicCjkTc-Bold.ttf",
          sha256: "6f40a3fcfed7128bebca12b0b27c5cf4a0982e4312143df1390d1645fa4e12e7"),
    Entry(fontID: "wdxl", name: "WD-XL 滑油字", postScriptName: "WD-XLLubrifontTC-Regular", file: "WD-XLLubrifontTC-Regular.otf",
          sha256: "51c179e927526a9acd88b7722909e44c958133733ca316e824f812a28713768b"),
    Entry(fontID: "cubic11", name: "俐方體 11 號", postScriptName: "Cubic_11", file: "Cubic_11.ttf",
          sha256: "0193f5f033612496df6b45ee92ac3b335bc6a5a24ff95da55ca87b33e57dcf62"),
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

guard CommandLine.arguments.count >= 2 else {
    fail("usage: swift scripts/render-font-previews.swift <open-source font dir> [fontID ...]")
}
let fontDir = URL(fileURLWithPath: CommandLine.arguments[1])
/// Optional font IDs after the directory limit the run to those entries, so
/// one preview can be redrawn without every Apple font being installed.
let onlyFontIDs = Set(CommandLine.arguments.dropFirst(2))

/// Returns the font to draw with. Open-source fonts are built straight from
/// the manifest file (hash-checked), so a same-named font installed on this
/// Mac can never be drawn instead; Apple fonts are matched through CoreText.
func resolve(_ entry: Entry) -> NSFont {
    if let file = entry.file {
        let url = fontDir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { fail("missing file \(url.path)") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == entry.sha256 else { fail("\(entry.fontID): \(file) SHA-256 \(digest) does not match the manifest") }
        // A collection (the .ttc of 文鼎 PL 中楷) holds several faces: take the one by name.
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first(where: {
                  CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == entry.postScriptName
              }) ?? descriptors.first else { fail("\(entry.fontID): cannot read \(file)") }
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
    // Reserve space for size/status at SE width; wrap without reducing 17pt.
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    let wrapped = NSMutableAttributedString(attributedString: string)
    wrapped.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: wrapped.length))
    let bounds = wrapped.boundingRect(with: NSSize(width: 210, height: 1000),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading])
    let size = NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
    let padding: CGFloat = 4
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
    wrapped.draw(with: NSRect(x: padding, y: padding, width: size.width, height: size.height),
                 options: [.usesLineFragmentOrigin, .usesFontLeading])
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

for entry in entries where onlyFontIDs.isEmpty || onlyFontIDs.contains(entry.fontID) {
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
