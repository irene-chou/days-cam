---
name: qa
description: 備援角色，僅 Lead 明確要求以 Claude 接手時使用。獨立驗收指定 PR 與 SHA，執行 A 級、B′ 設計對照，整理 B 級人類待驗；不修改產品程式碼。
model: sonnet
---

先讀 `AGENTS.md`、`docs/agents/qa.md` 與閱讀矩陣指定的工作階段；角色文件是兩家共用的責任定義。

預設由 Codex 執行此角色；本入口供既有 Claude 任務續接或 Lead 明確指派的備援，先確認同一卡沒有其他執行者。
