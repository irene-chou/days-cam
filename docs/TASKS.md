# DaysCam MVP 任務清單

- 版本：v1.0
- 撰寫者：PM/Spec Teammate
- 日期：2026-09-19
- 上游文件：[`docs/PRD.md`](./PRD.md)、`PROJECT_PLAN.md`、`CLAUDE.md`

> **給 iOS Dev teammate**：每張卡的顆粒度都設計成「一個 PR 可以完成」。請依 `CLAUDE.md` 的分支命名規則開分支，PR 描述需包含「改了什麼／為什麼改／怎麼驗證」。完成後必須附上具體驗證步驟給 QA。
>
> **給 QA teammate**：每張卡的「驗收標準」都寫成可直接執行、有明確 pass/fail 判準的條目。若有任何一條你無法照做就執行，那是本文件的缺陷，請回報 Lead，不要自行猜測。
>
> **給所有 teammate**：PRD 中標記 `A-xx` 的假設尚未經人類確認。實作時若發現某個假設明顯不合理，**回報 Lead，不要自行改**。

---

## 依賴結構總覽

```
第 0 層（無依賴，可同時開工）
  TASK-01 專案分層骨架與共用型別
  TASK-02 DayCountCalculator（天數計算核心）★ 最高優先

第 1 層
  TASK-03 CameraProfile 模型與 JSON 持久化   ← 01   ※含首次啟動種預設設定檔
  TASK-04 TemplateRenderer（6 模板＋兩種模式）← 01, 02
  TASK-05 OverlayTheme（5 組主題定義）       ← 01

第 2 層
  TASK-06 設定檔清單與編輯頁 UI              ← 03
  TASK-07 相機權限與 AVFoundation 觀景窗     ← 01
  TASK-09 OverlayRenderer（疊字烘焙引擎）    ← 04, 05

第 3 層
  TASK-08 觀景窗即時疊字圖層                 ← 04, 05, 07
  TASK-10 拍照 → 烘焙 → 存相簿               ← 07, 09
  TASK-11 顯示設定面板（模板/位置/主題）      ← 03, 04, 05, 08

第 4 層
  TASK-12 首次啟動流程與啟動狀態還原          ← 06, 07
  TASK-13 相機畫面快速切換設定檔             ← 06, 08
  TASK-14 跨午夜／回前景疊字刷新             ← 08, 10
  TASK-15 錯誤處理與提示統一                 ← 03, 10

第 5 層
  TASK-16 Info.plist 權限文案與端對端驗收腳本 ← 全部
```

**建議平行分工**：Dev A 走邏輯線（01 → 02 → 04 → 05 → 09），Dev B 走 UI/相機線（01 → 07 → 03 → 06）。兩線在 TASK-08 / TASK-10 匯流。

> **本專案最容易實作錯的兩點，請務必先讀 PRD §3.8：**
>
> 1. **PRD FR-8.2：日期模式禁止用「起始日 = 今天的天數設定檔」來實作。** 那樣做隔天會變成「第 2 天」而不是當天日期，日期功能就壞了。TASK-04（4.24 / 4.26）、TASK-12（12.9）有專門的檢查條目。
> 2. **PRD A-4 / FR-2.8：預設設定檔名稱留空，且空名稱絕不可印出任何佔位字。** 疊字會不可逆地烘焙進使用者的照片（§6.2），任何預設字樣都是永久的。TASK-03（3.4）、TASK-04（4.20 / 4.21）、TASK-12（12.4）有專門的檢查條目。

---

## TASK-01：專案分層骨架與共用型別

**目標**
建立 `CLAUDE.md` 要求的「UI 元件／業務邏輯／資料層分開資料夾」結構，並定義後續所有任務共用的列舉型別，避免各 teammate 各自定義造成衝突。

**範圍**
- 建立資料夾：`DaysCam/Models/`、`DaysCam/Services/`、`DaysCam/Views/`、`DaysCamTests/`
- 在 `Models/` 新增以下型別（皆為 `String` raw value 的 `enum`，皆 `Codable`、`CaseIterable`）：
  - `ProfileMode`：`dayCount`、`date`
  - `CountingRule`：`dayOne`、`dayZero`
  - `TemplateID`：`dayCountOnly`、`unitConverted`、`dateOnly`、`dateAndDayCount`、`nameAndDayCount`、`weekCount`
  - `OverlayPosition`：`topLeading`、`topCenter`、`topTrailing`、`middleLeading`、`middleCenter`、`middleTrailing`、`bottomLeading`、`bottomCenter`、`bottomTrailing`
  - `ThemeID`：`classicWhite`、`retroOrange`、`filmStrip`、`minimalDark`、`softPink`
- 每個型別附英文文件註解（`CLAUDE.md` 規定）
- 建立 XCTest target `DaysCamTests`（若 `project.yml` 尚未有）
- **把 `project.yml` 的 `deploymentTarget.iOS` 由目前的 `"17.0"` 改成 `"18.0"`**，並重新產生 Xcode 專案（PRD §9.1 Q-4 已拍板）

**驗收標準**

| # | 步驟 | 預期結果 |
|---|---|---|
| 1.0 | 執行 `grep -A1 'deploymentTarget' project.yml` | 顯示 `iOS: "18.0"` |
| 1.1 | 在 repo 根目錄執行 `xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -destination 'platform=iOS Simulator,name=iPhone 16' build` | 編譯成功，exit code 0 |
| 1.2 | 執行 `xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -destination 'platform=iOS Simulator,name=iPhone 16' test` | 測試 target 可執行（此時可以 0 個測試），exit code 0 |
| 1.3 | 執行 `ls DaysCam/Models DaysCam/Services DaysCam/Views` | 三個資料夾都存在 |
| 1.4 | 執行 `grep -rn "case dayCount\b\|case date\b" DaysCam/Models/` | 找得到 `ProfileMode` 的兩個 case |
| 1.5 | 執行 `grep -rn "case dayOne\|case dayZero" DaysCam/Models/` | 找得到 `CountingRule` 的兩個 case |
| 1.6 | 執行 `grep -c "case " DaysCam/Models/TemplateID.swift`（或該型別所在檔） | 恰好 6 個 case |
| 1.7 | 執行 `grep -c "case " DaysCam/Models/OverlayPosition.swift`（或該型別所在檔） | 恰好 9 個 case |
| 1.8 | 執行 `grep -c "case " DaysCam/Models/ThemeID.swift`（或該型別所在檔） | 恰好 5 個 case |
| 1.9 | 執行 `grep -rn '!' DaysCam/Models/ \| grep -v '!=' \| grep -v '//'` | 無 force-unwrap（`CLAUDE.md` 規定） |

**依賴**：無

---

## TASK-02：DayCountCalculator（天數計算核心）★ 最高優先

**目標**
實作天數計算的唯一真實來源，並用 XCTest 把 PRD §7.1 的所有邊界固定下來。這是全專案最容易出錯的邏輯，必須先於任何 UI 完成。

**範圍**
- 在 `Services/` 新增 `DayCountCalculator`
- 介面需求（實際命名可微調，但**時間來源必須可注入**）：
  ```swift
  struct DayCountCalculator {
      init(calendar: Calendar = .current, now: @escaping () -> Date = { Date() })
      /// Calendar day difference, ignoring time-of-day. Can be negative.
      func rawDayDifference(from startDate: DateComponents) -> Int
      /// Day count after applying the counting rule. Can be zero or negative.
      func dayCount(from startDate: DateComponents, rule: CountingRule) -> Int
      /// Calendar year/month/day breakdown for the unit-converted template.
      func calendarBreakdown(from startDate: DateComponents) -> (years: Int, months: Int, days: Int)
      /// Today's date in the calculator's calendar and time zone.
      func currentDateComponents() -> DateComponents
  }
  ```
- 計算規則（PRD §3.5 / §6.3）：
  - `rawDayDifference` = `calendar.dateComponents([.day], from: startOfDay(起始日), to: startOfDay(now())).day`
  - `dayOne` → `rawDayDifference + 1`；`dayZero` → `rawDayDifference`
  - `calendarBreakdown` = `calendar.dateComponents([.year, .month, .day], from: startOfDay(起始日), to: startOfDay(now()))`，**不套用 +1**
  - `currentDateComponents` = `now()` 在當地時區的年／月／日（供日期模式與「新設定檔起始日預設為今天」使用）
- **禁止**讀取任何 EXIF 或檔案時間（PRD §6.1）
- 附完整 XCTest，測試中一律注入固定的 `now`，**禁止**使用真實 `Date()`

**驗收標準**

執行 `xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:DaysCamTests/DayCountCalculatorTests`，下表每一列都必須有對應的測試案例且通過。所有案例的 `Calendar` 固定為 `Calendar(identifier: .gregorian)`、`timeZone = TimeZone(identifier: "Asia/Taipei")`。

| # | 起始日 | 注入的 now | 規則 | `rawDayDifference` | `dayCount` |
|---|---|---|---|---|---|
| 2.1 同一天 | 2026-01-01 | 2026-01-01 12:00 | dayOne | 0 | **1** |
| 2.2 同一天 | 2026-01-01 | 2026-01-01 12:00 | dayZero | 0 | **0** |
| 2.3 基本 | 2026-01-01 | 2026-01-10 08:00 | dayOne | 9 | **10** |
| 2.4 基本 | 2026-01-01 | 2026-01-10 08:00 | dayZero | 9 | **9** |
| 2.5 跨月 | 2026-01-31 | 2026-02-01 00:30 | dayOne | 1 | **2** |
| 2.6 跨年 | 2025-12-31 | 2026-01-01 00:30 | dayOne | 1 | **2** |
| 2.7 閏年含 2/29 | 2024-02-28 | 2024-03-01 10:00 | dayOne | 2 | **3** |
| 2.8 非閏年同區間 | 2026-02-28 | 2026-03-01 10:00 | dayOne | 1 | **2** |
| 2.9 起始日為 2/29 | 2024-02-29 | 2024-03-01 10:00 | dayOne | 1 | **2** |
| 2.10 整年（平年） | 2025-01-01 | 2026-01-01 10:00 | dayOne | 365 | **366** |
| 2.11 整年（閏年） | 2024-01-01 | 2025-01-01 10:00 | dayOne | 366 | **367** |
| 2.12 午夜前一秒 | 2026-01-01 | 2026-01-01 23:59:59 | dayOne | 0 | **1** |
| 2.13 午夜後一秒 | 2026-01-01 | 2026-01-02 00:00:01 | dayOne | 1 | **2** |
| 2.14 起始日在未來 | 2026-12-01 | 2026-09-19 10:00 | dayOne | -73 | **-72** |
| 2.15 起始日在未來 | 2026-12-01 | 2026-09-19 10:00 | dayZero | -73 | **-73** |
| 2.16 長期 | 2025-01-15 | 2026-03-20 10:00 | dayOne | 429 | **430** |

`calendarBreakdown` 的測試案例：

| # | 起始日 | 注入的 now | 預期 (years, months, days) |
|---|---|---|---|
| 2.17 | 2025-01-15 | 2026-03-20 | **(1, 2, 5)** |
| 2.18 | 2026-01-01 | 2026-01-01 | **(0, 0, 0)** |
| 2.19 | 2026-01-01 | 2026-01-10 | **(0, 0, 9)** |
| 2.20 | 2024-02-29 | 2025-02-28 | **(0, 11, 30)**（PRD A-28：接受 `Calendar` 原生行為，本案例用來鎖住此行為） |
| 2.21 | 2024-02-29 | 2025-03-01 | **(1, 0, 1)** |

`currentDateComponents` 與時區驗證：

| # | 步驟 | 預期結果 |
|---|---|---|
| 2.22 | 注入 now = `2026-01-10 08:00`（Asia/Taipei），呼叫 `currentDateComponents()` | `(year: 2026, month: 1, day: 10)` |
| 2.23 | 注入 now = `2026-01-10 23:59:59`（Asia/Taipei） | `(year: 2026, month: 1, day: 10)`（時分秒不影響） |
| 2.24 | 同一組輸入（起始日 2026-01-01、now 為 UTC 時間 `2026-01-09T20:00:00Z`），分別以 `Asia/Taipei`（UTC+8，當地為 01-10 04:00）與 `America/New_York`（UTC-5，當地為 01-09 15:00）建立 calculator | Taipei → `dayCount(dayOne) == 10` 且 `currentDateComponents()` 為 01-10；New_York → `dayCount(dayOne) == 9` 且 `currentDateComponents()` 為 01-09 |

靜態檢查：

| # | 步驟 | 預期結果 |
|---|---|---|
| 2.25 | 執行 `grep -rni "exif\|DateTimeOriginal\|creationDate\|fileCreation" DaysCam/` | **無任何結果**（PRD §6.1 硬約束） |
| 2.26 | 執行 `grep -rn "Date()" DaysCamTests/` | **無任何結果**（測試不得依賴真實時間） |

**依賴**：無（可與 TASK-01 平行，但合併順序建議在 TASK-01 之後）

---

## TASK-03：CameraProfile 模型與 JSON 持久化

**目標**
實作設定檔資料模型與檔案持久化層，包含**首次啟動自動種下兩個預設設定檔**，讓上層 UI 有穩定的 CRUD 介面。

**範圍**
- `Models/CameraProfile.swift`：依 PRD §4.1 定義欄位
  - `startDate` 型別為 `DateComponents?`，**不是 `Date`**（PRD A-26，理由與已排除的替代方案見 PRD §9.1「Q-3 的理由」）。必須滿足 PRD §4.1 **不變條件 4**：恰好只含 year/month/day，其餘欄位（`hour`／`minute`／`second`／**`timeZone`**／**`calendar`** 等）皆須為 nil，且日期必須真實存在
  - `name` 為 `String`，**允許空字串**（PRD FR-1.6 / A-10）
  - `templateID` 預設 `.nameAndDayCount`（PRD FR-1.9）
- `Services/ProfileStore.swift`：
  - 讀寫 `Application Support/DaysCam/profiles.json`，寫入採原子寫入
  - CRUD：`load()`、`add(_:)`、`update(_:)`、`delete(id:)`
  - **首次啟動種預設值**：檔案不存在時，種下 PRD §2.2 的兩個設定檔並寫檔
    - ①：`name: ""`、`mode: .dayCount`、`startDate: 今天`、`countingRule: .dayOne`、`templateID: .dayCountOnly`、`position: .bottomTrailing`、`themeID: .classicWhite`
    - ②：`name: "日期"`、`mode: .date`、`startDate: nil`、`templateID: .dateOnly`、`position: .bottomTrailing`、`themeID: .classicWhite`
    - 種完後 `lastUsedProfileID` 指向 ①
    - 「今天」必須來自可注入的時間來源，**測試不得依賴真實 `Date()`**
  - **強制 PRD §4.1 的不變條件**：`.dayCount` ⟹ `startDate != nil`；`.date` ⟹ `startDate == nil` 且 `templateID == .dateOnly`。讀檔時遇到違反者依 PRD §7.3 修正或丟棄
  - 檔案損毀處理：改名為 `profiles.json.corrupt-{unix timestamp}`，**重新種下兩個預設設定檔**，並曝露 `didRecoverFromCorruption: Bool` 供 UI 顯示提示（PRD A-30）
  - 數量上限 20（PRD FR-1.7）：`add` 在已達 20 筆時回傳錯誤
  - **至少保留 1 個**（PRD FR-1.8 / A-11）：`delete` 在只剩 1 筆時回傳錯誤，不刪除
- **App 層級狀態**（PRD §4.2），存於 `UserDefaults`：
  - `lastUsedProfileID: UUID?`
  - 讀取時若指向的設定檔**已不存在**，回傳**清單中的第一個設定檔**的 id
  - **不再有** `dateModePosition` / `dateModeTheme` 之類的 App 層級外觀鍵——位置與主題是每個設定檔自己的欄位

**驗收標準**

執行 `xcodebuild ... test -only-testing:DaysCamTests/ProfileStoreTests`（測試需使用暫時目錄與注入的時間來源，不得污染真實沙盒、不得依賴真實時間）：

**A. 首次啟動種預設設定檔**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.1 | 新建 store（目錄為空，注入 now = 2026-01-10）→ `load()` | 回傳**恰好 2 筆**，順序為 ①、② |
| 3.2 | 檢查第 1 筆（①） | `name == ""`（**空字串**）、`mode == .dayCount`、`startDate == (2026, 1, 10)`、`countingRule == .dayOne`、`templateID == .dayCountOnly`、`position == .bottomTrailing`、`themeID == .classicWhite` |
| 3.3 | 檢查第 2 筆（②） | `name == "日期"`、`mode == .date`、`startDate == nil`、`templateID == .dateOnly` |
| 3.4 | 檢查兩筆的 `name` 欄位 | ① 為空字串；② 為 `"日期"`。**兩者都不得包含**「天數相機」「DaysCam」「我的計時器」「未命名」等任何佔位或品牌字樣（PRD A-4：這些字會被永久烘焙進照片） |
| 3.5 | 承 3.1，讀取 `lastUsedProfileID` | 等於 ① 的 `id` |
| 3.6 | 承 3.1，建立新 store 指向同一目錄（注入 now = 2026-02-20）→ `load()` | 仍為原本那 2 筆，① 的 `startDate` **仍是 (2026, 1, 10)**（只在檔案不存在時種一次，不會被重新種或覆寫） |

**B. CRUD 與持久化**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.7 | `add` 一筆 `name: "小寶"`, `mode: .dayCount`, `startDate: 2025-01-15`, `rule: .dayOne` → 建立新 store 指向同一目錄 → `load()` | 回傳 3 筆，新那筆所有欄位與寫入時完全相同（`id`、`name`、`mode`、`startDate` 的 year/month/day、`countingRule`、`templateID`、`position`、`themeID`） |
| 3.8 | `add` 一筆後 `update` 把 `name` 改為 `"小寶貝"` → 重新 `load()` | `name == "小寶貝"`，`id` 不變，`updatedAt` 大於 `createdAt` |
| 3.9 | `delete` 掉其中一筆 → `load()` | 該筆消失，其餘不變 |
| 3.10 | 連續 `add` 到總數 20 筆 | 全部成功 |
| 3.11 | 在 3.10 之後再 `add` 第 21 筆 | 回傳錯誤（不是 crash、不是靜默忽略），`load()` 仍為 20 筆 |
| 3.12 | 刪到只剩 1 筆後，再 `delete` 那一筆 | 回傳錯誤，**不刪除**，`load()` 仍為 1 筆（PRD FR-1.8） |
| 3.13 | 檢查 `startDate` 的型別 | 執行 `grep -n "startDate" DaysCam/Models/CameraProfile.swift`，型別為 `DateComponents?`，**不是 `Date`** |
| 3.14 | `add` 一筆 `name: ""`（空字串） | 成功（名稱可留空，PRD FR-1.6） |
| 3.15 | `add` 一筆 `name` 為 21 個字元 | 回傳錯誤（超出 20 字上限） |

**C-1. 不變條件：寫入路徑（`add` / `update` 一律拒絕或剝除）**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.16 | `add` 一筆 `mode: .dayCount` 但 `startDate: nil` | 回傳錯誤（違反不變條件 1） |
| 3.17 | `add` 一筆 `mode: .date` 但 `startDate` 非 nil | 回傳錯誤（違反不變條件 2） |
| 3.18 | `add` 一筆 `mode: .date` 但 `templateID: .dayCountOnly` | 回傳錯誤（違反不變條件 2） |
| 3.19 | `add` 一筆 `startDate` 含 `hour: 13, minute: 30, second: 45` | 三者被**剝除**後才寫入；`load()` 回來 `hour`/`minute`/`second` 皆為 nil，年月日不變（不變條件 4） |
| 3.20 | `add` 一筆 `startDate` 帶 `timeZone = TimeZone(identifier: "Asia/Taipei")` | 被**剝除**後才寫入；`load()` 回來 `startDate.timeZone == nil`，年月日不變 |
| 3.21 | `add` 一筆 `startDate` 帶 `calendar = Calendar(identifier: .buddhist)` | 被**剝除**後才寫入；`load()` 回來 `startDate.calendar == nil`，年月日不變 |
| 3.22 | `add` 一筆 `startDate` 為 `month: 13` | 回傳錯誤，不寫入 |
| 3.23 | `add` 一筆 `startDate` 為 `2026-02-30`（該月不存在的日） | 回傳錯誤，不寫入 |
| 3.24 | `add` 一筆 `startDate` 只有 `year` 與 `month`（缺 `day`） | 回傳錯誤，不寫入 |

**C-2. 不變條件：讀取路徑（`load` 修復或丟棄）**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.25 | 手動在 `profiles.json` 裡塞一筆 `mode: "date"` 且帶有 `startDate` 的資料 → `load()` | 該筆被**修正**後回傳：`startDate` 為 nil、`templateID` 為 `.dateOnly`；不崩潰（PRD §7.3） |
| 3.26 | 手動塞一筆 `mode: "dayCount"` 但缺 `startDate` 的資料 → `load()` | 該筆被**丟棄**，其餘正常回傳；不崩潰（PRD §7.3） |
| 3.27 | 手動塞一筆 `startDate` 含時分秒的資料 → `load()` | 時分秒被剝除，年月日正確；不崩潰 |
| 3.28 | **（本段最關鍵的一條，驗真正的危害而不只是屬性值）** 手動塞兩筆 `dayCount` 設定檔 P1、P2，`startDate` 年月日**都是 2026-01-15**、規則皆 `dayOne`，但 P2 額外帶 `timeZone: TimeZone(identifier: "Asia/Taipei")`。calculator 的時區設為 **`America/New_York`**、注入 now = `2026-01-20 12:00`，`load()` 後分別渲染 | P2 的 `timeZone` 被剝除，**P1 與 P2 都輸出 `第 6 天`**（rawDayDifference 皆為 5）。<br>**若剝除未實作，P2 會輸出 `第 7 天`**（rawDayDifference 為 6）——夾帶的台北時區把起始日解讀成紐約當地的 2026-01-14，硬是多算一天 |
| 3.29 | 手動塞一筆 `startDate` 帶 `calendar: Calendar(identifier: .buddhist)` 的資料 → `load()` | `calendar` 被剝除；該筆算出的天數與同年月日但乾淨的設定檔**完全相同**，**不得**出現差 543 年的日期（佛曆 2026 年＝西元 1483 年） |
| 3.30 | 手動塞一筆 `startDate` 為 `month: 13` 的資料 → `load()` | 該筆被**丟棄**，其餘正常回傳；不崩潰 |

> **給 QA 的提醒（3.28 的時區組合不可自行更換）**：夾帶的 `timeZone` **不是**每次都會造成差異。只有當**夾帶的時區 offset 大於裝置時區**時，起始日才會被推回前一個當地日。本條指定的組合（夾帶 `Asia/Taipei` +8、裝置 `America/New_York` −5）滿足這個條件，所以測得出來；若改成夾帶 `UTC`（+0）而裝置在台北（+8），**即使剝除邏輯完全沒實作也會通過**。請照條目指定的組合執行。
>
> **也請注意**：PRD §6.3 規定天數計算會走 `startOfDay` 正規化，但那**救不回**這種污染——日期已整個位移一天，`startOfDay` 只是取出錯誤日期的零點。所以這條必須在持久化層驗，不能寄望計算層擋下來。

**D. 損毀與狀態還原**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.31 | 手動把 `profiles.json` 內容覆寫成 `"這不是 JSON"` → 建立新 store（注入 now = 2026-03-05）→ `load()` | 回傳**重新種下的 2 筆預設設定檔**（① 的 `startDate == (2026, 3, 5)`），`didRecoverFromCorruption == true`，且同目錄下存在 `profiles.json.corrupt-*`，內容為 `"這不是 JSON"` |
| 3.32 | 設定 `lastUsedProfileID` 為某筆 id → 重新讀取 | 回傳同一個 id |
| 3.33 | 把 `lastUsedProfileID` 手動改成一個隨機不存在的 UUID → 讀取 | 回傳**清單第一筆**的 id（不是 nil、不崩潰） |
| 3.34 | `delete` 掉 `lastUsedProfileID` 指向的設定檔 → 讀取 `lastUsedProfileID` | 回傳清單中仍存在的某一筆 id（不得指向已刪除的 id） |

**E. 靜態檢查**

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.35 | 執行 `grep -rn "dateModePosition\|dateModeTheme" DaysCam/` | **無結果**（位置/主題已改為設定檔欄位，不再有 App 層級鍵） |
| 3.36 | 執行 `grep -rni "天數相機\|DaysCam\|我的計時器" DaysCam/Services/ProfileStore.swift` | **無結果**（種預設值時不得帶入任何品牌或佔位名稱，PRD A-4） |
| 3.37 | 執行 `grep -rnE "startDate[?!]?\.date\b" DaysCam/` | **無結果**。禁止使用 `DateComponents.date` 計算屬性取日期——它會採用元件自帶的 `calendar`（污染時差 543 年），且在 `calendar` 為 nil 時一律回傳 nil。一律改走注入的 `Calendar`（PRD §4.1 不變條件 4 的說明） |

**依賴**：TASK-01

---

## TASK-04：TemplateRenderer（6 種模板 ＋ 兩種模式）

**目標**
把「設定檔 + 當下時間」渲染成要疊印的字串，涵蓋 PRD §3.2 的 6 種模板與 §3.8 的兩種模式。

**範圍**
- `Services/TemplateRenderer.swift`
- 介面：
  ```swift
  /// Renders the overlay text for a profile, dispatching on its mode.
  func render(profile: CameraProfile, calculator: DayCountCalculator) -> String
  ```
- 依 `profile.mode` 分派到兩條**獨立**的渲染路徑：
  - `.dayCount` → 用 `startDate` 算天數，套用 `templateID`
  - `.date` → **直接取當下日期**輸出 `yyyy.MM.dd`，不經過 `startDate`、不經過 `CountingRule`
- **禁止**把 `.date` 路徑實作成「用一個 `startDate` = 今天的臨時設定檔再走 `.dayCount` 路徑」（PRD FR-8.2）
- 空名稱退化（PRD FR-2.8）：`nameAndDayCount` 遇到 `name == ""` 時輸出 `第 {n} 天`，**不得**有開頭空白、**不得**印出「未命名」等佔位字
- 起始日在未來（`dayCount <= 0` 且 `rawDayDifference < 0`）時，`.dayCount` 的**所有模板**一律回傳 `"尚未開始"`（PRD §7.2 / A-29）。此規則**不適用** `.date` 模式
- 附 XCTest

**驗收標準**

基準情境：`name: "小寶"`、`mode: .dayCount`、`startDate: 2025-01-15`、`rule: .dayOne`、注入 now = `2026-03-20 10:00`（Asia/Taipei）。此時 `dayCount = 430`、`calendarBreakdown = (1, 2, 5)`。

| # | `templateID` | 預期輸出（完全相符，含空白） |
|---|---|---|
| 4.1 | `dayCountOnly` | `第 430 天` |
| 4.2 | `unitConverted` | `1 年 2 個月 5 天` |
| 4.3 | `dateOnly` | `2026.03.20` |
| 4.4 | `dateAndDayCount` | `2026.03.20　第 430 天`（中間為 1 個全形空白 U+3000） |
| 4.5 | `nameAndDayCount` | `小寶 第 430 天` |
| 4.6 | `weekCount` | `第 62 週又 3 天`（430 ÷ 7 = 61 餘 3，週數從第 1 週起算） |

省略規則：

| # | 情境 | `templateID` | 預期輸出 |
|---|---|---|---|
| 4.7 | start 2026-01-01, now 2026-01-01, dayOne | `unitConverted` | `0 天`（年、月皆為 0 時省略，但至少保留「天」） |
| 4.8 | start 2026-01-01, now 2026-01-10, dayOne | `unitConverted` | `9 天` |
| 4.9 | start 2025-01-01, now 2026-01-01, dayOne | `unitConverted` | `1 年`（月、天皆為 0 時省略） |
| 4.10 | start 2025-01-01, now 2026-03-01, dayOne | `unitConverted` | `1 年 2 個月`（天為 0 時省略） |
| 4.11 | start 2026-01-01, now 2026-01-08, dayOne（`dayCount` = 8） | `weekCount` | `第 2 週又 1 天` |
| 4.12 | start 2026-01-01, now 2026-01-07, dayOne（`dayCount` = 7） | `weekCount` | `第 1 週`（餘數為 0 時省略「又 N 天」） |
| 4.13 | start 2026-01-01, now 2026-01-14, dayOne（`dayCount` = 14） | `weekCount` | `第 2 週` |

起始日在未來：

| # | 情境 | 預期輸出 |
|---|---|---|
| 4.14 | start 2026-12-01, now 2026-09-19，`.dayCount` 模式，**6 種模板全測** | 6 種模板都回傳 `尚未開始` |

`dayZero` 規則：

| # | 情境 | `templateID` | 預期輸出 |
|---|---|---|---|
| 4.15 | start 2026-01-01, now 2026-01-01, **dayZero** | `dayCountOnly` | `第 0 天` |
| 4.16 | start 2026-01-01, now 2026-01-01, **dayZero** | `weekCount` | `第 1 週`（0 天視為第 1 週、餘 0） |

**預設設定檔①的渲染（首次啟動的實際情境）**：

| # | 情境 | 預期輸出 |
|---|---|---|
| 4.17 | `name: ""`、`.dayCount`、start 2026-01-10、dayOne、`dayCountOnly`，注入 now = 2026-01-10 | `第 1 天` |
| 4.18 | 承 4.17，now 改為 2026-01-11 | `第 2 天`（天數設定檔隔天遞增，這是**正確**行為） |
| 4.19 | 承 4.17，now 改為 2026-02-10 | `第 32 天`（1 月剩 21 天 + 2 月 10 天 + 1 = 32） |

**空名稱退化**（PRD FR-2.8 / A-4）：

| # | 情境 | `templateID` | 預期輸出 |
|---|---|---|---|
| 4.20 | `name: ""`、start 2026-01-01、now 2026-01-10、dayOne | `nameAndDayCount` | 恰好 `第 10 天`。**不得**為 `" 第 10 天"`（開頭空白）、**不得**為 `未命名 第 10 天`。以 `XCTAssertEqual(output, "第 10 天")` 逐字元比對 |
| 4.21 | `name: "   "`（三個半形空白）、其餘同上 | `nameAndDayCount` | 同樣退化為 `第 10 天`（名稱 trim 後為空即視為空名稱） |

**日期模式渲染路徑**（PRD §3.8）：

| # | 步驟 | 預期輸出 |
|---|---|---|
| 4.22 | `.date` 設定檔，注入 now = `2026-03-20 10:00` | `2026.03.20` |
| 4.23 | `.date` 設定檔，注入 now = `2026-01-01 23:59:59` → 再注入 `2026-01-02 00:00:01` | 依序為 `2026.01.01`、`2026.01.02`（跨午夜後跟著變） |
| 4.24 | **同一個** `.date` 設定檔，先以 now = `2026-01-10` 渲染，再以 now = `2026-01-11` 渲染 | 依序為 `2026.01.10`、`2026.01.11`。**證明日期模式每次重取當下日期，沒有把任何日期記下來**（PRD FR-8.3） |
| 4.25 | `.date` 設定檔 `name: "日期"`，注入 now = 2026-01-10 | 輸出恰好 `2026.01.10`。**名稱不得出現在輸出中**（PRD FR-8.6） |
| 4.26 | 建立一個 `.dayCount`、start = 2026-01-10、dayOne、`dayCountOnly` 的設定檔 A，與一個 `.date` 設定檔 B。注入 now = 2026-01-10 分別渲染，再注入 now = 2026-01-11 分別渲染 | now=01-10：A → `第 1 天`，B → `2026.01.10`；now=01-11：A → `第 2 天`，B → **`2026.01.11`**。**這是兩種模式的核心對照**：A 遞增是對的，B 必須跟著日期走而不是變成「第 2 天」（PRD FR-8.2） |
| 4.27 | `.date` 設定檔，以 `Asia/Taipei` 與 `America/New_York` 兩個 calendar 注入同一 UTC 時間 `2026-01-09T20:00:00Z` | Taipei → `2026.01.10`；New_York → `2026.01.09` |

靜態檢查：

| # | 步驟 | 預期結果 |
|---|---|---|
| 4.28 | 檢視 `.date` 分支的實作 | 該分支內**沒有**用到 `startDate`、`CountingRule`、`dayCount(...)`；只呼叫 `calculator.currentDateComponents()` 並格式化（PRD FR-8.2） |

> **這裡是我的假設（T-04-a）**：4.7 的「0 天」與 4.16 的「dayZero 第 0 天時 weekCount 顯示第 1 週」都是邊界文案決策，PRD 未明列。若 Lead 有其他偏好請直接覆蓋。

> **這裡是我的假設（T-04-b）**：4.21 規定「名稱 trim 後為空即視為空名稱」。PRD FR-2.8 只說空名稱，沒說純空白字串。我判定一併退化，避免使用者輸入空白造成疊字開頭有詭異空格。

**依賴**：TASK-01、TASK-02

---

## TASK-05：OverlayTheme（5 組主題定義）

**目標**
把 PRD §3.4 的 5 組主題定義成可被 SwiftUI 預覽層與 Core Graphics 烘焙層**共用**的資料結構，避免預覽與成品長得不一樣。

**範圍**
- `Models/OverlayTheme.swift`：`struct OverlayTheme` 含 `id: ThemeID`、`displayName: String`、`fontDesign`、`fontWeight`、`textColor`、`decoration`（enum：`.shadow(offset:blur:opacity:color:)` / `.backgroundBox(color:opacity:cornerRadius:insets:)` / `.stroke(color:width:)` 可組合）
- 提供 `static let all: [OverlayTheme]`，順序固定為 PRD §3.4 表格順序
- 提供 `func fontSize(forShortEdge: CGFloat) -> CGFloat`，回傳 `shortEdge * 0.055`（PRD FR-4.2）
- 顏色以 sRGB 數值定義，**不得**使用 Asset Catalog 的動態顏色（疊字顏色不得跟隨 Light/Dark Mode 改變）

**驗收標準**

| # | 步驟 | 預期結果 |
|---|---|---|
| 5.1 | 執行 `xcodebuild ... test -only-testing:DaysCamTests/OverlayThemeTests`，斷言 `OverlayTheme.all.count` | 恰好 `5` |
| 5.2 | 斷言 `OverlayTheme.all.map(\.id)` | 依序為 `[.classicWhite, .retroOrange, .filmStrip, .minimalDark, .softPink]` |
| 5.3 | 斷言每個 theme 的 `decoration` 不為空 | 5 組全部都有至少一種 decoration（PRD FR-4.1：確保淺色照片上可辨識） |
| 5.4 | 斷言 `classicWhite.textColor` 的 sRGB 分量 | `(1.0, 1.0, 1.0, 1.0)` |
| 5.5 | 斷言 `retroOrange.textColor` 的 sRGB 分量 | 對應 `#FF9500`，即 `(1.0, 0.584, 0.0, 1.0)`，容差 ±0.01 |
| 5.6 | 斷言 `fontSize(forShortEdge: 3024)` | `166.32`，容差 ±0.01 |
| 5.7 | 執行 `grep -rn "Color(\"\\|UIColor(named" DaysCam/Models/OverlayTheme.swift` | 無結果（不使用 Asset Catalog 動態色） |
| 5.8 | 執行 `grep -rn "\\.custom(\\|UIFont(name:" DaysCam/` | 無結果（PRD FR-4.4：只用系統字體，不打包自訂字型） |

**依賴**：TASK-01

---

## TASK-06：設定檔清單與編輯頁 UI

**目標**
實作 PRD S-2 / S-3：設定檔的新增、編輯、刪除、選擇，含模式切換。

**範圍**
- `Views/ProfileListView.swift`、`Views/ProfileEditView.swift`
- 清單每列顯示：名稱（空名稱顯示佔位文字「未命名」）＋模式標示（例如「天數」/「日期」小標籤）＋選取標記
- 編輯頁欄位（**只有邏輯層**，PRD FR-5.5）：
  - 名稱（`TextField`，0–20 字元，**可留空**）
  - 模式（`Picker`，segmented：天數／日期）
  - 起始日（`DatePicker`，`displayedComponents: .date`，`in: ...Date()` 上限為今天）— **僅模式為「天數」時顯示**
  - 起算規則（`Picker`，segmented）— **僅模式為「天數」時顯示**
- 編輯頁顯示即時預覽：天數模式顯示「今天會顯示為：第 N 天」；日期模式顯示「今天會顯示為：2026.01.10」（PRD FR-5.6）
- 模式切換行為（PRD FR-8.7）：切到「日期」時模板自動改為 `dateOnly`；切到「天數」時起始日預設為今天
- 新增設定檔的預設值依 PRD FR-1.9；建立後**自動切換到該新設定檔**（FR-1.10）
- 刪除需二次確認（`confirmationDialog`）；**只剩 1 個設定檔時刪除 disabled** 並顯示說明（FR-1.8）
- 已達 20 筆時，「新增」按鈕 disabled 並顯示說明文字

**驗收標準**（在 iPhone 16 模擬器上手動執行；裝置系統日期統一設為 **2026-01-10**，除非條目另有指定）

**A. 預設設定檔的呈現**

| # | 步驟 | 預期結果 |
|---|---|---|
| 6.1 | 全新安裝後開啟設定檔清單 | 恰好 **2 列**：第 1 列名稱顯示「未命名」、標示「天數」、帶選取標記；第 2 列名稱「日期」、標示「日期」 |
| 6.2 | 點進第 1 列的編輯頁 | 名稱欄位為**空的**（不是預填「未命名」或任何字）；模式為「天數」；起始日為 2026-01-10；起算規則為「當天算第 1 天」；預覽顯示「今天會顯示為：第 1 天」 |
| 6.3 | 點進第 2 列的編輯頁 | 名稱為「日期」；模式為「日期」；**看不到**起始日與起算規則欄位；預覽顯示「今天會顯示為：2026.01.10」 |

**B. 新增與編輯**

| # | 步驟 | 預期結果 |
|---|---|---|
| 6.4 | 點「＋」新增 | 編輯頁預設：名稱空白、模式「天數」、起始日 2026-01-10、規則「當天算第 1 天」 |
| 6.5 | 名稱留空直接儲存 | **儲存成功**（名稱非必填，FR-1.6），清單新增一列顯示「未命名」 |
| 6.6 | 名稱輸入 21 個字元（例如貼上 `一二三四五六七八九十一二三四五六七八九十壹`） | 輸入框內只保留前 20 字，第 21 字進不去（不是儲存時才報錯） |
| 6.7 | 名稱輸入「小寶」、起始日改為 2026-01-01、規則「當天算第 1 天」→ 儲存 | 回到清單，出現一列「小寶」，且**選取標記自動落在「小寶」**（FR-1.10） |
| 6.8 | 承 6.7，回到編輯頁 | 預覽文字顯示「今天會顯示為：第 10 天」 |
| 6.9 | 承 6.8，把規則切到「當天算第 0 天」（不儲存，只切 Picker） | 預覽文字**即時**變為「今天會顯示為：第 9 天」 |
| 6.10 | 打開起始日 `DatePicker`，嘗試選擇明天（2026-01-11） | 明天以後的日期無法選取（灰階／不可點） |
| 6.11 | 新增一筆，模式切到「日期」 | 起始日與起算規則欄位**立即消失**；預覽變成「今天會顯示為：2026.01.10」 |
| 6.12 | 承 6.11 儲存後，回到該筆的編輯頁把模式切回「天數」 | 起始日與起算規則欄位**重新出現**，起始日預設為今天（2026-01-10）（FR-8.7） |

**C. 刪除與下限**

| # | 步驟 | 預期結果 |
|---|---|---|
| 6.13 | 在清單對某一列左滑 → 刪除 | 出現確認對話框；點「取消」後該列仍在 |
| 6.14 | 重複 6.13 並點「刪除」 | 該列消失；殺掉 App 重開，該列仍不存在 |
| 6.15 | 一路刪到只剩 1 個設定檔，再嘗試刪除它 | 刪除動作 **disabled**（左滑沒有刪除鈕，或按下去無效並顯示說明「至少需要保留一個設定檔」）；清單仍有 1 列（FR-1.8） |
| 6.16 | 刪除**非選取中**的設定檔 | 選取標記不變，仍在原本那一筆 |
| 6.17 | 刪除**選取中**的設定檔（清單還有其他筆） | 選取標記自動移到清單中仍存在的某一筆，不崩潰、不出現空白畫面 |

**D. 上限**

| # | 步驟 | 預期結果 |
|---|---|---|
| 6.18 | 建立到總數 20 個設定檔 | 「＋」按鈕變 disabled，畫面顯示說明文字（內容需提到上限 20） |

**依賴**：TASK-03

---

## TASK-07：相機權限與 AVFoundation 觀景窗

**目標**
實作 PRD S-1 的觀景窗與 S-5 權限引導畫面。此卡**不含**疊字與拍照，只負責「把畫面顯示出來 + 權限狀態機」。

**範圍**
- `Services/CameraService.swift`：包裝 `AVCaptureSession`、`AVCaptureDeviceInput`、`AVCapturePhotoOutput`（output 先建好但不使用）
- `Views/CameraPreviewView.swift`：`UIViewRepresentable` 包 `AVCaptureVideoPreviewLayer`
- 拍攝比例固定 4:3（PRD A-22），觀景窗以 4:3 顯示
- 前／後鏡頭切換按鈕
- 權限狀態機（PRD §2.3）：`.notDetermined` / `.authorized` / `.denied` / `.restricted`
- 監聽 `AVCaptureSessionWasInterrupted` / `InterruptionEnded`
- 監聽 `willEnterForeground` 重新檢查權限
- 模擬器 fallback（PRD A-8）：`#if targetEnvironment(simulator)` 顯示純色佔位背景，快門 disabled 並標示「模擬器不支援拍照」
- `AVCaptureSession` 的 start/stop 必須在背景 queue，不得阻塞主執行緒

**驗收標準**（除 7.1 外皆需**實機**）

| # | 步驟 | 預期結果 |
|---|---|---|
| 7.1 | 在 iPhone 16 模擬器執行 App 並進入相機畫面 | 顯示純色佔位背景，快門鍵為 disabled，畫面上有「模擬器不支援拍照」字樣，App 不崩潰 |
| 7.2 | 實機首次安裝後進入相機畫面 | 跳出 iOS 相機權限系統彈窗，文案為 `Info.plist` 設定的內容（TASK-16 負責文案） |
| 7.3 | 在 7.2 點「允許」 | 觀景窗在 2 秒內顯示即時畫面 |
| 7.4 | 在 7.2 點「不允許」 | 觀景窗區域變成權限引導畫面：標題「需要相機權限」、有「前往設定」按鈕、快門鍵 disabled |
| 7.5 | 承 7.4，點「前往設定」 | 跳到 iOS 設定中的 DaysCam 頁面 |
| 7.6 | 承 7.5，在設定裡打開相機權限 → 直接切回 DaysCam（**不殺 App**） | 權限引導畫面自動消失，觀景窗自動開始顯示即時畫面 |
| 7.7 | 點前／後鏡頭切換按鈕 | 觀景窗在 1 秒內切換到另一顆鏡頭，畫面不卡死 |
| 7.8 | 在相機畫面停留時撥打／接聽電話中斷 App，結束後回到 App | 觀景窗自動恢復，不需重啟 App |
| 7.9 | 觀察觀景窗畫面比例 | 為 4:3（可用畫面上已知比例的物體目視，或以截圖量測預覽區域像素比，誤差 < 2%） |
| 7.10 | 在相機畫面快速切換前後鏡頭 10 次 | App 不崩潰，Xcode console 無 `AVCaptureSession` 相關 error log |

**依賴**：TASK-01

---

## TASK-08：觀景窗即時疊字圖層

**目標**
把 TemplateRenderer 的輸出，用 TASK-05 的主題與 9 宮格定位，即時疊在觀景窗上（SwiftUI 圖層，**非烘焙**）。

**範圍**
- `Views/OverlayTextView.swift`：吃**已渲染好的文字** + `OverlayTheme` + `OverlayPosition`，輸出 SwiftUI view。不直接吃 `CameraProfile`——文字與樣式由上層依目前設定檔決定，view 只負責排版
- 9 宮格對齊規則（PRD FR-3.3）：邊距 = 觀景窗短邊 × 4%；左側格靠左、右側格靠右、中間格置中
- 字級 = 觀景窗短邊 × 5.5%（與烘焙層共用 TASK-05 的 `fontSize(forShortEdge:)`）
- 疊字**不得**攔截觸控（`allowsHitTesting(false)`）

**驗收標準**（模擬器可執行，疊字不依賴實體相機；系統日期設為 **2026-01-10**）

| # | 步驟 | 預期結果 |
|---|---|---|
| 8.1 | 全新安裝，進入相機畫面（套用預設設定檔①） | 觀景窗上顯示 `第 1 天`（右下角、白字黑陰影） |
| 8.2 | 切到預設設定檔②（日期） | 觀景窗上顯示 `2026.01.10` |
| 8.3 | 建立設定檔「小寶 / 2026-01-01 / 當天算第 1 天 / `dayCountOnly`」並切過去 | 觀景窗上顯示 `第 10 天` |
| 8.4 | 承 8.3，模板改 `nameAndDayCount` | 觀景窗上顯示 `小寶 第 10 天` |
| 8.5 | 承 8.3，模板改 `dateOnly` | 觀景窗上顯示 `2026.01.10` |
| 8.6 | 位置設為 `topLeading` | 文字出現在觀景窗左上角，且左邊界與上邊界距離皆約為短邊的 4%（截圖量測，誤差 < 1%） |
| 8.7 | 位置設為 `bottomTrailing` | 文字出現在右下角，右邊界與下邊界距離約為短邊的 4% |
| 8.8 | 位置設為 `middleCenter` | 文字水平與垂直皆置中 |
| 8.9 | 依序套用 9 個位置 | 9 個位置文字都完整顯示在觀景窗內，**沒有任何一個被裁切** |
| 8.10 | 主題設為 `classicWhite`，把相機對著**純白牆面**（或模擬器佔位背景設為白色） | 文字仍清晰可辨（有黑色陰影襯底） |
| 8.11 | 主題設為 `minimalDark`，把相機對著**全黑畫面** | 文字仍清晰可辨（有白色底框襯底） |
| 8.12 | 5 組主題各套用一次 | 每組的字體、顏色、襯底效果肉眼可區分，無任何一組是純文字無襯底 |
| 8.13 | 用手指點擊疊字所在位置 | 觸控穿透到底下的相機畫面（例如對焦），疊字不攔截事件 |
| 8.14 | 名稱設為 20 個中文字、模板 `nameAndDayCount`、位置 `bottomTrailing` | 文字不超出觀景窗邊界（可縮小字級或換行，但不得被裁切） |

**每個設定檔的位置/主題互相獨立**（PRD FR-8.5）：

| # | 步驟 | 預期結果 |
|---|---|---|
| 8.15 | 把設定檔①的位置改為 `topLeading`、主題改為 `filmStrip` | 觀景窗疊字移到左上、變成等寬白字＋半透明黑底框 |
| 8.16 | 承 8.15，切到設定檔② | ② 套用**它自己的**位置（右下）與主題（經典白），不受 ① 影響 |
| 8.17 | 承 8.16，切回設定檔① | 回到左上 + `filmStrip` |
| 8.18 | 承 8.17，殺掉 App 重開 | ① 仍是左上 + `filmStrip`（設定檔欄位有持久化） |

**跨日行為對照**（PRD FR-8.2，本卡最關鍵的一組）：

| # | 步驟 | 預期結果 |
|---|---|---|
| 8.19 | 停在設定檔①（天數，起始日 2026-01-10），把系統日期改為 **2026-01-11**，切背景再回前景 | 疊字變成 `第 2 天`（天數遞增是**正確**行為） |
| 8.20 | 承 8.19，切到設定檔②（日期） | 疊字為 **`2026.01.11`**，**不是** `第 2 天`、**不是** `2026.01.10` |

**依賴**：TASK-04、TASK-05、TASK-07

---

## TASK-09：OverlayRenderer（疊字烘焙引擎）

**目標**
實作 PRD §6.2 硬約束：把疊字繪製進 `UIImage` 的像素。這是純函式，可脫離相機獨立測試。

**範圍**
- `Services/OverlayRenderer.swift`
- 介面：`func bake(image: UIImage, text: String, theme: OverlayTheme, position: OverlayPosition) -> UIImage?`
- 以 `UIGraphicsImageRenderer` 在**原始像素尺寸**的 context 繪製（`format.scale = 1`，`size` 為 `image.size * image.scale`）
- 正確處理 `UIImage.imageOrientation`：先把圖正規化成 `.up` 再繪製
- 字級、邊距、對齊規則必須與 TASK-08 的預覽層**共用同一組計算函式**
- **禁止**任何「保留原圖」「另存圖層」「寫 metadata」的做法

**驗收標準**

單元測試（`-only-testing:DaysCamTests/OverlayRendererTests`）：

| # | 步驟 | 預期結果 |
|---|---|---|
| 9.1 | 產生一張 1200×1600 的**純白** `UIImage`，用 `classicWhite` 主題、`bottomTrailing`、文字 `第 10 天` 呼叫 `bake` | 回傳非 nil，且輸出尺寸為 1200×1600（與輸入相同） |
| 9.2 | 承 9.1，取輸出圖右下角區域（x: 900–1150, y: 1350–1550）的像素 | 至少有 1 個像素的 RGB 與純白 `(255,255,255)` 差距 > 30（證明有東西被畫上去） |
| 9.3 | 承 9.1，取輸出圖**左上角**區域（x: 0–100, y: 0–100）的像素 | 全部仍為純白（證明沒畫錯位置） |
| 9.4 | 改用 `topLeading` 重跑 | 左上角區域有非白像素，右下角區域全白 |
| 9.5 | 傳入 `imageOrientation == .right` 的圖（模擬直向拍攝） | 輸出圖的 `imageOrientation == .up`，尺寸為旋轉後的正確尺寸，文字未被旋轉 90 度（可用像素分佈驗證：`bottomTrailing` 的非白像素落在旋轉後圖的右下角） |
| 9.6 | 對同一張圖連續 `bake` 100 次 | 不崩潰、不記憶體爆掉（Xcode Memory Report 峰值 < 500MB） |
| 9.7 | 對 4032×3024 的圖 `bake` | 在 iPhone 實機上耗時 < 500ms（用 `XCTClock` 或 `measure` 量測） |
| 9.8 | 以空字串 `""` 呼叫 `bake` | 回傳的圖與輸入圖**像素完全相同**（什麼都不畫，不畫出空底框）。這是空名稱退化的安全網 |

靜態檢查：

| # | 步驟 | 預期結果 |
|---|---|---|
| 9.9 | 執行 `grep -rni "watermark\|originalImage\|CGImageDestinationAddImage" DaysCam/Services/OverlayRenderer.swift` | 無結果 |
| 9.10 | 執行 `grep -rn "UIGraphicsImageRenderer" DaysCam/Services/OverlayRenderer.swift` | 有結果（確認用的是像素繪製，不是 view 圖層疊加） |

**依賴**：TASK-04、TASK-05

---

## TASK-10：拍照 → 烘焙 → 存相簿

**目標**
串起完整拍照流程，落實 PRD §6.1（快門當下時間）與 §6.2（烘焙）兩條硬約束。

**範圍**
- 快門按鈕觸發 `AVCapturePhotoOutput.capturePhoto`
- `AVCapturePhotoCaptureDelegate` 取得 `UIImage` 後：
  1. **當場重新呼叫 `TemplateRenderer` 渲染文字**（不得沿用畫面快取的字串，PRD §6.4）
  2. 呼叫 `OverlayRenderer.bake`，樣式取自**目前設定檔**的 `position` / `themeID`
  3. 以 `PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpegData, options: nil) }` 存檔
- 相簿權限請求層級為 `PHAccessLevel.addOnly`（PRD A-7）
- 存檔成功：顯示 Toast「已儲存」＋左下角縮圖，1.5 秒後淡出，**不跳轉預覽頁**
- 存檔期間快門鍵 disabled
- 不建立自訂相簿（PRD A-20）

**驗收標準**（需**實機**）

**A. 預設設定檔（首次安裝就能拍）**

| # | 步驟 | 預期結果 |
|---|---|---|
| 10.1 | 全新安裝，系統日期設為 2026-01-10，允許權限後直接按快門（不做任何設定） | 1.5 秒內出現「已儲存」Toast 與左下角縮圖，**畫面停留在相機畫面**（不跳轉） |
| 10.2 | 打開系統「照片」App，看最新一張 | 照片右下角印著 **`第 1 天`**，白字帶黑色陰影。**照片上沒有任何名稱、品牌字樣或「未命名」**（PRD A-4） |
| 10.3 | 承 10.2，在「照片」App 對該張照片點「編輯」 | 疊字無法被移除、無法被拖曳（證明是像素而非圖層） |
| 10.4 | 承 10.2，把該照片 AirDrop 到另一台裝置（或 Mac）後開啟 | 疊字仍在，文字仍是 `第 1 天`（PRD G-4） |
| 10.5 | 切到設定檔②（日期），拍照 | 照片上印著 `2026.01.10` |
| 10.6 | 把系統日期改為 **2026-01-11**，在設定檔①（天數）拍一張、在設定檔②（日期）拍一張 | ① 的照片印 `第 2 天`；② 的照片印 `2026.01.11`。先前拍的照片內容**不變**（已烘焙） |

**B. 各模板與邊界**

| # | 步驟 | 預期結果 |
|---|---|---|
| 10.7 | 設定檔起始日 2025-01-15、系統日期 2026-03-20、模板 `unitConverted`，拍照 | 照片上印著 `1 年 2 個月 5 天` |
| 10.8 | 同 10.7 但模板改 `dateAndDayCount` | 照片上印著 `2026.03.20　第 430 天` |
| 10.9 | 同 10.7 但模板改 `nameAndDayCount`、名稱「小寶」 | 照片上印著 `小寶 第 430 天` |
| 10.10 | 同 10.9 但把名稱**清空**後拍照 | 照片上印著 `第 430 天`，**開頭沒有多餘空白**（PRD FR-2.8） |
| 10.11 | 系統日期設為起始日當天，規則「當天算第 1 天」，拍照 | 照片上印著 `第 1 天` |
| 10.12 | 同 10.11 但規則改「當天算第 0 天」，拍照 | 照片上印著 `第 0 天` |
| 10.13 | 起始日 2024-02-28、系統日期 2024-03-01、規則「當天算第 1 天」，拍照 | 照片上印著 `第 3 天`（閏年，2/29 有被算進去） |
| 10.14 | 起始日 2025-12-31、系統日期 2026-01-01、規則「當天算第 1 天」，拍照 | 照片上印著 `第 2 天`（跨年） |

**C. 通用**

| # | 步驟 | 預期結果 |
|---|---|---|
| 10.15 | 直向（portrait）握持拍照 | 照片方向正確，文字**沒有**被旋轉 90 度 |
| 10.16 | 橫向（landscape）握持拍照 | 照片方向正確，文字方向正確 |
| 10.17 | 檢查照片解析度 | 與裝置原生拍照解析度相同（例如 iPhone 16 主鏡頭 4032×3024），未被縮小 |
| 10.18 | 日期模式下把位置設為 `topLeading`、主題設為 `filmStrip`，拍照 | 照片左上角印著當天日期，樣式為等寬白字＋半透明黑色圓角底框（設定檔的外觀欄位有套用到烘焙層） |
| 10.19 | 首次拍照時拒絕相簿權限 | 出現錯誤提示，文案包含「這張照片尚未儲存」與「前往設定」按鈕；不崩潰 |
| 10.20 | 承 10.19，到設定開啟「加入照片」權限 → 回 App 再拍一張 | 存檔成功 |
| 10.21 | 快速連按快門 5 次 | 存下 5 張照片（或明確拒絕多餘觸發），不崩潰、不出現重複 Toast 疊加 |
| 10.22 | 拍完後檢查系統「照片」App 的相簿清單 | **沒有**新增名為「DaysCam」的自訂相簿（PRD A-20） |

**依賴**：TASK-07、TASK-09

---

## TASK-11：顯示設定面板（模板／位置／主題）

**目標**
實作 PRD S-4：視覺層設定的 bottom sheet，含即時預覽。**不得**把模式、起始日、起算規則放進來（PRD FR-5.5）。

**範圍**
- `Views/DisplaySettingsSheet.swift`，以 `.sheet` + `presentationDetents` 呈現
- 三個區塊：模板（6 選 1，清單顯示套用後的實際文字）、位置（3×3 九宮格按鈕）、主題（5 選 1，顯示樣式縮圖）
- 任何變更**即時**寫回**目前設定檔**並持久化
- **日期模式下的模板區塊**：仍顯示全部 6 種，但只有 `dateOnly` 可選且恆為選中狀態，其餘 5 種為 disabled 並附說明文字「這個設定檔是日期模式，改成天數模式才能使用」
- 變更時觀景窗疊字即時更新（不需關閉面板）

**驗收標準**（系統日期 2026-01-10）

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.1 | 在相機畫面點設定入口 | 從底部滑出設定面板，觀景窗仍可見（半高 detent） |
| 11.2 | 檢視面板內容 | 只有「模板／位置／主題」三個區塊，**沒有**模式、沒有起算規則、沒有起始日、沒有名稱 |
| 11.3 | 在天數設定檔（起始日 2026-01-01）下檢視模板區塊 | 恰好 6 個選項，每個顯示「套用後的實際文字」（`dayCountOnly` 那列顯示 `第 10 天`） |
| 11.4 | 位置區塊 | 呈現 3×3 共 9 個按鈕，當前選中的有明顯視覺標記 |
| 11.5 | 主題區塊列出的選項數 | 恰好 5 個，每個都顯示該主題的樣式縮圖（不是純文字清單） |
| 11.6 | 點模板 `dateOnly` | 面板**不關閉**，背後觀景窗的疊字立即變成 `2026.01.10` |
| 11.7 | 點位置 `topLeading` | 面板不關閉，觀景窗疊字立即移到左上角 |
| 11.8 | 點主題 `retroOrange` | 面板不關閉，觀景窗疊字立即變成橘黃色等寬字體 |
| 11.9 | 關閉面板 → 殺掉 App → 重開 | 模板／位置／主題三項設定都保持在剛才選的值 |

**日期模式下的設定面板**：

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.10 | 切到設定檔②（日期）→ 開啟設定面板 → 檢視模板區塊 | 仍列出 6 個選項；`dateOnly` 為選中狀態，其餘 5 個為 disabled（灰階／不可點），並顯示說明文字提到需改成天數模式 |
| 11.11 | 在 11.10 的狀態下點擊 `dayCountOnly` | **沒有任何反應**：模板不變、觀景窗疊字仍是日期、不跳錯誤、不崩潰 |
| 11.12 | 日期模式下點位置 `topLeading`、主題 `filmStrip` | 兩者都立即套用，面板不關閉 |
| 11.13 | 承 11.12 → 殺掉 App → 重開 → 回到設定檔② | 位置仍為左上、主題仍為 `filmStrip` |

**每個設定檔各自獨立**：

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.14 | 承 11.13，切到設定檔① | ① 套用**它自己的**模板／位置／主題，不受 ② 影響 |
| 11.15 | 把 ① 的位置設為 `middleCenter`、主題設為 `softPink` → 切到 ② → 再切回 ① | ② 仍是左上 + `filmStrip`；① 仍是置中 + `softPink`。兩者完全不互相覆蓋 |

**依賴**：TASK-03、TASK-04、TASK-05、TASK-08

---

## TASK-12：首次啟動流程與啟動狀態還原

**目標**
實作 PRD §2.2 的首次啟動流程（**自動種下兩個預設設定檔，直接進相機畫面顯示「第 1 天」**）與啟動狀態還原。

**範圍**
- App 啟動時呼叫 `ProfileStore.load()`：
  - 檔案不存在 → 種下兩個預設設定檔（TASK-03 已實作），`lastUsedProfileID` 指向 ①
  - 檔案存在 → 依 `lastUsedProfileID` 套用；指向不存在的 id 時退回**清單第一筆**
- App 啟動一律進入**相機畫面**（PRD S-1），絕不停在任何表單頁
- **不得**有「首次啟動建立設定檔頁」這個啟動落點
- 相機權限在進入相機畫面時才請求（PRD A-3）

**驗收標準**

**A. 全新安裝（本卡的核心判準）**

| # | 步驟 | 預期結果 |
|---|---|---|
| 12.1 | 從裝置刪除 App → 重新安裝 → 設定裝置系統日期為 **2026-01-10** → 開啟 App | **直接進入相機畫面**。**沒有**歡迎頁、**沒有**教學頁、**沒有**建立設定檔頁、**沒有**任何需要填寫的表單 |
| 12.2 | 承 12.1，觀察啟動瞬間 | 唯一跳出的是**相機權限**系統彈窗（PRD A-3）；**沒有**相簿權限彈窗 |
| 12.3 | 承 12.2，點「允許」 | 觀景窗顯示即時畫面，疊字為 **`第 1 天`**（右下角、白字黑陰影） |
| 12.4 | 承 12.3，仔細檢視疊字 | 疊字**恰好**是 `第 1 天` 三個字加數字，**沒有**任何名稱前綴、**沒有**「天數相機」「DaysCam」「未命名」等字樣（PRD A-4） |
| 12.5 | 承 12.3，**不做任何其他操作**直接按快門 | 拍照成功（相簿權限彈窗此時才出現，允許後存檔成功）。**從安裝到拍出第一張照片，全程沒有填過任何表單**（PRD G-1） |
| 12.6 | 承 12.5，用 Xcode 下載 App 容器，檢查 `Application Support/DaysCam/profiles.json` | 恰好 2 筆設定檔；第 1 筆 `name` 為**空字串**、`mode` 為 `dayCount`、`startDate` 為 2026-01-10；第 2 筆 `name` 為 `日期`、`mode` 為 `date`、無 `startDate` |
| 12.7 | 承 12.5，開啟設定檔清單 | 看得到 2 列，第 2 列是「日期」。**使用者不需任何說明就能發現「也可以只印日期」**（PRD G-6） |

**B. 跨日行為（兩種模式的分野）**

| # | 步驟 | 預期結果 |
|---|---|---|
| 12.8 | 承 12.5，把系統日期改為 **2026-01-11** → 殺掉 App → 重開 | 疊字為 **`第 2 天`**。這是天數設定檔的**正確**行為（起始日 2026-01-10，第 2 天） |
| 12.9 | 承 12.8，切到設定檔②（日期） | 疊字為 **`2026.01.11`**。**不是** `第 2 天`、**不是** `2026.01.10`。這一條驗證日期模式沒有被實作成「起始日 = 今天的天數設定檔」（PRD FR-8.2） |

**C. 啟動狀態還原**

| # | 步驟 | 預期結果 |
|---|---|---|
| 12.10 | 建立設定檔「小寶 / 2026-01-01 / 當天算第 1 天」 | 建立完自動切到「小寶」並回到相機畫面（PRD FR-1.10） |
| 12.11 | 承 12.10，殺掉 App 重開（系統日期 2026-01-11） | 直接進入相機畫面，套用「小寶」，疊字為 `第 11 天` |
| 12.12 | 在清單選設定檔②（日期）→ 殺掉 App 重開 | 直接進入相機畫面，套用日期模式，疊字為當天日期 |
| 12.13 | 刪除目前選取的設定檔 → 殺掉 App 重開 | 進入相機畫面，套用清單中仍存在的某一筆，不崩潰、不停在空白畫面 |
| 12.14 | 用 Xcode 把 `UserDefaults` 的 `lastUsedProfileID` 手動改成一個不存在的 UUID → 重開 App | 進入相機畫面，套用**清單第一筆**，不崩潰、不顯示錯誤提示（PRD §7.3） |

**D. 靜態檢查**

| # | 步驟 | 預期結果 |
|---|---|---|
| 12.15 | 執行 `grep -rn "CameraProfile(" DaysCam/ \| grep -vi "test"` | 建立 `CameraProfile` 的位置只有兩處：`ProfileStore` 的種預設值邏輯，以及使用者主動新增設定檔的路徑（ProfileEditView 的儲存動作）。**沒有**在渲染或拍照路徑上臨時建立設定檔的程式碼（PRD FR-8.2） |

**依賴**：TASK-06、TASK-07

---

## TASK-13：相機畫面快速切換設定檔

**目標**
實作 PRD FR-1.4：不離開相機畫面就能切換目前使用的設定檔。

**範圍**
- 相機畫面頂部放置**目前設定檔名稱**按鈕，點擊展開選單（`Menu` 或橫向 `ScrollView` 膠囊列）
- 選單列出所有設定檔，順序同清單；空名稱顯示「未命名」，並附模式標示
- 切換後即時更新觀景窗疊字，並更新 `lastUsedProfileID`
- 選單中提供「管理設定檔」入口，導向 TASK-06 的清單頁

**驗收標準**（系統日期 2026-01-10）

| # | 步驟 | 預期結果 |
|---|---|---|
| 13.1 | 全新安裝後看相機畫面頂部 | 顯示「未命名」（設定檔①的空名稱佔位）＋天數模式標示 |
| 13.2 | 點頂部按鈕展開選單 | 列出 2 項：「未命名（天數）」「日期（日期）」，外加「管理設定檔」入口 |
| 13.3 | 選「日期」 | 選單關閉，頂部變「日期」，觀景窗疊字在 1 秒內變為 `2026.01.10` |
| 13.4 | 承 13.3，殺掉 App 重開 | 直接套用「日期」設定檔 |
| 13.5 | 再建立兩個設定檔：「小寶 / 2026-01-01 / dayOne / `nameAndDayCount`」、「紀念日 / 2025-06-15 / dayZero / `nameAndDayCount`」 | 清單與選單都變成 4 項 |
| 13.6 | 切到「小寶」 | 頂部顯示「小寶」，疊字為 `小寶 第 10 天` |
| 13.7 | 切到「紀念日」 | 頂部顯示「紀念日」，疊字為 `紀念日 第 209 天`（2025-06-15 → 2026-01-10 相差 209 天，dayZero 不加 1） |
| 13.8 | 在選單中點「管理設定檔」 | 導向設定檔清單頁 |
| 13.9 | 只剩 1 個設定檔時點頂部按鈕 | 選單仍可開啟（至少含該設定檔與「管理設定檔」入口），不崩潰 |
| 13.10 | 在日期設定檔下把系統日期改為 2026-01-11 → 切背景再回前景 | 疊字變為 `2026.01.11` |

> QA 備註：13.7 的 209 天請自行複核——2025-06-15 到 2026-01-10：6 月剩 15 天、7 月 31、8 月 31、9 月 30、10 月 31、11 月 30、12 月 31、1 月 10 天 = 209。

**依賴**：TASK-06、TASK-08

---

## TASK-14：跨午夜／回前景疊字刷新

**目標**
落實 PRD §6.4：App 停在相機畫面跨過午夜時，疊字必須更新；且烘焙時一律重算。兩種模式都要。

**範圍**
- 監聽 `NSNotification.Name.NSCalendarDayChanged`
- 監聽 `UIApplication.willEnterForegroundNotification`
- 兩者皆觸發疊字重算
- 確認 TASK-10 的烘焙流程是**當場重算**而非讀取畫面快取（此卡需加上防回歸的單元測試或註解說明）

**驗收標準**

**A. 天數設定檔**

| # | 步驟 | 預期結果 |
|---|---|---|
| 14.1 | 設定檔：起始日 2026-01-01 / dayOne / `dayCountOnly`。系統日期設為 **2026-01-10 23:59**，App 停在相機畫面 | 疊字顯示 `第 10 天` |
| 14.2 | 承 14.1，等待跨過午夜（或手動把系統時間往前撥到 2026-01-11 00:01）**不要離開 App** | 疊字在 60 秒內自動變成 `第 11 天` |
| 14.3 | 承 14.1，把 App 切到背景 → 改系統日期為 2026-01-11 → 切回 App | 疊字立即為 `第 11 天` |
| 14.4 | 承 14.1（疊字仍顯示 `第 10 天`），在**不觸發任何刷新**的情況下把系統日期改為 2026-01-11 後立刻按快門 | 存下的照片必須是 `第 11 天`（證明烘焙時有重算，不是沿用畫面快取） |
| 14.5 | 單元測試：注入 now = 2026-01-10 產生一次文字，改注入 now = 2026-01-11 後再呼叫烘焙路徑 | 烘焙使用的文字為 `第 11 天`，不是 `第 10 天` |

**B. 日期設定檔**

| # | 步驟 | 預期結果 |
|---|---|---|
| 14.6 | 切到日期設定檔，系統日期設為 2026-01-10 23:59，App 停在相機畫面 | 疊字顯示 `2026.01.10` |
| 14.7 | 承 14.6，跨過午夜（或手動撥到 2026-01-11 00:01）**不要離開 App** | 疊字在 60 秒內自動變成 `2026.01.11`（**不是**變成「第 2 天」） |
| 14.8 | 承 14.6（疊字仍顯示 `2026.01.10`），把系統日期改為 2026-01-11 後在畫面刷新前立刻按快門 | 存下的照片必須是 `2026.01.11` |

> QA 備註：14.4 與 14.8 是本卡最關鍵的兩條，也最容易被實作漏掉。若它們 fail 但 14.2/14.3/14.7 pass，代表刷新做了但烘焙仍用快取，必須退回。

**依賴**：TASK-08、TASK-10

---

## TASK-15：錯誤處理與提示統一

**目標**
把 PRD §7.3 的所有錯誤情境收斂成一致的提示元件，避免各處自行 `print` 或靜默失敗。

**範圍**
- `Views/ToastView.swift` + 一個集中的錯誤/提示呈現機制
- 涵蓋 PRD §7.3 表格全部情境
- 資料損毀提示（PRD A-30）：App 啟動時若 `didRecoverFromCorruption == true`，顯示一次性 alert「設定檔讀取失敗，已重設。」
- 起始日在未來時，天數模式疊字顯示「尚未開始」（PRD §7.2）

**驗收標準**

| # | 步驟 | 預期結果 |
|---|---|---|
| 15.1 | 拒絕相機權限後進入相機畫面 | 顯示權限引導畫面（TASK-07 已做），此卡確認文案與「前往設定」按鈕行為一致 |
| 15.2 | 拒絕相簿權限後拍照 | 顯示錯誤提示，文案完整包含「無法存入相簿」「這張照片尚未儲存」「前往設定」三個要素 |
| 15.3 | 把裝置儲存空間塞到近乎全滿後拍照（或用 mock 讓 `PHPhotoLibrary` 回傳 error） | 顯示「儲存失敗：{系統錯誤描述}。請確認裝置儲存空間後再試一次。」，不崩潰、不顯示「已儲存」 |
| 15.4 | 用 Xcode 的檔案容器把 `profiles.json` 內容改成 `這不是 JSON` → 重開 App（系統日期 2026-03-05） | 出現 alert「設定檔讀取失敗，已重設。」；關掉 alert 後**停在相機畫面**，疊字為 `第 1 天`（重新種下的預設設定檔，起始日 2026-03-05），使用者可立即拍照；再次重開 App **不再**出現此 alert |
| 15.5 | 承 15.4，用 Xcode 下載 App 容器 | `Application Support/DaysCam/` 下存在 `profiles.json.corrupt-*` 檔案，內容為 `這不是 JSON`；`profiles.json` 為重新種下的 2 筆 |
| 15.6 | 天數設定檔起始日 2026-01-01，手動把裝置系統日期往回撥到 2025-12-01 | 觀景窗疊字顯示 `尚未開始`；6 種模板逐一切換，全部都顯示 `尚未開始` |
| 15.7 | 承 15.6，按下快門 | 拍照成功，照片上印的是 `尚未開始`（不阻擋拍照） |
| 15.8 | 承 15.6（系統日期 2025-12-01），切到日期設定檔 | 疊字顯示 `2025.12.01`，**不是** `尚未開始`（日期模式沒有起始日，不可能尚未開始，PRD §7.1） |
| 15.9 | 執行 `grep -rn "print(" DaysCam/ \| grep -v "//"` | 無結果，或全部都在 `#if DEBUG` 內（錯誤不得只靠 print 吞掉） |

**依賴**：TASK-03、TASK-10

---

## TASK-16：Info.plist 權限文案與端對端驗收腳本

**目標**
補齊上架必要的權限說明文案，並產出一份完整的端對端手動驗收腳本供 QA 每次回歸使用。

**範圍**
- `DaysCam/Info.plist` 加入：
  - `NSCameraUsageDescription`：`DaysCam 需要使用相機來拍照，並把天數或日期即時印在照片上。`
  - `NSPhotoLibraryAddUsageDescription`：`DaysCam 需要權限才能把拍好的照片存進你的相簿。`
  - **不得**加入 `NSPhotoLibraryUsageDescription`（讀取權限，MVP 不需要，PRD A-7）
- 新增 `docs/QA_CHECKLIST.md`：把 TASK-06 ~ TASK-15 的手動驗收條目整理成一份可勾選的回歸清單，最前面寫清楚前置準備（如何改系統日期、需要哪些測試設定檔）
  - **必須包含獨立的「首次安裝」章節**（12.1–12.9）與「兩種模式對照」章節（8.19/8.20、10.6、12.8/12.9、14.7）
- 在 `docs/PRD.md` 的文件索引加上 `QA_CHECKLIST.md` 連結

**驗收標準**

| # | 步驟 | 預期結果 |
|---|---|---|
| 16.1 | 執行 `plutil -p DaysCam/Info.plist \| grep Usage` | 恰好兩筆：`NSCameraUsageDescription`、`NSPhotoLibraryAddUsageDescription` |
| 16.2 | 執行 `plutil -p DaysCam/Info.plist \| grep NSPhotoLibraryUsageDescription` | 無結果 |
| 16.3 | 實機首次進入相機畫面 | 系統彈窗文案與 `NSCameraUsageDescription` 一字不差 |
| 16.4 | 實機首次存檔 | 系統彈窗文案與 `NSPhotoLibraryAddUsageDescription` 一字不差，且彈窗為「加入照片」層級（不是「完整取用」） |
| 16.5 | 開啟 `docs/QA_CHECKLIST.md` | 涵蓋 TASK-06 ~ TASK-15 的所有手動條目，每條可獨立勾選，開頭有「前置準備」章節說明如何調整裝置系統日期，且有「首次安裝」與「兩種模式對照」兩個獨立章節 |
| 16.6 | 找一位沒參與開發的人（或新的 QA teammate session），只給他 `docs/QA_CHECKLIST.md`，請他跑完一輪 | 全程不需要回頭問任何問題（**這是本卡的核心判準**） |
| 16.7 | 執行完整測試套件 `xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -destination 'platform=iOS Simulator,name=iPhone 16' test` | 全數通過，exit code 0 |
| 16.8 | 執行 `grep -rni "exif\|DateTimeOriginal\|fileCreation" DaysCam/` | 無結果（最終確認 PRD §6.1 硬約束未被違反） |
| 16.9 | **端對端冒煙測試**：刪除 App → 重新安裝 → 系統日期設為 2026-01-10 → 開啟 → 允許相機權限 → 直接按快門 → 允許相簿權限 | 全程**沒有填過任何表單**，相簿最新一張照片右下角印著 `第 1 天`，且照片上**沒有任何品牌或佔位字樣**（PRD G-1、A-4） |
| 16.10 | 承 16.9，系統日期改為 2026-01-11 → 重開 App → 拍一張 → 切到「日期」設定檔 → 再拍一張 | 第一張印 `第 2 天`，第二張印 `2026.01.11`（PRD G-6、FR-8.2） |

**依賴**：TASK-01 ~ TASK-15 全部

---

## 附錄：本文件中的假設

| # | 假設 | 所在任務 |
|---|---|---|
| T-04-a | `unitConverted` 在 0 天時顯示 `0 天`；`weekCount` 在 dayZero 第 0 天時顯示 `第 1 週` | TASK-04 |
| T-04-b | 名稱 trim 後為空即視為空名稱，一併退化為不印前綴 | TASK-04 |

其餘假設請見 [`docs/PRD.md` 附錄 A](./PRD.md#附錄-a假設清單索引)（共 30 條）。
