# DaysCam（天數相機）

拍照時把天數或日期疊印在照片上的 iOS App。疊字會在儲存時烘焙進圖片像素。

- 目前規格：[`0.2 PRD`](docs/PRD-0.2-ui-redesign.md)；未覆蓋部分沿用 [`0.1 PRD`](docs/PRD.md)
- 目前任務：[`TASK-17～30`](docs/TASKS-0.2-ui-redesign.md)；舊版回歸依據 [`TASK-01～16`](docs/TASKS.md)
- Agent 開工：[`AGENTS.md`](AGENTS.md) → [`閱讀矩陣`](docs/AGENT-READING-MAP.md)
- 雙 agent 與 connector 設定：[`WORKFLOW`](docs/WORKFLOW.md#啟動與設定)
- 整體規劃：[`PROJECT_PLAN.md`](PROJECT_PLAN.md)

## 開發環境

- Xcode 16.2 以上
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- 最低支援 iOS 18.0

## Clone 後必須先產生專案檔

`DaysCam.xcodeproj` **不在版控裡**，`project.yml` 才是單一真實來源。clone 之後要先跑：

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

### 多個 worktree 並行時要指定 DerivedData

平行開發時每個人各有一個 git worktree，但專案名稱都是 `DaysCam`，Xcode 會把它們雜湊到**同一個** DerivedData 目錄。兩邊同時跑 `xcodebuild test` 會互踩，出現 result bundle 的寫入警告。

各自加上 `-derivedDataPath` 即可：

```
xcodebuild -project DaysCam.xcodeproj -scheme DaysCam \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/dd-<你的識別> test
```

單人開發不需要這個參數。
