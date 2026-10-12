# 繁中開源字型候選調查（TASK-121，Issue #454）

> 調查卡產出，不改產品程式碼。調查日期 2026-10-12，環境：macOS（本機），fontTools 4.x、CoreText。
> 本文件**不決定要加哪幾套**，只提供候選表、排除理由與推薦，由使用者從比較稿挑選後，再由 Lead 開實作卡。
> 方法沿用上一輪 [`fonts-tc.md`](fonts-tc.md)（#73）§B；分類依 TASK-120（#453）：黑、圓、宋、楷、手寫、書法、可愛。

## 0. 結論摘要

- **開源候選共 33 套**（§2），4808 常用字涵蓋率全部 ≥ 99%。其中清松手寫體與 2 套書法字型的授權有疑慮，列在未確認事項（§5），不可當成可用。
- **推薦 14 套**（§3）：
  - 黑：思源黑體、台北黑體。
  - 圓：源泉圓體、昭源環方。
  - 宋：源流明體、昭源宋體。
  - 楷：霞鶩文楷 TC、全字庫正楷體。
  - 手寫：霞鶩漫黑、何某手寫體、內海字體。
  - **書法：找不到合格的開源字型**（§3.6 列出搜尋過的來源）。
  - 可愛：俐方體 11 號、WD-XL 滑油字、大波浪圓體。
- **排除 12 項**（§4），理由包括涵蓋率不足、需另行申請授權、GPL，以及與現有字型或其他候選幾乎一樣。
- **烘焙實測（卡上第 6 項）只做了 macOS CoreText 的替代檢查**：推薦的 14 套整串文字都由該字型畫出、沒有退回蘋方。iOS 觀景窗與烘焙的一致性**待實作卡驗證**，因為這次不開模擬器（模擬器主機名額已滿）。詳見 §3.8。
- **超過 30 MB 的檔案**：內海字體 SemiBold／Bold、苦累蛙圓體 Bold、全字庫正楷體、全字庫正宋體（§2 以 ⚠ 標出）。

比較稿（每套用最粗的字重，依類型分組）：

- 推薦 14 套：[`fonts-tc-2/comparison-recommended.png`](fonts-tc-2/comparison-recommended.png)
- 全部候選 38 列（含不推薦與授權未確認的）：[`fonts-tc-2/comparison-all.png`](fonts-tc-2/comparison-all.png)

![推薦候選比較稿](fonts-tc-2/comparison-recommended.png)

## 1. 方法

### 1.1 來源與下載

- 字型檔一律從官方來源下載：GitHub release 或 repo 固定 commit、政府資料開放平臺、教育部語文成果網、Google Fonts repo。完整清單與網址在 [`fonts-tc-2/scripts/manifest.tsv`](fonts-tc-2/scripts/manifest.tsv)。
- 下載檔放在 scratchpad，不進 repo，也不加入 App target。
- 授權逐套讀原始授權檔（repo 的 `OFL.txt`／`LICENSE`）與字型內 `name` 表的第 0、13、14 筆紀錄。兩者不一致或缺檔時另外註明。

### 1.2 每套檢查的項目

1. **授權**：條文連結、可否隨 App 散布原檔、保留字型名稱（RFN）、OS/2 `fsType`。
2. **字形**：4808 常用字涵蓋率（字表 [ButTaiwan/cjktables `taiwan/standard/edu_standard_1.txt`](https://github.com/ButTaiwan/cjktables/blob/master/taiwan/standard/edu_standard_1.txt)），以及疊字用字 `0-9 . 第天歲個月年又週尚未開始`、半形空白、全形空白 U+3000，另加比較稿句子的「我的紀錄」。字形風格以比較稿右欄的檢查字「戶骨說溫黃真直角次吳」目視判斷。
3. **字重**：上游提供哪些字重，依 TASK-89 選最多 3 個，並記錄最粗到哪裡。
4. **檔案**：每個選定字重的大小與 SHA-256（§6 附錄），以及來源與版本。
5. **類型**：依 TASK-120 的七類歸類。
6. **烘焙**：見 §3.8。

### 1.3 判讀原則

- **散布判定**：OFL 1.1 允許隨軟體散布原檔，條件是附上版權聲明與授權全文，且不單獨販售字型。DaysCam 以原檔散布、不子集化（PRD-0.3 A-1），所以 **RFN 不影響我們**，只在表中註記。
- **`fsType`** 是「字型能否嵌入文件」的旗標。DaysCam 把文字畫成像素，不把字型嵌入照片，所以 `fsType` 不是排除條件。非 0 的值仍列出：4 表示可預覽列印，8 表示可編輯嵌入，12 是同時設了 4 與 8 的不規範寫法。
- **字形**分三種：
  - 台灣標準：接近教育部標準字體。
  - 印刷／傳承字形：例如「眞」，不是台灣教育部字形，但也不是簡體。
  - 大陸規範傾向：繁體字可顯示，但部件寫法偏大陸規範。

  卡上的排除條件是「簡體字形」，所以後兩種不排除，只標註。
- **全形空白 U+3000**：目前 `TemplateRenderer` 的分隔符是半形空白（`partSeparator = " "`），疊字輸出不會用到 U+3000。缺 U+3000 的字型照實標出，但目前不影響烘焙。

## 2. 候選總表

「選定字重」是建議放進 App 的字重，最多 3 個。「大小」是選定字重各自的原檔大小，順序與選定字重相同。完整位元組數、SHA-256 與 `fsType` 見 §6。

### 2.1 黑

| # | 字型 | 授權 | 散布 | 字形 | 4808 | 上游字重 → 選定 | 最粗 | 大小（MB） | 來源／版本 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 思源黑體 Noto Sans TC | [OFL 1.1](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE) | 可 | 台灣標準 | 4808 | Thin–Black 共 7 → Regular／Bold／Black | Black | 5.4／5.6／5.8 | [noto-cjk](https://github.com/notofonts/noto-cjk) `f8d1575` SubsetOTF/TC，2.004 |
| 2 | 台北黑體 Taipei Sans TC Beta | OFL 1.1（[官方下載頁](https://sites.google.com/view/jtfoundry/en/downloads)聲明；字型 `name` 表亦為 OFL） | 可（見註 1） | 印刷體慣用筆形 | 4808 | Light／Regular／Bold → 全選 | Bold | 19.3／19.7／20.7 | 翰字鑄造 Google 雲端硬碟，1.000 Beta |
| 3 | 源石黑體 GenSekiGothic2 TW | [OFL 1.1](https://github.com/ButTaiwan/genseki-font/blob/master/SIL_Open_Font_License_1.1.txt)（RFN「Source」） | 可 | 台灣標準（TW 月版） | 4808 | L／R／M／B／H → R／B／H | H | 15.7／14.3／14.0 | [release v2.100](https://github.com/ButTaiwan/genseki-font/releases/tag/v2.100) |
| 4 | 昭源黑體 Chiron Hei HK | [OFL 1.1](https://github.com/chiron-fonts/chiron-hei-hk/blob/release/LICENSE.md) | 可 | 香港字形為基礎，印刷慣用筆形 | 4808 | EL–H 共 8（另有斜體、Text） → R／B／H | Heavy | 15.4／16.3／16.0 | [repo](https://github.com/chiron-fonts/chiron-hei-hk) `release` 分支 `106b59c`，2.609 |
| 5 | 朱古力黑體 Chocolate Classical Sans | [OFL 1.1](https://github.com/MoonlitOwen/ChocolateSans/blob/main/license.md) | 可 | 傳承字形（眞） | 4808 | 只有 Regular | Regular | 11.6 | Google Fonts `bd8f81d`，1.005 |
| 6 | 未來熒黑 Glow Sans TC | 字型 `name` 表為 OFL 1.1；[repo LICENSE](https://github.com/welai/glow-sans/blob/master/LICENSE) 是 MIT（見註 2） | 可 | 繁中版（字形標準未查證） | **4798**（缺「值告填巔慎教清真鎮顛」） | Thin–Heavy 共 9（Normal 寬度） → Regular／Bold／Heavy | Heavy | 8.5／8.6／8.7 | [release v0.93](https://github.com/welai/glow-sans/releases/tag/v0.93) |

- **註 1**：台北黑體只在 Google 雲端硬碟提供，沒有版本化的 release，檔名仍是 Beta。實作時要自己保存一份原檔並寫死 SHA-256。
- **註 2**：Glow Sans 的 repo 授權檔是 MIT，字型內嵌的授權是 OFL，兩者不一致。另外缺「教、真、清」等非常常用的字，比較稿的檢查字「真」實測退回蘋方，所以**不推薦**。

### 2.2 圓

| # | 字型 | 授權 | 散布 | 字形 | 4808 | 上游字重 → 選定 | 最粗 | 大小（MB） | 來源／版本 |
|---|---|---|---|---|---|---|---|---|---|
| 7 | 源泉圓體 GenSenRounded2 TW | [OFL 1.1](https://github.com/ButTaiwan/gensen-font/blob/master/SIL_Open_Font_License_1.1.txt)（RFN「Source」） | 可 | 台灣標準 | 4808 | EL／L／R／M／B／H → R／B／H | H | 15.4／15.1／15.0 | [release v2.100](https://github.com/ButTaiwan/gensen-font/releases/tag/v2.100) |
| 8 | 獅尾圓體 Swei Gothic CJK TC | [OFL 1.1](https://github.com/max32002/swei-gothic/blob/master/SIL_Open_Font_License_1.1.txt) | 可（見註 3） | 港台字形 | 4808 | Thin–Black 共 7 → Regular／Bold／Black | Black | 15.4／15.0／14.3 | [repo](https://github.com/max32002/swei-gothic) `c363a1d`；三個檔案內部版本分別是 2.143／2.140／2.125 |
| 9 | 昭源環方 Chiron GoRound TC | [OFL 1.1](https://github.com/chiron-fonts/chiron-go-round-tc/blob/release/LICENSE.md) | 可 | 印刷慣用筆形 | 4808 | EL–H 共 10 → 400R／700B／900H | Heavy | 18.7／19.6／18.1 | [repo](https://github.com/chiron-fonts/chiron-go-round-tc) `release` 分支 `9d73676`，1.011 |

- **註 3**：獅尾系列 repo 的授權檔是沒有填版權人的 OFL 範本，字型 `name` 表的 RFN 寫成「Untitled6」這類佔位字。授權意思明確是 OFL，但中繼資料粗糙。與源泉圓體同樣源自思源黑體、外觀接近，所以只推薦源泉圓體。

### 2.3 宋

| # | 字型 | 授權 | 散布 | 字形 | 4808 | 上游字重 → 選定 | 最粗 | 大小（MB） | 來源／版本 |
|---|---|---|---|---|---|---|---|---|---|
| 10 | 源雲明體 GenWanMin2 TW | [OFL 1.1](https://github.com/ButTaiwan/genwan-font/blob/master/SIL_Open_Font_License_1.1.txt) | 可 | 台灣標準 | 4808 | EL／L／R／M／SB → R／M／SB | **SemiBold** | 21.7／21.7／21.6 | [release v2.100](https://github.com/ButTaiwan/genwan-font/releases/tag/v2.100) |
| 11 | 源流明體 GenRyuMin2 TW | [OFL 1.1](https://github.com/ButTaiwan/genryu-font/blob/master/SIL_Open_Font_License_1.1.txt) | 可 | 台灣標準 | 4808 | EL–H 共 7 → R／B／H | H | 15.7／15.5／15.3 | [release v2.100](https://github.com/ButTaiwan/genryu-font/releases/tag/v2.100) |
| 12 | 獅尾四季春 Swei Spring CJK TC | [OFL 1.1](https://github.com/max32002/swei-spring/blob/main/SIL_Open_Font_License_1.1.txt) | 可（見註 3、註 4） | 港台字形 | 4808 | EL–Black 共 7 → Regular／Bold／Black | Black | 16.6／16.5／16.9 | [repo](https://github.com/max32002/swei-spring) `365dde9`，1.068 |
| 13 | 獅尾加糖宋體 Swei Sugar CJK TC | [OFL 1.1](https://github.com/max32002/swei-sugar/blob/master/SIL_Open_Font_License_1.1.txt) | 可（見註 3、註 4） | 港台字形 | 4808 | EL–Black 共 7 → Regular／Bold／Black | Black | 27.6／27.6／27.7 | [repo](https://github.com/max32002/swei-sugar) `0d0a9e1`，內部版本 1.0 |
| 14 | 昭源宋體 Chiron Sung HK | [OFL 1.1](https://github.com/chiron-fonts/chiron-sung-hk/blob/release/LICENSE.md) | 可 | 香港字形為基礎，印刷慣用筆形 | 4808 | EL–H 共 8（另有斜體、Text） → R／B／H | Heavy | 23.0／25.4／23.5 | [repo](https://github.com/chiron-fonts/chiron-sung-hk) `release` 分支 `afbff1d`，1.024 |
| 15 | 仙人掌明體 Cactus Classical Serif | [OFL 1.1](https://github.com/MoonlitOwen/CactusSerif/blob/main/license.md) | 可 | 傳承字形（眞） | 4808（缺 U+3000） | 只有 Regular | Regular | 27.2 | Google Fonts `bd8f81d`，1.005 |
| 16 | 全字庫正宋體 TW-Sung | 二擇一：[政府資料開放授權條款第 1 版](https://data.gov.tw/license)或 OFL 1.1（[資料集頁](https://data.gov.tw/dataset/5961)；字型 `name` 表亦如此聲明） | 可，須註明來源 | 台灣標準（CNS 11643） | 4808 | 只有一個字重（細） | Regular | ⚠ 33.7 | [全字庫 Fonts_Sung.zip](https://www.cns11643.gov.tw/opendata/Fonts_Sung.zip)（20260805），內部版本 11503.01 |
| 17 | 宇文天穹 UoqMunThenKhung | [OFL 1.1](https://github.com/MoonlitOwen/ThenKhung/blob/main/license.md) | 可 | 傳承字形（眞） | 4808 | 只有 Regular（外觀偏粗） | Regular | 4.7 | Google Fonts `bd8f81d`，1.197 |

- **註 4**：獅尾四季春、獅尾加糖宋體的字型 `name` 表沒有版權與授權欄位，只靠 repo 的授權檔。上一輪（#73 §B 註 2）已提過加糖宋體的這個問題，這次確認四季春也一樣。

### 2.4 楷

| # | 字型 | 授權 | 散布 | 字形 | 4808 | 上游字重 → 選定 | 最粗 | 大小（MB） | 來源／版本 |
|---|---|---|---|---|---|---|---|---|---|
| 18 | 霞鶩文楷 TC LXGW WenKai TC | [OFL 1.1](https://github.com/lxgw/LxgwWenkaiTC/blob/main/OFL.txt) | 可 | 部分字採傳承字形（眞） | 4808 | Light／Regular／Medium → Regular／Medium | **Medium**（見註 5） | 14.6／14.3 | [release v1.522](https://github.com/lxgw/LxgwWenkaiTC/releases/tag/v1.522) |
| 19 | 全字庫正楷體 TW-Kai | 二擇一：政府資料開放授權條款第 1 版或 OFL 1.1（同 #16） | 可，須註明來源 | 台灣標準（CNS 11643） | 4808 | 只有一個字重 | Regular | ⚠ 35.2 | [全字庫 Fonts_Kai.zip](https://www.cns11643.gov.tw/opendata/Fonts_Kai.zip)（20260805），內部版本 11508.01，`fsType` 4 |
| 20 | 教育部標準楷書 | [CC BY-ND 3.0 TW](http://creativecommons.org/licenses/by-nd/3.0/tw/)（[教育部說明](https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/edukai.pdf)） | 可原檔散布，須標示「中華民國教育部」，不得改作 | 台灣標準 | 4808 | 只有一個字重 | Regular | 15.1 | [edukai-5.0.zip](https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/edukai-5.0.zip)，字型內部版本 5.00（2023-12），說明文件寫 5.1 |
| 21 | 文鼎 PL 中楷 AR PL UKai TW | Arphic Public License（[Debian 授權檔](https://metadata.ftp-master.debian.org/changelogs/main/f/fonts-arphic-ukai/stable_copyright)） | 可原檔散布，須附授權；改作須同授權 | 舊印刷楷書（眞、户） | 4808 | 只有一個字重 | Regular | 16.4（`ukai.ttc` 內含 4 個字面） | Debian `fonts-arphic-ukai` 0.2.20080216.2-6（上游 2008 年後未更新） |

- **註 5**：霞鶩文楷 TC 上游最新版 v1.522 只到 Medium。Google Fonts 收錄的 `LXGWWenKaiTC-Bold.ttf` 是舊版 1.330（2024-04），上游已不再提供 Bold，所以建議用上游 Medium。

### 2.5 手寫

| # | 字型 | 授權 | 散布 | 字形 | 4808 | 上游字重 → 選定 | 最粗 | 大小（MB） | 來源／版本 |
|---|---|---|---|---|---|---|---|---|---|
| 22 | 清松手寫體 JasonHandwriting 1–9 | [README](https://github.com/jasonhandwriting/JasonHandwriting#readme) 聲明 OFL，**repo 沒有授權檔**（見 §5） | 未確認 | 台灣手寫 | 1、3、5p–9p：4808；2：4802；4：4804（全部缺 U+3000） | 每號只有一個字重，1–9 號是不同風格 | Regular | 3.9–10.6（每號一檔） | [repo](https://github.com/jasonhandwriting/JasonHandwriting) `e488583` |
| 23 | 內海字體 NaikaiFont TW | [OFL 1.1](https://github.com/max32002/naikaifont/blob/master/SIL_Open_Font_License_1.1.txt)（衍生自瀨戶字體，OFL） | 可 | 台灣補字；作者自述「戶」部件多沿用日文寫法 | 4808 | EL／L／R／SB／B → R／SB／B | Bold | 25.0／⚠ 36.0／⚠ 36.8 | [repo](https://github.com/max32002/naikaifont) `7baa43a`，1.89，`fsType` 8 |
| 24 | 小賴字體 Xiaolai | [OFL 1.1](https://github.com/lxgw/kose-font/blob/master/OFL.txt) | 可 | 大陸規範傾向（README 說明以大陸規範字形為主） | 4808 | 只有 Regular | Regular | 21.2 | [release v3.126](https://github.com/lxgw/kose-font/releases/tag/v3.126) |
| 25 | 悠哉字體 Yozai | [OFL 1.1](https://github.com/lxgw/yozai-font/blob/master/OFL.txt)（RFN「Y.Oz」「YOz」） | 可 | 大陸規範傾向（README 說明） | 4808 | Light／Regular／Medium → Regular／Medium | Medium | 14.9／14.5 | [release v0.868](https://github.com/lxgw/yozai-font/releases/tag/v0.868) |
| 26 | 何某手寫體 NaniFont | [OFL 1.1](https://github.com/max32002/nanifont/blob/master/SIL_Open_Font_License_1.1.txt)（衍生自おつとめフォント，OFL；RFN「Otsutome_font」） | 可 | 台灣補字 | 4808 | EL／L／R／SB／B → Regular／Bold | Bold | 17.0／17.7 | [repo](https://github.com/max32002/nanifont) `90df131`，1.046 |
| 27 | 霞鶩漫黑 LXGW Marker Gothic | [OFL 1.1](https://github.com/lxgw/LxgwMarkerGothic/blob/main/OFL.txt) | 可 | 4808 台灣字＋香港常用字（README） | 4808 | 只有 Regular | Regular | 3.0 | [release v1.003](https://github.com/lxgw/LxgwMarkerGothic/releases/tag/v1.003) |
| 28 | 苦累蛙圓體 Kurewa Gothic CJK TC | [OFL 1.1](https://github.com/max32002/kurewa-gothic/blob/master/SIL_Open_Font_License_1.1.txt)（衍生自 Zen Kurenaido，OFL） | 可 | 日文部件與台灣補字混搭（作者自述） | 4808 | EL／L／R／SB／B → Regular／Bold | Bold | 29.7／⚠ 34.8 | [repo](https://github.com/max32002/kurewa-gothic) `10730fd`，1.100 |

### 2.6 書法

| # | 字型 | 授權 | 散布 | 字形 | 4808 | 上游字重 → 選定 | 最粗 | 大小（MB） | 來源／版本 |
|---|---|---|---|---|---|---|---|---|---|
| 29 | 莫大毛筆 Bakudai | 衍生者聲明 OFL 1.1；**原作授權未允許改作**（見 §5） | **未確認** | 台灣補字 | 4808 | EL／L／R／M／B | Bold | 15.9（Bold） | [repo](https://github.com/max32002/bakudaifont) `f1eb195`，1.48 |
| 30 | 正風毛筆 MasaFont | 同上；repo **沒有授權檔** | **未確認** | 台灣補字 | 4808 | EL／L／R／M／B | Bold | 18.1（Bold） | [repo](https://github.com/max32002/masafont) `8fa528c`，2.1 |

### 2.7 可愛

| # | 字型 | 授權 | 散布 | 字形 | 4808 | 上游字重 → 選定 | 最粗 | 大小（MB） | 來源／版本 |
|---|---|---|---|---|---|---|---|---|---|
| 31 | 大波浪圓體 Pop Gothic CJK TC | [OFL 1.1](https://github.com/max32002/pop-gothic/blob/master/SIL_Open_Font_License_1.1.txt)（衍生自はちまるポップ，OFL） | 可 | 日文部件與台灣補字混搭（作者自述） | 4808 | EL／L／R／SB／B → Regular／Bold | Bold | 8.0／9.8 | [repo](https://github.com/max32002/pop-gothic) `45bf2dd`，2.145 |
| 32 | WD-XL 滑油字 TC | [OFL 1.1](https://github.com/NightFurySL2001/WD-XL-font/blob/master/OFL.txt)（衍生自站酷慶科黃油體，OFL） | 可 | 繁體版（傳承字形，眞） | 4808 | 只有 Regular（外觀很粗） | Regular | 5.9 | [release v2.100](https://github.com/NightFurySL2001/WD-XL-font/releases/tag/v2.100) |
| 33 | 俐方體 11 號 Cubic 11 | [OFL 1.1](https://github.com/ACh-K/Cubic-11/blob/main/OFL.txt)（衍生自 M+ BITMAP FONTS） | 可 | 台灣習慣字形（README） | 4808 | 只有一個字重（像素字） | Regular | 2.6 | [repo](https://github.com/ACh-K/Cubic-11) `4c566f7`，字型內部版本 1.451（最新 tag v1.500 沒有附檔） |

## 3. 每類推薦

推薦的原則依序是：授權清楚、台灣字形或至少不是簡體、和現有 22 套與其他推薦有明顯差異、有夠粗的字重、檔案較小。

### 3.1 黑：思源黑體、台北黑體

- **思源黑體 Noto Sans TC**（Regular／Bold／Black）：最穩的台灣字形黑體，三個字重都不到 6 MB。和現有的思源宋體同一家族，命名與授權頁好處理。
- **台北黑體**（Light／Regular／Bold）：印刷體筆形，和思源黑體的觀感明顯不同。缺點是每個字重約 20 MB，而且只在雲端硬碟發布（§2.1 註 1）。
- 備選：昭源黑體（印刷筆形、最粗到 Heavy）、源石黑體（鉛字感）。這兩套與上面兩套各有部分重疊，挑一套即可。

### 3.2 圓：源泉圓體、昭源環方

- **源泉圓體**（R／B／H）：上一輪已實測過，台灣字形，最粗到 Heavy。
- **昭源環方**（Regular／Bold／Heavy）：方中帶圓，和源泉圓體、現有粉圓都不同。
- 現有的粉圓已是圓體，若只想加一套，建議源泉圓體。

### 3.3 宋：源流明體、昭源宋體

- **源流明體**（R／B／H）：台灣字形，鉛字感，最粗到 Heavy，和現有思源宋體的造形有明顯差異。
- **昭源宋體**（Regular／Bold／Heavy）：印刷筆形，粗字重很有份量；檔案較大（23–25 MB）。
- 備選：獅尾四季春（16–17 MB，`name` 表沒有授權欄位）、宇文天穹（只有 4.7 MB、外觀偏粗，但是傳承字形）。
- 不推薦源雲明體，因為最粗只到 SemiBold，疊在照片上太細。

### 3.4 楷：霞鶩文楷 TC、全字庫正楷體

- **霞鶩文楷 TC**（Regular／Medium）：手寫感楷書，和系統的楷體、標楷體都不同。最粗只到 Medium，比其他推薦細。
- **全字庫正楷體**（單一字重）：台灣標準楷書，授權可選 OFL，最清楚。檔案 35.2 MB 超過 30 MB；而且數字與英文是寬字距（比較稿可見「2026. 10. 11」），和系統標楷體的風格接近。
- 若在意大小，可用**教育部標準楷書**（15.1 MB）代替全字庫正楷體。兩者字形幾乎一樣，但教育部版是 CC BY-ND，不是字型專用授權，所以列為第二順位。

### 3.5 手寫：霞鶩漫黑、何某手寫體、內海字體

- **霞鶩漫黑**（單一字重）：麥克筆手寫感，只有 3.0 MB，是所有候選裡最小的。
- **何某手寫體**（Regular／Bold）：日系可愛手寫風、粗字重明顯。
- **內海字體**（Regular／SemiBold／Bold）：瀨戶字體的台灣補字版，筆觸自然。SemiBold、Bold 超過 30 MB；若在意大小只放 Regular（25.0 MB）。
- 小賴字體與內海字體同樣源自瀨戶字體，而且偏大陸規範字形，所以兩者擇一時選內海。
- 清松手寫體風格很受歡迎，但 repo 沒有授權檔，列在未確認事項（§5），暫不推薦。

### 3.6 書法：找不到合格的開源字型

搜尋過的來源與結果：

| 來源 | 找到的書法類 | 結果 |
|---|---|---|
| GitHub（Max 的補字計畫） | 莫大毛筆、正風毛筆（衍生自衡山毛筆フォント） | 原作授權沒有允許改作與改授權，**未確認**（§5） |
| GitHub `maoken-fonts/slidefont` | 演示夏行楷（行楷）等演示系列 5 套 | OFL，但 4808 只涵蓋 3059 字（63.6%），缺「歲個週開紀錄」，**排除** |
| 教育部語文成果網 | 國字隸書字形檔 | 商用需檢附文件、填切結書向教育部申請，**排除** |
| 王漢宗自由字型、cwTeX Q 字型 | 魏碑、隸書、行書等 | GPL v2、沒有字型例外，隨 App Store 散布有衝突疑慮；王漢宗字型另有來源爭議，**排除**（未下載實測） |
| Google Fonts 繁中分類 | 無書法類 | 書法字型 Zhi Mang Xing、Ma Shan Zheng、Liu Jian Mao Cao、Long Cang 只有簡體子集 |
| justfont 開源字型 | 只有粉圓 | 無書法類 |

書法類目前由系統字型（行楷、魏碑、隸變、報隸）提供。

### 3.7 可愛：俐方體 11 號、WD-XL 滑油字、大波浪圓體

- **俐方體 11 號**：像素字，2.6 MB，台灣字形。
- **WD-XL 滑油字**：粗黑、俏皮，5.9 MB。只有一個字重，外觀已經很粗。
- **大波浪圓體**（Regular／Bold）：圓滾手寫感，8.0–9.8 MB。

### 3.8 烘焙實測（卡上第 6 項，121.4）

**這次只做了 macOS CoreText 的替代檢查，iOS 實測待實作卡驗證。**

- **做了什麼**：[`render.swift`](fonts-tc-2/scripts/render.swift) 以 `CTFontManagerRegisterFontsForURL(.process)` 註冊原檔，用 PostScript 名稱建立字型，畫出比較稿；同時用 `CTLineGetGlyphRuns` 讀出每一段實際使用的字型。測試字串有三行：
  - 比較句「2026.10.11 我的紀錄 第 128 天」。
  - 疊字用字「1 歲又 3 個月 2 週　尚未開始」，含全形空白。
  - 檢查字「戶骨說溫黃真直角次吳」。
- **結果**：推薦的 14 套，三行全部由該字型畫出，沒有任何一段退回蘋方。逐列結果見 [`fonts-tc-2/coretext-runs.tsv`](fonts-tc-2/coretext-runs.tsv)。
- **有退回的候選**：
  - 清松手寫體 1、3、5p、7p、9p 與仙人掌明體：只有全形空白那一段退回 `PingFangTC-Regular`，因為缺 U+3000。目前疊字不用全形空白（§1.3），不影響現況。
  - 未來熒黑 TC：檢查字「真」退回 `PingFangTC-Semibold`，因為缺字。
- **還沒驗證的**：
  - iOS 上 `OverlayRenderer` 實際烘焙的結果。
  - 觀景窗 SwiftUI `Text` 與烘焙用的 `NSString.draw` 是否逐像素一致。#73 §C 對 8 套做過這項，這次的 14 套還沒做。
  - 這兩項請實作卡用 #73 §C 的方法補驗，未通過的字型不上架。

## 4. 排除清單

| 字型 | 理由 |
|---|---|
| 源樣黑體 GenYo Gothic | README 說明「維持思源原有造形」，與思源黑體幾乎一樣（[repo](https://github.com/ButTaiwan/genyog-font)） |
| 源樣明體 GenYo Serif | 同上，與現有思源宋體幾乎一樣（[repo](https://github.com/ButTaiwan/genyo-font)） |
| 源柔哥德 GenJyuu Gothic | 自家製フォント工房以思源黑體**日文版**圓角化、再以 M+ FONTS 補字的日文字型（[介紹](https://forest.watch.impress.co.jp/library/software/genjyuu_gt/)），漢字是日文字形；同為思源黑體圓角化的台灣版已有源泉圓體 |
| 演示系列 5 套（佛系體、悠然小楷、春風楷、夏行楷、秋鴻楷） | 4808 只涵蓋 3059 字（63.6%），疊字缺「歲個週開」，低於 99% 門檻 |
| 教育部國字隸書 | 只有 4808 字，且商用需書面申請、填切結書，不是公開授權 |
| 王漢宗自由字型 | GPL v2、沒有字型例外，App Store 散布有衝突疑慮；來源另有爭議（未下載實測） |
| cwTeX Q 字型 | GPL v2（[TTF repo](https://github.com/l10n-tw/cwtex-q-fonts-TTFs)），理由同上（未下載實測） |
| 縫合像素 Fusion Pixel 12px zh-TW | 繁中字形取自俐方體 11 號（發布檔附 `LICENSES/cubic-11`），與俐方體幾乎一樣，擇一保留俐方體 |
| 馬路口圓體 Maruko Gothic | 作者自述字形由電腦推論、粗糙，48px 以上會看出破綻，不適合烘焙到高解析度照片 |
| FakePearl、TaiwanPearl、YuPearl | 衍生自粉圓，與現有粉圓同一家族 |
| 霞鶩文楷 TC 的 Google Fonts Bold | 舊版 1.330，上游最新版已不提供 Bold（§2.4 註 5） |
| 上一輪已採用的粉圓、思源宋體、芫荽、辰宇落雁體 | 已在字型庫 |

## 5. 未確認事項

以下項目**不可當成可用**，要先由人類確認：

1. **莫大毛筆、正風毛筆的授權**：衍生者把它們以 OFL 發布，但原作「衡山毛筆フォント」的[官方頁](https://opentype.jp/kouzanmouhitufont.htm)與[行書頁](https://opentype.jp/kouzangyousho.htm)只寫「無料、商用利用可能で制限はありません、ロゴ等へも自由、雑誌・書籍への掲載・CD収録も自由」，**沒有提到改作與再授權**。正風毛筆的 repo 也沒有授權檔。要採用，需向原作者（青二書道教室）或 Musashi System 確認。
2. **清松手寫體的授權檔**：README 寫「created by Jason (Yu Ching Sung) under SIL Open Font License」，但 repo 沒有 `OFL.txt`，大多數字型 `name` 表也只有版權、沒有授權欄位（4 號例外，內嵌 OFL）。意思大致明確，但打包時要附的版權聲明與授權全文要自己補，建議先向作者確認。
3. **台北黑體的版本**：只有雲端硬碟上的 Beta 檔，沒有版本號以外的發布紀錄；日後檔案被替換時無法追溯。
4. **未來熒黑的授權不一致**：repo 是 MIT，字型內嵌 OFL（已不推薦）。
5. **文鼎 PL 中楷的 Arphic Public License** 與 App Store 散布條款是否相容：條文允許原樣散布並要求附授權，但它是 copyleft 授權，我沒有找到 App 內使用的明確先例（已不推薦）。
6. **教育部標準楷書的版本**：字型內部寫 5.00（2023-12），教育部說明 PDF 寫 Version 5.1。
7. **iOS 烘焙一致性**：§3.8，待實作卡驗證。
8. **`fsType` 非 0 的字型**（內海、全字庫正楷、清松、演示、莫大、正風、縫合像素）：我的判讀是烘焙成像素不算嵌入，不受限制。這是判讀，未經法律確認。

## 6. 附錄：檔案大小與 SHA-256

測的是 §2 各候選的選定字重，以及書法、演示系列的代表檔。「疊字缺字」包含比較句的「我的紀錄」。

| 檔案 | PostScript 名稱 | 版本 | 字重值 | 位元組 | MB | SHA-256 | fsType | 4808 | 疊字缺字 |
|---|---|---|---|---|---|---|---|---|---|
| `NotoSansTC-Black.otf` | `NotoSansTC-Black` | 2.004 | 900 | 6068384 | 5.8 | `3280b221ab7b011c6ae48d38388a0e8c72ddf479992bce62ff589ae932819ce4` | 0 | 4808 | — |
| `NotoSansTC-Bold.otf` | `NotoSansTC-Bold` | 2.004 | 700 | 5839972 | 5.6 | `55420b259eb119bf5f2a0aadba10cf9d736c12d64ab93e78546d69ef5f43558b` | 0 | 4808 | — |
| `NotoSansTC-Regular.otf` | `NotoSansTC-Regular` | 2.004 | 400 | 5683368 | 5.4 | `5bab0cb3c1cf89dde07c4a95a4054b195afbcfe784d69d75c340780712237537` | 0 | 4808 | — |
| `GenSekiGothic2TW-R.otf` | `GenSekiGothic2TW-R` | 2.100 | 400 | 16501448 | 15.7 | `bb3cccb9594a5a9c759a92bbbf147eb87826b8317d07d20f48ee7ebdcec684fa` | 0 | 4808 | — |
| `GenSekiGothic2TW-B.otf` | `GenSekiGothic2TW-B` | 2.100 | 700 | 15017684 | 14.3 | `911bc231c346f1e377796ccd1b85959184a547d1fce356da882a2f1abb9bfaa4` | 0 | 4808 | — |
| `GenSekiGothic2TW-H.otf` | `GenSekiGothic2TW-H` | 2.100 | 900 | 14691360 | 14.0 | `87880818a93362d11b4c07f9612993deeeb1a0800b1779a31bea197e4c8109f2` | 0 | 4808 | — |
| `ChironHeiHK-B.otf` | `ChironHeiHK-Bold` | 2.609 | 700 | 17083396 | 16.3 | `51a6c39f8dd0a4522a7c5d366d77e9e52aebe4280d9b16ed95f03288c802e821` | 0 | 4808 | — |
| `ChironHeiHK-H.otf` | `ChironHeiHK-Heavy` | 2.609 | 900 | 16828836 | 16.0 | `1dc39f1d97c9bdba16fef81f08be56c96eeb702aca03f4f5b8498c6bc4e385d4` | 0 | 4808 | — |
| `ChironHeiHK-R.otf` | `ChironHeiHK-Regular` | 2.609 | 400 | 16164592 | 15.4 | `72f68279a78a118b469bc683a1ab12364a5a3c244ee592da441d4a3cb0eda4b1` | 0 | 4808 | — |
| `ChocolateClassicalSans-Regular.ttf` | `ChocolateClassicalSans-Regular` | 1.005 | 400 | 12183000 | 11.6 | `e6345f3d92c7a9b7044c31a87d9b61f50220b08c0f1dcc2736e94c2aa587ce03` | 0 | 4808 | — |
| `GlowSansTC-Normal-Regular.otf` | `GlowSansTC-Normal-Regular` | 0.93 | 400 | 8926856 | 8.5 | `cbd6843ab96acc9bb92048dd426232ece37f79068cc9e48c40e8d48e9fd0ee59` | 0 | 4798 | — |
| `GlowSansTC-Normal-Bold.otf` | `GlowSansTC-Normal-Bold` | 0.93 | 700 | 8995980 | 8.6 | `8005c40f3777c540ec10ed352793f2a53363a13ec41bc0eeaf18d28e9c8c4312` | 0 | 4798 | — |
| `GlowSansTC-Normal-Heavy.otf` | `GlowSansTC-Normal-Heavy` | 0.93 | 900 | 9094228 | 8.7 | `88ee1042b780005beaa4bbc2bf86cf89a8d0362cfae57b5a9dee7c3887bafbb0` | 0 | 4798 | — |
| `SweiGothicCJKtc-Black.ttf` | `SweiGothicCJKtc-Black` | 2.125 | 900 | 14977188 | 14.3 | `7376c750c79bf05b14ad8476d2421696fd9b80bdb5b3ad0e7b27c608e9eef9af` | 0 | 4808 | — |
| `SweiGothicCJKtc-Bold.ttf` | `SweiGothicCJKtc-Bold` | 2.140 | 700 | 15757732 | 15.0 | `d3f03ebd366966c1967879d1b5760e96784e9f7b9bac6e4b5dd364db00a9c128` | 0 | 4808 | — |
| `SweiGothicCJKtc-Regular.ttf` | `SweiGothicCJKtc-Regular` | 2.143 | 400 | 16193916 | 15.4 | `0cb199c63ec23fda70905decf82e1a7f3657092a653323063e9e5f50adfc3f7f` | 0 | 4808 | — |
| `GenSenRounded2TW-R.otf` | `GenSenRounded2TW-R` | 2.100 | 400 | 16177104 | 15.4 | `092285878f1d9441c790e5d6a98e806bd508602ad0a8a55511b6fb0a71a25fed` | 0 | 4808 | — |
| `GenSenRounded2TW-B.otf` | `GenSenRounded2TW-B` | 2.100 | 700 | 15807568 | 15.1 | `050f9ebf394faab3c0ba59092ae3e4b6686b349eadb3018d76d385c5829a1267` | 0 | 4808 | — |
| `GenSenRounded2TW-H.otf` | `GenSenRounded2TW-H` | 2.100 | 900 | 15684388 | 15.0 | `1088f309fbc3d10d40b2b0e6ef3b965a881066c021f341fd8afd4eb751564ad6` | 0 | 4808 | — |
| `ChironGoRoundTC-400R.otf` | `ChironGoRoundTC-Regular` | 1.011 | 400 | 19635772 | 18.7 | `519253233cbca3c2b97b818949e803ccf08f937d75431bedf59e167b00bf4b65` | 0 | 4808 | — |
| `ChironGoRoundTC-700B.otf` | `ChironGoRoundTC-Bold` | 1.011 | 700 | 20500040 | 19.6 | `5ed043b3d1048e4d7868909c6d6fbba2d0cb50773d394003f4fb077a18e2b3fb` | 0 | 4808 | — |
| `ChironGoRoundTC-900H.otf` | `ChironGoRoundTC-Heavy` | 1.011 | 900 | 19010084 | 18.1 | `6989bb7c609805757146ca79765c4b37da2f17de0c808408d6031db49337e64e` | 0 | 4808 | — |
| `KurewaGothicCjkTc-Bold.ttf` | `KurewaGothicCjkTc-Bold` | 1.100 | 700 | 36472060 | 34.8 | `f3c77d55c30ebf113c1e9375ac500df23082dc76221e3299d9ba581eb54bf515` | 0 | 4808 | — |
| `KurewaGothicCjkTc-Regular.ttf` | `KurewaGothicCjkTc-Regular` | 1.100 | 400 | 31158716 | 29.7 | `da6d76a895ac0a8ba80edeb5b99dec0b0e8e205040244e37ba0a39054fa5289e` | 0 | 4808 | — |
| `PopGothicCjkTc-Bold.ttf` | `PopGothicCjkTc-Bold` | 2.145 | 700 | 10298960 | 9.8 | `6f40a3fcfed7128bebca12b0b27c5cf4a0982e4312143df1390d1645fa4e12e7` | 0 | 4808 | — |
| `PopGothicCjkTc-Regular.ttf` | `PopGothicCjkTc-Regular` | 2.145 | 400 | 8371820 | 8.0 | `3094ba8fa82bebdfbe4fd168c7460f1023d7bf8a515696a3dedc960f74bbba4a` | 0 | 4808 | — |
| `GenWanMin2TW-R.otf` | `GenWanMin2TW-R` | 2.100 | 400 | 22772928 | 21.7 | `4c1cea221f35ccfd7c27e295238012d3b48e57d149b92b4eb7d71aeb25d798cf` | 0 | 4808 | — |
| `GenWanMin2TW-M.otf` | `GenWanMin2TW-M` | 2.100 | 500 | 22710256 | 21.7 | `828b83e22e825030204183422701ae42afe24c93b1b131717e7678bd86b57768` | 0 | 4808 | — |
| `GenWanMin2TW-SB.otf` | `GenWanMin2TW-SB` | 2.100 | 600 | 22614524 | 21.6 | `86cc4abaec4151b5ad9ac6d39f635c974a2dc4155fe041e6a4fa9730114487d1` | 0 | 4808 | — |
| `TaipeiSansTCBeta-Bold.ttf` | `TaipeiSansTCBeta-Bold` | 1.000 | 700 | 21737516 | 20.7 | `5249d3bdda9c9f4c62840e804b4d2530b7f4dfab6d68fb508c120b0e7e600419` | 0 | 4808 | — |
| `TaipeiSansTCBeta-Light.ttf` | `TaipeiSansTCBeta-Light` | 1.000 | 300 | 20279264 | 19.3 | `d69a9ea6a77f694c3a1a1fb766c764aa74cb3e2c4c69f1b532edf98b3f2bb662` | 0 | 4808 | — |
| `TaipeiSansTCBeta-Regular.ttf` | `TaipeiSansTCBeta-Regular` | 1.000 | 400 | 20659344 | 19.7 | `8cc967e1e428c552701c461e8169e6ae76c7a23694ea1a6a786d6746adec53c4` | 0 | 4808 | — |
| `ukai.ttc` | `UKaiTW` | 0.2.20080216.1 | 400 | 17151049 | 16.4 | `cfc758e69386a21bade8cb3b373fda20d7f2fac6e8904ced2ded98588b63e274` | 0 | 4808 | — |
| `edukai-5.0.ttf` | `TW-MOE-Std-Kai` | 5.00, December, 2023 | 400 | 15820500 | 15.1 | `99ae11cc1ba0ee14d43da5336f2c555b17a3bf551f7203f42da4f7fbdfcf7b7b` | 0 | 4808 | — |
| `GenRyuMin2TW-R.otf` | `GenRyuMin2TW-R` | 2.100 | 400 | 16449288 | 15.7 | `d244c6115431b2a18b5dfb0066e08381f56e6a33532915a0f517dd3f7063b646` | 0 | 4808 | — |
| `GenRyuMin2TW-B.otf` | `GenRyuMin2TW-B` | 2.100 | 700 | 16217516 | 15.5 | `5e7d2c11cf9860c94ac7d1fba742329f6015f7042c736232e1e69eb8ab12d5da` | 0 | 4808 | — |
| `GenRyuMin2TW-H.otf` | `GenRyuMin2TW-H` | 2.100 | 900 | 16022096 | 15.3 | `921295896e780b306d79580a8dcacf8ea6c0e1bd29e1853f3eed18264fa6d44a` | 0 | 4808 | — |
| `SweiSpringCJKtc-Black.ttf` | `SweiSpringCJKtc-Black` | 1.068 | 900 | 17730092 | 16.9 | `7f71afb558abf3b599094119616502a29cdf31a339f8cf2223cec999f8995e56` | 0 | 4808 | — |
| `SweiSpringCJKtc-Bold.ttf` | `SweiSpringCJKtc-Bold` | 1.068 | 700 | 17336124 | 16.5 | `2bf4d16b849c4a87242c3f38817f18d45cf2a04d244fc3420dd5771d78b078fb` | 0 | 4808 | — |
| `SweiSpringCJKtc-Regular.ttf` | `SweiSpringCJKtc-Regular` | 1.068 | 400 | 17357244 | 16.6 | `8278b3f032b7bac5494d28ab1ddbe6b98959142a3e04a2b527c50c654dad6b80` | 0 | 4808 | — |
| `SweiSugarCJKtc-Black.ttf` | `SweiSugarCJKtc-Black` | 1.0 | 900 | 29001120 | 27.7 | `f39f956fc4a7f9f6729c62047da0c9376c56653ff7d6912a3b7032c490b449e3` | 0 | 4808 | — |
| `SweiSugarCJKtc-Bold.ttf` | `SweiSugarCJKtc-Bold` | 1.0 | 700 | 28989908 | 27.6 | `c71c1d5196e49211c5232df39210df2c6fbea0b60245cb8ef9fc7edd37a1a30c` | 0 | 4808 | — |
| `SweiSugarCJKtc-Regular.ttf` | `SweiSugarCJKtc-Regular` | 1.0 | 200 | 28960864 | 27.6 | `2e930dbafa3f5878df4de9fb773c5a4c9da0b658dd9219d62fd1a928db61447a` | 0 | 4808 | — |
| `ChironSungHK-B.otf` | `ChironSungHK-Bold` | 1.024 | 700 | 26585108 | 25.4 | `bc3f911227c98ae45caf31147201c29dd3cf14fc2c84af72936f4ef6067b397d` | 0 | 4808 | — |
| `ChironSungHK-H.otf` | `ChironSungHK-Heavy` | 1.024 | 900 | 24661440 | 23.5 | `2465ebd8119e0086bd1be03556d60dd6a3a2988f1579a962532ddb8c6b877cfa` | 0 | 4808 | — |
| `ChironSungHK-R.otf` | `ChironSungHK-Regular` | 1.024 | 400 | 24164960 | 23.0 | `d53da9ffb3593a6dcce34f9e4a5d94369c7e619efa1b3d9a60717c7d72aa65d0` | 0 | 4808 | — |
| `CactusClassicalSerif-Regular.ttf` | `CactusClassicalSerif-Regular` | 1.005 | 400 | 28502932 | 27.2 | `ecbd58961db922392d7fecfafa3681fefaeec0c399b860ab6940ba700f7da055` | 0 | 4808 | U+3000 |
| `UoqMunThenKhung-Regular.ttf` | `UoqMunThenKhung-Regular` | 1.197 | 400 | 4901688 | 4.7 | `943a23eb10d40ca85ee08491c0e3fb3adbc4bd111ef1f93526a4f766a8e66fbd` | 0 | 4808 | — |
| `TW-Kai-98_1.ttf` | `TW-Kai-98_1` | 11508.01 | 400 | 36925608 | 35.2 | `d5e8d7d8743c5cf816bdeb393a443f65105a8130266a04c19560e1d3401b28f0` | 4 | 4808 | — |
| `TW-Sung-98_1.ttf` | `TW-Sung-98_1` | 11503.01 | 400 | 35320040 | 33.7 | `9a3b74fe1a69fe1b3470b5ed780bf678c42a25cef93a13f280a5f31f795f0c56` | 0 | 4808 | — |
| `LXGWWenKaiTC-Medium.ttf` | `LXGWWenKaiTC-Medium` | 1.522 | 500 | 15025056 | 14.3 | `94ca2870022fb8e4f90e2887524603690598142d17b620dfae318f1818ba8e17` | 0 | 4808 | — |
| `LXGWWenKaiTC-Regular.ttf` | `LXGWWenKaiTC-Regular` | 1.522 | 400 | 15267616 | 14.6 | `b1a0795862c1415bf3f393ea50b2a4ea6275012cf5bad3f94feeb1222f555731` | 0 | 4808 | — |
| `LXGWWenKaiTC-Bold.ttf` | `LXGWWenKaiTC-Bold` | 1.330 | 700 | 12881104 | 12.3 | `5c9feadfd928f3ae3860e7d001ad3d0d0c55b0157fff08cd4d51b51aca677f23` | 0 | 4808 | — |
| `JasonHandwriting1.ttf` | `JasonHandwriting1-Regular` | 1.48 | 400 | 8921060 | 8.5 | `de76a15b1e2c1a7050d061485e28195f5b682d45e37499cf730c2b8554c44cf3` | 12 | 4808 | U+3000 |
| `JasonHandwriting2.ttf` | `JasonHandwriting2` | 1.06 | 400 | 5378712 | 5.1 | `b67dce349d32e92e4ee7befeb0339d04ca69551bb523e60cfb5ea8f5fbd5d669` | 8 | 4802 | U+3000 |
| `JasonHandwriting3.ttf` | `JasonHandwriting3` | 1.25 | 400 | 6089404 | 5.8 | `7747c276f3b16306c7ab7d52465647c566d01f91faeefa70c271a3890ed35fb0` | 12 | 4808 | U+3000 |
| `JasonHandwriting4.ttf` | `JasonHandwriting4-Regular` | 1.01 | 400 | 4137276 | 3.9 | `1db91107a80c78e6d04b6d78f86a4b8946f083cb0b41ff5864009c4e1698ee4b` | 0 | 4804 | U+3000 |
| `JasonHandwriting5p.ttf` | `JasonHandwriting5p` | 1.12 | 400 | 7034532 | 6.7 | `20cbc01f25637dc098ad98aa8c8e460b00613409c103879465c4185a1cb6c7a9` | 12 | 4808 | U+3000 |
| `JasonHandwriting6p.ttf` | `JasonHandwriting6p-Regular` | 1.00 | 400 | 8868680 | 8.5 | `761cced23f78f56c8254ecfc7d0f8566d53eded61dcb0a7b7936bdde747dedee` | 8 | 4808 | U+3000 |
| `JasonHandwriting7p.ttf` | `JasonHandwriting7p-Regular` | 1.01 | 400 | 11097316 | 10.6 | `df478acf044569d3f6393057574e20d1962d16ee0a48276f018c16694259ccfd` | 4 | 4808 | U+3000 |
| `JasonHandwriting8p.ttf` | `JasonHandwriting8p` | 1.00 | 400 | 9500240 | 9.1 | `368e64b89d468f72986a576674f8a4344c464d4d3f4596c93fe6692c70c18743` | 0 | 4808 | U+3000 |
| `JasonHandwriting9p.ttf` | `JasonHandwriting9p` | 1.00 | 400 | 9815492 | 9.4 | `e0ea1e62955008e065e1e5fc7186dd8f0ba87303987038f34fbffe5600c06c55` | 0 | 4808 | U+3000 |
| `NaikaiFont-Bold.ttf` | `NaikaiFont-Bold` | 1.89 | 700 | 38622668 | 36.8 | `43a3822eedd0d7d5fe464fc462c799f5ff2de8eaeabc0825ba09607b1035b621` | 8 | 4808 | — |
| `NaikaiFont-Regular.ttf` | `NaikaiFont-Regular` | 1.89 | 400 | 26254192 | 25.0 | `d3320b822131540d5e3cc9737f7b458aeb1c0ca76fe89aeaa1b76001f54e503e` | 8 | 4808 | — |
| `NaikaiFont-SemiBold.ttf` | `NaikaiFont-SemiBold` | 1.89 | 600 | 37776240 | 36.0 | `d88f0931677cb43c276148e76d5c1f3c9a6c4089ee8b747fd9b2e59759b2b27b` | 8 | 4808 | — |
| `Xiaolai-Regular.ttf` | `Xiaolai` | 3.126 | 400 | 22220806 | 21.2 | `e2f68daf0e72777a8cf58bc83de1b98634b251e537ddbfca24b0ae50d1802da2` | 0 | 4808 | — |
| `Yozai-Medium.ttf` | `Yozai-Medium` | 0.868 | 500 | 15238394 | 14.5 | `05f50f252b45197d0d6148a4abc3e37c7cd4cfdf03c955b57c25d53d924f835f` | 0 | 4808 | — |
| `Yozai-Regular.ttf` | `Yozai-Regular` | 0.868 | 400 | 15605374 | 14.9 | `25071998a0fe6a72f54c235e714986d259633e5ff670b1a2b5e264387f3316ac` | 0 | 4808 | — |
| `NaniFont-Bold.ttf` | `NaniFont-Bold` | 1.046 | 700 | 18508716 | 17.7 | `1b5da5077665309289ba3e62c2fe4b1b788c800dd638af8113bff9fed96b588e` | 0 | 4808 | — |
| `NaniFont-Regular.ttf` | `NaniFont-Regular` | 1.046 | 400 | 17799572 | 17.0 | `3fb7b030f853f2efc4d97dd28fae08a6fa93a565fc91a8f585897e0d53716c1c` | 0 | 4808 | — |
| `LXGWMarkerGothic-Regular.ttf` | `LXGWMarkerGothic-Regular` | 1.003 | 400 | 3179616 | 3.0 | `9a1e46379442856b9fc64de1d9bd4120903780990e28d99fd6415cadee78a47d` | 0 | 4808 | — |
| `Slidechunfeng-Regular.ttf` | `Slidechunfeng-Regular` | 1.000 | 400 | 9673860 | 9.2 | `0c2c7998ca39dd2be38e302a457198ea6e573af2834ccd84015fe714f9569cca` | 8 | 3059 | 歲個週開紀錄 |
| `Slidefu-Regular.ttf` | `Slidefu-Regular` | 1.000 | 400 | 15172184 | 14.5 | `b8c59c7cddb8723a8f9c53ce0bd2a949d10241ddc88569c1cbb0eb4d889861d2` | 8 | 3059 | 歲個週開U+3000紀錄 |
| `Slideqiuhong-Regular.ttf` | `Slideqiuhong-Regular` | 1.000 | 400 | 14924580 | 14.2 | `d74ea3a8872e10226833793d0075716a4bcc2a3f72edb45cfeac6330f912d899` | 8 | 3059 | 歲個週開紀錄 |
| `Slidexiaxing-Regular.ttf` | `Slidexiaxing-Regular` | 1.000 | 400 | 10073644 | 9.6 | `fac1f0ec044b63aa45c0775c17a2f03cbf6427b4bd7b93da87dde9e7e2020cfc` | 8 | 3059 | 歲個週開紀錄 |
| `Slideyouran-Regular.ttf` | `slideyouran-Regular` | 1.000 | 400 | 12639808 | 12.1 | `10a92c32d388f119db8a975fe6f0507ec48d15e3050e7ff2971c3784ad878580` | 8 | 3059 | 歲個週開U+3000紀錄 |
| `Bakudai-Bold.ttf` | `Bakudai-Bold` | 1.48 | 700 | 16711616 | 15.9 | `59c99887980e8002c4dea7c4ad7b207e9dd080cf1aef0f698750f4f806183cf8` | 8 | 4808 | — |
| `MasaFont-Bold.ttf` | `MasaFont-Bold` | 2.1 | 700 | 19027924 | 18.1 | `8fa80974e45ce2ba43ce6dd68aa1f2d0005a79dae761f6dde46e4d0a51b2dfb7` | 8 | 4808 | — |
| `Cubic_11.ttf` | `Cubic_11` | 1.451 | 400 | 2773732 | 2.6 | `0193f5f033612496df6b45ee92ac3b335bc6a5a24ff95da55ca87b33e57dcf62` | 0 | 4808 | — |
| `WD-XLLubrifontTC-Regular.otf` | `WD-XLLubrifontTC-Regular` | 2.100 | 400 | 6161104 | 5.9 | `51c179e927526a9acd88b7722909e44c958133733ca316e824f812a28713768b` | 0 | 4808 | — |
| `fusion-pixel-12px-proportional-zh_tw.otf` | `Fusion-Pixel-12px-Prop-zh-TW-Regular` | 2026.09.25 | 400 | 4974596 | 4.7 | `27e8ed8d3c0eb6d6cd46d7fa1530afda8251f371f9d52ee87b2af634e8cc5c08` | 4 | 4808 | — |
| `fusion-pixel-12px-proportional-zh_hant.otf` | `Fusion-Pixel-12px-Prop-zh-Hant-Regular` | 2026.09.25 | 400 | 4975024 | 4.7 | `37bcf09fbcd112dd1889d1229b90854c46be599b4dd48b3526ff076dcade6552` | 4 | 4808 | — |

## 7. 如何重現

實測程式不在產品程式碼或測試裡，放在本文件旁的 [`fonts-tc-2/scripts/`](fonts-tc-2/scripts/)，不會被 build 或測試執行：

- `manifest.tsv`：下載清單，每行是「資料夾、網址」；台北黑體、教育部楷書、文鼎 UKai 附在最後。
- `analyze.py`：讀名稱、版本、`fsType`、字重值、4808 涵蓋率、疊字缺字、大小與 SHA-256。
- `render.swift`：畫比較稿，並列出每段文字實際使用的字型。
- `sheet.tsv`：比較稿的字型清單；`<fonts>` 換成你的下載資料夾。

```sh
# 1. 依 manifest.tsv 把字型下載到 $FONTS/<資料夾>/，zip 解到 $FONTS/<資料夾>/x/
#    文鼎 UKai 的 .deb 用 `tar -xf` 解兩層（.deb → data.tar.*），取得 usr/share/fonts/truetype/arphic/ukai.ttc
#    （下載檔視為不受信任資料，與腳本放在不同資料夾）
# 2. 4808 字表
curl -sL https://raw.githubusercontent.com/ButTaiwan/cjktables/master/taiwan/standard/edu_standard_1.txt \
  | grep -v '^#' | cut -f1 | grep -v '^$' > chars4808.txt
# 3. 分析
python3 -m venv venv && venv/bin/pip install fonttools
#    傳資料夾即可：analyze.py 會遞迴收集 .ttf／.otf／.ttc／.otc（含 x/ 子目錄與 ukai.ttc）
venv/bin/python -I docs/research/fonts-tc-2/scripts/analyze.py chars4808.txt out.json "$FONTS"
# 4. 比較稿與退回檢查
sed "s|<fonts>/|$FONTS/|" docs/research/fonts-tc-2/scripts/sheet.tsv > sheet.tsv
swift docs/research/fonts-tc-2/scripts/render.swift sheet.tsv comparison.png runs.tsv "TASK-121 繁中開源字型比較稿"
```

iOS 烘焙實測沿用 #73 §7 的 `FontsTCResearchTests`（`git show 35a8b12:DaysCamTests/Research/FontsTCResearchTests.swift`），把 `TEST_RUNNER_DAYSCAM_FONT_RESEARCH_BAKE` 換成推薦字型的 PostScript 名稱即可。
