import CryptoKit
import XCTest
@testable import DaysCam

/// Covers TASK-142 (#494) 142.1, 142.2, 142.3 and 142.5: the 30 open-source
/// families of `docs/research/fonts-tc-2.md` §2 in the font library.
///
/// The expected table is written out here from the §6 appendix (file name,
/// bytes, SHA-256) and §2 (type, selected weights), independently of
/// `FontCatalog`, so a wrong catalog value cannot pass itself.
@MainActor
final class FontCatalogDownloadFamiliesTests: XCTestCase {

    private struct F {
        let id: String
        let weightName: String
        let postScriptName: String
        let path: String
        let bytes: Int
        let sha256: String

        init(_ id: String, _ weightName: String, _ postScriptName: String, _ path: String, _ bytes: Int,
             _ sha256: String) {
            self.id = id
            self.weightName = weightName
            self.postScriptName = postScriptName
            self.path = path
            self.bytes = bytes
            self.sha256 = sha256
        }
    }

    private struct X {
        let fontID: OverlayFontID
        let name: String
        let category: FontSection
        let defaultWeight: String
        let faces: [F]

        init(_ fontID: OverlayFontID, _ name: String, _ category: FontSection, _ defaultWeight: String, _ faces: [F]) {
            self.fontID = fontID
            self.name = name
            self.category = category
            self.defaultWeight = defaultWeight
            self.faces = faces
        }
    }

    /// §2 order: 黑 6, 圓 3, 宋 8, 楷 4, 手寫 6, 可愛 3.
    private let expected: [X] = [
        X(.notoSansTC, "思源黑體", .hei, "bold", [
            F("regular", "標準", "NotoSansTC-Regular", "noto-sans-tc/NotoSansTC-Regular.otf", 5_683_368,
              "5bab0cb3c1cf89dde07c4a95a4054b195afbcfe784d69d75c340780712237537"),
            F("bold", "粗", "NotoSansTC-Bold", "noto-sans-tc/NotoSansTC-Bold.otf", 5_839_972,
              "55420b259eb119bf5f2a0aadba10cf9d736c12d64ab93e78546d69ef5f43558b"),
            F("black", "特粗", "NotoSansTC-Black", "noto-sans-tc/NotoSansTC-Black.otf", 6_068_384,
              "3280b221ab7b011c6ae48d38388a0e8c72ddf479992bce62ff589ae932819ce4")]),
        X(.taipeiSans, "台北黑體", .hei, "bold", [
            F("light", "細", "TaipeiSansTCBeta-Light", "taipei-sans-tc/TaipeiSansTCBeta-Light.ttf", 20_279_264,
              "d69a9ea6a77f694c3a1a1fb766c764aa74cb3e2c4c69f1b532edf98b3f2bb662"),
            F("regular", "標準", "TaipeiSansTCBeta-Regular", "taipei-sans-tc/TaipeiSansTCBeta-Regular.ttf", 20_659_344,
              "8cc967e1e428c552701c461e8169e6ae76c7a23694ea1a6a786d6746adec53c4"),
            F("bold", "粗", "TaipeiSansTCBeta-Bold", "taipei-sans-tc/TaipeiSansTCBeta-Bold.ttf", 21_737_516,
              "5249d3bdda9c9f4c62840e804b4d2530b7f4dfab6d68fb508c120b0e7e600419")]),
        X(.genSeki, "源石黑體", .hei, "bold", [
            F("regular", "標準", "GenSekiGothic2TW-R", "gen-seki-gothic/GenSekiGothic2TW-R.otf", 16_501_448,
              "bb3cccb9594a5a9c759a92bbbf147eb87826b8317d07d20f48ee7ebdcec684fa"),
            F("bold", "粗", "GenSekiGothic2TW-B", "gen-seki-gothic/GenSekiGothic2TW-B.otf", 15_017_684,
              "911bc231c346f1e377796ccd1b85959184a547d1fce356da882a2f1abb9bfaa4"),
            F("black", "特粗", "GenSekiGothic2TW-H", "gen-seki-gothic/GenSekiGothic2TW-H.otf", 14_691_360,
              "87880818a93362d11b4c07f9612993deeeb1a0800b1779a31bea197e4c8109f2")]),
        X(.chironHei, "昭源黑體", .hei, "bold", [
            F("regular", "標準", "ChironHeiHK-Regular", "chiron-hei-hk/ChironHeiHK-R.otf", 16_164_592,
              "72f68279a78a118b469bc683a1ab12364a5a3c244ee592da441d4a3cb0eda4b1"),
            F("bold", "粗", "ChironHeiHK-Bold", "chiron-hei-hk/ChironHeiHK-B.otf", 17_083_396,
              "51a6c39f8dd0a4522a7c5d366d77e9e52aebe4280d9b16ed95f03288c802e821"),
            F("black", "特粗", "ChironHeiHK-Heavy", "chiron-hei-hk/ChironHeiHK-H.otf", 16_828_836,
              "1dc39f1d97c9bdba16fef81f08be56c96eeb702aca03f4f5b8498c6bc4e385d4")]),
        X(.chocolateSans, "朱古力黑體", .hei, "regular", [
            F("regular", "標準", "ChocolateClassicalSans-Regular", "chocolate-classical-sans/ChocolateClassicalSans-Regular.ttf", 12_183_000,
              "e6345f3d92c7a9b7044c31a87d9b61f50220b08c0f1dcc2736e94c2aa587ce03")]),
        X(.glowSans, "未來熒黑", .hei, "bold", [
            F("regular", "標準", "GlowSansTC-Normal-Regular", "glow-sans-tc/GlowSansTC-Normal-Regular.otf", 8_926_856,
              "cbd6843ab96acc9bb92048dd426232ece37f79068cc9e48c40e8d48e9fd0ee59"),
            F("bold", "粗", "GlowSansTC-Normal-Bold", "glow-sans-tc/GlowSansTC-Normal-Bold.otf", 8_995_980,
              "8005c40f3777c540ec10ed352793f2a53363a13ec41bc0eeaf18d28e9c8c4312"),
            F("black", "特粗", "GlowSansTC-Normal-Heavy", "glow-sans-tc/GlowSansTC-Normal-Heavy.otf", 9_094_228,
              "88ee1042b780005beaa4bbc2bf86cf89a8d0362cfae57b5a9dee7c3887bafbb0")]),
        X(.genSen, "源泉圓體", .yuan, "bold", [
            F("regular", "標準", "GenSenRounded2TW-R", "gen-sen-rounded/GenSenRounded2TW-R.otf", 16_177_104,
              "092285878f1d9441c790e5d6a98e806bd508602ad0a8a55511b6fb0a71a25fed"),
            F("bold", "粗", "GenSenRounded2TW-B", "gen-sen-rounded/GenSenRounded2TW-B.otf", 15_807_568,
              "050f9ebf394faab3c0ba59092ae3e4b6686b349eadb3018d76d385c5829a1267"),
            F("black", "特粗", "GenSenRounded2TW-H", "gen-sen-rounded/GenSenRounded2TW-H.otf", 15_684_388,
              "1088f309fbc3d10d40b2b0e6ef3b965a881066c021f341fd8afd4eb751564ad6")]),
        X(.sweiGothic, "獅尾圓體", .yuan, "bold", [
            F("regular", "標準", "SweiGothicCJKtc-Regular", "swei-gothic/SweiGothicCJKtc-Regular.ttf", 16_193_916,
              "0cb199c63ec23fda70905decf82e1a7f3657092a653323063e9e5f50adfc3f7f"),
            F("bold", "粗", "SweiGothicCJKtc-Bold", "swei-gothic/SweiGothicCJKtc-Bold.ttf", 15_757_732,
              "d3f03ebd366966c1967879d1b5760e96784e9f7b9bac6e4b5dd364db00a9c128"),
            F("black", "特粗", "SweiGothicCJKtc-Black", "swei-gothic/SweiGothicCJKtc-Black.ttf", 14_977_188,
              "7376c750c79bf05b14ad8476d2421696fd9b80bdb5b3ad0e7b27c608e9eef9af")]),
        X(.chironGoRound, "昭源環方", .yuan, "bold", [
            F("regular", "標準", "ChironGoRoundTC-Regular", "chiron-go-round-tc/ChironGoRoundTC-400R.otf", 19_635_772,
              "519253233cbca3c2b97b818949e803ccf08f937d75431bedf59e167b00bf4b65"),
            F("bold", "粗", "ChironGoRoundTC-Bold", "chiron-go-round-tc/ChironGoRoundTC-700B.otf", 20_500_040,
              "5ed043b3d1048e4d7868909c6d6fbba2d0cb50773d394003f4fb077a18e2b3fb"),
            F("black", "特粗", "ChironGoRoundTC-Heavy", "chiron-go-round-tc/ChironGoRoundTC-900H.otf", 19_010_084,
              "6989bb7c609805757146ca79765c4b37da2f17de0c808408d6031db49337e64e")]),
        X(.genWan, "源雲明體", .song, "semibold", [
            F("regular", "標準", "GenWanMin2TW-R", "gen-wan-min/GenWanMin2TW-R.otf", 22_772_928,
              "4c1cea221f35ccfd7c27e295238012d3b48e57d149b92b4eb7d71aeb25d798cf"),
            F("medium", "中粗", "GenWanMin2TW-M", "gen-wan-min/GenWanMin2TW-M.otf", 22_710_256,
              "828b83e22e825030204183422701ae42afe24c93b1b131717e7678bd86b57768"),
            F("semibold", "半粗", "GenWanMin2TW-SB", "gen-wan-min/GenWanMin2TW-SB.otf", 22_614_524,
              "86cc4abaec4151b5ad9ac6d39f635c974a2dc4155fe041e6a4fa9730114487d1")]),
        X(.genRyu, "源流明體", .song, "bold", [
            F("regular", "標準", "GenRyuMin2TW-R", "gen-ryu-min/GenRyuMin2TW-R.otf", 16_449_288,
              "d244c6115431b2a18b5dfb0066e08381f56e6a33532915a0f517dd3f7063b646"),
            F("bold", "粗", "GenRyuMin2TW-B", "gen-ryu-min/GenRyuMin2TW-B.otf", 16_217_516,
              "5e7d2c11cf9860c94ac7d1fba742329f6015f7042c736232e1e69eb8ab12d5da"),
            F("black", "特粗", "GenRyuMin2TW-H", "gen-ryu-min/GenRyuMin2TW-H.otf", 16_022_096,
              "921295896e780b306d79580a8dcacf8ea6c0e1bd29e1853f3eed18264fa6d44a")]),
        X(.sweiSpring, "獅尾四季春", .song, "bold", [
            F("regular", "標準", "SweiSpringCJKtc-Regular", "swei-spring/SweiSpringCJKtc-Regular.ttf", 17_357_244,
              "8278b3f032b7bac5494d28ab1ddbe6b98959142a3e04a2b527c50c654dad6b80"),
            F("bold", "粗", "SweiSpringCJKtc-Bold", "swei-spring/SweiSpringCJKtc-Bold.ttf", 17_336_124,
              "2bf4d16b849c4a87242c3f38817f18d45cf2a04d244fc3420dd5771d78b078fb"),
            F("black", "特粗", "SweiSpringCJKtc-Black", "swei-spring/SweiSpringCJKtc-Black.ttf", 17_730_092,
              "7f71afb558abf3b599094119616502a29cdf31a339f8cf2223cec999f8995e56")]),
        X(.sweiSugar, "獅尾加糖宋體", .song, "bold", [
            F("regular", "標準", "SweiSugarCJKtc-Regular", "swei-sugar/SweiSugarCJKtc-Regular.ttf", 28_960_864,
              "2e930dbafa3f5878df4de9fb773c5a4c9da0b658dd9219d62fd1a928db61447a"),
            F("bold", "粗", "SweiSugarCJKtc-Bold", "swei-sugar/SweiSugarCJKtc-Bold.ttf", 28_989_908,
              "c71c1d5196e49211c5232df39210df2c6fbea0b60245cb8ef9fc7edd37a1a30c"),
            F("black", "特粗", "SweiSugarCJKtc-Black", "swei-sugar/SweiSugarCJKtc-Black.ttf", 29_001_120,
              "f39f956fc4a7f9f6729c62047da0c9376c56653ff7d6912a3b7032c490b449e3")]),
        X(.chironSung, "昭源宋體", .song, "bold", [
            F("regular", "標準", "ChironSungHK-Regular", "chiron-sung-hk/ChironSungHK-R.otf", 24_164_960,
              "d53da9ffb3593a6dcce34f9e4a5d94369c7e619efa1b3d9a60717c7d72aa65d0"),
            F("bold", "粗", "ChironSungHK-Bold", "chiron-sung-hk/ChironSungHK-B.otf", 26_585_108,
              "bc3f911227c98ae45caf31147201c29dd3cf14fc2c84af72936f4ef6067b397d"),
            F("black", "特粗", "ChironSungHK-Heavy", "chiron-sung-hk/ChironSungHK-H.otf", 24_661_440,
              "2465ebd8119e0086bd1be03556d60dd6a3a2988f1579a962532ddb8c6b877cfa")]),
        X(.cactusSerif, "仙人掌明體", .song, "regular", [
            F("regular", "標準", "CactusClassicalSerif-Regular", "cactus-classical-serif/CactusClassicalSerif-Regular.ttf", 28_502_932,
              "ecbd58961db922392d7fecfafa3681fefaeec0c399b860ab6940ba700f7da055")]),
        X(.twSung, "全字庫正宋體", .song, "regular", [
            F("regular", "標準", "TW-Sung-98_1", "tw-sung/TW-Sung-98_1.ttf", 35_320_040,
              "9a3b74fe1a69fe1b3470b5ed780bf678c42a25cef93a13f280a5f31f795f0c56")]),
        X(.thenKhung, "宇文天穹", .song, "regular", [
            F("regular", "標準", "UoqMunThenKhung-Regular", "uoqmun-thenkhung/UoqMunThenKhung-Regular.ttf", 4_901_688,
              "943a23eb10d40ca85ee08491c0e3fb3adbc4bd111ef1f93526a4f766a8e66fbd")]),
        X(.lxgwWenKai, "霞鶩文楷 TC", .kai, "medium", [
            F("regular", "標準", "LXGWWenKaiTC-Regular", "lxgw-wenkai-tc/LXGWWenKaiTC-Regular.ttf", 15_267_616,
              "b1a0795862c1415bf3f393ea50b2a4ea6275012cf5bad3f94feeb1222f555731"),
            F("medium", "中粗", "LXGWWenKaiTC-Medium", "lxgw-wenkai-tc/LXGWWenKaiTC-Medium.ttf", 15_025_056,
              "94ca2870022fb8e4f90e2887524603690598142d17b620dfae318f1818ba8e17")]),
        X(.twKai, "全字庫正楷體", .kai, "regular", [
            F("regular", "標準", "TW-Kai-98_1", "tw-kai/TW-Kai-98_1.ttf", 36_925_608,
              "d5e8d7d8743c5cf816bdeb393a443f65105a8130266a04c19560e1d3401b28f0")]),
        X(.eduKai, "教育部標準楷書", .kai, "regular", [
            F("regular", "標準", "TW-MOE-Std-Kai", "edu-kai/edukai-5.0.ttf", 15_820_500,
              "99ae11cc1ba0ee14d43da5336f2c555b17a3bf551f7203f42da4f7fbdfcf7b7b")]),
        X(.arphicUKai, "文鼎 PL 中楷", .kai, "regular", [
            F("regular", "標準", "UKaiTW", "arphic-ukai/ukai.ttc", 17_151_049,
              "cfc758e69386a21bade8cb3b373fda20d7f2fac6e8904ced2ded98588b63e274")]),
        X(.naikai, "內海字體", .handwriting, "bold", [
            F("regular", "標準", "NaikaiFont-Regular", "naikai/NaikaiFont-Regular.ttf", 26_254_192,
              "d3320b822131540d5e3cc9737f7b458aeb1c0ca76fe89aeaa1b76001f54e503e"),
            F("semibold", "半粗", "NaikaiFont-SemiBold", "naikai/NaikaiFont-SemiBold.ttf", 37_776_240,
              "d88f0931677cb43c276148e76d5c1f3c9a6c4089ee8b747fd9b2e59759b2b27b"),
            F("bold", "粗", "NaikaiFont-Bold", "naikai/NaikaiFont-Bold.ttf", 38_622_668,
              "43a3822eedd0d7d5fe464fc462c799f5ff2de8eaeabc0825ba09607b1035b621")]),
        X(.xiaolai, "小賴字體", .handwriting, "regular", [
            F("regular", "標準", "Xiaolai", "xiaolai/Xiaolai-Regular.ttf", 22_220_806,
              "e2f68daf0e72777a8cf58bc83de1b98634b251e537ddbfca24b0ae50d1802da2")]),
        X(.yozai, "悠哉字體", .handwriting, "medium", [
            F("regular", "標準", "Yozai-Regular", "yozai/Yozai-Regular.ttf", 15_605_374,
              "25071998a0fe6a72f54c235e714986d259633e5ff670b1a2b5e264387f3316ac"),
            F("medium", "中粗", "Yozai-Medium", "yozai/Yozai-Medium.ttf", 15_238_394,
              "05f50f252b45197d0d6148a4abc3e37c7cd4cfdf03c955b57c25d53d924f835f")]),
        X(.nani, "何某手寫體", .handwriting, "bold", [
            F("regular", "標準", "NaniFont-Regular", "nanifont/NaniFont-Regular.ttf", 17_799_572,
              "3fb7b030f853f2efc4d97dd28fae08a6fa93a565fc91a8f585897e0d53716c1c"),
            F("bold", "粗", "NaniFont-Bold", "nanifont/NaniFont-Bold.ttf", 18_508_716,
              "1b5da5077665309289ba3e62c2fe4b1b788c800dd638af8113bff9fed96b588e")]),
        X(.lxgwMarker, "霞鶩漫黑", .handwriting, "regular", [
            F("regular", "標準", "LXGWMarkerGothic-Regular", "lxgw-marker-gothic/LXGWMarkerGothic-Regular.ttf", 3_179_616,
              "9a1e46379442856b9fc64de1d9bd4120903780990e28d99fd6415cadee78a47d")]),
        X(.kurewa, "苦累蛙圓體", .handwriting, "bold", [
            F("regular", "標準", "KurewaGothicCjkTc-Regular", "kurewa-gothic/KurewaGothicCjkTc-Regular.ttf", 31_158_716,
              "da6d76a895ac0a8ba80edeb5b99dec0b0e8e205040244e37ba0a39054fa5289e"),
            F("bold", "粗", "KurewaGothicCjkTc-Bold", "kurewa-gothic/KurewaGothicCjkTc-Bold.ttf", 36_472_060,
              "f3c77d55c30ebf113c1e9375ac500df23082dc76221e3299d9ba581eb54bf515")]),
        X(.popGothic, "大波浪圓體", .cute, "bold", [
            F("regular", "標準", "PopGothicCjkTc-Regular", "pop-gothic/PopGothicCjkTc-Regular.ttf", 8_371_820,
              "3094ba8fa82bebdfbe4fd168c7460f1023d7bf8a515696a3dedc960f74bbba4a"),
            F("bold", "粗", "PopGothicCjkTc-Bold", "pop-gothic/PopGothicCjkTc-Bold.ttf", 10_298_960,
              "6f40a3fcfed7128bebca12b0b27c5cf4a0982e4312143df1390d1645fa4e12e7")]),
        X(.wdxl, "WD-XL 滑油字", .cute, "regular", [
            F("regular", "標準", "WD-XLLubrifontTC-Regular", "wd-xl-lubrifont/WD-XLLubrifontTC-Regular.otf", 6_161_104,
              "51c179e927526a9acd88b7722909e44c958133733ca316e824f812a28713768b")]),
        X(.cubic11, "俐方體 11 號", .cute, "regular", [
            F("regular", "標準", "Cubic_11", "cubic-11/Cubic_11.ttf", 2_773_732,
              "0193f5f033612496df6b45ee92ac3b335bc6a5a24ff95da55ca87b33e57dcf62")]),
    ]

    // MARK: - 142.1

    /// 142.1: all 30 families are in the library's open-source group, typed
    /// as §2 says, with the weights §2 selects.
    func test_acceptance_142_1_thirtyFamiliesWithSection2TypesAndWeights() throws {
        XCTAssertEqual(expected.count, 30)
        XCTAssertEqual(FontCatalog.downloadFamilies.map(\.fontID), expected.map(\.fontID), "142.1 order")
        let counts = Dictionary(grouping: expected, by: \.category).mapValues(\.count)
        XCTAssertEqual(counts, [.hei: 6, .yuan: 3, .song: 8, .kai: 4, .handwriting: 6, .cute: 3], "142.1 §2 類型數")
        for item in expected {
            let family = try XCTUnwrap(FontCatalog.downloadFamiliesByID[item.fontID], "\(item.fontID)")
            XCTAssertEqual(family.displayName, item.name)
            XCTAssertEqual(family.category, item.category, "\(item.fontID) 類型")
            XCTAssertEqual(family.defaultWeightID, item.defaultWeight, "\(item.fontID) 預設字重")
            XCTAssertEqual(family.faces.map(\.id), item.faces.map(\.id), "\(item.fontID) 字重")
            XCTAssertEqual(family.faces.map(\.weightName), item.faces.map(\.weightName), "\(item.fontID) 字重名")
            XCTAssertEqual(family.faces.map(\.postScriptName), item.faces.map(\.postScriptName), "\(item.fontID)")

            let entry = FontCatalog.entry(for: item.fontID)
            XCTAssertEqual(entry.section, .openSource, "\(item.fontID) 在開源（可下載）組")
            XCTAssertEqual(entry.source, .openSource)
            XCTAssertEqual(entry.displayName, item.name)
            XCTAssertTrue((1...3).contains(entry.weights.count), "\(item.fontID) 最多三個字重")
            XCTAssertEqual(entry.weights.map(\.id), item.faces.map(\.id))
            XCTAssertEqual(entry.weights.map(\.postScriptName), item.faces.map(\.postScriptName))
            XCTAssertEqual(entry.defaultWeight.id, item.defaultWeight)
            XCTAssertEqual(entry.postScriptName, entry.defaultWeight.postScriptName)
            XCTAssertEqual(entry.openSource, entry.defaultWeight.openSource, "\(item.fontID) 預設資產")
        }
        let total = expected.reduce(0) { $0 + $1.faces.count }
        XCTAssertEqual(total, 63, "30 套共 63 個字重檔")
    }

    /// 142.1: not among them are the three fonts whose license is unconfirmed.
    func test_acceptance_142_1_unconfirmedLicenseFontsAreNotAdded() {
        let raw = Set(OverlayFontID.allCases.map { $0.rawValue.lowercased() })
        for banned in ["jasonhandwriting", "qingsong", "bakudai", "masa", "masafont", "mortai"] {
            XCTAssertFalse(raw.contains { $0.contains(banned) }, "清松、莫大、正風不可加入：\(banned)")
        }
        let names = Set(FontCatalog.entries.map(\.displayName))
        for banned in ["清松手寫體", "莫大毛筆", "正風毛筆"] {
            XCTAssertFalse(names.contains(banned), banned)
        }
    }

    // MARK: - 142.2

    /// 142.2: every face's path, byte count and SHA-256 are §6's, none
    /// repeats, and every face downloads from the `v4` tag.
    func test_acceptance_142_2_assetsMatchSection6AndAreUnique() throws {
        var paths = Set<String>()
        var hashes = Set<String>()
        for item in expected {
            let entry = FontCatalog.entry(for: item.fontID)
            for face in item.faces {
                let weight = try XCTUnwrap(entry.weights.first { $0.id == face.id }, "\(item.fontID)/\(face.id)")
                let asset = try XCTUnwrap(weight.openSource, "\(item.fontID)/\(face.id)")
                XCTAssertEqual(asset.repositoryPath, face.path)
                XCTAssertEqual(asset.fileName, (face.path as NSString).lastPathComponent)
                XCTAssertEqual(asset.byteCount, face.bytes, "\(face.path)")
                XCTAssertEqual(asset.sha256, face.sha256, "\(face.path)")
                XCTAssertTrue(asset.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
                XCTAssertFalse(asset.version.isEmpty, "\(face.path)")
                XCTAssertFalse(asset.copyright.isEmpty, "\(face.path)")
                XCTAssertFalse(asset.licenseFileNames.isEmpty, "\(face.path)")
                XCTAssertEqual(asset.primaryURL.absoluteString,
                               "https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v4/\(face.path)")
                XCTAssertEqual(asset.fallbackURL.absoluteString,
                               "https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v4/\(face.path)")
                XCTAssertTrue(paths.insert(asset.repositoryPath).inserted, "path repeats: \(face.path)")
                XCTAssertTrue(hashes.insert(asset.sha256).inserted, "SHA-256 repeats: \(face.path)")
                XCTAssertEqual(weight.downloadSizeMegabytes, Double(face.bytes) / 1_000_000)
            }
        }
        XCTAssertEqual(paths.count, 63)
        // None collides with the files of the four fonts that were already there.
        let older = Set([FontCatalog.huninnAsset, FontCatalog.notoSerifTCAsset, FontCatalog.iansuiAsset,
                         FontCatalog.chenyuluoyanAsset, FontCatalog.notoSerifTCRegularAsset,
                         FontCatalog.notoSerifTCBlackAsset].map(\.repositoryPath))
        XCTAssertTrue(older.isDisjoint(with: paths))
    }

    /// 142.2: the real verifier accepts a file with the asset's size and
    /// SHA-256 and rejects any other.
    func test_acceptance_142_2_verifierChecksSizeAndHash() throws {
        let data = Data("pretend this is a font file".utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("142-\(UUID().uuidString).ttf")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let real = try XCTUnwrap(FontCatalog.entry(for: .cubic11).openSource)
        func asset(bytes: Int, sha256: String) -> OpenSourceFontAsset {
            OpenSourceFontAsset(fileName: real.fileName, repositoryPath: real.repositoryPath, byteCount: bytes,
                                sha256: sha256, primaryURL: real.primaryURL, fallbackURL: real.fallbackURL,
                                version: real.version, copyright: real.copyright,
                                licenseFileNames: real.licenseFileNames)
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(FontFileVerifier.isValid(fileAt: url, for: asset(bytes: data.count, sha256: digest)))
        XCTAssertFalse(FontFileVerifier.isValid(fileAt: url, for: asset(bytes: data.count, sha256: real.sha256)),
                       "wrong hash is rejected")
        XCTAssertFalse(FontFileVerifier.isValid(fileAt: url, for: asset(bytes: data.count + 1, sha256: digest)),
                       "wrong size is rejected")
        XCTAssertFalse(FontFileVerifier.isValid(fileAt: url, for: real), "a catalog asset is not this file")
    }

    // MARK: - 142.3

    /// 142.3: before a family is downloaded, a profile that names it keeps its
    /// font ID and weight in the file and draws PingFang.
    func test_acceptance_142_3_undownloadedFamilyKeepsTheSettingAndDrawsPingFang() throws {
        for item in expected {
            for face in item.faces {
                let style = OverlayStyle(fontID: item.fontID, fontWeight: face.id)
                let reloaded = try JSONDecoder().decode(OverlayStyle.self, from: JSONEncoder().encode(style))
                XCTAssertEqual(reloaded.fontID, item.fontID, "\(item.fontID)")
                XCTAssertEqual(reloaded.fontWeight, face.id, "\(item.fontID)")
                let font = OverlayMetrics.resolvedFont(for: item.fontID, weightID: face.id,
                                                       availability: Unavailable())
                XCTAssertEqual(font, .pingFang, "\(item.fontID)/\(face.id) 未下載畫蘋方，不影響設定")
            }
        }
    }

    /// 142.2 / 142.3: every one of the 63 faces can be downloaded and deleted,
    /// one by one, with registration and hashing faked. The network behaves
    /// like the real hosts: jsDelivr refuses files over 20 MiB (measured on
    /// `v4`, see `docs/fonts-manifest.md`), raw GitHub serves everything, so
    /// the 19 large files must arrive through the fallback URL.
    func test_acceptance_142_3_everyFaceDownloadsAndDeletes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FontCatalogDownloadFamiliesTests-\(UUID().uuidString)", isDirectory: true)
        let suite = "FontCatalogDownloadFamiliesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let limit = 20 * 1024 * 1024
        let sizes = Dictionary(uniqueKeysWithValues: expected.flatMap { $0.faces }.map { ($0.path, $0.bytes) })
        let fetcher = CDNFetcher(sizes: sizes, jsDelivrLimit: limit)
        let registrar = AcceptingRegistrar()
        let library = FontLibrary(directory: directory, fetcher: fetcher, registrar: registrar,
                                  matcher: NeverMatcher(), defaults: defaults,
                                  verifyFile: { _, _ in true })
        for item in expected {
            for face in item.faces {
                XCTAssertEqual(library.state(for: item.fontID, weightID: face.id), .notDownloaded)
                XCTAssertTrue(library.download(item.fontID, weightID: face.id), "\(face.path)")
                await waitUntil("\(face.path) available") {
                    library.state(for: item.fontID, weightID: face.id) == .available
                }
                let stored = library.storedFileURL(for: item.fontID, weightID: face.id)
                XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path), "\(face.path)")
                XCTAssertEqual(stored.pathExtension, (face.path as NSString).pathExtension, "\(face.path)")
                XCTAssertTrue(library.delete(item.fontID, weightID: face.id), "\(face.path)")
                XCTAssertEqual(library.state(for: item.fontID, weightID: face.id), .notDownloaded)
                XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path), "\(face.path)")
            }
        }
        let large = sizes.filter { $0.value > limit }.keys
        XCTAssertEqual(large.count, 19, "measured: 19 files are over jsDelivr's 20 MiB limit")
        let requested = fetcher.requested.map(\.absoluteString)
        XCTAssertEqual(requested.filter { $0.contains("cdn.jsdelivr.net") }.count, 63, "jsDelivr is always tried first")
        XCTAssertEqual(requested.filter { $0.contains("raw.githubusercontent.com") }.count, 19,
                       "only the large files fall back to raw")
        for path in large {
            XCTAssertTrue(requested.contains("https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v4/\(path)"),
                          "\(path) arrives through the fallback")
        }
        XCTAssertTrue(requested.allSatisfy { $0.contains("@v4/") || $0.contains("/v4/") })
    }

    // MARK: - 142.5

    /// 142.5: every family's license files ship in the App, and the license
    /// page lists every face of all 30 with its copyright and license text.
    func test_acceptance_142_5_licensePageListsAllThirtyWithSpecialNotices() throws {
        for family in FontCatalog.downloadFamilies {
            for name in family.faces.flatMap(\.asset.licenseFileNames) {
                let text = try XCTUnwrap(FontLicenseModel.bundleText(name), "\(family.fontID): \(name)")
                XCTAssertGreaterThan(text.count, 500, name)
            }
        }
        let model = FontLicenseModel()
        for item in expected {
            let entry = try XCTUnwrap(model.entries.first { $0.fontID == item.fontID }, "\(item.fontID)")
            XCTAssertEqual(entry.files.map(\.fileName), item.faces.map { ($0.path as NSString).lastPathComponent })
            XCTAssertTrue(entry.files.allSatisfy { !$0.copyright.isEmpty && !$0.version.isEmpty })
            XCTAssertFalse(entry.licenses.isEmpty)
            XCTAssertTrue(entry.licenses.allSatisfy { !$0.text.isEmpty }, "\(item.fontID) 授權全文")
        }

        let kai = try XCTUnwrap(model.entries.first { $0.fontID == .twKai })
        let sung = try XCTUnwrap(model.entries.first { $0.fontID == .twSung })
        for entry in [kai, sung] {
            XCTAssertTrue(entry.sourceNote?.contains("全字庫") == true, "全字庫註明來源")
            XCTAssertEqual(entry.licenses.map(\.title), ["政府資料開放授權條款－第1版", "SIL Open Font License 1.1"])
        }
        let edu = try XCTUnwrap(model.entries.first { $0.fontID == .eduKai })
        XCTAssertTrue(edu.sourceNote?.contains("中華民國教育部") == true, "教育部標準楷書標示中華民國教育部")
        XCTAssertEqual(edu.licenses.map(\.title), ["創用 CC 姓名標示─禁止改作 3.0 台灣（CC BY-ND 3.0 TW）"])
        let arphic = try XCTUnwrap(model.entries.first { $0.fontID == .arphicUKai })
        XCTAssertEqual(arphic.licenses.map(\.title), ["Arphic Public License"])
        XCTAssertTrue(arphic.licenses[0].text.contains("ARPHIC PUBLIC LICENSE"), "附 Arphic Public License 全文")
        let glow = try XCTUnwrap(model.entries.first { $0.fontID == .glowSans })
        XCTAssertEqual(glow.licenses.map(\.title), ["SIL Open Font License 1.1", "MIT License"],
                       "未來熒黑字型內嵌 OFL、repo 為 MIT，兩者都附")
    }

    // MARK: - Fakes

    private struct Unavailable: FontAvailabilityProviding {
        func state(for fontID: OverlayFontID) -> FontState { .notDownloaded }
    }

    /// jsDelivr answers 403 for a file over its limit; raw GitHub serves any.
    private final class CDNFetcher: FontFileFetching, @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        private let sizes: [String: Int]
        private let jsDelivrLimit: Int
        var requested: [URL] { lock.withLock { urls } }

        init(sizes: [String: Int], jsDelivrLimit: Int) {
            self.sizes = sizes
            self.jsDelivrLimit = jsDelivrLimit
        }

        func fetch(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            lock.withLock { urls.append(url) }
            let text = url.absoluteString
            let path = sizes.keys.first { text.hasSuffix("/" + $0) }
            if text.contains("cdn.jsdelivr.net"), let path, (sizes[path] ?? 0) > jsDelivrLimit {
                throw FontFetchError.other
            }
            try Data("font".utf8).write(to: destination)
            progress(1)
        }
    }

    private struct AcceptingRegistrar: FontRegistering {
        func register(fontAt url: URL) -> Bool { true }
        func unregister(fontAt url: URL) {}
    }

    private struct NeverMatcher: SystemFontMatching {
        func startMatching(postScriptName: String, handler: @escaping @Sendable (SystemFontMatchEvent) -> Bool) {}
    }

    private func waitUntil(_ message: String, timeout: TimeInterval = 5,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(message)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}
