# 天數相機 App 專案規劃

目標：(1) 做出把日期／天數烘焙進照片的 iOS App；(2) 練習 Claude + Codex 協作與自動化 workflow，**過程 > 完成度**。

## 產品與路線圖

| 階段 | 範圍與依據 |
|---|---|
| 0.1 MVP | 即時拍照、設定檔、日期／天數文字、預設主題與九宮格、儲存；[PRD](docs/PRD.md)、[TASK-01～16](docs/TASKS.md) |
| 0.2 介面改版 | 相機工具、疊字面板、自選內建字型與色彩、任意天數單位、拖曳定位、照片瀏覽；[PRD-0.2](docs/PRD-0.2-ui-redesign.md)、[TASK-17～30](docs/TASKS-0.2-ui-redesign.md) |
| 發佈準備 | 階段驗收後，由 Lead 整理簽名、打包、TestFlight 與發佈流程；是否上架由人類決定 |
| 後續迭代 | 新功能另寫需求與任務卡，再走同一交接流程；不提前預留未核准功能 |

MVP 排除訂閱／IAP、雲端帳號同步、多語系、社群分享與 Widget；0.2 的完整非目標以 PRD-0.2 §2.2 為準。此規劃摘要不覆蓋 PRD 與驗收表。

技術底線：按下快門的系統時間顯式傳入日期／天數計算，疊字烘焙進像素。即時拍照不使用 EXIF；若未來開放匯入，缺少或不合理的 EXIF 應要求使用者輸入拍攝日期，不能默用檔案建立時間。

## Agent 團隊

需求與任務卡由 Claude Lead／Spec 負責；邏輯卡由 Codex 開發、UI 卡由 Claude 開發，review 交給另一家，高風險卡才另開獨立 QA。人類負責實機、視覺確認與發佈決策。

- [AGENTS.md](AGENTS.md)：共用規範、當前 merge gate。
- [WORKFLOW](docs/WORKFLOW.md)：角色／模型、交接格式、開發／QA／review、connector 設定與 pilot。
- [閱讀矩陣](docs/AGENT-READING-MAP.md)：新 agent 的最小必讀範圍。
- [任務表](docs/TASKS-0.2-ui-redesign.md#檔案所有權)：單一檔案擁有者與合併順序。

repo 文件、Issue 與 PR 保存決策；不依賴跨工具聊天記憶。明確任務只開需要的角色，高風險才加第二個模型判斷，避免重複整份 review 消耗額度。試行期間 Claude Action 的舊 gate 仍有效，切換條件見 WORKFLOW。
