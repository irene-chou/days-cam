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

extension FontSource {
    /// The heading above this source's not-yet-downloaded fonts in the list
    /// (TASK-120); `nil` for PingFang, which is never in that part of the list.
    var listTitle: String? {
        switch self {
        case .builtIn: return nil
        // Headings are for the person choosing a font: open-source fonts can
        // be deleted, system fonts cannot (TASK-120, replacing TASK-111's 可下載).
        case .openSource: return "開源字型"
        case .system: return "系統字型"
        }
    }

    /// Position of the source in list order: built-in, open source, system.
    var listRank: Int {
        switch self {
        case .builtIn: return 0
        case .openSource: return 1
        case .system: return 2
        }
    }
}

/// The type of a font's letterforms (TASK-120). Not shown to the user: it
/// only orders fonts inside their source group, in `allCases` order, so a new
/// font needs just a `source` and a `category` to land in the right place.
enum FontStyleCategory: String, CaseIterable, Equatable, Hashable, Sendable {
    case hei
    case yuan
    case song
    case kai
    case handwriting
    case calligraphy
    case cute

    /// The type's name, for tests and documentation.
    var title: String {
        switch self {
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

/// An exact face and its download/license facts (TASK-89).
struct FontWeightOption: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let displayName: String
    let postScriptName: String
    let downloadSizeMegabytes: Double?
    let openSource: OpenSourceFontAsset?
}

/// A stable download unit. Default faces retain the old disk/defaults key.
struct FontDownloadID: Equatable, Hashable, Sendable {
    let fontID: OverlayFontID
    let weightID: String

    var rawValue: String {
        let entry = FontCatalog.entry(for: fontID)
        return weightID == entry.defaultWeight.id ? fontID.rawValue : "\(fontID.rawValue)/\(weightID)"
    }
}

/// Everything the App knows about one overlay font (PRD 0.3 §4.1).
struct FontCatalogEntry: Equatable, Hashable, Sendable {
    let fontID: OverlayFontID
    /// The short Chinese name used in the picker, messages and license page.
    let displayName: String
    /// The letterform type; orders the font inside its source group (TASK-120).
    let category: FontStyleCategory
    let source: FontSource
    /// The legacy default face; explicit weights resolve through `weight(for:)`.
    let postScriptName: String
    /// Download size in megabytes as §4.1 lists it; `nil` for PingFang.
    let downloadSizeMegabytes: Double?
    /// Download and license facts; only open-source fonts have them.
    let openSource: OpenSourceFontAsset?

    /// At most three approved exact faces, in picker order.
    let weights: [FontWeightOption]

    init(fontID: OverlayFontID, displayName: String, category: FontStyleCategory, source: FontSource,
         postScriptName: String, downloadSizeMegabytes: Double?, openSource: OpenSourceFontAsset?,
         weights: [FontWeightOption]? = nil) {
        self.fontID = fontID
        self.displayName = displayName
        self.category = category
        self.source = source
        self.postScriptName = postScriptName
        self.downloadSizeMegabytes = downloadSizeMegabytes
        self.openSource = openSource
        self.weights = weights ?? FontCatalog.weightOptions(for: fontID, postScriptName: postScriptName,
                                                            megabytes: downloadSizeMegabytes, asset: openSource)
        precondition(!self.weights.isEmpty && self.weights.count <= 3)
        precondition(Set(self.weights.map(\.id)).count == self.weights.count)
        precondition(self.weights.contains { $0.postScriptName == postScriptName })
    }

    /// The existing face, preserved for old profiles and files.
    var defaultWeight: FontWeightOption {
        // The initializer guarantees the legacy face exists.
        weights.first { $0.postScriptName == postScriptName } ?? weights[0]
    }

    /// Unknown or absent IDs safely use the existing default face.
    func weight(for id: String?) -> FontWeightOption {
        weights.first { $0.id == id } ?? defaultWeight
    }

    /// The size as the list shows it, e.g. "43.7 MB"; `nil` for PingFang.
    var downloadSizeText: String? {
        downloadSizeMegabytes.map { String(format: "%.1f MB", $0) }
    }
}

/// The fixed catalog of the 52 overlay fonts (PRD 0.3 §4.1, §4.2; TASK-40
/// added 辰宇落雁體, TASK-142 the 30 families of `downloadFamilies`).
///
/// Hard-coded on purpose: there is no remote manifest (A-2). Open-source
/// values must match `docs/fonts-manifest.md`; change both together.
enum FontCatalog {
    /// The PostScript name PingFang is drawn with (A-6).
    static let pingFangPostScriptName = "PingFangTC-Semibold"

    /// The public repository and tag the open-source fonts are served from.
    static let repository = "irene-chou/dayscam-fonts"
    /// The fixed tag the URLs point at.
    static let repositoryTag = "v4"

    /// Every font in list order, which is `OverlayFontID.allCases` order.
    static var entries: [FontCatalogEntry] { OverlayFontID.allCases.map(entry(for:)) }

    /// `entries` in the order the font list shows them: by source
    /// (built-in, open source, system), then by type, then by catalog order.
    /// Computed, so the order does not depend on how `entries` is arranged
    /// (TASK-120).
    static func listOrdered(_ entries: [FontCatalogEntry]) -> [FontCatalogEntry] {
        let categories = FontStyleCategory.allCases
        return entries.enumerated().sorted { lhs, rhs in
            let (l, r) = (lhs.element, rhs.element)
            if l.source.listRank != r.source.listRank { return l.source.listRank < r.source.listRank }
            let (lc, rc) = (categories.firstIndex(of: l.category) ?? 0, categories.firstIndex(of: r.category) ?? 0)
            if lc != rc { return lc < rc }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Every entry, built once on first use. The catalog is fixed (A-2), so
    /// callers on hot paths (`encode`, font resolution) look entries up here
    /// instead of rebuilding them.
    static let entriesByID: [OverlayFontID: FontCatalogEntry] =
        Dictionary(uniqueKeysWithValues: OverlayFontID.allCases.map { ($0, makeEntry(for: $0)) })

    /// The catalog entry for `fontID`.
    static func entry(for fontID: OverlayFontID) -> FontCatalogEntry {
        guard let entry = entriesByID[fontID] else { return makeEntry(for: fontID) }
        return entry
    }

    /// Builds the entry from scratch, without the cache. Internal so tests can
    /// check the cached table against it.
    static func makeEntry(for fontID: OverlayFontID) -> FontCatalogEntry {
        switch fontID {
        case .pingFang:
            return FontCatalogEntry(fontID: fontID, displayName: "蘋方", category: .hei, source: .builtIn,
                                    postScriptName: pingFangPostScriptName, downloadSizeMegabytes: nil,
                                    openSource: nil)
        case .huninn:
            return openSourceEntry(fontID, "粉圓", "jf-openhuninn-2.1", .yuan, 4.9, asset: huninnAsset)
        case .notoSerifTC:
            return openSourceEntry(fontID, "思源宋體", "NotoSerifTC-Bold", .song, 8.3, asset: notoSerifTCAsset)
        case .iansui:
            return openSourceEntry(fontID, "芫荽", "Iansui-Regular", .kai, 9.4, asset: iansuiAsset)
        case .chenyuluoyan:
            return openSourceEntry(fontID, "辰宇落雁體", "ChenYuluoyan-2.0-Thin", .handwriting, 9.5, asset: chenyuluoyanAsset)
        case .lantinghei: return systemEntry(fontID, "蘭亭黑", .hei, "FZLTZHB--B51-0", 25.2)
        case .liHei: return systemEntry(fontID, "儷黑", .hei, "LiHeiPro", 4.2)
        case .hiraginoSans: return systemEntry(fontID, "冬青黑體", .hei, "HiraginoSansTC-W6", 14.1)
        case .yuanti: return systemEntry(fontID, "圓體", .yuan, "STYuanti-TC-Bold", 46.5)
        case .songti: return systemEntry(fontID, "宋體", .song, "STSongti-TC-Bold", 43.7)
        case .liSong: return systemEntry(fontID, "儷宋", .song, "LiSongPro", 7.1)
        case .kaiti: return systemEntry(fontID, "楷體", .kai, "STKaitiTC-Bold", 66.1)
        case .biauKai: return systemEntry(fontID, "標楷體", .kai, "BiauKaiTC-Regular", 17.8)
        case .hanziPen: return systemEntry(fontID, "翩翩體", .handwriting, "HanziPenTC-W5", 48.7)
        case .hannotate: return systemEntry(fontID, "手札體", .handwriting, "HannotateTC-W7", 50.0)
        case .lingWai: return systemEntry(fontID, "凌慧體", .handwriting, "MLingWaiMedium-TC", 18.4)
        case .xingkai: return systemEntry(fontID, "行楷", .calligraphy, "STXingkaiTC-Bold", 54.8)
        case .weibei: return systemEntry(fontID, "魏碑", .calligraphy, "WeibeiTC-Bold", 11.0)
        case .libian: return systemEntry(fontID, "隸變", .calligraphy, "STLibianTC-Regular", 21.6)
        case .baoli: return systemEntry(fontID, "報隸", .calligraphy, "STBaoliTC-Regular", 25.6)
        case .wawa: return systemEntry(fontID, "娃娃體", .cute, "DFWaWaTC-W5", 11.6)
        case .yuppy: return systemEntry(fontID, "雅痞", .cute, "YuppyTC-Regular", 12.9)
        default: return downloadFamilyEntry(for: fontID)
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

    /// Lead-approved face list, Issue #362 (89.1).
    static func weightOptions(for fontID: OverlayFontID, postScriptName: String,
                              megabytes: Double?, asset: OpenSourceFontAsset?) -> [FontWeightOption] {
        func option(_ id: String, _ name: String, _ face: String,
                    _ download: OpenSourceFontAsset? = nil) -> FontWeightOption {
            FontWeightOption(id: id, displayName: name, postScriptName: face,
                             downloadSizeMegabytes: download.map { Double($0.byteCount) / 1_000_000 } ?? megabytes,
                             openSource: download)
        }
        switch fontID {
        case .pingFang:
            return [option("light", "細", "PingFangTC-Light"), option("regular", "標準", "PingFangTC-Regular"),
                    option("semibold", "粗", postScriptName)]
        case .notoSerifTC:
            return [option("regular", "標準", "NotoSerifTC-Regular", notoSerifTCRegularAsset),
                    option("bold", "粗", postScriptName, asset),
                    option("black", "特粗", "NotoSerifTC-Black", notoSerifTCBlackAsset)]
        case .hiraginoSans:
            return [option("w3", "標準", "HiraginoSansTC-W3"), option("w6", "粗", postScriptName)]
        case .songti:
            return [option("light", "細", "STSongti-TC-Light"), option("regular", "標準", "STSongti-TC-Regular"),
                    option("bold", "粗", postScriptName)]
        case .kaiti:
            return [option("regular", "標準", "STKaitiTC-Regular"), option("bold", "粗", postScriptName),
                    option("black", "特粗", "STKaitiTC-Black")]
        case .yuanti:
            return [option("light", "細", "STYuanti-TC-Light"), option("regular", "標準", "STYuanti-TC-Regular"),
                    option("bold", "粗", postScriptName)]
        case .hannotate:
            return [option("w5", "標準", "HannotateTC-W5"), option("w7", "粗", postScriptName)]
        case .chenyuluoyan: return [option("thin", "細", postScriptName, asset)]
        default: return [option("regular", "標準", postScriptName, asset)]
        }
    }

    static let notoSerifTCRegularAsset = notoAsset(
        face: "Regular", bytes: 7_936_104,
        sha256: "63515eb0622d589a2f4062e8757c598b3da3bffd053f69abd181c210158ef10c")
    static let notoSerifTCBlackAsset = notoAsset(
        face: "Black", bytes: 8_122_092,
        sha256: "55c68df309e702cdb56b9ffd6b8185468afc0cb070aa9c2f14099de0cae64d12")

    private static func notoAsset(face: String, bytes: Int, sha256: String) -> OpenSourceFontAsset {
        asset(path: "noto-serif-tc/NotoSerifTC-\(face).otf",
              byteCount: bytes,
              sha256: sha256,
              version: "2.003",
              copyright: "© 2017-2024 Adobe (http://www.adobe.com/).",
              licenseFileNames: ["notoSerifTC-OFL.txt"])
    }

    // MARK: - Builders

    private static func openSourceEntry(_ fontID: OverlayFontID,
                                        _ displayName: String,
                                        _ postScriptName: String,
                                        _ category: FontStyleCategory,
                                        _ megabytes: Double,
                                        asset: OpenSourceFontAsset) -> FontCatalogEntry {
        FontCatalogEntry(fontID: fontID, displayName: displayName, category: category, source: .openSource,
                         postScriptName: postScriptName, downloadSizeMegabytes: megabytes, openSource: asset)
    }

    private static func systemEntry(_ fontID: OverlayFontID,
                                    _ displayName: String,
                                    _ category: FontStyleCategory,
                                    _ postScriptName: String,
                                    _ megabytes: Double) -> FontCatalogEntry {
        FontCatalogEntry(fontID: fontID, displayName: displayName, category: category, source: .system,
                         postScriptName: postScriptName, downloadSizeMegabytes: megabytes, openSource: nil)
    }

    static func asset(path: String,
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
