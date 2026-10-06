# Claude + Codex 工作流程

此文件承接 [AGENTS.md](../AGENTS.md)。按工作階段讀對應節；目前在**開發分工與 review gate 的試行期**，見文末 Pilot。

## 分工與交接

原則：一張卡盡量在同一個 session 做完；review 改由全新 session 執行（可與作者同模型），因為獨立視角在這一步最有價值。完整測試只在升版 PR 由 CI（`swift.yml`）執行，平常 PR 只跑相關測試 class。

| 工作 | 預設執行者／模型 | 交付 |
|---|---|---|
| 需求、設計稿、任務卡、Lead | Claude 主 session／Opus（不另開 `lead-spec` subagent） | PRD／Issue／任務卡、驗收、依賴、所有權；開卡時查程式碼，把相關檔案與 symbol 寫進卡片 |
| 邏輯開發（日期、渲染、相機、持久化） | Codex `core-style`、`core-device`／GPT-6 Astra low | 實作、XCTest、自驗 A 級、PR |
| UI 開發（面板、畫面骨架、對照設計稿調整） | Claude `ui-panel`、`ui-shell`／Sonnet | 實作、XCTest、自驗 A 級、B′ Preview 截圖、PR |
| Review（兼核對驗收） | 全新 session 的 agent，不分作者：Claude Action 自動 review 所有 PR；高風險另加 Codex connector | 必修／建議；逐條確認每個 A 級驗收都有測試或證據 |
| 獨立 QA | 僅 `risk: high`，由沒寫這張卡的那家執行 `qa` | 指定 SHA 的獨立驗收與證據 |
| 高風險 review／爭議 | Claude `risk-reviewer`／Opus | 問題、影響、建議、未驗證處 |

模型是可調整的起點；Codex ID 已對照本機 2026-10-03 模型清單。不可用時在 app 選擇可用模型並調整角色 TOML，不改走 API key。只有依賴已滿足且擁有檔案不重疊時，才同時開兩位 developer；同一時間只有一個 agent 操作 Xcode 視窗。

高風險包含相機／AVFoundation／並行、持久化與資料遷移、可能遺失照片或設定、跨模組介面，以及三輪 review 未收斂。Lead 在任務／PR 標 `risk: high` 並寫原因，加開獨立 QA；必要時再派 `risk-reviewer`。一般任務標 `risk: normal`。

**交接流程**：Claude 寫卡 → 開發者（依卡片類型為 Claude 或 Codex）領取、實作、自驗、開 PR → 全新 session review → 開發者在**同一個 session** 修正 → Lead 核對 gate、收斂人工事項並合併。開發者在 PR 寫明自己的 SHA、驗證結果與驗收對照，PR 本身就是交接紀錄。Lead 直接用 Codex CLI 派卡，不再請使用者轉交；訊息格式如下：

```text
任務：TASK-XX／Issue URL（目標、驗收、依賴、相關檔案見卡片）
角色：core-style／core-device／ui-shell／ui-panel／qa
風險：normal／high＋原因；假設與容易誤判的事項
交付：PR URL、head SHA、驗證命令／結果、待人類確認
```

```bash
codex exec -C <Codex worktree> -s workspace-write \
  -c sandbox_workspace_write.network_access=true "<上方派卡訊息>"
```

- 先替 Codex 建好自己的 worktree（見[開發](#開發)），`-C` 指向它；需要 push／開 PR，所以開網路權限。
- 長任務用背景執行，完成後讀最後輸出核對 PR URL 與 SHA；記下 session id，review 修正用 `codex exec resume <session id> "<修正指示>"` 沿用同一個 session。
- 互動式的 `/codex:rescue` 等外掛指令也可用，但派卡與修正以 CLI 為準，方便留紀錄。

共享 Markdown 任務由 Lead 記錄領取狀態，其他角色在 PR／Issue 回報；遇到跨角色接口，請擁有者修改並同步 Lead。不貼整段聊天，不安裝自動撿單服務。

## 額度不足

兩家都可能用完額度。角色是責任邊界，不綁定廠商；兩邊都保留全部角色入口（`.claude/agents/`、`.codex/agents/`），讓另一家能接手。

1. **依複雜度選模型，快到上限時只開簡單卡**：平時照上表依卡片複雜度選模型，不全面降級。剩餘額度不多（尚未用完）時，只開小模型能做完的簡單卡；高風險卡等重置後再做。額度已用完時，同家降級通常無效（同家模型大多共用額度，除非某模型另有獨立上限），直接換家或等重置。
2. **開工前先估量**：剩餘額度明顯不夠完成一張卡時，先不要開工；做到一半中斷，接手方要整份重讀，最浪費。
3. **中斷時留檢查點**：被迫中斷時，先 push WIP commit，開或更新 draft PR，寫明已完成／未完成的驗收編號與下一步，另一家可以直接接續。
4. **換家開發**：同一張卡改由另一家的對應角色接手，在 PR 註明「額度接手」。review 照常由全新 session 執行，哪一家都可以。
5. **review 的替代路徑**：
   - 一般卡：只需一個 approve。Claude 額度用完時 Action 會失敗或沒有結果，改用 `@codex review`；Codex 額度用完時用 Action 或 Claude `risk-reviewer` 全新 session。不需 `quota-fallback`。
   - 高風險卡：需兩家 approve，優先等額度重置。等不了時加 `quota-fallback` label，依 AGENTS 的額度不足例外合併：有額度那家的 approve，且人類在 PR 確認，由 Lead 記錄；qa gate 照舊。
6. **錯開重置時間**：大型開發排在剛重置之後；額度低的時段做不吃 token 的事，例如寫卡、人工驗收、整理截圖。
7. **記錄**：每次觸發替代路徑，在 PR 記錄哪一家、何時用完、改走哪條路徑，作為之後調整分工比例的依據。

## 開發

1. 依 [閱讀矩陣](AGENT-READING-MAP.md) 取得任務與回歸條目，檢查依賴已合併。
2. 各自 worktree，分支 `feature/task-XX-<簡述>`；修正／文件用對應前綴。一張卡一個 PR，必要時分 core／UI 半邊。高風險 QA 新增驗收測試用 `chore/qa-task-XX`。
3. 單元測試放 `DaysCamTests/Unit/<來源檔名>Tests.swift`，歸來源檔擁有者。QA 只能寫 `DaysCamTests/Acceptance/` 的版本化程式；測試輸出與專用截圖 worktree 可寫。
4. 每角色獨立模擬器，先用 `xcrun simctl list devices available` 查找 `iPhone 16 <角色>` 及 UUID，**查無才** `xcrun simctl clone "iPhone 16" "iPhone 16 <角色>"`；clone 不會檢查重名。找不到基底裝置時先查可用 runtime／裝置，不能盲目建多台。
5. 送出／修正前，在自己的模擬器跑改動相關的測試 class；完整測試**只在升版 PR**（分支 `chore/bump-<版本>`）由 CI（`swift.yml`）執行，其他 PR 不跑 CI、也不在本機跑全套（2026-10-05 人類決定，節省 macOS runner 分鐘數）；需要時 Lead 可在 Actions 手動觸發。升版 PR 的 CI 失敗，由 Lead 依失敗測試的所有權派修。獨立 DerivedData 防止平行執行互踩。純文件／角色設定 PR 做引用、設定與規則檢查，無須 iOS 產品測試，但仍須滿足 qa gate。

```sh
xcodegen generate
xcodebuild -project DaysCam.xcodeproj -scheme DaysCam \
  -destination 'platform=iOS Simulator,id=<角色模擬器 UUID>' \
  -derivedDataPath /tmp/dayscam-dd-<worktree識別>-<角色> \
  -only-testing:DaysCamTests/<相關測試class> test
```

PR 使用 [模板](../.github/PULL_REQUEST_TEMPLATE.md) 附驗收編號、具體指令、結果與假設；不要只寫「已測試」。開發者自驗 A 級，在 PR 列出「驗收編號 → 測試名稱或證據」對照表，供 reviewer 核對。

## Review

`.github/workflows/claude-code-review.yml` 在 opened／synchronize／ready_for_review／reopened 觸發，review 所有 PR，不分作者（每次都是全新執行）。新 push 撤銷舊 Claude approve；修改 review workflow 前已存在的分支需先 merge 最新 main，避免 Action 因 workflow 版本不同而跳過。

```sh
gh pr view <N> --json headRefOid,reviewDecision
gh pr view <N> --comments
gh api --paginate repos/irene-chou/days-cam/pulls/<N>/comments
gh api --paginate repos/irene-chou/days-cam/pulls/<N>/reviews
```

- Developer：在原本的開發 session 處理，不開新 session 重讀。必修逐條處理，同意則修正、相關測試通過後 push，回覆「已修正：<commit>」；不同意要說明並交 Lead／人類裁決。建議可自行取捨並簡短回覆理由。
- Codex connector：高風險卡必觸發；一般卡在 Action 沒結果或需要第二意見時觸發。開 PR 後與每輪修正集中 push 完後，各在最新 commit 留一次 `@codex review`；同 SHA 已在 review 時勿重複觸發。P0／P1 須處理；沒有留言不代表通過，要確認 review 對象是最新 SHA。
- Lead：依既有巡檢安排檢查開啟的 PR，按所有權派修；三輪仍未收斂就停止、加 `needs-human`。截圖待確認、dev 駁回 reviewer 條目也加此 label，人類回覆後記到 PR 並移除。
- 合併前確認同 SHA 的 `qa=success`、待裁決事項已結案，以及 review gate：一般卡至少一個 approve、`risk: high` 卡 Claude 與 Codex 各一個 approve，定義見 AGENTS。Claude approve 看 `APPROVED` review 的 `commit_id` 等於最新 `headRefOid`；Codex approve 看 connector review 針對最新 SHA 且沒有 P0／P1；任何 review 的必修／P0／P1 已修正或已裁決。Lead 在 PR 留言記錄核對結果。PR aggregate decision 不能代替 SHA 比對。
- 看板：可合併候選 `is:pr is:open review:approved status:success`（只靠 Codex approve 的 PR 不會出現，另查 `is:pr is:open status:success`）；等人類 `is:pr is:open label:needs-human`。搜尋只是入口，仍需上述最終檢查。

## QA

驗收層級：A＝QA 可執行（單元／靜態／view model）；B′＝設計對照（SwiftUI Preview）；B＝人類實機。模擬器不能證明實體相機、烘焙目視與權限行為。B 標「待人類驗」後回報，繼續其他可做項目。

**一般風險**：開發者自驗 A 級（相關測試 class），在 PR 列驗收對照表；reviewer 逐條核對對照表，有缺漏即列為必修。UI 卡的 B′ 由開發者（Claude）用 Xcode MCP `RenderPreview` 截圖並與設計稿比較差異。Lead 在相關測試證據齊全、review gate 達成、人工項目確認後，設定 qa status。

**高風險**：另由沒寫這張卡的那家以 `qa` 角色獨立驗收指定 SHA，在 PR 留逐條通過／失敗（附輸出）／待人類驗，補齊開發單元測試未涵蓋的 Acceptance 測試，並設定 qa status。

同時僅一個 agent 操作 Xcode 視窗。工具不可用就交接或標 pending，不能假稱截圖完成。

### qa status

`qa-status.yml` 對 opened／synchronize／reopened 初始化最新 SHA：只含 `docs/`、`.claude/` 或 `*.md` 為 success「純文件，免 qa」，其餘 pending「待 Lead 核對：review gate／人工確認」（不代表有 qa agent 在跑）。**新增 `.codex/*.toml` 不在豁免內**，此類 PR 需完成設定檢查並手動更新 status；本次不擴大自動豁免。

- `success`：A 全過，且 B／B′ 截圖及爭議已由人類完成必要確認，已可合併。
- `pending`：尚有實機、截圖、裁決或未執行的檢查，description 註明阻礙。review gate 達成後，Lead 把 description 改成具體在等什麼，例如「待人類在 PR 確認（Lead 自寫）」「待實機：29.9」；只有高風險卡派獨立 QA 時才寫「獨立 QA 驗收中 @<短 SHA>」。
- `failure`：驗收失敗。新 push 後重驗並設定新 SHA；舊報告不沿用。人類確認最後一項後由 Lead 記到 PR 並更新 status。

設定者：一般風險由 Lead 設定，開發者不可設定自己 PR 的 qa；高風險由獨立 QA 設定。Claude 的 UI 開發要在獨立的 subagent／session 進行，Lead 主 session 只核對與設定 qa；若 Lead 在同一個 session 親自寫了該 PR 的內容，qa 改由人類在 PR 確認後才設定。

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
3. Codex：邏輯卡用 `.codex/agents/core-style.toml`／`core-device.toml`；替 Claude PR 做高風險 QA 用 `qa.toml`。`ui-*` 入口只在額度接手時使用。例如「請以 core-style subagent 處理 TASK-XX，完成後回報 PR 與驗證。」由 Lead 以上方 `codex exec` 派送；若未辨識 custom agent，在訊息中指定相同角色文件與模型（`-m`）。
4. 角色檔是工作規範，不會自行安裝 Xcode MCP、建立 worktree 或派工。
5. GitHub connector：在 [Codex Code Review 設定](https://app.chatgpt.com/settings/code-review) 選 `irene-chou/days-cam`，**關閉 Automatic review**，只用手動 `@codex review`，避免連 Codex 自己開的 PR 也被重複 review。
6. repo 中的角色 TOML 不控制雲端 review；connector 讀適用的 AGENTS.md。這次沒有新增 API action／key，也沒有變更帳戶端開關。

[Codex subagent 官方設定](https://learn.chatgpt.com/docs/agent-configuration/subagents) 說明 project TOML 與模型繼承；[GitHub review 官方設定](https://learn.chatgpt.com/docs/third-party/github) 說明 trigger、`@codex review` 與 Code Review Rules。以實際帳戶可用功能為準。

## Pilot 與切換任務

**目標**：驗證開發分工與不分作者的 review gate。各用一張一般風險卡走完「Claude 開發 → 全新 session review」與「Codex 開發 → 全新 session review」。Lead 挑正常產品任務，不為試行製造無效 PR。

- [ ] 建立 `quota-fallback` label；connector 已改為手動觸發，記錄設定人與日期。
- [ ] 兩個 pilot PR 各記錄：PR URL、review URL、bot 身分／state／commit_id、CI 結果、qa 設定者、修正輪數、兩邊額度前後差。沒量測的欄位寫「未量測」。
- [ ] 至少一次修正 push 後重審，確認舊 review／qa 不會當成最新結果。
- [ ] 確認含 Claude Code 署名的 PR 也會觸發 Claude Action。
- [ ] 跑完約 5 張卡後，依額度紀錄檢討 UI／邏輯的分配比例。

本清單未勾選即表示 pilot 尚未完成。
