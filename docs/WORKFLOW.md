# Claude + Codex 工作流程

此文件承接 [AGENTS.md](../AGENTS.md)。按工作階段讀對應節。

## 分工與交接

原則：一張卡盡量在同一個 session 做完；review 改由全新 session 執行（可與作者同模型），因為獨立視角在這一步最有價值。完整測試只在升版 PR 由 CI（`swift.yml`）執行，平常 PR 只跑相關測試 class。

| 工作 | 預設執行者／模型 | 交付 |
|---|---|---|
| 需求、設計稿、任務卡、Lead | Claude 主 session／Opus（不另開 `lead-spec` subagent） | PRD／Issue／任務卡、驗收、依賴、所有權；開卡時查程式碼，把相關檔案與 symbol 寫進卡片 |
| 邏輯開發（日期、渲染、相機、持久化） | Claude `core-style`、`core-device` | 實作、XCTest、自驗 A 級、PR |
| UI 開發（面板、畫面骨架、對照設計稿調整） | Claude `ui-panel`、`ui-shell`／Sonnet | 實作、XCTest、自驗 A 級、B′ Preview 截圖、PR |
| Review（兼核對驗收） | 全新 session 的 agent，不分作者：Claude Action 自動 review 所有非 draft PR；高風險另加 Codex connector | 必修／建議；逐條確認每個 A 級驗收都有測試或證據 |
| 獨立 QA | 僅 `risk: high`，由沒參與開發的全新 session 執行 `qa` | 指定 SHA 的獨立驗收與證據 |
| 高風險 review／爭議 | Claude `risk-reviewer`／Opus | 問題、影響、建議、未驗證處 |

模型是可調整的起點。只有依賴已滿足且擁有檔案不重疊時，才同時開兩位 developer；同一時間只有一個 agent 操作 Xcode 視窗。

高風險包含相機／AVFoundation／並行、持久化與資料遷移、可能遺失照片或設定、跨模組介面。Lead 在任務卡寫 `risk: high` 與原因，PR 加 `risk:high` label（`qa-status.yml` 依此決定是否需要 qa），加開獨立 QA；必要時再派 `risk-reviewer`。一般任務標 `risk: normal`。

**交接流程**：Claude 寫卡 → 開發者（Claude subagent，依卡片類型用 core-style／core-device／ui-shell／ui-panel 角色）領取、開 draft PR、實作、自驗、補齊描述後轉 ready → 全新 session review（Claude bot Action＋`@codex review`）→ 開發者在**同一個 session** 修正 → Lead 核對 gate、收斂人工事項並合併。開發者在 PR 寫明自己的 SHA、驗證結果與驗收對照，PR 本身就是交接紀錄。Lead 以 Claude 的 Agent 工具派卡；訊息格式如下：

```text
任務：#N（Issue URL；目標、驗收、依賴、相關檔案見卡片）
角色：core-style／core-device／ui-shell／ui-panel／qa
風險：normal／high＋原因；假設與容易誤判的事項
執行位置：模擬器主機（名額）或本機；模擬器名稱
交付：PR URL、head SHA、驗證命令／結果、待人類確認
```

- **不用 `codex exec` 派任何工作**（開發、修 review、查證、QA 都不行）；Codex 只透過 GitHub connector 做 PR review。`.codex/agents/` 的角色檔保留作為紀錄。
- 長任務用背景 subagent 執行，完成後讀回報核對 PR URL 與 SHA；review 修正送回同一個 subagent（SendMessage）沿用 session。

共享 Markdown 任務由 Lead 記錄領取狀態，其他角色在 PR／Issue 回報；遇到跨角色接口，請擁有者修改並同步 Lead。不貼整段聊天，不安裝自動撿單服務。

## 額度不足

兩家都可能用完額度。開發只由 Claude 執行；Codex 額度只影響 review。

1. **依複雜度選模型，快到上限時只開簡單卡**：平時照上表依卡片複雜度選模型，不全面降級。剩餘額度不多（尚未用完）時，只開小模型能做完的簡單卡；高風險卡等重置後再做。額度已用完時，同家降級通常無效（同家模型大多共用額度，除非某模型另有獨立上限），直接換家或等重置。
2. **開工前先估量**：剩餘額度明顯不夠完成一張卡時，先不要開工；做到一半中斷，接手方要整份重讀，最浪費。
3. **中斷時留檢查點**：被迫中斷時，先 push WIP commit，開或更新 draft PR，寫明已完成／未完成的驗收編號與下一步，額度重置後可直接接續。
4. **review 的替代路徑**：
   - 一般卡：只需一個 approve。Claude 額度用完時 Action 會失敗或沒有結果，改用 `@codex review`；Codex 額度用完時用 Action 或 Claude `risk-reviewer` 全新 session。不需 `quota-fallback`。
   - 高風險卡：需兩家 approve，優先等額度重置。等不了時加 `quota-fallback` label，依 AGENTS 的額度不足例外合併：有額度那家的 approve 即可（不需人類另外同意），由 Lead 記錄；qa gate 照舊。
5. **錯開重置時間**：大型開發排在剛重置之後；額度低的時段做不吃 token 的事，例如寫卡、人工驗收、整理截圖。
6. **記錄**：每次觸發替代路徑，在 PR 記錄哪一家、何時用完、改走哪條路徑。

## 開發

1. 依 [閱讀矩陣](AGENT-READING-MAP.md) 取得任務與回歸條目，檢查依賴已合併。
2. 各自 worktree，分支 `feature/task-XX-<簡述>`；修正／文件用對應前綴。一張卡一個 PR，必要時分 core／UI 半邊。高風險 QA 新增驗收測試用 `chore/qa-task-XX`。
3. 單元測試放 `DaysCamTests/Unit/<來源檔名>Tests.swift`，歸來源檔擁有者。QA 只能寫 `DaysCamTests/Acceptance/` 的版本化程式；測試輸出與專用截圖 worktree 可寫。
4. **各角色獨立模擬器**：每個角色用自己的模擬器（`iPhone 16 <角色>`，SE 截圖用 `iPhone SE <角色>`）與 DerivedData `/tmp/dayscam-dd-<worktree識別>-<角色>`。先用 `xcrun simctl list devices available` 查名稱與 UUID，**查無才**以 `xcrun simctl create` 建立；create 不會檢查重名，不能盲目建多台。每次測試／截圖跑完立即 `xcrun simctl shutdown <自己的 UUID>`，不要讓模擬器開著等下一輪（人類要手動驗收、Lead 指定保留者除外）。執行機器與並行名額由 Lead 指派，不寫在專案文件。
5. **實機測試**：需要人類在實機操作的驗收（B 級，或 B′ 中無法自動化的手勢），由開發者用 `xcodebuild -destination "platform=iOS,id=<裝置 UDID>"` 建置，`xcrun devicectl device install app` 安裝到人類已配對的 iPhone（`xcrun devicectl list devices` 查 UDID），準備好待驗資料後通知人類操作。
6. 送出／修正前，在自己的模擬器跑改動相關的測試 class；完整測試**只在升版 PR**（分支 `chore/bump-<版本>`、build 號 `chore/build-<號>`）由 CI（`swift.yml`，單元測試與 4 個 UI 分片平行）執行，其他 PR 不跑 CI、也不跑全套（節省 macOS runner 分鐘數）；需要時 Lead 可在 Actions 手動觸發。升版 PR 的 CI 失敗，由 Lead 依失敗測試的所有權派修。獨立 DerivedData 防止平行執行互踩。純文件／角色設定 PR 做引用、設定與規則檢查，無須 iOS 產品測試，但仍須滿足 qa gate。

```sh
# worktree 根目錄
xcodegen generate && \
  xcodebuild -project DaysCam.xcodeproj -scheme DaysCam \
    -destination "platform=iOS Simulator,id=<角色模擬器 UUID>" \
    -derivedDataPath /tmp/dayscam-dd-<worktree識別>-<角色> \
    -only-testing:DaysCamTests/<相關測試class> test
```

任務卡以 issue 號碼識別，不再編 `TASK-N`；驗收在卡內編 1、2、3…，在別處引用寫 `#<issue>-<驗收>`（例如 `#537-3`）。舊卡的 `TASK-N`／`155.x` 照舊保留。PR 使用 [模板](../.github/PULL_REQUEST_TEMPLATE.md) 附驗收編號、具體指令、結果與假設；不要只寫「已測試」。開發者自驗 A 級，在 PR 列出「驗收編號 → 測試名稱或證據」對照表，供 reviewer 核對。

## Review

`.github/workflows/claude-code-review.yml` 在 opened／synchronize／ready_for_review／reopened 觸發，review 所有非 draft PR，不分作者（每次都是全新執行）；draft 略過，轉 ready 時觸發第一次 review。新 push 撤銷舊 Claude approve；修改 review workflow 前已存在的分支需先 merge 最新 main，避免 Action 因 workflow 版本不同而跳過。

```sh
gh pr view <N> --json headRefOid,reviewDecision
gh pr view <N> --comments
gh api --paginate repos/irene-chou/days-cam/pulls/<N>/comments
gh api --paginate repos/irene-chou/days-cam/pulls/<N>/reviews
```

- Developer：在原本的開發 session 處理，不開新 session 重讀。必修逐條處理，同意則修正、相關測試通過後 push，回覆「已修正：<commit>」；不同意要說明並交 Lead／人類裁決。建議可自行取捨並簡短回覆理由。
- Codex connector：高風險卡必觸發；一般卡在 Action 沒結果或需要第二意見時觸發。轉 ready 後與每輪修正集中 push 完後，各在最新 commit 留一次 `@codex review`；同 SHA 已在 review 時勿重複觸發。P0／P1 須處理；沒有留言不代表通過，要確認 review 對象是最新 SHA。
- Lead：依既有巡檢安排檢查開啟的 PR，按所有權派修；凡符合 AGENTS 的 `needs-human` 條件就加 label，並在 PR 留言列出要人類看什麼（驗收編號、截圖連結、待裁決條目）。人類回覆後記到 PR 並移除。
- 合併前確認同 SHA 的 `qa=success`、沒有 `needs-human`，以及 review gate：一般卡至少一個 approve、`risk:high` 卡 Claude 與 Codex 各一個 approve，定義見 AGENTS。Claude approve 看 `APPROVED` review 的 `commit_id` 等於最新 `headRefOid`；Codex approve 看 connector review 針對最新 SHA 且沒有 P0／P1；任何 review 的必修／P0／P1 已修正或已裁決。Lead 在 PR 留言記錄核對結果。PR aggregate decision 不能代替 SHA 比對。
- 看板：可合併候選 `is:pr is:open draft:false status:success -label:needs-human`（再逐一核對 review gate）；等人類 `is:pr is:open label:needs-human`。搜尋只是入口，仍需上述最終檢查。

## QA

驗收層級：A＝QA 可執行（單元／靜態／view model）；B′＝設計對照（SwiftUI Preview）；B＝人類實機。模擬器不能證明實體相機、烘焙目視與權限行為。B 與 B′ 截圖確認交人類：加 `needs-human` 後回報，繼續其他可做項目。

**一般風險**：開發者自驗 A 級（相關測試 class），在 PR 列驗收對照表；reviewer 逐條核對對照表，有缺漏即列為必修。UI 卡的 B′ 由開發者（Claude）用 Xcode MCP `RenderPreview` 截圖並與設計稿比較差異，交人類確認（`needs-human`）。不開 qa agent，qa 由 Action 自動設為免 qa。

**高風險**：另由沒寫這張卡的那家以 `qa` 角色獨立驗收指定 SHA，在 PR 留逐條通過／失敗（附輸出）／待人類驗，補齊開發單元測試未涵蓋的 Acceptance 測試，並設定 qa status。待人類驗的項目由 Lead 加 `needs-human`，不影響 qa。

同時僅一個 agent 操作 Xcode 視窗。工具不可用就交接或維持 pending，不能假稱截圖完成。

### qa status

`qa` 只代表獨立 qa agent 是否完成驗收；人類過目與實機一律走 `needs-human`，不放進 qa。`qa-status.yml` 在 opened／synchronize／reopened 與加減 `risk:high` label 時設定最新 SHA：

- 沒有 `risk:high`：success「免 qa（非高風險）」，不卡合併。
- 有 `risk:high`：pending「待 qa agent 驗收」。之後由獨立 qa agent 設定：
  - `success`：A 級全過、B′ 對照完成；待人類驗的項目已列在 PR。
  - `pending`：驗收中或尚未派 qa，description 寫「獨立 QA 驗收中 @<短 SHA>」。
  - `failure`：驗收失敗。新 push 後重驗並設定新 SHA；舊報告不沿用。

設定者：只有獨立 qa agent（或額度接手的 qa 角色）設定 qa；開發者、Lead 都不手動設定。

取 SHA 後，整輪驗收固定在該 commit；寫 status 前重新查 head，若不同先停下重驗。不可到最後才把舊測試結果寫給剛取得的新 SHA。

```sh
gh pr view <N> --json headRefOid -q .headRefOid
gh api repos/irene-chou/days-cam/statuses/<實際驗證的SHA> \
  -f state=success -f context=qa -f description='A1–A6 通過；B′ 對照完成'
```

description 至多 140 字元，完整結果留 PR。設定 PR 使用實際檢查摘要，不填不存在的 A 驗收。

### 截圖

截圖推專用孤兒分支 `qa-screenshots`，**永遠不合併 main、不 force push**。在獨立 worktree checkout 現有分支；不存在時在空的獨立工作區 `git switch --orphan qa-screenshots`，只加入圖片，不動開發 worktree。

路徑 `pr-<N>/<N>_<驗收編號>_<裝置>_<說明>.png`；push 後於 PR 引用：

```html
<img src="https://github.com/irene-chou/days-cam/blob/qa-screenshots/pr-<N>/<檔名>?raw=true" width="280">
```

標明驗收編號，可表格並排。需要多 PR／設計稿總覽時 Lead 做確認頁；人類在 PR 或對話確認，由 Lead 記到 PR 並移除 `needs-human`。任務卡寫「截圖推 qa-screenshots 並貼 PR」。

### 驗收指令規則

Markdown 表格內的 shell 指令不可含 `|`；跳脫後 agent 照原文執行會改變 grep 交替或破壞 shell 管線。改用多個 `-e` pattern 或表格外 code block。新增靜態檢查先用確實違規的 fixture 確認會失敗，避免假通過；誤傷語意正確的程式則交 Lead 收斂驗收。

## 啟動與設定

1. Codex 使用 ChatGPT 帳戶登入，確認帳戶訂閱與 Code Review 可用額度。
2. Claude：Lead 在主 session 進行；UI 卡用 `.claude/agents/ui-panel.md`／`ui-shell.md`，邏輯卡用 `core-style.md`／`core-device.md`；高風險用 `risk-reviewer.md`，獨立 QA 用 `qa.md`。
3. Codex：只做 GitHub PR code review（connector）；`.codex/agents/*.toml` 保留作紀錄，不使用。
4. 角色檔是工作規範，不會自行安裝 Xcode MCP、建立 worktree 或派工。
5. GitHub connector：在 [Codex Code Review 設定](https://app.chatgpt.com/settings/code-review) 選 `irene-chou/days-cam`，**關閉 Automatic review**，只用手動 `@codex review`，避免連 Codex 自己開的 PR 也被重複 review。
6. repo 中的角色 TOML 不控制雲端 review；connector 讀適用的 AGENTS.md。

[Codex subagent 官方設定](https://learn.chatgpt.com/docs/agent-configuration/subagents) 說明 project TOML 與模型繼承；[GitHub review 官方設定](https://learn.chatgpt.com/docs/third-party/github) 說明 trigger、`@codex review` 與 Code Review Rules。以實際帳戶可用功能為準。
