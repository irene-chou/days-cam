# Claude + Codex 工作流程

此文件承接 [AGENTS.md](../AGENTS.md)。按工作階段讀對應節；目前在**交叉 review 分工的試行期**，見文末 Pilot。

## 分工與交接

原則：一張卡盡量在同一個 session 做完；只有 review 換另一家，因為獨立視角在這一步最有價值。機械式的測試執行交給 CI（`swift.yml`），不另花 agent token。

| 工作 | 預設執行者／模型 | 交付 |
|---|---|---|
| 需求、設計稿、任務卡、Lead | Claude 主 session／Opus（不另開 `lead-spec` subagent） | PRD／Issue／任務卡、驗收、依賴、所有權；開卡時查程式碼，把相關檔案與 symbol 寫進卡片 |
| 邏輯開發（日期、渲染、相機、持久化） | Codex `core-style`、`core-device`／GPT-6 Astra low | 實作、XCTest、自驗 A 級、PR |
| UI 開發（面板、畫面骨架、對照設計稿調整） | Claude `ui-panel`、`ui-shell`／Sonnet | 實作、XCTest、自驗 A 級、B′ Preview 截圖、PR |
| Review（兼核對驗收） | 另一家：Codex PR → Claude Action；Claude PR（`author:claude`）→ Codex connector | 必修／建議；逐條確認每個 A 級驗收都有測試或證據 |
| 獨立 QA | 僅 `risk: high`，由沒寫這張卡的那家執行 `qa` | 指定 SHA 的獨立驗收與證據 |
| 高風險 review／爭議 | Claude `risk-reviewer`／Opus | 問題、影響、建議、未驗證處 |

模型是可調整的起點；Codex ID 已對照本機 2026-10-03 模型清單。不可用時在 app 選擇可用模型並調整角色 TOML，不改走 API key。只有依賴已滿足且擁有檔案不重疊時，才同時開兩位 developer；同一時間只有一個 agent 操作 Xcode 視窗。

高風險包含相機／AVFoundation／並行、持久化與資料遷移、可能遺失照片或設定、跨模組介面，以及三輪 review 未收斂。Lead 在任務／PR 標 `risk: high` 並寫原因，加開獨立 QA；必要時再派 `risk-reviewer`。一般任務標 `risk: normal`。

**交接流程**：Claude 寫卡 → 開發者（依卡片類型為 Claude 或 Codex）領取、實作、自驗、開 PR → 另一家 review → 開發者在**同一個 session** 修正 → Lead 核對 gate、收斂人工事項並合併。開發者在 PR 寫明自己的 SHA、驗證結果與驗收對照，PR 本身就是交接紀錄。跨家交接只發生在派卡與 review，派給 Codex 的訊息由使用者轉交：

```text
任務：TASK-XX／Issue URL（目標、驗收、依賴、相關檔案見卡片）
角色：core-style／core-device／ui-shell／ui-panel／qa
風險：normal／high＋原因；假設與容易誤判的事項
交付：PR URL、head SHA、驗證命令／結果、待人類確認
```

共享 Markdown 任務由 Lead 記錄領取狀態，其他角色在 PR／Issue 回報；遇到跨角色接口，請擁有者修改並同步 Lead。不貼整段聊天，不安裝自動撿單服務。

## 額度不足

兩家都可能用完額度。角色是責任邊界，不綁定廠商；兩邊都保留全部角色入口（`.claude/agents/`、`.codex/agents/`），讓另一家能接手。

1. **先降級，再換家**：Claude Opus → Sonnet，機械式修改用 Haiku；Codex 先降 reasoning effort 或改用較小模型。仍不夠才換家。
2. **開工前先估量**：剩餘額度明顯不夠完成一張卡時，先不要開工；做到一半中斷，接手方要整份重讀，最浪費。
3. **中斷時留檢查點**：被迫中斷時，先 push WIP commit，開或更新 draft PR，寫明已完成／未完成的驗收編號與下一步，另一家可以直接接續。
4. **換家開發**：同一張卡改由另一家的對應角色接手，在 PR 註明「額度接手」。review 仍要交給「不是這次寫程式的那一家」；兩家都寫過時，交給目前有額度的一家，再由人類補看。
5. **review 的替代路徑**：
   - Claude 額度用完：Codex PR 的 Action review 會失敗或沒有結果，改用 `@codex review`，並由人類在 PR 留言確認 → 加 `quota-fallback` label。
   - Codex 額度用完：Claude PR 改用 Claude `risk-reviewer` 開全新 session review（不沿用開發 session），結果貼 PR → 加 `quota-fallback` label。
   - 有 `quota-fallback` 的 PR 合併前，需人類在 PR 確認接受替代 gate，由 Lead 記錄。
6. **錯開重置時間**：大型開發排在剛重置之後；額度低的時段做不吃 token 的事，例如寫卡、人工驗收、整理截圖。
7. **記錄**：每次觸發替代路徑，在 PR 記錄哪一家、何時用完、改走哪條路徑，作為之後調整分工比例的依據。

## 開發

1. 依 [閱讀矩陣](AGENT-READING-MAP.md) 取得任務與回歸條目，檢查依賴已合併。
2. 各自 worktree，分支 `feature/task-XX-<簡述>`；修正／文件用對應前綴。一張卡一個 PR，必要時分 core／UI 半邊。Claude 開的 PR 加 `author:claude` label。高風險 QA 新增驗收測試用 `chore/qa-task-XX`。
3. 單元測試放 `DaysCamTests/Unit/<來源檔名>Tests.swift`，歸來源檔擁有者。QA 只能寫 `DaysCamTests/Acceptance/` 的版本化程式；測試輸出與專用截圖 worktree 可寫。
4. 每角色獨立模擬器，先用 `xcrun simctl list devices available` 查找 `iPhone 16 <角色>` 及 UUID，**查無才** `xcrun simctl clone "iPhone 16" "iPhone 16 <角色>"`；clone 不會檢查重名。找不到基底裝置時先查可用 runtime／裝置，不能盲目建多台。
5. 送出／修正前，在自己的模擬器跑改動相關的測試 class；完整測試以 PR 上的 CI（`swift.yml`）為準，CI 失敗就修到通過，不重複在本機跑全套。獨立 DerivedData 防止平行執行互踩。純文件／角色設定 PR 做引用、設定與規則檢查，無須 iOS 產品測試，但仍須滿足 qa gate。

```sh
xcodegen generate
xcodebuild -project DaysCam.xcodeproj -scheme DaysCam \
  -destination 'platform=iOS Simulator,id=<角色模擬器 UUID>' \
  -derivedDataPath /tmp/dayscam-dd-<worktree識別>-<角色> \
  -only-testing:DaysCamTests/<相關測試class> test
```

PR 使用 [模板](../.github/PULL_REQUEST_TEMPLATE.md) 附驗收編號、具體指令、結果與假設；不要只寫「已測試」。開發者自驗 A 級，在 PR 列出「驗收編號 → 測試名稱或證據」對照表，供 reviewer 核對。

## Review

`.github/workflows/claude-code-review.yml` 在 opened／synchronize／ready_for_review／reopened 觸發，但會略過有 `author:claude` label 的 PR；label 要在開 PR 時就加上（`gh pr create --label author:claude`）。新 push 撤銷舊 Claude approve；修改 review workflow 前已存在的分支需先 merge 最新 main，避免 Action 因 workflow 版本不同而跳過。

```sh
gh pr view <N> --json headRefOid,reviewDecision
gh pr view <N> --comments
gh api --paginate repos/irene-chou/days-cam/pulls/<N>/comments
gh api --paginate repos/irene-chou/days-cam/pulls/<N>/reviews
```

- Developer：在原本的開發 session 處理，不開新 session 重讀。必修逐條處理，同意則修正、等 CI 通過後 push，回覆「已修正：<commit>」；不同意要說明並交 Lead／人類裁決。建議可自行取捨並簡短回覆理由。
- Codex connector：只 review Claude 開的 PR。開 PR 後與每輪修正集中 push 完後，各在最新 commit 留一次 `@codex review`；同 SHA 已在 review 時勿重複觸發。P0／P1 須處理；沒有留言不代表通過，要確認 review 對象是最新 SHA。
- Lead：依既有巡檢安排檢查開啟的 PR，按所有權派修；三輪仍未收斂就停止、加 `needs-human`。截圖待確認、dev 駁回 reviewer 條目也加此 label，人類回覆後記到 PR 並移除。
- 合併前確認同 SHA 的 `qa=success`、待裁決事項已結案，以及 review gate：Codex PR 的 Claude `APPROVED` review `commit_id` 等於最新 `headRefOid`，且 PR decision 為 `APPROVED`；Claude PR 的 Codex review 針對最新 SHA，且沒有未解 P0／P1，Lead 在 PR 留言記錄核對結果。PR aggregate decision 不能代替 SHA 比對。
- 看板：可合併候選 `is:pr is:open review:approved status:success`（Claude PR 另查 `label:author:claude status:success`）；等人類 `is:pr is:open label:needs-human`。搜尋只是入口，仍需上述最終檢查。

## QA

驗收層級：A＝QA 可執行（單元／靜態／view model）；B′＝設計對照（SwiftUI Preview）；B＝人類實機。模擬器不能證明實體相機、烘焙目視與權限行為。B 標「待人類驗」後回報，繼續其他可做項目。

**一般風險**：開發者自驗 A 級（測試＋CI），在 PR 列驗收對照表；reviewer 逐條核對對照表，有缺漏即列為必修。UI 卡的 B′ 由開發者（Claude）用 Xcode MCP `RenderPreview` 截圖並與設計稿比較差異。Lead 在 CI 通過、review gate 達成、人工項目確認後，設定 qa status。

**高風險**：另由沒寫這張卡的那家以 `qa` 角色獨立驗收指定 SHA，在 PR 留逐條通過／失敗（附輸出）／待人類驗，補齊開發單元測試未涵蓋的 Acceptance 測試，並設定 qa status。

同時僅一個 agent 操作 Xcode 視窗。工具不可用就交接或標 pending，不能假稱截圖完成。

### qa status

`qa-status.yml` 對 opened／synchronize／reopened 初始化最新 SHA：只含 `docs/`、`.claude/` 或 `*.md` 為 success「純文件，免 qa」，其餘 pending。**新增 `.codex/*.toml` 不在豁免內**，此類 PR 需完成設定檢查並手動更新 status；本次不擴大自動豁免。

- `success`：A 全過，且 B／B′ 截圖及爭議已由人類完成必要確認，已可合併。
- `pending`：尚有實機、截圖、裁決或未執行的檢查，description 註明阻礙。
- `failure`：驗收失敗。新 push 後重驗並設定新 SHA；舊報告不沿用。人類確認最後一項後由 Lead 記到 PR 並更新 status。

設定者：一般風險由 Lead 設定，開發者不可設定自己 PR 的 qa；高風險由獨立 QA 設定。

取 SHA 後，整輪驗收固定在該 commit；寫 status 前重新查 head，若不同先停下重驗。不可到最後才把舊測試結果寫給剛取得的新 SHA。

```sh
gh pr view <N> --json headRefOid -q .headRefOid
gh api repos/irene-chou/days-cam/statuses/<實際驗證的SHA> \
  -f state=success -f context=qa -f description='A1–A6 通過；人工項目已確認'
```

description 至多 140 字元，完整結果留 PR。設定 PR 使用實際檢查摘要，不填不存在的 A 驗收。

### 截圖

截圖推專用孤兒分支 `qa-screenshots`，**永遠不合併 main、不 force push**。在獨立 worktree checkout 現有分支；不存在時在空的獨立工作區 `git switch --orphan qa-screenshots`，只加入圖片，不動開發 worktree。

路徑 `pr-<N>/<N>_<驗收編號>_<裝置>_<說明>.png`；push 後於 PR 引用：

```html
<img src="https://github.com/irene-chou/days-cam/blob/qa-screenshots/pr-<N>/<檔名>?raw=true" width="280">
```

標明驗收編號，可表格並排。需要多 PR／設計稿總覽時 Lead 做確認頁；人類在 PR 或對話確認，由 Lead 記到 PR。任務卡寫「截圖推 qa-screenshots 並貼 PR」。

### 驗收指令規則

Markdown 表格內的 shell 指令不可含 `|`；跳脫後 agent 照原文執行會改變 grep 交替或破壞 shell 管線。改用多個 `-e` pattern 或表格外 code block。新增靜態檢查先用確實違規的 fixture 確認會失敗，避免假通過；誤傷語意正確的程式則交 Lead 收斂驗收。

## 啟動與設定

1. 合併本 PR 後，Claude／Codex 的工作 checkout 都同步最新 main；Codex 使用 ChatGPT 帳戶登入，確認帳戶訂閱與 Code Review 可用額度。
2. Claude：Lead 在主 session 進行；UI 卡用 `.claude/agents/ui-panel.md`／`ui-shell.md`；高風險用 `risk-reviewer.md`，以及替 Codex PR 做獨立 QA 的 `qa.md`。`core-*` 入口只在額度接手時使用。
3. Codex：邏輯卡用 `.codex/agents/core-style.toml`／`core-device.toml`；替 Claude PR 做高風險 QA 用 `qa.toml`。`ui-*` 入口只在額度接手時使用。例如「請以 core-style subagent 處理 TASK-XX，完成後回報 PR 與驗證。」若客戶端未辨識 custom agent，可在獨立 session 指定相同角色文件與模型手動執行。
4. 角色檔是工作規範，不會自行安裝 Xcode MCP、建立 worktree 或派工。
5. GitHub connector：在 [Codex Code Review 設定](https://app.chatgpt.com/settings/code-review) 選 `irene-chou/days-cam`，**關閉 Automatic review**，只用手動 `@codex review`，避免連 Codex 自己開的 PR 也被重複 review。
6. repo 中的角色 TOML 不控制雲端 review；connector 讀適用的 AGENTS.md。這次沒有新增 API action／key，也沒有變更帳戶端開關。

[Codex subagent 官方設定](https://learn.chatgpt.com/docs/agent-configuration/subagents) 說明 project TOML 與模型繼承；[GitHub review 官方設定](https://learn.chatgpt.com/docs/third-party/github) 說明 trigger、`@codex review` 與 Code Review Rules。以實際帳戶可用功能為準。

## Pilot 與切換任務

**目標**：驗證交叉 review 分工。各用一張一般風險卡走完「Claude 開發 → Codex review」與「Codex 開發 → Claude review」。Lead 挑正常產品任務，不為試行製造無效 PR。

- [ ] 建立 `author:claude`、`quota-fallback` label；connector 已改為手動觸發，記錄設定人與日期。
- [ ] 兩個 pilot PR 各記錄：PR URL、review URL、bot 身分／state／commit_id、CI 結果、qa 設定者、修正輪數、兩邊額度前後差。沒量測的欄位寫「未量測」。
- [ ] 至少一次修正 push 後重審，確認舊 review／qa 不會當成最新結果。
- [ ] 確認有 `author:claude` 的 PR 不會觸發 Claude Action。
- [ ] 跑完約 5 張卡後，依額度紀錄檢討 UI／邏輯的分配比例。

本清單未勾選即表示 pilot 尚未完成。
