#!/usr/bin/env python3
"""Master'daki net sema hatalarini detayli goster."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / "master_database_updated.json").read_text(encoding="utf-8"))

print("=== ust anahtar tipleri ===")
for k, v in data.items():
    print(f"  {k}: {type(v).__name__} len={len(v) if hasattr(v, '__len__') else '-'}")

sosyal = data.get("sosyal")
print("\n=== sosyal ornek ===")
if isinstance(sosyal, list) and sosyal:
    print(json.dumps(sosyal[0], ensure_ascii=False, indent=2)[:800])
    print("sosyal keys sample:", sorted({kk for x in sosyal[:50] if isinstance(x, dict) for kk in x}))
elif isinstance(sosyal, dict):
    print("dict keys", list(sosyal.keys())[:20])
else:
    print(type(sosyal), sosyal)

print("\n=== adres float olan tesisler ===")
for i, t in enumerate(data["tesisler"]):
    if isinstance(t.get("adres"), float) or isinstance(t.get("adres"), int):
        print(f"[{i}] {t.get('il')} | {t.get('isim')} | adres={t.get('adres')!r} tip={t.get('tip')!r}")
        print("    full keys:", {k: type(v).__name__ for k, v in t.items()})

print("\n=== tip null ===")
for i, t in enumerate(data["tesisler"]):
    if t.get("tip") is None:
        print(f"[{i}] {t.get('il')} | {t.get('isim')} | {json.dumps(t, ensure_ascii=False)[:300]}")

print("\n=== kullanici alani ===")
for i, t in enumerate(data["tesisler"]):
    if "kullanıcı" in t or "kullanici" in t:
        print(f"[{i}] {t.get('il')} | {t.get('isim')} | kullanici={t.get('kullanıcı')!r}")

print("\n=== adres null ornek (ilk 10) ===")
n = 0
for i, t in enumerate(data["tesisler"]):
    if t.get("adres") is None:
        print(f"[{i}] {t.get('il')} | {t.get('isim')}")
        n += 1
        if n >= 10:
            break

print("\n=== duplicate tesis detay ===")
from collections import defaultdict

def fold(s):
    t = (s or "").strip().casefold()
    for a, b in (("ı", "i"), ("i̇", "i"), ("ş", "s"), ("ğ", "g"), ("ü", "u"), ("ö", "o"), ("ç", "c")):
        t = t.replace(a, b)
    return " ".join(t.split())

dups = defaultdict(list)
for i, t in enumerate(data["tesisler"]):
    dups[f"{fold(t.get('il'))}|{fold(t.get('isim'))}"].append(i)
for k, idxs in dups.items():
    if len(idxs) > 1:
        for i in idxs:
            t = data["tesisler"][i]
            print(f"  [{i}] lat={t.get('latitude')} lon={t.get('longitude')} adres={t.get('adres')!r} tip={t.get('tip')!r}")
        print("---")
