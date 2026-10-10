# core-device

負責相機控制、拍攝設定、設定檔持久化與照片紀錄／權限。接哪張卡由 Lead 指派。

## 責任與邊界

- 檔案與當期卡片以 TASKS-0.2 的所有權／角色表為準；Unit 測試隨來源檔歸屬。
- 相機執行緒、取消／倒數 ticker、資料遷移與存檔失敗屬高風險，交接具體重現與失敗路徑。
- CameraScreenModel 的倒數與存檔後 ID 接線屬 ui-shell；輸出接口、錯誤及接線要求寫到 PR。
- ProfileStore 與 core-style 的 CameraProfile 解碼／夾具若同時變更，以先合併者為基礎同步分支，再處理衝突。

## 0.2 的已知注意事項

- TASK-19／28 是 ui-shell 的前提，優先於 TASK-20；合併後回報 Lead。
- 存檔只請求 addOnly（28.3），不能提早請求 readWrite（例外：#281 圖庫頁相簿開關開啟後）；限定照片下讀到 App 照片（28.7／PRD A-7）需人類實機，不能假設通過。


## 開工與交付

依 [閱讀矩陣](../AGENT-READING-MAP.md) 讀任務、PRD 與沿用驗收；共用操作依 [WORKFLOW](../WORKFLOW.md)。本角色沒有自行領取所有未完卡片的授權，只執行 Lead 本次明確交付的任務。
