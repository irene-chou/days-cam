# Claude + Codex 協作流程設計

2026-10-03：人類已在對話核准本設計及第一個 PR 的實作。此文件是遷移決策紀錄；日常 agent 只需依 AGENTS.md 的閱讀路徑工作。

## 目標與邊界

保留「需求 → 任務卡 → 開發 → QA → review → 合併」，將 Claude Pro 留給需求、規格與高風險判斷；Codex 訂閱負責開發、QA 及 GitHub connector review。減少每次開新 agent 時重讀的文件與重複規則。

- Claude Lead/Spec：需求、PRD、任務卡、檔案所有權、仲裁。
- Codex：沿用 core-style、core-device、ui-shell、ui-panel、qa 五個責任範圍；一般一位 developer 後接獨立 QA，最多兩位檔案不重疊的 developer 平行。角色可跨階段沿用；複雜任務可先做一次唯讀可行性探索。
- Codex GitHub connector：一般 PR review；PR 開啟自動 review，修正後手動 `@codex review`。實際開關需另於帳戶設定完成。
- Claude Risk Reviewer：相機／AVFoundation／並行、持久化與遷移、資料遺失、跨模組或三輪未收斂的 review。
- 人類：實機、視覺確認、爭議與發佈決策。

## 相容與精簡

1. AGENTS.md 保留全域硬規則、當前合併條件及 Code Review Rules；操作細節集中到 docs/WORKFLOW.md。
2. 角色特有事項放 docs/agents/；兩家角色設定引用同一份內容。舊 Claude 五個角色保留成備援入口，避免既有啟動方式失效。
3. 閱讀矩陣指向單張任務卡、引用的規格段落及沿用驗收；不刪 PRD 或任何任務驗收表，也不假設舊版已全部失效。
4. PROJECT_PLAN.md 去掉過時的工具操作與重複規則；README 指向目前 0.2 的入口。PR 模板提供任務、風險、驗證、最新 SHA、人工確認欄位。
5. 跨供應商透過 GitHub Issue／PR／版本化文件交接；沒有新增自動派工服務，也不假設雙方 mailbox 互通。

## 遷移順序與驗收

- 本 PR：完成文件、模型與角色設定，檢查 TOML 語法、引用、規則完整性及文件減量；不變更產品或 Actions。
- 啟用 connector 後，用兩個低風險程式 PR 記錄首次 review／新 push 重審、review 的 SHA 與狀態、QA／人類確認及額度。
- 試行期間仍要求最新 commit 的 Claude bot approve、PR decision APPROVED、qa=success，三輪未收斂加 needs-human。
- 試行後另開 gate 切換 PR：查證 connector 是 approval、comment 或 reaction，決定能否直接作 required review；若需替代 status，必須能綁最新 SHA、在 push 時失效並處理失敗／無結果，不能將沉默當成功。
- 不設定 Platform API、API key 或 codex-action；不宣稱 repo 文件已啟用外部 connector。

驗收：五角色所有權與特殊注意事項保留；兩份 PRD、TASK-01～30 的卡片本文不變；QA／截圖／review gate 規則可從入口找到；單一角色的啟動內容縮短；外部尚待完成的步驟明列在 WORKFLOW.md。
