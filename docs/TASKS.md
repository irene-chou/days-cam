# DaysCam MVP 任務清單

- 版本：v1.0
- 日期：2026-09-19
- 上游：[`docs/PRD.md`](./PRD.md)、`PROJECT_PLAN.md`、`CLAUDE.md`

---

## 怎麼用這份文件

**每張卡的結構**：目標 / 範圍 / 驗收（分兩級）/ 依賴。顆粒度為**單一 PR 可完成**。

**驗收分兩級**：

| 級別 | 含義 | 誰執行 |
|---|---|---|
| **A. QA 可自動跑** | 單元測試、靜態檢查（grep）、模擬器上的 UI 操作 | QA teammate 可獨立完成，不需人類介入 |
| **B. 需人類實機** | 實體相機拍攝、烘焙結果目視、存入相簿、AirDrop、系統權限彈窗 | 必須人類拿實機做 |

QA teammate 沒有手可以拿手機，請**只跑 A 級**，B 級標記為「待人類驗」後回報，不要卡在上面。

**時間相關的驗收為何多數落在 A 級**：TASK-02 會建立一個 `#if DEBUG` 的時間覆寫機制（環境變數 `DAYSCAM_FAKE_TODAY`），讓模擬器可在不動主機時鐘的前提下驗證任意日期。沒有它，幾乎所有疊字驗收都會被迫落到 B 級。

**兩個最容易做錯的地方**：

1. **PRD FR-2.10：`dateOnly` 模板永不讀取 `startDate`。** 若用「起始日＝今天」來近似純日期，隔天會變成「第 2 天」。TASK-04（4.16／4.19）有專門的對照測試。
2. **PRD §4.1 不變條件 2：`startDate` 夾帶 `timeZone` 會繞過時區規則，且 `startOfDay` 救不回來。** TASK-03（3.21／3.27）有專門檢查，且**時區組合不可自行更換**（原因寫在條目裡）。

---

## 依賴結構

```
第 0 層
  TASK-01 建置設定與專案骨架（含 Info.plist 權限字串）★ 必須最先完成

第 1 層
  TASK-02 DayCountCalculator ★ 最高優先        ← 01
  TASK-03 CameraProfile 與持久化               ← 01
  TASK-05 OverlayTheme                         ← 01
  TASK-07 相機權限與觀景窗                      ← 01

第 2 層
  TASK-04 TemplateRenderer                     ← 01, 02
  TASK-09 OverlayRenderer（烘焙）               ← 04, 05

第 3 層
  TASK-06 設定檔清單與編輯頁                    ← 03, 04
  TASK-08 觀景窗即時疊字                        ← 04, 05, 07
  TASK-10 拍照 → 烘焙 → 存相簿                  ← 07, 09

第 4 層
  TASK-11 顯示設定面板                          ← 03, 04, 05, 08
  TASK-12 首次啟動與狀態還原                    ← 03, 06, 07
  TASK-13 相機畫面切換設定檔                    ← 06, 08
  TASK-14 跨午夜刷新                            ← 08, 10
  TASK-15 錯誤處理與提示                        ← 03, 10

第 5 層
  TASK-16 端對端整合驗收                        ← 全部
```

**建議分工**：Dev A 走邏輯線（02 → 04 → 09），Dev B 走 UI/相機線（07 → 03 → 06）。TASK-01 必須先合併，兩線才能開工。

> **TASK-01 為何必須最先**：目前 `Info.plist` **沒有** `NSCameraUsageDescription`。iOS 規定缺這個鍵時一呼叫 AVFoundation 就直接 crash。相機相關的卡在第 1 層就會用到，所以權限字串必須在 TASK-01 補齊，不能留到最後。

---

## TASK-01：建置設定與專案骨架

**目標**
把專案從「3 個樣板檔、無測試 target」變成可分層開發、可跑測試、簽章不會壞的狀態。後續所有卡都依賴這張。

**範圍**

1. **`project.yml`**
   - `options.deploymentTarget.iOS`：`"17.0"` → `"18.0"`
   - `settings.DEVELOPMENT_TEAM`：`""` → `"W5937V2WUF"`
   - `SWIFT_VERSION` **維持 `"5.0"`**（刻意不升，見 PRD §9）
   - 新增 `DaysCamTests` target（`type: bundle.unit-test`、`platform: iOS`、`sources: [DaysCamTests]`、`dependencies: [target: DaysCam]`）
2. **`.gitignore`** 加入 `*.xcodeproj`，並執行 `git rm -r --cached DaysCam.xcodeproj` 把它移出版控
3. **`README.md`** 註明 clone 後必須先跑 `xcodegen generate` 才有 `.xcodeproj`
4. **`Info.plist`** 補兩個權限字串：
   - `NSCameraUsageDescription`：`DaysCam 需要使用相機來拍照，並把天數印在照片上。`
   - `NSPhotoLibraryAddUsageDescription`：`DaysCam 需要權限才能把拍好的照片存進你的相簿。`
   - **不得**加入 `NSPhotoLibraryUsageDescription`（讀取權限，MVP 不需要）
5. **分層資料夾**：`DaysCam/Models/`、`DaysCam/Services/`、`DaysCam/Views/`、`DaysCamTests/`
6. **共用型別**（`Models/`，皆為 `String` raw value 的 `enum`，皆 `Codable`、`CaseIterable`，附英文文件註解）：
   - `CountingRule`：`dayOne`、`dayZero`
   - `TemplateID`：`dayCount`、`unitConverted`、`dateOnly`、`dateAndDayCount`、`weekCount`
   - `OverlayPosition`：`topLeading`、`topCenter`、`topTrailing`、`middleLeading`、`middleCenter`、`middleTrailing`、`bottomLeading`、`bottomCenter`、`bottomTrailing`
   - `ThemeID`：`classicWhite`、`retroOrange`、`filmStrip`、`minimalDark`、`softPink`

> **`DEVELOPMENT_TEAM` 這項不能漏**：Team ID `W5937V2WUF` 目前**只存在於 `DaysCam.xcodeproj/project.pbxproj`**。跑一次 `xcodegen generate` 就會被 `project.yml` 的空字串覆蓋、簽章無聲失效；而本卡又要把 pbxproj 移出版控，不搬進 `project.yml` 這個值就從版控消失了。

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 1.1 | `grep -A2 'deploymentTarget' project.yml` | 顯示 `iOS: "18.0"` |
| 1.2 | `grep 'DEVELOPMENT_TEAM' project.yml` | 值為 `W5937V2WUF`，**不是空字串** |
| 1.3 | `grep 'SWIFT_VERSION' project.yml` | 值為 `"5.0"` |
| 1.4 | `xcodegen generate && grep -c 'W5937V2WUF' DaysCam.xcodeproj/project.pbxproj` | 結果 > 0（證明 Team ID 有被 xcodegen 寫進去，不會被覆蓋掉） |
| 1.5 | `git ls-files \| grep xcodeproj` | **無結果**（已移出版控） |
| 1.6 | `grep 'xcodeproj' .gitignore` | 有結果 |
| 1.7 | `grep -c 'xcodegen' README.md` | 結果 > 0 |
| 1.8 | `plutil -p DaysCam/Info.plist \| grep Usage` | 恰好兩筆：`NSCameraUsageDescription`、`NSPhotoLibraryAddUsageDescription` |
| 1.9 | `plutil -p DaysCam/Info.plist \| grep NSPhotoLibraryUsageDescription` | **無結果** |
| 1.10 | `ls DaysCam/Models DaysCam/Services DaysCam/Views DaysCamTests` | 四個資料夾都存在 |
| 1.11 | `xcodegen generate && xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -destination 'platform=iOS Simulator,name=iPhone 16' build` | 編譯成功，exit code 0 |
| 1.12 | `xcodebuild ... test` | 測試 target 可執行（此時 0 個測試亦可），exit code 0 |
| 1.13 | `grep -c 'case ' DaysCam/Models/TemplateID.swift` | 恰好 **5**（不是 6，`nameAndDayCount` 已被 `showName` 取代） |
| 1.14 | `grep -c 'case ' DaysCam/Models/OverlayPosition.swift` | 恰好 9 |
| 1.15 | `grep -c 'case ' DaysCam/Models/ThemeID.swift` | 恰好 5 |
| 1.16 | `grep -rn '!' DaysCam/Models/ \| grep -v '!=' \| grep -v '//'` | 無 force-unwrap（`CLAUDE.md` 規定） |

**驗收 — B. 需人類實機**：無。

**依賴**：無

---

## TASK-02：DayCountCalculator（天數計算核心）★ 最高優先

**目標**
實作天數計算的唯一真實來源，用 XCTest 把 PRD §7.1 的所有邊界鎖住。這是全專案最容易出錯的邏輯，必須先於任何 UI 完成。

**範圍**

- `Services/DayCountCalculator.swift`，**時間來源必須可注入**：
  ```swift
  struct DayCountCalculator {
      init(calendar: Calendar = .current, now: @escaping () -> Date = { Date() })
      /// Calendar day difference, ignoring time of day. Can be negative.
      func rawDayDifference(from startDate: DateComponents) -> Int
      /// Day count after applying the counting rule. Can be zero or negative.
      func dayCount(from startDate: DateComponents, rule: CountingRule) -> Int
      /// Calendar year/month/day breakdown for the unit-converted template.
      func calendarBreakdown(from startDate: DateComponents) -> (years: Int, months: Int, days: Int)
      /// Today's date in this calculator's calendar and time zone.
      func currentDateComponents() -> DateComponents
  }
  ```
- 計算規則（PRD §3.3、§6.3）：
  - `rawDayDifference` = `calendar.dateComponents([.day], from: startOfDay(起始日), to: startOfDay(now())).day`
  - `dayOne` → `raw + 1`；`dayZero` → `raw`
  - `calendarBreakdown` = `calendar.dateComponents([.year,.month,.day], from: startOfDay(起始日), to: startOfDay(now()))`，**不加 1**
  - `currentDateComponents` = `now()` 在當地時區的 y/m/d（供 `dateOnly` 模板與「新設定檔起始日預設今天」使用）
- **`#if DEBUG` 時間覆寫**：讀環境變數 `DAYSCAM_FAKE_TODAY`（格式 `yyyy-MM-dd`），有值時 `now()` 回傳當地該日中午 12:00。Release build **不得**包含此程式碼。
- **禁止**讀取任何 EXIF 或檔案時間（PRD §6.1）

> **為什麼要加 `DAYSCAM_FAKE_TODAY`**：沒有它，任何「隔天疊字要變成第 2 天」的驗證都得改主機或裝置時鐘，QA teammate 做不到，會把大量條目推到人類那邊。有了它，TASK-08/11/12/13/14 的多數條目都能在模擬器上自動跑。

**驗收 — A. QA 可自動跑**

執行 `xcodebuild ... test -only-testing:DaysCamTests/DayCountCalculatorTests`。所有案例固定 `Calendar(identifier: .gregorian)`、`timeZone = Asia/Taipei`。**下表數值皆已用 Swift 6.0.3 實測確認。**

| # | 情境 | 起始日 | 注入的 now | `raw` | `dayOne` | `dayZero` |
|---|---|---|---|---|---|---|
| 2.1 | 同一天 | 2026-01-01 | 2026-01-01 12:00 | 0 | **1** | **0** |
| 2.2 | 基本 | 2026-01-01 | 2026-01-10 08:00 | 9 | **10** | **9** |
| 2.3 | 跨月 | 2026-01-31 | 2026-02-01 00:30 | 1 | **2** | **1** |
| 2.4 | 跨年 | 2025-12-31 | 2026-01-01 00:30 | 1 | **2** | **1** |
| 2.5 | 閏年含 2/29 | 2024-02-28 | 2024-03-01 10:00 | 2 | **3** | **2** |
| 2.6 | 非閏年同區間 | 2026-02-28 | 2026-03-01 10:00 | 1 | **2** | **1** |
| 2.7 | 起始日為 2/29 | 2024-02-29 | 2024-03-01 10:00 | 1 | **2** | **1** |
| 2.8 | 整年（平年） | 2025-01-01 | 2026-01-01 10:00 | 365 | **366** | **365** |
| 2.9 | 整年（閏年） | 2024-01-01 | 2025-01-01 10:00 | 366 | **367** | **366** |
| 2.10 | 午夜前一秒 | 2026-01-01 | 2026-01-01 23:59:59 | 0 | **1** | **0** |
| 2.11 | 午夜後一秒 | 2026-01-01 | 2026-01-02 00:00:01 | 1 | **2** | **1** |
| 2.12 | 起始日在未來 | 2026-12-01 | 2026-09-19 10:00 | **-73** | **-72** | **-73** |
| 2.13 | 長期 | 2025-01-15 | 2026-03-20 10:00 | 429 | **430** | **429** |
| 2.14 | 預設設定檔次日 | 2026-01-10 | 2026-01-11 10:00 | 1 | **2** | **1** |
| 2.15 | 預設設定檔一個月後 | 2026-01-10 | 2026-02-10 10:00 | 31 | **32** | **31** |

`calendarBreakdown`：

| # | 起始日 | 注入的 now | 預期 (years, months, days) |
|---|---|---|---|
| 2.16 | 2025-01-15 | 2026-03-20 | **(1, 2, 5)** |
| 2.17 | 2026-01-01 | 2026-01-01 | **(0, 0, 0)** |
| 2.18 | 2026-01-01 | 2026-01-10 | **(0, 0, 9)** |
| 2.19 | 2025-01-01 | 2026-01-01 | **(1, 0, 0)** |
| 2.20 | 2025-01-01 | 2026-03-01 | **(1, 2, 0)** |
| 2.21 | 2024-02-29 | 2025-02-28 | **(1, 0, 0)** ← 見下方註記 |
| 2.22 | 2024-02-29 | 2025-03-01 | **(1, 0, 1)** |

> **2.21 特別註記**：Foundation 把不存在的 2025-02-29 夾到 2025-02-28，並視為**滿一年**，回傳 `(1, 0, 0)`。這個值**已用 Swift 6.0.3 實測確認**。規格重審的決策清單曾寫成 `(0, 11, 30)`，那是錯的；若照那個數字寫測試會直接失敗。本條的用途是**鎖住 Foundation 的原生行為**，避免未來 OS 版本改變時無聲失效。

`currentDateComponents` 與時區：

| # | 步驟 | 預期結果 |
|---|---|---|
| 2.23 | 注入 now = `2026-01-10 08:00`（Asia/Taipei） | `(2026, 1, 10)` |
| 2.24 | 注入 now = `2026-01-10 23:59:59`（Asia/Taipei） | `(2026, 1, 10)`（時分秒不影響） |
| 2.25 | 起始日 2026-01-01、now = UTC `2026-01-09T20:00:00Z`，分別以 `Asia/Taipei`（當地 01-10 04:00）與 `America/New_York`（當地 01-09 15:00）建立 calculator | Taipei → `dayOne` 為 **10**、`currentDateComponents` 為 01-10；New_York → `dayOne` 為 **9**、`currentDateComponents` 為 01-09 |

靜態檢查：

| # | 步驟 | 預期結果 |
|---|---|---|
| 2.26 | `grep -rni "exif\|DateTimeOriginal\|creationDate\|fileCreation" DaysCam/` | **無結果**（PRD §6.1 硬約束） |
| 2.27 | `grep -rn "Date()" DaysCamTests/` | **無結果**（測試不得依賴真實時間） |
| 2.28 | 檢視 `DAYSCAM_FAKE_TODAY` 的實作 | 整段包在 `#if DEBUG` 內 |

**驗收 — B. 需人類實機**：無。

**依賴**：TASK-01

---

## TASK-03：CameraProfile 與 JSON 持久化

**目標**
實作設定檔資料模型與持久化層，含首次啟動種預設設定檔，以及 PRD §4.1 兩條不變條件的強制驗證。

**範圍**

- `Models/CameraProfile.swift`：依 PRD §4.1。`startDate` 為 `DateComponents`（**非** optional、**非** `Date`）；`showName: Bool` 預設 `false`；`templateID` 預設 `.dayCount`
- `Services/ProfileStore.swift`：
  - 讀寫 `Application Support/DaysCam/profiles.json`，**原子寫入**
  - CRUD：`load()`、`add(_:)`、`update(_:)`、`delete(id:)`
  - **首次啟動種預設值**：檔案不存在時建立**一個**設定檔（PRD §4.3 的表），`lastUsedProfileID` 指向它。「今天」必須來自可注入的時間來源
  - **強制不變條件 1**（名稱 trim 後 1–20 字）與**不變條件 2**（`startDate` 良構性）
  - 數量上限 20；至少保留 1 個（`delete` 在只剩 1 筆時回傳錯誤）
  - 損毀處理：改名為 `profiles.json.corrupt-{unix timestamp}`，**重新種預設設定檔**，曝露 `didRecoverFromCorruption: Bool`
- `lastUsedProfileID: UUID?` 存 `UserDefaults`；指向不存在的 id 時回傳清單第一筆的 id

**驗收 — A. QA 可自動跑**

`xcodebuild ... test -only-testing:DaysCamTests/ProfileStoreTests`。測試須用暫時目錄與注入的時間來源。

**A-1 首次啟動種預設值**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.1 | 新建 store（目錄空、注入 now = 2026-01-10）→ `load()` | 回傳**恰好 1 筆** |
| 3.2 | 檢查該筆所有欄位 | `name == "預設"`、`startDate == (2026,1,10)`、`countingRule == .dayOne`、`templateID == .dayCount`、`showName == false`、`position == .bottomTrailing`、`themeID == .classicWhite` |
| 3.3 | 讀 `lastUsedProfileID` | 等於該筆的 `id` |
| 3.4 | 建立新 store 指向同一目錄（注入 now = 2026-02-20）→ `load()` | 仍是原本那筆，`startDate` **仍是 (2026,1,10)**（只在檔案不存在時種一次） |

**A-2 CRUD**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.5 | `add` 一筆（`name: "小寶"`、`startDate: 2025-01-15`、`dayOne`）→ 新 store → `load()` | 回傳 2 筆；新那筆所有欄位與寫入時完全相同 |
| 3.6 | `update` 把 `name` 改為 `"小寶貝"` → `load()` | `name == "小寶貝"`，`id` 不變，`updatedAt > createdAt` |
| 3.7 | `delete` 其中一筆 → `load()` | 該筆消失，其餘不變 |
| 3.8 | `add` 到總數 20 筆 | 全部成功 |
| 3.9 | 再 `add` 第 21 筆 | 回傳錯誤（非 crash、非靜默忽略），`load()` 仍 20 筆 |
| 3.10 | 刪到只剩 1 筆後再 `delete` 那筆 | 回傳錯誤，**不刪除**，`load()` 仍 1 筆 |
| 3.11 | `grep -n "startDate" DaysCam/Models/CameraProfile.swift` | 型別為 `DateComponents`，**不是 `Date`**、**不是 optional** |
| 3.12 | `grep -n "showName" DaysCam/Models/CameraProfile.swift` | 存在且為 `Bool` |

**A-3 不變條件 1（名稱）**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.13 | `add` 一筆 `name: ""` | 回傳錯誤（必填） |
| 3.14 | `add` 一筆 `name: "   "`（純空白） | 回傳錯誤（trim 後為空） |
| 3.15 | `add` 一筆 `name` 為 21 字元 | 回傳錯誤 |
| 3.16 | `add` 一筆 `name` 為 20 字元 | 成功 |

**A-4 不變條件 2（`startDate` 良構性）— 寫入路徑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.17 | `add` 一筆 `startDate` 含 `hour: 13, minute: 30, second: 45` | 三者被**剝除**後寫入；`load()` 回來皆為 nil，年月日不變 |
| 3.18 | `add` 一筆 `startDate` 帶 `timeZone = TimeZone(identifier: "Asia/Taipei")` | 被**剝除**後寫入；`load()` 回來 `startDate.timeZone == nil` |
| 3.19 | `add` 一筆 `startDate` 帶 `calendar = Calendar(identifier: .buddhist)` | 被**剝除**後寫入；`load()` 回來 `startDate.calendar == nil` |
| 3.20 | `add` 一筆 `startDate` 為 `month: 13` | 回傳錯誤，不寫入 |
| 3.21 | `add` 一筆 `startDate` 為 `2026-02-30` | 回傳錯誤，不寫入 |
| 3.22 | `add` 一筆 `startDate` 只有 `year`、`month`（缺 `day`） | 回傳錯誤，不寫入 |

**A-5 不變條件 2 — 讀取路徑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.23 | 手動塞一筆 `startDate` 含時分秒 → `load()` | 時分秒被剝除，年月日正確，不崩潰 |
| 3.24 | 手動塞一筆 `name` 為空字串 → `load()` | 該筆被**丟棄**，其餘正常，不崩潰 |
| 3.25 | 手動塞一筆 `startDate` 為 `month: 13` → `load()` | 該筆被**丟棄**，其餘正常，不崩潰 |
| 3.26 | 手動塞一筆 `startDate` 帶 `calendar: .buddhist` → `load()` | `calendar` 被剝除；該筆算出的天數與同年月日的乾淨設定檔**完全相同**，**不得**出現差 543 年的日期 |
| 3.27 | **（最關鍵）** 手動塞兩筆設定檔 P1、P2，`startDate` 年月日**都是 2026-01-15**、皆 `dayOne`，但 P2 額外帶 `timeZone: TimeZone(identifier: "Asia/Taipei")`。calculator 的時區設為 **`America/New_York`**、注入 now = `2026-01-20 12:00` → `load()` 後分別渲染 | P2 的 `timeZone` 被剝除，**P1 與 P2 都輸出 `第 6 天`**（raw 皆為 5）。<br>**若剝除未實作，P2 會輸出 `第 7 天`**（raw 為 6）——夾帶的台北時區把起始日解讀成紐約當地的 2026-01-14，多算一天 |

> **3.27 的時區組合不可自行更換**：夾帶的 `timeZone` **不是**每次都會造成差異，只有當**夾帶的 offset 大於裝置 offset** 時才會把起始日推回前一天。本條指定的組合（夾帶 `Asia/Taipei` +8、裝置 `America/New_York` −5）滿足條件；若改成夾帶 `UTC`（+0）而裝置在台北（+8），**即使剝除邏輯完全沒實作也會通過**。
>
> 另外注意：PRD §6.3 的 `startOfDay` 正規化**救不回**這種污染，日期已整個位移一天。所以必須在持久化層驗，不能寄望計算層。

**A-6 損毀與狀態還原**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.28 | 把 `profiles.json` 覆寫成 `"這不是 JSON"` → 新 store（注入 now = 2026-03-05）→ `load()` | 回傳**重新種下的 1 筆預設設定檔**（`startDate == (2026,3,5)`），`didRecoverFromCorruption == true`，同目錄存在 `profiles.json.corrupt-*` 且內容為 `"這不是 JSON"` |
| 3.29 | 設 `lastUsedProfileID` → 重新讀取 | 回傳同一個 id |
| 3.30 | 把 `lastUsedProfileID` 改成不存在的 UUID → 讀取 | 回傳**清單第一筆**的 id（非 nil、不崩潰） |
| 3.31 | `delete` 掉 `lastUsedProfileID` 指向的設定檔 → 讀取 | 回傳清單中仍存在的某一筆 id |

**A-7 靜態檢查**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.32 | `grep -rnE "startDate[?!]?\.date\b" DaysCam/` | **無結果**。禁止使用 `DateComponents.date`——它會採用元件自帶的 `calendar`（佛曆造成 543 年偏移），且 `calendar` 為 nil 時一律回傳 nil。一律走注入的 `Calendar` |

**驗收 — B. 需人類實機**：無。

**依賴**：TASK-01

---

## TASK-04：TemplateRenderer（5 模板 × showName）

**目標**
把「設定檔 ＋ 當下時間」渲染成疊印字串，涵蓋 PRD §3.2 的 5 種模板與 `showName` 開關。

**範圍**

- `Services/TemplateRenderer.swift`
  ```swift
  /// Renders the overlay text for a profile as of `capturedAt`.
  ///
  /// `capturedAt` is the moment the photo was taken. MVP always passes the shutter
  /// instant; a future import feature can pass a date obtained elsewhere without
  /// changing this function. Never read the system clock inside this type.
  func render(profile: CameraProfile,
              capturedAt: Date,
              calendar: Calendar = .current) -> String
  ```
- **禁止在 `TemplateRenderer` 內呼叫 `Date()`**（PRD §6.5 / FR-2.11）。內部一律以 `DayCountCalculator(calendar: calendar, now: { capturedAt })` 取得計算結果，讓 `capturedAt` 成為**唯一**的時間來源
- `templateID == .dateOnly` 時走**獨立分支**：以 `capturedAt` 換算出的當地年月日格式化，**不得**讀取 `profile.startDate`、不得呼叫 `dayCount(...)`（PRD FR-2.10）
- `showName` 開啟時前置 `"\(name) "`（一個半形空格）；關閉時輸出不得有開頭空白
- 起始日在未來（`raw < 0`）時，除 `dateOnly` 外所有模板回傳 `"尚未開始"`（PRD §7.2）
- 附 XCTest

**驗收 — A. QA 可自動跑**

基準：`name: "小寶"`、`startDate: 2025-01-15`、`dayOne`、`capturedAt` = `2026-03-20 10:00`（Asia/Taipei）。此時 `n = 430`、breakdown `(1,2,5)`。

> 下表凡寫「注入 now」處，一律指**傳入的 `capturedAt` 參數**，不是系統時鐘。

**A-1 5 種模板（`showName` 關閉）**

| # | `templateID` | 預期輸出（逐字元相符） |
|---|---|---|
| 4.1 | `dayCount` | `第 430 天` |
| 4.2 | `unitConverted` | `1 年 2 個月 5 天` |
| 4.3 | `dateOnly` | `2026.03.20` |
| 4.4 | `dateAndDayCount` | `2026.03.20　第 430 天`（中間為全形空白 U+3000） |
| 4.5 | `weekCount` | `第 61 週又 3 天`（430 = 61×7 + 3） |

**A-2 `showName` 開啟（同一基準）**

| # | `templateID` | 預期輸出 |
|---|---|---|
| 4.6 | `dayCount` | `小寶 第 430 天` |
| 4.7 | `unitConverted` | `小寶 1 年 2 個月 5 天` |
| 4.8 | `dateOnly` | `小寶 2026.03.20` |
| 4.9 | `dateAndDayCount` | `小寶 2026.03.20　第 430 天` |
| 4.10 | `weekCount` | `小寶 第 61 週又 3 天` |
| 4.11 | 承 4.1（`showName` 關閉） | 輸出**不得**以空白開頭；以 `XCTAssertEqual(out, "第 430 天")` 逐字元比對 |

**A-3 單位轉換的省略規則**

| # | 情境（`dayOne`） | 預期輸出 |
|---|---|---|
| 4.12 | start 2026-01-01, now 2026-01-01 → (0,0,0) | `0 天` |
| 4.13 | start 2026-01-01, now 2026-01-10 → (0,0,9) | `9 天` |
| 4.14 | start 2025-01-01, now 2026-01-01 → (1,0,0) | `1 年` |
| 4.15 | start 2025-01-01, now 2026-03-01 → (1,2,0) | `1 年 2 個月` |

**A-4 `dateOnly` 永不讀 `startDate`（PRD FR-2.10）**

| # | 步驟 | 預期輸出 |
|---|---|---|
| 4.16 | 建立設定檔 A（`dayCount` 模板、start 2026-01-10、`dayOne`）與 B（`dateOnly` 模板、start 也是 2026-01-10）。注入 now = 2026-01-10 → 各渲染一次；再注入 now = 2026-01-11 → 各渲染一次 | now=01-10：A → `第 1 天`，B → `2026.01.10`<br>now=01-11：A → `第 2 天`（**正確**，天數本來就遞增），B → **`2026.01.11`**（**不得**變成 `第 2 天`） |
| 4.17 | `dateOnly` 設定檔，`startDate` 設成 **1999-01-01**（與今天無關的值），注入 now = 2026-03-20 | 輸出 `2026.03.20`。`startDate` 完全不影響 `dateOnly` 的輸出 |
| 4.18 | `dateOnly` 設定檔，起始日在未來（start 2026-12-01、now 2026-09-19） | 輸出 `2026.09.19`，**不是** `尚未開始` |
| 4.19 | 檢視 `.dateOnly` 分支的實作 | 該分支內**沒有**用到 `profile.startDate`、`countingRule`、`dayCount(...)`；只由 `capturedAt` 換算出年月日並格式化 |

**A-4b 拍攝時刻是顯式參數（PRD §6.5 的接縫，Phase 4 匯入功能的前提）**

| # | 步驟 | 預期結果 |
|---|---|---|
| 4.19a | **同一個** `dateOnly` 設定檔，以 `capturedAt = 2019-07-04 09:00` 呼叫一次，再以 `capturedAt = 2026-03-20 10:00` 呼叫一次 | 依序得到 **`2019.07.04`** 與 **`2026.03.20`**。證明 `dateOnly` 完全以傳入的參考日期為準，可餵入任意過去日期——這是日後匯入舊照片的前提 |
| 4.19b | **同一個**天數設定檔（start 2025-01-15、`dayOne`），以 `capturedAt = 2025-01-16` 與 `capturedAt = 2026-03-20` 各呼叫一次 | 依序得到 **`第 2 天`** 與 **`第 430 天`**。天數同樣完全由 `capturedAt` 決定 |
| 4.19c | `grep -rn "Date()" DaysCam/Services/TemplateRenderer.swift` | **無結果**。渲染層不得自行讀取系統時鐘（PRD FR-2.11 / §6.5.3） |
| 4.19d | 檢視 `render` 的簽章 | 含 `capturedAt: Date` 參數。**若有人把它移除並改回內部讀時鐘，4.19a/4.19b 會立刻失敗**——這兩條就是這個接縫的防回歸測試 |

**A-5 週數模板**（規則：`q = n/7`、`r = n%7`；`r == 0` 印 `第 q 週`，否則 `第 q 週又 r 天`）

| # | `n` | 預期輸出 |
|---|---|---|
| 4.20 | 0（`dayZero` 同一天） | `第 0 週` |
| 4.21 | 1 | `第 0 週又 1 天` |
| 4.22 | 7 | `第 1 週` |
| 4.23 | 8 | `第 1 週又 1 天` |
| 4.24 | 14 | `第 2 週` |
| 4.25 | 430 | `第 61 週又 3 天` |

**A-6 `dayZero` 與未來日期**

| # | 情境 | 預期輸出 |
|---|---|---|
| 4.26 | start 2026-01-01, now 2026-01-01, **dayZero**, `dayCount` | `第 0 天` |
| 4.27 | start 2026-12-01, now 2026-09-19，**除 `dateOnly` 外的 4 種模板全測** | 4 種都回傳 `尚未開始` |
| 4.28 | 承 4.27，`showName` 開啟 | 輸出為 `小寶 尚未開始` |

**A-7 時區**

| # | 步驟 | 預期輸出 |
|---|---|---|
| 4.29 | `dateOnly` 設定檔，以 `Asia/Taipei` 與 `America/New_York` 注入同一 UTC 時間 `2026-01-09T20:00:00Z` | Taipei → `2026.01.10`；New_York → `2026.01.09` |

**驗收 — B. 需人類實機**：無。

**依賴**：TASK-01、TASK-02

---

## TASK-05：OverlayTheme（5 組主題）

**目標**
把 PRD §3.4 的 5 組主題定義成**預覽層與烘焙層共用**的資料結構，避免兩邊長得不一樣。

**範圍**

- `Models/OverlayTheme.swift`：`struct OverlayTheme` 含 `id`、`displayName`、`fontDesign`、`fontWeight`、`textColor`、`decoration`（enum：`.shadow(offset:blur:opacity:color:)` / `.backgroundBox(color:opacity:cornerRadius:insets:)` / `.stroke(color:width:)`，可組合）
- `static let all: [OverlayTheme]`，順序固定為 PRD §3.4 表格順序
- `func baseFontSize(forShortEdge: CGFloat) -> CGFloat` 回傳 `shortEdge * 0.055`
- `func margin(forShortEdge: CGFloat) -> CGFloat` 回傳 `shortEdge * 0.04`
- **字級自動縮小**的共用函式（PRD FR-4.8）：給定可用寬度與文字，回傳實際字級，下限為基準的 60%
- 顏色以 sRGB 數值定義，**不得**用 Asset Catalog 動態色（疊字不得跟隨 Light/Dark Mode 改變）

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 5.1 | `OverlayTheme.all.count` | 恰好 **5** |
| 5.2 | `OverlayTheme.all.map(\.id)` | 依序 `[.classicWhite, .retroOrange, .filmStrip, .minimalDark, .softPink]` |
| 5.3 | 每個 theme 的 `decoration` | 5 組全部至少有一種 decoration（PRD FR-4.6） |
| 5.4 | `classicWhite.textColor` 的 sRGB 分量 | `(1.0, 1.0, 1.0, 1.0)` |
| 5.5 | `retroOrange.textColor` 的 sRGB 分量 | 對應 `#FF9500` 即 `(1.0, 0.584, 0.0, 1.0)`，容差 ±0.01 |
| 5.6 | `baseFontSize(forShortEdge: 3024)` | `166.32`，容差 ±0.01 |
| 5.7 | `margin(forShortEdge: 3024)` | `120.96`，容差 ±0.01 |
| 5.8 | 縮小函式：給一段長到超出可用寬度的文字 | 回傳字級 < 基準，且 **>= 基準 × 0.6** |
| 5.9 | 縮小函式：給一段很短的文字 | 回傳**恰好**等於基準字級（短文字不縮） |
| 5.10 | `grep -rn 'Color("\|UIColor(named' DaysCam/Models/OverlayTheme.swift` | 無結果 |
| 5.11 | `grep -rn '\.custom(\|UIFont(name:' DaysCam/` | 無結果（PRD FR-4.10：只用系統字體） |

**驗收 — B. 需人類實機**：無。

**依賴**：TASK-01

---

## TASK-06：設定檔清單與編輯頁

**目標**
實作 PRD S-2 / S-3：設定檔的新增、編輯、刪除、選擇。

**範圍**

- `Views/ProfileListView.swift`、`Views/ProfileEditView.swift`
- 清單每列：名稱 ＋ 選取標記
- 編輯頁欄位（**只有邏輯層**，PRD FR-3.5）：名稱（`TextField`，1–20 字）、起始日（`DatePicker`，`in: ...Date()`）、起算規則（segmented `Picker`）
- **模板為 `dateOnly` 時隱藏起始日與起算規則**（PRD FR-3.7）
- 即時預覽「今天會顯示為：…」
- 新增預設值依 PRD FR-1.9；建立後自動切換到新設定檔（FR-1.10）
- 刪除二次確認；只剩 1 個時刪除 disabled 並說明（FR-1.8）
- 達 20 筆時新增 disabled 並說明

**驗收 — A. QA 可自動跑**（iPhone 16 模擬器，以 `DAYSCAM_FAKE_TODAY=2026-01-10` 啟動）

| # | 步驟 | 預期結果 |
|---|---|---|
| 6.1 | 全新安裝後開啟設定檔清單 | 恰好 **1 列**，名稱「預設」，帶選取標記 |
| 6.2 | 點進「預設」的編輯頁 | 名稱「預設」；起始日 2026-01-10；規則「當天算第 1 天」；預覽顯示「今天會顯示為：第 1 天」 |
| 6.3 | 點「＋」新增 | 預設：名稱空白、起始日 2026-01-10、規則「當天算第 1 天」 |
| 6.4 | 名稱留空直接儲存 | 「儲存」為 disabled（名稱必填） |
| 6.5 | 名稱輸入純空白「   」 | 「儲存」仍 disabled |
| 6.6 | 名稱貼上 21 字（`一二三四五六七八九十一二三四五六七八九十壹`） | 輸入框只保留前 20 字，第 21 字進不去 |
| 6.7 | 名稱「小寶」、起始日改 2026-01-01、規則「當天算第 1 天」→ 儲存 | 回清單出現「小寶」，且**選取標記自動落在「小寶」**（FR-1.10） |
| 6.8 | 承 6.7 回編輯頁 | 預覽顯示「今天會顯示為：第 10 天」 |
| 6.9 | 承 6.8 把規則切到「當天算第 0 天」（不儲存） | 預覽**即時**變成「今天會顯示為：第 9 天」 |
| 6.10 | 打開起始日 `DatePicker`，試選 2026-01-11 | 明天以後不可選（灰階／不可點） |
| 6.11 | 把某設定檔的模板改成「純日期」（在 TASK-11 的面板改），再回編輯頁 | 起始日與起算規則兩個欄位**不顯示**；預覽顯示「今天會顯示為：2026.01.10」 |
| 6.12 | 承 6.11 把模板改回「純天數」，回編輯頁 | 兩個欄位**重新出現** |
| 6.13 | 對某列左滑 → 刪除 | 出現確認對話框；點「取消」該列仍在 |
| 6.14 | 重複 6.13 點「刪除」 | 該列消失；重啟 App 仍不存在 |
| 6.15 | 刪到只剩 1 個，再嘗試刪除 | 刪除 disabled（左滑無刪除鈕或按下無效），顯示「至少需要保留一個設定檔」，清單仍 1 列 |
| 6.16 | 刪除**非選取中**的設定檔 | 選取標記不變 |
| 6.17 | 刪除**選取中**的設定檔（尚有其他筆） | 選取標記自動移到仍存在的某筆，不崩潰 |
| 6.18 | 建立到 20 個 | 「＋」變 disabled 並顯示說明（提到上限 20） |

**驗收 — B. 需人類實機**：無。

**依賴**：TASK-03、TASK-04

---

## TASK-07：相機權限與 AVFoundation 觀景窗

**目標**
實作 PRD S-1 觀景窗與 S-5 權限引導畫面。**不含**疊字與拍照。

**範圍**

- `Services/CameraService.swift`：包裝 `AVCaptureSession`、`AVCaptureDeviceInput`、`AVCapturePhotoOutput`（output 先建好不使用）
- `Views/CameraPreviewView.swift`：`UIViewRepresentable` 包 `AVCaptureVideoPreviewLayer`
- 拍攝與預覽比例固定 4:3
- 前／後鏡頭切換
- 權限狀態機（PRD §2.3）；監聽 `AVCaptureSessionWasInterrupted` / `InterruptionEnded`；監聽 `willEnterForeground` 重檢權限
- 模擬器 fallback：`#if targetEnvironment(simulator)` 顯示純色佔位背景，快門 disabled 並標示「模擬器不支援拍照」
- session 的 start/stop 必須在背景 queue，不得阻塞主執行緒

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 7.1 | 模擬器執行並進入相機畫面 | 顯示純色佔位背景，快門 disabled，有「模擬器不支援拍照」字樣，不崩潰 |
| 7.2 | 模擬器上量測觀景窗區域的像素長寬比 | 4:3，誤差 < 2% |
| 7.3 | `grep -rn "startRunning\|stopRunning" DaysCam/Services/CameraService.swift` | 兩者都不在主執行緒直接呼叫（包在背景 queue 內） |
| 7.4 | 模擬器上反覆進出相機畫面 10 次 | 不崩潰，console 無 `AVCaptureSession` error |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 7.5 | 實機首次安裝後進入相機畫面 | 跳出相機權限彈窗，文案與 `Info.plist` 的 `NSCameraUsageDescription` 一字不差 |
| 7.6 | 點「允許」 | 觀景窗 2 秒內顯示即時畫面 |
| 7.7 | 重裝後點「不允許」 | 觀景窗區域變權限引導畫面：標題「需要相機權限」、有「前往設定」、快門 disabled |
| 7.8 | 承 7.7 點「前往設定」 | 跳到 iOS 設定的 DaysCam 頁 |
| 7.9 | 承 7.8 開啟相機權限 → 直接切回 App（**不殺 App**） | 引導畫面自動消失，觀景窗自動開始顯示 |
| 7.10 | 點前／後鏡頭切換 | 1 秒內切換，畫面不卡死 |
| 7.11 | 快速切換前後鏡頭 10 次 | 不崩潰，console 無 error |
| 7.12 | 停在相機畫面時接聽來電，結束後回 App | 觀景窗自動恢復，不需重啟 |

**依賴**：TASK-01

---

## TASK-08：觀景窗即時疊字

**目標**
把 TemplateRenderer 的輸出，用 TASK-05 的主題與 9 宮格定位即時疊在觀景窗上（SwiftUI 圖層，非烘焙）。

**範圍**

- `Views/OverlayTextView.swift`：吃**已渲染好的文字** ＋ `OverlayTheme` ＋ `OverlayPosition`，輸出 SwiftUI view（不直接吃 `CameraProfile`，文字由上層決定）
- 對齊規則（PRD FR-4.3）：邊距 = 短邊 × 4%；左側格靠左、右側格靠右、中間格置中
- 字級 = 短邊 × 5.5%，過長時依 TASK-05 的共用函式縮小（下限 60%）
- `allowsHitTesting(false)`

**驗收 — A. QA 可自動跑**（模擬器，`DAYSCAM_FAKE_TODAY` 控制日期）

| # | 步驟 | 預期結果 |
|---|---|---|
| 8.1 | 全新安裝，`DAYSCAM_FAKE_TODAY=2026-01-10` | 觀景窗顯示 `第 1 天`，右下角，白字黑陰影 |
| 8.2 | 同上但 `DAYSCAM_FAKE_TODAY=2026-01-11` | 顯示 `第 2 天`（天數遞增，**正確**） |
| 8.3 | 把「預設」的模板改成「純日期」，`DAYSCAM_FAKE_TODAY=2026-01-11` | 顯示 **`2026.01.11`**，**不是** `第 2 天` |
| 8.4 | 開啟 `showName`（名稱「預設」），模板「純天數」，日期 2026-01-10 | 顯示 `預設 第 1 天` |
| 8.5 | 關閉 `showName` | 顯示 `第 1 天`，開頭無多餘空白 |
| 8.6 | 位置設 `topLeading` | 文字在左上，左／上邊界距離皆約短邊 4%（截圖量測，誤差 < 1%） |
| 8.7 | 位置設 `bottomTrailing` | 文字在右下，右／下邊界距離約短邊 4% |
| 8.8 | 位置設 `middleCenter` | 水平垂直皆置中 |
| 8.9 | 依序套用 9 個位置 | 9 個位置文字都完整顯示，**無任何一個被裁切** |
| 8.10 | 5 組主題各套一次 | 字體、顏色、襯底肉眼可區分，無任何一組是純文字無襯底 |
| 8.11 | 名稱 20 字 ＋ `showName` 開啟 ＋ 模板「日期＋天數」＋ 位置 `bottomTrailing` | 文字**不超出觀景窗邊界**；字級縮小但不低於基準 60%；不換行、不截斷 |
| 8.12 | 點擊疊字所在位置 | 觸控穿透到底下（疊字不攔截事件） |
| 8.13 | 建立第二個設定檔，位置/主題設成不同值，來回切換 | 每個設定檔各自保留自己的位置與主題，互不覆蓋 |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 8.14 | 主題 `classicWhite`，相機對著**純白牆面** | 文字仍清晰可辨（黑色陰影襯底發揮作用） |
| 8.15 | 主題 `minimalDark`，相機對著**全黑畫面** | 文字仍清晰可辨（白色底框襯底發揮作用） |

**依賴**：TASK-04、TASK-05、TASK-07

---

## TASK-09：OverlayRenderer（疊字烘焙）

**目標**
實作 PRD §6.2：把疊字繪製進 `UIImage` 像素。純函式，可脫離相機測試。

**範圍**

- `Services/OverlayRenderer.swift`
  ```swift
  /// Bakes already-rendered text into the pixels of an image.
  ///
  /// Deliberately agnostic about where the image came from: a live capture today,
  /// a file loaded from disk tomorrow. It never inspects dates or metadata.
  func bake(image: UIImage, text: String, theme: OverlayTheme, position: OverlayPosition) -> UIImage?
  ```
- **介面不得綁定影像來源**（PRD §6.5.4）：只接受「影像 ＋ 已渲染好的文字 ＋ 樣式」，**不得**接受 `CameraProfile`、日期、或任何 `AVFoundation` 型別。文字怎麼算出來的與本層無關
- `UIGraphicsImageRenderer` 在**原始像素尺寸** context 繪製（`format.scale = 1`，size 為 `image.size * image.scale`）
- 先把圖正規化成 `.up` 再繪製
- 字級、邊距、縮小規則必須與 TASK-08 **共用 TASK-05 的同一組函式**
- **禁止**保留原圖、另存圖層、寫 metadata

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 9.1 | 1200×1600 **純白**圖，`classicWhite`、`bottomTrailing`、文字 `第 10 天` | 回傳非 nil，輸出尺寸 1200×1600（與輸入相同） |
| 9.2 | 承 9.1，取右下角區域（x 900–1150、y 1350–1550）像素 | 至少 1 個像素與純白 `(255,255,255)` 差距 > 30 |
| 9.3 | 承 9.1，取左上角區域（x 0–100、y 0–100）像素 | 全部仍為純白（沒畫錯位置） |
| 9.4 | 改 `topLeading` 重跑 | 左上角有非白像素，右下角全白 |
| 9.5 | 傳入 `imageOrientation == .right` 的圖 | 輸出 `imageOrientation == .up`，尺寸為旋轉後正確尺寸；`bottomTrailing` 的非白像素落在旋轉後圖的右下角（文字未被轉 90 度） |
| 9.6 | 以空字串 `""` 呼叫 | 輸出與輸入**像素完全相同**（什麼都不畫，不畫空底框） |
| 9.7 | 同一張圖連續 `bake` 100 次 | 不崩潰，記憶體峰值 < 500MB |
| 9.8 | `grep -rni "watermark\|originalImage\|CGImageDestinationAddImage" DaysCam/Services/OverlayRenderer.swift` | 無結果 |
| 9.9 | `grep -rn "UIGraphicsImageRenderer" DaysCam/Services/OverlayRenderer.swift` | 有結果（確認是像素繪製而非 view 疊加） |
| 9.10 | `grep -rnE "CameraProfile\|AVCapture\|Date\b\|DateComponents" DaysCam/Services/OverlayRenderer.swift` | **無結果**。烘焙層不得認識設定檔、相機型別或任何日期概念——它只是「影像＋文字→影像」（PRD §6.5.4） |
| 9.11 | 用一張**從檔案載入**的 `UIImage`（非相機產生）呼叫 `bake` | 與 9.1 的行為完全相同。證明介面不綁定影像來源，日後匯入舊照片時本層可直接沿用 |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 9.12 | 對 4032×3024 的圖 `bake`，在實機量測耗時 | < 500ms |

**依賴**：TASK-04、TASK-05

---

## TASK-10：拍照 → 烘焙 → 存相簿

**目標**
串起完整拍照流程，落實 PRD §6.1 與 §6.2 兩條硬約束。

**範圍**

- 快門觸發 `capturePhoto`
- delegate 取得 `UIImage` 後：**當場重新呼叫 `TemplateRenderer`**（不得用畫面快取的字串，PRD §6.4），`capturedAt` 傳入**按下快門當下的 `Date()`** → `OverlayRenderer.bake`（樣式取自目前設定檔）→ `PHPhotoLibrary` 存檔
- **本卡是整個 App 唯一產生「拍攝時刻」的地方**（PRD §6.5.5）。計算層與渲染層都只接受傳入的參數，不自行讀時鐘；日後要支援匯入舊照片時，改的是這裡而不是那兩層
- 相簿權限 `.addOnly`
- 成功後 Toast「已儲存」＋左下角縮圖，1.5 秒淡出，不跳轉
- 存檔期間快門 disabled
- 不建立自訂相簿

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 10.1 | `grep -rn "PHAccessLevel" DaysCam/` | 只出現 `.addOnly`，**無** `.readWrite` |
| 10.2 | `grep -rni "createAssetCollection\|PHAssetCollectionChangeRequest" DaysCam/` | **無結果**（不建立自訂相簿） |
| 10.3 | 單元測試：以 `capturedAt = 2026-01-10` 渲染一次文字後，改以 `capturedAt = 2026-01-11` 再走烘焙路徑 | 烘焙使用的文字為 `第 2 天`，**不是** `第 1 天`（證明當場重算，PRD §6.4） |
| 10.4 | 檢視快門 delegate 的實作 | `capturedAt` 是在此處以 `Date()` 產生並往下傳；`TemplateRenderer` 與 `OverlayRenderer` 內都**沒有** `Date()`（PRD §6.5.5） |

**驗收 — B. 需人類實機**

前置：實機裝置日期設為 **2026-01-10**，全新安裝（預設設定檔起始日即 2026-01-10）。

| # | 步驟 | 預期結果 |
|---|---|---|
| 10.5 | 允許權限後直接按快門（不做任何設定） | 1.5 秒內出現「已儲存」Toast 與左下角縮圖，**留在相機畫面**不跳轉 |
| 10.6 | 開「照片」App 看最新一張 | 右下角印著 **`第 1 天`**，白字黑陰影。**照片上沒有「預設」二字**（`showName` 預設關閉） |
| 10.7 | 對該照片點「編輯」 | 疊字無法移除、無法拖曳（是像素不是圖層） |
| 10.8 | 把該照片 AirDrop 到另一台裝置後開啟 | 疊字仍在，文字仍是 `第 1 天`（PRD G-4） |
| 10.9 | 裝置日期改 **2026-01-11**，重開 App 拍一張 | 照片印 `第 2 天`；先前那張**仍是** `第 1 天`（已烘焙不會回溯） |
| 10.10 | 把模板改「純日期」，拍一張 | 照片印 **`2026.01.11`**，**不是** `第 2 天` |
| 10.11 | 開啟 `showName`（名稱「小寶」）、模板「純天數」，拍一張 | 照片印 `小寶 第 2 天` |
| 10.12 | 設定檔起始日 2025-01-15、裝置日期 2026-03-20、模板「單位轉換」，拍照 | 照片印 `1 年 2 個月 5 天` |
| 10.13 | 同上改模板「日期＋天數」 | 照片印 `2026.03.20　第 430 天` |
| 10.14 | 起始日 2024-02-28、裝置日期 2024-03-01、`dayOne`，拍照 | 照片印 `第 3 天`（閏年 2/29 有算進去） |
| 10.15 | 起始日 2025-12-31、裝置日期 2026-01-01、`dayOne`，拍照 | 照片印 `第 2 天`（跨年） |
| 10.16 | 直向握持拍照 | 照片方向正確，文字**未被轉 90 度** |
| 10.17 | 橫向握持拍照 | 照片方向正確，文字方向正確 |
| 10.18 | 檢查照片解析度 | 與裝置原生拍照解析度相同（iPhone 16 主鏡頭 4032×3024），未被縮小 |
| 10.19 | 位置 `topLeading`、主題 `filmStrip`，拍照 | 照片左上角印字，樣式為等寬白字＋半透明黑圓角底框 |
| 10.20 | 首次拍照時拒絕相簿權限 | 錯誤提示含「這張照片尚未儲存」與「前往設定」；不崩潰 |
| 10.21 | 承 10.19 到設定開啟「加入照片」→ 回 App 再拍 | 存檔成功 |
| 10.22 | 快速連按快門 5 次 | 存下 5 張（或明確拒絕多餘觸發），不崩潰、Toast 不疊加 |
| 10.23 | 檢查「照片」App 的相簿清單 | **沒有**新增名為「DaysCam」的自訂相簿 |

**依賴**：TASK-07、TASK-09

---

## TASK-11：顯示設定面板

**目標**
實作 PRD S-4：視覺層設定的 bottom sheet，含即時預覽。**不得**放起始日與起算規則。

**範圍**

- `Views/DisplaySettingsSheet.swift`，`.sheet` + `presentationDetents`
- 四個區塊：模板（5 選 1，顯示套用後的實際文字）、**顯示名稱開關**（`Toggle`）、位置（3×3）、主題（5 選 1，樣式縮圖）
- 任何變更**即時**寫回目前設定檔並持久化
- 變更時觀景窗疊字即時更新，面板不關閉

**驗收 — A. QA 可自動跑**（模擬器，`DAYSCAM_FAKE_TODAY=2026-01-10`，設定檔起始日 2026-01-01、`dayOne`、名稱「小寶」）

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.1 | 相機畫面點設定入口 | 從底部滑出面板，觀景窗仍可見（半高 detent） |
| 11.2 | 檢視面板內容 | 只有「模板／顯示名稱／位置／主題」四區塊，**沒有**起始日、起算規則、名稱輸入框 |
| 11.3 | 模板區塊選項數 | 恰好 **5** 個，每個顯示套用後的實際文字（「純天數」那列顯示 `第 10 天`） |
| 11.4 | 位置區塊 | 3×3 共 9 個按鈕，當前選中有明顯標記 |
| 11.5 | 主題區塊選項數 | 恰好 5 個，每個顯示樣式縮圖（不是純文字清單） |
| 11.6 | 「顯示名稱」開關的預設狀態 | **關閉** |
| 11.7 | 打開「顯示名稱」 | 面板不關閉，觀景窗疊字立即變成 `小寶 第 10 天` |
| 11.8 | 關閉「顯示名稱」 | 疊字立即變回 `第 10 天`，開頭無空白 |
| 11.9 | 點模板「純日期」 | 面板不關閉，疊字立即變 `2026.01.10` |
| 11.10 | 承 11.9，模板列表中「純日期」以外的 4 種**仍可選** | 5 種模板任何時候都可自由切換（沒有模式限制） |
| 11.11 | 點位置 `topLeading` | 面板不關閉，疊字立即移到左上 |
| 11.12 | 點主題 `retroOrange` | 面板不關閉，疊字立即變橘黃色等寬字 |
| 11.13 | 關閉面板 → 殺掉 App → 重開 | 模板／顯示名稱／位置／主題四項都保持剛才選的值 |
| 11.14 | 建立第二個設定檔，四項都設成不同值，來回切換 | 每個設定檔各自保留自己的設定，互不覆蓋 |

**驗收 — B. 需人類實機**：無。

**依賴**：TASK-03、TASK-04、TASK-05、TASK-08

---

## TASK-12：首次啟動與啟動狀態還原

**目標**
實作 PRD §2.2：自動種一個設定檔、直接進相機畫面顯示「第 1 天」，以及啟動時的狀態還原。

**範圍**

- 啟動呼叫 `ProfileStore.load()`：檔案不存在則種預設設定檔（TASK-03 已實作），`lastUsedProfileID` 指向它；存在則依 `lastUsedProfileID` 套用，指向不存在時退回清單第一筆
- 啟動一律進**相機畫面**，絕不停在表單頁
- **不得**有「首次啟動建立設定檔頁」
- 相機權限在進相機畫面時才請求

**驗收 — A. QA 可自動跑**（模擬器）

| # | 步驟 | 預期結果 |
|---|---|---|
| 12.1 | 刪除模擬器 App 資料 → `DAYSCAM_FAKE_TODAY=2026-01-10` 啟動 | **直接進相機畫面**。無歡迎頁、無教學頁、無建立設定檔頁、**無任何需填寫的表單** |
| 12.2 | 承 12.1 檢視疊字 | 恰好 `第 1 天`。**沒有**名稱前綴、沒有「預設」「DaysCam」等字樣 |
| 12.3 | 承 12.1 檢查 App 容器的 `Application Support/DaysCam/profiles.json` | **恰好 1 筆**設定檔；`name` 為 `預設`、`startDate` 為 2026-01-10、`showName` 為 `false` |
| 12.4 | 承 12.1 開啟設定檔清單 | 恰好 1 列 |
| 12.5 | 改用 `DAYSCAM_FAKE_TODAY=2026-01-11` 重啟 | 疊字為 `第 2 天`（天數遞增，正確） |
| 12.6 | 承 12.5 把模板改「純日期」，再重啟 | 疊字為 **`2026.01.11`**，**不是** `第 2 天`（PRD FR-2.10） |
| 12.7 | 建立「小寶 / 2026-01-01 / 當天算第 1 天」 | 自動切到「小寶」並回相機畫面 |
| 12.8 | 承 12.7 殺掉 App 重開（`DAYSCAM_FAKE_TODAY=2026-01-11`） | 直接進相機畫面，套用「小寶」，疊字 `第 11 天` |
| 12.9 | 在清單選「預設」→ 殺掉 App 重開 | 套用「預設」 |
| 12.10 | 刪除目前選取的設定檔 → 殺掉 App 重開 | 套用清單中仍存在的某筆，不崩潰、不停在空白畫面 |
| 12.11 | 把 `UserDefaults` 的 `lastUsedProfileID` 改成不存在的 UUID → 重開 | 套用**清單第一筆**，不崩潰、不顯示錯誤 |
| 12.12 | `grep -rn "CameraProfile(" DaysCam/ \| grep -vi test` | 建立 `CameraProfile` 的位置只有兩處：`ProfileStore` 種預設值，以及使用者新增設定檔的儲存動作。**沒有**在渲染或拍照路徑上臨時建立設定檔 |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 12.13 | 實機刪除 App → 重裝 → 裝置日期 2026-01-10 → 開啟 | 直接進相機畫面，唯一彈窗是**相機權限**；**沒有**相簿權限彈窗 |
| 12.14 | 承 12.13 允許後，不做任何操作直接按快門 | 拍照成功（此時才出現相簿權限彈窗），照片印 `第 1 天`。**從安裝到拍出第一張照片全程沒填過任何表單**（PRD G-1） |

**依賴**：TASK-03、TASK-06、TASK-07

---

## TASK-13：相機畫面切換設定檔

**目標**
實作 PRD FR-1.4：不離開相機畫面就能切換設定檔。

**範圍**

- 相機畫面頂部放目前設定檔名稱按鈕，點擊展開選單（`Menu` 或橫向膠囊列）
- 選單列出所有設定檔，順序同清單
- 切換後即時更新疊字並更新 `lastUsedProfileID`
- 選單提供「管理設定檔」入口，導向 TASK-06 清單頁

**驗收 — A. QA 可自動跑**（模擬器，`DAYSCAM_FAKE_TODAY=2026-01-10`）

| # | 步驟 | 預期結果 |
|---|---|---|
| 13.1 | 全新安裝後看相機畫面頂部 | 顯示「預設」 |
| 13.2 | 點頂部展開選單 | 列出 1 項「預設」＋「管理設定檔」入口，不崩潰 |
| 13.3 | 建立「小寶 / 2026-01-01 / dayOne / 純天數」與「紀念日 / 2025-06-15 / dayZero / 純天數」 | 選單變 3 項 |
| 13.4 | 切到「小寶」 | 頂部顯示「小寶」，疊字 `第 10 天` |
| 13.5 | 切到「紀念日」 | 頂部顯示「紀念日」，疊字在 1 秒內變 `第 209 天`（2025-06-15 → 2026-01-10 相差 209 天，`dayZero` 不加 1） |
| 13.6 | 承 13.5 殺掉 App 重開 | 直接套用「紀念日」 |
| 13.7 | 點「管理設定檔」 | 導向設定檔清單頁 |

> QA 可自行複核 13.5 的 209：6 月剩 15 天 + 7 月 31 + 8 月 31 + 9 月 30 + 10 月 31 + 11 月 30 + 12 月 31 + 1 月 10 天 = 209。

**驗收 — B. 需人類實機**：無。

**依賴**：TASK-06、TASK-08

---

## TASK-14：跨午夜／回前景疊字刷新

**目標**
落實 PRD §6.4：停在相機畫面跨午夜時疊字必須更新，且烘焙時一律重算。

**範圍**

- 監聽 `NSNotification.Name.NSCalendarDayChanged` 與 `UIApplication.willEnterForegroundNotification`，兩者皆觸發重算
- 確認 TASK-10 的烘焙是當場重算而非讀畫面快取（加防回歸測試）

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 14.1 | 單元測試：注入 now = 2026-01-10 渲染一次，改注入 2026-01-11 後呼叫烘焙路徑 | 烘焙文字為 `第 2 天`（起始日 2026-01-10），不是 `第 1 天` |
| 14.2 | 同 14.1 但模板為「純日期」 | 烘焙文字為 `2026.01.11`，不是 `2026.01.10`、不是 `第 2 天` |
| 14.3 | `grep -rn "NSCalendarDayChanged\|willEnterForegroundNotification" DaysCam/` | 兩者都有被監聽 |
| 14.4 | 模擬器：以 `DAYSCAM_FAKE_TODAY=2026-01-10` 啟動 → 切背景 → 改成 `2026-01-11` 重啟 App | 疊字為 `第 2 天` |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 14.5 | 起始日 2026-01-01 / `dayOne` / 純天數。裝置日期設 **2026-01-10 23:59**，App 停在相機畫面 | 疊字 `第 10 天` |
| 14.6 | 承 14.5 等待跨午夜（或手動撥到 2026-01-11 00:01），**不要離開 App** | 疊字在 60 秒內自動變 `第 11 天` |
| 14.7 | 承 14.5 切背景 → 改日期為 2026-01-11 → 切回 App | 疊字立即為 `第 11 天` |
| 14.8 | 承 14.5（疊字仍顯示 `第 10 天`），**在畫面刷新前**把日期改 2026-01-11 後立刻按快門 | 存下的照片必須是 `第 11 天`（證明烘焙當場重算，不是沿用快取） |
| 14.9 | 同 14.8 但模板為「純日期」 | 存下的照片必須是 `2026.01.11` |

> 14.8 / 14.9 是本卡最關鍵的兩條，也最容易被漏掉。若它們 fail 但 14.6 / 14.7 pass，代表刷新做了但烘焙仍用快取，必須退回。

**依賴**：TASK-08、TASK-10

---

## TASK-15：錯誤處理與提示統一

**目標**
把 PRD §7.3 的錯誤情境收斂成一致的提示元件，避免各處自行 `print` 或靜默失敗。

**範圍**

- `Views/ToastView.swift` ＋ 集中的錯誤／提示呈現機制
- 涵蓋 PRD §7.3 全部情境
- 資料損毀提示：啟動時若 `didRecoverFromCorruption == true`，顯示一次性 alert「設定檔讀取失敗，已重設。」
- 起始日在未來時疊字顯示「尚未開始」

**驗收 — A. QA 可自動跑**（模擬器）

| # | 步驟 | 預期結果 |
|---|---|---|
| 15.1 | 把容器內 `profiles.json` 改成 `這不是 JSON` → 重開（`DAYSCAM_FAKE_TODAY=2026-03-05`） | 出現 alert「設定檔讀取失敗，已重設。」；關掉後**停在相機畫面**，疊字 `第 1 天`（重新種的預設設定檔），可立即操作；再次重開**不再**出現此 alert |
| 15.2 | 承 15.1 檢查容器 | 存在 `profiles.json.corrupt-*`，內容為 `這不是 JSON`；`profiles.json` 為重新種的 1 筆 |
| 15.3 | 設定檔起始日 2026-01-01，`DAYSCAM_FAKE_TODAY=2025-12-01` 啟動 | 疊字顯示 `尚未開始`；除「純日期」外的 4 種模板逐一切換皆顯示 `尚未開始` |
| 15.4 | 承 15.3 切到「純日期」模板 | 疊字顯示 `2025.12.01`，**不是** `尚未開始` |
| 15.5 | 承 15.3 開啟 `showName`（名稱「小寶」） | 疊字顯示 `小寶 尚未開始` |
| 15.6 | `grep -rn "print(" DaysCam/ \| grep -v "//"` | 無結果，或全部在 `#if DEBUG` 內 |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 15.7 | 拒絕相機權限後進相機畫面 | 顯示權限引導畫面，文案與「前往設定」行為一致 |
| 15.8 | 拒絕相簿權限後拍照 | 提示完整包含「無法存入相簿」「這張照片尚未儲存」「前往設定」三要素 |
| 15.9 | 把裝置儲存空間塞到近滿後拍照 | 顯示「儲存失敗：{系統錯誤描述}。請確認裝置儲存空間後再試一次。」，不崩潰、不顯示「已儲存」 |
| 15.10 | 承 15.3 的狀態按快門 | 拍照成功，照片印 `尚未開始`（不阻擋拍照） |

**依賴**：TASK-03、TASK-10

---

## TASK-16：端對端整合驗收

**目標**
不寫新功能，只做完整流程的整合驗證，確認所有卡合起來符合 PRD §1.2 的成功定義。

**範圍**

- 不改產品程式碼。若發現問題，開 issue 或回報 Lead，不在本卡修
- 產出一份驗收結果回報（哪些通過、哪些失敗、失敗的重現步驟）

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 16.1 | `xcodegen generate && xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -destination 'platform=iOS Simulator,name=iPhone 16' test` | 全數通過，exit code 0 |
| 16.2 | `grep -rni "exif\|DateTimeOriginal\|creationDate\|fileCreation" DaysCam/` | 無結果（PRD §6.1 最終確認） |
| 16.3 | `grep -rnE "startDate[?!]?\.date\b" DaysCam/` | 無結果 |
| 16.4 | `git ls-files \| grep xcodeproj` | 無結果 |
| 16.5 | 模擬器冒煙：刪除 App 資料 → `DAYSCAM_FAKE_TODAY=2026-01-10` 啟動 → 開設定檔清單 → 改模板為「純日期」→ `DAYSCAM_FAKE_TODAY=2026-01-11` 重啟 | 首次顯示 `第 1 天`；改模板並跨日後顯示 `2026.01.11`（不是 `第 2 天`） |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 16.6 | **G-1**：刪除 App → 重裝 → 裝置日期 2026-01-10 → 開啟 → 允許相機 → 直接按快門 → 允許相簿 | 全程**沒填過任何表單**，相簿最新一張右下角印 `第 1 天`，照片上無任何品牌或佔位字樣 |
| 16.7 | **G-5**：接續 16.6（裝置日期仍為 2026-01-10），計時完成「進設定檔編輯頁 → 把起始日改成 2025-01-15 → 回相機拍一張」 | 90 秒內完成，照片印 **`第 361 天`**（2025-01-15 → 2026-01-10 相差 360 天，`dayOne` 加 1） |
| 16.7b | 承 16.7，把模板改成「單位轉換」再拍一張 | 照片印 **`0 年 11 個月 26 天`**，依 FR-2.6 省略值為 0 的單位後即 **`11 個月 26 天`** |
| 16.8 | **G-3**：對 16.6 拍的照片在「照片」App 點編輯 | 疊字無法移除 |
| 16.9 | **G-4**：把 16.6 的照片 AirDrop 到另一台裝置開啟 | 疊字仍在且文字不變 |
| 16.10 | 連續使用 5 分鐘：切換設定檔、改模板/位置/主題、拍 10 張 | 不崩潰、無記憶體持續上升、每張照片的疊字都與拍照當下觀景窗顯示的一致 |

**依賴**：TASK-01 ~ TASK-15 全部
