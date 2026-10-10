# Agent 最小閱讀路徑

所有角色先讀根目錄 [AGENTS.md](../AGENTS.md)。以下是按需閱讀，不表示可以忽略任務引用的回歸驗收。

| 情境 | 接著讀 |
|---|---|
| Claude Lead／Spec | [WORKFLOW 的分工與交接](WORKFLOW.md#分工與交接)、[README 路線圖](../README.md#路線圖與規格)、需求涉及的 PRD 段落；改卡前讀任務表依賴與所有權 |
| 開發（Claude subagent：邏輯與 UI） | `docs/agents/<角色>.md`、[開發操作](WORKFLOW.md#開發)、下方「0.2 共用入口」、該張卡的目標／範圍／全部驗收／依賴 |
| 高風險獨立 QA | [qa](agents/qa.md)、[QA 與截圖](WORKFLOW.md#qa)、下方「0.2 共用入口」、PR 對應的完整卡片及沿用驗收 |
| 一般／高風險 review | PR diff／描述、AGENTS 的 Code Review Rules、[review 操作](WORKFLOW.md#review)、變更涉及的驗收與 PRD 段落；高風險另讀 [risk-reviewer](../.claude/agents/risk-reviewer.md) |
| 首次環境設定 | [README](../README.md)、[角色啟動與 connector 設定](WORKFLOW.md#啟動與設定) |

## 0.2 共用入口

1. [TASKS-0.2](TASKS-0.2-ui-redesign.md) 只先讀 TASK-17 之前：驗收分級、事先預告、依賴、所有權。
2. 找單張卡：`rg -n '^## TASK-' docs/TASKS-0.2-ui-redesign.md`，依行號讀該卡至下一張卡之前。
3. 讀卡片引用的 [PRD-0.2](PRD-0.2-ui-redesign.md) 章節及 §0.1 假設；牽涉設計時讀 §1 及指定設計稿。設計稿可互動，規格以 PRD 為準。
4. 0.2 沒覆蓋的規格沿用 [PRD 0.1](PRD.md)。卡片的「沿用」及角色特別注意若引用 [TASKS 0.1](TASKS.md)，必須讀那些驗收；不要整份載入，也不要整份跳過。
5. 修改拍攝／日期／渲染／持久化時補讀 PRD 0.1 §4、§6 相關不變條件；兩版衝突先查 PRD 0.2 §9 的覆蓋清單。

新任務不要複製一整份背景，提供文件路徑、章節、TASK／PR 編號與 SHA 即可。
