# DaysCam 上架（App Store）

> 擁有者：Lead。這頁只放 DaysCam 專屬的決策、建置步驟、回歸清單與商店資料；Apple 端的通用操作看官方文件，一次性問題在 chat 處理。agent 在雲端無法建置 iOS、簽名或登入 App Store Connect，標「人類」的項目要在有 Xcode 的 Mac 上執行。

## 決策

| 決定 | 影響 |
|---|---|
| 第一版只上 iPhone | `TARGETED_DEVICE_FAMILY: "1"`、移除 iPad 方向設定；日後上 iPad 要升次版並補 13 吋截圖 |
| 裝置顯示名稱「DaysCam」；商店名稱「DaysCam 天數相機」 | 不加 `CFBundleDisplayName` |
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

## 要填的資料（App Store Connect）

| 欄位 | 值 |
|---|---|
| Bundle ID | `com.irenechou.DaysCam` |
| SKU | `dayscam-ios` |
| 名稱 | DaysCam 天數相機 |
| 主要語言 | 繁體中文 |
| 類別 | 攝影與錄影 |
| 副標 | 每張照片都記得第幾天 |
| 宣傳文字 | 寶寶出生、開始健身、搬進新家……設定一個起始日，之後按下快門，天數就直接印在照片上。離線、免帳號，照片只存在你的相簿。 |
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

- 退件或當機需要改程式時走 `fix/` 分支，升修訂版（build 號歸 1），重新 Archive。
- App Store Connect 的「當機」與「TestFlight 回饋」由 Lead 轉成 Issue。
