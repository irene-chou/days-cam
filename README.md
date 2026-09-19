# DaysCam（天數相機）

拍照時把天數或日期疊印在照片上的 iOS App。疊字會在儲存時烘焙進圖片像素。

- 產品規格：[`docs/PRD.md`](docs/PRD.md)
- 任務清單：[`docs/TASKS.md`](docs/TASKS.md)
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
