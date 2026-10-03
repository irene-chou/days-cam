# Claude + Codex Workflow Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan in the current session. The user approved implementation; proceed to the reviewable PR.

**Goal:** 建立可沿用現有交接與 gate 的雙 agent 文件／角色設定，降低新 agent 閱讀負擔。
**Architecture:** 全域規則集中 AGENTS.md，按需讀 WORKFLOW 與角色文件；Claude／Codex 設定只是各自的入口。
**Tech Stack:** Markdown、Claude YAML frontmatter、Codex TOML、現有 GitHub Actions。
**Spec:** [設計](../specs/2026-10-03-claude-codex-workflow-design.md)

## Global Constraints

- 不變更產品或 Actions；維持最新 commit 的 Claude approve 與 qa=success。
- 不刪 PRD 或任何任務驗收表；兩家使用相同檔案所有權與 QA 邊界。
- 不設定 Platform API、API key 或 codex-action。
- 分支 docs/claude-codex-workflow；只建立 PR，不合併。

## Review Focus

- 新 agent 能否找到沿用的 0.1 驗收，而非只讀 0.2。
- 精簡後 QA 是否仍等待實機／截圖／爭議的人類確認。
- 舊 Claude 角色入口、模擬器隔離與檔案所有權是否仍有效。
- connector 沒啟用、沒結果或只有留言時是否被誤認為已 approve。
- 新增 .codex TOML 是否被誤認為 qa-status.yml 自動豁免的純文件。

## Task 1: 文件與交接

**Files:** AGENTS.md、PROJECT_PLAN.md、README.md、docs/WORKFLOW.md、docs/AGENT-READING-MAP.md、docs/TASKS-0.2-ui-redesign.md、.github/PULL_REQUEST_TEMPLATE.md。
**Interfaces:** 保留任務驗收；提供所有角色共用的操作與閱讀路徑。
- [x] 精簡 root 規則，將 review／QA／截圖與模擬器命令移到 WORKFLOW；新增跨工具交接與 pilot 清單。
- [x] 更新索引、任務表中的 agent 入口與 Lead 所有權；TASK-17 以下本文不變。
- [x] 以 git diff 檢查規則保留、Markdown 連結與舊 gate 相容性。

## Task 2: 角色與設定

**Files:** docs/agents/*.md、.claude/agents/*.md、.codex/agents/*.toml。
**Interfaces:** 沿用 Task 1 的閱讀路徑與當前 task table 所有權。
- [x] 將五個舊角色的特有指示移入 docs/agents；Claude 原入口改為備援引用。
- [x] 新增 Claude lead-spec、risk-reviewer，Codex 五角色及 feasibility explorer；限定 QA 產品碼不可寫。
- [x] TOML 解析、required fields／本機模型識別碼及所有內部引用檢查；runtime 未啟動要明確記錄。

## Task 3: 檢查與 PR

**Files:** 上述檔案、此計畫的完成紀錄。
**Interfaces:** 一份可供全分支 review 的 diff。
- [x] 檢查 whitespace、PRD／task card／workflow 未變；記錄入口字元減量（不換算 token）。
- [x] 一次獨立唯讀 review，修正實質問題；文件／設定改動不跑 iOS 產品測試。
- [ ] 依邏輯分組 commit，push 文件分支，建立並附加 PR；記錄 connector 與 pilot 未執行。

## 執行紀錄

- Ruling：採同一 session 實作；避免為文件拆出多個 implementer，最後只做一次獨立 review。
- Ruling：設定／文件檢查取代 TDD 與 iOS 測試；本 PR 不改可執行產品程式。
- Task 1／2 complete：共用文件、五個可延續角色、Claude 備援入口、Codex TOML 與 PR 模板已完成。
- 檢查：Python 3.12 tomllib 解析六份 Codex TOML、Python YAML 解析七份 Claude frontmatter，required fields／模型與 reasoning 清單相符；64 個內部 Markdown 引用存在，git diff --check 通過。
- 保留檢查：PRD 兩份、TASKS 0.1、TASK-17～30 卡片本文、CLAUDE.md 匯入及全部 Actions 與基底逐位元相同。
- 獨立 review：workflow_review 未發現 Critical／Important；角色描述與 QA 的舊卡片指示依已核准的「跨階段角色」要求收斂。
- 文件量測：AGENTS.md 5,005 → 2,105 Unicode 字元（減少 57.9%）；PROJECT_PLAN.md 4,345 → 1,157（減少 73.4%）。字元不是 token；共用操作移至按需讀取的 WORKFLOW，總 repo 篇幅不代表啟動成本。
- 尚未執行：custom agent 實際載入／模型呼叫、Xcode MCP、外部 connector 設定與兩個 pilot PR。這些列於 WORKFLOW 的後續任務；本 PR 不跑 iOS 測試。
- 自我檢視：設計各項皆由 Task 1／2 覆蓋；Review Focus 逐項由保留檢查與獨立 review 查核。設定可用性以 pilot 為準，不聲稱已執行。
