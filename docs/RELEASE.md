# DaysCam 上架手冊（App Store）

> 擁有者：Lead。2026-10-10 依人類「協助我將 app 上架」整理。此處的「人類」指 Apple 開發者帳號持有人；agent 在雲端無法建置 iOS、簽名或登入 App Store Connect，第 2 步起的操作都要在有 Xcode 的 Mac 上由人類執行。

## 現況速覽（2026-10-10，main `d289101`）

| 項目 | 狀態 | 說明 |
|---|---|---|
| Bundle ID／Team | ✅ | `com.irenechou.DaysCam`、Team `W5937V2WUF`，自動簽名（`project.yml`） |
| 權限用途說明 | ✅ | 相機、相簿新增、相簿讀取三段繁中說明都在 `project.yml` |
| 隱私清單 `PrivacyInfo.xcprivacy` | ✅ 本次補上 | 不追蹤、不收集；申報 UserDefaults（CA92.1）。缺少會被 App Store Connect 退回 |
| 出口管制 `ITSAppUsesNonExemptEncryption` | ✅ 本次補上 | 設 `false`（只用 HTTPS 下載字型），上傳後不必每次回答加密問卷 |
| Release 不含除錯時鐘 | ✅ | `DAYSCAM_FAKE_TODAY` 與 `-UITest*` 旗標都在 `#if DEBUG` 內（TASKS 0.1 §10.4） |
| 字型授權 | ✅ | OFL／Apache 全文隨 App 內建並可在字型頁查看；下載來源為公開 repo（允許 2.5.2：下載的是字型檔不是程式碼） |
| **App 圖示** | ❌ 阻擋 | `Assets.xcassets/AppIcon.appiconset` 只有空的 `Contents.json`，沒有 1024×1024 圖檔。沒有圖示無法上傳 |
| **版本號** | ⏳ 待升 | 目前 `0.5.0`；正式上架才改 `1.0.0`（AGENTS 硬規則），走升版 PR `chore/bump-1.0.0` 讓 CI 跑全套測試 |
| **iPad 支援** | ⚠️ 待決定 | `TARGETED_DEVICE_FAMILY: "1,2"` 等於宣告支援 iPad：審查會在 iPad 測、必須附 13 吋 iPad 截圖，而所有設計稿都只照 iPhone 16 |
| 隱私權政策網址 | ⏳ | App Store Connect 必填。草稿在 [PRIVACY-POLICY.md](PRIVACY-POLICY.md)，需放到公開網址 |
| 螢幕截圖、商店文案 | ⏳ | 第 5 步 |
| 實機驗收（B 級） | ⏳ | 第 4 步，透過 TestFlight |

## 第 0 步：人類先決定

| # | 問題 | 建議 |
|---|---|---|
| D1 | 要不要支援 iPad？ | **建議只上 iPhone**：把 `TARGETED_DEVICE_FAMILY` 改 `"1"`，刪掉 `UISupportedInterfaceOrientations~ipad`。少一組截圖與審查面，之後想加再升版。保留 iPad 就要補 13 吋截圖並在 iPad 實機跑一遍 B 級 |
| D2 | 商店顯示名稱 | App 在裝置上目前顯示「DaysCam」。若想顯示「天數相機」，在 `project.yml` `info.properties` 加 `CFBundleDisplayName`。商店名稱（最長 30 字）可寫「DaysCam 天數相機」 |
| D3 | App 圖示 | 需要一張 1024×1024、不透明、無圓角的 PNG。人類提供設計或指定 agent 出草稿 |
| D4 | 價格與地區 | 建議免費、全地區；MVP 排除 IAP（PRD §排除項） |
| D5 | 隱私權政策放哪 | GitHub Pages、Notion 公開頁或任何固定網址皆可；內容用 [PRIVACY-POLICY.md](PRIVACY-POLICY.md) 改 |
| D6 | 支援信箱／網址 | App Store Connect 必填支援 URL；可用 repo Issues 頁或 Notion 頁 |

決定後由 Lead 開一張任務卡（`chore/release-1.0`）處理 D1–D3 的程式變更，再開 `chore/bump-1.0.0` 升版 PR。

## 第 1 步：程式與專案準備（Lead／agent 可做）

1. 合併本次的隱私清單與出口管制設定。
2. 放入 App 圖示：把 1024 PNG 放進 `DaysCam/Assets.xcassets/AppIcon.appiconset/`，`Contents.json` 的那筆加上 `"filename"`。
3. 依 D1、D2 修改 `project.yml`。
4. 開 `chore/bump-1.0.0`：`MARKETING_VERSION` 改 `"1.0.0"`、`CURRENT_PROJECT_VERSION` 保持 `"1"`（每次重新上傳同版本就加 1）；README 路線圖把 0.4 改為已完成並加一列「1.0 上架」。這條分支會觸發 `swift.yml` 跑完整測試，全綠才合併。
5. 建議在合併升版 PR 後打 tag：`git tag v1.0.0 && git push origin v1.0.0`。

## 第 2 步：Apple Developer 與 App Store Connect 建檔（人類）

1. 確認 [Apple Developer Program](https://developer.apple.com/account) 會員有效，且 Team `W5937V2WUF` 是這個帳號。
2. Certificates, Identifiers & Profiles → Identifiers：確認 `com.irenechou.DaysCam` 已註冊（Xcode 自動簽名第一次 Archive 時也會自動建立，可先跳過）。Capability 不需要額外勾選。
3. [App Store Connect](https://appstoreconnect.apple.com) → My Apps → ＋ → New App：
   - 平台 iOS、名稱（D2）、主要語言「繁體中文」、Bundle ID 選 `com.irenechou.DaysCam`、SKU 填 `dayscam-ios`。
4. 「App 資訊」：類別選「攝影與錄影」，內容版權填你的名字。
5. 「價格與供應情況」：依 D4。

## 第 3 步：Archive 與上傳（人類，在 Mac）

GUI 走法（第一次建議用這個）：

1. `git checkout main && git pull && xcodegen generate`，用 Xcode 開 `DaysCam.xcodeproj`。
2. 目標選「Any iOS Device (arm64)」，Product → Archive。
3. Organizer → Distribute App → App Store Connect → Upload，簽名選 Automatically manage signing，其餘預設。

指令走法（之後重複上傳用）：

```bash
xcodegen generate
xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/DaysCam.xcarchive archive
xcodebuild -exportArchive -archivePath build/DaysCam.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates
```

上傳後 10–30 分鐘 App Store Connect 的 TestFlight 頁會出現該 build；若收到「Missing Privacy Manifest」或「ITMS-9xxxx」信件，對照速覽表檢查。

## 第 4 步：TestFlight 實機驗收（人類；B 級）

在 TestFlight 加自己為內部測試員，裝到實機後至少跑一遍下列情境，結果記到升版 PR：

| # | 情境 | 期望 |
|---|---|---|
| R-1 | 全新安裝首次開啟 | 出現相機權限提示，文案為 `project.yml` 的 `NSCameraUsageDescription` |
| R-2 | 拒絕相機權限 | 看到引導到「設定」的畫面，不閃退 |
| R-3 | 拍一張、存檔 | 只彈「新增照片」權限（addOnly）；相簿裡的照片疊字與觀景窗一致 |
| R-4 | 拒絕相簿新增權限後再拍 | 明確顯示儲存失敗，不報成功（AGENTS Code Review Rules） |
| R-5 | 圖庫頁開啟「存到 DaysCam 相簿」 | 此時才要求讀寫權限（#281） |
| R-6 | 飛航模式下到字型頁下載字型 | 顯示失敗可重試；已內建字型照常可用 |
| R-7 | 跨午夜或改裝置日期後回到 App | 觀景窗天數即時更新 |
| R-8 | 來電／切到背景再回來 | 預覽恢復，可繼續拍 |
| R-9 | 兩個設定檔快速切換後拍照 | 照片印的是切換後的設定檔 |
| R-10 | （保留 iPad 時）iPad 直向 | 版面不破、可拍可存 |

Release build 沒有 `DAYSCAM_FAKE_TODAY`，R-7 要真的改系統日期或等到跨日。

## 第 5 步：商店資料與審查備註（人類）

**截圖**（App Store Connect → 該版本 → App 預覽與截圖）：

- iPhone 6.9 吋（iPhone 16 Pro Max／17 Pro Max，1320×2868）必填，最多 10 張；其他 iPhone 尺寸會自動沿用。
- 保留 iPad 時另需 iPad 13 吋（2064×2752）。
- 建議 5 張：觀景窗＋天數、疊字面板（樣式）、位置拖曳、設定檔頁、成品照片。用模擬器 `⌘S` 截圖即可，不能是裝置外框合成以外的加工畫面。

**文案草稿**（可直接改）：

- 副標（30 字內）：把日子印在照片上
- 宣傳文字：拍照時就把「第 N 天」或日期寫進照片，不用事後編輯。
- 描述：
  > DaysCam 是一台專門記錄日子的相機。設定一個起始日——寶寶出生、開始健身、搬進新家——之後每一張照片都會自動印上今天是第幾天，或是當天的日期。
  >
  > ・天數或日期直接烘焙進照片像素，到任何地方都看得見
  > ・多組設定檔，同時記錄不同的日子
  > ・自選字型、顏色、大小與位置；內建繁體中文開源字型
  > ・完全離線、沒有帳號，照片只存在你的相簿
- 關鍵字（100 字元內）：天數,日期相機,紀念日,寶寶,打卡,倒數,日期浮水印,day counter,date stamp,timestamp camera
- 支援 URL／隱私權政策 URL：依 D5、D6。

**App 隱私（Privacy Nutrition Label）**：選「不收集資料」。與 `PrivacyInfo.xcprivacy` 一致。

**年齡分級**：全部選「無」→ 4+。

**審查備註（App Review Information → Notes）**：

> 這是一款相機 App，需要在實機測試。無需帳號登入。拍照後照片會存進系統相簿，請允許相機與相簿權限。字型頁的「下載」會從公開的 GitHub／jsDelivr 下載開源字型檔（非可執行程式碼）；其餘功能完全離線。

**出口管制**：因為 Info.plist 已含 `ITSAppUsesNonExemptEncryption = false`，上傳後不會再問。

## 第 6 步：送審與退件處理

1. 選定 build、填完所有欄位、按「加入審查」。首次審查通常 24–48 小時。
2. 常見退件與對策：
   - Guideline 2.1（閃退／無法使用）：多半是審查員拒絕權限後的流程；R-2、R-4 要先在實機過。
   - Guideline 5.1.1（權限文案不夠具體）：三段 `project.yml` 文案已寫明用途，若仍被退，在審查備註補流程說明。
   - Guideline 2.3（截圖與實際不符）：截圖要來自這個 build。
3. 退件在「解決方案中心」回覆；需要改程式就走 `fix/` 分支 → 升修訂版 `1.0.1`、`CURRENT_PROJECT_VERSION` +1 → 重新 Archive。

## 第 7 步：上架後

- 上架當天在 README 路線圖加「1.0 已上架（日期）」，`v1.0.0` tag 指向合併的升版 commit。
- 之後版本依 AGENTS：功能升次版、修正升修訂版；每次上傳 build 號 +1。
- 開啟 App Store Connect 的「當機」與「TestFlight 回饋」，由 Lead 轉成 Issue。
