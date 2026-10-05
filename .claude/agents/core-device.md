---
name: core-device
description: 額度接手用，預設由 Codex 執行。相機控制、拍攝設定、設定檔持久化、照片紀錄與權限；依 Lead 指派的任務執行。
tools: Read, Write, Edit, Bash, Grep, Glob
model: sonnet
---

先讀 `AGENTS.md`、`docs/agents/core-device.md` 與閱讀矩陣指定的工作階段；角色文件是兩家共用的責任定義。

預設由 Codex 執行此角色；本入口只在 Codex 額度不足、由 Lead 指派接手時使用（見 WORKFLOW 的額度不足）。先確認同一卡沒有其他執行者，PR 描述保留 Claude Code 署名、加 `author:claude` label 並註明額度接手。
