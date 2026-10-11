import XCTest
@testable import DaysCam

/// Covers TASK-32 32.1 and 32.9, and TASK-40 40.1–40.3: the 22 fonts of
/// PRD 0.3 §4.1 plus 辰宇落雁體 (TASK-40), and the open-source download facts
/// of `docs/fonts-manifest.md`.
///
/// Expected values are written out here, independently of `FontCatalog`, so a
/// wrong catalog value cannot pass itself.
final class FontCatalogTests: XCTestCase {


    /// TASK-78 78.3/78.4: verified full face names, while short names stay unchanged.
    func testApprovedWeightsResolveToExactFacesAndPreserveLegacyDefaults() {
        let expected: [(OverlayFontID, [String], [String], String)] = [
            (.pingFang, ["light", "regular", "semibold"], ["PingFangTC-Light", "PingFangTC-Regular", "PingFangTC-Semibold"], "semibold"),
            (.notoSerifTC, ["regular", "bold", "black"], ["NotoSerifTC-Regular", "NotoSerifTC-Bold", "NotoSerifTC-Black"], "bold"),
            (.hiraginoSans, ["w3", "w6"], ["HiraginoSansTC-W3", "HiraginoSansTC-W6"], "w6"),
            (.songti, ["light", "regular", "bold"], ["STSongti-TC-Light", "STSongti-TC-Regular", "STSongti-TC-Bold"], "bold"),
            (.kaiti, ["regular", "bold", "black"], ["STKaitiTC-Regular", "STKaitiTC-Bold", "STKaitiTC-Black"], "bold"),
            (.yuanti, ["light", "regular", "bold"], ["STYuanti-TC-Light", "STYuanti-TC-Regular", "STYuanti-TC-Bold"], "bold"),
            (.hannotate, ["w5", "w7"], ["HannotateTC-W5", "HannotateTC-W7"], "w7"),
            (.chenyuluoyan, ["thin"], ["ChenYuluoyan-2.0-Thin"], "thin")
        ]
        for (id, weights, faces, defaultID) in expected {
            let entry = FontCatalog.entry(for: id)
            XCTAssertEqual(entry.weights.map(\.id), weights)
            XCTAssertEqual(entry.weights.map(\.postScriptName), faces)
            XCTAssertEqual(entry.defaultWeight.id, defaultID)
        }
        for entry in FontCatalog.entries {
            XCTAssertEqual(entry.weight(for: nil).postScriptName, entry.postScriptName)
            XCTAssertEqual(entry.weight(for: "invalid").postScriptName, entry.postScriptName)
            XCTAssertTrue((1...3).contains(entry.weights.count))
            XCTAssertEqual(Set(entry.weights.map(\.id)).count, entry.weights.count)
        }
    }

    func testNewNotoWeightsCarryVerifiedDownloadAndLicenseFacts() throws {
        let entry = FontCatalog.entry(for: .notoSerifTC)
        let regular = try XCTUnwrap(entry.weight(for: "regular").openSource)
        let black = try XCTUnwrap(entry.weight(for: "black").openSource)
        XCTAssertEqual(regular.fileName, "NotoSerifTC-Regular.otf")
        XCTAssertEqual(regular.byteCount, 7_936_104)
        XCTAssertEqual(regular.sha256, "63515eb0622d589a2f4062e8757c598b3da3bffd053f69abd181c210158ef10c")
        XCTAssertEqual(black.fileName, "NotoSerifTC-Black.otf")
        XCTAssertEqual(black.byteCount, 8_122_092)
        XCTAssertEqual(black.sha256, "55c68df309e702cdb56b9ffd6b8185468afc0cb070aa9c2f14099de0cae64d12")
        for asset in [regular, black] {
            XCTAssertEqual(asset.copyright, "© 2017-2024 Adobe (http://www.adobe.com/).")
            XCTAssertEqual(asset.licenseFileNames, ["notoSerifTC-OFL.txt"])
        }
    }

    /// 91.1 / 91.2: every weight's open-source asset, including Noto Regular
    /// and Black, downloads from `dayscam-fonts@v3`; no upstream URL remains.
    func testEveryWeightAssetDownloadsFromTheV3Tag() {
        let assets = FontCatalog.entries.flatMap { $0.weights.compactMap(\.openSource) }
        XCTAssertEqual(assets.count, 6, "91.1")
        for asset in assets {
            XCTAssertEqual(asset.primaryURL.absoluteString,
                           "https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v3/\(asset.repositoryPath)",
                           "91.1 \(asset.fileName)")
            XCTAssertEqual(asset.fallbackURL.absoluteString,
                           "https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v3/\(asset.repositoryPath)",
                           "91.1 \(asset.fileName)")
            XCTAssertFalse(asset.primaryURL.absoluteString.contains("notofonts"), "91.1 \(asset.fileName)")
            XCTAssertFalse(asset.fallbackURL.absoluteString.contains("notofonts"), "91.1 \(asset.fileName)")
        }
        let notoPaths = FontCatalog.entry(for: .notoSerifTC).weights.compactMap(\.openSource?.repositoryPath)
        XCTAssertEqual(notoPaths, ["noto-serif-tc/NotoSerifTC-Regular.otf",
                                   "noto-serif-tc/NotoSerifTC-Bold.otf",
                                   "noto-serif-tc/NotoSerifTC-Black.otf"], "91.1")
    }

    func testFullNamesMatchVerifiedFontMetadata() {
        let names: [OverlayFontID: String] = [
            .pingFang: "蘋方-繁 中粗體",
            .lantinghei: "蘭亭黑-繁 中黑",
            .liHei: "儷黑 Pro",
            .hiraginoSans: "冬青黑體繁體中文 W6",
            .yuanti: "圓體-繁 粗體",
            .songti: "宋體-繁 粗體",
            .liSong: "儷宋 Pro",
            .kaiti: "楷體-繁 粗體",
            .biauKai: "標楷體-繁",
            .hanziPen: "翩翩體-繁 粗體",
            .hannotate: "手札體-繁 粗體",
            .lingWai: "凌慧體-繁 中黑體",
            .xingkai: "行楷-繁 粗體",
            .weibei: "魏碑-繁 粗體",
            .libian: "隸變-繁 標準體",
            .baoli: "報隸-繁 標準體",
            .wawa: "娃娃體-繁 標準體",
            .yuppy: "雅痞-繁 標準體",
            .huninn: "jf open 粉圓",
            .notoSerifTC: "Noto Serif TC Bold",
            .iansui: "芫荽 Regular",
            .chenyuluoyan: "辰宇落雁體 2.0 細體",
        ]
        XCTAssertEqual(names.count, FontCatalog.entries.count)
        for entry in FontCatalog.entries {
            XCTAssertEqual(entry.fullName, names[entry.fontID], "\(entry.fontID)")
        }
    }

    /// PRD 0.3 §4.1, row by row: ID, name, section, source, PostScript, size.
    private let table: [(OverlayFontID, String, FontSection, FontSource, String, String?)] = [
        (.pingFang, "蘋方", .builtIn, .builtIn, "PingFangTC-Semibold", nil),
        (.huninn, "粉圓", .openSource, .openSource, "jf-openhuninn-2.1", "4.9 MB"),
        (.notoSerifTC, "思源宋體", .openSource, .openSource, "NotoSerifTC-Bold", "8.3 MB"),
        (.iansui, "芫荽", .openSource, .openSource, "Iansui-Regular", "9.4 MB"),
        (.chenyuluoyan, "辰宇落雁體", .openSource, .openSource, "ChenYuluoyan-2.0-Thin", "9.5 MB"),
        (.lantinghei, "蘭亭黑", .hei, .system, "FZLTZHB--B51-0", "25.2 MB"),
        (.liHei, "儷黑", .hei, .system, "LiHeiPro", "4.2 MB"),
        (.hiraginoSans, "冬青黑體", .hei, .system, "HiraginoSansTC-W6", "14.1 MB"),
        (.yuanti, "圓體", .yuan, .system, "STYuanti-TC-Bold", "46.5 MB"),
        (.songti, "宋體", .song, .system, "STSongti-TC-Bold", "43.7 MB"),
        (.liSong, "儷宋", .song, .system, "LiSongPro", "7.1 MB"),
        (.kaiti, "楷體", .kai, .system, "STKaitiTC-Bold", "66.1 MB"),
        (.biauKai, "標楷體", .kai, .system, "BiauKaiTC-Regular", "17.8 MB"),
        (.hanziPen, "翩翩體", .handwriting, .system, "HanziPenTC-W5", "48.7 MB"),
        (.hannotate, "手札體", .handwriting, .system, "HannotateTC-W7", "50.0 MB"),
        (.lingWai, "凌慧體", .handwriting, .system, "MLingWaiMedium-TC", "18.4 MB"),
        (.xingkai, "行楷", .calligraphy, .system, "STXingkaiTC-Bold", "54.8 MB"),
        (.weibei, "魏碑", .calligraphy, .system, "WeibeiTC-Bold", "11.0 MB"),
        (.libian, "隸變", .calligraphy, .system, "STLibianTC-Regular", "21.6 MB"),
        (.baoli, "報隸", .calligraphy, .system, "STBaoliTC-Regular", "25.6 MB"),
        (.wawa, "娃娃體", .cute, .system, "DFWaWaTC-W5", "11.6 MB"),
        (.yuppy, "雅痞", .cute, .system, "YuppyTC-Regular", "12.9 MB")
    ]

    /// 32.1 / 40.1: 22 fonts; order, names, sections, sources, PostScript
    /// names and sizes as in PRD 0.3 §4.1 with TASK-40's 辰宇落雁體 after 芫荽.
    func testCatalogMatchesPRDTableInOrder() {
        XCTAssertEqual(OverlayFontID.allCases.count, 22, "40.1")
        XCTAssertEqual(OverlayFontID.allCases, table.map(\.0), "32.1 order")
        XCTAssertEqual(FontCatalog.entries.map(\.fontID), table.map(\.0), "32.1 catalog order")
        for (fontID, name, section, source, postScriptName, size) in table {
            let entry = FontCatalog.entry(for: fontID)
            XCTAssertEqual(entry.fontID, fontID)
            XCTAssertEqual(entry.displayName, name, "32.1 \(fontID)")
            XCTAssertEqual(fontID.displayName, name, "32.1 \(fontID)")
            XCTAssertEqual(entry.section, section, "32.1 \(fontID)")
            XCTAssertEqual(entry.source, source, "32.1 \(fontID)")
            XCTAssertEqual(entry.postScriptName, postScriptName, "32.1 \(fontID)")
            XCTAssertEqual(fontID.postScriptName, postScriptName, "32.1 \(fontID)")
            XCTAssertEqual(entry.downloadSizeText, size, "32.1 \(fontID)")
            XCTAssertEqual(entry.openSource != nil, source == .openSource, "only open-source fonts carry assets")
        }
    }

    /// FR-16.2: sections in list order, each with its heading, and fonts
    /// grouped contiguously in that order.
    func testSectionsAreInListOrderAndContiguous() {
        XCTAssertEqual(FontSection.allCases.map(\.title),
                       ["內建", "可下載", "黑", "圓", "宋", "楷", "手寫", "書法", "可愛"])
        var seen: [FontSection] = []
        for entry in FontCatalog.entries where seen.last != entry.section {
            seen.append(entry.section)
        }
        XCTAssertEqual(seen, FontSection.allCases)
    }

    /// 40.1: the open-source section is four fonts, contiguous, 辰宇落雁體 last.
    func testOpenSourceSectionIsFourContiguousFonts() {
        let ids = FontCatalog.entries.map(\.fontID)
        let openSource = FontCatalog.entries.filter { $0.section == .openSource }.map(\.fontID)
        XCTAssertEqual(openSource, [.huninn, .notoSerifTC, .iansui, .chenyuluoyan], "40.1")
        XCTAssertEqual(Array(ids[1...4]), openSource, "40.1 contiguous, right after 蘋方")
        XCTAssertEqual(ids[5], .lantinghei, "40.1 蘭亭黑 follows 辰宇落雁體")
    }

    /// 32.9: open-source sizes, SHA-256, versions and copyright notices as in
    /// `docs/fonts-manifest.md` (TASK-31, merged in #196).
    func testOpenSourceAssetsMatchTheManifest() throws {
        let huninn = try XCTUnwrap(FontCatalog.entry(for: .huninn).openSource)
        XCTAssertEqual(huninn.fileName, "jf-openhuninn-2.1.ttf")
        XCTAssertEqual(huninn.repositoryPath, "huninn/jf-openhuninn-2.1.ttf")
        XCTAssertEqual(huninn.byteCount, 4_911_464, "32.9")
        XCTAssertEqual(huninn.sha256, "9d5bf4932d31fe94c18cd8cfddc98bc1b14ce10f4e354c682179db290a99c825", "32.9")
        XCTAssertEqual(huninn.version, "2.1", "32.9")
        XCTAssertEqual(huninn.copyright, """
            [Kosugi Maru]
            Copyright (c) 2010 MOTOYA CO.,LTD.

            [Varela Round]
            Copyright (x) 2011-2016 The Varela Round Project Authors \
            (https://github.com/alefalefalef/Varela-Round-Hebrew/), \
            with Reserved Font Names 'Varela' and 'Varela Round'.

            [jf open huninn]
            Copyright (c) 2020-2024 The jf open huninn font is redistributed by justfont Co., Ltd., \
            with Reserved Font Names 'open huninn' and 'huninn' under SIL Open Font License. \
            The Hanzi part of this project was derived from Kosugi Maru under Apache-2.0 \
            (https://www.apache.org/licenses/LICENSE-2.0).
            """, "32.9")
        XCTAssertEqual(huninn.licenseFileNames, ["huninn-OFL.txt", "huninn-Apache-2.0.txt"])

        let noto = try XCTUnwrap(FontCatalog.entry(for: .notoSerifTC).openSource)
        XCTAssertEqual(noto.fileName, "NotoSerifTC-Bold.otf")
        XCTAssertEqual(noto.repositoryPath, "noto-serif-tc/NotoSerifTC-Bold.otf")
        XCTAssertEqual(noto.byteCount, 8_253_304, "32.9")
        XCTAssertEqual(noto.sha256, "3ca2b3294ec84b795d0a45695e78e3612a44dce50f9fc776cd40206340a5768d", "32.9")
        XCTAssertEqual(noto.version, "2.003", "32.9")
        XCTAssertEqual(noto.copyright, "© 2017-2024 Adobe (http://www.adobe.com/).", "32.9")
        XCTAssertEqual(noto.licenseFileNames, ["notoSerifTC-OFL.txt"])

        let iansui = try XCTUnwrap(FontCatalog.entry(for: .iansui).openSource)
        XCTAssertEqual(iansui.fileName, "Iansui-Regular.ttf")
        XCTAssertEqual(iansui.repositoryPath, "iansui/Iansui-Regular.ttf")
        XCTAssertEqual(iansui.byteCount, 9_447_424, "32.9")
        XCTAssertEqual(iansui.sha256, "7f1aa62e9dcbf40d0ce41a5d3f1e5ea602e66c295778ac6fefb6b84d8ed08bd5", "32.9")
        XCTAssertEqual(iansui.version, "1.012", "32.9")
        XCTAssertEqual(iansui.copyright, "Copyright 2025 The Iansui Project Authors (https://github.com/ButTaiwan/iansui)",
                       "32.9")
        XCTAssertEqual(iansui.licenseFileNames, ["iansui-OFL.txt"])
    }

    /// 40.2: 辰宇落雁體's path, size, SHA-256, PostScript name, version and
    /// copyright as on TASK-40 (Issue #219).
    func testChenyuluoyanAssetMatchesTheCard() throws {
        let entry = FontCatalog.entry(for: .chenyuluoyan)
        XCTAssertEqual(entry.postScriptName, "ChenYuluoyan-2.0-Thin", "40.2")
        let asset = try XCTUnwrap(entry.openSource)
        XCTAssertEqual(asset.fileName, "ChenYuluoyan-2.0-Thin.ttf", "40.2")
        XCTAssertEqual(asset.repositoryPath, "chenyuluoyan/ChenYuluoyan-2.0-Thin.ttf", "40.2")
        XCTAssertEqual(asset.byteCount, 9_522_140, "40.2")
        XCTAssertEqual(asset.sha256, "1289e42a6d1ec995d0cb23aee89efc69fc95749fbd54a610057a3e992dc453db", "40.2")
        XCTAssertEqual(asset.version, "2.100", "40.2")
        XCTAssertEqual(asset.copyright,
                       "Copyright (c) 2022, Wang, Li-Yu & Liu, Wei-Chen.\n(c) 2022 王立宇、劉韋辰 版權所有。", "40.2")
        XCTAssertEqual(asset.licenseFileNames, ["chenyuluoyan-OFL.txt"])
        XCTAssertEqual(asset.primaryURL.absoluteString,
                       "https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v3/chenyuluoyan/ChenYuluoyan-2.0-Thin.ttf",
                       "40.2")
        XCTAssertEqual(asset.fallbackURL.absoluteString,
                       "https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v3/chenyuluoyan/ChenYuluoyan-2.0-Thin.ttf",
                       "40.2")
    }

    /// 40.3: the license file ships in the App and is the OFL 1.1 text for
    /// Chenyuluoyan.
    func testChenyuluoyanLicenseShipsInTheApp() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "chenyuluoyan-OFL", withExtension: "txt"), "40.3")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("SIL Open Font License, Version 1.1"), "40.3")
        XCTAssertTrue(text.contains("Chenyuluoyan"), "40.3")
    }

    /// Every license file the catalog names ships in the App bundle (TASK-31).
    func testLicenseFilesShipInTheApp() {
        for entry in FontCatalog.entries {
            for name in entry.openSource?.licenseFileNames ?? [] {
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                XCTAssertNotNil(Bundle.main.url(forResource: base, withExtension: ext), "\(entry.fontID): \(name)")
            }
        }
    }

    /// A-2: jsDelivr first, GitHub raw second, both on the fixed tag
    /// (`v3` since TASK-91, 91.1).
    func testOpenSourceURLsPointAtTheFixedTag() throws {
        let asset = try XCTUnwrap(FontCatalog.entry(for: .notoSerifTC).openSource)
        XCTAssertEqual(asset.primaryURL.absoluteString,
                       "https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v3/noto-serif-tc/NotoSerifTC-Bold.otf")
        XCTAssertEqual(asset.fallbackURL.absoluteString,
                       "https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v3/noto-serif-tc/NotoSerifTC-Bold.otf")
        XCTAssertEqual(asset.fileExtension, "otf")
        XCTAssertEqual(FontCatalog.entries.compactMap(\.openSource).count, 4, "40.2")
        for entry in FontCatalog.entries {
            guard let asset = entry.openSource else { continue }
            XCTAssertEqual(asset.primaryURL.absoluteString,
                           "https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v3/\(asset.repositoryPath)",
                           "40.2 \(entry.fontID)")
            XCTAssertEqual(asset.fallbackURL.absoluteString,
                           "https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v3/\(asset.repositoryPath)",
                           "40.2 \(entry.fontID)")
            XCTAssertTrue(asset.primaryURL.absoluteString.hasSuffix(asset.repositoryPath), "\(entry.fontID)")
            XCTAssertTrue(asset.fallbackURL.absoluteString.hasSuffix(asset.repositoryPath), "\(entry.fontID)")
            XCTAssertEqual(asset.primaryURL.lastPathComponent, asset.fileName, "\(entry.fontID)")
            XCTAssertEqual(asset.sha256.count, 64, "\(entry.fontID)")
            // §4.1 lists the open-source sizes as these byte counts in MB.
            XCTAssertEqual(entry.downloadSizeText, String(format: "%.1f MB", Double(asset.byteCount) / 1_000_000))
        }
    }
}
