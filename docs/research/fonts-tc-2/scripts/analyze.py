"""Analyze font files: names, version, fsType, weight, 4808 coverage, overlay chars, size, sha256.

Usage: python -I analyze.py <chars4808.txt> <out.json> <font files...>
"""
import hashlib
import json
import os
import sys

from fontTools.ttLib import TTCollection, TTFont

OVERLAY = "0123456789.第天歲個月年又週尚未開始 　我的紀錄"


def name(font, nid):
    rec = font["name"].getName(nid, 3, 1, 0x409) or font["name"].getName(nid, 1, 0, 0)
    if rec is None:
        for r in font["name"].names:
            if r.nameID == nid:
                rec = r
                break
    return rec.toUnicode() if rec else None


def zh_name(font, nid):
    for r in font["name"].names:
        if r.nameID == nid and r.platformID == 3 and r.langID in (0x404, 0xC04, 0x1404, 0x804):
            return r.toUnicode()
    return None


def analyze_face(font, chars):
    cmap = font.getBestCmap() or {}
    missing = [c for c in chars if ord(c) not in cmap]
    ov_missing = [c for c in OVERLAY if ord(c) not in cmap]
    os2 = font["OS/2"] if "OS/2" in font else None
    return {
        "family": name(font, 16) or name(font, 1),
        "subfamily": name(font, 17) or name(font, 2),
        "zh_family": zh_name(font, 16) or zh_name(font, 1),
        "postscript": name(font, 6),
        "version": name(font, 5),
        "copyright": (name(font, 0) or "")[:200],
        "license": (name(font, 13) or "")[:200],
        "license_url": name(font, 14),
        "fsType": os2.fsType if os2 else None,
        "weightClass": os2.usWeightClass if os2 else None,
        "cmap_size": len(cmap),
        "cov4808": len(chars) - len(missing),
        "missing4808": "".join(missing[:40]),
        "overlay_missing": "".join(ov_missing),
    }


def main():
    chars = [l.strip() for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
    out = []
    for path in sys.argv[3:]:
        data = open(path, "rb").read()
        entry = {
            "path": path,
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "faces": [],
        }
        try:
            if path.lower().endswith((".ttc", ".otc")):
                coll = TTCollection(path, lazy=True)
                fonts = coll.fonts
            else:
                fonts = [TTFont(path, lazy=True)]
            for f in fonts:
                entry["faces"].append(analyze_face(f, chars))
        except Exception as exc:  # noqa: BLE001
            entry["error"] = repr(exc)
        out.append(entry)
        print(os.path.basename(path), entry.get("error") or [
            (fc["postscript"], fc["cov4808"], fc["overlay_missing"], fc["fsType"]) for fc in entry["faces"]
        ], flush=True)
    json.dump(out, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
