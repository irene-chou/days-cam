# DaysCam 上架（App Store）

> 擁有者：Lead。這頁只放 DaysCam 專屬的決策、檢查表與要填的資料；Apple 端的通用操作看官方文件，一次性問題在 chat 處理。agent 在雲端無法建置 iOS、簽名或登入 App Store Connect，標「人類」的項目要在有 Xcode 的 Mac 上執行。

## 決策紀錄

| 日期 | 決定 | 影響 |
|---|---|---|
| 2026-10-10 | 第一版只上 iPhone | `TARGETED_DEVICE_FAMILY: "1"`、移除 iPad 方向設定；日後上 iPad 要升次版並補 13 吋截圖 |
| 2026-10-10 | 裝置顯示名稱維持「DaysCam」；商店名稱用「DaysCam 天數相機」 | 不加 `CFBundleDisplayName` |
| 2026-10-10 | 免費、全地區 | MVP 排除 IAP（PRD 排除項） |
| 2026-10-10 | 隱私權政策與支援頁放 GitHub Pages | 網址見下表 |
| 2026-10-10 | 出口管制申報 `ITSAppUsesNonExemptEncryption = false` | 只用 HTTPS 下載字型，屬豁免 |
| 2026-10-12 | Apple Developer Program 已開通，Team ID 維持 `W5937V2WUF`；版本升 1.0.0 | `project.yml`、`scripts/ExportOptions.plist` 不必改 Team；`MARKETING_VERSION: "1.0.0"`（`chore/bump-1.0.0`） |

## 送審前檢查表

| 項目 | 狀態 | 依據 |
|---|---|---|
| 隱私清單 `DaysCam/PrivacyInfo.xcprivacy` | ✅ | 不追蹤、不收集；申報 UserDefaults（CA92.1）與 FileTimestamp（C617.1，字型驗證標記只讀 App 容器內字型檔的修改日期）。Archive 後用 Organizer 的 Generate Privacy Report 核對，多出別的類別就交 Lead 改程式 |
| 出口管制、權限用途說明 | ✅ | `project.yml` `info.properties` |
| Release 不含除錯時鐘與 UI 測試旗標 | ✅ | `DAYSCAM_FAKE_TODAY`、`-UITest*` 都在 `#if DEBUG`（TASKS 0.1 §10.4） |
| App 圖示 | ✅ | `AppIcon.png` 1024×1024、無 alpha、未預切圓角（#383） |
| 字型授權 | ✅ | OFL／Apache 全文內建於字型頁；下載的是字型檔不是程式碼 |
| 版本號 `1.0.0` | ✅ | `chore/bump-1.0.0`（CI 全套測試），合併後打 tag `v1.0.0`。之後功能升次版、修正升修訂版，每次上傳 `CURRENT_PROJECT_VERSION` +1 |
| Apple Developer Program 會員 | ✅ | 2026-10-12 開通，Team ID 與 `W5937V2WUF` 相同，`project.yml` 與 `scripts/ExportOptions.plist` 不必改 |
| TestFlight 實機驗收 | ⏳ 人類 | 下方「實機驗收」 |
| 截圖、商店資料 | ⏳ 人類 | 下方「要填的資料」 |

## 建置與上傳

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

結果記到升版 PR。

| # | 情境 | 期望 |
|---|---|---|
| R-1 | 全新安裝首次開啟 | 相機權限提示文案為 `NSCameraUsageDescription` |
| R-2 | 拒絕相機權限 | 引導到「設定」的畫面，不閃退 |
| R-3 | 拍一張、存檔 | 只彈「新增照片」權限（addOnly）；相簿裡的疊字與觀景窗一致 |
| R-4 | 拒絕相簿新增權限後再拍 | 明確顯示儲存失敗，不報成功 |
| R-5 | 圖庫頁開啟「存到 DaysCam 相簿」 | 此時才要求讀寫權限（#281） |
| R-6 | 飛航模式下載字型 | 顯示失敗可重試；內建字型照常可用 |
| R-7 | 跨午夜或改裝置日期後回到 App | 觀景窗天數即時更新（Release 沒有假時鐘，要真的改日期） |
| R-8 | 來電／切到背景再回來 | 預覽恢復，可繼續拍 |
| R-9 | 兩個設定檔快速切換後拍照 | 照片印的是切換後的設定檔 |

## 要填的資料（App Store Connect）

| 欄位 | 值 |
|---|---|
| Bundle ID | `com.irenechou.DaysCam` |
| SKU | `dayscam-ios` |
| 名稱 | DaysCam 天數相機 |
| 主要語言 | 繁體中文 |
| 類別 | 攝影與錄影 |
| 副標 | 每張照片都記得第幾天（2026-10-12 人類選定；原案「把日子印在照片上」） |
| 宣傳文字 | 寶寶出生、開始健身、搬進新家……設定一個起始日，之後按下快門，天數就直接印在照片上。離線、免帳號，照片只存在你的相簿。（2026-10-12 人類選定；原案「拍照時就把「第 N 天」或日期寫進照片，不用事後編輯。」） |
| 關鍵字 | 天數,日期相機,紀念日,寶寶,打卡,倒數,日期浮水印,day counter,date stamp,timestamp camera |
| 隱私權政策 URL | <https://irene-chou.github.io/dayscam-privacy/privacy/> |
| 支援 URL | <https://irene-chou.github.io/dayscam-privacy/> |
| 聯絡信箱 | irene.chou0710@gmail.com |
| App 隱私 | 不收集資料（與隱私清單一致） |
| 年齡分級 | 全部「無」→ 4+ |
| 截圖 | iPhone 6.9 吋 1320×2868 必填，不需 iPad；建議觀景窗＋天數、樣式面板、位置拖曳、設定檔頁、成品照片五張，模擬器 `⌘S` 直出 |

描述：

> DaysCam 是一台專門記錄日子的相機。設定一個起始日——寶寶出生、開始健身、搬進新家——之後每一張照片都會自動印上今天是第幾天，或是當天的日期。
>
> ・天數或日期直接烘焙進照片像素，到任何地方都看得見
> ・多組設定檔，同時記錄不同的日子
> ・自選字型、顏色、大小與位置；內建繁體中文開源字型
> ・完全離線、沒有帳號，照片只存在你的相簿

審查備註：

> 這是一款相機 App，需要在實機測試。無需帳號登入。拍照後照片會存進系統相簿，請允許相機與相簿權限。字型頁的「下載」會從公開的 GitHub／jsDelivr 下載開源字型檔（非可執行程式碼）；其餘功能完全離線。

## 上架後

- README 路線圖加「1.0 已上架（日期）」。
- 退件或當機需要改程式時走 `fix/` 分支，升修訂版，build 號 +1，重新 Archive。
- App Store Connect 的「當機」與「TestFlight 回饋」由 Lead 轉成 Issue。
