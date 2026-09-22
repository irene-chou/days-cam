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

**撰寫與執行驗收指令的規則**：表格儲存格裡的 shell 指令**不得含有 `|` 字元**。

Markdown 表格用 `|` 分欄，所以儲存格內的 `|` 必須跳脫成 `\|`。但 agent 讀的是**原始檔**，照原文複製執行時：

- **`grep -E` 裡的 `\|` 是字面的管線字元，不是交替**——檢查永遠找不到東西，**靜默地假通過**。本專案曾有 1.16、2.27、5.3a、9.10 四條驗收因此從來不可能失敗
- **當 shell 管線用的 `\|` 會變成傳給前一個指令的參數**——管線直接斷掉，例如 `plutil -p file \| grep X` 會吐出整份檔案而 `grep` 根本沒執行

所以一律改寫成不含 `|` 的形式：多個 pattern 用 `grep -e A -e B`，管線改成單一指令的等價寫法。**新增驗收條目時，請先用一個「確實含有違規」的檔案測試它，確認它真的會失敗**——只驗證乾淨程式碼會通過，證明不了檢查有效。

**兩個最容易做錯的地方**：

1. **PRD FR-2.17：日期的渲染路徑永不讀取 `startDate`。** 若用「起始日＝今天」來近似日期顯示，隔天會變成「第 2 天」。TASK-04（4.44 跨日對照／4.47 實作檢視）有專門的檢查。
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

## 檔案所有權

**一個檔案只有一個擁有者。需要改別人的檔案時，回報 Lead，不要自己動手。**

| 擁有者 | 檔案 |
|---|---|
| core-dev | `Models/`（全部）、`Services/DayCountCalculator.swift`、`Services/ProfileStore.swift`、`Services/TemplateRenderer.swift`、`Services/OverlayRenderer.swift`、`Services/OverlayMetrics.swift`、`Services/PhotoSaver.swift`、`Services/CameraService.swift`、`DaysCamTests/Unit/` |
| ui-dev | `Views/`（全部，含 `CameraScreen.swift`）、`DaysCamApp.swift` |
| qa | `DaysCamTests/Acceptance/`。**不得修改任何產品程式碼**，發現 bug 回報不自己修 |
| Lead 獨佔 | `project.yml`、`.gitignore`、`README.md`、`docs/**`、`CLAUDE.md` |

> **`Views/CameraScreen.swift` 是六張卡的共同寫入點**
>
> TASK-08、10、11、12、13、14 都要改它。TASK-01 已建立骨架，目前仍是佔位畫面。**擁有者是 ui-dev**（見上表）——`Views/` 全部歸它，沒有另一個「相機線 Dev」角色。
>
> **這五張卡因此無法平行，是專案的序列化瓶頸。** 這是接受的取捨，不要為了平行化而拆這個檔案。
>
> **接線時機**：`CameraScreen` 要等 `Services/CameraService.swift`（TASK-07，core-dev）落地才能真正組裝觀景窗。在那之前它是 TASK-01 的佔位畫面，**往上加入口按鈕沒有意義**——等 TASK-07／08 整合時一併接。
>
> 因此 **TASK-11 的驗收 11.1（「相機畫面點設定入口」）屬於整合階段**，不在 TASK-11 的 PR 範圍內。TASK-11 交付的是 `DisplaySettingsSheet` 與 `DisplaySettingsModel` 本體＋可單元測試的狀態邏輯；入口按鈕與 `.sheet` 修飾子在 `CameraScreen` 接線那張卡補上。**交付 TASK-11 時必須在 PR 描述裡寫明這點**，不要宣稱 11.1 已通過。
>
> 這五張卡因此**無法平行**，是專案的序列化瓶頸。這是接受的取捨，不要為了平行化而拆這個檔案。

> **測試目錄分兩處**：`DaysCamTests/Unit/` 由 core-dev 隨實作一起寫（TDD，`CLAUDE.md` 要求新功能附測試）；`DaysCamTests/Acceptance/` 由 qa 獨立撰寫，負責比對 TASKS.md 的驗收表是否被完整覆蓋、補齊缺口、並執行全部 A 級驗收。qa **不重寫** core-dev 已覆蓋的案例，但要驗證覆蓋率並獨立複核結果。
>
> **UI 相關的 A 級驗收靠 view model 而非 XCUITest。** `xcrun simctl` 沒有任何點擊能力（只有 `ui appearance` 與 `io screenshot`），無法執行互動序列。因此 ui-dev 必須把狀態與文字組裝邏輯放進**可觀察的 view model**（`Views/` 底下，但與 View 分離），讓 qa 用一般單元測試驗證；View 本身只負責畫面。真正需要實機互動的條目歸 B 級。這同時呼應 `CLAUDE.md`「避免所有邏輯塞在單一 View 檔案裡」。

> **`project.yml` 只有 Lead 能改。** 因為 `sources` 是資料夾 glob，新增 `.swift` 檔**不需要**動它。若你認為需要改（例如加依賴），先回報 Lead。

---

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
4. **權限字串**（**寫進 `project.yml` 的 `info.properties`，不是直接改 `Info.plist`**——該檔由 XcodeGen 產生，手改會被覆蓋）：
   - `NSCameraUsageDescription`：`DaysCam 需要使用相機來拍照，並把天數印在照片上。`
   - `NSPhotoLibraryAddUsageDescription`：`DaysCam 需要權限才能把拍好的照片存進你的相簿。`
   - **不得**加入 `NSPhotoLibraryUsageDescription`（讀取權限，MVP 不需要）
5. **分層資料夾**：`DaysCam/Models/`、`DaysCam/Services/`、`DaysCam/Views/`、`DaysCamTests/`
6. **共用型別**（`Models/`，皆為 `String` raw value 的 `enum`，皆 `Codable`、`CaseIterable`，附英文文件註解）：
   - `CountingRule`：`dayOne`、`dayZero`
   - `DisplayUnit`：`year`、`month`、`week`、`day`
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
| 1.5 | `git ls-files -- '*xcodeproj*'` | **無結果**（已移出版控） |
| 1.6 | `grep 'xcodeproj' .gitignore` | 有結果 |
| 1.7 | `grep -c 'xcodegen' README.md` | 結果 > 0 |
| 1.8 | `grep -c 'UsageDescription</key>' DaysCam/Info.plist` | 恰好兩筆：`NSCameraUsageDescription`、`NSPhotoLibraryAddUsageDescription` |
| 1.9 | `grep 'NSPhotoLibraryUsageDescription</key>' DaysCam/Info.plist` | **無結果** |
| 1.10 | `ls DaysCam/Models DaysCam/Services DaysCam/Views DaysCamTests` | 四個資料夾都存在 |
| 1.11 | `xcodegen generate && xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -destination 'platform=iOS Simulator,name=iPhone 16' build` | 編譯成功，exit code 0 |
| 1.12 | `xcodebuild ... test` | 測試 target 可執行（此時 0 個測試亦可），exit code 0 |
| 1.13 | `grep -c 'case ' DaysCam/Models/DisplayUnit.swift` | 恰好 **4**（`year`／`month`／`week`／`day`）。疊字內容改由正交開關組成，**沒有** `TemplateID` 這個型別（PRD §3.2） |
| 1.13a | `grep -rn 'TemplateID' DaysCam/` | **無結果**。模板列舉已廢除 |
| 1.14 | `grep -c 'case ' DaysCam/Models/OverlayPosition.swift` | 恰好 9 |
| 1.15 | `grep -c 'case ' DaysCam/Models/ThemeID.swift` | 恰好 5 |
| 1.16 | `grep -rnE -e 'try!' -e 'as!' -e '[A-Za-z0-9_)\]]![^=]' -e '[A-Za-z0-9_)\]]!$' DaysCam/Models/` | 無 force-unwrap／force-try／force-cast（`CLAUDE.md` 規定）。**注意**：不要用 `grep -rn '!'`——那會連邏輯否定 `!flag` 一起判失敗，逼程式碼寫成 `flag == false`。本條只抓後綴 `!`（force-unwrap）與 `try!`／`as!` |

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
      func monthDayBreakdown(from startDate: DateComponents) -> (months: Int, days: Int)
      /// Today's date in this calculator's calendar and time zone.
      func currentDateComponents() -> DateComponents
  }
  ```
- 計算規則（PRD §3.3、§6.3）：
  - `rawDayDifference` = `calendar.dateComponents([.day], from: startOfDay(起始日), to: startOfDay(now())).day`
  - `dayOne` → `raw + 1`；`dayZero` → `raw`
  - `calendarBreakdown` = `calendar.dateComponents([.year,.month,.day], from: startOfDay(起始日), to: startOfDay(now()))`，**不加 1**
  - `monthDayBreakdown` = `calendar.dateComponents([.month,.day], ...)`，**不加 1**。月軌的「14 個月」**無法**從年軌的 `(1, 2, 5)` 用算術推出來，必須另外向 `Calendar` 要。放在這裡而非 renderer，是為了不讓 `startOfDay` 正規化邏輯在兩處各寫一份
  - `currentDateComponents` = `now()` 在當地時區的 y/m/d（供日期顯示與「新設定檔起始日預設今天」使用）
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
| 2.26 | `grep -rni -e exif -e DateTimeOriginal -e creationDate -e fileCreation DaysCam/` | **無結果**（PRD §6.1 硬約束） |
| 2.27 | `grep -rnE -e '=[[:space:]]*Date\(\)' -e '\bDate\(\)\)' -e '\{ Date\(\) \}' DaysCamTests/` | **無結果**（測試不得依賴真實時間）。**注意**：不要用 `grep -rn "Date()"`——那會抓到測試方法名稱（例如 `testRendersJustTheDate()`）與註解，逼測試作者為了過 grep 去改命名 |
| 2.28 | 檢視 `DAYSCAM_FAKE_TODAY` 的實作 | 整段包在 `#if DEBUG` 內 |
| 2.29 | `grep -rnE -e '^[^/]*Calendar = \.current\b' DaysCam/` | **無結果**。所有 `Calendar` 預設參數一律用 `.autoupdatingCurrent`（PRD §6.3）。`.current` 存進屬性後時區會凍結在建構當下，使用者換時區後天數會差一天。本條涵蓋整個 `DaysCam/`（含 `Views/`），不只 `Services/` |

**驗收 — B. 需人類實機**：無。

**依賴**：TASK-01

---

## TASK-03：CameraProfile 與 JSON 持久化

**目標**
實作設定檔資料模型與持久化層，含首次啟動種預設設定檔，以及 PRD §4.1 兩條不變條件的強制驗證。

**範圍**

- `Models/CameraProfile.swift`：依 PRD §4.1。`startDate` 為 `DateComponents`（**非** optional、**非** `Date`）；`showDayCount` 預設 `true`、`showDate`／`showName`／`useAgeWording` 預設 `false`、`largestUnit`／`smallestUnit` 預設 `.day`
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
| 3.2 | 檢查該筆所有欄位 | `name == "預設"`、`startDate == (2026,1,10)`、`countingRule == .dayOne`、`showDayCount == true`、`showDate == false`、`showName == false`、`largestUnit == .day`、`smallestUnit == .day`、`useAgeWording == false`、`position == .bottomTrailing`、`themeID == .classicWhite` |
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

## TASK-04：TemplateRenderer（顯示開關 × 單位區間）

**目標**
把「設定檔 ＋ **呼叫端傳入的拍攝時刻**」渲染成疊印字串，涵蓋 PRD §3.2 的三個顯示開關與天數單位區間。**本型別不得自行讀取系統時鐘**——拍攝時刻一律由參數傳入（PRD §6.5 的接縫）。

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
- **禁止在 `TemplateRenderer` 內呼叫 `Date()`**（PRD FR-2.18 / §6.5.3）。內部一律以 `DayCountCalculator(calendar: calendar, now: { capturedAt })` 取得計算結果，讓 `capturedAt` 成為**唯一**的時間來源
- 組裝順序：名稱 → 日期 → 天數（PRD FR-2.5）。名稱後接一個半形空格；日期與天數之間用全形空白 U+3000
- **日期部分走獨立分支**：只由 `capturedAt` 換算當地年月日，**不得**讀取 `profile.startDate`、不得呼叫 `dayCount(...)`（PRD FR-2.17）
- 天數部分依 `largestUnit` 決定軌道取值（PRD §3.2 軌道表）：
  - 年軌 → `dateComponents([.year,.month,.day])`
  - 月軌 → `dateComponents([.month,.day])`
  - 週軌 → `q = n / 7`、`r = n % 7`
  - 天軌 → `n`
- 起始日在未來（`raw < 0`）時，**天數部分**回傳 `尚未開始`；日期部分若開啟仍照常輸出（PRD §7.2）
- 附 XCTest

**驗收 — A. QA 可自動跑**

基準：`name: "小寶"`、`startDate: 2025-01-15`、`dayOne`、`capturedAt` = `2026-03-20 10:00`（Asia/Taipei）。此時 `n = 430`、年軌 `(1,2,5)`、月軌 `(14,5)`、週軌 `(61,3)`。

> 下表凡寫「now =」處，一律指**傳入的 `capturedAt` 參數**，不是系統時鐘。
> 所有曆法差數值皆以 Swift 6.0.3 實測確認，可直接作為預期值。

**A-1 八種合法單位組合**（`showDate` 關、`showName` 關）

| # | 最大 | 最小 | 預期輸出（逐字元相符） |
|---|---|---|---|
| 4.1 | 天 | 天 | `第 430 天` |
| 4.2 | 週 | 天 | `61 週又 3 天` |
| 4.3 | 週 | 週 | `61 週` |
| 4.4 | 月 | 天 | `14 個月又 5 天` |
| 4.5 | 月 | 月 | `14 個月` |
| 4.6 | 年 | 天 | `1 年 2 個月 5 天` |
| 4.7 | 年 | 月 | `1 年 2 個月` |
| 4.8 | 年 | 年 | `1 年` |

**A-2 `showDate` 與並列順序**（PRD FR-2.5）

| # | 設定 | 預期輸出 |
|---|---|---|
| 4.9 | `showDate` 開、`showDayCount` 關 | `2026.03.20` |
| 4.10 | `showDate` 開、`showDayCount` 開（天/天） | `2026.03.20　第 430 天`（中間為**全形空白 U+3000**） |
| 4.11 | 承 4.10，`showName` 開 | `小寶 2026.03.20　第 430 天`（名稱後為**半形**空格） |
| 4.12 | `showName` 開、`showDate` 關、天/天 | `小寶 第 430 天` |
| 4.13 | 承 4.1（`showName` 關） | 輸出**不得**以空白開頭；以 `XCTAssertEqual(out, "第 430 天")` 逐字元比對 |
| 4.14 | 檢視 4.10 的輸出 | 分隔符必須是 U+3000，不是半形空格或兩個半形空格。以 `out.contains("\u{3000}")` 斷言 |

**A-3 歲措辭**（PRD FR-2.9）

| # | 設定 | 預期輸出 |
|---|---|---|
| 4.15 | 年/月、`useAgeWording` 開 | `1 歲 2 個月` |
| 4.16 | 年/天、`useAgeWording` 開 | `1 歲 2 個月 5 天` |
| 4.17 | 年/年、`useAgeWording` 開 | `1 歲` |
| 4.18 | 年/月、`useAgeWording` 關 | `1 年 2 個月`（對照組，確認只有措辭不同） |

**A-4 值為 0 的單位省略**（PRD FR-2.12）

| # | 情境（`dayOne`） | 軌道 | 實測值 | 預期輸出 |
|---|---|---|---|---|
| 4.19 | start 2026-01-01, now 2026-01-10 | 年/天 | (0,0,9) | `9 天` |
| 4.20 | start 2025-01-01, now 2026-01-01 | 年/天 | (1,0,0) | `1 年` |
| 4.21 | start 2025-01-01, now 2026-03-01 | 年/天 | (1,2,0) | `1 年 2 個月` |
| 4.22 | start 2026-01-01, now 2026-09-04 | 年/天 | (0,8,3) | `8 個月 3 天` |
| 4.23 | start 2026-01-01, now 2026-09-04 | 年/月, 歲措辭開 | (0,8,3) | `8 個月`（歲為 0 省略） |
| 4.24 | start 2026-01-01, now 2026-01-06 | 年/月, 歲措辭開 | (0,0,5) | `0 天`（年月皆 0，該軌道全零 → 輸出 `0 天`） |
| 4.25 | start 2025-01-01, now 2026-01-01 | 月/天 | 月軌 (12,0) | `12 個月` |
| 4.26 | start 2026-01-01, now 2026-01-10 | 月/天 | 月軌 (0,9) | `9 天` |

**A-5 週軌道**（PRD FR-2.14，基數非序數，連接詞「又」）

| # | `n` | 最大/最小 | 預期輸出 |
|---|---|---|---|
| 4.27 | 0（`dayZero` 同一天） | 週/天 | `0 天` |
| 4.28 | 1 | 週/天 | `1 天`（`q == 0`，省略週） |
| 4.29 | 7 | 週/天 | `1 週`（`r == 0`，省略天） |
| 4.30 | 8 | 週/天 | `1 週又 1 天` |
| 4.31 | 10 | 週/天 | `1 週又 3 天` |
| 4.32 | 14 | 週/天 | `2 週` |
| 4.33 | 430 | 週/天 | `61 週又 3 天` |
| 4.34 | 430 | 週/週 | `61 週`（餘數被最小單位截掉，非省略） |

**A-6 「天」在不同軌道代表不同數值**（PRD §3.2 的硬性說明，**本卡最容易實作錯的一組**）

同一個基準設定檔，只改單位區間：

| # | 最大/最小 | 「天」的值 | 預期輸出 |
|---|---|---|---|
| 4.35 | 年/天 | 5（曆法差餘數） | `1 年 2 個月 5 天` |
| 4.36 | 月/天 | 5（曆法差餘數） | `14 個月又 5 天` |
| 4.37 | 週/天 | 3（`n % 7`） | `61 週又 3 天` |
| 4.38 | 天/天 | 430（`n` 本身） | `第 430 天` |

| # | 步驟 | 預期結果 |
|---|---|---|
| 4.39 | 檢視實作 | 四條軌道的「天」必須各自取值，**不得**共用同一個變數。若實作把「天」統一成 `n`，4.35／4.36／4.37 會同時失敗 |

**A-7 起算規則只作用於天/週軌道**（PRD §3.2 的硬性說明）

起始日當天（start = now = 2026-01-01、`dayOne`，`n = 1`、年軌 `(0,0,0)`）：

| # | 最大/最小 | 預期輸出 |
|---|---|---|
| 4.40 | 天/天 | `第 1 天`（`n` 有 +1） |
| 4.41 | 週/天 | `1 天`（由 `n` 導出，有 +1） |
| 4.42 | 年/天 | `0 天`（曆法差無 +1，全零 → `0 天`） |
| 4.43 | 月/天 | `0 天`（同上） |

> 4.40 與 4.42 **刻意不同**。這不是 bug，是「當天算第 1 天」只適用於天數概念的必然結果。若有人為了「一致」把年軌也 +1，4.42 會失敗。

**A-8 日期部分永不讀 `startDate`**（PRD FR-2.17）

| # | 步驟 | 預期輸出 |
|---|---|---|
| 4.44 | 設定檔 A（只顯示天數、start 2026-01-10、`dayOne`）與 B（只顯示日期、start 也是 2026-01-10）。now = 2026-01-10 各渲染一次；再以 now = 2026-01-11 各渲染一次 | now=01-10：A → `第 1 天`，B → `2026.01.10`<br>now=01-11：A → `第 2 天`（**正確**，天數本來就遞增），B → **`2026.01.11`**（**不得**變成 `第 2 天`） |
| 4.45 | 只顯示日期的設定檔，`startDate` 設成 **1999-01-01**（與今天無關的值），now = 2026-03-20 | 輸出 `2026.03.20`。`startDate` 完全不影響日期輸出 |
| 4.46 | 只顯示日期的設定檔，起始日在未來（start 2026-12-01、now 2026-09-19） | 輸出 `2026.09.19`，**不是** `尚未開始` |
| 4.47 | 檢視日期分支的實作 | 該分支內**沒有**用到 `profile.startDate`、`countingRule`、`dayCount(...)`；只由 `capturedAt` 換算出年月日並格式化 |

**A-9 拍攝時刻是顯式參數**（PRD §6.5 的接縫，Phase 4 匯入功能的前提）

| # | 步驟 | 預期結果 |
|---|---|---|
| 4.48 | **同一個**只顯示日期的設定檔，以 `capturedAt = 2019-07-04 09:00` 呼叫一次，再以 `capturedAt = 2026-03-20 10:00` 呼叫一次 | 依序得到 **`2019.07.04`** 與 **`2026.03.20`**。證明日期完全以傳入的拍攝時刻為準，可餵入任意過去日期——這是日後匯入舊照片的前提 |
| 4.49 | **同一個**天數設定檔（start 2025-01-15、`dayOne`、天/天），以 `capturedAt = 2025-01-16` 與 `capturedAt = 2026-03-20` 各呼叫一次 | 依序得到 **`第 2 天`** 與 **`第 430 天`**。天數同樣完全由 `capturedAt` 決定 |
| 4.50 | `grep -rn "Date()" DaysCam/Services/TemplateRenderer.swift` | **無結果**。渲染層不得自行讀取系統時鐘（PRD FR-2.18 / §6.5.3） |
| 4.51 | 檢視 `render` 的簽章 | 含 `capturedAt: Date` 參數。**若有人把它移除並改回內部讀時鐘，4.48／4.49 會立刻失敗**——這兩條就是這個接縫的防回歸測試 |

**A-10 `dayZero` 與未來日期**

| # | 情境 | 預期輸出 |
|---|---|---|
| 4.52 | start 2026-01-01, now 2026-01-01, **dayZero**, 天/天 | `第 0 天` |
| 4.53 | start 2026-12-01, now 2026-09-19，**八種單位組合全測**，只顯示天數 | 八種都回傳 `尚未開始` |
| 4.54 | 承 4.53，`showName` 開啟 | 輸出為 `小寶 尚未開始` |
| 4.55 | 承 4.53，`showDate` 也開啟 | 輸出為 `2026.09.19　尚未開始`（日期照常，只有天數部分變成「尚未開始」） |

**A-11 時區**

| # | 步驟 | 預期輸出 |
|---|---|---|
| 4.56 | 只顯示日期的設定檔，以 `Asia/Taipei` 與 `America/New_York` 傳入同一 UTC 時刻 `2026-01-09T20:00:00Z` | Taipei → `2026.01.10`；New_York → `2026.01.09` |

**驗收 — B. 需人類實機**：無。

**依賴**：TASK-01、TASK-02

---

## TASK-05：OverlayTheme（5 組主題）

**目標**
把 PRD §3.4 的 5 組主題定義成**預覽層與烘焙層共用**的資料結構，避免兩邊長得不一樣。

**範圍**

- `Models/OverlayTheme.swift`：`struct OverlayTheme` 含 `id`、`displayName`、`fontDesign`、`fontWeight`、`textColor`、**`decorations: [OverlayDecoration]`**（`.shadow(offset:blur:opacity:color:)` / `.backgroundBox(color:opacity:cornerRadius:insets:)` / `.stroke(color:width:)`）。用**陣列**是因為單一主題可能同時有描邊與陰影（例如 `softPink`），單數欄位裝不下
- **`OverlayTheme` 必須是純資料，不得 `import UIKit`／`SwiftUI`**。`textColor` 用自訂的 `OverlayColor { red, green, blue, opacity }`（sRGB 分量，便於斷言）。需要量測文字寬度的字級自動縮小函式**不放這裡**，改放 `Services/OverlayMetrics.swift`（見下）
- `Services/OverlayMetrics.swift`：字級與邊距的共用計算（`baseFontSize(forShortEdge:)`＝短邊 ×5.5%、`margin(forShortEdge:)`＝短邊 ×4%、以及需要量測實際文字寬度的自動縮小函式，下限 60%）。**`OverlayTextView`（ui-dev）與 `OverlayRenderer`（core-dev）必須共用這一份，不得各刻一份**
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
| 5.3 | 每個 theme 的 `decorations` | 5 組全部至少有一種 decoration，即 `decorations.isEmpty == false`（PRD FR-4.6） |
| 5.3a | `grep -rn -e 'import UIKit' -e 'import SwiftUI' DaysCam/Models/OverlayTheme.swift` | **無結果**。`OverlayTheme` 是純資料，量測相關的函式在 `Services/OverlayMetrics.swift` |
| 5.4 | `classicWhite.textColor` 的 sRGB 分量 | `(1.0, 1.0, 1.0, 1.0)` |
| 5.5 | `retroOrange.textColor` 的 sRGB 分量 | 對應 `#FF9500` 即 `(1.0, 0.584, 0.0, 1.0)`，容差 ±0.01 |
| 5.6 | `baseFontSize(forShortEdge: 3024)` | `166.32`，容差 ±0.01 |
| 5.7 | `margin(forShortEdge: 3024)` | `120.96`，容差 ±0.01 |
| 5.8 | 縮小函式：給一段長到超出可用寬度的文字 | 回傳字級 < 基準，且 **>= 基準 × 0.6** |
| 5.9 | 縮小函式：給一段很短的文字 | 回傳**恰好**等於基準字級（短文字不縮） |
| 5.10 | `grep -rn -e 'Color("' -e 'UIColor(named' DaysCam/Models/OverlayTheme.swift` | 無結果 |
| 5.11 | `grep -rn -e '\.custom(' -e 'UIFont(name:' DaysCam/` | 無結果（PRD FR-4.10：只用系統字體） |

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
- **`showDayCount` 關閉時隱藏起始日與起算規則**（PRD FR-3.7）
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
| 6.11 | 把某設定檔的「顯示天數」關掉、「顯示日期」打開（在 TASK-11 的面板改），再回編輯頁 | 起始日與起算規則兩個欄位**不顯示**；預覽顯示「今天會顯示為：2026.01.10」 |
| 6.12 | 承 6.11 把「顯示天數」重新打開，回編輯頁 | 兩個欄位**重新出現** |
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

> **本卡橫跨兩個人，驗收也分兩半**
>
> `Services/CameraService.swift` 歸 core-dev、`Views/CameraPreviewView.swift` 與相機畫面接線歸 ui-dev（見檔案所有權表）。
>
> **core-dev 半邊**：7.3、7.4a、7.4b（純 Services，不需要 View）
> **ui-dev 半邊**：7.1、7.2、7.4（都需要畫面跑起來才量得到）
>
> 所以 core-dev 交付時只會回報 7.3／7.4a／7.4b，**qa 不要因為 7.1/7.2/7.4 沒結果就判定它漏交**——那三條要等 ui-dev 接好 `CameraScreen` 才跑得動。

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 7.1 | 模擬器執行並進入相機畫面 | 顯示純色佔位背景，快門 disabled，有「模擬器不支援拍照」字樣，不崩潰（**ui-dev 半邊**） |
| 7.2 | 模擬器上量測觀景窗區域的像素長寬比 | 4:3，誤差 < 2%（**ui-dev 半邊**） |
| 7.3 | `grep -rn -e startRunning -e stopRunning DaysCam/Services/CameraService.swift` | 兩者都不在主執行緒直接呼叫（包在背景 queue 內） |
| 7.4 | 模擬器上反覆進出相機畫面 10 次 | 不崩潰，console 無 `AVCaptureSession` error（**ui-dev 半邊**） |
| 7.4a | `xcodebuild ... test -only-testing:DaysCamTests/CameraServiceTests` | 全數通過。必須涵蓋 **PRD §2.3 權限狀態機的每一列**（未決定／已授權／被拒／受限／從設定返回後重檢）與 **§2.4 的中斷與恢復**。實作需把權限查詢與裝置取得做成可注入的介面，否則這些只能在實機驗 |
| 7.4b | `grep -rn -e 'AVCaptureDevice.authorizationStatus' -e 'AVCaptureDevice.default(' DaysCam/Services/CameraService.swift` | 這兩個呼叫**只能出現在可注入介面的預設實作裡**，不得散落在狀態機邏輯中——否則 7.4a 無法在模擬器執行 |

> **為什麼補 7.4a／7.4b**
>
> 本卡原本的 A 級只有四條，權限狀態機（§2.3 五種狀態＋從設定返回）與中斷恢復（§2.4）**全部落在 B 級**，等於 QA 完全無法驗證這張卡最複雜的部分，只能等人類拿實機跑。
>
> 但那套狀態機其實**完全可以在模擬器測**——只要把「查詢權限」與「取得擷取裝置」做成注入的介面。core-dev 實作時自行加了這兩個接縫並寫了 22 個測試，證明可行。這兩條把那個做法變成規格要求，而不是靠實作者自發。

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
| 8.3 | 把「預設」改成只顯示日期（天數關、日期開），`DAYSCAM_FAKE_TODAY=2026-01-11` | 顯示 **`2026.01.11`**，**不是** `第 2 天` |
| 8.4 | 開啟 `showName`（名稱「預設」），單位天/天，日期 2026-01-10 | 顯示 `預設 第 1 天` |
| 8.5 | 關閉 `showName` | 顯示 `第 1 天`，開頭無多餘空白 |
| 8.6 | 位置設 `topLeading` | 文字在左上，左／上邊界距離皆約短邊 4%（截圖量測，誤差 < 1%） |
| 8.7 | 位置設 `bottomTrailing` | 文字在右下，右／下邊界距離約短邊 4% |
| 8.8 | 位置設 `middleCenter` | 水平垂直皆置中 |
| 8.9 | 依序套用 9 個位置 | 9 個位置文字都完整顯示，**無任何一個被裁切** |
| 8.10 | 5 組主題各套一次 | 字體、顏色、襯底肉眼可區分，無任何一組是純文字無襯底 |
| 8.11 | 名稱 20 字 ＋ `showName` 開啟 ＋ `showDate` 開啟 ＋ 單位年/天 ＋ 位置 `bottomTrailing` | 文字**不超出觀景窗邊界**；字級縮小但不低於基準 60%；不換行、不截斷 |
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
| 9.8 | `grep -rni -e watermark -e originalImage -e CGImageDestinationAddImage DaysCam/Services/OverlayRenderer.swift` | 無結果 |
| 9.9 | `grep -rn "UIGraphicsImageRenderer" DaysCam/Services/OverlayRenderer.swift` | 有結果（確認是像素繪製而非 view 疊加） |
| 9.10 | `grep -rnE -e 'CameraProfile' -e 'AVCapture' -e 'Date\b' -e 'DateComponents' DaysCam/Services/OverlayRenderer.swift` | **無結果**。烘焙層不得認識設定檔、相機型別或任何日期概念——它只是「影像＋文字→影像」（PRD §6.5.4） |
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

> **本卡橫跨兩個人，驗收也分兩半**
>
> | 擁有者 | 範圍 | 驗收 |
> |---|---|---|
> | core-dev | `Services/PhotoSaver.swift`（`PHPhotoLibrary` 存檔）、`CameraService` 的原生解析度設定 | 10.1、10.2、10.18，以及 `PhotoSaver` 自己的單元測試 |
> | ui-dev | 快門 UI，以及在 `CameraScreenModel` 把 `capturePhoto` → `TemplateRenderer` → `OverlayRenderer.bake` → `PhotoSaver` 串起來 | **10.3、10.4**，以及其餘需要畫面的條目 |
>
> **10.3（當場重算文字）與 10.4（`capturedAt` 在哪裡產生）屬於 ui-dev**，因為它們驗的是串接邏輯，而串接發生在 `CameraScreenModel`。這兩條最容易出現「兩邊都以為對方會寫」——core-dev 開工前主動確認才抓到。
>
> **10.18 原生解析度落在 core-dev**：`CameraService` 目前沒有設定 `photoOutput.maxPhotoDimensions`，照片停在系統預設尺寸，實機上不一定是 4032×3024。這在 TASK-07 的 code review 被列為 Minor 後一直沒處理，本卡補上。

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 10.1 | `grep -rn "PHAccessLevel" DaysCam/` | 只出現 `.addOnly`，**無** `.readWrite` |
| 10.2 | `grep -rni -e createAssetCollection -e PHAssetCollectionChangeRequest DaysCam/` | **無結果**（不建立自訂相簿） |
| 10.3 | 單元測試：以 `capturedAt = 2026-01-10` 渲染一次文字後，改以 `capturedAt = 2026-01-11` 再走烘焙路徑 | 烘焙使用的文字為 `第 2 天`，**不是** `第 1 天`（證明當場重算，PRD §6.4） |
| 10.4 | 檢視快門處理的實作 | **快門處是唯一產生 `capturedAt` 的地方**，產生後往下傳；`TemplateRenderer` 與 `OverlayRenderer` 內都**沒有** `Date()`（PRD §6.5.5）。`capturedAt` 應取自與觀景窗預覽**相同的時鐘**（`DayCountCalculator().now()`），**不要**字面寫 `Date()`——否則 Debug 下設了 `DAYSCAM_FAKE_TODAY` 時，觀景窗顯示的天數與照片印的會不一致。Release build 下兩者相同 |

**驗收 — B. 需人類實機**

前置：實機裝置日期設為 **2026-01-10**，全新安裝（預設設定檔起始日即 2026-01-10）。

| # | 步驟 | 預期結果 |
|---|---|---|
| 10.5 | 允許權限後直接按快門（不做任何設定） | 1.5 秒內出現「已儲存」Toast 與左下角縮圖，**留在相機畫面**不跳轉 |
| 10.6 | 開「照片」App 看最新一張 | 右下角印著 **`第 1 天`**，白字黑陰影。**照片上沒有「預設」二字**（`showName` 預設關閉） |
| 10.7 | 對該照片點「編輯」 | 疊字無法移除、無法拖曳（是像素不是圖層） |
| 10.8 | 把該照片 AirDrop 到另一台裝置後開啟 | 疊字仍在，文字仍是 `第 1 天`（PRD G-4） |
| 10.9 | 裝置日期改 **2026-01-11**，重開 App 拍一張 | 照片印 `第 2 天`；先前那張**仍是** `第 1 天`（已烘焙不會回溯） |
| 10.10 | 改成只顯示日期（天數關、日期開），拍一張 | 照片印 **`2026.01.11`**，**不是** `第 2 天` |
| 10.11 | 開啟 `showName`（名稱「小寶」）、單位天/天，拍一張 | 照片印 `小寶 第 2 天` |
| 10.12 | 設定檔起始日 2025-01-15、裝置日期 2026-03-20、單位年/天，拍照 | 照片印 `1 年 2 個月 5 天` |
| 10.13 | 同上改單位週/天 | 照片印 `61 週又 3 天`（430 = 61×7 + 3） |
| 10.13a | 同上改單位月/天 | 照片印 `14 個月又 5 天`（月軌實測值） |
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
- 四個區塊：
  1. **顯示內容**：三個 `Toggle`（顯示天數／顯示日期／顯示名稱）
  2. **天數格式**：最大單位與最小單位兩個選擇器 ＋ 歲措辭 `Toggle`
  3. **位置**：3×3
  4. **主題**：5 選 1，樣式縮圖
- **最小單位選擇器的選項隨最大單位動態變化**（PRD §3.2 軌道表）：年→[年,月,天]、月→[月,天]、週→[週,天]、天→[天]
- 改最大單位時若現有最小單位不在新軌道上，**自動夾到該軌道的最小單位**（例如年/天 → 改成週 → 變成週/天；年/月 → 改成週 → 變成週/週，因為月不在週軌上）
- **歲措辭開關僅在最大單位為「年」時可用**，其餘情況 disabled 並自動關閉
- **顯示天數與顯示日期不得同時關閉**（PRD FR-2.4）：只剩一個開啟時該開關 disabled 並顯示「至少需要顯示天數或日期其中一項」
- 顯示天數關閉時，「天數格式」整區 disabled
- 任何變更**即時**寫回目前設定檔並持久化；變更時觀景窗疊字即時更新，面板不關閉

**驗收 — A. QA 可自動跑**（模擬器，`DAYSCAM_FAKE_TODAY=2026-01-10`，設定檔起始日 2026-01-01、`dayOne`、名稱「小寶」。此時 `n = 10`、年軌 `(0,0,9)`、月軌 `(0,9)`、週軌 `(1,3)`——**皆已實測**）

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.1 | 相機畫面點設定入口 | 從底部滑出面板，觀景窗仍可見（半高 detent） |
| 11.2 | 檢視面板內容 | 只有「顯示內容／天數格式／位置／主題」四區塊，**沒有**起始日、起算規則、名稱輸入框 |
| 11.3 | 檢視「顯示內容」區塊 | 恰好 3 個 `Toggle`：顯示天數（**預設開**）、顯示日期（**預設關**）、顯示名稱（**預設關**） |
| 11.4 | 檢視「天數格式」區塊 | 最大單位、最小單位兩個選擇器 ＋ 歲措辭開關（**預設關**、此時 disabled，因為預設最大單位是「天」） |
| 11.5 | 位置區塊 | 3×3 共 9 個按鈕，當前選中有明顯標記 |
| 11.6 | 主題區塊選項數 | 恰好 5 個，每個顯示樣式縮圖（不是純文字清單） |
| 11.7 | 初始疊字 | `第 10 天` |

**A-2 顯示開關**

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.8 | 打開「顯示名稱」 | 面板不關閉，疊字立即變成 `小寶 第 10 天` |
| 11.9 | 關閉「顯示名稱」 | 疊字立即變回 `第 10 天`，開頭無空白 |
| 11.10 | 打開「顯示日期」 | 疊字變成 `2026.01.10　第 10 天`（中間全形空白 U+3000） |
| 11.11 | 承 11.10，關閉「顯示天數」 | 疊字變成 `2026.01.10` |
| 11.12 | 承 11.11，檢視「顯示日期」開關 | **disabled**，並顯示「至少需要顯示天數或日期其中一項」（PRD FR-2.4） |
| 11.13 | 承 11.11，檢視「天數格式」整區 | **disabled** |
| 11.14 | 承 11.11，重新打開「顯示天數」 | 「顯示日期」恢復可按、「天數格式」區恢復可用；疊字回到 `2026.01.10　第 10 天` |

**A-3 單位區間**

| # | 步驟 | 預期疊字 |
|---|---|---|
| 11.15 | 最大＝天、最小＝天（預設） | `第 10 天` |
| 11.16 | 最大改成「週」 | `1 週又 3 天` |
| 11.17 | 承 11.16，最小改成「週」 | `1 週` |
| 11.18 | 最大改成「月」、最小「天」 | `9 天`（月軌 `(0,9)`，月為 0 省略） |
| 11.19 | 最大改成「年」、最小「天」 | `9 天`（年軌 `(0,0,9)`，年月皆 0 省略） |
| 11.20 | 承 11.19，最小改成「年」 | `0 天`（該軌道全零 → `0 天`，PRD FR-2.12） |

**A-4 選項連動與夾取**

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.21 | 最大單位設為「年」，檢視最小單位選項 | 恰好 3 個：年、月、天 |
| 11.22 | 最大單位設為「月」，檢視最小單位選項 | 恰好 2 個：月、天 |
| 11.23 | 最大單位設為「週」，檢視最小單位選項 | 恰好 2 個：週、天 |
| 11.24 | 最大單位設為「天」，檢視最小單位選項 | 恰好 1 個：天（或該選擇器 disabled） |
| 11.25 | 設成年/月後，把最大單位改成「週」 | 最小單位自動變成**週**（月不在週軌上，夾到該軌最小值）；疊字為 `1 週` |
| 11.26 | 設成年/天後，把最大單位改成「週」 | 最小單位維持**天**（天在週軌上）；疊字為 `1 週又 3 天` |
| 11.27 | 嘗試把最小單位設成大於最大單位的值 | UI 上不存在這種選項（選項清單已排除），無法做到 |

**A-5 歲措辭**

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.28 | 最大單位＝「天」時檢視歲措辭開關 | **disabled** |
| 11.29 | 最大單位改成「年」 | 歲措辭開關變成可用，狀態仍為關閉 |
| 11.30 | 打開歲措辭（年/年，起始日改為 2025-01-01 使年份非 0） | 疊字為 `1 歲` |
| 11.31 | 承 11.30，最大單位改回「月」 | 歲措辭自動**關閉**且 disabled；疊字不含「歲」 |

**A-6 持久化**

| # | 步驟 | 預期結果 |
|---|---|---|
| 11.32 | 關閉面板 → 殺掉 App → 重開 | 三個顯示開關、最大／最小單位、歲措辭、位置、主題全部保持剛才選的值 |
| 11.33 | 建立第二個設定檔，各項都設成不同值，來回切換 | 每個設定檔各自保留自己的設定，互不覆蓋 |

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
| 12.6 | 承 12.5 改成只顯示日期，再重啟 | 疊字為 **`2026.01.11`**，**不是** `第 2 天`（PRD FR-2.17） |
| 12.7 | 建立「小寶 / 2026-01-01 / 當天算第 1 天」 | 自動切到「小寶」並回相機畫面 |
| 12.8 | 承 12.7 殺掉 App 重開（`DAYSCAM_FAKE_TODAY=2026-01-11`） | 直接進相機畫面，套用「小寶」，疊字 `第 11 天` |
| 12.9 | 在清單選「預設」→ 殺掉 App 重開 | 套用「預設」 |
| 12.10 | 刪除目前選取的設定檔 → 殺掉 App 重開 | 套用清單中仍存在的某筆，不崩潰、不停在空白畫面 |
| 12.11 | 把 `UserDefaults` 的 `lastUsedProfileID` 改成不存在的 UUID → 重開 | 套用**清單第一筆**，不崩潰、不顯示錯誤 |
| 12.12 | `grep -rn 'CameraProfile(' DaysCam/Services/TemplateRenderer.swift DaysCam/Services/OverlayRenderer.swift DaysCam/Services/CameraService.swift` | **無結果**。渲染與拍照路徑上**不得**臨時建立設定檔。（合法的建立位置有三處：`ProfileStore` 種預設值、新增設定檔、以及 SwiftUI `#Preview` 夾具——原本寫「只有兩處」漏算了 `#Preview`，而且用數處數的方式無法精確表達「不得出現在渲染路徑」這個意圖） |

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
| 14.2 | 同 14.1 但改成只顯示日期 | 烘焙文字為 `2026.01.11`，不是 `2026.01.10`、不是 `第 2 天` |
| 14.3 | `grep -rn -e NSCalendarDayChanged -e willEnterForegroundNotification DaysCam/` | 兩者都有被監聽 |
| 14.4 | 模擬器：以 `DAYSCAM_FAKE_TODAY=2026-01-10` 啟動 → 切背景 → 改成 `2026-01-11` 重啟 App | 疊字為 `第 2 天` |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 14.5 | 起始日 2026-01-01 / `dayOne` / 純天數。裝置日期設 **2026-01-10 23:59**，App 停在相機畫面 | 疊字 `第 10 天` |
| 14.6 | 承 14.5 等待跨午夜（或手動撥到 2026-01-11 00:01），**不要離開 App** | 疊字在 60 秒內自動變 `第 11 天` |
| 14.7 | 承 14.5 切背景 → 改日期為 2026-01-11 → 切回 App | 疊字立即為 `第 11 天` |
| 14.8 | 承 14.5（疊字仍顯示 `第 10 天`），**在畫面刷新前**把日期改 2026-01-11 後立刻按快門 | 存下的照片必須是 `第 11 天`（證明烘焙當場重算，不是沿用快取） |
| 14.9 | 同 14.8 但改成只顯示日期 | 存下的照片必須是 `2026.01.11` |

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
| 15.3 | 設定檔起始日 2026-01-01，`DAYSCAM_FAKE_TODAY=2025-12-01` 啟動 | 疊字顯示 `尚未開始`；八種單位組合逐一切換皆顯示 `尚未開始` |
| 15.4 | 承 15.3 關掉「顯示天數」、打開「顯示日期」 | 疊字顯示 `2025.12.01`，**不是** `尚未開始` |
| 15.5 | 承 15.3 開啟 `showName`（名稱「小寶」） | 疊字顯示 `小寶 尚未開始` |
| 15.6 | `grep -rnE '^[^/]*print\(' DaysCam/` | 無結果，或全部在 `#if DEBUG` 內 |

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
| 16.2 | `grep -rni -e exif -e DateTimeOriginal -e creationDate -e fileCreation DaysCam/` | 無結果（PRD §6.1 最終確認） |
| 16.3 | `grep -rnE "startDate[?!]?\.date\b" DaysCam/` | 無結果 |
| 16.4 | `git ls-files -- '*xcodeproj*'` | 無結果 |
| 16.5 | 模擬器冒煙：刪除 App 資料 → `DAYSCAM_FAKE_TODAY=2026-01-10` 啟動 → 開顯示設定面板 → 關「顯示天數」開「顯示日期」→ `DAYSCAM_FAKE_TODAY=2026-01-11` 重啟 | 首次顯示 `第 1 天`；改設定並跨日後顯示 `2026.01.11`（不是 `第 2 天`） |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 16.6 | **G-1**：刪除 App → 重裝 → 裝置日期 2026-01-10 → 開啟 → 允許相機 → 直接按快門 → 允許相簿 | 全程**沒填過任何表單**，相簿最新一張右下角印 `第 1 天`，照片上無任何品牌或佔位字樣 |
| 16.7 | **G-5**：接續 16.6（裝置日期仍為 2026-01-10），計時完成「進設定檔編輯頁 → 把起始日改成 2025-01-15 → 回相機拍一張」 | 90 秒內完成，照片印 **`第 361 天`**（2025-01-15 → 2026-01-10 相差 360 天，`dayOne` 加 1） |
| 16.7b | 承 16.7，把單位改成年/天再拍一張 | 依 FR-2.12 省略值為 0 的單位後印 **`11 個月 26 天`** |
| 16.8 | **G-3**：對 16.6 拍的照片在「照片」App 點編輯 | 疊字無法移除 |
| 16.9 | **G-4**：把 16.6 的照片 AirDrop 到另一台裝置開啟 | 疊字仍在且文字不變 |
| 16.10 | 連續使用 5 分鐘：切換設定檔、改顯示開關/單位區間/位置/主題、拍 10 張 | 不崩潰、無記憶體持續上升、每張照片的疊字都與拍照當下觀景窗顯示的一致 |

**依賴**：TASK-01 ~ TASK-15 全部
