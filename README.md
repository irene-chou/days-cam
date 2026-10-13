# DaysCam（天數相機）

拍照時把天數或日期疊印在照片上的 iOS App。疊字會在儲存時烘焙進圖片像素。

## 路線圖與規格

| 階段 | 範圍 | 規格 |
|---|---|---|
| 0.1 MVP | 即時拍照、設定檔、日期／天數文字、九宮格位置、儲存 | [PRD](docs/PRD.md) |
| 0.2 介面改版 | 相機工具、疊字面板、字型與色彩、天數單位、拖曳定位、照片瀏覽 | [PRD-0.2](docs/PRD-0.2-ui-redesign.md) |
| 0.3 繁中字型 | 蘋方內建、開源與系統字型點了才下載 | [PRD-0.3](docs/PRD-0.3-fonts.md) |
| 0.4 面板改版 | 面板與設定檔流程調整 | Issue [#226](https://github.com/irene-chou/days-cam/issues/226) 與各 TASK issue；任務卡一律為 GitHub issue |
| 1.0 上架 | 首版 App Store 上架，只上 iPhone | [RELEASE](docs/RELEASE.md) |

新版未覆蓋的規格沿用前一版。MVP 排除訂閱／IAP、雲端帳號同步、多語系、社群分享與 Widget。發佈（簽名、TestFlight、商店資料）步驟與現況見 [RELEASE](docs/RELEASE.md)，是否上架由人類決定。

Agent 開工：[`AGENTS.md`](AGENTS.md) → [`閱讀矩陣`](docs/AGENT-READING-MAP.md)；雙 agent 與 connector 設定見 [`WORKFLOW`](docs/WORKFLOW.md#啟動與設定)。

## 開發環境

- Xcode 16.2 以上
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- 最低支援 iOS 18.0；只支援 iPhone（2026-10-10 使用者裁定暫不支援 iPad，iPad 收起面板的 3:4 布局底部裁切問題不處理）

## Clone 後必須先產生專案檔

`DaysCam.xcodeproj` 與 `DaysCam/Info.plist` **不在版控裡**，`project.yml` 才是單一真實來源（權限說明等 Info.plist 內容改 `project.yml` 的 `info.properties`）。clone 之後要先跑：

```
xcodegen generate
```

才會有 `.xcodeproj` 可以用 Xcode 開啟。之後任何時候改了 `project.yml`，或從遠端拉到新增的原始檔，都再跑一次。

## 建置與測試

```
xcodegen generate
xcodebuild -project DaysCam.xcodeproj -scheme DaysCam \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

xcodebuild -project DaysCam.xcodeproj -scheme DaysCam \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

並行開發（各自 worktree、DerivedData、模擬器）見 [WORKFLOW 開發](docs/WORKFLOW.md#開發)。
