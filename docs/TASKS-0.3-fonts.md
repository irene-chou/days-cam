# DaysCam 0.3 繁中字型任務清單

- 版本：0.3
- 日期：2026-10-06
- 上游：[`PRD-0.3-fonts.md`](./PRD-0.3-fonts.md)、[`design/D6-font-picker.html`](./design/D6-font-picker.html)（方案 C）、Issue #162
- 接續 [`TASKS-0.2-ui-redesign.md`](./TASKS-0.2-ui-redesign.md)（TASK-17～30），編號從 TASK-31 開始

---

## 怎麼用這份文件

驗收分級、共用測試情境、指令規則沿用 [TASKS-0.2 開頭](./TASKS-0.2-ui-redesign.md#怎麼用這份文件)。A 級由開發者在本機跑相關測試 class 自驗；完整測試只在升版 PR 由 CI 執行（[WORKFLOW 開發第 5 點](./WORKFLOW.md#開發)）。

**開工條件**：0.2 全部合併、TASK-30 通過、`MARKETING_VERSION` 升為 `0.2.0` 之後。

### 事先預告：會讓你誤判的地方

1. **0.2 驗收 17.12（10 種字型都能取得）會失效，這是預期的。** 10 種英文字型在 TASK-32 移除，由 32.x 取代。不要為了讓舊測試通過而保留舊 case。
2. **0.2 FR-10.3「中文由蘋方補字、不得指定 fallback」已廢除**（PRD-0.3 FR-10.3′）。看到疊字中文改用所選字型畫出不是 bug；但仍**不得**為缺字另外指定 fallback 字型清單，缺字交給系統。
3. **0.2 的「未知 `fontID` 改用 `sfRounded`」改成 `pingFang`**。舊設定檔升級後字型全部變蘋方是 PRD-0.3 §4.3 的預期結果，不是遷移遺失。
4. **系統字型在模擬器第一次比對會真的連網下載**（數 MB 到 66 MB）。單元測試一律注入假比對介面；只有標明的整合測試會連網，沒網路時略過並在 PR 註明。
5. **字型解析回傳蘋方不一定是 bug**：字型不是 `available` 時，觀景窗與照片**都**用蘋方是規格（FR-5.14、FR-16.14）。要檢查的是兩邊一致。

---

## 依賴結構

```
TASK-31 Lead：字型檔下載點、預覽圖、授權文字
TASK-32 core-style：字型清單、OverlayFontID、舊檔轉換、字型解析
   └─► TASK-33 core-device：FontLibrary（下載、驗證、註冊、比對、刪除）
          ├─► TASK-34 ui-panel：字型格子、更多字型清單、字型授權頁（依 31、32、33）
          └─► TASK-35 ui-shell：啟動準備、快門保護、需重新下載提示（依 32、33）
TASK-36 qa：0.3 端對端整合驗收 → Lead 升版 0.3.0
```

TASK-34 可在 TASK-33 合併前先用 TASK-32 定義的介面加假實作開工，但合併要等 33。

## 檔案所有權（0.3 增補，其餘照 [TASKS-0.2](./TASKS-0.2-ui-redesign.md#檔案所有權)）

| 擁有者 | 新增或變更的檔案 |
|---|---|
| core-style | `Models/OverlayStyle.swift`（`OverlayFontID`）、`Models/FontCatalog.swift`（新）、`Services/OverlayMetrics.swift` |
| core-device | `Services/FontLibrary.swift`（新）、`Services/FontDownloader.swift`（新，若拆檔） |
| ui-panel | `Views/OverlayPanel/StyleTabView.swift`、`StyleTabModel.swift`、`Views/OverlayPanel/FontLibraryView.swift`／`FontLibraryModel.swift`（新）、`Views/OverlayPanel/FontLicenseView.swift`（新） |
| ui-shell | `CameraScreenModel.swift`、`CameraScreen.swift`、`DaysCamApp.swift` |
| Lead | 外部 repo `irene-chou/dayscam-fonts`、`scripts/render-font-previews.swift`（新）、`DaysCam/Assets.xcassets/FontPreviews/`（新，**例外**：預覽圖由 Lead 產生）、`DaysCam/Resources/FontLicenses/`（新） |

---

## TASK-31：字型下載點、預覽圖、授權文字

**負責**：Lead

**目標**
PRD-0.3 §4.2 的開源字型資產，以及 FR-16.4 預覽圖、FR-16.13 授權文字。

**範圍**

- 建立公開 repo `irene-chou/dayscam-fonts`：`jf-openhuninn-2.1.ttf`、`Iansui-Regular.ttf`（取自官方 v1.020 release）、`NotoSerifTC-Bold.otf`（noto-cjk SubsetOTF），每套附上游授權全文與 README（來源、版本、授權）。打 tag `v1`
- 在本 repo 新增 `docs/fonts-manifest.md`：每套的 `fontID`、檔名、位元組大小、SHA-256、jsDelivr 與 GitHub raw 網址、PostScript 名稱
- `scripts/render-font-previews.swift`：用真字型把 21 套名稱畫成 @2x／@3x 模板圖，輸出到 `Assets.xcassets/FontPreviews/<fontID>.imageset`
- `DaysCam/Resources/FontLicenses/`：3 套開源字型的授權全文（粉圓另附 Apache-2.0）
- `docs/fonts-manifest.md` 另列每套的版本與著作權聲明（取自授權檔首段），供 TASK-32 寫進 FontCatalog

**驗收 — A.**

| # | 步驟 | 預期結果 |
|---|---|---|
| 31.1 | 對 manifest 的每個 jsDelivr 與 GitHub raw 網址下載 | 6 個網址都 200，大小與 SHA-256 與 manifest 一致 |
| 31.2 | `ls DaysCam/Assets.xcassets/FontPreviews` | 21 個 imageset，`fontID` 與 PRD-0.3 §4.1 一致 |
| 31.3 | `ls DaysCam/Resources/FontLicenses` | 4 個授權檔（3 套 OFL＋粉圓 Apache-2.0） |

**依賴**：PRD-0.3 合併

---

## TASK-32：字型清單、`OverlayFontID`、舊檔轉換、字型解析

**負責**：core-style　**風險**：high（設定檔遷移、烘焙一致性）

**目標**
PRD-0.3 §4.1、§4.3、§4.4、FR-5.14、FR-10.3′ 的模型與渲染層。

**範圍**

- `OverlayFontID` 換成 21 個 case（PRD §4.1 順序），未知值（含 0.2 的 10 種）解碼為 `pingFang`；`OverlayStyle.fontID` 預設 `pingFang`
- `Models/FontCatalog.swift`：每個 `fontID` 的顯示名稱、分段、來源（內建／開源／系統）、PostScript 名稱、下載大小；開源字型另含檔名、位元組數、SHA-256、主要與備援網址、版本、著作權聲明、授權檔名（值取自 TASK-31 的 `docs/fonts-manifest.md`）
- 字型狀態型別（PRD §4.4）與唯讀介面 `FontAvailabilityProviding`（`state(for:) -> FontState`），供 TASK-33 實作、TASK-34／35 使用
- `OverlayMetrics.font(for:size:availability:)`：`available` 時回傳該字型；其他狀態回傳 `PingFangTC-Semibold`。觀景窗（`renderText`）與烘焙走同一個函式。移除 0.2 FR-10.3 的蘋方補字註解與假設
- 字重固定為 §4.1 的 PostScript 名稱，不做字重選擇

**驗收 — A.**

| # | 步驟 | 預期結果 |
|---|---|---|
| 32.1 | `OverlayFontID.allCases` | 21 個，順序、顯示名稱、分段、來源與 PRD §4.1 一致 |
| 32.2 | 解碼 `"futura"`、`"sfRounded"`、`"不存在"` | 都是 `pingFang`；含該值的設定檔 JSON 讀取後筆數不變 |
| 32.3 | 0.2 格式 `profiles.json` 夾具（10 種舊字型各一筆）讀取、存回 | 10 筆都在，`fontID` 全為 `pingFang`，其他樣式欄位不變 |
| 32.4 | 0.1 格式夾具（沿用 TASK-17 的夾具） | 照 0.2 §4.3 轉換，字型為 `pingFang` |
| 32.5 | 假 availability 回傳 `available` 的開源字型（測試內以 `CTFontManagerRegisterFontURLs` 註冊 TASK-31 的檔案，或用測試夾具字型） | 解析出的 `UIFont.fontName` 為該字型的 PostScript 名稱 |
| 32.6 | 假 availability 回傳 `notDownloaded`／`preparing`／`failed` | 解析出 `PingFangTC-Semibold` |
| 32.7 | 同一 style 與 availability 下，觀景窗 `renderText` 與烘焙使用的字型 | `fontName` 相同（以注入的解析函式或間諜驗證） |
| 32.8 | `pingFang` 解析 | `PingFangTC-Semibold`，不需 availability 也可用 |
| 32.9 | FontCatalog 開源 3 套的大小、SHA-256、版本、著作權聲明 | 與 `docs/fonts-manifest.md` 一致（測試讀死值比對即可） |

**依賴**：TASK-31（manifest 數值）

---

## TASK-33：FontLibrary（下載、驗證、註冊、比對、刪除）

**負責**：core-device　**風險**：high（網路、檔案持久化、啟動流程）

**目標**
PRD-0.3 §4.2、§4.4、FR-16.6～16.12、FR-16.14、FR-5.15 的服務層。

**範圍**

- `Services/FontLibrary.swift`：`ObservableObject`，實作 `FontAvailabilityProviding`，發布每個 `fontID` 的 `FontState`
- 開源字型：下載（先 jsDelivr、失敗改 GitHub raw）→ 驗證大小與 SHA-256 → 存 `Application Support/Fonts/<fontID>.<ext>`（`isExcludedFromBackup`）→ `CTFontManagerRegisterFontURLs(.process)`。驗證失敗刪檔並 `failed`
- 系統字型：`CTFontDescriptorMatchFontDescriptorsWithProgressHandler` 下載與比對；以「最後是否比對成功」判定，不因中途錯誤（如 #302）就判失敗（調查報告註 1）
- `download(_:)`、`cancel(_:)`、`delete(_:)`（只限開源，刪檔並取消註冊）、`prepareAtLaunch(priority:)`（目前設定檔的字型優先，回傳完成或 3 秒逾時）、`cancelAllDownloads()`（App 退到背景時呼叫，FR-16.11）
- `downloadedSystemFontIDs` 存 `UserDefaults`：系統字型下載成功時加入；啟動只比對清單內的字型，比對開始回報需要下載（已被系統清掉）時取消、移除並視為 `notDownloaded`，不得自動下載（PRD FR-5.15）
- 失敗原因至少區分「沒網路」與「其他」
- 網路、檔案系統、CoreText 比對都抽成可注入介面，單元測試不連網
- 刪除後「用到它的設定檔改 `pingFang` 並存檔」由本卡提供 `ProfileStore` 方法（`replaceFont(_:with:)`）

**驗收 — A.**

| # | 步驟 | 預期結果 |
|---|---|---|
| 33.1 | 假網路回傳正確檔案 | 狀態 `notDownloaded → downloading → available`；檔案在 `Application Support/Fonts/`、已設不備份；註冊被呼叫一次 |
| 33.2 | 假網路回傳 SHA-256 不符的檔案 | `failed(.other)`，檔案不存在，未註冊 |
| 33.3 | 主要網址失敗、備援成功 | `available`，兩個網址各被請求一次 |
| 33.4 | 假網路回報沒網路 | 立即 `failed(.offline)` |
| 33.5 | 下載中 `cancel` | 回到 `notDownloaded`，暫存檔已清 |
| 33.6 | `delete(.huninn)` | 檔案不存在、取消註冊、狀態 `notDownloaded`；`delete` 系統字型或 `pingFang` 被拒絕 |
| 33.7 | 重建 FontLibrary（模擬重開 App），檔案存在 | `prepareAtLaunch` 後開源字型為 `available`；不重新下載 |
| 33.8 | 重開時檔案被刪或 SHA-256 不符 | `notDownloaded`／`failed`，不崩潰 |
| 33.9 | 假比對器：系統字型比對成功、途中回報錯誤但最後成功 | 皆為 `available` |
| 33.10 | 假比對器不回應 | `prepareAtLaunch` 3 秒逾時回傳，該字型變 `failed(.other)`，可再呼叫 `download` 重試；不阻塞其他字型 |
| 33.10a | `downloadedSystemFontIDs = ["xingkai"]`，假比對器在開始時回報下載量 > 0 | 比對被取消、未下載任何位元組；`xingkai` 從清單移除且為 `notDownloaded` |
| 33.10b | `downloadedSystemFontIDs` 為空 | 啟動不比對任何系統字型 |
| 33.10c | 兩套下載中呼叫 `cancelAllDownloads()` | 兩套皆 `failed(.other)`，暫存檔已清 |
| 33.11 | `replaceFont(.huninn, with: .pingFang)` | 用到粉圓的設定檔全部改成蘋方並寫檔；其他設定檔不變 |
| 33.12 | 整合測試（模擬器、需網路）：實際比對 `LiHeiPro` | `available`，`UIFont(name: "LiHeiPro")` 非 nil。沒網路時略過並在 PR 註明 |

**驗收 — B.**

| # | 步驟 | 預期結果 |
|---|---|---|
| 33.13 | 實機下載粉圓與行楷，殺掉 App 重開 | 兩套仍可用，粉圓不重新下載 |
| 33.14 | 飛航模式下載 | 顯示沒網路；關掉飛航後重試成功 |

**依賴**：TASK-32

---

## TASK-34：字型格子、更多字型清單、字型授權頁

**負責**：ui-panel　**風險**：normal

**目標**
PRD-0.3 FR-10.2′、FR-16，設計稿 D-6 方案 C。

**範圍**

- `StyleTabView` 字型格子：只列 `available` 的字型（§4.1 順序）＋「更多字型」格；目前字型不可用時的「需重新下載」格（FR-10.2′.4）
- `FontLibraryView`／`FontLibraryModel`：全螢幕清單，外觀同管理設定檔；分段、預覽圖、右側狀態、點列的行為、「⋯」刪除選單、提示文字（FR-16.1～16.12）
- `FontLicenseView`：讀 `Resources/FontLicenses/`（FR-16.13）
- 狀態與文字邏輯在 view model，用假 `FontAvailabilityProviding`＋假動作測
- 每個主要狀態提供 `#Preview`：格子（只有蘋方、有 3 套已下載、目前字型需重新下載）、清單（未下載、下載中、失敗、已下載）

**驗收 — A.**

| # | 步驟 | 預期結果 |
|---|---|---|
| 34.1 | 只有蘋方可用 | 格子 = [蘋方, 更多字型] |
| 34.2 | 粉圓、行楷可用 | 格子 = [蘋方, 粉圓, 行楷, 更多字型]（§4.1 順序） |
| 34.3 | 目前字型為行楷但 `notDownloaded` | 格子含行楷且為選中，副標「需重新下載」 |
| 34.4 | 清單分段 | 9 段，標題與每段字型與 §4.1 一致 |
| 34.5 | 各狀態的右側文字 | 未下載「43.7 MB」（宋體）、下載中「38%」、失敗「重試」、已下載開源有「⋯」、系統與蘋方無 |
| 34.6 | 點未下載 → 假下載完成 | 呼叫 `download` 一次；完成後目前設定檔 `fontID` 變成它；下載完成前 `fontID` 不變 |
| 34.7 | 點下載中 | 呼叫 `cancel`，提示「已取消下載」 |
| 34.8 | 「⋯」› 刪除，有 2 個設定檔使用 | 選單文字含「2 個設定檔正在使用」；確認後呼叫 `delete` 與 `replaceFont` |
| 34.9 | 系統字型列 | 沒有「⋯」 |
| 34.10 | 授權頁 | 列出 3 套開源字型，各有名稱、版本、著作權聲明與授權全文（粉圓另有 Apache-2.0）；註明系統字型由 Apple 提供 |
| 34.11 | `grep -rn -e 'UIActivityViewController' -e 'ShareLink' -e 'fileExporter' DaysCam/Views/OverlayPanel/` | 無結果（PRD-0.3 §7 不得匯出字型檔） |

**驗收 — B′.** 對照 D-6 方案 C：格子與清單的各狀態 Preview 截圖。

**驗收 — B.**

| # | 步驟 | 預期結果 |
|---|---|---|
| 34.12 | 實機進更多字型，下載粉圓 | 進度正確，完成後自動套用，觀景窗立即變粉圓 |
| 34.13 | 用粉圓拍照 | 照片疊字與觀景窗一致 |

**依賴**：TASK-31、32、33（可先以介面開工）

---

## TASK-35：啟動準備、快門保護、需重新下載提示

**負責**：ui-shell　**風險**：normal

**目標**
PRD-0.3 FR-5.15、FR-5.16、FR-16.14 的畫面接線。

**範圍**

- `DaysCamApp`／`CameraScreenModel`：啟動時呼叫 `FontLibrary.prepareAtLaunch`，目前設定檔的字型優先
- 目前設定檔字型為 `preparing` 時快門停用；完成或 3 秒逾時後恢復
- 字型不可用時（非 `available`、非 `preparing`），開面板或切到該設定檔時提示一次「「<名稱>」需要重新下載，暫時用蘋方」
- 觀景窗與烘焙都把 `FontLibrary` 傳給 `OverlayMetrics` 的解析函式
- 觀景窗疊字圖片快取（`OverlayTextView.swift` 的 `OverlayTextRenderCache.Key`）必須包含**解析後的字型 PostScript 名稱**，字型狀態由 `preparing`／`notDownloaded` 變 `available`（或反向）時一定重畫，不得沿用舊的蘋方圖片（FR-5.14）
- `scenePhase` 變成 `.background` 時呼叫 `FontLibrary.cancelAllDownloads()`（FR-16.11）

**驗收 — A.**

| # | 步驟 | 預期結果 |
|---|---|---|
| 35.1 | 假 FontLibrary：目前字型 `preparing` | 快門停用；變 `available` 後啟用 |
| 35.2 | 假 FontLibrary 3 秒不回應 | 3 秒後快門啟用，觀景窗用蘋方 |
| 35.3 | 切到字型 `notDownloaded` 的設定檔 | 提示文字出現一次；再切回來不重複（同一次啟動內） |
| 35.4 | 烘焙路徑 | 拿到的 availability 與觀景窗是同一個實例 |
| 35.4b | 假 FontLibrary 先 `preparing` 再變 `available`，期間取觀景窗疊字圖片兩次 | 第二次圖片的字型為該字型（快取未命中舊的蘋方圖片）；反向（`available` → `notDownloaded`）同理變回蘋方 |
| 35.4a | 模擬 `scenePhase` 變 `.background` | 假 FontLibrary 的 `cancelAllDownloads` 被呼叫一次 |

**驗收 — B.**

| # | 步驟 | 預期結果 |
|---|---|---|
| 35.5 | 實機用行楷，殺 App 重開後立刻按快門 | 照片是行楷，不是蘋方 |

**依賴**：TASK-32、33

---

## TASK-36：0.3 端對端整合驗收

**負責**：qa

**驗收 — A.**

| # | 步驟 | 預期結果 |
|---|---|---|
| 36.1 | 0.2 格式 `profiles.json`（含 10 種舊字型）啟動 | 筆數不變，字型全為蘋方，疊字可畫 |
| 36.2 | 完整測試 `xcodebuild ... test`（本機） | 全數通過。例外同 TASKS-0.2 30.3：整合驗收保留本機全套 |
| 36.3 | `grep -rn 'kCGImagePropertyExif' DaysCam/` | 無結果 |
| 36.4 | `grep -n 'MARKETING_VERSION' project.yml` | `"0.3.0"`，由 Lead 在其餘 A 級通過後修改 |

**驗收 — B′.** D-6 方案 C 對照。

**驗收 — B.** 33.13、33.14、34.12、34.13、35.5 在同一台實機重跑；另加：全新安裝不下載任何字型，拍照為蘋方；空間不足時（可略）。

**依賴**：全部
