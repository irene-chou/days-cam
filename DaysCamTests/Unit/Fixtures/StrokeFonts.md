# TASK-80 outline fixtures

These are outline-preserving subsets of the downloaded Chinese fonts in
`FontCatalog` (font-assets tag `v2`). The original licenses are adjacent.
Only names were changed to `Task80Iansui`, `Task80Thin`, and `Task80Serif`,
including the reserved names of ChenYuluoyan. No contours were simplified.
The fixtures are test resources, never registered by the product.

Original assets and SHA-256:

- `iansui/Iansui-Regular.ttf`: `7f1aa62e9dcbf40d0ce41a5d3f1e5ea602e66c295778ac6fefb6b84d8ed08bd5`
- `chenyuluoyan/ChenYuluoyan-2.0-Thin.ttf`: see `FontCatalog.chenyuluoyanAsset`
- `noto-serif-tc/NotoSerifTC-Bold.otf`: see `FontCatalog.notoSerifAsset`

Subset with FontTools `pyftsubset`, retaining all names and the characters:

```sh
pyftsubset <original-font> --text='0 8 日 囍 & fi A 第10天' \
  --output-file=<fixture> --name-IDs='*' --name-legacy --name-languages='*'
```

Rename name IDs 1, 3, 4, 6, 16 to the test family and IDs 2, 17 to `Regular`.
For CFF, also rename fontNames, FamilyName and FullName. Keep the original
copyright and license name records.
