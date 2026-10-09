import Foundation

/// Where an overlay font comes from (PRD 0.3 §4.1).
enum FontSource: String, Equatable, Hashable, Sendable {
    /// Ships with iOS and is always available: PingFang.
    case builtIn
    /// Downloaded by the App from `irene-chou/dayscam-fonts` (§4.2).
    case openSource
    /// An Apple downloadable system font, fetched through font matching.
    case system
}

/// The headed sections the font list is grouped into, in list order
/// (PRD 0.3 §4.1, FR-16.2).
enum FontSection: String, CaseIterable, Equatable, Hashable, Sendable {
    case builtIn
    case openSource
    case hei
    case yuan
    case song
    case kai
    case handwriting
    case calligraphy
    case cute

    /// The section heading shown above its fonts.
    var title: String {
        switch self {
        case .builtIn: return "內建"
        case .openSource: return "開源"
        case .hei: return "黑"
        case .yuan: return "圓"
        case .song: return "宋"
        case .kai: return "楷"
        case .handwriting: return "手寫"
        case .calligraphy: return "書法"
        case .cute: return "可愛"
        }
    }
}

/// The download and license facts of one open-source font
/// (PRD 0.3 §4.2, FR-16.13; values from `docs/fonts-manifest.md`).
struct OpenSourceFontAsset: Equatable, Hashable, Sendable {
    /// The upstream file name, unchanged (A-1).
    let fileName: String
    /// Path of the file inside the `dayscam-fonts` repository.
    let repositoryPath: String
    /// Exact file size in bytes; a download of any other size is rejected.
    let byteCount: Int
    /// Lower-case hex SHA-256 of the file; a mismatch is a failed download.
    let sha256: String
    /// jsDelivr URL, tried first (A-2).
    let primaryURL: URL
    /// GitHub raw URL, tried when the primary fails (A-2).
    let fallbackURL: URL
    /// The font's own version, as `docs/fonts-manifest.md` lists it.
    let version: String
    /// Copyright notice, verbatim from the font file's copyright name
    /// (`kCTFontCopyrightNameKey`); may span several lines.
    let copyright: String
    /// License files in `DaysCam/Resources/FontLicenses/`, in display order.
    let licenseFileNames: [String]

    /// Extension of `fileName` ("ttf" or "otf"), for the stored copy's name.
    var fileExtension: String { (fileName as NSString).pathExtension }
}

/// A weight a font can be drawn in (TASK-89). The raw value is what
/// `OverlayStyle` stores as `fontWeight`.
///
/// Names are relative to the font: each font's heaviest common face is
/// "粗" whatever its own name (Semibold, W6, W7), so the picker never shows
/// raw names such as W3.
enum OverlayFontWeight: String, Codable, CaseIterable, Sendable {
    case light
    case regular
    case bold
    case heavy

    /// The Chinese name the weight buttons show.
    var displayName: String {
        switch self {
        case .light: return "細"
        case .regular: return "標準"
        case .bold: return "粗"
        case .heavy: return "特粗"
        }
    }
}

/// One weight of one font, as the catalog offers it (TASK-89).
struct FontWeightOption: Equatable, Hashable, Sendable, Identifiable {
    let weight: OverlayFontWeight
    /// The exact face drawn for this weight.
    let postScriptName: String
    /// Download size in megabytes; `nil` when not listed (PingFang, and
    /// system weights other than the default, which are not measured).
    let downloadSizeMegabytes: Double?
    /// Download and license facts; only open-source fonts have them.
    let openSource: OpenSourceFontAsset?

    /// The stored `fontWeight` value, e.g. `"bold"`.
    var id: String { weight.rawValue }
}

/// The thing downloaded and registered: one weight of one font (TASK-89).
///
/// A font's default weight keeps the storage name the App used before
/// weights existed, so a file already downloaded is found and not fetched
/// again.
struct FontDownloadUnit: Equatable, Hashable, Sendable {
    let fontID: OverlayFontID
    let weight: OverlayFontWeight

    /// Base file name (without extension) of the stored copy, also the key
    /// for remembered system downloads: `fontID` for the default weight,
    /// `fontID-weight` otherwise.
    var storageName: String {
        weight == FontCatalog.entry(for: fontID).defaultWeight
            ? fontID.rawValue
            : "\(fontID.rawValue)-\(weight.rawValue)"
    }

    /// The catalog option this unit downloads.
    var option: FontWeightOption { FontCatalog.entry(for: fontID).option(for: weight) }
}

/// Everything the App knows about one overlay font (PRD 0.3 §4.1).
struct FontCatalogEntry: Equatable, Hashable, Sendable {
    let fontID: OverlayFontID
    /// The short Chinese name used in the picker, messages and license page.
    let displayName: String
    let section: FontSection
    let source: FontSource
    /// The face of the default weight, the one drawn before TASK-89.
    let postScriptName: String
    /// Download size in megabytes of the default weight as §4.1 lists it;
    /// `nil` for PingFang.
    let downloadSizeMegabytes: Double?
    /// Download and license facts of the default weight; only open-source
    /// fonts have them.
    let openSource: OpenSourceFontAsset?
    /// The weights offered, light to heavy; at most three (TASK-89).
    let weights: [FontWeightOption]
    /// The weight used when none, or one this font does not offer, is chosen.
    let defaultWeight: OverlayFontWeight

    /// Creates an entry. Without `weights` the font has a single weight,
    /// `defaultWeight`, drawn in `postScriptName`; a single weight's name is
    /// never shown, so its value only needs to be stable.
    init(fontID: OverlayFontID,
         displayName: String,
         section: FontSection,
         source: FontSource,
         postScriptName: String,
         downloadSizeMegabytes: Double?,
         openSource: OpenSourceFontAsset?,
         weights: [FontWeightOption]? = nil,
         defaultWeight: OverlayFontWeight = .regular) {
        self.fontID = fontID
        self.displayName = displayName
        self.section = section
        self.source = source
        self.postScriptName = postScriptName
        self.downloadSizeMegabytes = downloadSizeMegabytes
        self.openSource = openSource
        self.defaultWeight = defaultWeight
        self.weights = weights ?? [FontWeightOption(weight: defaultWeight, postScriptName: postScriptName,
                                                    downloadSizeMegabytes: downloadSizeMegabytes,
                                                    openSource: openSource)]
    }

    /// Whether the font offers more than one weight.
    var hasWeightChoice: Bool { weights.count > 1 }

    /// `weight` if this font offers it, else `defaultWeight` (85.6).
    func resolvedWeight(_ weight: OverlayFontWeight?) -> OverlayFontWeight {
        guard let weight, weights.contains(where: { $0.weight == weight }) else { return defaultWeight }
        return weight
    }

    /// The option for `weight`, falling back to the default weight.
    func option(for weight: OverlayFontWeight?) -> FontWeightOption {
        let resolved = resolvedWeight(weight)
        return weights.first { $0.weight == resolved }
            ?? FontWeightOption(weight: defaultWeight, postScriptName: postScriptName,
                                downloadSizeMegabytes: downloadSizeMegabytes, openSource: openSource)
    }

    /// The face drawn for `weight`, falling back to the default weight.
    func postScriptName(for weight: OverlayFontWeight?) -> String { option(for: weight).postScriptName }

    /// One download unit per offered weight, in `weights` order.
    var downloadUnits: [FontDownloadUnit] { weights.map { FontDownloadUnit(fontID: fontID, weight: $0.weight) } }

    /// The localized full face name shown in the font list and VoiceOver.
    /// Verified against CoreText localized names and the font name table (TASK-78).
    var fullName: String {
        switch fontID {
        case .pingFang: return "蘋方-繁 中粗體"
        case .huninn: return "jf open 粉圓 2.1"
        case .notoSerifTC: return "Noto Serif TC Bold"
        case .iansui: return "芫荽 Regular"
        case .chenyuluoyan: return "辰宇落雁體 2.0 細體"
        case .lantinghei: return "蘭亭黑-繁 中黑"
        case .liHei: return "儷黑 Pro"
        case .hiraginoSans: return "冬青黑體繁體中文 W6"
        case .yuanti: return "圓體-繁 粗體"
        case .songti: return "宋體-繁 粗體"
        case .liSong: return "儷宋 Pro"
        case .kaiti: return "楷體-繁 粗體"
        case .biauKai: return "標楷體-繁"
        case .hanziPen: return "翩翩體-繁 粗體"
        case .hannotate: return "手札體-繁 粗體"
        case .lingWai: return "凌慧體-繁 中黑體"
        case .xingkai: return "行楷-繁 粗體"
        case .weibei: return "魏碑-繁 粗體"
        case .libian: return "隸變-繁 標準體"
        case .baoli: return "報隸-繁 標準體"
        case .wawa: return "娃娃體-繁 標準體"
        case .yuppy: return "雅痞-繁 標準體"
        }
    }

    /// The size as the list shows it, e.g. "43.7 MB"; `nil` for PingFang.
    var downloadSizeText: String? {
        downloadSizeMegabytes.map { String(format: "%.1f MB", $0) }
    }
}

/// The fixed catalog of the 22 overlay fonts (PRD 0.3 §4.1, §4.2; TASK-40
/// added 辰宇落雁體; TASK-89 added weights, see #362).
///
/// Hard-coded on purpose: there is no remote manifest (A-2). Open-source
/// values must match `docs/fonts-manifest.md`; change both together.
enum FontCatalog {
    /// The PostScript name PingFang is drawn with (A-6).
    static let pingFangPostScriptName = "PingFangTC-Semibold"

    /// The public repository and tag the open-source fonts are served from.
    static let repository = "irene-chou/dayscam-fonts"
    /// The fixed tag the URLs point at.
    static let repositoryTag = "v3"

    /// Every font in list order, which is `OverlayFontID.allCases` order.
    static var entries: [FontCatalogEntry] { OverlayFontID.allCases.map(entry(for:)) }

    /// The catalog entry for `fontID`.
    static func entry(for fontID: OverlayFontID) -> FontCatalogEntry {
        switch fontID {
        case .pingFang:
            let weights: [FontWeightOption] = [
                builtInWeight(.light, "PingFangTC-Light"),
                builtInWeight(.regular, "PingFangTC-Regular"),
                builtInWeight(.bold, pingFangPostScriptName)
            ]
            return FontCatalogEntry(fontID: fontID, displayName: "蘋方", section: .builtIn, source: .builtIn,
                                    postScriptName: pingFangPostScriptName, downloadSizeMegabytes: nil,
                                    openSource: nil, weights: weights, defaultWeight: .bold)
        case .huninn:
            return openSourceEntry(fontID, "粉圓", "jf-openhuninn-2.1", 4.9, asset: huninnAsset)
        case .notoSerifTC:
            let weights = [
                FontWeightOption(weight: .regular, postScriptName: "NotoSerifTC-Regular",
                                 downloadSizeMegabytes: 7.9, openSource: notoSerifTCRegularAsset),
                FontWeightOption(weight: .bold, postScriptName: "NotoSerifTC-Bold",
                                 downloadSizeMegabytes: 8.3, openSource: notoSerifTCAsset),
                FontWeightOption(weight: .heavy, postScriptName: "NotoSerifTC-Black",
                                 downloadSizeMegabytes: 8.1, openSource: notoSerifTCBlackAsset)
            ]
            return openSourceEntry(fontID, "思源宋體", "NotoSerifTC-Bold", 8.3, asset: notoSerifTCAsset,
                                   weights: weights, defaultWeight: .bold)
        case .iansui:
            return openSourceEntry(fontID, "芫荽", "Iansui-Regular", 9.4, asset: iansuiAsset)
        case .chenyuluoyan:
            return openSourceEntry(fontID, "辰宇落雁體", "ChenYuluoyan-2.0-Thin", 9.5, asset: chenyuluoyanAsset,
                                   defaultWeight: .light)
        case .lantinghei: return systemEntry(fontID, "蘭亭黑", .hei, "FZLTZHB--B51-0", 25.2)
        case .liHei: return systemEntry(fontID, "儷黑", .hei, "LiHeiPro", 4.2)
        case .hiraginoSans: return systemEntry(fontID, "冬青黑體", .hei, "HiraginoSansTC-W6", 14.1,
                                                   extra: [(.regular, "HiraginoSansTC-W3")])
        case .yuanti: return systemEntry(fontID, "圓體", .yuan, "STYuanti-TC-Bold", 46.5,
                                             extra: [(.light, "STYuanti-TC-Light"), (.regular, "STYuanti-TC-Regular")])
        case .songti: return systemEntry(fontID, "宋體", .song, "STSongti-TC-Bold", 43.7,
                                             extra: [(.light, "STSongti-TC-Light"), (.regular, "STSongti-TC-Regular")])
        case .liSong: return systemEntry(fontID, "儷宋", .song, "LiSongPro", 7.1)
        case .kaiti: return systemEntry(fontID, "楷體", .kai, "STKaitiTC-Bold", 66.1,
                                            extra: [(.regular, "STKaitiTC-Regular")])
        case .biauKai: return systemEntry(fontID, "標楷體", .kai, "BiauKaiTC-Regular", 17.8)
        case .hanziPen: return systemEntry(fontID, "翩翩體", .handwriting, "HanziPenTC-W5", 48.7)
        case .hannotate: return systemEntry(fontID, "手札體", .handwriting, "HannotateTC-W7", 50.0,
                                                           extra: [(.regular, "HannotateTC-W5")])
        case .lingWai: return systemEntry(fontID, "凌慧體", .handwriting, "MLingWaiMedium-TC", 18.4)
        case .xingkai: return systemEntry(fontID, "行楷", .calligraphy, "STXingkaiTC-Bold", 54.8)
        case .weibei: return systemEntry(fontID, "魏碑", .calligraphy, "WeibeiTC-Bold", 11.0)
        case .libian: return systemEntry(fontID, "隸變", .calligraphy, "STLibianTC-Regular", 21.6)
        case .baoli: return systemEntry(fontID, "報隸", .calligraphy, "STBaoliTC-Regular", 25.6)
        case .wawa: return systemEntry(fontID, "娃娃體", .cute, "DFWaWaTC-W5", 11.6)
        case .yuppy: return systemEntry(fontID, "雅痞", .cute, "YuppyTC-Regular", 12.9)
        }
    }

    // MARK: - Open-source assets (docs/fonts-manifest.md)

    static let huninnAsset = asset(
        path: "huninn/jf-openhuninn-2.1.ttf",
        byteCount: 4_911_464,
        sha256: "9d5bf4932d31fe94c18cd8cfddc98bc1b14ce10f4e354c682179db290a99c825",
        version: "2.1",
        copyright: """
            [Kosugi Maru]
            Copyright (c) 2010 MOTOYA CO.,LTD.

            [Varela Round]
            Copyright (x) 2011-2016 The Varela Round Project Authors (https://github.com/alefalefalef/Varela-Round-Hebrew/), with Reserved Font Names 'Varela' and 'Varela Round'.

            [jf open huninn]
            Copyright (c) 2020-2024 The jf open huninn font is redistributed by justfont Co., Ltd., with Reserved Font Names 'open huninn' and 'huninn' under SIL Open Font License. The Hanzi part of this project was derived from Kosugi Maru under Apache-2.0 (https://www.apache.org/licenses/LICENSE-2.0).
            """,
        licenseFileNames: ["huninn-OFL.txt", "huninn-Apache-2.0.txt"])

    static let notoSerifTCAsset = asset(
        path: "noto-serif-tc/NotoSerifTC-Bold.otf",
        byteCount: 8_253_304,
        sha256: "3ca2b3294ec84b795d0a45695e78e3612a44dce50f9fc776cd40206340a5768d",
        version: "2.003",
        copyright: "© 2017-2024 Adobe (http://www.adobe.com/).",
        licenseFileNames: ["notoSerifTC-OFL.txt"])

    /// 思源宋體 Regular, added in `v3` (TASK-89).
    static let notoSerifTCRegularAsset = asset(
        path: "noto-serif-tc/NotoSerifTC-Regular.otf",
        byteCount: 7_936_104,
        sha256: "63515eb0622d589a2f4062e8757c598b3da3bffd053f69abd181c210158ef10c",
        version: "2.003",
        copyright: "© 2017-2024 Adobe (http://www.adobe.com/).",
        licenseFileNames: ["notoSerifTC-OFL.txt"])

    /// 思源宋體 Black, added in `v3` (TASK-89).
    static let notoSerifTCBlackAsset = asset(
        path: "noto-serif-tc/NotoSerifTC-Black.otf",
        byteCount: 8_122_092,
        sha256: "55c68df309e702cdb56b9ffd6b8185468afc0cb070aa9c2f14099de0cae64d12",
        version: "2.003",
        copyright: "© 2017-2024 Adobe (http://www.adobe.com/).",
        licenseFileNames: ["notoSerifTC-OFL.txt"])

    static let iansuiAsset = asset(
        path: "iansui/Iansui-Regular.ttf",
        byteCount: 9_447_424,
        sha256: "7f1aa62e9dcbf40d0ce41a5d3f1e5ea602e66c295778ac6fefb6b84d8ed08bd5",
        version: "1.012",
        copyright: "Copyright 2025 The Iansui Project Authors (https://github.com/ButTaiwan/iansui)",
        licenseFileNames: ["iansui-OFL.txt"])

    /// The font has an English and a Traditional Chinese copyright record;
    /// both are listed, English first (TASK-40).
    static let chenyuluoyanAsset = asset(
        path: "chenyuluoyan/ChenYuluoyan-2.0-Thin.ttf",
        byteCount: 9_522_140,
        sha256: "1289e42a6d1ec995d0cb23aee89efc69fc95749fbd54a610057a3e992dc453db",
        version: "2.100",
        copyright: """
            Copyright (c) 2022, Wang, Li-Yu & Liu, Wei-Chen.
            (c) 2022 王立宇、劉韋辰 版權所有。
            """,
        licenseFileNames: ["chenyuluoyan-OFL.txt"])

    // MARK: - Builders

    private static func openSourceEntry(_ fontID: OverlayFontID,
                                        _ displayName: String,
                                        _ postScriptName: String,
                                        _ megabytes: Double,
                                        asset: OpenSourceFontAsset,
                                        weights: [FontWeightOption]? = nil,
                                        defaultWeight: OverlayFontWeight = .regular) -> FontCatalogEntry {
        FontCatalogEntry(fontID: fontID, displayName: displayName, section: .openSource, source: .openSource,
                         postScriptName: postScriptName, downloadSizeMegabytes: megabytes, openSource: asset,
                         weights: weights, defaultWeight: defaultWeight)
    }

    private static func builtInWeight(_ weight: OverlayFontWeight, _ postScriptName: String) -> FontWeightOption {
        FontWeightOption(weight: weight, postScriptName: postScriptName, downloadSizeMegabytes: nil, openSource: nil)
    }

    private static func systemEntry(_ fontID: OverlayFontID,
                                    _ displayName: String,
                                    _ section: FontSection,
                                    _ postScriptName: String,
                                    _ megabytes: Double,
                                    extra: [(OverlayFontWeight, String)] = []) -> FontCatalogEntry {
        // `extra` are the lighter weights; the current face is the default
        // and heaviest. Their sizes are not measured (#362, Lead 5).
        let lighter = extra.map {
            FontWeightOption(weight: $0.0, postScriptName: $0.1, downloadSizeMegabytes: nil, openSource: nil)
        }
        let weights: [FontWeightOption]? = extra.isEmpty ? nil : lighter + [
            FontWeightOption(weight: .bold, postScriptName: postScriptName,
                             downloadSizeMegabytes: megabytes, openSource: nil)
        ]
        return FontCatalogEntry(fontID: fontID, displayName: displayName, section: section, source: .system,
                                postScriptName: postScriptName, downloadSizeMegabytes: megabytes, openSource: nil,
                                weights: weights, defaultWeight: extra.isEmpty ? .regular : .bold)
    }

    private static func asset(path: String,
                              byteCount: Int,
                              sha256: String,
                              version: String,
                              copyright: String,
                              licenseFileNames: [String]) -> OpenSourceFontAsset {
        OpenSourceFontAsset(
            fileName: (path as NSString).lastPathComponent,
            repositoryPath: path,
            byteCount: byteCount,
            sha256: sha256,
            primaryURL: remoteURL("https://cdn.jsdelivr.net/gh/\(repository)@\(repositoryTag)/\(path)"),
            fallbackURL: remoteURL("https://raw.githubusercontent.com/\(repository)/\(repositoryTag)/\(path)"),
            version: version,
            copyright: copyright,
            licenseFileNames: licenseFileNames)
    }

    /// Builds a URL from a constant in this file. A malformed constant is a
    /// programming error caught by `FontCatalogTests`, not a runtime condition.
    private static func remoteURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("FontCatalog: malformed URL \(string)")
        }
        return url
    }
}
