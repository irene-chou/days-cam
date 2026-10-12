import UIKit
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

    /// 91.1 / 91.2 / 142.2: every weight's open-source asset, including Noto
    /// Regular and Black and the 63 TASK-142 faces, downloads from
    /// `dayscam-fonts@v4`; no upstream URL remains.
    func testEveryWeightAssetDownloadsFromTheV4Tag() {
        let assets = FontCatalog.entries.flatMap { $0.weights.compactMap(\.openSource) }
        XCTAssertEqual(assets.count, 69, "91.1 / 142.2")
        for asset in assets {
            XCTAssertEqual(asset.primaryURL.absoluteString,
                           "https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v4/\(asset.repositoryPath)",
                           "91.1 \(asset.fileName)")
            XCTAssertEqual(asset.fallbackURL.absoluteString,
                           "https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v4/\(asset.repositoryPath)",
                           "91.1 \(asset.fileName)")
            XCTAssertFalse(asset.primaryURL.absoluteString.contains("notofonts"), "91.1 \(asset.fileName)")
            XCTAssertFalse(asset.fallbackURL.absoluteString.contains("notofonts"), "91.1 \(asset.fileName)")
        }
        let notoPaths = FontCatalog.entry(for: .notoSerifTC).weights.compactMap(\.openSource?.repositoryPath)
        XCTAssertEqual(notoPaths, ["noto-serif-tc/NotoSerifTC-Regular.otf",
                                   "noto-serif-tc/NotoSerifTC-Bold.otf",
                                   "noto-serif-tc/NotoSerifTC-Black.otf"], "91.1")
    }

    /// TASK-148: the list, VoiceOver and the previews use the short Chinese
    /// name, never the name table's full face name ("-繁", "Bold", "W6", "Pro"...).
    func testDisplayNamesAreTheShortChineseNames() {
        for entry in FontCatalog.entries {
            let name = entry.displayName
            XCTAssertFalse(name.isEmpty, "\(entry.fontID)")
            for noise in ["-繁", "Bold", "Regular", "W6", "粗體", "標準體", "中黑", " Pro"] {
                XCTAssertFalse(name.contains(noise), "148.3 \(entry.fontID) 的簡稱不該帶「\(noise)」：\(name)")
            }
        }
        let expected: [OverlayFontID: String] = [
            .pingFang: "蘋方", .notoSerifTC: "思源宋體", .notoSansTC: "思源黑體", .genSeki: "源石黑體",
            .kaiti: "楷體", .songti: "宋體", .biauKai: "標楷體", .huninn: "粉圓",
        ]
        for (fontID, name) in expected {
            XCTAssertEqual(FontCatalog.entry(for: fontID).displayName, name, "148.3")
        }
    }

    /// 148.2: every font has its preview image, so no row falls back to text.
    func testEveryFontHasAPreviewImage() {
        for fontID in OverlayFontID.allCases {
            XCTAssertNotNil(UIImage(named: fontID.rawValue), "148.2 \(fontID) 缺預覽圖")
        }
    }

    /// PRD 0.3 §4.1, row by row: ID, name, section, source, PostScript, size.
    private let table: [(OverlayFontID, String, FontStyleCategory, FontSource, String, String?)] = [
        (.pingFang, "蘋方", .hei, .builtIn, "PingFangTC-Semibold", nil),
        (.huninn, "粉圓", .yuan, .openSource, "jf-openhuninn-2.1", "4.9 MB"),
        (.notoSerifTC, "思源宋體", .song, .openSource, "NotoSerifTC-Bold", "8.3 MB"),
        (.iansui, "芫荽", .kai, .openSource, "Iansui-Regular", "9.4 MB"),
        (.chenyuluoyan, "辰宇落雁體", .handwriting, .openSource, "ChenYuluoyan-2.0-Thin", "9.5 MB"),
        (.notoSansTC, "思源黑體", .hei, .openSource, "NotoSansTC-Bold", "5.8 MB"),
        (.taipeiSans, "台北黑體", .hei, .openSource, "TaipeiSansTCBeta-Bold", "21.7 MB"),
        (.genSeki, "源石黑體", .hei, .openSource, "GenSekiGothic2TW-B", "15.0 MB"),
        (.chironHei, "昭源黑體", .hei, .openSource, "ChironHeiHK-Bold", "17.1 MB"),
        (.chocolateSans, "朱古力黑體", .hei, .openSource, "ChocolateClassicalSans-Regular", "12.2 MB"),
        (.glowSans, "未來熒黑", .hei, .openSource, "GlowSansTC-Normal-Bold", "9.0 MB"),
        (.genSen, "源泉圓體", .yuan, .openSource, "GenSenRounded2TW-B", "15.8 MB"),
        (.sweiGothic, "獅尾圓體", .yuan, .openSource, "SweiGothicCJKtc-Bold", "15.8 MB"),
        (.chironGoRound, "昭源環方", .yuan, .openSource, "ChironGoRoundTC-Bold", "20.5 MB"),
        (.genWan, "源雲明體", .song, .openSource, "GenWanMin2TW-SB", "22.6 MB"),
        (.genRyu, "源流明體", .song, .openSource, "GenRyuMin2TW-B", "16.2 MB"),
        (.sweiSpring, "獅尾四季春", .song, .openSource, "SweiSpringCJKtc-Bold", "17.3 MB"),
        (.sweiSugar, "獅尾加糖宋體", .song, .openSource, "SweiSugarCJKtc-Bold", "29.0 MB"),
        (.chironSung, "昭源宋體", .song, .openSource, "ChironSungHK-Bold", "26.6 MB"),
        (.cactusSerif, "仙人掌明體", .song, .openSource, "CactusClassicalSerif-Regular", "28.5 MB"),
        (.twSung, "全字庫正宋體", .song, .openSource, "TW-Sung-98_1", "35.3 MB"),
        (.thenKhung, "宇文天穹", .song, .openSource, "UoqMunThenKhung-Regular", "4.9 MB"),
        (.lxgwWenKai, "霞鶩文楷 TC", .kai, .openSource, "LXGWWenKaiTC-Medium", "15.0 MB"),
        (.twKai, "全字庫正楷體", .kai, .openSource, "TW-Kai-98_1", "36.9 MB"),
        (.eduKai, "教育部標準楷書", .kai, .openSource, "TW-MOE-Std-Kai", "15.8 MB"),
        (.arphicUKai, "文鼎 PL 中楷", .kai, .openSource, "UKaiTW", "17.2 MB"),
        (.naikai, "內海字體", .handwriting, .openSource, "NaikaiFont-Bold", "38.6 MB"),
        (.xiaolai, "小賴字體", .handwriting, .openSource, "Xiaolai", "22.2 MB"),
        (.yozai, "悠哉字體", .handwriting, .openSource, "Yozai-Medium", "15.2 MB"),
        (.nani, "何某手寫體", .handwriting, .openSource, "NaniFont-Bold", "18.5 MB"),
        (.lxgwMarker, "霞鶩漫黑", .handwriting, .openSource, "LXGWMarkerGothic-Regular", "3.2 MB"),
        (.kurewa, "苦累蛙圓體", .handwriting, .openSource, "KurewaGothicCjkTc-Bold", "36.5 MB"),
        (.popGothic, "大波浪圓體", .cute, .openSource, "PopGothicCjkTc-Bold", "10.3 MB"),
        (.wdxl, "WD-XL 滑油字", .cute, .openSource, "WD-XLLubrifontTC-Regular", "6.2 MB"),
        (.cubic11, "俐方體 11 號", .cute, .openSource, "Cubic_11", "2.8 MB"),
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

    /// 32.1 / 40.1 / 142.1: 52 fonts; order, names, sections, sources,
    /// PostScript names and sizes as in PRD 0.3 §4.1 with TASK-40's 辰宇落雁體
    /// after 芫荽 and TASK-142's 30 families after it, in type order.
    func testCatalogMatchesPRDTableInOrder() {
        XCTAssertEqual(OverlayFontID.allCases.count, 52, "40.1 / 142.1")
        XCTAssertEqual(OverlayFontID.allCases, table.map(\.0), "32.1 order")
        XCTAssertEqual(FontCatalog.entries.map(\.fontID), table.map(\.0), "32.1 catalog order")
        for (fontID, name, category, source, postScriptName, size) in table {
            let entry = FontCatalog.entry(for: fontID)
            XCTAssertEqual(entry.fontID, fontID)
            XCTAssertEqual(entry.displayName, name, "32.1 \(fontID)")
            XCTAssertEqual(fontID.displayName, name, "32.1 \(fontID)")
            XCTAssertEqual(entry.category, category, "120 \(fontID)")
            XCTAssertEqual(entry.source, source, "32.1 \(fontID)")
            XCTAssertEqual(entry.postScriptName, postScriptName, "32.1 \(fontID)")
            XCTAssertEqual(fontID.postScriptName, postScriptName, "32.1 \(fontID)")
            XCTAssertEqual(entry.downloadSizeText, size, "32.1 \(fontID)")
            XCTAssertEqual(entry.openSource != nil, source == .openSource, "only open-source fonts carry assets")
        }
    }

    /// TASK-120: the list headings come from the source, the type only orders.
    func testHeadingsAndCategoryOrder() {
        XCTAssertEqual([FontSource.builtIn, .openSource, .system].map(\.listTitle), [nil, "開源字型", "系統字型"], "120.1")
        XCTAssertEqual(FontStyleCategory.allCases.map(\.title),
                       ["黑", "圓", "宋", "楷", "手寫", "書法", "可愛"], "120 類型順序")
    }

    /// TASK-120: the list order is computed from source and type, not from
    /// how the catalog array is arranged.
    func testListOrderedSortsBySourceThenCategoryThenCatalogOrder() {
        let entries = FontCatalog.entries
        let expected = entries.sorted { lhs, rhs in
            (lhs.source.listRank, FontStyleCategory.allCases.firstIndex(of: lhs.category)!)
                < (rhs.source.listRank, FontStyleCategory.allCases.firstIndex(of: rhs.category)!)
        }
        XCTAssertEqual(FontCatalog.listOrdered(entries).map(\.fontID).first, .pingFang)
        // Shuffling the input only changes the order of fonts of equal source and type.
        let ordered = FontCatalog.listOrdered(entries.reversed())
        XCTAssertEqual(ordered.map { [$0.source.listRank, FontStyleCategory.allCases.firstIndex(of: $0.category)!] },
                       expected.map { [$0.source.listRank, FontStyleCategory.allCases.firstIndex(of: $0.category)!] })
    }

    /// 40.1 / 142.1 / 120: the open-source fonts are the four original ones
    /// and the 30 TASK-142 families, each with a category.
    func testOpenSourceFontsAreThirtyFourWithTheirCategories() {
        let openSource = FontCatalog.entries.filter { $0.source == .openSource }.map(\.fontID)
        XCTAssertEqual(openSource.count, 34, "142.1")
        XCTAssertEqual(Array(openSource.prefix(4)), [.huninn, .notoSerifTC, .iansui, .chenyuluoyan], "40.1")
        XCTAssertEqual(Array(openSource.dropFirst(4)), FontCatalog.downloadFamilies.map(\.fontID), "142.1")
        XCTAssertEqual(openSource.prefix(4).map { FontCatalog.entry(for: $0).category },
                       [.yuan, .song, .kai, .handwriting], "120 四套原開源字型的類型")
        for family in FontCatalog.downloadFamilies {
            XCTAssertEqual(FontCatalog.entry(for: family.fontID).category, family.category, "\(family.fontID)")
        }
        XCTAssertEqual(FontCatalog.entries.count, 52)
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
                       "https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v4/chenyuluoyan/ChenYuluoyan-2.0-Thin.ttf",
                       "40.2")
        XCTAssertEqual(asset.fallbackURL.absoluteString,
                       "https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v4/chenyuluoyan/ChenYuluoyan-2.0-Thin.ttf",
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
    /// (`v3` since TASK-91, `v4` since TASK-142; `v4` holds every `v3` file).
    func testOpenSourceURLsPointAtTheFixedTag() throws {
        let asset = try XCTUnwrap(FontCatalog.entry(for: .notoSerifTC).openSource)
        XCTAssertEqual(asset.primaryURL.absoluteString,
                       "https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v4/noto-serif-tc/NotoSerifTC-Bold.otf")
        XCTAssertEqual(asset.fallbackURL.absoluteString,
                       "https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v4/noto-serif-tc/NotoSerifTC-Bold.otf")
        XCTAssertEqual(asset.fileExtension, "otf")
        XCTAssertEqual(FontCatalog.entries.compactMap(\.openSource).count, 34, "40.2 / 142.1")
        for entry in FontCatalog.entries {
            guard let asset = entry.openSource else { continue }
            XCTAssertEqual(asset.primaryURL.absoluteString,
                           "https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v4/\(asset.repositoryPath)",
                           "40.2 \(entry.fontID)")
            XCTAssertEqual(asset.fallbackURL.absoluteString,
                           "https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v4/\(asset.repositoryPath)",
                           "40.2 \(entry.fontID)")
            XCTAssertTrue(asset.primaryURL.absoluteString.hasSuffix(asset.repositoryPath), "\(entry.fontID)")
            XCTAssertTrue(asset.fallbackURL.absoluteString.hasSuffix(asset.repositoryPath), "\(entry.fontID)")
            XCTAssertEqual(asset.primaryURL.lastPathComponent, asset.fileName, "\(entry.fontID)")
            XCTAssertEqual(asset.sha256.count, 64, "\(entry.fontID)")
            // §4.1 lists the open-source sizes as these byte counts in MB.
            XCTAssertEqual(entry.downloadSizeText, String(format: "%.1f MB", Double(asset.byteCount) / 1_000_000))
        }
    }

    // MARK: - 133.1

    /// The cached table returns exactly what a fresh build does, for every font.
    func testCachedEntriesMatchFreshlyBuiltEntries() {
        for fontID in OverlayFontID.allCases {
            XCTAssertEqual(FontCatalog.entry(for: fontID), FontCatalog.makeEntry(for: fontID), "133.1 \(fontID)")
        }
        XCTAssertEqual(FontCatalog.entriesByID.count, OverlayFontID.allCases.count)
        XCTAssertEqual(FontCatalog.entries, OverlayFontID.allCases.map(FontCatalog.makeEntry(for:)))
    }
}
