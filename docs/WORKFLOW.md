# Claude + Codex 工作流程

此文件承接 [AGENTS.md](../AGENTS.md)。按工作階段讀對應節；目前在 **pilot 準備期**，外部 connector 是否啟用與試行結果必須另留證據。

## 分工與交接

| 工作 | 預設執行者／模型 | 交付 |
|---|---|---|
| 需求、規格、任務卡、Lead | Claude `lead-spec`／Sonnet | PRD／Issue／任務卡、驗收、依賴、所有權；複雜架構再用 Opus |
| 日期／渲染／相機／畫面骨架 | Codex `core-style`、`core-device`、`ui-shell`／GPT-6 Astra low | 實作、XCTest、PR 與驗證步驟 |
| 範圍明確的面板開發 | Codex `ui-panel`／GPT-6 Luna high | 實作、XCTest、PR；跨模組難題交 Lead 協調升級 |
| 驗收、截圖、失敗重現 | Codex `qa`／GPT-6 Luna high | 獨立驗收、證據、最新 SHA 的 qa status；複雜失敗另以 Astra 調查 |
| 開工前可行性檢查（按需一次） | Codex `feasibility-explorer`／GPT-6 Luna high | 唯讀的檔案／依賴／風險摘要 |
| 一般 review | Codex GitHub connector／服務管理的 review 模型 | GitHub review；不受本機 TOML 模型設定控制 |
| 高風險 review／爭議 | Claude `risk-reviewer`／Opus | 問題、影響、建議、未驗證處 |

模型是可調整的起點；上述 Codex ID 已對照本機 2026-10-03 模型清單，不保證其他帳戶可用。不可用時先在 app 選擇可用模型並調整該角色 TOML，不能改走 API key。五份角色是責任邊界，按任務啟動。一般流程是一位 developer 完成後交獨立 QA；只有依賴已滿足且擁有檔案不重疊時，才同時啟動兩位 developer。QA 操作 Xcode 的時段保持單一；完成任務即交接並結束，review 不再自動派多位 reviewer。下一階段更新任務表，延用角色職責即可。

高風險包含相機／AVFoundation／並行、持久化與資料遷移、可能遺失照片或設定、跨模組介面，以及三輪 review 未收斂。Lead 在任務／PR 標 `risk: high` 並寫原因，明確派 Claude review；此文字本身不是 Action 觸發器。一般任務標 `risk: normal`。

**交接流程**：Claude 寫好任務卡 → Codex 明確領取 → developer 開 PR → 獨立 QA 與 reviewer 檢查 → Lead 收斂人工事項與合併。兩家工具沒有共用 mailbox；以 GitHub Issue／PR／版本化文件交接，使用者或已有授權的工具送出以下資訊：

```text
任務：TASK-XX／Issue URL（目標、驗收、依賴見卡片）
角色：core-style／core-device／ui-shell／ui-panel／qa
領取：執行者、branch、worktree；寫回任務或 Issue，避免重複領取
閱讀：文件路徑＋章節，沿用驗收編號
風險：normal／high＋原因；假設與容易誤判的事項
交付：PR URL、head SHA、驗證命令／結果、待人類確認
```

共享 Markdown 任務由 Lead 記錄領取狀態，其他角色在 PR／Issue 回報；不要搶改 Lead 文件。遇到跨角色接口，請擁有者修改並同步 Lead。完成後用這份交接資料即可續接，不貼整段聊天。這一版不安裝自動撿單／跨工具派工服務。

## 開發

1. 依 [閱讀矩陣](AGENT-READING-MAP.md) 取得任務與回歸條目，檢查依賴已合併。
2. 各自 worktree，分支 `feature/task-XX-<簡述>`；修正／文件用對應前綴。一張卡一個 PR，必要時分 core／UI 半邊。QA 新增驗收測試用 `chore/qa-task-XX`。
3. 單元測試放 `DaysCamTests/Unit/<來源檔名>Tests.swift`，歸來源檔擁有者。QA 只能寫 `DaysCamTests/Acceptance/` 的版本化程式；測試輸出與專用截圖 worktree 可寫。
4. 每角色獨立模擬器，先用 `xcrun simctl list devices available` 查找 `iPhone 16 <角色>` 及 UUID，**查無才** `xcrun simctl clone "iPhone 16" "iPhone 16 <角色>"`；clone 不會檢查重名。找不到基底裝置時先查可用 runtime／裝置，不能盲目建多台。
5. 程式 PR 送出／修正前在自己的模擬器跑完整測試；獨立 DerivedData 防止平行執行互踩。純文件／角色設定 PR 做引用、設定與規則檢查，無須 iOS 產品測試，但仍須滿足 qa gate。

```sh
xcodegen generate
xcodebuild -project DaysCam.xcodeproj -scheme DaysCam \
  -destination 'platform=iOS Simulator,id=<角色模擬器 UUID>' \
  -derivedDataPath /tmp/dayscam-dd-<worktree識別>-<角色> test
```

PR 使用 [模板](../.github/PULL_REQUEST_TEMPLATE.md) 附驗收編號、具體指令、結果與假設；不要只寫「已測試」。

## Review

試行期 `.github/workflows/claude-code-review.yml` 仍在 opened／synchronize／ready_for_review／reopened 觸發。新 push 撤銷舊 Claude approve；修改 review workflow 前已存在的分支需先 merge 最新 main，避免 Action 因 workflow 版本不同而跳過。

```sh
gh pr view <N> --json headRefOid,reviewDecision
gh pr view <N> --comments
gh api --paginate repos/irene-chou/days-cam/pulls/<N>/comments
gh api --paginate repos/irene-chou/days-cam/pulls/<N>/reviews
```

- Developer：必修逐條處理，同意則修正、完整測試、push，回覆「已修正：<commit>」；不同意要說明並交 Lead／人類裁決。建議可自行取捨並簡短回覆理由。
- Codex connector：預設開 PR 自動 review；修正集中 push 完後，在最新 commit 留一次 `@codex review`。同 SHA 已在 review 時勿重複觸發。P0／P1 與 Claude 必修均須處理；沒有留言不代表通過。
- Lead：依既有巡檢安排檢查開啟的 PR，按所有權派修；三輪仍未收斂就停止、加 `needs-human`。截圖待確認、dev 駁回 reviewer 條目也加此 label，人類回覆後記到 PR 並移除。
- 合併前確認 Claude 的 `APPROVED` review 的 `commit_id` 等於最新 `headRefOid`、PR decision 為 `APPROVED`、同 SHA 的 `qa=success`，且待裁決事項已結案。PR aggregate decision 不能代替 SHA 比對。
- 看板：可合併候選 `is:pr is:open review:approved status:success`；等人類 `is:pr is:open label:needs-human`。搜尋只是入口，仍需上述最終檢查。

## QA

驗收層級：A＝QA 可執行（單元／靜態／view model）；B′＝設計對照（SwiftUI Preview）；B＝人類實機。模擬器不能證明實體相機、烘焙目視與權限行為。B 標「待人類驗」後回報，繼續其他可做項目。

QA 在 PR 留逐條通過／失敗（附輸出）／待人類驗；補齊開發單元測試未涵蓋的 Acceptance 測試。B′ 由 QA 持有 Xcode MCP，`RenderPreview` 與設計稿比較差異；同時僅一個 agent 操作 Xcode 視窗。工具不可用就交接或標 pending，不能假稱截圖完成。

### qa status

`qa-status.yml` 對 opened／synchronize／reopened 初始化最新 SHA：只含 `docs/`、`.claude/` 或 `*.md` 為 success「純文件，免 qa」，其餘 pending。**新增 `.codex/*.toml` 不在豁免內**，此類 PR 需完成設定檢查並手動更新 status；本次不擴大自動豁免。

- `success`：A 全過，且 B／B′ 截圖及爭議已由人類完成必要確認，已可合併。
- `pending`：尚有實機、截圖、裁決或未執行的檢查，description 註明阻礙。
- `failure`：驗收失敗。新 push 後重驗並設定新 SHA；舊報告不沿用。人類確認最後一項後由 Lead 記到 PR 並更新 status。

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
2. Claude 使用 `.claude/agents/lead-spec.md` 或 `risk-reviewer.md`。五個舊開發／QA 角色是備援，只在 Lead 明確指派時使用，避免兩家同時領同一卡。
3. Codex 新 session 使用 `.codex/agents/*.toml`。例如「請以 core-style subagent 處理 TASK-XX，依交接卡領取，完成後回報 PR 與驗證。」先確認任務／模型／worktree；若客戶端未辨識 custom agent，可在獨立 session 指定相同角色文件與模型手動執行並回報限制。
4. QA 由獨立 agent 驗收 PR 的指定 SHA，工具與 MCP 的權限依執行環境提供。角色檔是工作規範，不會自行安裝 Xcode MCP、創建 worktree 或派工。
5. GitHub connector：在 [Codex Code Review 設定](https://app.chatgpt.com/settings/code-review) 選 `irene-chou/days-cam`、確認 repo 連接與 push／admin 權限，啟用 Automatic review，將 Review trigger 選為 PR 開啟（若畫面提供 On PR open）。若沒有此選項，先用手動 `@codex review`，記錄實際選項，不假定每次 push 都需要重跑。
6. repo 中的角色 TOML 不控制雲端 review；connector 讀適用的 AGENTS.md。這次沒有新增 API action／key，也沒有變更帳戶端開關。

[Codex subagent 官方設定](https://learn.chatgpt.com/docs/agent-configuration/subagents) 說明 project TOML 與模型繼承；[GitHub review 官方設定](https://learn.chatgpt.com/docs/third-party/github) 說明 trigger、`@codex review` 與 Code Review Rules。以實際帳戶可用功能為準。

## Pilot 與切換任務

**目標**：兩個低風險程式 PR 能走 Codex 開發 → 獨立 QA → connector review，保有既有合併 gate。**依賴**：本 PR 合併、帳戶 connector 啟用。Lead 挑正常產品任務，不為試行製造無效 PR。

- [ ] 記錄 connector 設定人、日期、repo 與 trigger；新 Codex session 能辨識角色，QA 可用 Xcode 工具。
- [ ] Pilot 1／2 各在 PR 記錄：PR URL、觸發方式、review URL、bot 身分／state／commit_id（若回傳）、QA SHA、人工項目、錯誤或漏觸發、兩邊額度前後差。沒量測的欄位寫「未量測」。
- [ ] 至少一次修正 push 後重審，確認舊 review／QA 不會當成最新結果；額度不足或服務失敗時維持未完成。
- [ ] Lead 根據證據開第二個 gate 切換 PR：若 connector 只有 COMMENTED／reaction，須設計可靠的 SHA 綁定 review status 或人工 gate；不可把無留言或按讚直接當 APPROVED。
- [ ] 第二個 PR 才將 Claude Action 改為高風險／人工觸發，同步修改合併規範、branch protection（如有）與看板。完成前仍執行現有 Claude gate。

本清單尚未勾選即表示外部設定／pilot 未完成；文件合併不代表 gate 已切換。
