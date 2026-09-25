# CLAUDE.md — 天數相機 App 專案規範

> 這是初版,由人類起草合理預設值,之後由 PM/Docs teammate 依實際開發狀況持續修訂。
> 標示【可調整】的項目是團隊還沒有共識前的合理預設,可視情況覆蓋;標示【硬規則】的項目建議所有 agent 都嚴格遵守,因為改動會影響多個 agent 之間的協作品質。

## 專案簡介
一個 iOS 相機 App:拍照時可將日期或天數(小孩年齡、紀念日天數等)疊印在照片上。目前是 MVP 階段,目標是同時練習「多 Claude Code agent 協作開發流程」,過程比產品完成度優先。詳細範圍見 `docs/PRD.md` 與 `PROJECT_PLAN.md`。

## 技術棧【可調整】
- 語言:Swift(最新穩定版)
- UI:SwiftUI 優先,只有在 SwiftUI 明顯無法滿足需求時(如底層相機控制)才用 UIKit 橋接
- 相機:AVFoundation
- 最低支援版本:先以近三個大版本的 iOS 為準,除非有明確理由需要往下相容
- 不引入第三方套件,除非該功能自己寫的成本明顯過高(例如複雜的圖片濾鏡函式庫);要引入前先在任務卡註明理由

## 程式風格【可調整】
- 命名採用 Swift 官方風格(camelCase、型別用 PascalCase),不使用縮寫命名(如 `btn`、`vc`)
- 避免 force-unwrap(`!`)與 force-try,除非在測試程式碼中且有明確理由
- 每個 public 函式/型別需要簡短的文件註解說明用途,註解語言用**英文**(程式碼是給任何未來可能加入的人看的;跟人類/agent 之間的討論、PR 描述、Issue 內容才用**繁體中文**,方便你直接讀懂)
- UI 元件、業務邏輯、資料層分開資料夾放,避免所有邏輯塞在單一 View 檔案裡

## Git / 任務流程【硬規則】
- 分支命名:`feature/<簡述>`、`fix/<簡述>`、`chore/<簡述>`
- 每個 PR 只做一件事,PR 描述需包含:改了什麼、為什麼改、怎麼驗證
- commit message 第一行簡短說明,不需要嚴格遵守 Conventional Commits 格式,但要讓人一眼看懂改了什麼
- 禁止直接 push 到 `main`,一律透過 PR
- **版本號**:上線前主版號一律為 0。每個大階段升一次次版號(MVP = 0.1、介面改版 = 0.2…),階段內的修正升修訂號(0.2.1);正式上架 App Store 時才升到 1.0.0。文件稱呼同步使用 0.x(例如「0.2 PRD」),不用 v1/v2。版本號只在 `project.yml` 的 `MARKETING_VERSION` 修改,由 Lead 在該階段任務全部合併後調整

## Agent 交接協議【硬規則】
這是多 agent 協作最容易出問題的地方,務必遵守:

1. **任務卡格式**:每個任務(GitHub Issue 或共享任務清單項目)必須包含:
   - 目標(這個任務要達成什麼)
   - 驗收標準(明確到下一個 agent,例如 QA teammate,可以直接照著測,不用回頭問)
   - 依賴的其他任務(如果有)
2. **決策落地**:任何規格變更、架構決策都要寫進 repo 裡的檔案(`docs/` 底下)或 GitHub Issue,不能只存在對話紀錄裡——因為下一個 teammate 不會看到你跟 Lead 的對話歷史。
3. **完成回報**:Dev teammate 完成任務後,必須附上「如何驗證這個改動」的具體步驟(指令、操作流程),QA teammate 才能直接照做。
4. **不確定就標記,不要猜**:遇到規格不明確的情況,在任務卡或 PR 描述裡明確標記「這裡是我的假設:...」,不要悄悄按自己猜的方式做掉,方便 Lead 或人類審核時能一眼抓到。
5. **規格自相矛盾時,以驗收表為準,先實作再回報**:散文式的需求描述與驗收表不一致時(這在本專案發生過),**以驗收表為準**繼續實作,同時回報 Lead 修正文字。理由是驗收表通常寫得更具體、也是 QA 實際照做的依據。不要停下來等裁決,但也不要默默選一邊。
6. **主動預告下游會誤判的地方**:交接時若你知道某處規格會讓下一個 teammate 誤判(例如「若照 FR-2.14 字面看會覺得這條驗收錯了,請以表格為準」),**在交接訊息裡先講**。事後解釋比事前預告貴得多——本專案已有一次因為預告而省掉整輪假 bug 往返的實例。
7. **靜態檢查(grep)誤傷時回報,不要遷就它**:若某條 grep 驗收逼你改變數命名、改方法名或改寫法才能通過,而那個改動在語意上毫無必要,**那通常是驗收條目寫得太粗,不是你的程式碼有問題**。回報 Lead 收斂該條,不要默默配合。本專案已有三條驗收因此被修正。
8. **Code review 迴圈**:每個 PR 開啟與每次 push 後,`claude[bot]` 會自動 review,送出 Approve 或 Request changes;有新 commit 時會先撤銷 bot 對舊 commit 的 approve。審核狀態看 PR 的 Review decision(`gh pr view <N> --json reviewDecision`)。
   - **Dev teammate**:收到 Lead 通知(或自己看到 Changes requested)後,讀 bot 的 review 總結與行內留言(`gh pr view <N> --comments`、`gh api repos/irene-chou/days-cam/pulls/<N>/comments`)。`[必修]` 逐條處理:同意就在同一分支修正、跑完整測試、push,並回覆該留言「已修正:<commit>」;不同意就回覆理由並告知 Lead,不要為了拿到 approve 硬改(同第 7 條精神)。`[建議]` 可自行判斷,不採納時簡短回覆原因即可
   - **Lead**:定期(例如 `/loop 10m`)檢查開著的 PR;bot 對最新 commit 要求修改時,依 TASKS-0.2「檔案所有權」通知負責的 teammate。同一個 PR 來回 **3 輪**仍未 approve,就停下來交給人類判斷,不要讓 bot 與 dev 無限往返
   - **合併條件**:bot 對最新 commit 已 approve(`reviewDecision` 為 `APPROVED`),且 qa 驗收通過;bot 被 dev 以理由駁回的條目需由 Lead 或人類確認
   - review workflow 修改前開的分支,若沒 merge 最新 `main`,不會跑新版 review(workflow 檔與 `main` 不同會被跳過),先 merge `main` 再 push

## 測試【可調整】
- 新增功能需附上對應的 XCTest 單元測試,涵蓋主要邏輯(尤其是天數計算這種容易出錯的核心邏輯)
- UI 測試先不強制要求,MVP 階段以手動驗證為主,除非某個流程反覆出問題才補自動化 UI 測試

## 明確禁止事項【硬規則】
- 不要加入訂閱付費、App 內購買、第三方分析/追蹤 SDK 等超出 MVP 範圍的功能,除非任務卡明確要求
- 不要依賴照片 EXIF 時間戳計算天數(見 `PROJECT_PLAN.md` 的技術重點說明);MVP 只做即時拍照
- 不要把「檔案建立時間」當作拍攝時間的備援卻不告知使用者

## 文件索引
- `PROJECT_PLAN.md`:整體規劃、MVP 範圍、agent 團隊架構、路線圖
- `docs/PRD.md`:詳細產品需求規格(由 PM teammate 產出)
- `docs/ARCHITECTURE.md`:技術架構文件(視需要由 Dev teammate 或 Docs teammate 補上)
- `docs/PRD-0.2-ui-redesign.md`、`docs/TASKS-0.2-ui-redesign.md`:0.2 介面改版的規格與任務卡;`docs/design/` 為定案設計稿
- `.claude/agents/`:各 teammate 的角色定義(職責、擁有的檔案、模型),spawn 時指定對應的 agent type