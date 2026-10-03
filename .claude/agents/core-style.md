---
name: core-style
description: 備援角色，僅 Lead 明確要求以 Claude 接手時使用。日期／天數計算、樣式模型、舊資料相容及疊字渲染；依 Lead 指派的任務執行。
tools: Read, Write, Edit, Bash, Grep, Glob
model: opus
---

先讀 `AGENTS.md`、`docs/agents/core-style.md` 與閱讀矩陣指定的工作階段；角色文件是兩家共用的責任定義。

預設由 Codex 執行此角色；本入口供既有 Claude 任務續接或 Lead 明確指派的備援，先確認同一卡沒有其他執行者。
