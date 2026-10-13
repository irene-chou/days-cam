# 開發約定：檔案所有權、驗收分級、易誤判處

任務卡改用 GitHub issue；原本 `TASKS*.md` 中仍有效的共用規則整理於此。卡片歷史以 issue／PR 與 git 歷史為準。

## 驗收分級

| 級別 | 含義 | 誰執行 |
|---|---|---|
| **A. 可自動跑** | 單元測試、靜態檢查、view model 測試、模擬器 UI 操作 | 開發者在本機跑相關測試 class 自驗（完整測試由 CI 分片執行，見 [WORKFLOW 開發](WORKFLOW.md#開發)），reviewer 核對；`risk:high` 卡另由獨立 QA 驗收 |
| **B′. 設計對照** | 截 SwiftUI `#Preview` 或模擬器畫面，與 `docs/design/` 設計稿並排比對版面、顏色、間距 | agent；結果截圖貼 PR 由人類確認 |
| **B. 需人類實機** | 相機、閃光燈、實際拍照與烘焙結果目視、相簿權限彈窗 | 人類 |

**共用測試情境**（卡片另寫除外）：`DAYSCAM_FAKE_TODAY=2026-01-10`（`#if DEBUG` 時間覆寫），設定檔「小寶」起始日 2026-01-01、`dayOne`、只顯示天數 → 疊字 `第 10 天`。

**設計稿是視覺依據，PRD 是規格依據**，兩者衝突時照 PRD。驗收指令寫法見 [WORKFLOW 驗收指令規則](WORKFLOW.md#驗收指令規則)。

## 檔案所有權

**一個檔案只有一個擁有者。需要改別人的檔案時，回報 Lead，不要自己動手。**

| 擁有者 | 檔案 |
|---|---|
| core-style | `Models/`（`CaptureSettings.swift` 除外，含 `OverlayStyle.swift`、`FontCatalog*.swift`）、`Services/OverlayMetrics.swift`、`OverlayRenderer.swift`、`TemplateRenderer.swift`、`DayCountCalculator.swift`、`RecentColorsStore.swift` |
| core-device | `Models/CaptureSettings.swift`、`Services/CameraService.swift`、`CaptureSettingsStore.swift`、`ImageCropper.swift`、`ProfileStore.swift`、`PhotoSaver.swift`、`CapturedPhotoStore.swift`、`AlbumSettingsStore.swift`、`FontLibrary.swift`、`FontDownloader.swift` |
| ui-shell | `Views/` 下除了 ui-panel 那幾項以外的全部（含 `CameraScreen.swift`、`CameraScreenModel.swift`、`OverlayTextView.swift`、`ProfileListModel*.swift`、`Views/Theme/`、`Views/CameraToolbar/`、`Views/ProfileManager/`、`Views/Gallery/`）、`DaysCamApp.swift`、`Assets.xcassets`（`FontPreviews/` 除外） |
| ui-panel | `Views/OverlayPanel/` 下各分頁的 View 與 view model（含 `StyleTab*`、`FontLibrary*`、`FontLicenseView`；面板殼層 `OverlayPanelModel` 與容器 View 屬 ui-shell）、`Views/DisplaySettingsModel.swift`、`Views/ProfileEditModel.swift` |
| qa | `DaysCamTests/Acceptance/`。**不得修改任何產品程式碼**，發現 bug 回報不自己修 |
| Lead | `project.yml`、`.gitignore`、`README.md`、`docs/**`、`AGENTS.md`、`CLAUDE.md`、`.claude/`、`.codex/`、`.github/`、`scripts/`、`Assets.xcassets/FontPreviews/`、`Resources/FontLicenses/`、外部 repo `irene-chou/dayscam-fonts` |

- **單元測試**：`DaysCamTests/Unit/<來源檔名>Tests.swift` 歸該來源檔的擁有者，隨實作一起寫。
- **`project.yml` 只有 Lead 能改。** `sources` 是資料夾 glob，新增 `.swift` 檔不需要動它。

## 易誤判處（不要報成回歸）

1. **自訂與系統字型是規格**：`UIFont(name:)` 用於系統內建字型與下載的開源字型（PRD-0.3 §4.1），不是違規。中文用所選字型畫出不是 bug，但仍不得為缺字另外指定 fallback 字型清單。
2. **`OverlayTheme` 沒有固定 5 組主題**：它是由 `OverlayStyle` 產生的渲染值，允許無裝飾（PRD-0.2 FR-10.10）。
3. **天數單位是任意勾選**：0.1 的「單位軌道」（`DisplayUnitTrack`、最小單位隨最大單位夾取）已刪除；舊 `(largest, smallest)` 對應到單位集合後，輸出文字必須與 0.1 相同（PRD-0.2 §4.3、§4.5）。
4. **舊畫面已刪**：0.1 的顯示設定面板、清單與編輯頁、切換選單不存在；其邏輯（FR-2.4 開關互鎖、名稱 1～20 字等）由新 view model 測試涵蓋。
5. **相簿權限兩段式**：存檔只請求 `.addOnly`，照片瀏覽才請求 `.readWrite`（例外見 AGENTS.md Code Review Rules）；啟動時不得詢問相簿權限。
6. **未知 `fontID` 改用蘋方**：舊設定檔升級後字型變蘋方是 PRD-0.3 §4.3 的預期結果，不是遷移遺失。
7. **字型解析回傳蘋方不一定是 bug**：字型不是 `available` 時，觀景窗與照片都用蘋方（FR-5.14、FR-16.14），要檢查的是兩邊一致。
8. **系統字型第一次比對會真的連網下載**（數 MB 到 66 MB）。單元測試一律注入假比對介面；只有標明的整合測試會連網，沒網路時略過並在 PR 註明。
9. **日期的渲染路徑永不讀取 `startDate`**（PRD FR-2.17）；**`startDate` 不可夾帶 `timeZone`**（PRD §4.1 不變條件 2）。
10. **`CameraScreen.swift` 由 ui-shell 獨佔**；ui-panel 要在觀景窗上加東西時向 ui-shell 提需求。
