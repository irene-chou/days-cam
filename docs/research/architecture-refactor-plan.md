# CameraScreenModel 拆分、@Observable 與 strict concurrency 遷移規劃（TASK-135）

> 調查卡產出，**草稿**。依驗收 135.3，人類 review 本文件之前不開任何實作卡。
> 程式碼行號以 main `1eccba4` 為準（`CameraScreenModel.swift` 與 issue 所寫的 `2af1e1c` 相同）。

## 0. 結論摘要

1. **先修資料安全，再談架構**：`TabProfileWriter` 的「漏欄位就默默丟改動」風險，用一個守門測試（R0）立刻擋住，不必等重構。
2. **拆分與 @Observable 一起做**：從 `CameraScreenModel` 拆出的新物件一出生就是 `@Observable`，舊物件保留**轉接屬性（facade）**，讓既有測試與 qa 擁有的驗收測試不用跟著改，每一步都能單獨合併。
3. **順序**：守門測試 → 葉節點 `@Observable` → `@MainActor` 補齊 → 拆 `CameraScreenModel`（呈現 → 縮圖 → 字型 → 疊字編輯 → 拍攝）→ `CameraScreenModel` 本身轉 `@Observable` → strict concurrency `targeted` → `complete`。
4. **與進行中卡片的衝突**：TASK-122（#458）、TASK-128（#468）、TASK-129（#469）都改 `CameraScreenModel.swift`；TASK-124（#464）、TASK-134（#474）改 `ProfileStore`；TASK-125／130／131 改 `CameraService`；TASK-132 改 `FontLibrary`。拆分步驟必須排在它們之後（見 §7）。
5. **`DaysCamCore` SPM**：現在不做。等 strict concurrency `complete` 後再評估，最小版本只放純計算（見 §6）。
6. **135.2 的 `targeted` 試編譯尚未執行**（Lead 指示本卡不跑 xcodebuild），§5.1 附指令與預期分類，待 Lead 指派 rinclaw 執行後補數字。

---

## 1. 現況盤點

### 1.1 `CameraScreenModel` 的職責（1691 行）

| # | 職責 | 位置（約） | 目標歸屬 |
|---|---|---|---|
| 1 | 組裝依賴（init 20 個參數、建 zoom／focus model） | L301–416 | 留在 `CameraScreenModel`（composition root） |
| 2 | 鏡像 `profileStore.profiles`／`selectedProfileID` | L101–103、L418–445 | `CameraScreenModel` |
| 3 | 建立樣式／內容／位置分頁 model、寫入合併 | L472–514、L1546–1627 | `OverlayEditingCoordinator` |
| 4 | 轉發 `cameraService` 變動、推導權限／狀態 | L523–535、L702–760 | `CameraScreenModel`（推導屬性） |
| 5 | 首次導覽接線 | L536–548、L826–837 | `CameraScreenModel` |
| 6 | 變焦接線 | L550–582 | `CameraScreenModel` |
| 7 | 對焦接線 | L584–616 | `CameraScreenModel` |
| 8 | 拍攝設定轉發、工具列（閃光燈／計時／比例／格線） | L618–627、L913–1040 | `CameraScreenModel`（薄轉接） |
| 9 | 面板開關、觀景窗點擊路由 | L629–647、L984–1034 | `CameraScreenModel` |
| 10 | 跨日／回前景刷新 `refreshTick` | L649–670 | `CameraScreenModel` |
| 11 | 疊字預覽推導（文字／樣式／字型／位置） | L762–800 | `CameraScreenModel` |
| 12 | 設定檔管理、圖庫的開關 | L802–859、L902–911 | `PresentationState` |
| 13 | 縮圖載入與刷新 | L861–900 | `ThumbnailProvider` |
| 14 | 快門、倒數 | L1043–1160 | `CaptureController` |
| 15 | 裁切／烘焙／存檔管線 | L1204–1294 | `CaptureController` |
| 16 | 錯誤 alert、toast | L1296–1333 | `PresentationState` |
| 17 | 字型協調（pending 套用、3 秒逾時、不可用提示） | L1335–1545 | `FontCoordinator` |
| 18 | 飛行動畫 | L1629–1691 | `CaptureController` 產生，`ThumbnailProvider` 收尾 |

### 1.2 為什麼整個畫面一起重算

`CameraScreen`、`CameraToolbar`（兩個 struct）、`OverlayPanelView` 都 `@ObservedObject var model: CameraScreenModel`。`CameraScreenModel` 有 21 個 `@Published`，另外把 5 個子物件的 `objectWillChange` 轉發給自己：

- `cameraService`（L523）、`onboarding`（L536）、`captureSettingsStore`（L618）、`panelModel`（L629）、`fontLibrary`（L1458，含逾時 Task 的 `objectWillChange.send()` L1529）
- 另有 `zoomModel.$isPinching` 部分轉發（L569）

ObservableObject 沒有屬性層級的追蹤，所以倒數每秒、toast、字型下載進度、滑桿每格寫入（經 `profileStore.$profiles` → `profiles`）都讓三個 view 的 body 全部重算。

### 1.3 `TabProfileWriter`

- 樣式／內容／位置三個 tab model 與設定檔編輯頁的 `RulesTabModel`，各自持有完整 `CameraProfile` 副本，`updateProfile` 每次送出整份。
- `TabProfileWriter.merging`（L1613–1626）手寫 10 個欄位逐一比對。目前**有涵蓋** `CameraProfile` 全部可變欄位（`id`／`createdAt`／`updatedAt` 刻意排除），但沒有任何機制保證之後新增欄位時會記得加。

### 1.4 Observation 與並行標註

| 型別 | 擁有者 | ObservableObject | `@MainActor` |
|---|---|---|---|
| `CameraScreenModel`、`ViewfinderZoomModel`、`ViewfinderFocusModel`、`ZoomPresetExpansion`、`GalleryModel`、`ProfileManagerModel` | ui-shell | 是 | 有 |
| `OverlayPanelModel`、`OnboardingSpotlightModel` | ui-shell | 是 | **無**（後者註解說明是因為被當預設參數建立） |
| `StyleTabModel`、`FormatTabModel`、`PositionTabModel`、`RulesTabModel`、`FontLibraryModel`、`DisplaySettingsModel`、`ProfileEditModel` | ui-panel | 是 | 有 |
| `FontLibrary` | core-device | 是 | 有（背景回呼用 `MainActor.assumeIsolated`） |
| `ProfileStore`、`CaptureSettingsStore`、`CapturedPhotoStore`、`AlbumSettingsStore` | core-device | 是 | **無** |
| `RecentColorsStore` | core-style | 是 | **無** |
| `CameraService` | core-device | 是 | **無**；內部用 `sessionQueue`，`publish(...)` 自行跳回 main |

編譯設定：`SWIFT_VERSION: "5.0"`，未設 `SWIFT_STRICT_CONCURRENCY`；deployment target iOS 18（Observation 需要 iOS 17，可用）。

---

## 2. 拆分方案

原則：

- 新物件都放在 `Views/CameraScreen/`（新資料夾，**擁有者 ui-shell**；Lead 需在[檔案所有權](../TASKS-0.2-ui-redesign.md#檔案所有權)補一行），一律 `@MainActor @Observable final class`。
- 新物件之間不互相持有，透過 `CameraScreenModel` 注入的 closure 溝通（例如 `showToast`），避免循環參照，也方便單元測試。
- `CameraScreenModel` 在過渡期保留同名的轉接屬性／方法（如 `var toastState: ToastState? { presentation.toastState }`），**既有測試與 qa 擁有的 `DaysCamTests/Acceptance/` 不必改**。最後一步（C7）才移除轉接、改寫測試。

### 2.1 `PresentationState`（職責 12、16）

```swift
@MainActor @Observable final class PresentationState {
    private(set) var toastState: ToastState?
    private(set) var captureError: CaptureAlertError?
    private(set) var showsCorruptionRecoveredAlert: Bool
    var isProfileManagerPresented = false
    var isGalleryPresented = false
    private(set) var galleryModel: GalleryModel?
    func showToast(message: String, thumbnail: UIImage? = nil)
    func presentCaptureError(_ error: CaptureAlertError)
    func dismissCaptureError()
    func dismissCorruptionRecoveredAlert()
}
```

- 注入：`scheduleToastDismiss`、`makeGalleryModel`、`capturedPhotoStore`。
- `announce`（VoiceOver）也搬過來。
- 收益：toast 與 alert 的變動只讓讀到它們的 view 重算；`CameraScreen` 建議同時把 toast 抽成小 subview（同為 ui-shell）。

### 2.2 `ThumbnailProvider`（職責 13、18 的收尾）

```swift
@MainActor @Observable final class ThumbnailProvider {
    private(set) var latestThumbnailImage: UIImage?
    private(set) var thumbnailLandingCount: Int
    func loadLaunchThumbnail() async
    func refreshFromLibrary(replacingExisting: Bool) async
    func land(_ thumbnail: UIImage)   // 飛行動畫抵達且已存檔時由 CaptureController 呼叫
}
```

- 注入：`makeThumbnailLibrary`、`capturedPhotoStore`。
- 依賴 TASK-128（縮圖改真實像素大小）先合併。

### 2.3 `FontCoordinator`（職責 17）

```swift
@MainActor @Observable final class FontCoordinator {
    var isWaitingForFont: Bool { get }             // 取代 L739
    func applyFont(_ fontID: OverlayFontID, profileID: UUID)
    func prepareFontsAtLaunch() async
    func sceneDidEnterBackground()
    func selectedProfileDidChange(_ profile: CameraProfile?)
    func fontLibraryDidChange()
}
```

- 狀態：`pendingFontApplications`、`timedOutPreparingFonts`、`preparationTimeoutTasks`、`noticedUnavailableFonts`、`lastSeenProfileID`（逾時從 `objectWillChange.send()` 改成寫入被追蹤的 `timedOutPreparingFonts`，自然觸發重算）。
- 注入：`fontLibrary`、`profileStore`、`showToast`、`postToFontList`（取代直接讀 `styleTabModel?.fontLibraryModel`）、`syncStyleTab`。
- 依賴 TASK-122（#458，改的正是 pending 字型套用）與 TASK-132（`FontLibrary` 啟動驗證）先合併。

### 2.4 `OverlayEditingCoordinator`（職責 3）

```swift
@MainActor @Observable final class OverlayEditingCoordinator {
    let panelModel: OverlayPanelModel
    private(set) var styleTabModel: StyleTabModel?
    private(set) var formatTabModel: FormatTabModel?
    private(set) var positionTabModel: PositionTabModel?
    func selectedProfileDidChange(_ profile: CameraProfile?)  // 取代 refreshOverlayPanelTabModelsIfNeeded
    func profilesDidChange(_ profiles: [CameraProfile])        // 取代 L425–437 的 applyExternalChanges
    func makeRulesModel(for profile: CameraProfile) -> RulesTabModel
}
```

- `positionDragAdapter`、writer 都收在這裡。
- 建議在 §4 的 keyed update（R1–R3）完成後才拆，這樣它一出生就不需要 `TabProfileWriter`。

### 2.5 `CaptureController`（職責 14、15、18）

```swift
@MainActor @Observable final class CaptureController {
    private(set) var isCapturing: Bool
    private(set) var countdownRemaining: Int?
    private(set) var captureTriggerCount: Int
    private(set) var captureFlights: [CaptureFlight]
    func capturePhoto(profile: CameraProfile)
    func captureContext(for profile: CameraProfile) -> CaptureContext
    func flightDidLand(id: UUID)
    func removeCaptureFlight(id: UUID)
}
```

- 注入：`calculator`、`renderer`、`calendar`、`resolveFont`、`captureSettingsStore`、`captureImage`、`crop`、`bake`、`save`、`countdownTicker`、`capturedPhotoStore`，以及 `presentation`／`thumbnails` 的回呼。
- **拍攝時間仍在 `captureContext(for:)` 一次取得並顯式傳入**（AGENTS Code Review Rules），不可改讀 EXIF 或檔案時間；拆分不得改變 `calculator.now()` 的呼叫時機。
- risk:high（相機並行、失敗不可報成功）；依賴 TASK-128、TASK-129（#469 會把 `isCapturing` 拆成兩個狀態並加 serial 管線）、TASK-130 先合併。

### 2.6 拆完後的 `CameraScreenModel`

保留：組裝依賴、設定檔鏡像、相機／變焦／對焦／導覽接線、工具列轉接、面板點擊路由、疊字預覽推導、`refreshTick`、`isShutterDisabled`（組合 `capture`、`fonts`、相機狀態）。預估 500–600 行。

---

## 3. 改用 `@Observable` 的順序

### 3.1 通用注意事項

- `@Observable` 沒有 `objectWillChange` 與 `$property`。凡是 `.sink` 在某物件的 `$xxx` 或 `objectWillChange` 上的程式，要在**同一個 PR** 改成明確回呼或 `withObservationTracking`。
- `lazy var` 與其他 property wrapper 不能放在 `@Observable` 內被追蹤：`CameraScreenModel.profileManagerModel`、`StyleTabModel`、`ProfileManagerModel` 各有一個 `lazy var`，要改成 `@ObservationIgnored` 或在 init 建好。
- View 端：`@ObservedObject` → 一般 `let`／`var`（需要 binding 時 `@Bindable`）；`@StateObject` → `@State`。`@State` 的初始值在每次 view init 都會被求值（只保留第一次），`ProfileEditorView` 的 `RulesTabModel` 需確認 init 沒有副作用。
- 父物件仍是 ObservableObject 時，view body 讀到的子 `@Observable` 屬性**仍會被追蹤**，所以可以由葉往上逐一轉換，不必一次全換。
- 測試裡 `model.objectWillChange.sink`（`CameraScreenModelTests.swift:354、655、1237`，`FontLibraryModelTests.swift:398`）要改成共用的 `withObservationTracking` 輔助函式；建議 O1 先在 `DaysCamTests/Unit/` 加一個 `ObservationProbe` 測試工具（ui-shell 擁有）。

### 3.2 步驟

| 步驟 | 內容 | 擁有者 | 可單獨合併 | 需同步調整的測試 | 風險 |
|---|---|---|---|---|---|
| O1 | `OverlayPanelModel`、`ZoomPresetExpansion`、`OnboardingSpotlightModel` 轉 `@Observable`（同時補 `@MainActor`）；移除 `bindToPanelModel`、`bindToOnboarding` 的轉發；加 `ObservationProbe` | ui-shell | 是 | `OnboardingSpotlightModelTests`、`ZoomPresetBarTests`、`CameraScreenModelTests` 中 panel／onboarding 的重算測試 | 低 |
| O2 | `ViewfinderZoomModel`、`ViewfinderFocusModel` 轉換；`zoomModel.$isPinching` 改回呼 | ui-shell | 是 | `ViewfinderZoomModelTests`、`ViewfinderFocusModelTests` | 低 |
| O3 | ui-panel tab model（`StyleTabModel`、`FormatTabModel`、`DisplaySettingsModel`、`PositionTabModel`、`RulesTabModel`、`ProfileEditModel`）；`FormatTabModel` 對 `displaySettings` 的轉發移除 | ui-panel（`ProfileEditorView` 的 `@StateObject` 屬 ui-shell，同 PR 需 Lead 協調或拆成先後兩個 PR） | 是（`StyleTabModel` 對 `fontLibrary`／`recentColorsStore` 的轉發保留到 O5） | 各 `*TabModelTests` | 中 |
| O4 | `CaptureSettingsStore`、`RecentColorsStore`、`AlbumSettingsStore`、`CapturedPhotoStore` 轉換（前置 S1 的 `@MainActor`）；移除 `bindToCaptureSettingsStore` | core-device、core-style 各一個 PR；`CameraScreenModel`／`StyleTabModel` 的轉發移除由 ui-shell／ui-panel 跟進 | 是，但每個 store 的轉換與其訂閱者要同 PR 或訂閱者先改成不依賴 `objectWillChange` | 各 store 測試 | 中 |
| O5 | `FontLibrary` 與 `FontListControlling` 協定拿掉 `objectWillChange` 要求，改 `@Observable`；`FontLibraryModel`、`StyleTabModel`、`CameraScreenModel` 的訂閱改回呼 | core-device＋ui-panel＋ui-shell（**跨三個擁有者**，Lead 協調）；qa 擁有的 `FontWeightPanelAcceptanceTests.swift:12` 假字型庫也要改 | 否，需一次合併或先加相容層 | `FontLibraryTests`、`FontLibraryModelTests`、`CameraScreenModelFontTests`、qa 驗收測試 | 中 |
| O6 | `ProfileStore` 轉換；`$profiles`／`$selectedProfileID` 的訂閱（`CameraScreenModel` L418、`ProfileManagerModel`）改回呼或 `withObservationTracking` | core-device＋ui-shell | 否，同上 | `ProfileStoreTests`、`ProfileManagerModelTests`、`CameraScreenModelTests` | 中 |
| O7 | `CameraService`：保留 ObservableObject，另加 `@MainActor @Observable` 的 `CameraState`（`permission`、`status`、`facing`、`zoom`），`publish(...)` 改寫入它 | core-device | 是 | `CameraServiceTests` | 高（相機並行） |
| O8 | `CameraScreenModel` 本身轉 `@Observable`；三個 view 改 `let model`；`DaysCamApp` 改 `@State` | ui-shell | 是（需 C1–C6 與 O1–O7 完成） | `CameraScreenModelTests` 的重算測試 | 中 |

O1、O2 可在拆分（§2）之前做；O8 應在拆分完成後做，才能吃到「只重算讀到的 view」的收益。

---

## 4. 取代 `TabProfileWriter`：keyed／partial update

### 4.1 設計

```swift
// ProfileStore（core-device）
/// Applies `change` to the stored profile `id` and persists it.
func update(id: UUID, _ change: (inout CameraProfile) -> Void) throws -> CameraProfile
```

- tab model 的 `updateProfile` 型別由 `(CameraProfile) throws -> Void` 改為 `((inout CameraProfile) -> Void) throws -> Void`，每次只送出「這次改了哪幾個欄位」：`updateProfile { $0.style.fontID = id }`。
- store 讀取自己最新那份、套用、驗證、寫入，不再需要 baseline 比對與 `adopt`。
- tab model 自己的顯示副本仍由現有 `applyExternalChanges(from:)` 跟上 store。

### 4.2 步驟

| 步驟 | 內容 | 擁有者 | 可單獨合併 | 風險 | 依賴 |
|---|---|---|---|---|---|
| R0 | 守門測試：用 `Mirror` 列出 `CameraProfile` 所有儲存屬性，斷言 `TabProfileWriter` 對除 `id`／`createdAt`／`updatedAt` 外的每個欄位都會合併（逐一改一個欄位，確認寫回 store）。新增欄位忘了加清單就會失敗 | ui-shell（新檔 `DaysCamTests/Unit/TabProfileWriterTests.swift`） | 是，隨時可做 | 低 | 無 |
| R1 | `ProfileStore.update(id:_:)` | core-device | 是 | 低 | TASK-124（debounce 寫檔）、TASK-134 |
| R2 | ui-panel 四個 tab model 改送 partial change | ui-panel | 是（`TabProfileWriter` 加一個 `write(change:)` 過渡入口） | 中（#70 的回歸） | R1 |
| R3 | 刪除 `TabProfileWriter` 與 R0 測試，相關 #70 測試改測 R1 行為 | ui-shell | 是 | 低 | R2 |

---

## 5. Strict concurrency

### 5.1 135.2 試編譯（**待驗**）

本卡依 Lead 指示未執行 xcodebuild。請 Lead 指派到 rinclaw（不需開模擬器，只編譯）：

```bash
xcodegen generate   # .xcodeproj 不在版控
xcodebuild build -project DaysCam.xcodeproj -scheme DaysCam \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/dd-task135 \
  SWIFT_STRICT_CONCURRENCY=targeted 2>&1 \
  | grep -E 'warning: .*(Sendable|actor|isolat|concurren)' | sort -u > targeted.txt
wc -l targeted.txt
sed -E 's#^.*/DaysCam/##; s#:[0-9]+:[0-9]+: warning: # | #' targeted.txt \
  | awk -F' \\| ' '{print $1}' | sort | uniq -c | sort -rn   # 依檔案分類
```

`complete` 也跑一次以估算後續工作量。結果補回本節，不提交 `project.yml`。

靜態閱讀預期會出現的類別：

| 類別 | 主要位置 | 對應步驟 |
|---|---|---|
| 非 Sendable closure 跨進 `DispatchQueue.global` | `CameraScreenModel.processCapturedImage`（`crop`／`bake`／`save` 被背景 closure 捕獲） | C6（隨 TASK-129 的 serial 管線一起整理） |
| 預設參數在非隔離環境建立 main actor 物件 | `CameraScreenModel.init` 的 `OnboardingSpotlightModel()` 等預設值（S1 後 `CaptureSettingsStore()` 等也會） | S1；必要時改由 `DaysCamApp` 明確傳入 |
| `sessionQueue` closure 捕獲非 Sendable 的 `self` | `CameraService` 多處 | O7／S3 |
| Combine `.sink` closure 呼叫 main actor 方法 | `CameraScreenModel` 的各 `bindTo...`、`StyleTabModel`、`FontLibraryModel` | 隨 O 系列改成回呼後消失 |
| `@unchecked Sendable` 與 `assumeIsolated` | `FontLibrary`、`MatchSession`、`GalleryLibrary.ImageRequestHandle` | 只需確認，不一定要改 |

### 5.2 需要補 `@MainActor` 的型別（S1）

`ProfileStore`、`CaptureSettingsStore`、`CapturedPhotoStore`、`AlbumSettingsStore`（core-device）；`RecentColorsStore`（core-style）；`OverlayPanelModel`、`OnboardingSpotlightModel`（ui-shell，併入 O1）；`PhotoSaver`（core-device，目前只從 main 呼叫，`AlbumSaveSettings` 也是）。`CameraService` **不**直接標 `@MainActor`（session 工作必須留在 `sessionQueue`），走 O7 的拆法。

### 5.3 步驟

| 步驟 | 內容 | 擁有者 | 可單獨合併 | 風險 |
|---|---|---|---|---|
| S0 | §5.1 試編譯，補數字（本卡 135.2） | Lead 指派 | — | — |
| S1 | 補 §5.2 的 `@MainActor`，修因此出現的呼叫端錯誤 | 各擁有者各一 PR（store 先、呼叫端後） | 是 | 中：`ProfileStore` 在 TASK-124 後有背景寫檔，標註要對準 main 與背景的分界 |
| S2 | `project.yml` 設 `SWIFT_STRICT_CONCURRENCY: targeted`（App 與測試 target），把剩餘警告清到 0 | Lead 改設定；修正分派給各擁有者 | 是 | 低 |
| S3 | 改 `complete`，逐檔清警告；`CameraService` 依 O7 定出隔離邊界 | Lead＋core-device 主修 | 每個擁有者的修正可單獨合併，設定變更最後一個 PR | 高（相機並行） |
| S4（選做） | Swift 6 language mode；另評估 Xcode 26 的 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`（App target 預設 main actor，可大量省掉手動標註） | Lead | 是 | 中 |

注意：rinclaw 的 Xcode 上限是 26.3，任何新設定都要在 26.3 驗證過。

---

## 6. 是否抽出本地 SPM `DaysCamCore`

候選內容：`Models/`（全部只 import Foundation／CoreGraphics）、`DayCountCalculator`、`TemplateRenderer`、`CaptureSettingsStore`、`ProfileStore`（TASK-124 後會訂閱 `UIApplication` 通知，需另抽介面）、`RecentColorsStore`、`ZoomPlan`。

| | 內容 |
|---|---|
| 利 | 純邏輯測試可在 macOS 主機 `swift test` 跑，不佔 rinclaw 模擬器名額；增量編譯較快；模組邊界強制分層（UI 不能偷用 internal）；strict concurrency 可在套件先開 `complete` |
| 弊 | 對外型別都要 `public` 並依 AGENTS 補英文文件註解，改動面大；`project.yml` 要加 local package；測試 target 拆分；檔案所有權表路徑全改；與進行中的 core-style／core-device 卡衝突機率高；`OverlayRenderer`、`OverlayMetrics`、`FontLibrary` 依賴 UIKit／CoreText，拆不進去，邊界不如預期乾淨 |

**建議：現在不做。** S3（`complete`）完成後再評估；若做，先只放 `Models/`＋`DayCountCalculator`＋`TemplateRenderer`（日期／天數計算的核心，也是最需要大量測試的部分）。

---

## 7. 與進行中卡片的排序

| 進行中卡 | 碰到的檔案 | 與本計畫的關係 |
|---|---|---|
| TASK-122（#458） | `CameraScreenModel` 字型 pending | C3（`FontCoordinator`）前必須合併 |
| TASK-124（#464）、TASK-134（#474） | `ProfileStore` | R1、S1、O6 前必須合併 |
| TASK-125（#465）、130（#470）、131（#471） | `CameraService` | O7、S3 前必須合併 |
| TASK-128（#468）、TASK-129（#469） | `CameraScreenModel` 拍攝管線 | C2、C6 前必須合併；129 是 risk:high |
| TASK-132（#472）、133（#473） | `FontLibrary`、`FontCatalog`；133 的 `invalidateFontCache()` 接線可能落在 `CameraScreenModel` | O5、C3 前必須合併 |
| TASK-115（PR #456）、123（#462） | ui-panel 字型清單 | O3、O5 前合併 |

可以**現在就做**、不與上述衝突的：R0、S0。其餘全部排在 TASK-122～134 合併之後。

---

## 8. 任務卡草稿

> 編號以 `REF-` 暫代，Lead 開卡時換成正式 TASK 編號。依 135.3，人類 review 後才開。

| 草稿 | 標題 | 擁有者 | risk | 依賴 | 可單獨合併 |
|---|---|---|---|---|---|
| REF-R0 | `TabProfileWriter` 欄位覆蓋守門測試 | ui-shell | 一般 | 無 | 是 |
| REF-S0 | strict concurrency `targeted`／`complete` 試編譯並補本文件數字 | Lead 指派 | 一般 | 無 | 是（只改 docs） |
| REF-O1 | 面板殼層、焦段展開、首次導覽改 `@Observable`＋`ObservationProbe` | ui-shell | 一般 | TASK-122 | 是 |
| REF-O2 | 變焦、對焦 model 改 `@Observable` | ui-shell | 一般 | REF-O1 | 是 |
| REF-S1a | core-device store 補 `@MainActor` | core-device | 一般 | TASK-124、134 | 是 |
| REF-S1b | `RecentColorsStore` 補 `@MainActor` | core-style | 一般 | 無 | 是 |
| REF-R1 | `ProfileStore.update(id:_:)` | core-device | 一般 | TASK-124、134 | 是 |
| REF-R2 | tab model 改送 partial change | ui-panel | 一般 | REF-R1 | 是 |
| REF-R3 | 移除 `TabProfileWriter` | ui-shell | 一般 | REF-R2 | 是 |
| REF-C1 | 抽出 `PresentationState` | ui-shell | 一般 | REF-O1、TASK-129 | 是 |
| REF-C2 | 抽出 `ThumbnailProvider` | ui-shell | 一般 | REF-C1、TASK-128 | 是 |
| REF-C3 | 抽出 `FontCoordinator` | ui-shell | 一般 | REF-C1、TASK-122、132、133 | 是 |
| REF-C4 | 抽出 `OverlayEditingCoordinator` | ui-shell | 一般 | REF-R3 | 是 |
| REF-O3 | ui-panel tab model 改 `@Observable` | ui-panel（`ProfileEditorView` ui-shell 跟進） | 一般 | REF-C4 | 是（分兩個 PR） |
| REF-O4 | 各 store 改 `@Observable` | core-device／core-style＋訂閱者 | 一般 | REF-S1a、S1b | 每個 store 一個 PR |
| REF-O5 | `FontLibrary` 與字型協定改 `@Observable` | core-device＋ui-panel＋ui-shell＋qa | 一般 | REF-C3、REF-O3 | 否（Lead 協調一次合併） |
| REF-O6 | `ProfileStore` 改 `@Observable` | core-device＋ui-shell | 一般 | REF-R3、REF-C4 | 否 |
| REF-C6 | 抽出 `CaptureController` | ui-shell | **high** | REF-C1、C2、TASK-128、129、130 | 是 |
| REF-O7 | `CameraService` 加 `CameraState` | core-device | **high** | TASK-125、130、131 | 是 |
| REF-O8 | `CameraScreenModel` 改 `@Observable`、移除轉接屬性、改寫測試 | ui-shell（qa 驗收測試若用到轉接屬性需 qa 跟進） | 一般 | 以上全部 | 是 |
| REF-S2 | 開啟 `targeted` | Lead | 一般 | REF-S1a、S1b、O1 | 是 |
| REF-S3 | 開啟 `complete` | Lead＋各擁有者 | **high** | REF-S2、O7、C6 | 修正可分 PR，設定最後 |
| REF-P1 | 評估 `DaysCamCore` | Lead | 一般 | REF-S3 | 調查卡 |

建議的主線：`R0 → S0 →（等 TASK-122～134）→ O1 → O2 → S1 → R1 → R2 → R3 → C1 → C2 → C3 → C4 → O3 → O4 → O5 → O6 → C6 → O7 → O8 → S2 → S3`。`S2` 可在 S1 後提早開，以免後續新程式再增加警告。

---

## 9. 這裡是我的假設

- `CameraScreen.swift` 等 view 的拆小（toast、倒數抽 subview）視為各步驟的一部分，不另開卡。
- 新資料夾 `Views/CameraScreen/` 歸 ui-shell，需 Lead 更新所有權表。
- 過渡期的轉接屬性是讓 qa 驗收測試不必改的前提；若 Lead 允許 qa 同步改驗收測試，可省掉轉接，步驟數不變但每個 PR 會變大。
- 「拆出後預估 500–600 行」是依 §1.1 歸屬粗估，未實際計算。
- §5.1 預期分類是靜態閱讀推測，以實際試編譯結果為準。
