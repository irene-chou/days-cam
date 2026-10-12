import Foundation

/// The open-source families TASK-142 (#494) added to the library: 30 fonts
/// researched in `docs/research/fonts-tc-2.md` (TASK-121), each with one to
/// three faces. Values are written out from `docs/fonts-manifest.md`; change
/// both together.
///
/// A family's `category` is the type it sorts under (黑 圓 宋 楷 手寫 可愛).
/// It is kept here until the library groups open-source fonts by type
/// (TASK-120, #453), which will move it onto `FontCatalogEntry`.
extension FontCatalog {
    /// One downloadable face of a family.
    struct DownloadFace: Equatable, Sendable {
        /// The face ID stored in profiles (`FontWeightOption.id`).
        let id: String
        /// The weight name shown on the button, e.g. "粗".
        let weightName: String
        let postScriptName: String
        let asset: OpenSourceFontAsset
    }

    /// A downloadable family: its type, the face a new selection starts with
    /// and the faces in picker order.
    struct DownloadFamily: Equatable, Sendable {
        let fontID: OverlayFontID
        let displayName: String
        let category: FontSection
        /// The face's full name from the font's name table, Traditional Chinese
        /// record first, version dropped (PRD-0.3 FR-16.4, TASK-78): the list
        /// row, VoiceOver and the preview image of a single-weight font.
        let fullName: String
        /// The family name from the name table, for a row with several weights.
        let listName: String
        let defaultWeightID: String
        /// Source and attribution the license page shows under the name, for
        /// fonts whose license asks for it (全字庫, 教育部標準楷書, 文鼎 PL 中楷).
        let sourceNote: String?
        let faces: [DownloadFace]

        /// The face a new selection starts with.
        var defaultFace: DownloadFace {
            // `family(...)` guarantees the default ID names a face.
            faces.first { $0.id == defaultWeightID } ?? faces[0]
        }
    }

    /// The families by font ID.
    static let downloadFamiliesByID: [OverlayFontID: DownloadFamily] =
        Dictionary(uniqueKeysWithValues: downloadFamilies.map { ($0.fontID, $0) })

    /// The catalog entry of a family, with its faces as weight options.
    static func downloadFamilyEntry(for fontID: OverlayFontID) -> FontCatalogEntry {
        guard let family = downloadFamiliesByID[fontID] else {
            preconditionFailure("FontCatalog: no download family for \(fontID)")
        }
        let defaultFace = family.defaultFace
        let weights = family.faces.map {
            FontWeightOption(id: $0.id, displayName: $0.weightName, postScriptName: $0.postScriptName,
                             downloadSizeMegabytes: Double($0.asset.byteCount) / 1_000_000, openSource: $0.asset)
        }
        return FontCatalogEntry(fontID: fontID, displayName: family.displayName, section: .openSource,
                                source: .openSource, postScriptName: defaultFace.postScriptName,
                                downloadSizeMegabytes: Double(defaultFace.asset.byteCount) / 1_000_000,
                                openSource: defaultFace.asset, weights: weights)
    }

    private static func family(_ fontID: OverlayFontID, _ displayName: String, _ category: FontSection,
                               fullName: String, listName: String, defaultWeight: String, sourceNote: String? = nil,
                               faces: [DownloadFace]) -> DownloadFamily {
        precondition(faces.contains { $0.id == defaultWeight }, "\(fontID): default weight is not a face")
        return DownloadFamily(fontID: fontID, displayName: displayName, category: category,
                              fullName: fullName, listName: listName, defaultWeightID: defaultWeight, sourceNote: sourceNote, faces: faces)
    }

    private static func face(_ id: String, _ weightName: String, _ postScriptName: String,
                             path: String, bytes: Int, sha256: String, version: String,
                             copyright: String, licenses: [String]) -> DownloadFace {
        DownloadFace(id: id, weightName: weightName, postScriptName: postScriptName,
                     asset: asset(path: path, byteCount: bytes, sha256: sha256, version: version,
                                  copyright: copyright, licenseFileNames: licenses))
    }

    // MARK: - Families (docs/fonts-manifest.md)

    static let downloadFamilies: [DownloadFamily] = [
        family(.notoSansTC, "思源黑體", .hei, fullName: "Noto Sans TC Bold", listName: "Noto Sans TC", defaultWeight: "bold", faces: [
            face("regular", "標準", "NotoSansTC-Regular",
                 path: "noto-sans-tc/NotoSansTC-Regular.otf", bytes: 5_683_368,
                 sha256: "5bab0cb3c1cf89dde07c4a95a4054b195afbcfe784d69d75c340780712237537",
                 version: "2.004",
                 copyright: "© 2014-2021 Adobe (http://www.adobe.com/).",
                 licenses: ["notoSansTC-OFL.txt"]),
            face("bold", "粗", "NotoSansTC-Bold",
                 path: "noto-sans-tc/NotoSansTC-Bold.otf", bytes: 5_839_972,
                 sha256: "55420b259eb119bf5f2a0aadba10cf9d736c12d64ab93e78546d69ef5f43558b",
                 version: "2.004",
                 copyright: "© 2014-2021 Adobe (http://www.adobe.com/).",
                 licenses: ["notoSansTC-OFL.txt"]),
            face("black", "特粗", "NotoSansTC-Black",
                 path: "noto-sans-tc/NotoSansTC-Black.otf", bytes: 6_068_384,
                 sha256: "3280b221ab7b011c6ae48d38388a0e8c72ddf479992bce62ff589ae932819ce4",
                 version: "2.004",
                 copyright: "© 2014-2021 Adobe (http://www.adobe.com/).",
                 licenses: ["notoSansTC-OFL.txt"])
        ]),
        family(.taipeiSans, "台北黑體", .hei, fullName: "Taipei Sans TC Beta Bold", listName: "Taipei Sans TC Beta", defaultWeight: "bold", faces: [
            face("light", "細", "TaipeiSansTCBeta-Light",
                 path: "taipei-sans-tc/TaipeiSansTCBeta-Light.ttf", bytes: 20_279_264,
                 sha256: "d69a9ea6a77f694c3a1a1fb766c764aa74cb3e2c4c69f1b532edf98b3f2bb662",
                 version: "1.000",
                 copyright: "Taipei Sans TC is a modified font of Source Han Sans'.",
                 licenses: ["taipeiSans-OFL.txt"]),
            face("regular", "標準", "TaipeiSansTCBeta-Regular",
                 path: "taipei-sans-tc/TaipeiSansTCBeta-Regular.ttf", bytes: 20_659_344,
                 sha256: "8cc967e1e428c552701c461e8169e6ae76c7a23694ea1a6a786d6746adec53c4",
                 version: "1.000",
                 copyright: "Taipei Sans TC is a modified font of Source Han Sans.",
                 licenses: ["taipeiSans-OFL.txt"]),
            face("bold", "粗", "TaipeiSansTCBeta-Bold",
                 path: "taipei-sans-tc/TaipeiSansTCBeta-Bold.ttf", bytes: 21_737_516,
                 sha256: "5249d3bdda9c9f4c62840e804b4d2530b7f4dfab6d68fb508c120b0e7e600419",
                 version: "1.000",
                 copyright: "Taipei Sans TC Beta is a modified font of Source Han Sans.",
                 licenses: ["taipeiSans-OFL.txt"])
        ]),
        family(.genSeki, "源石黑體", .hei, fullName: "源石黑體月 B", listName: "源石黑體月", defaultWeight: "bold", faces: [
            face("regular", "標準", "GenSekiGothic2TW-R",
                 path: "gen-seki-gothic/GenSekiGothic2TW-R.otf", bytes: 16_501_448,
                 sha256: "bb3cccb9594a5a9c759a92bbbf147eb87826b8317d07d20f48ee7ebdcec684fa",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genSeki-OFL.txt"]),
            face("bold", "粗", "GenSekiGothic2TW-B",
                 path: "gen-seki-gothic/GenSekiGothic2TW-B.otf", bytes: 15_017_684,
                 sha256: "911bc231c346f1e377796ccd1b85959184a547d1fce356da882a2f1abb9bfaa4",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genSeki-OFL.txt"]),
            face("black", "特粗", "GenSekiGothic2TW-H",
                 path: "gen-seki-gothic/GenSekiGothic2TW-H.otf", bytes: 14_691_360,
                 sha256: "87880818a93362d11b4c07f9612993deeeb1a0800b1779a31bea197e4c8109f2",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genSeki-OFL.txt"])
        ]),
        family(.chironHei, "昭源黑體", .hei, fullName: "Chiron Hei HK Bold", listName: "Chiron Hei HK", defaultWeight: "bold", faces: [
            face("regular", "標準", "ChironHeiHK-Regular",
                 path: "chiron-hei-hk/ChironHeiHK-R.otf", bytes: 16_164_592,
                 sha256: "72f68279a78a118b469bc683a1ab12364a5a3c244ee592da441d4a3cb0eda4b1",
                 version: "2.609",
                 copyright: "© 2014-2025 Adobe (http://www.adobe.com/).",
                 licenses: ["chironHei-OFL.txt"]),
            face("bold", "粗", "ChironHeiHK-Bold",
                 path: "chiron-hei-hk/ChironHeiHK-B.otf", bytes: 17_083_396,
                 sha256: "51a6c39f8dd0a4522a7c5d366d77e9e52aebe4280d9b16ed95f03288c802e821",
                 version: "2.609",
                 copyright: "© 2014-2025 Adobe (http://www.adobe.com/).",
                 licenses: ["chironHei-OFL.txt"]),
            face("black", "特粗", "ChironHeiHK-Heavy",
                 path: "chiron-hei-hk/ChironHeiHK-H.otf", bytes: 16_828_836,
                 sha256: "1dc39f1d97c9bdba16fef81f08be56c96eeb702aca03f4f5b8498c6bc4e385d4",
                 version: "2.609",
                 copyright: "© 2014-2025 Adobe (http://www.adobe.com/).",
                 licenses: ["chironHei-OFL.txt"])
        ]),
        family(.chocolateSans, "朱古力黑體", .hei, fullName: "朱古力黑體", listName: "朱古力黑體", defaultWeight: "regular", faces: [
            face("regular", "標準", "ChocolateClassicalSans-Regular",
                 path: "chocolate-classical-sans/ChocolateClassicalSans-Regular.ttf", bytes: 12_183_000,
                 sha256: "e6345f3d92c7a9b7044c31a87d9b61f50220b08c0f1dcc2736e94c2aa587ce03",
                 version: "1.005",
                 copyright: "Copyright 2025 The Chocolate Classical Sans Project Authors (https://github.com/MoonlitOwen/ChocolateSans)",
                 licenses: ["chocolateSans-OFL.txt"])
        ]),
        family(.glowSans, "未來熒黑", .hei, fullName: "未來熒黑 Normal Bold", listName: "未來熒黑", defaultWeight: "bold", faces: [
            face("regular", "標準", "GlowSansTC-Normal-Regular",
                 path: "glow-sans-tc/GlowSansTC-Normal-Regular.otf", bytes: 8_926_856,
                 sha256: "cbd6843ab96acc9bb92048dd426232ece37f79068cc9e48c40e8d48e9fd0ee59",
                 version: "0.93",
                 copyright: "Glow Sans (c) 2021 Project Welai",
                 licenses: ["glowSans-OFL.txt", "glowSans-MIT.txt"]),
            face("bold", "粗", "GlowSansTC-Normal-Bold",
                 path: "glow-sans-tc/GlowSansTC-Normal-Bold.otf", bytes: 8_995_980,
                 sha256: "8005c40f3777c540ec10ed352793f2a53363a13ec41bc0eeaf18d28e9c8c4312",
                 version: "0.93",
                 copyright: "Glow Sans (c) 2021 Project Welai",
                 licenses: ["glowSans-OFL.txt", "glowSans-MIT.txt"]),
            face("black", "特粗", "GlowSansTC-Normal-Heavy",
                 path: "glow-sans-tc/GlowSansTC-Normal-Heavy.otf", bytes: 9_094_228,
                 sha256: "88ee1042b780005beaa4bbc2bf86cf89a8d0362cfae57b5a9dee7c3887bafbb0",
                 version: "0.93",
                 copyright: "Glow Sans (c) 2021 Project Welai",
                 licenses: ["glowSans-OFL.txt", "glowSans-MIT.txt"])
        ]),
        family(.genSen, "源泉圓體", .yuan, fullName: "源泉圓體月 B", listName: "源泉圓體月", defaultWeight: "bold", faces: [
            face("regular", "標準", "GenSenRounded2TW-R",
                 path: "gen-sen-rounded/GenSenRounded2TW-R.otf", bytes: 16_177_104,
                 sha256: "092285878f1d9441c790e5d6a98e806bd508602ad0a8a55511b6fb0a71a25fed",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genSen-OFL.txt"]),
            face("bold", "粗", "GenSenRounded2TW-B",
                 path: "gen-sen-rounded/GenSenRounded2TW-B.otf", bytes: 15_807_568,
                 sha256: "050f9ebf394faab3c0ba59092ae3e4b6686b349eadb3018d76d385c5829a1267",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genSen-OFL.txt"]),
            face("black", "特粗", "GenSenRounded2TW-H",
                 path: "gen-sen-rounded/GenSenRounded2TW-H.otf", bytes: 15_684_388,
                 sha256: "1088f309fbc3d10d40b2b0e6ef3b965a881066c021f341fd8afd4eb751564ad6",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genSen-OFL.txt"])
        ]),
        family(.sweiGothic, "獅尾圓體", .yuan, fullName: "獅尾圓體-Bold", listName: "獅尾圓體", defaultWeight: "bold", faces: [
            face("regular", "標準", "SweiGothicCJKtc-Regular",
                 path: "swei-gothic/SweiGothicCJKtc-Regular.ttf", bytes: 16_193_916,
                 sha256: "0cb199c63ec23fda70905decf82e1a7f3657092a653323063e9e5f50adfc3f7f",
                 version: "2.143",
                 copyright: "Copyright (c) 2020, Chun yu Yao",
                 licenses: ["sweiGothic-OFL.txt"]),
            face("bold", "粗", "SweiGothicCJKtc-Bold",
                 path: "swei-gothic/SweiGothicCJKtc-Bold.ttf", bytes: 15_757_732,
                 sha256: "d3f03ebd366966c1967879d1b5760e96784e9f7b9bac6e4b5dd364db00a9c128",
                 version: "2.140",
                 copyright: "Copyright (c) 2020, Chun yu Yao",
                 licenses: ["sweiGothic-OFL.txt"]),
            face("black", "特粗", "SweiGothicCJKtc-Black",
                 path: "swei-gothic/SweiGothicCJKtc-Black.ttf", bytes: 14_977_188,
                 sha256: "7376c750c79bf05b14ad8476d2421696fd9b80bdb5b3ad0e7b27c608e9eef9af",
                 version: "2.125",
                 copyright: "Copyright (c) 2020, Chun yu Yao",
                 licenses: ["sweiGothic-OFL.txt"])
        ]),
        family(.chironGoRound, "昭源環方", .yuan, fullName: "Chiron GoRound TC Bold", listName: "Chiron GoRound TC", defaultWeight: "bold", faces: [
            face("regular", "標準", "ChironGoRoundTC-Regular",
                 path: "chiron-go-round-tc/ChironGoRoundTC-400R.otf", bytes: 19_635_772,
                 sha256: "519253233cbca3c2b97b818949e803ccf08f937d75431bedf59e167b00bf4b65",
                 version: "1.011",
                 copyright: "© 2014-2025 Adobe (http://www.adobe.com/).",
                 licenses: ["chironGoRound-OFL.txt"]),
            face("bold", "粗", "ChironGoRoundTC-Bold",
                 path: "chiron-go-round-tc/ChironGoRoundTC-700B.otf", bytes: 20_500_040,
                 sha256: "5ed043b3d1048e4d7868909c6d6fbba2d0cb50773d394003f4fb077a18e2b3fb",
                 version: "1.011",
                 copyright: "© 2014-2025 Adobe (http://www.adobe.com/).",
                 licenses: ["chironGoRound-OFL.txt"]),
            face("black", "特粗", "ChironGoRoundTC-Heavy",
                 path: "chiron-go-round-tc/ChironGoRoundTC-900H.otf", bytes: 19_010_084,
                 sha256: "6989bb7c609805757146ca79765c4b37da2f17de0c808408d6031db49337e64e",
                 version: "1.011",
                 copyright: "© 2014-2025 Adobe (http://www.adobe.com/).",
                 licenses: ["chironGoRound-OFL.txt"])
        ]),
        family(.genWan, "源雲明體", .song, fullName: "源雲明體月 SB", listName: "源雲明體月", defaultWeight: "semibold", faces: [
            face("regular", "標準", "GenWanMin2TW-R",
                 path: "gen-wan-min/GenWanMin2TW-R.otf", bytes: 22_772_928,
                 sha256: "4c1cea221f35ccfd7c27e295238012d3b48e57d149b92b4eb7d71aeb25d798cf",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genWan-OFL.txt"]),
            face("medium", "中粗", "GenWanMin2TW-M",
                 path: "gen-wan-min/GenWanMin2TW-M.otf", bytes: 22_710_256,
                 sha256: "828b83e22e825030204183422701ae42afe24c93b1b131717e7678bd86b57768",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genWan-OFL.txt"]),
            face("semibold", "半粗", "GenWanMin2TW-SB",
                 path: "gen-wan-min/GenWanMin2TW-SB.otf", bytes: 22_614_524,
                 sha256: "86cc4abaec4151b5ad9ac6d39f635c974a2dc4155fe041e6a4fa9730114487d1",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genWan-OFL.txt"])
        ]),
        family(.genRyu, "源流明體", .song, fullName: "源流明體月 B", listName: "源流明體月", defaultWeight: "bold", faces: [
            face("regular", "標準", "GenRyuMin2TW-R",
                 path: "gen-ryu-min/GenRyuMin2TW-R.otf", bytes: 16_449_288,
                 sha256: "d244c6115431b2a18b5dfb0066e08381f56e6a33532915a0f517dd3f7063b646",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genRyu-OFL.txt"]),
            face("bold", "粗", "GenRyuMin2TW-B",
                 path: "gen-ryu-min/GenRyuMin2TW-B.otf", bytes: 16_217_516,
                 sha256: "5e7d2c11cf9860c94ac7d1fba742329f6015f7042c736232e1e69eb8ab12d5da",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genRyu-OFL.txt"]),
            face("black", "特粗", "GenRyuMin2TW-H",
                 path: "gen-ryu-min/GenRyuMin2TW-H.otf", bytes: 16_022_096,
                 sha256: "921295896e780b306d79580a8dcacf8ea6c0e1bd29e1853f3eed18264fa6d44a",
                 version: "2.100",
                 copyright: "Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font\nName 'Source'. Source is a trademark of Adobe in the United States\nand/or other countries.",
                 licenses: ["genRyu-OFL.txt"])
        ]),
        family(.sweiSpring, "獅尾四季春", .song, fullName: "獅尾四季春-Bold", listName: "獅尾四季春", defaultWeight: "bold", faces: [
            face("regular", "標準", "SweiSpringCJKtc-Regular",
                 path: "swei-spring/SweiSpringCJKtc-Regular.ttf", bytes: 17_357_244,
                 sha256: "8278b3f032b7bac5494d28ab1ddbe6b98959142a3e04a2b527c50c654dad6b80",
                 version: "1.068",
                 copyright: "字型檔與授權檔都沒有填寫著作權人（授權檔是未填寫的 SIL OFL 1.1 範本）。作者：Max（https://github.com/max32002/swei-spring）。",
                 licenses: ["sweiSpring-OFL.txt"]),
            face("bold", "粗", "SweiSpringCJKtc-Bold",
                 path: "swei-spring/SweiSpringCJKtc-Bold.ttf", bytes: 17_336_124,
                 sha256: "2bf4d16b849c4a87242c3f38817f18d45cf2a04d244fc3420dd5771d78b078fb",
                 version: "1.068",
                 copyright: "字型檔與授權檔都沒有填寫著作權人（授權檔是未填寫的 SIL OFL 1.1 範本）。作者：Max（https://github.com/max32002/swei-spring）。",
                 licenses: ["sweiSpring-OFL.txt"]),
            face("black", "特粗", "SweiSpringCJKtc-Black",
                 path: "swei-spring/SweiSpringCJKtc-Black.ttf", bytes: 17_730_092,
                 sha256: "7f71afb558abf3b599094119616502a29cdf31a339f8cf2223cec999f8995e56",
                 version: "1.068",
                 copyright: "字型檔與授權檔都沒有填寫著作權人（授權檔是未填寫的 SIL OFL 1.1 範本）。作者：Max（https://github.com/max32002/swei-spring）。",
                 licenses: ["sweiSpring-OFL.txt"])
        ]),
        family(.sweiSugar, "獅尾加糖宋體", .song, fullName: "獅尾加糖宋體-Bold", listName: "獅尾加糖宋體", defaultWeight: "bold", faces: [
            face("regular", "標準", "SweiSugarCJKtc-Regular",
                 path: "swei-sugar/SweiSugarCJKtc-Regular.ttf", bytes: 28_960_864,
                 sha256: "2e930dbafa3f5878df4de9fb773c5a4c9da0b658dd9219d62fd1a928db61447a",
                 version: "1.0",
                 copyright: "字型檔與授權檔都沒有填寫著作權人（授權檔是未填寫的 SIL OFL 1.1 範本）。作者：max32002（https://github.com/max32002/swei-sugar）。",
                 licenses: ["sweiSugar-OFL.txt"]),
            face("bold", "粗", "SweiSugarCJKtc-Bold",
                 path: "swei-sugar/SweiSugarCJKtc-Bold.ttf", bytes: 28_989_908,
                 sha256: "c71c1d5196e49211c5232df39210df2c6fbea0b60245cb8ef9fc7edd37a1a30c",
                 version: "1.0",
                 copyright: "字型檔與授權檔都沒有填寫著作權人（授權檔是未填寫的 SIL OFL 1.1 範本）。作者：max32002（https://github.com/max32002/swei-sugar）。",
                 licenses: ["sweiSugar-OFL.txt"]),
            face("black", "特粗", "SweiSugarCJKtc-Black",
                 path: "swei-sugar/SweiSugarCJKtc-Black.ttf", bytes: 29_001_120,
                 sha256: "f39f956fc4a7f9f6729c62047da0c9376c56653ff7d6912a3b7032c490b449e3",
                 version: "1.0",
                 copyright: "字型檔與授權檔都沒有填寫著作權人（授權檔是未填寫的 SIL OFL 1.1 範本）。作者：max32002（https://github.com/max32002/swei-sugar）。",
                 licenses: ["sweiSugar-OFL.txt"])
        ]),
        family(.chironSung, "昭源宋體", .song, fullName: "Chiron Sung HK Bold", listName: "Chiron Sung HK", defaultWeight: "bold", faces: [
            face("regular", "標準", "ChironSungHK-Regular",
                 path: "chiron-sung-hk/ChironSungHK-R.otf", bytes: 24_164_960,
                 sha256: "d53da9ffb3593a6dcce34f9e4a5d94369c7e619efa1b3d9a60717c7d72aa65d0",
                 version: "1.024",
                 copyright: "© 2017-2024 Adobe (http://www.adobe.com/).",
                 licenses: ["chironSung-OFL.txt"]),
            face("bold", "粗", "ChironSungHK-Bold",
                 path: "chiron-sung-hk/ChironSungHK-B.otf", bytes: 26_585_108,
                 sha256: "bc3f911227c98ae45caf31147201c29dd3cf14fc2c84af72936f4ef6067b397d",
                 version: "1.024",
                 copyright: "© 2017-2024 Adobe (http://www.adobe.com/).",
                 licenses: ["chironSung-OFL.txt"]),
            face("black", "特粗", "ChironSungHK-Heavy",
                 path: "chiron-sung-hk/ChironSungHK-H.otf", bytes: 24_661_440,
                 sha256: "2465ebd8119e0086bd1be03556d60dd6a3a2988f1579a962532ddb8c6b877cfa",
                 version: "1.024",
                 copyright: "© 2017-2024 Adobe (http://www.adobe.com/).",
                 licenses: ["chironSung-OFL.txt"])
        ]),
        family(.cactusSerif, "仙人掌明體", .song, fullName: "仙人掌明體", listName: "仙人掌明體", defaultWeight: "regular", faces: [
            face("regular", "標準", "CactusClassicalSerif-Regular",
                 path: "cactus-classical-serif/CactusClassicalSerif-Regular.ttf", bytes: 28_502_932,
                 sha256: "ecbd58961db922392d7fecfafa3681fefaeec0c399b860ab6940ba700f7da055",
                 version: "1.005",
                 copyright: "Copyright 2025 The Cactus Serif Project Authors (https://github.com/MoonlitOwen/CactusSerif)",
                 licenses: ["cactusSerif-OFL.txt"])
        ]),
        family(.twSung, "全字庫正宋體", .song, fullName: "全字庫正宋體", listName: "全字庫正宋體", defaultWeight: "regular", sourceNote: "來源：全字庫（數位發展部，https://www.cns11643.gov.tw/）。授權：政府資料開放授權條款第 1 版或 SIL OFL 1.1，二擇一；使用時須註明來源。", faces: [
            face("regular", "標準", "TW-Sung-98_1",
                 path: "tw-sung/TW-Sung-98_1.ttf", bytes: 35_320_040,
                 sha256: "9a3b74fe1a69fe1b3470b5ed780bf678c42a25cef93a13f280a5f31f795f0c56",
                 version: "11503.01",
                 copyright: "(c)2026 Ministry of Digital Affairs. You can use any of the following terms as needed. 1. Open Government Data License, version 1.0(https://data.gov.tw/en/license). 2. the SIL Open Font License, version 1.1. (https://scripts.sil.org/OFL)\n(c)2026數位發展部。使用者可依需求擇一使用以下條款：1.「政府資料開放授權條款-第一版」(https://data.gov.tw/license) ；2. 「開源字型授權1.1版(OFL 1.1) 」(https://scripts.sil.org/OFL)",
                 licenses: ["twSung-OGDL.txt", "twSung-OFL.txt"])
        ]),
        family(.thenKhung, "宇文天穹", .song, fullName: "宇文天穹", listName: "宇文天穹", defaultWeight: "regular", faces: [
            face("regular", "標準", "UoqMunThenKhung-Regular",
                 path: "uoqmun-thenkhung/UoqMunThenKhung-Regular.ttf", bytes: 4_901_688,
                 sha256: "943a23eb10d40ca85ee08491c0e3fb3adbc4bd111ef1f93526a4f766a8e66fbd",
                 version: "1.197",
                 copyright: "Copyright 2025 The UoqMunThenKhung Project Authors (https://github.com/MoonlitOwen/ThenKhung)",
                 licenses: ["thenKhung-OFL.txt"])
        ]),
        family(.lxgwWenKai, "霞鶩文楷 TC", .kai, fullName: "LXGW WenKai TC Medium", listName: "霞鶩文楷 TC", defaultWeight: "medium", faces: [
            face("regular", "標準", "LXGWWenKaiTC-Regular",
                 path: "lxgw-wenkai-tc/LXGWWenKaiTC-Regular.ttf", bytes: 15_267_616,
                 sha256: "b1a0795862c1415bf3f393ea50b2a4ea6275012cf5bad3f94feeb1222f555731",
                 version: "1.522",
                 copyright: "Copyright 2022-2026 LXGW (https://github.com/lxgw/LxgwWenkaiTC)\nCopyright 2020 The Klee Project Authors (https://github.com/fontworks-fonts/Klee)",
                 licenses: ["lxgwWenKai-OFL.txt"]),
            face("medium", "中粗", "LXGWWenKaiTC-Medium",
                 path: "lxgw-wenkai-tc/LXGWWenKaiTC-Medium.ttf", bytes: 15_025_056,
                 sha256: "94ca2870022fb8e4f90e2887524603690598142d17b620dfae318f1818ba8e17",
                 version: "1.522",
                 copyright: "Copyright 2022-2026 LXGW (https://github.com/lxgw/LxgwWenkaiTC)\nCopyright 2020 The Klee Project Authors (https://github.com/fontworks-fonts/Klee)",
                 licenses: ["lxgwWenKai-OFL.txt"])
        ]),
        family(.twKai, "全字庫正楷體", .kai, fullName: "全字庫正楷體", listName: "全字庫正楷體", defaultWeight: "regular", sourceNote: "來源：全字庫（數位發展部，https://www.cns11643.gov.tw/）。授權：政府資料開放授權條款第 1 版或 SIL OFL 1.1，二擇一；使用時須註明來源。", faces: [
            face("regular", "標準", "TW-Kai-98_1",
                 path: "tw-kai/TW-Kai-98_1.ttf", bytes: 36_925_608,
                 sha256: "d5e8d7d8743c5cf816bdeb393a443f65105a8130266a04c19560e1d3401b28f0",
                 version: "11508.01",
                 copyright: "(c)2026 Ministry of Digital Affairs. You can use any of the following terms as needed. 1. Open Government Data License, version 1.0(https://data.gov.tw/en/license). 2. the SIL Open Font License, version 1.1. (https://scripts.sil.org/OFL)\n(c)2026數位發展部。使用者可依需求擇一使用以下條款：1.「政府資料開放授權條款-第一版」(https://data.gov.tw/license) ；2. 「開源字型授權1.1版(OFL 1.1) 」(https://scripts.sil.org/OFL)",
                 licenses: ["twKai-OGDL.txt", "twKai-OFL.txt"])
        ]),
        family(.eduKai, "教育部標準楷書", .kai, fullName: "教育部標準楷書", listName: "教育部標準楷書", defaultWeight: "regular", sourceNote: "著作權人：中華民國教育部。依創用 CC 姓名標示─禁止改作 3.0 台灣版授權，原檔散布、未經修改；引用請標示「中華民國教育部」。", faces: [
            face("regular", "標準", "TW-MOE-Std-Kai",
                 path: "edu-kai/edukai-5.0.ttf", bytes: 15_820_500,
                 sha256: "99ae11cc1ba0ee14d43da5336f2c555b17a3bf551f7203f42da4f7fbdfcf7b7b",
                 version: "5.00, December, 2023",
                 copyright: "(c) This license allows for redistribution, commercial and non-commercial, as long as it is passed along unchanged and in whole, with credit to MOE.\n(c)本字形檔採用創用CC姓名標示-禁止改作3.0 臺灣版授權。如需引用，請標示中華民國教育部。",
                 licenses: ["eduKai-CCBYND.txt"])
        ]),
        family(.arphicUKai, "文鼎 PL 中楷", .kai, fullName: "AR PL UKai TW", listName: "AR PL UKai TW", defaultWeight: "regular", sourceNote: "文鼎 PL 中楷（AR PL UKai TW），依 Arphic Public License 授權，原檔散布、未經修改；授權全文如下。", faces: [
            face("regular", "標準", "UKaiTW",
                 path: "arphic-ukai/ukai.ttc", bytes: 17_151_049,
                 sha256: "cfc758e69386a21bade8cb3b373fda20d7f2fac6e8904ced2ded98588b63e274",
                 version: "0.2.20080216.1",
                 copyright: "This font is derieved from the \"AR PL \" and \"AR PL \" fonts. ((c) Copyright 1994-1999, Arphic Technology Co., Ltd.)\n\nModifications have been made to add, replace and modify glyphs, change encoding and add bitmap representations. ((c) Copyright 2003-2007 Arne Goetje <arne@ubuntu.com>)\n\nThis font is published as par",
                 licenses: ["arphicUKai-APL.txt"])
        ]),
        family(.naikai, "內海字體", .handwriting, fullName: "内海フォント-Bold", listName: "內海字體", defaultWeight: "bold", faces: [
            face("regular", "標準", "NaikaiFont-Regular",
                 path: "naikai/NaikaiFont-Regular.ttf", bytes: 26_254_192,
                 sha256: "d3320b822131540d5e3cc9737f7b458aeb1c0ca76fe89aeaa1b76001f54e503e",
                 version: "1.89",
                 copyright: "Nozomi Seto\n內海字體",
                 licenses: ["naikai-OFL.txt"]),
            face("semibold", "半粗", "NaikaiFont-SemiBold",
                 path: "naikai/NaikaiFont-SemiBold.ttf", bytes: 37_776_240,
                 sha256: "d88f0931677cb43c276148e76d5c1f3c9a6c4089ee8b747fd9b2e59759b2b27b",
                 version: "1.89",
                 copyright: "Nozomi Seto\n內海字體",
                 licenses: ["naikai-OFL.txt"]),
            face("bold", "粗", "NaikaiFont-Bold",
                 path: "naikai/NaikaiFont-Bold.ttf", bytes: 38_622_668,
                 sha256: "43a3822eedd0d7d5fe464fc462c799f5ff2de8eaeabc0825ba09607b1035b621",
                 version: "1.89",
                 copyright: "Nozomi Seto\n內海字體",
                 licenses: ["naikai-OFL.txt"])
        ]),
        family(.xiaolai, "小賴字體", .handwriting, fullName: "Xiaolai", listName: "小賴字體", defaultWeight: "regular", faces: [
            face("regular", "標準", "Xiaolai",
                 path: "xiaolai/Xiaolai-Regular.ttf", bytes: 22_220_806,
                 sha256: "e2f68daf0e72777a8cf58bc83de1b98634b251e537ddbfca24b0ae50d1802da2",
                 version: "3.126",
                 copyright: "Copyright 2020-2024 LXGW (https://github.com/lxgw/kose-font)\nCopyright 2014 Nozomi Seto (https://ja.osdn.net/projects/setofont/)",
                 licenses: ["xiaolai-OFL.txt"])
        ]),
        family(.yozai, "悠哉字體", .handwriting, fullName: "Yozai Medium", listName: "Yozai", defaultWeight: "medium", faces: [
            face("regular", "標準", "Yozai-Regular",
                 path: "yozai/Yozai-Regular.ttf", bytes: 15_605_374,
                 sha256: "25071998a0fe6a72f54c235e714986d259633e5ff670b1a2b5e264387f3316ac",
                 version: "0.868",
                 copyright: "Copyright 2020, 2024 LXGW (https://github.com/lxgw/yozai-font)\nOriginal Font Data Copyright (C) Y.OzVox.",
                 licenses: ["yozai-OFL.txt"]),
            face("medium", "中粗", "Yozai-Medium",
                 path: "yozai/Yozai-Medium.ttf", bytes: 15_238_394,
                 sha256: "05f50f252b45197d0d6148a4abc3e37c7cd4cfdf03c955b57c25d53d924f835f",
                 version: "0.868",
                 copyright: "Copyright 2020, 2024 LXGW (https://github.com/lxgw/yozai-font)\nOriginal Font Data Copyright (C) Y.OzVox.",
                 licenses: ["yozai-OFL.txt"])
        ]),
        family(.nani, "何某手寫體", .handwriting, fullName: "何某手寫-Bold", listName: "何某手寫", defaultWeight: "bold", faces: [
            face("regular", "標準", "NaniFont-Regular",
                 path: "nanifont/NaniFont-Regular.ttf", bytes: 17_799_572,
                 sha256: "3fb7b030f853f2efc4d97dd28fae08a6fa93a565fc91a8f585897e0d53716c1c",
                 version: "1.046",
                 copyright: "Copyright (c) 2016-2020, Nanigashitei.",
                 licenses: ["nani-OFL.txt"]),
            face("bold", "粗", "NaniFont-Bold",
                 path: "nanifont/NaniFont-Bold.ttf", bytes: 18_508_716,
                 sha256: "1b5da5077665309289ba3e62c2fe4b1b788c800dd638af8113bff9fed96b588e",
                 version: "1.046",
                 copyright: "Copyright (c) 2016-2020, Nanigashitei.",
                 licenses: ["nani-OFL.txt"])
        ]),
        family(.lxgwMarker, "霞鶩漫黑", .handwriting, fullName: "LXGW Marker Gothic Regular", listName: "LXGW Marker Gothic", defaultWeight: "regular", faces: [
            face("regular", "標準", "LXGWMarkerGothic-Regular",
                 path: "lxgw-marker-gothic/LXGWMarkerGothic-Regular.ttf", bytes: 3_179_616,
                 sha256: "9a1e46379442856b9fc64de1d9bd4120903780990e28d99fd6415cadee78a47d",
                 version: "1.003",
                 copyright: "Copyright 2024 The LXGW Marker Gothic Project Authors (https://github.com/lxgw/LxgwMarkerGothic)",
                 licenses: ["lxgwMarker-OFL.txt"])
        ]),
        family(.kurewa, "苦累蛙圓體", .handwriting, fullName: "苦累蛙圓體 CJK TC-Bold", listName: "苦累蛙圓體 CJK TC", defaultWeight: "bold", faces: [
            face("regular", "標準", "KurewaGothicCjkTc-Regular",
                 path: "kurewa-gothic/KurewaGothicCjkTc-Regular.ttf", bytes: 31_158_716,
                 sha256: "da6d76a895ac0a8ba80edeb5b99dec0b0e8e205040244e37ba0a39054fa5289e",
                 version: "1.100",
                 copyright: "Copyright 2021 The Kurewa Project Authors (https://github.com/max32002/kurewa-gothic)",
                 licenses: ["kurewa-OFL.txt"]),
            face("bold", "粗", "KurewaGothicCjkTc-Bold",
                 path: "kurewa-gothic/KurewaGothicCjkTc-Bold.ttf", bytes: 36_472_060,
                 sha256: "f3c77d55c30ebf113c1e9375ac500df23082dc76221e3299d9ba581eb54bf515",
                 version: "1.100",
                 copyright: "Copyright 2021 The Kurewa Project Authors (https://github.com/max32002/kurewa-gothic)",
                 licenses: ["kurewa-OFL.txt"])
        ]),
        family(.popGothic, "大波浪圓體", .cute, fullName: "大波浪圓體 CJK TC-Bold", listName: "大波浪圓體 CJK TC", defaultWeight: "bold", faces: [
            face("regular", "標準", "PopGothicCjkTc-Regular",
                 path: "pop-gothic/PopGothicCjkTc-Regular.ttf", bytes: 8_371_820,
                 sha256: "3094ba8fa82bebdfbe4fd168c7460f1023d7bf8a515696a3dedc960f74bbba4a",
                 version: "2.145",
                 copyright: "Copyright 2021 The PopGothic Project Authors (https://github.com/max32002/pop-gothic)",
                 licenses: ["popGothic-OFL.txt"]),
            face("bold", "粗", "PopGothicCjkTc-Bold",
                 path: "pop-gothic/PopGothicCjkTc-Bold.ttf", bytes: 10_298_960,
                 sha256: "6f40a3fcfed7128bebca12b0b27c5cf4a0982e4312143df1390d1645fa4e12e7",
                 version: "2.145",
                 copyright: "Copyright 2021 The PopGothic Project Authors (https://github.com/max32002/pop-gothic)",
                 licenses: ["popGothic-OFL.txt"])
        ]),
        family(.wdxl, "WD-XL 滑油字", .cute, fullName: "WD-XL 滑油字 TC", listName: "WD-XL 滑油字 TC", defaultWeight: "regular", faces: [
            face("regular", "標準", "WD-XLLubrifontTC-Regular",
                 path: "wd-xl-lubrifont/WD-XLLubrifontTC-Regular.otf", bytes: 6_161_104,
                 sha256: "51c179e927526a9acd88b7722909e44c958133733ca316e824f812a28713768b",
                 version: "2.100",
                 copyright: "Copyright 2020-2025 The WD-XL Lubrifont Project Authors (https://github.com/NightFurySL2001/WD-XL-font)\n版權 2020-2025 WD-XL 滑油字計劃作者 (https://github.com/NightFurySL2001/WD-XL-font)",
                 licenses: ["wdxl-OFL.txt"])
        ]),
        family(.cubic11, "俐方體 11 號", .cute, fullName: "俐方體11號", listName: "俐方體11號", defaultWeight: "regular", faces: [
            face("regular", "標準", "Cubic_11",
                 path: "cubic-11/Cubic_11.ttf", bytes: 2_773_732,
                 sha256: "0193f5f033612496df6b45ee92ac3b335bc6a5a24ff95da55ca87b33e57dcf62",
                 version: "1.451",
                 copyright: "[Cubic 11]\nCopyright (c) 2022-2025 ACh\nCopyright (c) 2022 Cubic 11 Project Authors\nThese fonts are free software.\nUnlimited permission is granted to use, copy, and distribute them, with or without modification, either commercially or noncommercially.\nTHESE FONTS ARE PROVIDED \"AS IS\" WITHOUT WARRANTY.\n\n\n\n[JF Dot M+H 12]\nCopyright(c) 2005 M+ FONTS PROJECT\n[M+ BITMAP FONTS]\nCopyright (C) 2002-2004 COZ\nThese fonts are free software.\nUnlimited permission is granted to use, copy, and distribute it, with or without modification, either commercially and noncommercially.\nTHESE FONTS ARE PROVIDED \"AS IS\" WITHOUT WARRANTY.\n[Cubic 11]\nCopyright (c) 2022-2025 ACh\nCopyright (c) 2022 Cubic 11 Project Authors\nThese fonts are free software.\nUnlimited permission is granted to use, copy, and distribute them, with or without modification, either commercially or noncommercially.\nTHESE FONTS ARE PROVIDED \"AS IS\" WITHOUT WARRANTY.\n此字型是免費的。\n無論您是否進行對本字型進行商業或非商業性修改，均可無限制地使用，複製和分發它們。\n本字型的衍生品之授權必須與此字型相同，且不作任何擔保。\n[JF Dot M+H 12]\nCopyright(c) 2005 M+ FONTS PROJECT\n[M+ BITMAP FONTS]\nCopyright (C) 2002-2004 COZ\nThese fonts are free software.\nUnlimited permission is granted to use, copy, and distribute it, with or without modification, either commercially and noncommercially.\nTHESE FONTS ARE PROVIDED \"AS IS\" WITHOUT WARRANTY.\nこれらのフォントはフリー（自由な）ソフトウエアです。\nあらゆる改変の有無に関わらず、また商業的な利用であっても、自由にご利用、複製、再配布することができますが、全て無保証とさせていただきます。",
                 licenses: ["cubic11-OFL.txt"])
        ]),
    ]
}
