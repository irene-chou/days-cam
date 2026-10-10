# DaysCam App Icon 設計稿

目前套用版本：`dayscam-icon-v2.png`（內建 imagegen 編輯）。依使用者要求改為較淺的同系列配色：淺杏橘底、奶油白日曆、暖棕鏡頭；保留 v1 構圖。已輸出至 AppIcon，1024×1024、不含 alpha。

v2 編輯 prompt：保留原圖的日曆＋相機輪廓、位置、比例與鏡頭細節，只將配色調淺；背景 #F3D3AE、日曆 #FFFAF3、鏡頭與裝訂環 #94704E、中間鏡頭環 #B49473、橘色鏡頭環 #E9B574，降低陰影強度，保持小尺寸對比；不加入文字、邊框或外部圓角遮罩。

圖稿：`dayscam-icon-v1.png`。以奶油白日曆輪廓融合相機鏡頭，沿用介面的暖橘與炭黑色系；不使用文字或日期數字，方便小尺寸辨識。

這裡是我的假設：使用者已指定將本稿套用到專案，採用同一圖稿作為預設 AppIcon。此圖未套 iOS 外框遮罩，由系統裁切。

驗收 ICON-1：日曆裝訂環與相機鏡頭均清楚可辨；ICON-2：無文字、浮水印或外部裝置框；已目視確認。ICON-3：接入 `DaysCam/Assets.xcassets/AppIcon.appiconset/AppIcon.png`，輸出為 1024×1024、不含 alpha。驗證指令：`sips -g pixelWidth -g pixelHeight -g hasAlpha DaysCam/Assets.xcassets/AppIcon.appiconset/AppIcon.png`。下游注意：尚未完成裝置桌面驗收。

產出方式：內建 imagegen。

Prompt:

```text
Use case: logo-brand. Create one polished iOS app icon for DaysCam, an app that stamps dates and elapsed days onto photographs. Preserve and fuse calendar + camera into ONE memorable geometric symbol: an ivory calendar page with two bold binding tabs at the top and a warm charcoal circular camera lens integrated in its lower body, with a restrained amber ring and a tiny ivory lens reflection. Follow the project's warm palette: amber #C9772A, warm ivory #F7F3EE, charcoal #2A2622. Amber full-bleed square background, subtle warm tonal depth only. Front-facing, centered, generous safe margins, clean bold geometry, softened corners, elegant flat vector-like finish with extremely restrained depth. Calendar silhouette should read immediately; lens should clearly evoke photography. Strong silhouette at 48px. No letters, no numbers, no date grid, no watermark, no extra decorative objects, no mockup, no device frame, no exterior rounded-square mask: image fills the entire square, opaque background. Output a single square icon artwork.
```
