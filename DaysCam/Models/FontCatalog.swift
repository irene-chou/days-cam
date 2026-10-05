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

/// Everything the App knows about one overlay font (PRD 0.3 §4.1).
struct FontCatalogEntry: Equatable, Hashable, Sendable {
    let fontID: OverlayFontID
    /// The Chinese name shown in the grid and the list.
    let displayName: String
    let section: FontSection
    let source: FontSource
    /// The exact face drawn; weights are fixed (FR-10.3′).
    let postScriptName: String
    /// Download size in megabytes as §4.1 lists it; `nil` for PingFang.
    let downloadSizeMegabytes: Double?
    /// Download and license facts; only open-source fonts have them.
    let openSource: OpenSourceFontAsset?

    /// The size as the list shows it, e.g. "43.7 MB"; `nil` for PingFang.
    var downloadSizeText: String? {
        downloadSizeMegabytes.map { String(format: "%.1f MB", $0) }
    }
}

/// The fixed catalog of the 21 overlay fonts (PRD 0.3 §4.1, §4.2).
///
/// Hard-coded on purpose: there is no remote manifest (A-2). Open-source
/// values must match `docs/fonts-manifest.md`; change both together.
enum FontCatalog {
    /// The PostScript name PingFang is drawn with (A-6).
    static let pingFangPostScriptName = "PingFangTC-Semibold"

    /// The public repository and tag the open-source fonts are served from.
    static let repository = "irene-chou/dayscam-fonts"
    /// The fixed tag the URLs point at.
    static let repositoryTag = "v1"

    /// Every font in list order, which is `OverlayFontID.allCases` order.
    static var entries: [FontCatalogEntry] { OverlayFontID.allCases.map(entry(for:)) }

    /// The catalog entry for `fontID`.
    static func entry(for fontID: OverlayFontID) -> FontCatalogEntry {
        switch fontID {
        case .pingFang:
            return FontCatalogEntry(fontID: fontID, displayName: "蘋方", section: .builtIn, source: .builtIn,
                                    postScriptName: pingFangPostScriptName, downloadSizeMegabytes: nil,
                                    openSource: nil)
        case .huninn:
            return openSourceEntry(fontID, "粉圓", "jf-openhuninn-2.1", 4.9, asset: huninnAsset)
        case .notoSerifTC:
            return openSourceEntry(fontID, "思源宋體", "NotoSerifTC-Bold", 8.3, asset: notoSerifTCAsset)
        case .iansui:
            return openSourceEntry(fontID, "芫荽", "Iansui-Regular", 9.4, asset: iansuiAsset)
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

    // MARK: - Builders

    private static func openSourceEntry(_ fontID: OverlayFontID,
                                        _ displayName: String,
                                        _ postScriptName: String,
                                        _ megabytes: Double,
                                        asset: OpenSourceFontAsset) -> FontCatalogEntry {
        FontCatalogEntry(fontID: fontID, displayName: displayName, section: .openSource, source: .openSource,
                         postScriptName: postScriptName, downloadSizeMegabytes: megabytes, openSource: asset)
    }

    private static func systemEntry(_ fontID: OverlayFontID,
                                    _ displayName: String,
                                    _ section: FontSection,
                                    _ postScriptName: String,
                                    _ megabytes: Double) -> FontCatalogEntry {
        FontCatalogEntry(fontID: fontID, displayName: displayName, section: section, source: .system,
                         postScriptName: postScriptName, downloadSizeMegabytes: megabytes, openSource: nil)
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
