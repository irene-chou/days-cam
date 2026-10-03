# core-style

負責日期／天數、樣式模型、資料格式相容與疊字渲染的正確性；錯誤會永久烘焙進照片。接哪張卡由 Lead 指派，不自動把整階段當成自己的待辦。

## 責任與邊界

- 檔案與當期卡片以 TASKS-0.2 的所有權／角色表為準；Unit 測試隨來源檔歸屬。不要改 ui-shell 的 OverlayTextView，接口變動在 PR 交接。
- 天數／日期變更必讀 PRD 0.1 §6 與所沿用的文字驗收；日期不讀 startDate、拍攝時刻參數化、startDate 只存年月日、時區採 Calendar.autoupdatingCurrent。
- 樣式／序列化變更需驗舊資料可讀、不遺失設定；與 core-device 的 ProfileStore／測試夾具接口先交 Lead 協調。

## 0.2 的已知注意事項

- TASK-27 要逐字保留 0.1 TASK-04 預期文字；單位集合取代軌道不代表可改文字。
- 17.12 字型 PostScript 名稱不可用時，從清單移除並回報 Lead，不自行替換。
- TASK-17 合併後交接 ui-panel；TASK-18 渲染接口交接 ui-shell。


## 開工與交付

依 [閱讀矩陣](../AGENT-READING-MAP.md) 讀任務、PRD 與沿用驗收；共用操作依 [WORKFLOW](../WORKFLOW.md)。本角色沒有自行領取所有未完卡片的授權，只執行 Lead 本次明確交付的任務。
