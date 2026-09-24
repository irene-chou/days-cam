# DaysCam v2 介面改版任務清單

- 版本：v2.0
- 日期：2026-09-25
- 上游：[`docs/PRD-v2-ui-redesign.md`](./PRD-v2-ui-redesign.md)、[`docs/PRD.md`](./PRD.md)、[`docs/design/`](./design/)
- 接續 [`docs/TASKS.md`](./TASKS.md)（TASK-01～16，已完成），編號從 TASK-17 開始

---

## 怎麼用這份文件

卡片結構、驗收分級、「儲存格指令不得含 `|`」等規則**全部沿用 [`docs/TASKS.md`](./TASKS.md#怎麼用這份文件)**，這裡不重複。本次新增一個驗收等級：

| 級別 | 含義 | 誰執行 |
|---|---|---|
| **A. QA 可自動跑** | 單元測試、靜態檢查、view model 測試 | QA teammate |
| **B′. 設計對照** | 用 Xcode MCP 的 `RenderPreview` 截 SwiftUI `#Preview`，與 `docs/design/` 設計稿並排比對版面、顏色、間距 | 有 Xcode MCP 的 agent 或人類。Xcode MCP 一次只能綁一個 Xcode 視窗，**同時只能一個 agent 用** |
| **B. 需人類實機** | 相機、閃光燈、實際拍照與烘焙結果目視、相簿權限彈窗 | 人類 |

**共用測試情境**（除非卡片另外寫）：`DAYSCAM_FAKE_TODAY=2026-01-10`，設定檔「小寶」起始日 2026-01-01、`dayOne`、只顯示天數 → 疊字 `第 10 天`。

**設計稿是視覺依據，PRD 是規格依據。** 兩者衝突時照 PRD（v2 PRD §1）。

### 事先預告：會讓你誤判的地方

1. **v1 驗收 5.11 會開始失敗，這是預期的。** 它用 `grep UIFont(name:` 禁止自訂字型，但 v2 FR-10.2 要用 `UIFont(name: "AvenirNext-Bold")` 這類**系統內建**字型。5.11 由本文件 17.12 取代，不要為了讓它通過而改寫法。
2. **v1 驗收 5.1～5.3（5 組主題、每組必有裝飾）在 TASK-17 之後不再成立。** `OverlayTheme` 改成由 `OverlayStyle` 產生的渲染值，沒有固定 5 組，也允許無裝飾（v2 FR-10.10）。
3. **v1 的「單位軌道」驗收在 TASK-27 之後部分失效**：v1 11.21～11.27（最小單位選項隨最大單位變化、夾取）與 v1 不變條件 4 已廢除。但 **v1 TASK-04 與 11.15～11.20 的輸出文字全部仍然成立**（v2 PRD §4.5 保證），只是輸入從 `(largest, smallest)` 換成對應的單位集合。看到 `DisplayUnitTrack` 被刪掉不是 bug。
4. **v1 TASK-11（顯示設定面板）、TASK-06（清單與編輯頁）、TASK-13（切換選單）的 UI 驗收在 TASK-26 之後失效**，因為那些畫面被刪除。它們的**邏輯**驗收（FR-2.4 開關互鎖、名稱 1～20 字等）必須在新卡片的 view model 測試裡重新涵蓋，見各卡的「沿用」欄。
5. **相簿權限會從 `.addOnly` 變成兩段式**：存檔仍只要 `.addOnly`，照片瀏覽才要 `.readWrite`。v1 驗收 12.13（「沒有相簿權限彈窗」）與 10.x 的權限條目仍然成立，不要因為加了讀取權限就提早在啟動時詢問。

---

## 依賴結構

```
第 0 層（可平行）
  TASK-17 OverlayStyle 模型、舊檔轉換、最近自訂顏色      core-dev
  TASK-19 相機工具（比例、閃光燈、計時器、格線）          core-dev
  TASK-20 ProfileStore 排序、複製、命名                  core-dev
  TASK-28 已拍照片紀錄與讀取權限                         core-dev

第 1 層
  TASK-18 渲染層支援 OverlayStyle 與自訂位置      ← 17        core-dev（OverlayTextView 由 ui-dev 配合）
  TASK-27 天數單位改為任意勾選（計算與文字）       ← 17        core-dev
  TASK-21 主題 tokens 與相機畫面改版              ← 19, 28    ui-dev

第 2 層
  TASK-22 疊字面板殼層                           ← 18, 21    ui-dev

第 3 層（都是 ui-dev，CameraScreen.swift 以外可平行，實務上依序做）
  TASK-23 樣式分頁                               ← 22
  TASK-24 格式分頁與位置分頁（含拖曳）             ← 22, 27
  TASK-25 天數規則分頁                           ← 22
  TASK-26 管理設定檔面板；刪除舊畫面               ← 20, 22
  TASK-29 照片瀏覽畫面                           ← 21, 28

第 4 層
  TASK-30 端對端整合驗收                          ← 全部       qa
```

**建議分工**：core-dev 依序 17 → 18 → 27，中間穿插 19、20、28；ui-dev 在 19、28 完成後從 21 開始。

## 檔案所有權

沿用 [`docs/TASKS.md` 的檔案所有權表](./TASKS.md#檔案所有權)。新增檔案的歸屬：

| 擁有者 | 新檔案 |
|---|---|
| core-dev | `Models/OverlayStyle.swift`、`Models/OverlayPlacement.swift`、`Models/CaptureSettings.swift`、`Services/CaptureSettingsStore.swift`、`Services/ImageCropper.swift`、`Services/RecentColorsStore.swift`、`Services/CapturedPhotoStore.swift` |
| ui-dev | `Views/Theme/`（tokens）、`Views/OverlayPanel/`（面板與各分頁）、`Views/ProfileManager/`、`Views/CameraToolbar/`、`Views/Gallery/` |

> **`Views/CameraScreen.swift` 仍是序列化瓶頸**（v1 TASKS 已說明）。TASK-21、22、24（拖曳）、26、29 都要改它，必須依序合併。分頁內容請放在 `Views/OverlayPanel/` 的獨立檔案，不要塞進 `CameraScreen.swift`。

---

## TASK-17：OverlayStyle 模型、舊檔轉換、最近自訂顏色

**目標**
把 v2 PRD §4.1～4.3 的樣式與位置模型落地：`OverlayStyle` 取代 `themeID`，`OverlayPlacement` 取代 `position`，舊檔能無損讀進來。（天數單位的模型變更在 TASK-27。）

**範圍**

- `Models/OverlayStyle.swift`：`OverlayStyle`（含 `outlineColor: OverlayColor?`）、`OverlayFontID`（10 種，順序同 PRD FR-10.2）、`OverlayOutline`、`OverlayShadow`，全部 `Codable`、`Equatable`、純資料（不 `import UIKit`／`SwiftUI`）
- `OverlayColor` 加 `Codable`，編碼為 `"#RRGGBB"` 字串；加 `relativeLuminance` 與 `autoContrastColor`（> 0.55 回 `#1C1C1E`，否則 `#FFFFFF`）
- `OverlayStyle.resolvedOutlineColor`：`outlineColor ?? textColor.autoContrastColor`
- `Models/OverlayPlacement.swift`：`enum OverlayPlacement { case anchor(OverlayPosition), custom(x: Double, y: Double) }`，`Codable`
- `CameraProfile`：移除 `themeID`，新增 `style`；`position` 改型別為 `OverlayPlacement`；預設值依 PRD §4.2
- PRD §4.1 新增的樣式與位置不變條件加進 `validate(calendar:)`
- 自訂 `init(from:)`：讀到 v1 欄位時依 PRD §4.3 轉換；未知 `fontID` 退回 `sfRounded`
- `OverlayFontID` 提供 `displayName`（英文原名）與 `postScriptName: String?`（系統字型為 `nil`）
- 色票常數 `OverlayStyle.swatches`（7 色，PRD FR-10.4）
- `Services/RecentColorsStore.swift`：`recentCustomColors`，規則照 PRD FR-10.7，存 `UserDefaults`

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 17.1 | `OverlayFontID.allCases.map(\.displayName)` | 依序 `["SF Rounded","SF Pro","SF Mono","New York","Avenir Next","Futura","Georgia","Typewriter","Didot","Snell Roundhand"]` |
| 17.2 | `OverlayStyle()` 預設值 | `fontID == .sfRounded`、`textColor == #FFFFFF`、`outline == .none`、`outlineColor == nil`、`shadow == .soft`、`sizeScale == 100` |
| 17.3 | 讀 v1 夾具 JSON（5 筆，各用一種 `themeID`，`position` 為 v1 字串） | 5 筆全部讀入，不丟筆；每筆的 `style` 等於 PRD §4.3 對照表；`position` 轉成 `.anchor(原值)` |
| 17.4 | 承 17.3，呼叫 `persist` 後讀回原始 JSON 文字 | 不含 `themeID` 鍵；含 `style` 鍵 |
| 17.5 | 讀一筆 `fontID` 為 `"comicSans"` 的 JSON | 採用該筆，`fontID == .sfRounded` |
| 17.6 | `sizeScale` 為 65、165、72 的設定檔呼叫 `validate` | 三者都拋出錯誤 |
| 17.7 | `sizeScale` 為 70、100、160 | 不拋錯 |
| 17.8 | `.custom(x: 1.2, y: 0.5)` 呼叫 `validate` | 拋錯；`.custom(x: 0, y: 1)` 不拋錯 |
| 17.9 | `autoContrastColor`：`#FFFFFF`、`#1C1C1E`、`#FF6B9D`、`#FFD60A` | 依序 `#1C1C1E`、`#FFFFFF`、`#FFFFFF`、`#1C1C1E` |
| 17.10 | `resolvedOutlineColor`：`outlineColor` 為 `nil` 與 `#0A84FF` | 前者等於 `autoContrastColor`，後者為 `#0A84FF` |
| 17.11 | `OverlayColor` 編碼再解碼 `#FF9500` | 往返相等；JSON 值為字串 `"#FF9500"` |
| 17.12 | 在 iOS 18 模擬器上，對每個 `postScriptName != nil` 的字型呼叫 `UIFont(name:size:)` | 全部非 `nil`。**有任何一個是 `nil`：從清單移除並回報 Lead，不要自行換成別的字型**（PRD A-6）。本條取代 v1 驗收 5.11 |
| 17.13 | `RecentColorsStore`：依序加入 `#111111`…`#888888`（8 個） | 保留 7 個，第一個是 `#888888`，`#111111` 被丟掉 |
| 17.14 | 已有 `[#222222, #111111]` 時再加入 `#111111` | 變成 `[#111111, #222222]`，不重複 |
| 17.15 | 加入色票裡的 `#FF9500` | 不加入 |
| 17.16 | `grep -rn -e 'import UIKit' -e 'import SwiftUI' DaysCam/Models/OverlayStyle.swift DaysCam/Models/OverlayPlacement.swift` | 無結果 |
| 17.17 | `grep -rn 'themeID' DaysCam/` | 只出現在舊檔轉換的程式碼與其註解中 |

**沿用**：v1 TASK-03 的所有持久化測試必須在新模型下仍通過（夾具要一併更新成新格式）。

**依賴**：無

---

## TASK-18：渲染層支援 OverlayStyle 與自訂位置

**目標**
預覽（`OverlayTextView`）與烘焙（`OverlayRenderer`）都照 `OverlayStyle` 與 `OverlayPlacement` 畫，兩者結果一致。

**範圍**

- `OverlayTheme` 改為**由 `OverlayStyle` 產生的渲染值**（`OverlayTheme(style:)`），保留 `decorations` 陣列機制；PRD FR-10 的裝飾常數表寫進這裡，描邊與底框用 `resolvedOutlineColor`
- `OverlayMetrics.font(for:size:)` 支援 10 種字型；`baseFontSize` 乘上 `sizeScale / 100`；自動縮小下限為縮放後字級的 60%（PRD FR-5.10）
- `OverlayLayout.origin` 支援 `.custom`：以中心點換算，並把整個框夾進 4% 邊距（PRD FR-12.2、FR-12.6）
- `OverlayRenderer.bake(image:text:style:placement:)`：簽名換成新型別，仍**不綁定影像來源**（v1 §6.5.4）
- `OverlayTextView`（ui-dev）改讀同一份 `OverlayTheme(style:)` 與 `OverlayMetrics`，**不得自行刻常數**
- 外框與陰影皆為 `.none` 時 `decorations` 為空陣列，照常渲染

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 18.1 | `OverlayTheme(style: 預設)` 的 decorations | 恰好 1 個 `.shadow`，參數 offset (0,2)、blur 4、opacity 0.6、黑色 |
| 18.2 | `outline: .solidBox`、`textColor: #FFFFFF`、`outlineColor: nil` | decorations 含 `.backgroundBox`，顏色 `#1C1C1E`、opacity 1.0、圓角 8、內距 12×6 |
| 18.3 | 承 18.2 但 `outlineColor: #0A84FF` | 底框顏色 `#0A84FF` |
| 18.4 | `outline: .none`、`shadow: .none` | `decorations.isEmpty == true`，`bake` 仍回傳非 nil 影像且文字區有非透明像素 |
| 18.5 | `baseFontSize(forShortEdge: 3024, sizeScale: 160)` | `266.11`，容差 ±0.01 |
| 18.6 | 縮小函式在 `sizeScale: 70`、超長文字 | 回傳字級 ≥ `3024 × 0.055 × 0.7 × 0.6`（= 69.85） |
| 18.7 | 3024×4032 白圖，`.custom(x: 0.5, y: 0.5)` 烘焙 | 文字框中心在 (1512, 2016) ±3px（像素抽樣找最小包圍框） |
| 18.8 | 同上，`.custom(x: 1.0, y: 1.0)` | 文字框右下角落在 (3024−121, 4032−121) ±3px，沒有超出邊距 |
| 18.9 | 對 10 種字型各烘焙一次 | 全部成功，文字區有非透明像素 |
| 18.10 | 對 4 種陰影 × 5 種外框（20 種組合）各烘焙一次 | 全部成功 |
| 18.11 | `grep -rn -e 'blur: 4' -e 'cornerRadius: 8' DaysCam/Views/` | 無結果（常數只能在 `OverlayTheme`） |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 18.12 | 用 SF Mono＋`#FF9500`＋藍色細描邊＋發光、字級 160%、自訂位置拍一張 | 相簿裡的照片與觀景窗的字型、顏色、裝飾、位置一致 |

**依賴**：TASK-17

---

## TASK-19：相機工具（比例、閃光燈、計時器、格線）

**目標**
PRD FR-7.4～7.10、§6 的相機端邏輯，全部可在 view model 層測試。

**範圍**

- `Models/CaptureSettings.swift`：`CaptureAspectRatio`（`threeByFour`／`oneByOne`／`nineBySixteen`）、`FlashMode`（`off`／`auto`／`on`，含 `next`）、`TimerSetting`（0／3／10，含 `next`）
- `Services/CaptureSettingsStore.swift`：`captureAspectRatio` 與 `showsGrid` 存 `UserDefaults`；`flashMode`、`timerSeconds` 只在記憶體（PRD §4.4）
- `Services/ImageCropper.swift`：從 4:3 原圖置中裁切成指定比例，**先裁再烘焙**（PRD FR-5.7′）
- `CameraService`：`capturePhoto` 帶入 flash mode；提供 `isFlashAvailable`（前鏡頭或無閃光燈為 false）
- `CameraScreenModel`：計時器倒數狀態（`countdownRemaining: Int?`）、倒數中再按快門取消、倒數結束才拍照；疊字在實際拍照時重算（沿用 v1 §6.4）
- 倒數用可注入的 tick 來源，測試不得真的等待

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 19.1 | `FlashMode.off.next.next.next` | `.off`（關→自動→開→關） |
| 19.2 | `TimerSetting` 從 0 連按三次 | 依序 3、10、0 |
| 19.3 | 設比例 1:1、開格線、閃光燈開、計時器 3 → 重建 store（模擬重開 App） | 比例 1:1、格線開；閃光燈 `.off`、計時器 0 |
| 19.4 | 切到前鏡頭（假裝置無閃光燈） | `isFlashAvailable == false`；送出的 photo settings flashMode 為 `.off` |
| 19.5 | 4032×3024 圖裁 1:1 | 3024×3024，取自水平置中 |
| 19.6 | 3024×4032（直拍）圖裁 9:16 | 2268×4032，水平置中 |
| 19.7 | 3024×4032 圖裁 3:4 | 尺寸不變 |
| 19.8 | 計時 3 秒按快門，注入 3 次 tick | `countdownRemaining` 依序 3、2、1、nil，第 3 次 tick 後呼叫拍照恰好 1 次 |
| 19.9 | 計時 10 秒按快門，tick 2 次後再按快門 | 倒數取消，`countdownRemaining == nil`，拍照 0 次，toast 為「已取消」 |
| 19.10 | 計時 3 秒：開始倒數時 now = 2026-01-10 23:59:59，拍照時 now = 2026-01-11 00:00:02 | 烘焙文字為 `第 11 天`（以實際拍下時刻為準） |
| 19.11 | 比例 1:1 下烘焙，裁切後短邊 3024 | 字級、邊距以 3024 計算（與 3:4 相同短邊）；9:16 時短邊為 2268，邊距 90.72 |
| 19.12 | `grep -rn 'kCGImagePropertyExif' DaysCam/` | 無結果（v1 §6.1 不變） |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 19.13 | 暗處、閃光燈「開」拍照 | 閃光燈觸發 |
| 19.14 | 三種比例各拍一張 | 相簿照片比例正確，構圖與觀景窗一致，疊字在觀景窗看到的位置 |
| 19.15 | 計時 10 秒拍照 | 倒數數字顯示正確，第 10 秒拍下 |

**依賴**：無

---

## TASK-20：ProfileStore 排序、複製、命名

**目標**
管理設定檔需要的持久化操作（PRD FR-9）。

**範圍**

- `ProfileStore.move(fromOffsets:toOffset:)`：改變陣列順序並持久化
- `ProfileStore.duplicate(id:) -> CameraProfile`：新 `id`、新 `createdAt`、名稱「{原名} 副本」、插在原設定檔之後、**不改變目前選取**（PRD A-3）
- `ProfileStore.uniqueName(base:)`：重複時加「 2」「 3」…；超過 20 字時截斷原名部分（PRD FR-9.9）
- 新增設定檔改用 `uniqueName(base: "新設定檔")`
- 上限 20（FR-1.7）與至少 1 個（FR-1.8）沿用

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 20.1 | [A, B, C] 把 C 移到最前 → 重新 load | 順序 [C, A, B] |
| 20.2 | 複製「小寶」 | 新增「小寶 副本」，位置在「小寶」正後方；`lastUsedProfileID` 不變；除 `id`、`name`、時間戳外所有欄位相同 |
| 20.3 | 再複製一次「小寶」 | 名稱「小寶 副本 2」 |
| 20.4 | 已有「新設定檔」「新設定檔 2」時新增 | 名稱「新設定檔 3」 |
| 20.5 | 原名 20 字（`一二三四五六七八九十一二三四五六七八九十`）複製 | 新名稱長度 ≤ 20，且以「 副本」結尾 |
| 20.6 | 已有 20 個時 `duplicate` | 拋出上限錯誤，檔案不變 |

**依賴**：無

---

## TASK-21：主題 tokens 與相機畫面改版

**目標**
PRD FR-7、FR-14：淺色主題、滿版觀景窗、頂部工具列、新底部列。面板在 TASK-22，照片瀏覽頁在 TASK-29。

**範圍**

- `Views/Theme/`：PRD FR-14 的 tokens（Asset Catalog 顏色＋字體、動效常數）。相機畫面**固定淺色**，不跟隨系統深色模式
- `CameraScreen`：滿版觀景窗；比例切換時的三種版面（FR-7.8）；格線；倒數大數字
- `Views/CameraToolbar/`：頂部工具列（閃光燈、計時器、名稱選單、比例選單、格線、翻轉），狀態來自 TASK-19
- 名稱選單只列名稱＋打勾（FR-7.11），移除 v1 的「管理設定檔」入口
- 底部列：左最新照片縮圖（來源依 PRD FR-15.2，資料來自 TASK-28；點擊先留空，TASK-29 接上）、快門（`accent` 實心＋外圈）、疊字鍵（`textformat`）。無文字、無底色
- 疊字鍵此時先打開 v1 的顯示設定 sheet 當過渡（TASK-22 換掉），**PR 描述要寫明**

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 21.1 | view model：名稱選單項目 | 只有設定檔名稱，順序同 `ProfileStore`；沒有「管理設定檔」項目 |
| 21.2 | view model：閃光燈按鈕狀態在前鏡頭 | disabled |
| 21.3 | view model：啟用中的工具（閃光燈自動、計時 3、格線開） | 三者 `isActive == true` |
| 21.4 | view model：本次開 App 尚未拍照、無讀取權限 | 縮圖為相片圖示狀態 |
| 21.5 | view model：拍一張後 | 縮圖為剛才的烘焙結果（不需讀取權限） |
| 21.6 | `grep -rn -e 'RoundedRectangle(cornerRadius: 20' -e 'padding(.horizontal, 8)' DaysCam/Views/CameraScreen.swift` | 無結果（觀景窗無圓角、無邊距） |
| 21.7 | `grep -rn 'preferredColorScheme(.light)' DaysCam/Views/` | 至少一處，作用在相機畫面根 view |

**驗收 — B′. 設計對照**（對照 `docs/design/D1-camera.html`）

| # | 步驟 | 預期結果 |
|---|---|---|
| 21.8 | `RenderPreview` 相機畫面 `#Preview`（3:4） | 版面、按鈕位置、顏色與 D-1 一致；按鈕無底色；翻轉在頂部最右 |
| 21.9 | 分別 preview 1:1、9:16 | 與 D-1 切換比例後的畫面一致 |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 21.10 | 系統切到深色模式開 App | 相機畫面仍為淺色 |

**依賴**：TASK-19、TASK-28

---

## TASK-22：疊字面板殼層

**目標**
PRD FR-8：面板展開收合、觀景窗縮放、底部列切換、分頁框架。分頁內容在 23～25。

**範圍**

- `Views/OverlayPanel/OverlayPanelModel.swift`：`isOpen`、`selectedTab`（樣式／格式／位置／天數規則，記住上次，PRD A-4）、`open()`、`close()`
- 展開時觀景窗縮到 80% 並置中（FR-8.2），彈簧動畫；只影響顯示
- 底部列切換（FR-8.3），快門縮到 64pt 且可拍
- 第一層分段控制（FR-8.4）；各分頁先放空白佔位
- 點觀景窗上疊字以外的區域收起（FR-8.7）
- 移除 TASK-21 的過渡 sheet

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 22.1 | 初始 `selectedTab` | 樣式 |
| 22.2 | 切到「位置」→ close → open | `selectedTab` 仍為位置 |
| 22.3 | 重建 model（模擬重開 App） | `selectedTab` 為樣式 |
| 22.4 | 面板打開時觸發拍照 | 拍照照常執行，面板保持打開 |
| 22.5 | 面板打開時的底部列 view model | 左為管理設定檔、右為收起；關閉時左為照片縮圖、右為疊字 |

**驗收 — B′. 設計對照**（對照 `docs/design/D2-overlay-panel.html`）

| # | 步驟 | 預期結果 |
|---|---|---|
| 22.6 | `RenderPreview` 面板打開狀態 | 觀景窗 80%、分段控制、底部列與 D-2 一致；面板無底色、無框線 |

**依賴**：TASK-18、TASK-21

---

## TASK-23：樣式分頁

**目標**
PRD FR-10。

**範圍**

- `Views/OverlayPanel/StyleTab*.swift` 與其 view model：第二層 5 個純圖示（FR-10.1）
- 字型列：每個選項用該字型寫自己的名稱，選中只變色（FR-10.2）
- 顏色與外框顏色：兩排色票、彩虹圓、「最近」（FR-10.4、10.6、10.7），最近清單來自 `RecentColorsStore`
- 外框、陰影：小色塊上只畫「Aa」（FR-10.5、10.8）
- 字級：滑桿 70～160、步進 5，顯示百分比
- 任何變更即時寫回（FR-8.6）

**驗收 — A. QA 可自動跑**（view model）

| # | 步驟 | 預期結果 |
|---|---|---|
| 23.1 | 第二層項目的無障礙標籤 | 恰好 `["字型","顏色","外框","陰影","字級"]`，且都沒有可見文字 |
| 23.2 | 字型選項數與順序 | 同 17.1 |
| 23.3 | 選 Futura | 設定檔 `style.fontID == .futura` 並已持久化（重新 load 仍是） |
| 23.4 | 文字顏色第一排 | 7 色（順序同 PRD FR-10.4）＋ 1 個自訂入口，共 8 項 |
| 23.5 | 外框顏色第一排 | 自動 ＋ 前 6 色 ＋ 自訂入口，共 8 項；初始選中「自動」 |
| 23.6 | ColorPicker 選 `#123456` 當文字顏色 | `style.textColor == #123456`；`recentCustomColors` 第一個是 `#123456`；外框顏色的「最近」排也出現它 |
| 23.7 | 外框為「無」 | 外框顏色整塊 disabled |
| 23.8 | 外框、陰影都選無 | 寫入成功，沒有任何警告狀態（FR-10.10） |
| 23.9 | 字級滑桿設 72 | 寫入值為 70 或 75（對齊步進），不是 72 |
| 23.10 | 字級滑桿範圍 | 最小 70、最大 160 |
| 23.11 | `grep -rn -e 'presets' -e '預設樣式' DaysCam/Views/OverlayPanel/` | 無結果（沒有模板） |

**驗收 — B′. 設計對照**（對照 `docs/design/D3-style-tab.html`）

| # | 步驟 | 預期結果 |
|---|---|---|
| 23.12 | 在 iPhone SE（375pt 寬）尺寸 preview 顏色與外框兩個項目 | 兩排色票都**不需橫向捲動**就完整顯示（FR-10.4） |
| 23.13 | 五個第二層各 preview 一次 | 版面與 D-3 一致 |

**依賴**：TASK-22

---

## TASK-24：格式分頁與位置分頁（含拖曳）

**目標**
PRD FR-11、FR-12。

**範圍**

- 格式分頁：第二層「顯示內容｜天數格式」（文字）。顯示內容沿用 `DisplaySettingsModel` 的開關互鎖；天數格式改成 4 個勾選框（FR-11.3、11.4），寫入 TASK-27 的 `displayUnits`
- 位置分頁：九宮格快速對齊＋位置名稱，無說明文字
- 觀景窗拖曳：**只在面板打開且位於「位置」分頁時**疊字可拖（`allowsHitTesting` 僅此時為 true），拖曳中即時夾進邊距，放開後存 `.custom`（FR-12.1～12.3）
- 拖曳換算用觀景窗實際尺寸（縮到 80% 後的尺寸），存成比例值

**驗收 — A. QA 可自動跑**

沿用 v1 驗收 11.8～11.14（顯示開關互鎖與疊字文字），改對新 view model 跑，全數通過。另外：

| # | 步驟 | 預期結果 |
|---|---|---|
| 24.1 | 格式第二層項目 | `["顯示內容","天數格式"]` |
| 24.2 | 天數格式初始（只勾天） | 天為勾選且 disabled（只剩一個），年月週未勾 |
| 24.3 | 勾年 → 勾週 | `displayUnits == [.year, .week, .day]`，**沒有**任何格子被自動取消 |
| 24.4 | 承 24.3，打開「年改成歲」→ 取消勾年 | 「年改成歲」自動關閉且 disabled |
| 24.5 | 關閉天數 | 天數格式 disabled，說明文字「天數未顯示，格式設定暫不作用」 |
| 24.6 | 在「樣式」分頁時的疊字 | 不接受拖曳 |
| 24.7 | 面板收起時的疊字 | 不接受拖曳（v1 FR-6.4 仍成立） |
| 24.8 | 在「位置」分頁拖曳換算：觀景窗 288×384，把中心拖到 (144, 192) | 存成 `.custom(x: 0.5, y: 0.5)` |
| 24.9 | 拖到 (400, 500)（超出觀景窗） | x、y 被夾到使框留在 4% 邊距內，值 ≤ 1 |
| 24.10 | 點九宮格「左上」 | `position == .anchor(.topLeading)`，位置名稱顯示「左上」 |
| 24.11 | `.custom` 狀態下的位置名稱 | 「自訂位置」 |

**驗收 — B′. 設計對照**（對照 `docs/design/D4-format-position-rules.html`）

| # | 步驟 | 預期結果 |
|---|---|---|
| 24.12 | preview 格式（兩個第二層）與位置分頁 | 與 D-4 一致 |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 24.13 | 在位置分頁把疊字拖到畫面左上附近後拍照 | 照片中的位置與觀景窗一致 |
| 24.14 | 自訂位置後切換比例 1:1、9:16 | 疊字落在相同的相對位置 |

**依賴**：TASK-22、TASK-27

---

## TASK-25：天數規則分頁

**目標**
PRD FR-13。

**範圍**

- 名稱行內編輯（20 字上限、清空還原）、compact `DatePicker`（上限今天）、起算分段控制
- 邏輯**沿用 `ProfileEditModel`** 的驗證
- 天數關閉時只留名稱＋說明

**驗收 — A. QA 可自動跑**

沿用 v1 TASK-06 的名稱驗證與起始日上限驗收。另外：

| # | 步驟 | 預期結果 |
|---|---|---|
| 25.1 | 輸入第 21 個字 | 被擋，名稱仍為 20 字 |
| 25.2 | 清空名稱後結束編輯 | 名稱還原為原值，未寫入空字串 |
| 25.3 | 起始日可選上限 | 2026-01-10（`DAYSCAM_FAKE_TODAY`） |
| 25.4 | 起算切到「第 0 天」 | 疊字 `第 9 天` |
| 25.5 | 關閉天數後的列 | 只有名稱，說明「天數未顯示，起始日與起算規則已隱藏」 |
| 25.6 | 起算分段控制的兩個選項文字 | 「當天算第 1 天」「第 0 天」，**兩者都在畫面內**（D-4 review 時曾因空間不足被裁掉） |

**驗收 — B′. 設計對照**：preview 天數規則分頁，三列完整顯示，與 D-4 一致。

**依賴**：TASK-22

---

## TASK-26：管理設定檔面板；刪除舊畫面

**目標**
PRD FR-9，並移除 v1 的 S-2、S-3、S-4。

**範圍**

- `Views/ProfileManager/`：清單、拖曳排序（`onMove`）、`⋯` 選單（複製、刪除）、刪除確認、新增
- 新增後：切換、關閉管理面板、疊字面板切到天數規則（FR-9.8）
- 刪除 `ProfileListView`、`ProfileEditView`、`DisplaySettingsSheet` 及只被它們使用的程式碼；仍被新介面使用的 model 保留
- 打勾圖示關閉鍵（FR-14.3）

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 26.1 | 列的副標 | 「2026/01/01 起」；天數關閉的設定檔為「只顯示日期」 |
| 26.2 | view model 裡沒有疊字預覽欄位 | `grep -rn -e 'overlayPreview' -e 'previewText' DaysCam/Views/ProfileManager/` 無結果 |
| 26.3 | 只剩 1 個時的刪除項目 | disabled，文字「刪除（至少保留 1 個）」 |
| 26.4 | 20 個時 | 新增 disabled「已達 20 個上限」；複製 disabled「複製（已達 20 個）」 |
| 26.5 | 新增 | 目前設定檔變成新的那筆；管理面板關閉；疊字面板 `selectedTab == 天數規則` |
| 26.6 | 刪除目前設定檔 | 切到清單中前一筆（沒有前一筆則下一筆），不崩潰 |
| 26.7 | `ls DaysCam/Views/ProfileListView.swift DaysCam/Views/ProfileEditView.swift DaysCam/Views/DisplaySettingsSheet.swift` | 三個檔案都不存在 |
| 26.8 | 完整測試 `xcodebuild ... test` | 全數通過（被刪畫面的 UI 測試一併移除，邏輯測試已移到新卡片） |

**驗收 — B′. 設計對照**：preview 管理面板，與 D-2 的管理設定檔一致；無疊字預覽、打勾關閉鍵。

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 26.9 | 拖曳排序後，打開頂部名稱選單 | 順序與管理面板相同；重開 App 仍保留 |

**依賴**：TASK-20、TASK-22

---

## TASK-27：天數單位改為任意勾選（計算與文字）

**目標**
PRD §4.5：`largestUnit`／`smallestUnit` 換成 `displayUnits`，計算與文字規則照 U-1～U-9，**v1 的輸出一字不變**。

**範圍**

- `CameraProfile`：移除 `largestUnit`、`smallestUnit`，新增 `displayUnits: Set<DisplayUnit>`（預設 `[.day]`）；讀 v1 檔時依 PRD §4.3 轉換
- 不變條件：`displayUnits` 非空；`useAgeWording` 需含 `.year`（取代 v1 不變條件 4、5）
- `DayCountCalculator`：新增依單位集合取整的方法（U-3、U-4、U-6），拍攝時刻仍由參數傳入（v1 §6.5）
- `TemplateRenderer.elapsedText`：改用集合，連接詞依 U-8
- 刪除 `DisplayUnitTrack` 與只被它使用的程式碼
- `DisplaySettingsModel`：`setLargestUnit`／`setSmallestUnit` 換成 `toggleUnit(_:)`（只剩一個時不可取消；取消年時關閉歲措辭）

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 27.1 | v1 TASK-04 的**全部**測試案例，把每組 `(largest, smallest)` 換成 PRD §4.3 對應的集合 | 預期文字**逐字相同**，全數通過 |
| 27.2 | 基準情境（2025-01-15、`dayOne`、拍攝 2026-03-20），勾「年、天」 | `1 年 64 天` |
| 27.3 | 同上，勾「年、月、週、天」 | `1 年 2 個月 5 天` |
| 27.4 | 同上，勾「月、週」 | `14 個月` |
| 27.5 | 起始日 2024-08-01、`dayOne`、拍攝 2026-01-22，勾「年、月、週」 | `1 年 5 個月 3 週` |
| 27.6 | 同 27.5，勾「月、週」 | `17 個月又 3 週`（兩個單位、不含年 → 「又」） |
| 27.7 | 同 27.5，勾「年、月」 | `1 年 5 個月`（含年 → 空格） |
| 27.8 | 起始日 2026-01-01、`dayOne`、拍攝 2026-01-10，勾「週、天」 | `1 週又 3 天`（套用 +1，n = 10） |
| 27.9 | 同 27.8，勾「月、天」 | `9 天`（不套用 +1，月為 0 省略） |
| 27.10 | 起始日 2024-02-29、拍攝 2025-02-28，勾「年、月、天」 | `1 年`（U-6，同 v1 §7.1） |
| 27.11 | v1 夾具 8 種 `(largest, smallest)` 讀入 | 分別轉成 PRD §4.3 的集合 |
| 27.12 | `displayUnits` 為空集合呼叫 `validate` | 拋錯 |
| 27.13 | `toggleUnit`：只勾天時取消天 | 無效，仍為 `[.day]` |
| 27.14 | `grep -rn -e 'largestUnit' -e 'smallestUnit' -e 'DisplayUnitTrack' DaysCam/` | 只出現在舊檔轉換的程式碼與其註解中 |

**依賴**：TASK-17

---

## TASK-28：已拍照片紀錄與讀取權限

**目標**
PRD FR-15.1～15.4 的資料層：記下 DaysCam 拍的照片，並以兩段式權限讀回來。

**範圍**

- `Services/CapturedPhotoStore.swift`：`capturedAssetIDs` 存 `Application Support/DaysCam/photos.json`，原子寫入（同 v1 §4.3 的做法）
- `PhotoSaver` 存檔成功後回傳新照片的 `localIdentifier`，由呼叫端寫入 store
- 讀取介面：`fetchAssets()` 回傳仍存在的照片（新的在前），並把已不存在的 ID 從檔案移除
- 權限：`requestReadAccessIfNeeded()` 請求 `.readWrite`；存檔路徑**仍只請求 `.addOnly`**
- 相簿存取抽成可注入的介面（沿用 v1 `PhotoSaver` 的做法），測試不碰真的相簿
- **先驗證 PRD A-7**：在實機以「限定照片」授權，確認讀得到 App 自己建立的照片；不成立時停下來回報 Lead

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 28.1 | 假相簿存檔成功（ID `A`、再存 `B`） | `capturedAssetIDs == ["B","A"]`，重建 store 後仍是 |
| 28.2 | 假相簿裡 `A` 已被刪除時 `fetchAssets()` | 只回傳 `B`；檔案內容變成 `["B"]` |
| 28.3 | 存檔流程呼叫的權限等級 | 只有 `.addOnly`，沒有 `.readWrite` |
| 28.4 | 首次呼叫 `requestReadAccessIfNeeded()` | 請求 `.readWrite` 恰好一次；已授權時不再請求 |
| 28.5 | `photos.json` 損毀 | 視為空清單，不崩潰（照片本身仍在相簿） |

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 28.6 | 全新安裝，拍照存檔 | 只出現「加入照片」權限彈窗 |
| 28.7 | 讀取權限選「限定照片」且不勾任何照片 | 仍讀得到 DaysCam 拍的照片（PRD A-7）。**不成立時回報 Lead** |

**依賴**：無

---

## TASK-29：照片瀏覽畫面

**目標**
PRD FR-15.5～15.10、設計稿 D-5。

**範圍**

- `Views/Gallery/`：瀏覽頁與其 view model（目前張、張數、標題、刪除後的選位、空狀態、權限被拒狀態）
- 相機畫面左下縮圖點擊 → 請求讀取權限（TASK-28）→ 進入瀏覽頁
- 大圖左右滑動、縮圖列、系統刪除確認（`PHAssetChangeRequest.deleteAssets`）
- 標題日期用 `PHAsset.creationDate`，**只用於顯示**（PRD §7）

**驗收 — A. QA 可自動跑**（view model＋假相簿）

| # | 步驟 | 預期結果 |
|---|---|---|
| 29.1 | 6 張照片進入 | 顯示最新一張，標題副標「1 / 6」 |
| 29.2 | 刪除第 3 張 | 顯示原本的第 4 張（現在的第 3 張），副標「3 / 5」 |
| 29.3 | 刪除最後一張（第 5 / 5） | 顯示上一張 |
| 29.4 | 刪完全部 | 空狀態，文字「還沒有照片」 |
| 29.5 | 權限 `.denied` | 權限被拒狀態，有「前往設定」 |
| 29.6 | 畫面上的按鈕 | 只有回相機（打勾圖示）、刪除；沒有分享、編輯 |
| 29.7 | `grep -rn -e 'UIActivityViewController' -e 'ShareLink' DaysCam/` | 無結果（FR-15.9） |
| 29.8 | `grep -rn 'creationDate' DaysCam/Services/` | 無結果（拍攝日期只在 `Views/Gallery/` 顯示，不進入計算層） |

**驗收 — B′. 設計對照**（對照 `docs/design/D5-gallery.html`）：有照片、空狀態、權限被拒三種狀態各 preview 一次。

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 29.9 | 第一次點左下縮圖 | 跳出讀取權限彈窗；同意後進入瀏覽頁 |
| 29.10 | 在「照片」App 刪掉一張 DaysCam 照片後回 App 瀏覽 | 那張不在清單中 |
| 29.11 | 在瀏覽頁刪除 | 系統確認框出現；確認後照片進入「最近刪除」 |

**依賴**：TASK-21、TASK-28

---

## TASK-30：端對端整合驗收

**目標**
v2 全部功能串起來驗一次，並回歸 v1 的核心保證。

**驗收 — A. QA 可自動跑**

| # | 步驟 | 預期結果 |
|---|---|---|
| 30.1 | 全新安裝 `DAYSCAM_FAKE_TODAY=2026-01-10` 啟動 | 直接進相機畫面、疊字 `第 1 天`、淺色主題、3:4、閃光燈關（v1 G-1） |
| 30.2 | 放一份 v1 格式的 `profiles.json`（5 筆、5 種主題、各種單位組合）後啟動 | 5 筆都在，樣式照 PRD §4.3，疊字文字與 v1 相同 |
| 30.3 | 完整測試 `xcodebuild ... test` | 全數通過 |
| 30.4 | `grep -rn 'kCGImagePropertyExif' DaysCam/` | 無結果 |
| 30.5 | 只顯示日期，跨日重啟（2026-01-10 → 2026-01-11） | `2026.01.11`，不是 `第 2 天`（v1 FR-2.17） |

**驗收 — B′. 設計對照**：D-1～D-5 每個畫面各 preview 一次，與設計稿逐一對照，差異列成清單回報。

**驗收 — B. 需人類實機**

| # | 步驟 | 預期結果 |
|---|---|---|
| 30.6 | 建兩個設定檔，各自設不同的字型、顏色、外框與外框顏色、陰影、字級、單位組合、自訂位置；三種比例各拍一張 | 每張照片的疊字與拍攝時的觀景窗一致 |
| 30.7 | 面板打開時拍照 | 可拍，面板不關 |
| 30.8 | 計時 3 秒，跨午夜（23:59:58 按下） | 照片為新的一天的天數 |
| 30.9 | 拍幾張後點左下縮圖 | 瀏覽頁列出剛拍的照片，最新在前 |
| 30.10 | AirDrop 到另一台裝置 | 疊字不變（v1 G-4） |

**依賴**：全部
