#!/usr/bin/env python3
"""Öğretmenevi/polisevi/DHMİ dışındaki tesisleri kurum gruplarına ayır (araştırma listeleri).

Çıktı: data_out/fiyat/groups/<grup>.json  (il, isim, tip, adres, telefon)
       data_out/fiyat/groups/ogretmenevi_sitesiz.json  (MEB sitesi taranmamış öğretmenevleri)
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data_out" / "fiyat"
sys.path.insert(0, str(ROOT / "scripts"))
from preview_missing_tesisler import fold_tr  # noqa: E402

MASTER = ROOT.parent / "rotalink-data" / "master_database_updated.json"

RULES = [
    ("dhmi", r"dhmi|havaliman|havacilik akademisi"),
    ("polisevi", r"polis|pol evi|emniyet"),
    ("ogretmenevi", r"ogretmen|ogretmenevi|aso mudurlugu"),
    ("orduevi", r"orduevi|ordu evi|askeri|kisla|gazino|jandarma|msb|garnizon|astsubay|subay"),
    ("uygulama_oteli", r"uygulama oteli|uygulama otel|okul oteli|meslek lisesi|mtal|otelcilik"),
    ("universite", r"universite|universitesi|odtu|metu"),
    ("dsi", r"\bdsi\b|devlet su isleri"),
    ("karayollari", r"karayol"),
    ("meteoroloji", r"meteoroloji|\bmgm\b"),
    ("orman", r"orman"),
    ("tcdd_ptt_enerji", r"tcdd|demiryol|\bptt\b|tedas|teias|euas|medas|tulomsas|tuvasas|telekom|\bttk\b|eti maden|\bmta\b|\bmke\b|seker fabrika"),
    ("saglik_adalet", r"saglik|hekimevi|hastane|adalet|hakimevi|adliye|ceza infaz"),
    ("maliye_tarim_cevre", r"maliye|defterdar|vergi|gumruk|tarim|tigem|gida|cevre|sehircilik|tapu|sgk|nufus"),
]


def main() -> None:
    master = json.loads(MASTER.read_text(encoding="utf-8"))["tesisler"]
    host_db = json.loads((OUT / "host_db.json").read_text(encoding="utf-8"))
    crawled = {(r["il"], r["isim"]) for recs in host_db.values() for r in recs}
    groups: dict[str, list] = {}
    for t in master:
        key = fold_tr(f"{t.get('tip') or ''} {t['isim']}").lower()
        g = next((name for name, rx in RULES if re.search(rx, key)), "diger")
        rec = {k: t.get(k) for k in ("il", "isim", "tip", "adres", "telefon")}
        if g == "ogretmenevi" and (t["il"], t["isim"]) not in crawled:
            groups.setdefault("ogretmenevi_sitesiz", []).append(rec)
        groups.setdefault(g, []).append(rec)
    gdir = OUT / "groups"
    gdir.mkdir(exist_ok=True)
    for g, recs in groups.items():
        recs.sort(key=lambda r: (fold_tr(str(r["il"])), fold_tr(r["isim"])))
        (gdir / f"{g}.json").write_text(json.dumps(recs, ensure_ascii=False, indent=1), encoding="utf-8")
    print(Counter({g: len(v) for g, v in groups.items()}))


if __name__ == "__main__":
    main()
