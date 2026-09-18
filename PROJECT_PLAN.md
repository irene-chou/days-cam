# 「天數相機」App 專案規劃書
> 目標雙軌並行:(1) 做出一個可用的 iOS 相機 App,把日期/天數印在照片上;(2) 以此專案為載體,practicing 多 Claude Code agent 協作 + 自動化 workflow,**過程 > 完成度**。

---

## 1. 產品範圍(刻意精簡的 MVP)

**核心單一功能**:開啟相機 → 選擇/建立一個「計時器」(小孩生日 / 紀念日 / 自訂起始日)→ 依所選樣式把日期或天數即時疊在觀景窗與拍出的照片上 → 存到相簿。

**MVP 明確排除**(留給後續迭代當作 agent 團隊的練習任務):
- 訂閱付費、App 內購買
- 雲端同步 / 帳號系統
- 多語系
- 社群分享、小工具(Widget)

**技術重點/坑**(競品研究得到的教訓):
- 天數計算要以「按下快門當下的系統時間」為準,**不要**依賴照片檔案的 EXIF 時間戳,否則透過 AirDrop/社群傳輸的照片會導致天數跑掉(BabyAgeCam 踩過這個坑)。這個坑只存在於「匯入舊照片」情境——MVP 只做即時拍照,架構上就不會碰到 EXIF 是否可靠的問題。若未來做匯入功能,原則是:有 EXIF 就用,沒有或不合理時**跳出來讓用戶手動輸入拍攝日期**,絕不能默默用檔案建立時間充數。
- 疊字要在儲存時「烘焙」進圖片像素,而不是只做成可移除的浮水印圖層,才能達到類似傳統沖印相機「印在照片上」的效果。

### 顯示格式自訂——分三軸拆解,分級決定 MVP 邊界

自訂功能容易滾雪球,拆成三個獨立的軸來看:

1. **內容格式**(顯示什麼文字)——差異化價值最高,MVP 做完整
2. **視覺呈現**(怎麼呈現這段文字)——MVP 做到「夠用」,不做到「做滿」
3. **邏輯層**(天數怎麼算,如起算日規則)——獨立於視覺格式之外,避免混在同一個設定畫面裡

| 項目 | MVP 做 | 留到後續迭代(Phase 4 練習題) |
|---|---|---|
| 內容格式 | 5~6 種預設模板(純天數、天數+單位轉換如「1年2個月」、純日期、日期+天數並列、自訂前後綴文字帶入變數) | 使用者自訂字串樣板(自由文字框插入變數) |
| 位置 | 9 宮格定位 | 自由拖曳定位 |
| 字體/顏色 | 4~6 組預設「主題」(字體+顏色+陰影組合,陰影/底色框避免淺色照片文字看不清) | 完全自由選字型、上傳自訂字型、漸層色 |
| 天數起算規則 | 「當天算第 1 天 / 第 0 天」二選一 | 農曆、時區邊界等進階規則 |

用「預設模板/主題」取代「完全自由客製」,是為了用較低的工程量涵蓋大部分需求;真正複雜的自由客製化(拖曳定位、自訂字型)留到後續迭代,剛好適合當作 iOS Dev teammate + QA teammate 協作的中等難度練習任務。

---

## 2. Agent 團隊架構(核心練習目標)

用 **Claude Code Agent Teams**(實驗性功能)當作整個開發流程的骨幹:一個 Lead session 負責拆解需求、分派任務、整合結果;多個 Teammate session 各自獨立運作,透過共享任務清單與 mailbox 訊息互相協調。

### 開通方式
在 `~/.claude/settings.json` 或 shell 環境變數加入:
```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

### 團隊角色設計

| 角色 | 定位 | 主要交付物 | 建議工具/權限 |
|---|---|---|---|
| **Lead(你直接對話的 session)** | 拆解 PRD、分派任務、仲裁衝突、最終審核 | 任務清單、進度整合 | 全權限 |
| **PM/Spec Teammate** | 把你的口頭需求轉成明確 PRD 與驗收標準 | `docs/PRD.md`、任務卡 | Read/Write |
| **iOS Dev Teammate**(可視工作量開多個) | 依規格寫 SwiftUI / AVFoundation 相機邏輯 | Feature branch + PR | Read/Write/Bash |
| **QA/Test Teammate** | 寫 XCTest 單元測試、跑測試、回報 bug | 測試報告、bug issue | Read/Bash(唯讀+跑測試) |
| **Release/DevOps Teammate** | 版本號、Fastlane 打包、TestFlight 上傳、GitHub Actions | Release note、CI 設定檔 | Read/Write/Bash |
| **Docs Teammate**(選配) | README、架構文件、變更日誌 | `docs/` 底下文件 | Read/Write |

**分工原則**:
- 用 **Subagent**(`.claude/agents/*.md`)定義可重複使用的角色規格(例如 `ios-dev.md`、`qa-tester.md`),之後 spawn teammate 時可以直接繼承這份定義的 system prompt 與工具限制。
- 用 **Agent Teams** 處理真正需要「討論、平行推進、互相依賴」的階段(例如同時開發 UI 與相機核心邏輯);單純、明確、不太需要來回討論的小任務,交給一般 subagent 就好,成本更低。
- 每個 teammate **不會**自動繼承 Lead 的對話歷史,只會載入專案的 `CLAUDE.md`、MCP 設定與 skills——所以規格、驗收標準一定要寫進共享文件或任務卡裡,不能只存在你跟 Lead 的對話中。

---

## 3. Workflow 骨幹

```
GitHub Repo(單一事實來源)
├── CLAUDE.md              ← 專案規範、程式風格、agent 之間的交接協議
├── docs/
│   ├── PRD.md              ← PM Teammate 產出
│   └── ARCHITECTURE.md
├── .claude/
│   └── agents/             ← 各角色 subagent 定義(ios-dev.md, qa-tester.md, release-bot.md...)
├── App/                    ← Xcode 專案
├── Tests/
├── fastlane/               ← 簽名、打包、TestFlight 上傳腳本
└── .github/workflows/      ← CI:lint、build、test 自動跑
```

**交接協議(寫進 CLAUDE.md)**:
- 每個任務卡必須包含:目標、驗收標準、依賴的其他任務。
- Dev Teammate 完成後必須附上「如何驗證」的步驟,QA Teammate 才能直接照做,不用回頭問。
- 所有決策與規格變更都落地成 repo 裡的檔案或 GitHub Issue,禁止「只講在對話裡」。

**人類(你)的角色**:當「最終審核 + 仲裁者」——關鍵決策(要不要上架、方向要不要轉彎)由你拍板,其餘盡量放手讓 agent 團隊自己跑完一輪。

---

## 4. 分階段路線圖

### Phase 0:環境與骨架(這階段主要是你手動做,建立起跑點)
- [ ] 開通 Agent Teams(env var)
- [ ] 建立 GitHub repo + Xcode 專案骨架(空的 SwiftUI App,能跑起來即可)
- [ ] 寫第一版 `CLAUDE.md`(先簡單列出程式風格與交接規則,之後讓 PM/Docs teammate 補完)
- [ ] Apple Developer 帳號設定 Bundle ID、Provisioning Profile

### Phase 1:PRD 與任務拆解(練習「Lead 分派任務」)
- 對 Lead 下一個類似這樣的 prompt:
  > 「我要做一個 iOS 相機 App,核心功能是〔見上方 MVP 範圍〕。幫我 spawn 一個 PM teammate 把這個需求寫成 PRD 和任務清單,驗收標準要明確到 QA teammate 可以直接照著測。」

### Phase 2:團隊協作開發 MVP(核心練習)
- Spawn iOS Dev + QA + (視情況)Design teammate 平行推進
- 觀察並練習:teammate 之間怎麼互相依賴、怎麼透過共享任務清單自動解鎖後續任務、怎麼用 mailbox 直接溝通而不透過你

### Phase 3:自動化發佈流程(練習 DevOps 自動化)
- Release teammate 建立 Fastlane 設定 + GitHub Actions,做到「push 到 main → 自動跑測試 → 自動打包上傳 TestFlight」
- 這階段特別適合拿來練習「hooks」(例如 PostToolUse 自動跑 linter)

### Phase 4:迭代練習(把之前排除的功能當練習題)
- 每加一個功能(訂閱、Widget、多語系...)就是一次完整走一遍「PRD → 分工 → 開發 → 測試 → 發佈」的機會,可以嘗試不同的團隊分工方式做對照練習

---

## 5. 成本與注意事項
- Agent Teams 會同時跑多個完整的 Claude Code session,token 消耗遠高於單一 subagent,建議先用小任務(如 Phase 1 的 PRD 拆解)試水溫,抓一下實際花費再決定 Phase 2 要開幾個 teammate 平行跑。
- Teammate 不會自動套用 Lead 的 model,如果要統一模型,記得在 prompt 裡明講(例如「每個 teammate 都用 Sonnet」)。
- 這是實驗性功能,行為可能隨版本更新調整,開工前建議看一下當時最新的官方文件。