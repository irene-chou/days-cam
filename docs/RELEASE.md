# DaysCam 上架（App Store）

> 擁有者：Lead。這頁只放 DaysCam 專屬的決策、建置步驟、回歸清單與商店資料；Apple 端的通用操作看官方文件，一次性問題在 chat 處理。agent 在雲端無法建置 iOS、簽名或登入 App Store Connect，標「人類」的項目要在有 Xcode 的 Mac 上執行。

## 決策

| 決定 | 影響 |
|---|---|
| 第一版只上 iPhone | `TARGETED_DEVICE_FAMILY: "1"`、移除 iPad 方向設定；日後上 iPad 要升次版並補 13 吋截圖 |
| 裝置顯示名稱「DaysCam」；商店名稱 2.0 起「DaysCam 天數相機 · 紀念日照片紀錄」（1.x 為「DaysCam 天數相機」） | 不加 `CFBundleDisplayName`；商店名稱補搜尋字，見「要填的資料」 |
| 免費、全地區 | MVP 排除 IAP（PRD 排除項） |
| 隱私權政策與支援頁放 GitHub Pages | 網址見下表 |
| 出口管制申報 `ITSAppUsesNonExemptEncryption = false` | 只用 HTTPS 下載字型，屬豁免 |
| Apple Developer Program Team ID `W5937V2WUF` | `project.yml`、`scripts/ExportOptions.plist` 使用此 Team |

## 建置與上傳

版本規則：功能升次版、修正升修訂版（`chore/bump-<版本>`，CI 全套測試），`CURRENT_PROJECT_VERSION` 每個新版本從 1 開始（升版 PR 一併歸 1），同一版本重新上傳才 +1（`chore/build-<號>`，同樣跑 CI 全套）。升版 PR 內文必附「此版本的新增功能」段落（繁中、給使用者看的 App Store「新功能」文案，≤4000 字，一行一項、不寫卡號與技術細節），人類直接貼到 App Store Connect（使用者 2026-10-23 指示）。送審前用 Organizer 的 Generate Privacy Report 核對 `PrivacyInfo.xcprivacy`（只申報 UserDefaults CA92.1、FileTimestamp C617.1），多出別的類別交 Lead 改程式。

GUI：Xcode 選「Any iOS Device (arm64)」→ Product → Archive → Organizer → Distribute App → App Store Connect，自動簽名。

指令：

```bash
xcodegen generate
xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/DaysCam.xcarchive archive
xcodebuild -exportArchive -archivePath build/DaysCam.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates
```

## 實機驗收（B 級，TestFlight）

每版上傳後跑一次，結果記到升版 PR。2.0.0 起改為下表（照片不動、瀏覽即時標天數、匯出才烘焙，PRD-2.0）；1.x 的「拍照即印字」「存到 DaysCam 相簿開關」項目已不適用。

| # | 情境 | 期望 |
|---|---|---|
| R-1 | 全新安裝首次開啟 | 不詢問照片權限（PRD-2.0 §7.1）；相機權限提示文案為 `NSCameraUsageDescription`；首頁是紀錄列表 |
| R-2 | 拒絕相機權限 | 引導到「設定」的畫面，不閃退 |
| R-3 | 第一次點進紀錄 | 先出權限說明頁，按「繼續」才跳系統詢問；文案為 `NSPhotoLibraryUsageDescription`（§7.1） |
| R-4 | 允許完整取用 | 「照片」App 出現與紀錄同名的相簿；在「照片」App 把照片放進該相簿，回到 DaysCam 照片牆出現並標出第幾天 |
| R-5 | 拍一張 | 「照片」App 的紀錄相簿多一張**沒有印字**的原圖；照片牆即時標天數 |
| R-6 | 限制取用（只允許部分照片） | 不建相簿；照片牆頂端出現提示列；拍照與「加入照片」只出現在當下紀錄；改成完整取用後提示列「加進相簿」可一次補進相簿，照片數不變 |
| R-7 | 不允許照片權限 | 照片牆換成「需要「照片」權限」頁，「前往設定」可開設定；紀錄列表仍可進 |
| R-8 | 單張匯出、批次匯出（含「隱藏文字」） | 另存新照片到「最近項目」，原圖不變；印字與預覽一致；隱藏文字時不印天數 |
| R-9 | 從 1.3.0 升級（先裝 App Store 版拍幾張、設兩個紀錄，再裝 TestFlight） | 紀錄、起始日、樣式都在；1.x 拍的照片出現在原紀錄（PRD-2.0 §4.3） |
| R-10 | 起始日之前的照片、跨午夜或改裝置日期後回到 App | 早於起始日顯示「前 N 天」；天數即時更新（Release 沒有假時鐘，要真的改日期） |
| R-11 | 音量鍵、動作按鈕、相機控制鈕 | 在相機畫面按下＝快門 |
| R-12 | 水平儀、疊字預覽開關 | 水平儀細長、水平時連成一線；疊字預覽可開關 |
| R-13 | 來電／切到背景再回來 | 預覽恢復，可繼續拍 |
| R-14 | iOS「設定」→ DaysCam →「字型授權」 | 看得到各字型版權與授權全文 |
| R-15 | 飛航模式套用需下載字型的樣式 | 顯示失敗可重試；內建字型照常可用 |
| R-16 | 相機比例 3:4／1:1／9:16 各拍一張（直拿、橫拿） | 「照片」App 裡的照片比例與取景框一致、方向正確、沒有印字；3:4 不裁（#712） |
| R-17 | 面板「內容」把天數、日期、名稱全關 | 取景窗與匯出都不畫字；照片牆、大圖頂列的天數照常（#713） |

## 要填的資料（App Store Connect，2.0）

2.0 主軸從「拍照即印字的相機」改成「照片不動、瀏覽標天數、匯出才印」（PRD-2.0），商店資料整份重寫。1.x 的文案在 git 歷史（`243e4a0`）。

### 搜尋權重原則

- App Store 搜尋只索引**名稱、副標、關鍵字**三欄（權重依序遞減）；描述與宣傳文字不索引，只影響轉換率。
- 三欄之間不重複用字（重複不加分，只浪費字數）；關鍵字用半形逗號分隔、不加空格；不放別家 App 名稱（審查準則 2.3.7）。
- 中文會自動拆字組合：名稱有「天數」「相機」「紀念日」「照片」「紀錄」，就涵蓋「天數紀錄」「紀念日相機」「照片紀錄」等組合，不必再寫一次。
- 只放 2.0 真的有的功能；拍立得框、對比圖、影片是後期，不寫。
- 改名稱、副標、關鍵字要隨新版本送審才生效；宣傳文字可隨時改。上架兩到四週後看 App Store Connect「分析 › 來源 › App Store 搜尋」的曝光與轉換再調關鍵字。

### 繁體中文（主要語言）

| 欄位 | 值 | 字數／上限 |
|---|---|---|
| Bundle ID | `com.irenechou.DaysCam` | — |
| SKU | `dayscam-ios` | — |
| 名稱 | DaysCam 天數相機 · 紀念日照片紀錄 | 22／30 |
| 副標 | 寶寶成長、戀愛、健身，每張照片標出第幾天 | 20／30 |
| 關鍵字 | 倒數,日期,浮水印,時間戳記,打卡,育兒,懷孕,孕期,在一起,交往,情侶,週年,滿月,生日,嬰兒,新生兒,親子,寵物,毛孩,減肥,戒菸,日記,相簿,記錄,計算,日子,里程碑,計日,幾天,月齡,時光 | 98／100 |
| 宣傳文字 | 平常照樣用內建相機拍。把照片放進紀錄，DaysCam 自動標出每張是第幾天，原圖完全不動；想分享時，再匯出一張印上天數的新照片。寶寶成長、戀愛紀念、健身打卡都適用。 | 82／170 |
| 主要類別 | 攝影與錄影 | — |
| 次要類別 | 生活風格（新增；多一個類別榜與瀏覽入口） | — |
| 隱私權政策 URL | <https://irene-chou.github.io/dayscam-privacy/privacy/>（**公開頁要照 `docs/PRIVACY-POLICY.md` 更新**，1.x 版寫的是「僅新增」與拍照烘焙） | — |
| 支援 URL | <https://irene-chou.github.io/dayscam-privacy/> | — |
| 聯絡信箱 | irene.chou0710@gmail.com | — |
| App 隱私 | 不收集資料（不變；讀取照片只在裝置上，與隱私清單一致） | — |
| 年齡分級 | 全部「無」→ 4+ | — |
| 價格與地區 | 免費、全地區（不變） | — |

描述（不影響搜尋，前三行決定「更多」之前看到什麼）：

```text
DaysCam 幫你的照片標出「第幾天」。設定一個起始日——寶寶出生、在一起、開始健身、搬進新家——每張照片都會依拍攝日期，自動算出那天是第幾天。

平常照樣用內建相機拍。把照片放進紀錄，DaysCam 即時標上天數，原始照片完全不動；想分享時，再匯出一張印好天數或日期的新照片。

【照片不動，天數照樣看得到】
・每個紀錄對應「照片」App 裡的一本相簿，在那裡加進的照片會自動出現
・照片牆依月份排列，每張標出第幾天
・起始日之前的照片顯示「前 N 天」
・改了起始日，所有天數立刻重算

【想分享，再印上去】
・匯出是另存一張新照片，原圖不變
・一次選多張批次匯出，也可以隱藏文字
・十款文字樣式：經典、字幕、海報、描邊、雜誌、手寫、便條、可愛、霓虹、復古
・自選顏色、底框、大小與位置，還能加底片風格的日期戳記
・內建繁體中文開源字型

【也是一台乾淨的相機】
・取景窗即時預覽天數，拍下的是沒有印字的原圖
・3:4、1:1、9:16 比例，格線、水平儀、計時器
・音量鍵、相機控制鈕都能當快門

【多個紀錄，同時記錄不同的日子】
寶寶成長、戀愛紀念、健身、寵物、新家，各有自己的起始日、相簿與樣式。

【你的照片只屬於你】
・沒有帳號、沒有廣告、不追蹤
・照片只存在你的「照片」圖庫，不會上傳到任何地方
```

此版本的新增功能（2.0.0）：

```text
2.0 是一次大改版：照片不再被印字。

・拍下與加入的照片都保持原樣，天數改在瀏覽時即時標出
・全新的紀錄首頁與照片牆：每個紀錄對應「照片」App 的一本相簿，用內建相機拍的照片也能加入
・想分享時再匯出：另存一張印上天數的新照片，可批次匯出、可隱藏文字
・十款文字樣式一鍵套用，另有底片日期戳記
・相機新增水平儀，音量鍵與相機控制鈕可當快門
・原有的紀錄、起始日與樣式都會保留；之前拍的照片會出現在你最後使用的紀錄
・第一次進入紀錄時會詢問「照片」權限，用來讀取紀錄的相簿
```

審查備註：

```text
無需帳號登入。2.0 是大改版：App 不再於拍照時把字印進照片，改為瀏覽時即時標出天數，使用者匯出時才另存一張印字的新照片，原始照片不會被修改。

照片權限：第一次點進任一紀錄時，會先顯示說明頁，按「繼續」才出現系統詢問（啟動時不詢問）。需要完整取用是因為每個紀錄對應「照片」App 的一本相簿：App 會建立相簿、讀取相簿內的照片來顯示第幾天，並把拍的照片加進該相簿。選「限制取用」或「不允許」App 仍可使用（限制取用時只顯示使用者在 App 內加入或拍攝的照片）。

測試方式：首頁點「我的紀錄」→ 允許照片權限 → 左下角「加入照片」選幾張 → 照片牆顯示每張第幾天 → 點一張 →「匯出」。相機功能（照片牆右下「拍照」）需要實機。

網路：只有在文字樣式選到尚未下載的字型時，會從公開的 GitHub／jsDelivr 下載開源字型檔（非可執行程式碼）；除此之外 App 不自行連線（匯出 iCloud 照片時由系統「照片」下載原圖）。
```

### 截圖（iPhone 6.9 吋 1320×2868，不需 iPad；1.x 那組全部重拍）

搜尋結果只露出前三張，所以前三張要單看就懂；每張上方加一行大字標題（標題文字據 ASO 業界觀察也會被搜尋讀到，用字與名稱、副標互補）。

| # | 畫面 | 標題 |
|---|---|---|
| 1 | 照片牆（每格標第幾天） | 每張照片，都記得是第幾天 |
| 2 | 匯出面板（原圖與印字預覽） | 原圖不動，分享時再印上天數 |
| 3 | 紀錄列表（寶寶、在一起、健身三個紀錄） | 寶寶、戀愛、健身，各記各的日子 |
| 4 | 文字樣式（十款樣式膠囊） | 十款文字樣式，一鍵套用 |
| 5 | 相機取景窗（疊字預覽） | 邊拍邊看天數，存下的是乾淨原圖 |
| 6 | 照片牆選取模式 | 一次選多張，批次匯出 |

### 英文（選用，建議加 English (U.K.)）

台灣、香港店面除了繁體中文也索引 English (U.K.) 的名稱／副標／關鍵字，加這個語系等於多 100 字關鍵字；沒有英文語系時，其他國家店面顯示繁中資料。App 介面只有繁中，描述第一行要寫明。

| 欄位 | 值 | 字數／上限 |
|---|---|---|
| 名稱 | DaysCam: Day Counter Photos | 27／30 |
| 副標 | Label photos with day counts | 28／30 |
| 關鍵字 | date,stamp,timestamp,baby,milestone,anniversary,journal,tracker,since,album,pregnancy,fitness,camera | 100／100 |
| 宣傳文字 | Shoot with your usual camera. DaysCam shows which day each photo was taken on, and never touches the original. | 110／170 |

```text
Interface language: Traditional Chinese only.

DaysCam labels every photo with its day number. Pick a start date (a birth, an anniversary, day one at the gym) and each photo shows which day it was taken on.

• Your originals are never modified; day counts are drawn live while you browse
• Each record syncs with an album in the Photos app
• Export a new copy with the day count or date stamped on, one photo or many
• Ten text styles, custom colour, size and position, optional film-style date stamp
• A clean camera with live preview, 3:4 / 1:1 / 9:16, grid, level and timer
• No account, no ads, no tracking; photos stay in your library
```

## 上架後

- 退件或當機需要改程式時走 `fix/` 分支，升修訂版（build 號歸 1），重新 Archive。
- App Store Connect 的「當機」與「TestFlight 回饋」由 Lead 轉成 Issue。
