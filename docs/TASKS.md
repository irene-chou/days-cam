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
  TASK-03 DaysTimer 模型與 JSON 持久化      ← 01   ※含日期模式偏好儲存
  TASK-04 TemplateRenderer（6 模板＋日期模式）← 01, 02
  TASK-05 OverlayTheme（5 組主題定義）       ← 01

第 2 層
  TASK-06 計時器列表與編輯頁 UI              ← 03   ※含「日期模式」列
  TASK-07 相機權限與 AVFoundation 觀景窗     ← 01
  TASK-09 OverlayRenderer（疊字烘焙引擎）    ← 04, 05

第 3 層
  TASK-08 觀景窗即時疊字圖層                 ← 04, 05, 07
  TASK-10 拍照 → 烘焙 → 存相簿               ← 07, 09
  TASK-11 顯示設定面板（模板/位置/主題）      ← 03, 04, 05, 08

第 4 層
  TASK-12 首次啟動流程與空狀態               ← 06, 07
  TASK-13 相機畫面快速切換模式／計時器        ← 06, 08
  TASK-14 跨午夜／回前景天數刷新             ← 08, 10
  TASK-15 錯誤處理與提示統一                 ← 03, 10

第 5 層
  TASK-16 Info.plist 權限文案與端對端驗收腳本 ← 全部
```

**建議平行分工**：Dev A 走邏輯線（01 → 02 → 04 → 05 → 09），Dev B 走 UI/相機線（01 → 07 → 03 → 06）。兩線在 TASK-08 / TASK-10 匯流。

> **關於「日期模式」（PRD §3.8）**：最容易被實作錯的一點是 **PRD FR-8.2：禁止用「自動建立一個 `startDate` = 今天的計時器」來實作日期模式**——那樣做隔天會變成「第 2 天」而不是當天日期。TASK-03（3.17）、TASK-04（4.23 / 4.25）、TASK-12（12.5 / 12.6 / 12.16）都有專門針對這點的檢查條目，請勿略過。

---

## TASK-01：專案分層骨架與共用型別

**目標**
建立 `CLAUDE.md` 要求的「UI 元件／業務邏輯／資料層分開資料夾」結構，並定義後續所有任務共用的列舉型別，避免各 teammate 各自定義造成衝突。

**範圍**
- 建立資料夾：`DaysCam/Models/`、`DaysCam/Services/`、`DaysCam/Views/`、`DaysCamTests/`
- 在 `Models/` 新增以下型別（皆為 `String` raw value 的 `enum`，皆 `Codable`、`CaseIterable`）：
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
| 1.4 | 執行 `grep -rn "case dayOne\|case dayZero" DaysCam/Models/` | 找得到 `CountingRule` 的兩個 case |
| 1.5 | 執行 `grep -c "case " DaysCam/Models/TemplateID.swift`（或該型別所在檔） | 恰好 6 個 case |
| 1.6 | 執行 `grep -c "case " DaysCam/Models/OverlayPosition.swift`（或該型別所在檔） | 恰好 9 個 case |
| 1.7 | 執行 `grep -c "case " DaysCam/Models/ThemeID.swift`（或該型別所在檔） | 恰好 5 個 case |
| 1.8 | 執行 `grep -rn '!' DaysCam/Models/ \| grep -v '!=' \| grep -v '//'` | 無 force-unwrap（`CLAUDE.md` 規定） |

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
  }
  ```
- 計算規則（PRD §3.5 / §6.3）：
  - `rawDayDifference` = `calendar.dateComponents([.day], from: startOfDay(起始日), to: startOfDay(now())).day`
  - `dayOne` → `rawDayDifference + 1`；`dayZero` → `rawDayDifference`
  - `calendarBreakdown` = `calendar.dateComponents([.year, .month, .day], from: startOfDay(起始日), to: startOfDay(now()))`，**不套用 +1**
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
| 2.20 | 2024-02-29 | 2025-02-28 | **(0, 11, 30)**（PRD A-22：接受 `Calendar` 原生行為，本案例用來鎖住此行為） |
| 2.21 | 2024-02-29 | 2025-03-01 | **(1, 0, 1)** |

時區驗證：

| # | 步驟 | 預期結果 |
|---|---|---|
| 2.22 | 同一組輸入（起始日 2026-01-01、now 為 UTC 時間 `2026-01-09T20:00:00Z`），分別以 `Asia/Taipei`（UTC+8，當地為 01-10 04:00）與 `America/New_York`（UTC-5，當地為 01-09 15:00）建立 calculator | Taipei → `dayCount(dayOne) == 10`；New_York → `dayCount(dayOne) == 9`。兩者都正確反映「當地日期」 |

靜態檢查：

| # | 步驟 | 預期結果 |
|---|---|---|
| 2.23 | 執行 `grep -rni "exif\|DateTimeOriginal\|creationDate\|fileCreation" DaysCam/` | **無任何結果**（PRD §6.1 硬約束） |
| 2.24 | 執行 `grep -rn "Date()" DaysCamTests/` | **無任何結果**（測試不得依賴真實時間） |

**依賴**：無（可與 TASK-01 平行，但合併順序建議在 TASK-01 之後）

---

## TASK-03：DaysTimer 模型與 JSON 持久化

**目標**
實作計時器資料模型與檔案持久化層，讓上層 UI 有穩定的 CRUD 介面。

**範圍**
- `Models/DaysTimer.swift`：依 PRD §4.1 定義欄位。`startDate` 型別為 `DateComponents`（只含 year/month/day），**不是 `Date`**（PRD A-20）
- `Services/TimerStore.swift`：
  - 讀寫 `Application Support/DaysCam/timers.json`
  - 寫入採原子寫入
  - CRUD：`load()`、`add(_:)`、`update(_:)`、`delete(id:)`
  - 檔案損毀處理：改名為 `timers.json.corrupt-{unix timestamp}`，以空清單啟動，並曝露一個 `didRecoverFromCorruption: Bool` 供 UI 顯示提示（PRD A-24）
- 數量上限 20（PRD FR-1.7）：`add` 在已達 20 筆時回傳錯誤
- **App 層級狀態（PRD §4.2）**，皆存於 `UserDefaults`：
  - `lastUsedTimerID: UUID?`，預設 `nil`。**`nil` 是合法且預設的值，代表日期模式**（PRD FR-8.1）
  - `dateModePosition: OverlayPosition`，預設 `.bottomTrailing`
  - `dateModeTheme: ThemeID`，預設 `.classicWhite`
  - 讀取 `lastUsedTimerID` 時，若其指向的計時器**已不存在**，必須回傳 `nil`（＝日期模式），**不得**退回第一筆計時器
  - `dateModePosition` / `dateModeTheme` 與任何 `DaysTimer.position` / `.themeID` **完全獨立**，互不覆蓋（PRD A-25）

**驗收標準**

執行 `xcodebuild ... test -only-testing:DaysCamTests/TimerStoreTests`（測試需使用暫時目錄，不得污染真實沙盒）：

| # | 步驟 | 預期結果 |
|---|---|---|
| 3.1 | 新建 store（目錄為空）→ `load()` | 回傳空陣列，不拋錯，`didRecoverFromCorruption == false` |
| 3.2 | `add` 一筆 `name: "小寶"`, `startDate: 2025-01-15`, `rule: .dayOne` → 建立新 store 指向同一目錄 → `load()` | 回傳 1 筆，所有欄位與寫入時完全相同（`id`、`name`、`startDate` 的 year/month/day、`countingRule`、`templateID`、`position`、`themeID`） |
| 3.3 | `add` 一筆後 `update` 把 `name` 改為 `"小寶貝"` → 重新 `load()` | 回傳 1 筆，`name == "小寶貝"`，`id` 不變，`updatedAt` 大於 `createdAt` |
| 3.4 | `add` 兩筆 → `delete` 第一筆的 id → `load()` | 回傳 1 筆，且為第二筆的 id |
| 3.5 | 連續 `add` 20 筆 | 全部成功 |
| 3.6 | 在 3.5 之後再 `add` 第 21 筆 | 回傳錯誤（不是 crash、不是靜默忽略），`load()` 仍為 20 筆 |
| 3.7 | 手動把 `timers.json` 內容覆寫成 `"這不是 JSON"` → 建立新 store → `load()` | 回傳空陣列，`didRecoverFromCorruption == true`，且同目錄下存在一個檔名符合 `timers.json.corrupt-*` 的檔案，內容為 `"這不是 JSON"` |
| 3.8 | 設定 `lastUsedTimerID` 為某筆 id → 重新讀取 | 回傳同一個 id |
| 3.9 | `delete` 掉 `lastUsedTimerID` 指向的計時器 → 讀取 `lastUsedTimerID` | 回傳 `nil`（不得指向已刪除的 id） |
| 3.10 | 檢查 `startDate` 的型別 | 執行 `grep -n "startDate" DaysCam/Models/DaysTimer.swift`，型別為 `DateComponents`，**不是 `Date`** |
| 3.11 | 全新的 store（`UserDefaults` 未曾寫入）→ 讀取 `lastUsedTimerID` | 回傳 `nil`，且**不拋錯、不 fallback 到任何計時器**（PRD §4.2：`nil` ＝日期模式，是正常狀態） |
| 3.12 | `add` 兩筆計時器 T1、T2 → 把 `lastUsedTimerID` 設為 T1 → 手動把 `UserDefaults` 的 `lastUsedTimerID` 改成一個隨機不存在的 UUID → 讀取 | 回傳 `nil`（**不是** T1、**不是** T2、**不是**第一筆） |
| 3.13 | 全新的 store → 讀取 `dateModePosition` 與 `dateModeTheme` | 分別為 `.bottomTrailing` 與 `.classicWhite` |
| 3.14 | 設定 `dateModePosition = .topLeading` → 重新建立 store 讀取 | 回傳 `.topLeading` |
| 3.15 | `add` 一筆計時器（`position` 為預設 `.bottomTrailing`）→ 把 `dateModePosition` 設為 `.topLeading` → `load()` 該計時器 | 該計時器的 `position` 仍為 `.bottomTrailing`（證明兩者獨立，PRD A-25） |
| 3.16 | 承 3.15，反向操作：把該計時器的 `position` 改為 `.middleCenter` 並 `update` → 讀取 `dateModePosition` | 仍為 `.topLeading`（證明反向也不互相覆蓋） |
| 3.17 | 執行 `grep -rn "dateMode" DaysCam/Services/TimerStore.swift` | 找得到 `dateModePosition` 與 `dateModeTheme`，且**找不到**任何建立 `DaysTimer` 的程式碼與之相關（PRD FR-8.2：禁止用自動建立計時器實作日期模式） |

**依賴**：TASK-01

---

## TASK-04：TemplateRenderer（6 種模板 ＋ 日期模式）

**目標**
把「計時器 + 當下時間」渲染成要疊印的字串，涵蓋 PRD §3.2 的 6 種模板，**外加日期模式的渲染路徑**（PRD §3.8）。

**範圍**
- `Services/TemplateRenderer.swift`
- 介面（兩條路徑）：
  ```swift
  /// Renders the overlay text for a timer.
  func render(timer: DaysTimer, calculator: DayCountCalculator) -> String
  /// Renders the overlay text for date mode: always the current date, no timer involved.
  func renderDateMode(calculator: DayCountCalculator) -> String
  ```
- `renderDateMode` **不接受 `DaysTimer` 參數**，輸出恆為 `yyyy.MM.dd` 格式的**當下日期**（PRD FR-8.3 / FR-2.7）
- **禁止**把 `renderDateMode` 實作成「建立一個 `startDate` = 今天的臨時 `DaysTimer` 再丟給 `render`」（PRD FR-8.2）。日期模式沒有起始日這個概念
- 起始日在未來（`dayCount <= 0` 且 `rawDayDifference < 0`）時，**所有模板**一律回傳 `"尚未開始"`（PRD §7.2 / A-23）。此規則**不適用**日期模式——日期模式不可能出現「尚未開始」
- 附 XCTest

**驗收標準**

基準情境：`name: "小寶"`、`startDate: 2025-01-15`、`rule: .dayOne`、注入 now = `2026-03-20 10:00`（Asia/Taipei）。此時 `dayCount = 430`、`calendarBreakdown = (1, 2, 5)`。

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
| 4.9 | start 2025-01-01, now 2026-01-01, dayOne | `unitConverted` | `1 年` （月、天皆為 0 時省略） |
| 4.10 | start 2025-01-01, now 2026-03-01, dayOne | `unitConverted` | `1 年 2 個月`（天為 0 時省略） |
| 4.11 | start 2026-01-01, now 2026-01-08, dayOne（`dayCount` = 8） | `weekCount` | `第 2 週又 1 天` |
| 4.12 | start 2026-01-01, now 2026-01-07, dayOne（`dayCount` = 7） | `weekCount` | `第 1 週`（餘數為 0 時省略「又 N 天」） |
| 4.13 | start 2026-01-01, now 2026-01-14, dayOne（`dayCount` = 14） | `weekCount` | `第 2 週` |

起始日在未來：

| # | 情境 | 預期輸出 |
|---|---|---|
| 4.14 | start 2026-12-01, now 2026-09-19，**6 種模板全測** | 6 種模板都回傳 `尚未開始` |

`dayZero` 規則：

| # | 情境 | `templateID` | 預期輸出 |
|---|---|---|---|
| 4.15 | start 2026-01-01, now 2026-01-01, **dayZero** | `dayCountOnly` | `第 0 天` |
| 4.16 | start 2026-01-01, now 2026-01-01, **dayZero** | `weekCount` | `第 1 週`（0 天視為第 1 週、餘 0） |

**日期模式渲染路徑**（PRD §3.8）：

| # | 步驟 | 預期輸出 |
|---|---|---|
| 4.17 | 注入 now = `2026-03-20 10:00`，呼叫 `renderDateMode` | `2026.03.20` |
| 4.18 | 注入 now = `2026-01-01 00:00:01`，呼叫 `renderDateMode` | `2026.01.01` |
| 4.19 | 注入 now = `2026-01-01 23:59:59`，呼叫 `renderDateMode` | `2026.01.01`（同一天內時分秒不影響輸出） |
| 4.20 | 注入 now = `2026-01-02 00:00:01`，呼叫 `renderDateMode` | `2026.01.02`（跨午夜後輸出跟著變） |
| 4.21 | **同一個** renderer 先以 now = `2026-01-10` 呼叫 `renderDateMode`，再以 now = `2026-01-11` 呼叫 | 依序為 `2026.01.10`、`2026.01.11`。**證明日期模式每次都重取當下日期，沒有把任何日期記下來**（PRD FR-8.3） |
| 4.22 | 建立一個 `startDate` = 2026-01-10、`rule: .dayOne`、`templateID: .dateOnly` 的計時器，注入 now = `2026-01-10` → 呼叫 `render`；同時呼叫 `renderDateMode` | 兩者都是 `2026.01.10`（當天相同） |
| 4.23 | 承 4.22，把 now 改為 `2026-01-11` → 分別呼叫 `render`（同一個計時器，模板改 `dayCountOnly`）與 `renderDateMode` | `render` → `第 2 天`；`renderDateMode` → `2026.01.11`。**這一條是日期模式的核心判準**：日期模式隔天仍印日期，不會變成「第 2 天」（PRD FR-8.2 的理由） |
| 4.24 | 以 `Asia/Taipei` 與 `America/New_York` 兩個 calendar，注入同一個 UTC 時間 `2026-01-09T20:00:00Z`，各呼叫 `renderDateMode` | Taipei → `2026.01.10`；New_York → `2026.01.09` |

靜態檢查：

| # | 步驟 | 預期結果 |
|---|---|---|
| 4.25 | 執行 `grep -n "renderDateMode" -A 20 DaysCam/Services/TemplateRenderer.swift` | `renderDateMode` 的實作內**沒有**建立 `DaysTimer`、**沒有**呼叫 `render(timer:)`、**沒有**用到 `CountingRule`（PRD FR-8.2） |

> **這裡是我的假設（T-04-a）**：4.7 的「0 天」與 4.16 的「dayZero 第 0 天時 weekCount 顯示第 1 週」都是邊界文案決策，PRD 未明列。若 Lead 有其他偏好請直接覆蓋。

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

## TASK-06：計時器列表與編輯頁 UI

**目標**
實作 PRD S-2 / S-3：計時器的新增、編輯、刪除、選擇，**以及日期模式的選取**。

**範圍**
- `Views/TimerListView.swift`、`Views/TimerEditView.swift`
- **列表第一列固定為「日期模式」**（PRD A-26）：標題「日期模式」、副標「只印當天日期」，可被選取，**無編輯入口、左滑無刪除動作**。此列即使一個計時器都沒有也必須存在
- 選取日期模式 ＝ 把 `lastUsedTimerID` 設為 `nil`（PRD FR-8.1）
- 編輯頁欄位（**只有邏輯層**，PRD FR-5.5）：名稱（`TextField`，1–20 字元）、起始日（`DatePicker`，`displayedComponents: .date`，`in: ...Date()` 上限為今天）、起算規則（`Picker`，segmented）
- 編輯頁顯示即時預覽：「今天會顯示為：第 N 天」（PRD FR-5.6）
- 建立新計時器成功後，**自動把該新計時器設為目前選取**（PRD A-27）
- 刪除需二次確認（`confirmationDialog`）；刪除最後一個計時器後**自動切回日期模式**（PRD FR-1.8）
- 已達 20 筆時，「新增」按鈕 disabled 並顯示說明文字（日期模式那一列**不計入** 20 的上限）

**驗收標準**（在 iPhone 16 模擬器上手動執行）

| # | 步驟 | 預期結果 |
|---|---|---|
| 6.1 | 開啟計時器列表 → 點「＋」→ 名稱留空 | 「儲存」按鈕為 disabled 狀態 |
| 6.2 | 名稱輸入 21 個字元（例如貼上 `一二三四五六七八九十一二三四五六七八九十壹`） | 輸入框內只保留前 20 字，第 21 字進不去（不是儲存時才報錯） |
| 6.3 | 名稱輸入「小寶」、起始日選 2026-01-01、規則選「當天算第 1 天」→ 儲存 | 回到列表，出現一列「小寶」 |
| 6.4 | 在編輯頁把起始日設為 2026-01-01、規則「當天算第 1 天」，並把**裝置系統日期設為 2026-01-10**（設定 → 一般 → 日期與時間 → 關閉「自動設定」） | 編輯頁的預覽文字顯示「今天會顯示為：第 10 天」 |
| 6.5 | 承 6.4，把規則切到「當天算第 0 天」（不儲存，只切 Picker） | 預覽文字**即時**變為「今天會顯示為：第 9 天」 |
| 6.6 | 打開起始日 `DatePicker`，嘗試選擇明天的日期 | 明天以後的日期無法選取（灰階／不可點） |
| 6.7 | 在列表對「小寶」左滑 → 刪除 | 出現確認對話框，文案包含計時器名稱；點「取消」後該列仍在 |
| 6.8 | 重複 6.7 並點「刪除」 | 該列消失；殺掉 App 重開，該列仍不存在 |
| 6.9 | 建立到第 20 個計時器 | 「＋」按鈕變 disabled，畫面顯示說明文字（內容需提到上限 20）。此時列表共 **21 列**（1 列日期模式 + 20 列計時器），日期模式那一列不計入上限 |
| 6.10 | 在列表點選某個計時器 | 該列出現選取標記，且回到相機畫面後套用的是這個計時器（若 TASK-13 尚未完成，至少 `lastUsedTimerID` 已更新，可用 TASK-03 的測試手段確認） |

**日期模式相關**（PRD §3.8）：

| # | 步驟 | 預期結果 |
|---|---|---|
| 6.11 | 全新安裝後開啟計時器列表（尚無任何計時器） | 列表共 **1 列**：標題「日期模式」、副標「只印當天日期」，且該列帶有選取標記 |
| 6.12 | 對「日期模式」那一列左滑 | **沒有**刪除動作出現（不可刪除，PRD FR-8.7） |
| 6.13 | 點擊「日期模式」那一列 | **不會**進入編輯頁（不可編輯）；僅切換選取狀態 |
| 6.14 | 承 6.11，建立計時器「小寶 / 2026-01-01 / 當天算第 1 天」 | 列表變成 2 列（日期模式 + 小寶），**選取標記自動落在「小寶」**（PRD A-27），不是留在日期模式 |
| 6.15 | 承 6.14，點「日期模式」那一列 | 選取標記移回「日期模式」，「小寶」**仍在列表中沒有被刪除**（日期模式是永久可選的模式，PRD FR-1.10） |
| 6.16 | 承 6.15，殺掉 App 重開並回到列表 | 選取標記仍在「日期模式」 |
| 6.17 | 承 6.15（目前選取日期模式），刪除「小寶」 | 列表剩 1 列（日期模式），選取標記仍在日期模式，不崩潰 |
| 6.18 | 建立兩個計時器 A、B → 選取 A → 刪除 **B**（非選取中的那個） | 選取標記**仍在 A**，不會被切走（PRD §3.8 對照表） |
| 6.19 | 承 6.18，刪除 A（＝刪除最後一個計時器） | 列表剩 1 列（日期模式），選取標記**自動移到日期模式**，且**不會**跳出「建立計時器頁」（PRD FR-1.8） |

**依賴**：TASK-03

---

## TASK-07：相機權限與 AVFoundation 觀景窗

**目標**
實作 PRD S-1 的觀景窗與 S-5 權限引導畫面。此卡**不含**疊字與拍照，只負責「把畫面顯示出來 + 權限狀態機」。

**範圍**
- `Services/CameraService.swift`：包裝 `AVCaptureSession`、`AVCaptureDeviceInput`、`AVCapturePhotoOutput`（output 先建好但不使用）
- `Views/CameraPreviewView.swift`：`UIViewRepresentable` 包 `AVCaptureVideoPreviewLayer`
- 拍攝比例固定 4:3（PRD A-18），觀景窗以 4:3 顯示
- 前／後鏡頭切換按鈕
- 權限狀態機（PRD §2.3）：`.notDetermined` / `.authorized` / `.denied` / `.restricted`
- 監聽 `AVCaptureSessionWasInterrupted` / `InterruptionEnded`
- 監聽 `willEnterForeground` 重新檢查權限
- 模擬器 fallback（PRD A-7）：`#if targetEnvironment(simulator)` 顯示純色佔位背景，快門 disabled 並標示「模擬器不支援拍照」
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
- `Views/OverlayTextView.swift`：吃**已渲染好的文字** + `OverlayTheme` + `OverlayPosition`，輸出 SwiftUI view。**不要**讓這個 view 直接吃 `DaysTimer`——日期模式沒有 `DaysTimer`，文字來源應由上層決定（`render` 或 `renderDateMode`），view 只負責排版
- 上層依目前模式選擇文字與樣式來源：
  - 日期模式（`lastUsedTimerID == nil`）→ `renderDateMode` ＋ `dateModePosition` ＋ `dateModeTheme`
  - 計時器模式 → `render(timer:)` ＋ 該計時器的 `position` ＋ `themeID`
- 9 宮格對齊規則（PRD FR-3.3）：邊距 = 觀景窗短邊 × 4%；左側格靠左、右側格靠右、中間格置中
- 字級 = 觀景窗短邊 × 5.5%（與烘焙層共用 TASK-05 的 `fontSize(forShortEdge:)`）
- 疊字**不得**攔截觸控（`allowsHitTesting(false)`）

**驗收標準**（模擬器可執行，疊字不依賴實體相機）

| # | 步驟 | 預期結果 |
|---|---|---|
| 8.1 | 計時器：起始日 2026-01-01、規則「當天算第 1 天」、模板 `dayCountOnly`；裝置系統日期設為 2026-01-10 | 觀景窗上顯示 `第 10 天` |
| 8.2 | 承 8.1，模板改 `dateOnly` | 觀景窗上顯示 `2026.01.10` |
| 8.3 | 承 8.1，模板改 `nameAndDayCount`，計時器名稱為「小寶」 | 觀景窗上顯示 `小寶 第 10 天` |
| 8.4 | 位置設為 `topLeading` | 文字出現在觀景窗左上角，且左邊界與上邊界距離皆約為短邊的 4%（截圖量測，誤差 < 1%） |
| 8.5 | 位置設為 `bottomTrailing` | 文字出現在右下角，右邊界與下邊界距離約為短邊的 4% |
| 8.6 | 位置設為 `middleCenter` | 文字水平與垂直皆置中 |
| 8.7 | 依序套用 9 個位置 | 9 個位置文字都完整顯示在觀景窗內，**沒有任何一個被裁切** |
| 8.8 | 主題設為 `classicWhite`，把相機對著**純白牆面**（或模擬器佔位背景設為白色） | 文字仍清晰可辨（有黑色陰影襯底） |
| 8.9 | 主題設為 `minimalDark`，把相機對著**全黑畫面** | 文字仍清晰可辨（有白色底框襯底） |
| 8.10 | 5 組主題各套用一次 | 每組的字體、顏色、襯底效果肉眼可區分，無任何一組是純文字無襯底 |
| 8.11 | 用手指點擊疊字所在位置 | 觸控穿透到底下的相機畫面（例如對焦），疊字不攔截事件 |
| 8.12 | 名稱設為 20 個中文字、模板 `nameAndDayCount`、位置 `bottomTrailing` | 文字不超出觀景窗邊界（可縮小字級或換行，但不得被裁切） |

**日期模式**（PRD §3.8）：

| # | 步驟 | 預期結果 |
|---|---|---|
| 8.13 | 全新安裝、尚無任何計時器、裝置系統日期設為 2026-01-10，進入相機畫面 | 觀景窗疊字為 `2026.01.10`，位置右下、主題經典白（日期模式預設值） |
| 8.14 | 承 8.13，把 `dateModePosition` 改為 `topLeading`（透過設定面板，TASK-11） | 疊字移到左上角 |
| 8.15 | 承 8.14，殺掉 App 重開 | 疊字仍在左上角（日期模式偏好有持久化，PRD FR-8.5） |
| 8.16 | 承 8.14（日期模式位置＝左上），建立計時器「小寶」並切到它 | 「小寶」套用的是**它自己的**預設位置右下，**不是**左上（PRD A-25：兩者獨立） |
| 8.17 | 承 8.16，切回日期模式 | 疊字回到左上角（日期模式的偏好沒有被計時器覆蓋） |
| 8.18 | 日期模式下，把裝置系統日期從 2026-01-10 改為 **2026-01-11** 並讓畫面刷新（切背景再回前景） | 疊字變成 `2026.01.11`（**不是**「第 2 天」，PRD FR-8.2） |

> **這裡是我的假設（T-08-a）**：8.12 的「過長文字」處理方式（縮小字級 vs 換行 vs 截斷）PRD 未規定。**Dev 實作時請在 PR 描述中說明你採用哪一種，並回報 Lead 確認。**

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

靜態檢查：

| # | 步驟 | 預期結果 |
|---|---|---|
| 9.8 | 執行 `grep -rni "watermark\|originalImage\|CGImageDestinationAddImage" DaysCam/Services/OverlayRenderer.swift` | 無結果 |
| 9.9 | 執行 `grep -rn "UIGraphicsImageRenderer" DaysCam/Services/OverlayRenderer.swift` | 有結果（確認用的是像素繪製，不是 view 圖層疊加） |

**依賴**：TASK-04、TASK-05

---

## TASK-10：拍照 → 烘焙 → 存相簿

**目標**
串起完整拍照流程，落實 PRD §6.1（快門當下時間）與 §6.2（烘焙）兩條硬約束。

**範圍**
- 快門按鈕觸發 `AVCapturePhotoOutput.capturePhoto`
- `AVCapturePhotoCaptureDelegate` 取得 `UIImage` 後：
  1. **當場重新呼叫 `TemplateRenderer` 計算文字**（不得沿用畫面快取的字串，PRD §6.4）
  2. 呼叫 `OverlayRenderer.bake`
  3. 以 `PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpegData, options: nil) }` 存檔
- 相簿權限請求層級為 `PHAccessLevel.addOnly`（PRD A-6）
- 存檔成功：顯示 Toast「已儲存」＋左下角縮圖，1.5 秒後淡出，**不跳轉預覽頁**
- 存檔期間快門鍵 disabled
- 不建立自訂相簿（PRD A-16）

**驗收標準**（需**實機**）

| # | 步驟 | 預期結果 |
|---|---|---|
| 10.1 | 計時器：起始日 2026-01-01、規則「當天算第 1 天」、模板 `dayCountOnly`、位置 `bottomTrailing`、主題 `classicWhite`；裝置系統日期設為 2026-01-10。按下快門 | 1.5 秒內出現「已儲存」Toast 與左下角縮圖，**畫面停留在相機畫面**（不跳轉） |
| 10.2 | 打開系統「照片」App，看最新一張 | 照片右下角印著 `第 10 天`，白字帶黑色陰影 |
| 10.3 | 承 10.2，在「照片」App 對該張照片點「編輯」 | 疊字無法被移除、無法被拖曳（證明是像素而非圖層） |
| 10.4 | 承 10.2，把該照片 AirDrop 到另一台裝置（或 Mac）後開啟 | 疊字仍在，文字仍是 `第 10 天`（PRD G-4） |
| 10.5 | 把起始日改成 2025-01-15、系統日期設為 2026-03-20、模板 `unitConverted`，拍照 | 照片上印著 `1 年 2 個月 5 天` |
| 10.6 | 同 10.5 但模板改 `dateAndDayCount` | 照片上印著 `2026.03.20　第 430 天` |
| 10.7 | 系統日期設為 **2026-01-01**（＝起始日），規則「當天算第 1 天」，拍照 | 照片上印著 `第 1 天` |
| 10.8 | 同 10.7 但規則改「當天算第 0 天」，拍照 | 照片上印著 `第 0 天` |
| 10.9 | 起始日設為 2024-02-28、系統日期設為 2024-03-01、規則「當天算第 1 天」，拍照 | 照片上印著 `第 3 天`（閏年，2/29 有被算進去） |
| 10.10 | 起始日設為 2025-12-31、系統日期設為 2026-01-01、規則「當天算第 1 天」，拍照 | 照片上印著 `第 2 天`（跨年） |
| 10.11 | 直向（portrait）握持拍照 | 照片方向正確，文字**沒有**被旋轉 90 度 |
| 10.12 | 橫向（landscape）握持拍照 | 照片方向正確，文字方向正確 |
| 10.13 | 檢查照片解析度 | 與裝置原生拍照解析度相同（例如 iPhone 16 主鏡頭 4032×3024），未被縮小 |
| 10.14 | 首次拍照時拒絕相簿權限 | 出現錯誤提示，文案包含「這張照片尚未儲存」與「前往設定」按鈕；不崩潰 |
| 10.15 | 承 10.14，到設定開啟「加入照片」權限 → 回 App 再拍一張 | 存檔成功 |
| 10.16 | 快速連按快門 5 次 | 存下 5 張照片（或明確拒絕多餘觸發），不崩潰、不出現重複 Toast 疊加 |
| 10.17 | 拍完後檢查系統「照片」App 的相簿清單 | **沒有**新增名為「DaysCam」的自訂相簿（PRD A-16） |

**日期模式拍照**（PRD §3.8 FR-8.8）：

| # | 步驟 | 預期結果 |
|---|---|---|
| 10.18 | 切到日期模式、系統日期設為 2026-01-10、位置 `bottomTrailing`、主題 `classicWhite`，按快門 | 存檔成功；照片右下角印著 **`2026.01.10`**，白字帶黑色陰影 |
| 10.19 | 承 10.18，在「照片」App 對該照片點「編輯」 | 疊字無法移除（同樣是烘焙進像素，日期模式不走特例路徑） |
| 10.20 | 承 10.18，把系統日期改為 **2026-01-11**，在日期模式下再拍一張 | 新照片印著 **`2026.01.11`**；先前那張**仍然**是 `2026.01.10`（已烘焙，不會回溯改變） |
| 10.21 | 承 10.20，檢查兩張照片 | 兩張都**不是** `第 1 天` / `第 2 天`。日期模式永遠印日期（PRD FR-8.2） |
| 10.22 | 日期模式下把位置設為 `topLeading`、主題設為 `filmStrip`，拍照 | 照片左上角印著當天日期，樣式為等寬白字＋半透明黑色圓角底框（FR-8.5 的偏好有套用到烘焙層） |
| 10.23 | 日期模式下直向握持拍照 | 照片方向正確，文字未被旋轉 90 度 |

**依賴**：TASK-07、TASK-09

---

## TASK-11：顯示設定面板（模板／位置／主題）

**目標**
實作 PRD S-4：視覺層設定的 bottom sheet，含即時預覽。**不得**把起算規則放進來（PRD FR-5.5）。

**範圍**
- `Views/DisplaySettingsSheet.swift`，以 `.sheet` + `presentationDetents` 呈現
- 三個區塊：模板（6 選 1，列表顯示套用後的實際文字）、位置（3×3 九宮格按鈕）、主題（5 選 1，顯示樣式縮圖）
- 任何變更**即時**寫回並持久化：計時器模式寫回該 `DaysTimer`；**日期模式寫回 `dateModePosition` / `dateModeTheme`**（PRD FR-8.5、§4.2）
- **日期模式下的模板區塊**（PRD A-28）：仍顯示全部 6 種，但只有 `dateOnly` 可選且恆為選中狀態，其餘 5 種為 disabled 並附說明文字「需要先選擇一個計時器」
- 變更時觀景窗疊字即時更新（不需關閉面板）

**驗收標準**

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.1 | 在相機畫面點設定入口 | 從底部滑出設定面板，觀景窗仍可見（半高 detent） |
| 11.2 | 檢視面板內容 | 只有「模板／位置／主題」三個區塊，**沒有**起算規則、沒有起始日、沒有名稱 |
| 11.3 | 模板區塊列出的選項數 | 恰好 6 個，且每個選項顯示的是「套用後的實際文字」（例如當前是 2026-01-10、起始日 2026-01-01，`dayCountOnly` 那列顯示 `第 10 天`） |
| 11.4 | 位置區塊 | 呈現 3×3 共 9 個按鈕，當前選中的有明顯視覺標記 |
| 11.5 | 主題區塊列出的選項數 | 恰好 5 個，每個都顯示該主題的樣式縮圖（不是純文字清單） |
| 11.6 | 點模板 `dateOnly` | 面板**不關閉**，背後觀景窗的疊字立即變成 `2026.01.10` |
| 11.7 | 點位置 `topLeading` | 面板不關閉，觀景窗疊字立即移到左上角 |
| 11.8 | 點主題 `retroOrange` | 面板不關閉，觀景窗疊字立即變成橘黃色等寬字體 |
| 11.9 | 關閉面板 → 殺掉 App → 重開 | 模板／位置／主題三項設定都保持在剛才選的值 |
| 11.10 | 建立第二個計時器，設定不同的模板／位置／主題，來回切換兩個計時器 | 每個計時器各自保留自己的設定，不會互相覆蓋 |

**日期模式下的設定面板**（PRD §3.8 / A-28）：

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.11 | 全新安裝（日期模式）→ 開啟設定面板 → 檢視模板區塊 | 仍列出 6 個選項；`dateOnly` 為選中狀態，其餘 5 個為 disabled（灰階／不可點），並顯示說明文字「需要先選擇一個計時器」 |
| 11.12 | 在 11.11 的狀態下點擊 `dayCountOnly` | **沒有任何反應**：模板不變、觀景窗疊字仍是日期、不跳錯誤、不崩潰 |
| 11.13 | 日期模式下點位置 `topLeading` | 面板不關閉，觀景窗疊字立即移到左上角 |
| 11.14 | 日期模式下點主題 `filmStrip` | 面板不關閉，疊字立即變成等寬白字＋半透明黑色圓角底框 |
| 11.15 | 承 11.13 / 11.14 → 關閉面板 → 殺掉 App → 重開 | 日期模式的位置仍為左上、主題仍為 `filmStrip` |
| 11.16 | 承 11.15，建立計時器「小寶」（會自動切到它）→ 開啟設定面板 | 模板區塊 6 個選項**全部可選**（不再 disabled）；「小寶」的位置／主題為其自身預設值（右下／經典白），**不是**日期模式的左上／`filmStrip` |
| 11.17 | 承 11.16，把「小寶」的位置設為 `middleCenter`、主題設為 `softPink` → 切回日期模式 | 日期模式的位置仍為左上、主題仍為 `filmStrip`（PRD A-25：兩者完全獨立） |

**依賴**：TASK-03、TASK-04、TASK-05、TASK-08

---

## TASK-12：首次啟動流程與空狀態

**目標**
實作 PRD §2.2 的首次啟動流程（**直接進日期模式相機畫面**）、啟動狀態還原，以及刪光計時器後的行為。

**範圍**
- App 啟動時一律進入**相機畫面**（PRD S-1），絕不停在任何表單頁。依 `lastUsedTimerID` 決定套用哪個模式：
  - `nil`（含全新安裝、從未選過）→ **日期模式**
  - 有 id 且該計時器存在 → 套用該計時器
  - 有 id 但該計時器**已不存在** → **日期模式**（**不是**退回第一筆；PRD §4.2）
- **不得**在啟動時自動建立任何 `DaysTimer`（PRD FR-8.2）
- **不得**有「首次啟動建立計時器頁」這個啟動落點；建立計時器一律走相機畫面 → 計時器列表 → 編輯頁
- 刪除最後一個計時器後切回日期模式並**留在相機畫面**（PRD FR-1.8）
- 相機權限在進入相機畫面時才請求（PRD A-3）

**驗收標準**

**A. 全新安裝（本卡的核心判準）**

| # | 步驟 | 預期結果 |
|---|---|---|
| 12.1 | 從裝置刪除 App → 重新安裝 → 設定裝置系統日期為 **2026-01-10** → 開啟 App | **直接進入相機畫面**。**沒有**歡迎頁、**沒有**教學頁、**沒有**建立計時器頁、**沒有**任何需要填寫的表單 |
| 12.2 | 承 12.1，觀察啟動瞬間 | 唯一跳出的是**相機權限**系統彈窗（PRD A-3）；**沒有**相簿權限彈窗 |
| 12.3 | 承 12.2，點「允許」 | 觀景窗顯示即時畫面，疊字為 **`2026.01.10`**（右下角、白字黑陰影） |
| 12.4 | 承 12.3，**不做任何其他操作**直接按快門 | 拍照成功（相簿權限彈窗此時才出現，允許後存檔成功）。**從安裝到拍出第一張照片，全程沒有填過任何表單**（PRD G-1） |
| 12.5 | 承 12.4，用 Xcode 下載 App 容器，檢查 `Application Support/DaysCam/` | **不存在** `timers.json`，或存在但內容為空陣列 `[]`。**絕不可**出現任何自動建立的計時器（PRD FR-8.2） |
| 12.6 | 承 12.4，把裝置系統日期改為 **2026-01-11** → 殺掉 App → 重開 | 疊字為 **`2026.01.11`**。**不是** `第 2 天`、**不是** `2026.01.10`。這一條直接驗證「日期模式不是隱藏的計時器」 |

**B. 啟動狀態還原**

| # | 步驟 | 預期結果 |
|---|---|---|
| 12.7 | 承上（日期模式）→ 建立計時器「小寶 / 2026-01-01 / 當天算第 1 天」 | 建立完自動切到「小寶」並回到相機畫面（PRD A-27） |
| 12.8 | 承 12.7，殺掉 App 重開（系統日期 2026-01-11） | 直接進入相機畫面，套用「小寶」，疊字為 `第 11 天` |
| 12.9 | 建立第二個計時器「小花」並在列表選取它 → 殺掉 App 重開 | 直接進入相機畫面，套用「小花」 |
| 12.10 | 在計時器列表選「日期模式」→ 殺掉 App 重開 | 直接進入相機畫面，**套用日期模式**，疊字為當天日期。「小寶」「小花」**都還在**列表裡沒被刪除 |
| 12.11 | 承 12.9（目前選「小花」），刪除「小花」→ 殺掉 App 重開 | 進入相機畫面，套用**日期模式**（疊字為當天日期）。**不是**退回第一筆「小寶」，不崩潰、不停在空白畫面 |
| 12.12 | 用 Xcode 把 `UserDefaults` 的 `lastUsedTimerID` 手動改成一個不存在的 UUID → 重開 App | 進入相機畫面，套用**日期模式**，不崩潰、不顯示錯誤提示（靜默處理，PRD §7.3） |

**C. 刪光計時器**

| # | 步驟 | 預期結果 |
|---|---|---|
| 12.13 | 準備 2 個計時器，選取其中一個 → 逐一刪除到一個都不剩 | 刪掉最後一個的瞬間，**自動切回日期模式**；畫面回到相機畫面，疊字為當天日期。**不會**跳出「建立計時器頁」（PRD FR-1.8） |
| 12.14 | 承 12.13，殺掉 App 重開 | 仍是相機畫面 + 日期模式，不會出現任何表單 |
| 12.15 | 承 12.14，開啟計時器列表 | 只有 1 列「日期模式」，且為選取狀態 |

**D. 靜態檢查**

| # | 步驟 | 預期結果 |
|---|---|---|
| 12.16 | 執行 `grep -rn "DaysTimer(" DaysCam/ \| grep -vi "test"` | 所有建立 `DaysTimer` 的位置都在**使用者主動建立計時器**的路徑上（TimerEditView 的儲存動作）；**沒有**任何在 App 啟動、日期模式、或 store 初始化時建立 `DaysTimer` 的程式碼（PRD FR-8.2） |

**依賴**：TASK-06、TASK-07

---

## TASK-13：相機畫面快速切換模式／計時器

**目標**
實作 PRD FR-1.4：不離開相機畫面就能在**日期模式與各計時器之間**切換。

**範圍**
- 相機畫面頂部放置**目前模式名稱**按鈕，點擊展開選單（`Menu` 或橫向 `ScrollView` 膠囊列）
- 選單內容：**第一項固定為「日期模式」**（PRD A-26），其下列出所有計時器
- 日期模式時，頂部按鈕顯示「日期模式」
- 切換後即時更新觀景窗疊字，並更新 `lastUsedTimerID`（選日期模式時設為 `nil`）
- 選單中提供「管理計時器」入口，導向 TASK-06 的列表頁

**驗收標準**

| # | 步驟 | 預期結果 |
|---|---|---|
| 13.1 | 準備兩個計時器：「小寶 / 2026-01-01 / dayOne」、「紀念日 / 2025-06-15 / dayZero」；系統日期設為 2026-01-10；兩者模板皆 `nameAndDayCount` | — |
| 13.2 | 相機畫面目前為「小寶」 | 頂部顯示「小寶」，觀景窗疊字為 `小寶 第 10 天` |
| 13.3 | 點頂部名稱 → 選「紀念日」 | 選單關閉，頂部變「紀念日」，觀景窗疊字在 1 秒內變為 `紀念日 第 209 天`（2025-06-15 → 2026-01-10 相差 209 天，dayZero 不加 1） |
| 13.4 | 承 13.3，殺掉 App 重開 | 直接套用「紀念日」 |
| 13.5 | 在選單中點「管理計時器」 | 導向計時器列表頁 |
| 13.6 | 只有 1 個計時器時點頂部名稱 | 選單仍可開啟（至少含「日期模式」與「管理計時器」入口），不崩潰 |

**日期模式切換**（PRD §3.8）：

| # | 步驟 | 預期結果 |
|---|---|---|
| 13.7 | 承 13.1，點頂部名稱展開選單 | 選單**第一項**為「日期模式」，其下才是「小寶」「紀念日」 |
| 13.8 | 承 13.7，選「日期模式」 | 選單關閉，頂部顯示「**日期模式**」，觀景窗疊字在 1 秒內變為 `2026.01.10`（不含任何名稱與天數） |
| 13.9 | 承 13.8，殺掉 App 重開 | 直接套用日期模式，頂部仍顯示「日期模式」 |
| 13.10 | 承 13.8，再點頂部 → 選「小寶」 | 頂部變「小寶」，疊字變回 `小寶 第 10 天`（可自由來回切換，PRD FR-1.10） |
| 13.11 | 全新安裝、一個計時器都沒有時點頂部按鈕 | 頂部顯示「日期模式」；選單可開啟，內容為「日期模式」＋「管理計時器」，**不崩潰、不顯示空清單錯誤** |
| 13.12 | 在日期模式下把系統日期改為 2026-01-11 → 切背景再回前景 | 疊字變為 `2026.01.11`（日期模式每次重取當下日期） |

> QA 備註：13.3 的 209 天請自行複核——2025-06-15 到 2026-01-10：6 月剩 15 天、7 月 31、8 月 31、9 月 30、10 月 31、11 月 30、12 月 31、1 月 10 天 = 209。

**依賴**：TASK-06、TASK-08

---

## TASK-14：跨午夜／回前景天數刷新

**目標**
落實 PRD §6.4：App 停在相機畫面跨過午夜時，疊字必須更新；且烘焙時一律重算。

**範圍**
- 監聽 `NSNotification.Name.NSCalendarDayChanged`
- 監聽 `UIApplication.willEnterForegroundNotification`
- 兩者皆觸發疊字重算
- 確認 TASK-10 的烘焙流程是**當場重算**而非讀取畫面快取（此卡需加上防回歸的單元測試或註解說明）

**驗收標準**

| # | 步驟 | 預期結果 |
|---|---|---|
| 14.1 | 計時器：起始日 2026-01-01 / dayOne / `dayCountOnly`。裝置系統日期設為 **2026-01-10 23:59**，App 停在相機畫面 | 疊字顯示 `第 10 天` |
| 14.2 | 承 14.1，等待跨過午夜（或手動把系統時間往前撥到 2026-01-11 00:01）**不要離開 App** | 疊字在 60 秒內自動變成 `第 11 天` |
| 14.3 | 承 14.1，把 App 切到背景 → 改系統日期為 2026-01-11 → 切回 App | 疊字立即為 `第 11 天` |
| 14.4 | 承 14.1（疊字仍顯示 `第 10 天`），在**不觸發任何刷新**的情況下把系統日期改為 2026-01-11 後立刻按快門（若畫面尚未刷新） | 存下的照片必須是 `第 11 天`（證明烘焙時有重算，不是沿用畫面快取） |
| 14.5 | 單元測試：注入 now = 2026-01-10 產生一次文字，改注入 now = 2026-01-11 後再呼叫烘焙路徑 | 烘焙使用的文字為 `第 11 天`，不是 `第 10 天` |
| 14.6 | **日期模式**下：系統日期設為 2026-01-10 23:59，App 停在相機畫面 | 疊字顯示 `2026.01.10` |
| 14.7 | 承 14.6，跨過午夜（或手動撥到 2026-01-11 00:01）**不要離開 App** | 疊字在 60 秒內自動變成 `2026.01.11`（**不是**變成「第 2 天」） |
| 14.8 | 承 14.6（疊字仍顯示 `2026.01.10`），把系統日期改為 2026-01-11 後在畫面刷新前立刻按快門 | 存下的照片必須是 `2026.01.11`（日期模式的烘焙同樣當場重算） |

> QA 備註：14.4 是本卡最關鍵的一條，也最容易被實作漏掉。若 14.4 fail 但 14.2/14.3 pass，代表刷新做了但烘焙仍用快取，必須退回。

**依賴**：TASK-08、TASK-10

---

## TASK-15：錯誤處理與提示統一

**目標**
把 PRD §7.3 的所有錯誤情境收斂成一致的提示元件，避免各處自行 `print` 或靜默失敗。

**範圍**
- `Views/ToastView.swift` + 一個集中的錯誤/提示呈現機制
- 涵蓋 PRD §7.3 表格全部 6 種情境
- 資料損毀提示（PRD A-24）：App 啟動時若 `didRecoverFromCorruption == true`，顯示一次性 alert「計時器資料讀取失敗，已重設。」
- 起始日在未來時，疊字顯示「尚未開始」（PRD §7.2）

**驗收標準**

| # | 步驟 | 預期結果 |
|---|---|---|
| 15.1 | 拒絕相機權限後進入相機畫面 | 顯示權限引導畫面（TASK-07 已做），此卡確認文案與「前往設定」按鈕行為一致 |
| 15.2 | 拒絕相簿權限後拍照 | 顯示錯誤提示，文案完整包含「無法存入相簿」「這張照片尚未儲存」「前往設定」三個要素 |
| 15.3 | 把裝置儲存空間塞到近乎全滿後拍照（或用 mock 讓 `PHPhotoLibrary` 回傳 error） | 顯示「儲存失敗：{系統錯誤描述}。請確認裝置儲存空間後再試一次。」，不崩潰、不顯示「已儲存」 |
| 15.4 | 用 Xcode 的檔案容器把 `timers.json` 內容改成 `這不是 JSON` → 重開 App | 出現 alert「計時器資料讀取失敗，已重設。」；關掉 alert 後**停在相機畫面並套用日期模式**（疊字為當天日期，使用者可立即拍照）；**不會**跳到建立計時器頁；再次重開 App **不再**出現此 alert |
| 15.5 | 承 15.4，用 Xcode 下載 App 容器 | `Application Support/DaysCam/` 下存在 `timers.json.corrupt-*` 檔案，內容為 `這不是 JSON` |
| 15.6 | 建立計時器後，手動把裝置系統日期往回撥到起始日之前（例如起始日 2026-01-01，系統日期設為 2025-12-01） | 觀景窗疊字顯示 `尚未開始`；6 種模板逐一切換，全部都顯示 `尚未開始` |
| 15.7 | 承 15.6，按下快門 | 拍照成功，照片上印的是 `尚未開始`（不阻擋拍照） |
| 15.8 | 承 15.6（系統日期 2025-12-01），切到**日期模式** | 疊字顯示 `2025.12.01`，**不是** `尚未開始`（日期模式沒有起始日，不可能尚未開始，PRD §7.1） |
| 15.9 | 執行 `grep -rn "print(" DaysCam/ \| grep -v "//"` | 無結果，或全部都在 `#if DEBUG` 內（錯誤不得只靠 print 吞掉） |

**依賴**：TASK-03、TASK-10

---

## TASK-16：Info.plist 權限文案與端對端驗收腳本

**目標**
補齊上架必要的權限說明文案，並產出一份完整的端對端手動驗收腳本供 QA 每次回歸使用。

**範圍**
- `DaysCam/Info.plist` 加入：
  - `NSCameraUsageDescription`：`DaysCam 需要使用相機來拍照，並把日期或天數即時印在照片上。`（需同時涵蓋日期模式與計時器模式，故文案講「日期或天數」）
  - `NSPhotoLibraryAddUsageDescription`：`DaysCam 需要權限才能把拍好的照片存進你的相簿。`
  - **不得**加入 `NSPhotoLibraryUsageDescription`（讀取權限，MVP 不需要，PRD A-6）
- 新增 `docs/QA_CHECKLIST.md`：把 TASK-06 ~ TASK-15 的手動驗收條目整理成一份可勾選的回歸清單，並在最前面寫清楚前置準備（如何改系統日期、需要哪些測試計時器）
  - **必須包含獨立的「日期模式」章節**，涵蓋 12.1–12.6 的全新安裝路徑、13.7–13.12 的模式切換、10.18–10.23 的日期模式拍照
- 在 `docs/PRD.md` 的文件索引加上 `QA_CHECKLIST.md` 連結

**驗收標準**

| # | 步驟 | 預期結果 |
|---|---|---|
| 16.1 | 執行 `plutil -p DaysCam/Info.plist \| grep Usage` | 恰好兩筆：`NSCameraUsageDescription`、`NSPhotoLibraryAddUsageDescription` |
| 16.2 | 執行 `plutil -p DaysCam/Info.plist \| grep NSPhotoLibraryUsageDescription` | 無結果 |
| 16.3 | 實機首次進入相機畫面 | 系統彈窗文案與 `NSCameraUsageDescription` 一字不差 |
| 16.4 | 實機首次存檔 | 系統彈窗文案與 `NSPhotoLibraryAddUsageDescription` 一字不差，且彈窗為「加入照片」層級（不是「完整取用」） |
| 16.5 | 開啟 `docs/QA_CHECKLIST.md` | 涵蓋 TASK-06 ~ TASK-15 的所有手動條目，每條可獨立勾選，開頭有「前置準備」章節說明如何調整裝置系統日期，且有獨立的「日期模式」章節 |
| 16.6 | 找一位沒參與開發的人（或新的 QA teammate session），只給他 `docs/QA_CHECKLIST.md`，請他跑完一輪 | 全程不需要回頭問任何問題（**這是本卡的核心判準**） |
| 16.7 | 執行完整測試套件 `xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -destination 'platform=iOS Simulator,name=iPhone 16' test` | 全數通過，exit code 0 |
| 16.8 | 執行 `grep -rni "exif\|DateTimeOriginal\|fileCreation" DaysCam/` | 無結果（最終確認 PRD §6.1 硬約束未被違反） |
| 16.9 | **端對端冒煙測試**：刪除 App → 重新安裝 → 設定系統日期為 2026-01-10 → 開啟 App → 允許相機權限 → 直接按快門 → 允許相簿權限 | 全程**沒有填過任何表單**，相簿最新一張照片右下角印著 `2026.01.10`（PRD G-1） |
| 16.10 | 承 16.9，把系統日期改為 2026-01-11 → 殺掉 App 重開 → 拍一張 | 新照片印著 `2026.01.11`。App 從未自動建立過任何計時器（可用 12.5 的容器檢查複核） |

**依賴**：TASK-01 ~ TASK-15 全部

---

## 附錄：本文件中的假設

| # | 假設 | 所在任務 |
|---|---|---|
| T-04-a | `unitConverted` 在 0 天時顯示 `0 天`；`weekCount` 在 dayZero 第 0 天時顯示 `第 1 週` | TASK-04 |
| T-08-a | 過長文字的處理方式（縮小字級／換行／截斷）未定，由 Dev 在 PR 中提案 | TASK-08 |

其餘假設請見 [`docs/PRD.md` 附錄 A](./PRD.md#附錄-a假設清單索引)（共 28 條，其中 A-25 ~ A-28 為日期模式相關）。
