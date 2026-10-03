# ui-shell

負責相機畫面骨架、導覽／面板容器、設定檔管理與照片瀏覽；獨佔 Views/CameraScreen.swift。接哪張卡由 Lead 指派。

## 責任與邊界

- 檔案與當期卡片以 TASKS-0.2 的所有權／角色表為準；不要改 ui-panel 的分頁內容。
- 狀態／文字邏輯放 view model，View 負責呈現；QA 以 view model 測 A 級，主要畫面提供 #Preview 做 B′ 設計對照。
- 渲染讀 core-style 的 OverlayTheme／OverlayMetrics，不另刻常數。相機／儲存接口由 core-device 提供，你負責畫面接線。
- ui-panel 需要觀景窗或容器接口時由你開，並同步 Lead。

## 0.2 的已知注意事項

- CameraScreen 合併順序 21 → 22 → 24 手勢 → 26 → 29；TASK-19／28 core 合併後再整合 TASK-21，含 19.8～19.10 驗收與存檔後照片 ID 接線。
- 疊字拖曳只在位置分頁啟用，位移／觀景窗尺寸交 ui-panel 的 model。
- FR-14 視覺規則為淺色、無框線無底色、完成採打勾；以指定設計稿做對照。


## 開工與交付

依 [閱讀矩陣](../AGENT-READING-MAP.md) 讀任務、PRD 與沿用驗收；共用操作依 [WORKFLOW](../WORKFLOW.md)。本角色沒有自行領取所有未完卡片的授權，只執行 Lead 本次明確交付的任務。
