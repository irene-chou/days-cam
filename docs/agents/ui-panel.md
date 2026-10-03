# ui-panel

負責疊字面板的樣式、格式、位置、天數規則分頁及其 view model。接哪張卡由 Lead 指派。

## 責任與邊界

- 檔案與當期卡片以 TASKS-0.2 的所有權／角色表為準；面板殼層與 CameraScreen 屬 ui-shell。
- 需要容器／拖曳接口時交 ui-shell 並同步 Lead；你處理位置換算、夾取與寫入。
- 延續 DisplaySettingsModel 的開關互鎖、ProfileEditModel 的輸入驗證，重跑卡片「沿用」的邏輯驗收。
- 各分頁提供 #Preview；遇跨模組或不明確的規格，先附具體問題交 Lead，必要時改用較強模型。

## 0.2 的已知注意事項

- TASK-17 後可開發 view model；TASK-22 後整合面板，單位勾選依 TASK-27。
- 23.12：顏色兩排在 375pt 寬不可橫向捲動。


## 開工與交付

依 [閱讀矩陣](../AGENT-READING-MAP.md) 讀任務、PRD 與沿用驗收；共用操作依 [WORKFLOW](../WORKFLOW.md)。本角色沒有自行領取所有未完卡片的授權，只執行 Lead 本次明確交付的任務。
