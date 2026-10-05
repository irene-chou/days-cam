# 開源字型清單（0.3）

App 下載的開源字型與授權資料。數值寫死在 `FontCatalog`（TASK-32），由 TASK-31 產生；換版本時新增 `dayscam-fonts` 的 tag 並同步本表。

- 下載點：公開 repo [`irene-chou/dayscam-fonts`](https://github.com/irene-chou/dayscam-fonts)，tag `v1`
- 主要網址：`https://cdn.jsdelivr.net/gh/irene-chou/dayscam-fonts@v1/<路徑>`
- 備援網址：`https://raw.githubusercontent.com/irene-chou/dayscam-fonts/v1/<路徑>`
- 2026-10-06 已對 6 個網址完整下載驗證，大小與 SHA-256 一致（驗收 31.1，紀錄見 #162）

| fontID | 顯示名稱 | 路徑 | bytes | SHA-256 | PostScript | 字型版本 | App 內授權檔 |
|---|---|---|---|---|---|---|---|
| `huninn` | 粉圓 | `huninn/jf-openhuninn-2.1.ttf` | 4911464 | `9d5bf4932d31fe94c18cd8cfddc98bc1b14ce10f4e354c682179db290a99c825` | `jf-openhuninn-2.1` | 2.1 | `huninn-OFL.txt`、`huninn-Apache-2.0.txt` |
| `notoSerifTC` | 思源宋體 | `noto-serif-tc/NotoSerifTC-Bold.otf` | 8253304 | `3ca2b3294ec84b795d0a45695e78e3612a44dce50f9fc776cd40206340a5768d` | `NotoSerifTC-Bold` | 2.003 | `notoSerifTC-OFL.txt` |
| `iansui` | 芫荽 | `iansui/Iansui-Regular.ttf` | 9447424 | `7f1aa62e9dcbf40d0ce41a5d3f1e5ea602e66c295778ac6fefb6b84d8ed08bd5` | `Iansui-Regular` | 1.012（官方 release tag `v1.020`） | `iansui-OFL.txt` |

## 著作權聲明（授權頁顯示用）

逐字取自**字型檔的 copyright 欄位**（`kCTFontCopyrightNameKey`），不改寫。粉圓與芫荽的字型欄位和授權檔首段內容一致；思源宋體的上游 LICENSE 沒有著作權行，所以一律以字型檔欄位為準（粉圓欄位中的 `(x)` 是原文，照錄）。

- **粉圓**：

  ```
  [Kosugi Maru]
  Copyright (c) 2010 MOTOYA CO.,LTD.

  [Varela Round]
  Copyright (x) 2011-2016 The Varela Round Project Authors (https://github.com/alefalefalef/Varela-Round-Hebrew/), with Reserved Font Names 'Varela' and 'Varela Round'.

  [jf open huninn]
  Copyright (c) 2020-2024 The jf open huninn font is redistributed by justfont Co., Ltd., with Reserved Font Names 'open huninn' and 'huninn' under SIL Open Font License. The Hanzi part of this project was derived from Kosugi Maru under Apache-2.0 (https://www.apache.org/licenses/LICENSE-2.0).
  ```
- **思源宋體**：`© 2017-2024 Adobe (http://www.adobe.com/).`
- **芫荽**：`Copyright 2025 The Iansui Project Authors (https://github.com/ButTaiwan/iansui)`

## 預覽圖

`swift scripts/render-font-previews.swift <三個開源字型檔所在資料夾>` 產生 `DaysCam/Assets.xcassets/FontPreviews/<fontID>.imageset`（17pt、@2x／@3x 模板圖）。開源字型直接從檔案建立（先比對 SHA-256），不會畫到 Mac 上安裝的同名字型；系統字型經 CoreText 比對。取得的字型名稱不符 PRD-0.3 §4.1 時以非零狀態結束。

預覽圖高度不一（@2x 約 38～54px，依字型的行高），TASK-34 顯示時以固定高度的框置中或以基線對齊，不要直接用圖片原始高度排版。
