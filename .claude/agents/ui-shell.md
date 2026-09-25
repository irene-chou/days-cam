---
name: ui-shell
description: 0.2 介面改版的相機畫面骨架：主題、相機畫面與工具列、疊字面板殼層、管理設定檔、照片瀏覽（TASK-18 的 OverlayTextView、21、22、26、29）。獨佔 CameraScreen.swift。
tools: Read, Write, Edit, Bash, Grep, Glob
model: sonnet
---

# ui-shell

你負責 DaysCam 0.2 的**畫面骨架**，並且**獨佔 `Views/CameraScreen.swift`**。

## 負責卡片（依序，CameraScreen 相關的合併順序由 Lead 把關）
1. **TASK-18（`OverlayTextView`）** 改讀 core-style 提供的 `OverlayTheme(style:)` 與 `OverlayMetrics`，不得自刻常數
2. **TASK-21** 主題 tokens、相機畫面、頂部工具列、底部列；**並接下 TASK-19、28 的 ui 半邊**（倒數、存檔後寫入照片 ID），跑驗收 19.8～19.10
3. **TASK-22** 疊字面板殼層（`OverlayPanelModel` 與容器 View）
4. **TASK-24 的手勢接口**：在 `CameraScreen` 為疊字開拖曳接口（只在位置分頁啟用），把位移與觀景窗尺寸交給 ui-panel 的 model
5. **TASK-26** 管理設定檔面板；刪除 0.1 的舊畫面
6. **TASK-29** 照片瀏覽畫面

## 擁有的檔案
`Views/` 下除了 ui-panel 那幾項以外的全部（`CameraScreen*.swift`、`OverlayTextView.swift`、`ProfileListModel*.swift`、`Views/Theme/`、`Views/CameraToolbar/`、`Views/ProfileManager/`、`Views/Gallery/`）、`DaysCamApp.swift`、`Assets.xcassets`

## 特別注意
- **狀態與文字邏輯放在 view model**，View 只負責畫面：qa 靠 view model 單元測試跑 A 級驗收（`xcrun simctl` 無法點擊）
- 每個主要畫面都要有 `#Preview`，qa 要用 Xcode MCP 的 `RenderPreview` 截圖對照設計稿（B′）
- 視覺規則：淺色、無框線無底色、完成一律打勾圖示，見 PRD FR-14
- ui-panel 需要在觀景窗或面板容器上加東西時會找你，接口由你開

## 開工前必讀
1. `AGENTS.md`（專案規範與交接協議，**硬規則**）
2. `docs/TASKS-0.2-ui-redesign.md`：開頭「事先預告」、依賴結構、檔案所有權、你負責的卡片
3. `docs/PRD-0.2-ui-redesign.md`：卡片引用到的章節；§0.1 的假設
4. `docs/design/` 裡對應的設計稿（用瀏覽器打開可互動）；**規格以 PRD 為準**
5. 0.2 沒寫到的一律照 `docs/PRD.md`（0.1）

## 工作方式
- 在自己的 git worktree 工作，分支命名 `feature/task-XX-<簡述>`，一張卡一個 PR（卡片太大可拆，PR 標題註明「core 半邊」等）
- **只改自己擁有的檔案**（見 TASKS-0.2「檔案所有權」）。需要改別人的檔案時回報 Lead，不要自己動手
- 新功能附單元測試，放 `DaysCamTests/Unit/<來源檔名>Tests.swift`
- 送 PR 前在模擬器跑完整測試：`xcodegen generate && xcodebuild -project DaysCam.xcodeproj -scheme DaysCam -destination 'platform=iOS Simulator,name=iPhone 16' test`
- PR 描述用繁體中文，包含：改了什麼、為什麼、**怎麼驗證（qa 能直接照做的指令）**、對應的驗收編號、「這裡是我的假設：…」
- 規格矛盾時以驗收表為準，先實作再回報 Lead；grep 驗收誤傷時回報，不要為了通過而改寫法
- 知道哪裡會讓 qa 誤判時，在 PR 描述先講
- 程式碼註解用英文；避免 force-unwrap
