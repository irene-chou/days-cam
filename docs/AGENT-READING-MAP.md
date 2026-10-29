# Agent 最小閱讀路徑

所有角色先讀根目錄 [AGENTS.md](../AGENTS.md)。以下是按需閱讀，不表示可以忽略任務引用的回歸驗收。

| 情境 | 接著讀 |
|---|---|
| Claude Lead／Spec | [WORKFLOW 的分工與交接](WORKFLOW.md#分工與交接)、[README 路線圖](../README.md#路線圖與規格)、需求涉及的 PRD 段落；開卡前讀 [CONVENTIONS](CONVENTIONS.md) |
| 開發（Claude subagent：邏輯與 UI） | `docs/agents/<角色>.md`、[開發操作](WORKFLOW.md#開發)、下方「共用入口」、該張卡的目標／範圍／全部驗收／依賴 |
| 高風險獨立 QA | [qa](agents/qa.md)、[QA 與截圖](WORKFLOW.md#qa)、下方「共用入口」、PR 對應的完整卡片及沿用驗收 |
| 一般／高風險 review | PR diff／描述、AGENTS 的 Code Review Rules、[review 操作](WORKFLOW.md#review)、變更涉及的驗收與 PRD 段落；高風險另讀 [risk-reviewer](../.claude/agents/risk-reviewer.md) |
| 首次環境設定 | [README](../README.md)、[角色啟動與 connector 設定](WORKFLOW.md#啟動與設定) |

## 共用入口

1. [CONVENTIONS](CONVENTIONS.md)：驗收分級、共用測試情境、檔案所有權、易誤判處。
2. 任務卡是 GitHub issue：`gh issue view <號碼>`，讀目標／範圍／全部驗收／依賴。
3. 規格分四層：[PRD 0.1](PRD.md) ← [PRD-0.2](PRD-0.2-ui-redesign.md) ← [PRD-0.3](PRD-0.3-fonts.md) ← [PRD-2.0](PRD-2.0-browse-first.md)，新版未覆蓋的沿用前一版；衝突先查 PRD-2.0 §9、PRD-0.2 §9、PRD-0.3 §8 的覆蓋清單。**2.0 的卡（#613 起）必讀 PRD-2.0 與設計稿 [D7](design/D7-browse-flow.html)**。只讀卡片引用的章節，牽涉設計時讀對應設計稿（規格以 PRD 為準）。
4. 修改拍攝／日期／渲染／持久化時補讀 PRD 0.1 §4、§6 相關不變條件。

新任務不要複製一整份背景，提供文件路徑、章節、issue／PR 編號與 SHA 即可。
