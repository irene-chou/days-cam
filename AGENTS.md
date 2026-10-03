# DaysCam — 共用 agent 規範

拍照時將日期／天數烘焙進照片的 iOS App；目前為 0.2 介面改版，並練習 Claude + Codex 協作。以下【硬規則】適用所有角色；技術與風格預設可由任務卡說明調整。

## 開工入口

- 先讀本檔，再依 [閱讀矩陣](docs/AGENT-READING-MAP.md) 讀角色與單張任務；不要預設通讀所有 PRD／TASKS。
- Claude：需求／規格／Lead、高風險 review；Codex：開發、獨立 QA、一般 GitHub review。詳細分工與跨工具交接見 [WORKFLOW](docs/WORKFLOW.md)。
- `CLAUDE.md` 匯入本檔；兩家的角色入口共用 `docs/agents/`，0.2 所有權以 [任務表](docs/TASKS-0.2-ui-redesign.md#檔案所有權) 為準。

## 技術與風格

- Swift／SwiftUI 優先、AVFoundation；UIKit 僅用於 SwiftUI 不足處。實際版本以 `project.yml` 為準（環境見 README）。
- UI、業務邏輯、資料層分開；採 Swift 命名，不用 btn／vc 等縮寫。避免 force-unwrap／force-try，測試有明確理由才例外。
- public 型別／函式需簡短英文文件註解；討論、Issue、PR 用繁體中文。
- 新功能附主要邏輯 XCTest；UI 測試 MVP 不強制，反覆出問題再補。第三方套件僅在自行實作成本過高時採用，先於任務卡註明理由。

## 任務與 Git【硬規則】

- 一張任務卡須有目標、可執行的驗收標準、依賴；每個 PR 做一件事，描述改了什麼、為什麼、怎麼驗證。
- 分支 `feature/`、`fix/`、`chore/`、`docs/`；禁止直接 push main，一律 PR。commit 首行簡短明確。
- 各角色用自己的 worktree、模擬器與 DerivedData；操作見 [開發](docs/WORKFLOW.md#開發)。只改擁有的檔案，跨所有權先交 Lead 協調；QA 不改產品程式碼。
- 決策、規格變更必須寫入 docs 或 Issue。完成交接須有驗證指令／操作、驗收編號、明列「這裡是我的假設」，並主動預告下游可能誤判的地方。
- 需求散文與驗收表矛盾時，以驗收表實作並回報 Lead 修正文案。靜態檢查若迫使無意義改名／改寫，回報收斂驗收，不遷就檢查。
- 上架前版本為 0.x：階段升次版、修正升修訂版；正式上架才 1.0.0。只由 Lead 在階段任務全合併後改 `project.yml` 的 `MARKETING_VERSION`，文件稱呼同步。

## Review 與 QA gate【硬規則】

- **目前為遷移試行期**：每次 PR 開啟／push 仍由 `claude[bot]` review 並撤銷舊 approve。Codex connector 結果尚未取代既有 gate。
- 合併須有 **Claude bot 對最新 commit 的 approve、PR decision `APPROVED`、最新 commit 的 `qa=success`**；被駁回的 bot 條目需 Lead／人類確認。
- `qa=success` 只給 A 級全過且 B 級、B′ 截圖、爭議均已獲必要的人類確認者；有待辦維持 pending，失敗為 failure。新 push 需重新驗證最新 SHA。
- 必修逐條修正或附理由交 Lead；同 PR 三輪未收斂就停止往返。待人類決定時加 `needs-human`，確認後由 Lead 移除並記錄。
- review 回覆、status 指令、`qa-screenshots` 孤兒分支及人工確認方式見 [WORKFLOW](docs/WORKFLOW.md#review)；開始 review／QA／合併前必讀對應段落。

## Code Review Rules

- 以繁體中文提出有具體觸發條件、影響及檔案行號的問題；區分必修與建議，不將個人風格當成阻擋。
- 拍攝時間須顯式傳入計算與烘焙；不可改讀 EXIF／檔案建立時間。日期模式不可讀 startDate；startDate 僅存年月日，時間／時區依 PRD §6。
- 遷移不得遺失設定檔；存檔只請求 addOnly，瀏覽才請求 readWrite。相機並行、權限與儲存失敗不得報成成功。
- 0.2 取代的舊 UI／主題／單位軌道不可誤報回歸；先查 [事先預告](docs/TASKS-0.2-ui-redesign.md#事先預告會讓你誤判的地方)，沿用的文字輸出與邏輯驗收仍須成立。

## 範圍限制【硬規則】

不加入訂閱／IAP／追蹤 SDK 等任務卡未要求的 MVP 外功能；即時拍照不依賴 EXIF 計算天數，不可默默用檔案建立時間代替拍攝時間。
