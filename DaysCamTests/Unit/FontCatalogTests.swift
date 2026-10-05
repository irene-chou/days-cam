import XCTest
@testable import DaysCam

/// Covers TASK-32 32.1 and 32.9: the 21 fonts of PRD 0.3 §4.1 and the
/// open-source download facts of `docs/fonts-manifest.md`.
///
/// Expected values are written out here, independently of `FontCatalog`, so a
/// wrong catalog value cannot pass itself.
final class FontCatalogTests: XCTestCase {

    /// PRD 0.3 §4.1, row by row: ID, name, section, source, PostScript, size.
    private let table: [(OverlayFontID, String, FontSection, FontSource, String, String?)] = [
        (.pingFang, "蘋方", .builtIn, .builtIn, "PingFangTC-Semibold", nil),
        (.huninn, "粉圓", .openSource, .openSource, "jf-openhuninn-2.1", "4.9 MB"),
        (.notoSerifTC, "思源宋體", .openSource, .openSource, "NotoSerifTC-Bold", "8.3 MB"),
        (.iansui, "芫荽", .openSource, .openSource, "Iansui-Regular", "9.4 MB"),
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

    /// 32.1: 21 fonts; order, names, sections, sources, PostScript names and
    /// sizes as in PRD 0.3 §4.1.
    func testCatalogMatchesPRDTableInOrder() {
        XCTAssertEqual(OverlayFontID.allCases.count, 21, "32.1")
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
                       ["內建", "開源", "黑", "圓", "宋", "楷", "手寫", "書法", "可愛"])
        var seen: [FontSection] = []
        for entry in FontCatalog.entries where seen.last != entry.section {
            seen.append(entry.section)
        }
        XCTAssertEqual(seen, FontSection.allCases)
    }

    /// 32.9: open-source sizes, SHA-256, versions and copyright notices as in
    /// `docs/fonts-manifest.md` (TASK-31, #196 at 33f5809).
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

    /// A-2: jsDelivr first, GitHub raw second, both on the fixed tag.
    func testOpenSourceURLsPointAtTheFixedTag() throws {
        let asset = try XCTUnwrap(FontCatalog.entry(for: .notoSerifTC).openSource)
        XCTAssertEqual(asset.primaryURL.absoluteString,
                       "https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v1/noto-serif-tc/NotoSerifTC-Bold.otf")
        XCTAssertEqual(asset.fallbackURL.absoluteString,
                       "https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v1/noto-serif-tc/NotoSerifTC-Bold.otf")
        XCTAssertEqual(asset.fileExtension, "otf")
        for entry in FontCatalog.entries {
            guard let asset = entry.openSource else { continue }
            XCTAssertTrue(asset.primaryURL.absoluteString.hasSuffix(asset.repositoryPath), "\(entry.fontID)")
            XCTAssertTrue(asset.fallbackURL.absoluteString.hasSuffix(asset.repositoryPath), "\(entry.fontID)")
            XCTAssertEqual(asset.primaryURL.lastPathComponent, asset.fileName, "\(entry.fontID)")
            XCTAssertEqual(asset.sha256.count, 64, "\(entry.fontID)")
            // §4.1 lists the open-source sizes as these byte counts in MB.
            XCTAssertEqual(entry.downloadSizeText, String(format: "%.1f MB", Double(asset.byteCount) / 1_000_000))
        }
    }
}
