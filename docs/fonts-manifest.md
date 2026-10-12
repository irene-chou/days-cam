# 開源字型清單（0.3）

App 下載的開源字型與授權資料。數值寫死在 `FontCatalog`（TASK-32），由 TASK-31 產生；換版本時新增 `dayscam-fonts` 的 tag 並同步本表。

- 下載點：公開 repo [`irene-chou/dayscam-fonts`](https://github.com/irene-chou/dayscam-fonts)，tag `v4`（TASK-142 起；`v1`～`v3` 保留不覆寫。`v2` 含 `v1` 的三個原檔加辰宇落雁體，`v3` 含 `v2` 全部檔案加思源宋體 Regular／Black，`v4` 含 `v3` 全部檔案加 30 套 63 個字重檔，路徑與 SHA-256 與 `v3` 相同的檔案不變）
- 主要網址：`https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v4/<路徑>`
- 備援網址：`https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v4/<路徑>`
- 2026-10-06 已對 `v1` 的 6 個網址完整下載驗證，大小與 SHA-256 一致（驗收 31.1，紀錄見 #162）；`v2` 的 8 個網址待 tag 推上後驗證（驗收 40.5，#219）；2026-10-10 以 `curl -sIL` 確認 `v3` 的 Regular、Black 與粉圓在 jsDelivr／raw 皆回 200，raw 的 content-length 與本表 bytes 相同（驗收 91.3，#384）

| fontID | 顯示名稱 | 路徑 | bytes | SHA-256 | PostScript | 字型版本 | App 內授權檔 |
|---|---|---|---|---|---|---|---|
| `huninn` | 粉圓 | `huninn/jf-openhuninn-2.1.ttf` | 4911464 | `9d5bf4932d31fe94c18cd8cfddc98bc1b14ce10f4e354c682179db290a99c825` | `jf-openhuninn-2.1` | 2.1 | `huninn-OFL.txt`、`huninn-Apache-2.0.txt` |
| `notoSerifTC` | 思源宋體 | `noto-serif-tc/NotoSerifTC-Bold.otf` | 8253304 | `3ca2b3294ec84b795d0a45695e78e3612a44dce50f9fc776cd40206340a5768d` | `NotoSerifTC-Bold` | 2.003 | `notoSerifTC-OFL.txt` |
| `notoSerifTC`／`regular` | 思源宋體 標準 | `noto-serif-tc/NotoSerifTC-Regular.otf` | 7936104 | `63515eb0622d589a2f4062e8757c598b3da3bffd053f69abd181c210158ef10c` | `NotoSerifTC-Regular` | 2.003 | `notoSerifTC-OFL.txt` |
| `notoSerifTC`／`black` | 思源宋體 特粗 | `noto-serif-tc/NotoSerifTC-Black.otf` | 8122092 | `55c68df309e702cdb56b9ffd6b8185468afc0cb070aa9c2f14099de0cae64d12` | `NotoSerifTC-Black` | 2.003 | `notoSerifTC-OFL.txt` |
| `iansui` | 芫荽 | `iansui/Iansui-Regular.ttf` | 9447424 | `7f1aa62e9dcbf40d0ce41a5d3f1e5ea602e66c295778ac6fefb6b84d8ed08bd5` | `Iansui-Regular` | 1.012（官方 release tag `v1.020`） | `iansui-OFL.txt` |
| `chenyuluoyan` | 辰宇落雁體 | `chenyuluoyan/ChenYuluoyan-2.0-Thin.ttf` | 9522140 | `1289e42a6d1ec995d0cb23aee89efc69fc95749fbd54a610057a3e992dc453db` | `ChenYuluoyan-2.0-Thin` | 2.100（官方 release `v2.0`） | `chenyuluoyan-OFL.txt` |
| `notoSansTC`／`regular` | 思源黑體 標準 | `noto-sans-tc/NotoSansTC-Regular.otf` | 5683368 | `5bab0cb3c1cf89dde07c4a95a4054b195afbcfe784d69d75c340780712237537` | `NotoSansTC-Regular` | 2.004 | `notoSansTC-OFL.txt` |
| `notoSansTC` | 思源黑體 | `noto-sans-tc/NotoSansTC-Bold.otf` | 5839972 | `55420b259eb119bf5f2a0aadba10cf9d736c12d64ab93e78546d69ef5f43558b` | `NotoSansTC-Bold` | 2.004 | `notoSansTC-OFL.txt` |
| `notoSansTC`／`black` | 思源黑體 特粗 | `noto-sans-tc/NotoSansTC-Black.otf` | 6068384 | `3280b221ab7b011c6ae48d38388a0e8c72ddf479992bce62ff589ae932819ce4` | `NotoSansTC-Black` | 2.004 | `notoSansTC-OFL.txt` |
| `taipeiSans`／`light` | 台北黑體 細 | `taipei-sans-tc/TaipeiSansTCBeta-Light.ttf` | 20279264 | `d69a9ea6a77f694c3a1a1fb766c764aa74cb3e2c4c69f1b532edf98b3f2bb662` | `TaipeiSansTCBeta-Light` | 1.000 | `taipeiSans-OFL.txt` |
| `taipeiSans`／`regular` | 台北黑體 標準 | `taipei-sans-tc/TaipeiSansTCBeta-Regular.ttf` | 20659344 | `8cc967e1e428c552701c461e8169e6ae76c7a23694ea1a6a786d6746adec53c4` | `TaipeiSansTCBeta-Regular` | 1.000 | `taipeiSans-OFL.txt` |
| `taipeiSans` | 台北黑體 | `taipei-sans-tc/TaipeiSansTCBeta-Bold.ttf` | 21737516 | `5249d3bdda9c9f4c62840e804b4d2530b7f4dfab6d68fb508c120b0e7e600419` | `TaipeiSansTCBeta-Bold` | 1.000 | `taipeiSans-OFL.txt` |
| `genSeki`／`regular` | 源石黑體 標準 | `gen-seki-gothic/GenSekiGothic2TW-R.otf` | 16501448 | `bb3cccb9594a5a9c759a92bbbf147eb87826b8317d07d20f48ee7ebdcec684fa` | `GenSekiGothic2TW-R` | 2.100 | `genSeki-OFL.txt` |
| `genSeki` | 源石黑體 | `gen-seki-gothic/GenSekiGothic2TW-B.otf` | 15017684 | `911bc231c346f1e377796ccd1b85959184a547d1fce356da882a2f1abb9bfaa4` | `GenSekiGothic2TW-B` | 2.100 | `genSeki-OFL.txt` |
| `genSeki`／`black` | 源石黑體 特粗 | `gen-seki-gothic/GenSekiGothic2TW-H.otf` | 14691360 | `87880818a93362d11b4c07f9612993deeeb1a0800b1779a31bea197e4c8109f2` | `GenSekiGothic2TW-H` | 2.100 | `genSeki-OFL.txt` |
| `chironHei`／`regular` | 昭源黑體 標準 | `chiron-hei-hk/ChironHeiHK-R.otf` | 16164592 | `72f68279a78a118b469bc683a1ab12364a5a3c244ee592da441d4a3cb0eda4b1` | `ChironHeiHK-Regular` | 2.609 | `chironHei-OFL.txt` |
| `chironHei` | 昭源黑體 | `chiron-hei-hk/ChironHeiHK-B.otf` | 17083396 | `51a6c39f8dd0a4522a7c5d366d77e9e52aebe4280d9b16ed95f03288c802e821` | `ChironHeiHK-Bold` | 2.609 | `chironHei-OFL.txt` |
| `chironHei`／`black` | 昭源黑體 特粗 | `chiron-hei-hk/ChironHeiHK-H.otf` | 16828836 | `1dc39f1d97c9bdba16fef81f08be56c96eeb702aca03f4f5b8498c6bc4e385d4` | `ChironHeiHK-Heavy` | 2.609 | `chironHei-OFL.txt` |
| `chocolateSans` | 朱古力黑體 | `chocolate-classical-sans/ChocolateClassicalSans-Regular.ttf` | 12183000 | `e6345f3d92c7a9b7044c31a87d9b61f50220b08c0f1dcc2736e94c2aa587ce03` | `ChocolateClassicalSans-Regular` | 1.005 | `chocolateSans-OFL.txt` |
| `glowSans`／`regular` | 未來熒黑 標準 | `glow-sans-tc/GlowSansTC-Normal-Regular.otf` | 8926856 | `cbd6843ab96acc9bb92048dd426232ece37f79068cc9e48c40e8d48e9fd0ee59` | `GlowSansTC-Normal-Regular` | 0.93 | `glowSans-OFL.txt`、`glowSans-MIT.txt` |
| `glowSans` | 未來熒黑 | `glow-sans-tc/GlowSansTC-Normal-Bold.otf` | 8995980 | `8005c40f3777c540ec10ed352793f2a53363a13ec41bc0eeaf18d28e9c8c4312` | `GlowSansTC-Normal-Bold` | 0.93 | `glowSans-OFL.txt`、`glowSans-MIT.txt` |
| `glowSans`／`black` | 未來熒黑 特粗 | `glow-sans-tc/GlowSansTC-Normal-Heavy.otf` | 9094228 | `88ee1042b780005beaa4bbc2bf86cf89a8d0362cfae57b5a9dee7c3887bafbb0` | `GlowSansTC-Normal-Heavy` | 0.93 | `glowSans-OFL.txt`、`glowSans-MIT.txt` |
| `genSen`／`regular` | 源泉圓體 標準 | `gen-sen-rounded/GenSenRounded2TW-R.otf` | 16177104 | `092285878f1d9441c790e5d6a98e806bd508602ad0a8a55511b6fb0a71a25fed` | `GenSenRounded2TW-R` | 2.100 | `genSen-OFL.txt` |
| `genSen` | 源泉圓體 | `gen-sen-rounded/GenSenRounded2TW-B.otf` | 15807568 | `050f9ebf394faab3c0ba59092ae3e4b6686b349eadb3018d76d385c5829a1267` | `GenSenRounded2TW-B` | 2.100 | `genSen-OFL.txt` |
| `genSen`／`black` | 源泉圓體 特粗 | `gen-sen-rounded/GenSenRounded2TW-H.otf` | 15684388 | `1088f309fbc3d10d40b2b0e6ef3b965a881066c021f341fd8afd4eb751564ad6` | `GenSenRounded2TW-H` | 2.100 | `genSen-OFL.txt` |
| `sweiGothic`／`regular` | 獅尾圓體 標準 | `swei-gothic/SweiGothicCJKtc-Regular.ttf` | 16193916 | `0cb199c63ec23fda70905decf82e1a7f3657092a653323063e9e5f50adfc3f7f` | `SweiGothicCJKtc-Regular` | 2.143 | `sweiGothic-OFL.txt` |
| `sweiGothic` | 獅尾圓體 | `swei-gothic/SweiGothicCJKtc-Bold.ttf` | 15757732 | `d3f03ebd366966c1967879d1b5760e96784e9f7b9bac6e4b5dd364db00a9c128` | `SweiGothicCJKtc-Bold` | 2.140 | `sweiGothic-OFL.txt` |
| `sweiGothic`／`black` | 獅尾圓體 特粗 | `swei-gothic/SweiGothicCJKtc-Black.ttf` | 14977188 | `7376c750c79bf05b14ad8476d2421696fd9b80bdb5b3ad0e7b27c608e9eef9af` | `SweiGothicCJKtc-Black` | 2.125 | `sweiGothic-OFL.txt` |
| `chironGoRound`／`regular` | 昭源環方 標準 | `chiron-go-round-tc/ChironGoRoundTC-400R.otf` | 19635772 | `519253233cbca3c2b97b818949e803ccf08f937d75431bedf59e167b00bf4b65` | `ChironGoRoundTC-Regular` | 1.011 | `chironGoRound-OFL.txt` |
| `chironGoRound` | 昭源環方 | `chiron-go-round-tc/ChironGoRoundTC-700B.otf` | 20500040 | `5ed043b3d1048e4d7868909c6d6fbba2d0cb50773d394003f4fb077a18e2b3fb` | `ChironGoRoundTC-Bold` | 1.011 | `chironGoRound-OFL.txt` |
| `chironGoRound`／`black` | 昭源環方 特粗 | `chiron-go-round-tc/ChironGoRoundTC-900H.otf` | 19010084 | `6989bb7c609805757146ca79765c4b37da2f17de0c808408d6031db49337e64e` | `ChironGoRoundTC-Heavy` | 1.011 | `chironGoRound-OFL.txt` |
| `genWan`／`regular` | 源雲明體 標準 | `gen-wan-min/GenWanMin2TW-R.otf` | 22772928 | `4c1cea221f35ccfd7c27e295238012d3b48e57d149b92b4eb7d71aeb25d798cf` | `GenWanMin2TW-R` | 2.100 | `genWan-OFL.txt` |
| `genWan`／`medium` | 源雲明體 中粗 | `gen-wan-min/GenWanMin2TW-M.otf` | 22710256 | `828b83e22e825030204183422701ae42afe24c93b1b131717e7678bd86b57768` | `GenWanMin2TW-M` | 2.100 | `genWan-OFL.txt` |
| `genWan` | 源雲明體 | `gen-wan-min/GenWanMin2TW-SB.otf` | 22614524 | `86cc4abaec4151b5ad9ac6d39f635c974a2dc4155fe041e6a4fa9730114487d1` | `GenWanMin2TW-SB` | 2.100 | `genWan-OFL.txt` |
| `genRyu`／`regular` | 源流明體 標準 | `gen-ryu-min/GenRyuMin2TW-R.otf` | 16449288 | `d244c6115431b2a18b5dfb0066e08381f56e6a33532915a0f517dd3f7063b646` | `GenRyuMin2TW-R` | 2.100 | `genRyu-OFL.txt` |
| `genRyu` | 源流明體 | `gen-ryu-min/GenRyuMin2TW-B.otf` | 16217516 | `5e7d2c11cf9860c94ac7d1fba742329f6015f7042c736232e1e69eb8ab12d5da` | `GenRyuMin2TW-B` | 2.100 | `genRyu-OFL.txt` |
| `genRyu`／`black` | 源流明體 特粗 | `gen-ryu-min/GenRyuMin2TW-H.otf` | 16022096 | `921295896e780b306d79580a8dcacf8ea6c0e1bd29e1853f3eed18264fa6d44a` | `GenRyuMin2TW-H` | 2.100 | `genRyu-OFL.txt` |
| `sweiSpring`／`regular` | 獅尾四季春 標準 | `swei-spring/SweiSpringCJKtc-Regular.ttf` | 17357244 | `8278b3f032b7bac5494d28ab1ddbe6b98959142a3e04a2b527c50c654dad6b80` | `SweiSpringCJKtc-Regular` | 1.068 | `sweiSpring-OFL.txt` |
| `sweiSpring` | 獅尾四季春 | `swei-spring/SweiSpringCJKtc-Bold.ttf` | 17336124 | `2bf4d16b849c4a87242c3f38817f18d45cf2a04d244fc3420dd5771d78b078fb` | `SweiSpringCJKtc-Bold` | 1.068 | `sweiSpring-OFL.txt` |
| `sweiSpring`／`black` | 獅尾四季春 特粗 | `swei-spring/SweiSpringCJKtc-Black.ttf` | 17730092 | `7f71afb558abf3b599094119616502a29cdf31a339f8cf2223cec999f8995e56` | `SweiSpringCJKtc-Black` | 1.068 | `sweiSpring-OFL.txt` |
| `sweiSugar`／`regular` | 獅尾加糖宋體 標準 | `swei-sugar/SweiSugarCJKtc-Regular.ttf` | 28960864 | `2e930dbafa3f5878df4de9fb773c5a4c9da0b658dd9219d62fd1a928db61447a` | `SweiSugarCJKtc-Regular` | 1.0 | `sweiSugar-OFL.txt` |
| `sweiSugar` | 獅尾加糖宋體 | `swei-sugar/SweiSugarCJKtc-Bold.ttf` | 28989908 | `c71c1d5196e49211c5232df39210df2c6fbea0b60245cb8ef9fc7edd37a1a30c` | `SweiSugarCJKtc-Bold` | 1.0 | `sweiSugar-OFL.txt` |
| `sweiSugar`／`black` | 獅尾加糖宋體 特粗 | `swei-sugar/SweiSugarCJKtc-Black.ttf` | 29001120 | `f39f956fc4a7f9f6729c62047da0c9376c56653ff7d6912a3b7032c490b449e3` | `SweiSugarCJKtc-Black` | 1.0 | `sweiSugar-OFL.txt` |
| `chironSung`／`regular` | 昭源宋體 標準 | `chiron-sung-hk/ChironSungHK-R.otf` | 24164960 | `d53da9ffb3593a6dcce34f9e4a5d94369c7e619efa1b3d9a60717c7d72aa65d0` | `ChironSungHK-Regular` | 1.024 | `chironSung-OFL.txt` |
| `chironSung` | 昭源宋體 | `chiron-sung-hk/ChironSungHK-B.otf` | 26585108 | `bc3f911227c98ae45caf31147201c29dd3cf14fc2c84af72936f4ef6067b397d` | `ChironSungHK-Bold` | 1.024 | `chironSung-OFL.txt` |
| `chironSung`／`black` | 昭源宋體 特粗 | `chiron-sung-hk/ChironSungHK-H.otf` | 24661440 | `2465ebd8119e0086bd1be03556d60dd6a3a2988f1579a962532ddb8c6b877cfa` | `ChironSungHK-Heavy` | 1.024 | `chironSung-OFL.txt` |
| `cactusSerif` | 仙人掌明體 | `cactus-classical-serif/CactusClassicalSerif-Regular.ttf` | 28502932 | `ecbd58961db922392d7fecfafa3681fefaeec0c399b860ab6940ba700f7da055` | `CactusClassicalSerif-Regular` | 1.005 | `cactusSerif-OFL.txt` |
| `twSung` | 全字庫正宋體 | `tw-sung/TW-Sung-98_1.ttf` | 35320040 | `9a3b74fe1a69fe1b3470b5ed780bf678c42a25cef93a13f280a5f31f795f0c56` | `TW-Sung-98_1` | 11503.01 | `twSung-OGDL.txt`、`twSung-OFL.txt` |
| `thenKhung` | 宇文天穹 | `uoqmun-thenkhung/UoqMunThenKhung-Regular.ttf` | 4901688 | `943a23eb10d40ca85ee08491c0e3fb3adbc4bd111ef1f93526a4f766a8e66fbd` | `UoqMunThenKhung-Regular` | 1.197 | `thenKhung-OFL.txt` |
| `lxgwWenKai`／`regular` | 霞鶩文楷 TC 標準 | `lxgw-wenkai-tc/LXGWWenKaiTC-Regular.ttf` | 15267616 | `b1a0795862c1415bf3f393ea50b2a4ea6275012cf5bad3f94feeb1222f555731` | `LXGWWenKaiTC-Regular` | 1.522 | `lxgwWenKai-OFL.txt` |
| `lxgwWenKai` | 霞鶩文楷 TC | `lxgw-wenkai-tc/LXGWWenKaiTC-Medium.ttf` | 15025056 | `94ca2870022fb8e4f90e2887524603690598142d17b620dfae318f1818ba8e17` | `LXGWWenKaiTC-Medium` | 1.522 | `lxgwWenKai-OFL.txt` |
| `twKai` | 全字庫正楷體 | `tw-kai/TW-Kai-98_1.ttf` | 36925608 | `d5e8d7d8743c5cf816bdeb393a443f65105a8130266a04c19560e1d3401b28f0` | `TW-Kai-98_1` | 11508.01 | `twKai-OGDL.txt`、`twKai-OFL.txt` |
| `eduKai` | 教育部標準楷書 | `edu-kai/edukai-5.0.ttf` | 15820500 | `99ae11cc1ba0ee14d43da5336f2c555b17a3bf551f7203f42da4f7fbdfcf7b7b` | `TW-MOE-Std-Kai` | 5.00, December, 2023 | `eduKai-CCBYND.txt` |
| `arphicUKai` | 文鼎 PL 中楷 | `arphic-ukai/ukai.ttc` | 17151049 | `cfc758e69386a21bade8cb3b373fda20d7f2fac6e8904ced2ded98588b63e274` | `UKaiTW` | 0.2.20080216.1 | `arphicUKai-APL.txt` |
| `naikai`／`regular` | 內海字體 標準 | `naikai/NaikaiFont-Regular.ttf` | 26254192 | `d3320b822131540d5e3cc9737f7b458aeb1c0ca76fe89aeaa1b76001f54e503e` | `NaikaiFont-Regular` | 1.89 | `naikai-OFL.txt` |
| `naikai`／`semibold` | 內海字體 半粗 | `naikai/NaikaiFont-SemiBold.ttf` | 37776240 | `d88f0931677cb43c276148e76d5c1f3c9a6c4089ee8b747fd9b2e59759b2b27b` | `NaikaiFont-SemiBold` | 1.89 | `naikai-OFL.txt` |
| `naikai` | 內海字體 | `naikai/NaikaiFont-Bold.ttf` | 38622668 | `43a3822eedd0d7d5fe464fc462c799f5ff2de8eaeabc0825ba09607b1035b621` | `NaikaiFont-Bold` | 1.89 | `naikai-OFL.txt` |
| `xiaolai` | 小賴字體 | `xiaolai/Xiaolai-Regular.ttf` | 22220806 | `e2f68daf0e72777a8cf58bc83de1b98634b251e537ddbfca24b0ae50d1802da2` | `Xiaolai` | 3.126 | `xiaolai-OFL.txt` |
| `yozai`／`regular` | 悠哉字體 標準 | `yozai/Yozai-Regular.ttf` | 15605374 | `25071998a0fe6a72f54c235e714986d259633e5ff670b1a2b5e264387f3316ac` | `Yozai-Regular` | 0.868 | `yozai-OFL.txt` |
| `yozai` | 悠哉字體 | `yozai/Yozai-Medium.ttf` | 15238394 | `05f50f252b45197d0d6148a4abc3e37c7cd4cfdf03c955b57c25d53d924f835f` | `Yozai-Medium` | 0.868 | `yozai-OFL.txt` |
| `nani`／`regular` | 何某手寫體 標準 | `nanifont/NaniFont-Regular.ttf` | 17799572 | `3fb7b030f853f2efc4d97dd28fae08a6fa93a565fc91a8f585897e0d53716c1c` | `NaniFont-Regular` | 1.046 | `nani-OFL.txt` |
| `nani` | 何某手寫體 | `nanifont/NaniFont-Bold.ttf` | 18508716 | `1b5da5077665309289ba3e62c2fe4b1b788c800dd638af8113bff9fed96b588e` | `NaniFont-Bold` | 1.046 | `nani-OFL.txt` |
| `lxgwMarker` | 霞鶩漫黑 | `lxgw-marker-gothic/LXGWMarkerGothic-Regular.ttf` | 3179616 | `9a1e46379442856b9fc64de1d9bd4120903780990e28d99fd6415cadee78a47d` | `LXGWMarkerGothic-Regular` | 1.003 | `lxgwMarker-OFL.txt` |
| `kurewa`／`regular` | 苦累蛙圓體 標準 | `kurewa-gothic/KurewaGothicCjkTc-Regular.ttf` | 31158716 | `da6d76a895ac0a8ba80edeb5b99dec0b0e8e205040244e37ba0a39054fa5289e` | `KurewaGothicCjkTc-Regular` | 1.100 | `kurewa-OFL.txt` |
| `kurewa` | 苦累蛙圓體 | `kurewa-gothic/KurewaGothicCjkTc-Bold.ttf` | 36472060 | `f3c77d55c30ebf113c1e9375ac500df23082dc76221e3299d9ba581eb54bf515` | `KurewaGothicCjkTc-Bold` | 1.100 | `kurewa-OFL.txt` |
| `popGothic`／`regular` | 大波浪圓體 標準 | `pop-gothic/PopGothicCjkTc-Regular.ttf` | 8371820 | `3094ba8fa82bebdfbe4fd168c7460f1023d7bf8a515696a3dedc960f74bbba4a` | `PopGothicCjkTc-Regular` | 2.145 | `popGothic-OFL.txt` |
| `popGothic` | 大波浪圓體 | `pop-gothic/PopGothicCjkTc-Bold.ttf` | 10298960 | `6f40a3fcfed7128bebca12b0b27c5cf4a0982e4312143df1390d1645fa4e12e7` | `PopGothicCjkTc-Bold` | 2.145 | `popGothic-OFL.txt` |
| `wdxl` | WD-XL 滑油字 | `wd-xl-lubrifont/WD-XLLubrifontTC-Regular.otf` | 6161104 | `51c179e927526a9acd88b7722909e44c958133733ca316e824f812a28713768b` | `WD-XLLubrifontTC-Regular` | 2.100 | `wdxl-OFL.txt` |
| `cubic11` | 俐方體 11 號 | `cubic-11/Cubic_11.ttf` | 2773732 | `0193f5f033612496df6b45ee92ac3b335bc6a5a24ff95da55ca87b33e57dcf62` | `Cubic_11` | 1.451 | `cubic11-OFL.txt` |

## 著作權聲明（授權頁顯示用）

逐字取自**字型檔的 copyright 欄位**（`kCTFontCopyrightNameKey`），不改寫。粉圓與芫荽的字型欄位和授權檔首段內容一致；思源宋體的上游 LICENSE 沒有著作權行，所以一律以字型檔欄位為準（粉圓欄位中的 `(x)` 是原文，照錄）。

- **粉圓**：

  ```
  [Kosugi Maru]
  Copyright (c) 2010 MOTOYA CO.,LTD.

  [Varela Round]
  Copyright (x) 2011-2016 The Varela Round Project Authors (https://github.com/alefalefalef/Varela-Round-Hebrew/), with Reserved Font Names 'Varela' and 'Varela Round'.

  [jf open huninn]
  Copyright (c) 2020-2024 The jf open huninn font is redistributed by justfont Co., Ltd., with Reserved Font Names 'open huninn' and 'huninn' under SIL Open Font License. The Hanzi part of this project was derived from Kosugi Maru under Apache-2.0 (https://www.apache.org/licenses/LICENSE-2.0).
  ```
- **思源宋體**：`© 2017-2024 Adobe (http://www.adobe.com/).`
- **芫荽**：`Copyright 2025 The Iansui Project Authors (https://github.com/ButTaiwan/iansui)`
- **辰宇落雁體**：字型檔有英文與繁中兩筆 copyright 記錄，兩行都列（英文在前）。先前紀錄為上游 repo 沒有附授權檔；TASK-89 查證的固定 commit `6e36815b0bec9f4f948298698d00b27a5f0b65c1` 已有 [license.txt](https://github.com/Chenyu-otf/chenyuluoyan_thin/blob/6e36815b0bec9f4f948298698d00b27a5f0b65c1/license.txt)。既有 `chenyuluoyan-OFL.txt` 由 Lead 依字型內嵌聲明與 OFL 1.1 全文整理（與 `dayscam-fonts@v2` 的 `chenyuluoyan/OFL.txt` 逐字相同）。

  ```
  Copyright (c) 2022, Wang, Li-Yu & Liu, Wei-Chen.
  (c) 2022 王立宇、劉韋辰 版權所有。
  ```

### TASK-142 的 30 套

字型檔的 copyright 欄位逐字照錄，英文在前、繁中（若有）在後，`\r\n` 一律寫成換行；各檔相同者只列一次。字型檔欄位是空的有 7 套，改取該套隨檔授權檔（或發行 zip 內授權檔）首段的著作權行，照錄：源石黑體、源泉圓體、源雲明體、源流明體（發行 zip 的 `SIL_Open_Font_License_1.1.txt`）、仙人掌明體（上游 `license.md`）；獅尾四季春、獅尾加糖宋體的字型與授權檔都沒有著作權人（授權檔是未填寫的 OFL 範本），授權頁寫明這一點與作者。

- **思源黑體**：

  ```
  © 2014-2021 Adobe (http://www.adobe.com/).
  ```
- **台北黑體**：
  `TaipeiSansTCBeta-Light.ttf`

  ```
  Taipei Sans TC is a modified font of Source Han Sans'.
  ```
  `TaipeiSansTCBeta-Regular.ttf`

  ```
  Taipei Sans TC is a modified font of Source Han Sans.
  ```
  `TaipeiSansTCBeta-Bold.ttf`

  ```
  Taipei Sans TC Beta is a modified font of Source Han Sans.
  ```
- **源石黑體**：

  ```
  Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font
  Name 'Source'. Source is a trademark of Adobe in the United States
  and/or other countries.
  ```
- **昭源黑體**：

  ```
  © 2014-2025 Adobe (http://www.adobe.com/).
  ```
- **朱古力黑體**：

  ```
  Copyright 2025 The Chocolate Classical Sans Project Authors (https://github.com/MoonlitOwen/ChocolateSans)
  ```
- **未來熒黑**：

  ```
  Glow Sans (c) 2021 Project Welai
  ```
- **源泉圓體**：

  ```
  Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font
  Name 'Source'. Source is a trademark of Adobe in the United States
  and/or other countries.
  ```
- **獅尾圓體**：

  ```
  Copyright (c) 2020, Chun yu Yao
  ```
- **昭源環方**：

  ```
  © 2014-2025 Adobe (http://www.adobe.com/).
  ```
- **源雲明體**：

  ```
  Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font
  Name 'Source'. Source is a trademark of Adobe in the United States
  and/or other countries.
  ```
- **源流明體**：

  ```
  Copyright 2014-2019 Adobe (http://www.adobe.com/), with Reserved Font
  Name 'Source'. Source is a trademark of Adobe in the United States
  and/or other countries.
  ```
- **獅尾四季春**：

  ```
  字型檔與授權檔都沒有填寫著作權人（授權檔是未填寫的 SIL OFL 1.1 範本）。作者：Max（https://github.com/max32002/swei-spring）。
  ```
- **獅尾加糖宋體**：

  ```
  字型檔與授權檔都沒有填寫著作權人（授權檔是未填寫的 SIL OFL 1.1 範本）。作者：max32002（https://github.com/max32002/swei-sugar）。
  ```
- **昭源宋體**：

  ```
  © 2017-2024 Adobe (http://www.adobe.com/).
  ```
- **仙人掌明體**：

  ```
  Copyright 2025 The Cactus Serif Project Authors (https://github.com/MoonlitOwen/CactusSerif)
  ```
- **全字庫正宋體**：

  ```
  (c)2026 Ministry of Digital Affairs. You can use any of the following terms as needed. 1. Open Government Data License, version 1.0(https://data.gov.tw/en/license). 2. the SIL Open Font License, version 1.1. (https://scripts.sil.org/OFL)
  (c)2026數位發展部。使用者可依需求擇一使用以下條款：1.「政府資料開放授權條款-第一版」(https://data.gov.tw/license) ；2. 「開源字型授權1.1版(OFL 1.1) 」(https://scripts.sil.org/OFL)
  ```
- **宇文天穹**：

  ```
  Copyright 2025 The UoqMunThenKhung Project Authors (https://github.com/MoonlitOwen/ThenKhung)
  ```
- **霞鶩文楷 TC**：

  ```
  Copyright 2022-2026 LXGW (https://github.com/lxgw/LxgwWenkaiTC)
  Copyright 2020 The Klee Project Authors (https://github.com/fontworks-fonts/Klee)
  ```
- **全字庫正楷體**：

  ```
  (c)2026 Ministry of Digital Affairs. You can use any of the following terms as needed. 1. Open Government Data License, version 1.0(https://data.gov.tw/en/license). 2. the SIL Open Font License, version 1.1. (https://scripts.sil.org/OFL)
  (c)2026數位發展部。使用者可依需求擇一使用以下條款：1.「政府資料開放授權條款-第一版」(https://data.gov.tw/license) ；2. 「開源字型授權1.1版(OFL 1.1) 」(https://scripts.sil.org/OFL)
  ```
- **教育部標準楷書**：

  ```
  (c) This license allows for redistribution, commercial and non-commercial, as long as it is passed along unchanged and in whole, with credit to MOE.
  (c)本字形檔採用創用CC姓名標示-禁止改作3.0 臺灣版授權。如需引用，請標示中華民國教育部。
  ```
- **文鼎 PL 中楷**：

  ```
  This font is derieved from the "AR PL " and "AR PL " fonts. ((c) Copyright 1994-1999, Arphic Technology Co., Ltd.)

  Modifications have been made to add, replace and modify glyphs, change encoding and add bitmap representations. ((c) Copyright 2003-2007 Arne Goetje <arne@ubuntu.com>)

  This font is published as par
  ```
- **內海字體**：

  ```
  Nozomi Seto
  內海字體
  ```
- **小賴字體**：

  ```
  Copyright 2020-2024 LXGW (https://github.com/lxgw/kose-font)
  Copyright 2014 Nozomi Seto (https://ja.osdn.net/projects/setofont/)
  ```
- **悠哉字體**：

  ```
  Copyright 2020, 2024 LXGW (https://github.com/lxgw/yozai-font)
  Original Font Data Copyright (C) Y.OzVox.
  ```
- **何某手寫體**：

  ```
  Copyright (c) 2016-2020, Nanigashitei.
  ```
- **霞鶩漫黑**：

  ```
  Copyright 2024 The LXGW Marker Gothic Project Authors (https://github.com/lxgw/LxgwMarkerGothic)
  ```
- **苦累蛙圓體**：

  ```
  Copyright 2021 The Kurewa Project Authors (https://github.com/max32002/kurewa-gothic)
  ```
- **大波浪圓體**：

  ```
  Copyright 2021 The PopGothic Project Authors (https://github.com/max32002/pop-gothic)
  ```
- **WD-XL 滑油字**：

  ```
  Copyright 2020-2025 The WD-XL Lubrifont Project Authors (https://github.com/NightFurySL2001/WD-XL-font)
  版權 2020-2025 WD-XL 滑油字計劃作者 (https://github.com/NightFurySL2001/WD-XL-font)
  ```
- **俐方體 11 號**：

  ```
  [Cubic 11]
  Copyright (c) 2022-2025 ACh
  Copyright (c) 2022 Cubic 11 Project Authors
  These fonts are free software.
  Unlimited permission is granted to use, copy, and distribute them, with or without modification, either commercially or noncommercially.
  THESE FONTS ARE PROVIDED "AS IS" WITHOUT WARRANTY.



  [JF Dot M+H 12]
  Copyright(c) 2005 M+ FONTS PROJECT
  [M+ BITMAP FONTS]
  Copyright (C) 2002-2004 COZ
  These fonts are free software.
  Unlimited permission is granted to use, copy, and distribute it, with or without modification, either commercially and noncommercially.
  THESE FONTS ARE PROVIDED "AS IS" WITHOUT WARRANTY.
  [Cubic 11]
  Copyright (c) 2022-2025 ACh
  Copyright (c) 2022 Cubic 11 Project Authors
  These fonts are free software.
  Unlimited permission is granted to use, copy, and distribute them, with or without modification, either commercially or noncommercially.
  THESE FONTS ARE PROVIDED "AS IS" WITHOUT WARRANTY.
  此字型是免費的。
  無論您是否進行對本字型進行商業或非商業性修改，均可無限制地使用，複製和分發它們。
  本字型的衍生品之授權必須與此字型相同，且不作任何擔保。
  [JF Dot M+H 12]
  Copyright(c) 2005 M+ FONTS PROJECT
  [M+ BITMAP FONTS]
  Copyright (C) 2002-2004 COZ
  These fonts are free software.
  Unlimited permission is granted to use, copy, and distribute it, with or without modification, either commercially and noncommercially.
  THESE FONTS ARE PROVIDED "AS IS" WITHOUT WARRANTY.
  これらのフォントはフリー（自由な）ソフトウエアです。
  あらゆる改変の有無に関わらず、また商業的な利用であっても、自由にご利用、複製、再配布することができますが、全て無保証とさせていただきます。
  ```

## 預覽圖

`swift scripts/render-font-previews.swift <四個開源字型檔所在資料夾>` 產生 `DaysCam/Assets.xcassets/FontPreviews/<fontID>.imageset`（17pt、@2x／@3x 模板圖）。開源字型直接從檔案建立（先比對 SHA-256），不會畫到 Mac 上安裝的同名字型；系統字型經 CoreText 比對。取得的字型名稱不符 PRD-0.3 §4.1 時以非零狀態結束。

TASK-78：字型頁與 VoiceOver 使用 `FontCatalogEntry.fullName`；toast、授權頁與其他簡稱沿用 `displayName`。預覽圖以完整名稱、17pt、210pt 文字寬換行，保留 4pt 透明邊界（保留負 side bearing 與下緣字形）；列表使用原始點尺寸，不再以 24pt 高度縮小兩行圖。下載版本與 PostScript 名稱不變，完整名稱依系統 CoreText 在地化 fullName／字型 name table ID 4 查證（對照表見 PR #323）。

## TASK-89 字重下載與上游授權紀錄

- 名單依 Issue #362 最後的查證表與 Lead 裁定；思源宋體預設仍為 `bold`，新增 Regular／Black 不覆寫 Bold 或既有 v2 tag。
- 新增 OTF 取自 notofonts/noto-cjk `f8d157532fbfaeda587e826d4cd5b21a49186f7c` 的 `Serif/SubsetOTF/TC/`，原檔不改寫放進 `dayscam-fonts@v3`（#378）。TASK-91 起 App 一律從 `v3` 下載全部開源字型，不再直接連上游 URL；檔案路徑、bytes、SHA-256 與 `v2` 相同，已下載的使用者不需重新下載。
- 三個 Noto OTF 各自的 copyright 均為 `© 2017-2024 Adobe (http://www.adobe.com/).`；[上游 Serif/LICENSE](https://github.com/notofonts/noto-cjk/blob/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Serif/LICENSE) 為 SIL OFL 1.1，與 App 的 `notoSerifTC-OFL.txt` 一併保留，授權頁須逐 face 列檔名與 copyright。
- 辰宇 Thin 固定 commit 的上游 `license.txt` 另有上游著作權段落；App 現有逐字字型內嵌英文／繁中 copyright 與 OFL 全文繼續保留，不以新查證覆寫舊 tag。
- Default face 的磁碟路徑仍為 `<fontID>.<ext>`；其他字重為 `<fontID>-<weightID>.<ext>`。系統 matching 與持久化改按指定 face，舊 `downloadedSystemFontIDs` 僅代表預設 face；新 `downloadedSystemFontWeights` 記錄非預設的 `<fontID>/<weightID>`，讀取時相容舊紀錄。

## TASK-142 新增的 30 套（v4，#494）

使用者 2026-10-12 裁決「PR#460 裡找到的字型全部加入」。名單、選定字重與來源見 [`research/fonts-tc-2.md`](research/fonts-tc-2.md) §2；每個檔案的 bytes 與 SHA-256 與該文件 §6 相同（台北黑體以 §6 為準），原檔不子集化、不改名（PRD-0.3 A-1）。**不含**清松手寫體、莫大毛筆、正風毛筆（授權待作者確認，§5 第 1–2 項）。

### 類型與字重

清單目前把這些字型放在「可下載」組，依 catalog 順序（黑、圓、宋、楷、手寫、可愛）；類型記在 `FontCatalog.downloadFamilies`，待 TASK-120（#453）改為組內依類型排序時使用。預設字重是新選取時用的那一個：有 Bold 取 Bold，其餘取最粗的。

| 類型 | 字型 | 字重（預設以 ★ 標示） | 預設字重 PostScript | 預設字重大小 |
|---|---|---|---|---|
| 黑 | 思源黑體 | 標準、粗★、特粗 | `NotoSansTC-Bold` | 5.8 MB |
| 黑 | 台北黑體 | 細、標準、粗★ | `TaipeiSansTCBeta-Bold` | 21.7 MB |
| 黑 | 源石黑體 | 標準、粗★、特粗 | `GenSekiGothic2TW-B` | 15.0 MB |
| 黑 | 昭源黑體 | 標準、粗★、特粗 | `ChironHeiHK-Bold` | 17.1 MB |
| 黑 | 朱古力黑體 | 標準★ | `ChocolateClassicalSans-Regular` | 12.2 MB |
| 黑 | 未來熒黑 | 標準、粗★、特粗 | `GlowSansTC-Normal-Bold` | 9.0 MB |
| 圓 | 源泉圓體 | 標準、粗★、特粗 | `GenSenRounded2TW-B` | 15.8 MB |
| 圓 | 獅尾圓體 | 標準、粗★、特粗 | `SweiGothicCJKtc-Bold` | 15.8 MB |
| 圓 | 昭源環方 | 標準、粗★、特粗 | `ChironGoRoundTC-Bold` | 20.5 MB |
| 宋 | 源雲明體 | 標準、中粗、半粗★ | `GenWanMin2TW-SB` | 22.6 MB |
| 宋 | 源流明體 | 標準、粗★、特粗 | `GenRyuMin2TW-B` | 16.2 MB |
| 宋 | 獅尾四季春 | 標準、粗★、特粗 | `SweiSpringCJKtc-Bold` | 17.3 MB |
| 宋 | 獅尾加糖宋體 | 標準、粗★、特粗 | `SweiSugarCJKtc-Bold` | 29.0 MB |
| 宋 | 昭源宋體 | 標準、粗★、特粗 | `ChironSungHK-Bold` | 26.6 MB |
| 宋 | 仙人掌明體 | 標準★ | `CactusClassicalSerif-Regular` | 28.5 MB |
| 宋 | 全字庫正宋體 | 標準★ | `TW-Sung-98_1` | 35.3 MB |
| 宋 | 宇文天穹 | 標準★ | `UoqMunThenKhung-Regular` | 4.9 MB |
| 楷 | 霞鶩文楷 TC | 標準、中粗★ | `LXGWWenKaiTC-Medium` | 15.0 MB |
| 楷 | 全字庫正楷體 | 標準★ | `TW-Kai-98_1` | 36.9 MB |
| 楷 | 教育部標準楷書 | 標準★ | `TW-MOE-Std-Kai` | 15.8 MB |
| 楷 | 文鼎 PL 中楷 | 標準★ | `UKaiTW` | 17.2 MB |
| 手寫 | 內海字體 | 標準、半粗、粗★ | `NaikaiFont-Bold` | 38.6 MB |
| 手寫 | 小賴字體 | 標準★ | `Xiaolai` | 22.2 MB |
| 手寫 | 悠哉字體 | 標準、中粗★ | `Yozai-Medium` | 15.2 MB |
| 手寫 | 何某手寫體 | 標準、粗★ | `NaniFont-Bold` | 18.5 MB |
| 手寫 | 霞鶩漫黑 | 標準★ | `LXGWMarkerGothic-Regular` | 3.2 MB |
| 手寫 | 苦累蛙圓體 | 標準、粗★ | `KurewaGothicCjkTc-Bold` | 36.5 MB |
| 可愛 | 大波浪圓體 | 標準、粗★ | `PopGothicCjkTc-Bold` | 10.3 MB |
| 可愛 | WD-XL 滑油字 | 標準★ | `WD-XLLubrifontTC-Regular` | 6.2 MB |
| 可愛 | 俐方體 11 號 | 標準★ | `Cubic_11` | 2.8 MB |

### 授權與來源的特殊處理

- **全字庫正宋體、正楷體**：字型內嵌聲明為「(c)2026 數位發展部；使用者可依需求擇一使用『政府資料開放授權條款－第 1 版』或 OFL 1.1」，兩份全文都附（`twSung-OGDL.txt`／`-OFL.txt`，正楷同）。授權頁在名稱下註明來源「全字庫（數位發展部）」。
- **教育部標準楷書**：CC BY-ND 3.0 TW，須標示「中華民國教育部」且不得改作；App 只下載、不修改原檔。授權頁在名稱下標示著作權人，並附 CC BY-ND 3.0 TW 全文（`eduKai-CCBYND.txt`，取自 creativecommons.org 的繁中版條款，標頭加上教育部說明文件的標示要求）。字型內部版本 5.00（2023-12），教育部說明文件寫 5.1（調查 §5 第 6 項，使用者已接受）。
- **文鼎 PL 中楷**：Arphic Public License，授權全文取自字型 `name` 表第 13 筆（6888 字元；與 Debian 套件 `copyright` 檔內的 APL 條文逐字相同，比對時忽略空白）。檔案是 `ukai.ttc`（含 4 個字面，字型內 PostScript 名稱 `UKaiTW` 是台灣字面），App 以整個集合註冊，存檔副檔名為 `.ttc`。copyleft 授權與 App Store 散布條款是否相容為調查 §5 第 5 項，使用者已接受。
- **未來熒黑**：字型內嵌 OFL、repo 的 `LICENSE` 是 MIT（調查 §2.1 註 2）；兩份都附。字型缺「值告填巔慎教清真鎮顛」10 字（4798／4808），這些字畫蘋方（見 142.4 紀錄）。
- **台北黑體**：沒有隨檔授權檔，OFL 1.1 全文以字型 `name` 表內嵌的聲明（OFL 1.1）加官方下載頁的聲明組成（`taipeiSans-OFL.txt`，標頭寫明衍生自 Source Han Sans）。只有 Google 雲端硬碟的 Beta 檔，無版本化 release；檔案已存進 `dayscam-fonts@v4`，以 SHA-256 為準。
- **獅尾圓體／四季春／加糖宋體**：repo 的 OFL 是未填寫著作權人的範本，字型 `name` 表的 RFN 也是佔位字；授權意思明確是 OFL 1.1，原樣附上。
- **其餘**：OFL 1.1 全文取自各上游 repo／release 的授權檔（`dayscam-fonts` 各資料夾的 `OFL.txt` 與 App 內 `<fontID>-OFL.txt` 逐字相同）。

### 大檔與 jsDelivr 實測

單檔超過 30 MB 的有內海字體 SemiBold／Bold、苦累蛙圓體 Bold、全字庫正楷體、全字庫正宋體（照放，因為是使用者自選下載）。

#### `v4` 的 63 個網址實測（2026-10-12，tag 推上後）

- **raw（備援）**：63 個網址全部回 200，`content-length` 等於本表 bytes。其中 19 個 jsDelivr 不服務的檔案已用 `curl` 從 raw 完整下載，大小與 SHA-256 全部通過。
- **jsDelivr（主要）**：44 個檔案（最大 20,659,344 bytes）回 200，已完整下載，大小與 SHA-256 全部通過。
- **jsDelivr 對 19 個檔案回 403**（回應內文「File size exceeded the configured limit of 20 MB」）：全部是超過 20 MiB（20,971,520 bytes）的檔案，最小 21,737,516 bytes，與 20 MiB 上限吻合；調查標 ⚠ 的 5 個大檔（內海 SemiBold／Bold、苦累蛙 Bold、全字庫正楷／正宋）都在其中。這些檔案由 App 的備援網址（raw）下載；`FontLibrary` 對主要網址的任何非 2xx 都改試備援（`FontDownloader` 把非 2xx 視為 `FontFetchError.other`），XCTest `test_acceptance_142_3_everyFaceDownloadsAndDeletes` 以「jsDelivr 拒絕 > 20 MiB」的假網路證明這 19 個檔案都由 raw 下載成功。
- tag 剛推上時，jsDelivr 第一次請求有幾個 20 MiB 以下的小檔回過 403，數分鐘內重試即 200（冷啟動）；App 遇到時同樣會走 raw 備援，不影響下載。

jsDelivr 不服務、由 raw 下載的 19 個檔案：

| 路徑 | bytes | MB |
|---|---|---|
| `taipei-sans-tc/TaipeiSansTCBeta-Bold.ttf` | 21737516 | 21.7 |
| `xiaolai/Xiaolai-Regular.ttf` | 22220806 | 22.2 |
| `gen-wan-min/GenWanMin2TW-SB.otf` | 22614524 | 22.6 |
| `gen-wan-min/GenWanMin2TW-M.otf` | 22710256 | 22.7 |
| `gen-wan-min/GenWanMin2TW-R.otf` | 22772928 | 22.8 |
| `chiron-sung-hk/ChironSungHK-R.otf` | 24164960 | 24.2 |
| `chiron-sung-hk/ChironSungHK-H.otf` | 24661440 | 24.7 |
| `naikai/NaikaiFont-Regular.ttf` | 26254192 | 26.3 |
| `chiron-sung-hk/ChironSungHK-B.otf` | 26585108 | 26.6 |
| `cactus-classical-serif/CactusClassicalSerif-Regular.ttf` | 28502932 | 28.5 |
| `swei-sugar/SweiSugarCJKtc-Regular.ttf` | 28960864 | 29.0 |
| `swei-sugar/SweiSugarCJKtc-Bold.ttf` | 28989908 | 29.0 |
| `swei-sugar/SweiSugarCJKtc-Black.ttf` | 29001120 | 29.0 |
| `kurewa-gothic/KurewaGothicCjkTc-Regular.ttf` | 31158716 | 31.2 |
| `tw-sung/TW-Sung-98_1.ttf` | 35320040 | 35.3 |
| `kurewa-gothic/KurewaGothicCjkTc-Bold.ttf` | 36472060 | 36.5 |
| `tw-kai/TW-Kai-98_1.ttf` | 36925608 | 36.9 |
| `naikai/NaikaiFont-SemiBold.ttf` | 37776240 | 37.8 |
| `naikai/NaikaiFont-Bold.ttf` | 38622668 | 38.6 |

### 142.4 烘焙與觀景窗一致性

用 #73 §C（`docs/research/fonts-tc.md`）的方法：真的 `OverlayRenderer.bake`（1200 × 1600 照片、白字、無外框無陰影）烘焙「2026.10.11 我的紀錄 第 128 天」，與觀景窗畫法（SwiftUI `Text`＋`Font(uiFont)`，同字級）比較；用 CoreText 逐段列出實際用的字型。每套取最粗字重，在 rinclaw 的 iOS 26.3 模擬器（iPhone 16 Pro Max）執行；程式放在 `docs/research/fonts-tc-2/scripts/bake-probe-tests.swift.txt`（平常不跑）。

結果：**30 套全部整串由該字型畫出，沒有任何一段退回蘋方；烘焙與觀景窗的墨跡寬度逐像素相同；每套的寬度都與蘋方（915）不同。** 比較圖放在 PR 的 `qa-screenshots` 分支。

| 字型 | 最粗字重 | PostScript | 烘焙寬 | 觀景窗寬 |
|---|---|---|---|---|
| notoSansTC | black | `NotoSansTC-Black` | 940 | 940 |
| taipeiSans | bold | `TaipeiSansTCBeta-Bold` | 921 | 921 |
| genSeki | black | `GenSekiGothic2TW-H` | 939 | 939 |
| chironHei | black | `ChironHeiHK-Heavy` | 937 | 937 |
| chocolateSans | regular | `ChocolateClassicalSans-Regular` | 888 | 888 |
| glowSans | black | `GlowSansTC-Normal-Heavy` | 909 | 909 |
| genSen | black | `GenSenRounded2TW-H` | 937 | 937 |
| sweiGothic | black | `SweiGothicCJKtc-Black` | 938 | 938 |
| chironGoRound | black | `ChironGoRoundTC-Heavy` | 937 | 937 |
| genWan | semibold | `GenWanMin2TW-SB` | 887 | 887 |
| genRyu | black | `GenRyuMin2TW-H` | 903 | 903 |
| sweiSpring | black | `SweiSpringCJKtc-Black` | 941 | 941 |
| sweiSugar | black | `SweiSugarCJKtc-Black` | 926 | 926 |
| chironSung | black | `ChironSungHK-Heavy` | 926 | 926 |
| cactusSerif | regular | `CactusClassicalSerif-Regular` | 851 | 851 |
| twSung | regular | `TW-Sung-98_1` | 951 | 951 |
| thenKhung | regular | `UoqMunThenKhung-Regular` | 931 | 931 |
| lxgwWenKai | medium | `LXGWWenKaiTC-Medium` | 964 | 964 |
| twKai | regular | `TW-Kai-98_1` | 947 | 947 |
| eduKai | regular | `TW-MOE-Std-Kai` | 947 | 947 |
| arphicUKai | regular | `UKaiTW` | 949 | 949 |
| naikai | bold | `NaikaiFont-Bold` | 946 | 946 |
| xiaolai | regular | `Xiaolai` | 944 | 944 |
| yozai | medium | `Yozai-Medium` | 931 | 931 |
| nani | bold | `NaniFont-Bold` | 906 | 906 |
| lxgwMarker | regular | `LXGWMarkerGothic-Regular` | 864 | 864 |
| kurewa | bold | `KurewaGothicCjkTc-Bold` | 852 | 852 |
| popGothic | bold | `PopGothicCjkTc-Bold` | 1073 | 1073 |
| wdxl | regular | `WD-XLLubrifontTC-Regular` | 672 | 672 |
| cubic11 | regular | `Cubic_11` | 940 | 940 |

**未來熒黑缺字（照實記錄，不擋）**：字型缺「值告填巔慎教清真鎮顛」，這些字由 CoreText 退回 `PingFangTC-Semibold`，其餘文字仍是未來熒黑（實測分段：`值告填巔慎教清真鎮顛=PingFangTC-Semibold| 第 128 天=GlowSansTC-Normal-Heavy`）。觀景窗與烘焙使用同一個 `UIFont`，退回的結果一致。

### 預覽圖

30 套的預覽圖（`DaysCam/Assets.xcassets/FontPreviews/<fontID>.imageset`）用 `scripts/render-font-previews.swift` 產生：把 30 個預設字重的原檔放進同一個資料夾，`swift scripts/render-font-previews.swift <資料夾> <fontID ...>`。圖上的文字是清單名稱（FR-16.4，見下表），字型取各套的預設字重。

清單名稱取自預設字重原檔 `name` 表：第 4 筆（完整名稱）繁中（0x404）紀錄優先、沒有或與英文相同時用英文，不含版本號；多字重的家族在列上只顯示家族名（第 16 筆，沒有則第 1 筆，同樣繁中優先），字重由展開後的按鈕顯示。顯示名稱（`displayName`，toast、授權頁用）仍是中文簡稱。

**使用者裁決（2026-10-12）**：清單名稱照 name table 原樣，不改簡稱，包含「源石黑體月 B」「内海フォント-Bold」這類字型自己的寫法。

| fontID | 顯示名稱 | 清單／VoiceOver／預覽圖（完整名稱） | 多字重列（家族名） |
|---|---|---|---|
| `notoSansTC` | 思源黑體 | Noto Sans TC Bold | Noto Sans TC |
| `taipeiSans` | 台北黑體 | Taipei Sans TC Beta Bold | Taipei Sans TC Beta |
| `genSeki` | 源石黑體 | 源石黑體月 B | 源石黑體月 |
| `chironHei` | 昭源黑體 | Chiron Hei HK Bold | Chiron Hei HK |
| `chocolateSans` | 朱古力黑體 | 朱古力黑體 | — |
| `glowSans` | 未來熒黑 | 未來熒黑 Normal Bold | 未來熒黑 |
| `genSen` | 源泉圓體 | 源泉圓體月 B | 源泉圓體月 |
| `sweiGothic` | 獅尾圓體 | 獅尾圓體-Bold | 獅尾圓體 |
| `chironGoRound` | 昭源環方 | Chiron GoRound TC Bold | Chiron GoRound TC |
| `genWan` | 源雲明體 | 源雲明體月 SB | 源雲明體月 |
| `genRyu` | 源流明體 | 源流明體月 B | 源流明體月 |
| `sweiSpring` | 獅尾四季春 | 獅尾四季春-Bold | 獅尾四季春 |
| `sweiSugar` | 獅尾加糖宋體 | 獅尾加糖宋體-Bold | 獅尾加糖宋體 |
| `chironSung` | 昭源宋體 | Chiron Sung HK Bold | Chiron Sung HK |
| `cactusSerif` | 仙人掌明體 | 仙人掌明體 | — |
| `twSung` | 全字庫正宋體 | 全字庫正宋體 | — |
| `thenKhung` | 宇文天穹 | 宇文天穹 | — |
| `lxgwWenKai` | 霞鶩文楷 TC | LXGW WenKai TC Medium | 霞鶩文楷 TC |
| `twKai` | 全字庫正楷體 | 全字庫正楷體 | — |
| `eduKai` | 教育部標準楷書 | 教育部標準楷書 | — |
| `arphicUKai` | 文鼎 PL 中楷 | AR PL UKai TW | — |
| `naikai` | 內海字體 | 内海フォント-Bold | 內海字體 |
| `xiaolai` | 小賴字體 | Xiaolai | — |
| `yozai` | 悠哉字體 | Yozai Medium | Yozai |
| `nani` | 何某手寫體 | 何某手寫-Bold | 何某手寫 |
| `lxgwMarker` | 霞鶩漫黑 | LXGW Marker Gothic Regular | — |
| `kurewa` | 苦累蛙圓體 | 苦累蛙圓體 CJK TC-Bold | 苦累蛙圓體 CJK TC |
| `popGothic` | 大波浪圓體 | 大波浪圓體 CJK TC-Bold | 大波浪圓體 CJK TC |
| `wdxl` | WD-XL 滑油字 | WD-XL 滑油字 TC | — |
| `cubic11` | 俐方體 11 號 | 俐方體11號 | — |
