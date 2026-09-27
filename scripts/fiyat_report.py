#!/usr/bin/env python3
"""fiyat_build.py çıktısından A–F raporunu üret.

Girdi : data_out/fiyat/report_records.json, fiyatlar_preview.json, rotalink-data/fiyatlar.json, master
Çıktı : data_out/fiyat/FIYAT_RAPORU.md
  A: resmî güncel fiyatla güncellendi (fiyatlar.json'a yazıldı)
  B: resmî kaynak var ama tarih belirsiz / güncel değil (yazılmadı)
  C: resmî kaynakta fiyat bulunamadı
  D: tesis bulundu ama tarife yayımlanmıyor
  E: PDF/Excel/Word/görselden işlenenler (A ve B içinden)
  F: teyit gerekli (mevcut kaydı olup doğrulanamayanlar + görselden elle okunup OCR'la doğrulanamayanlar + B)
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data_out" / "fiyat"
DATA = ROOT.parent / "rotalink-data"


def main() -> None:
    recs = json.loads((OUT / "report_records.json").read_text(encoding="utf-8"))
    master = json.loads((DATA / "master_database_updated.json").read_text(encoding="utf-8"))["tesisler"]
    preview = json.loads((OUT / "fiyatlar_preview.json").read_text(encoding="utf-8"))["tesisler"]
    by_key: dict = {}
    order = {"A": 0, "B": 1, "D": 2, "C": 3}
    for r in recs:
        k = (r["il"], r["isim"])
        if k not in by_key or order[r["durum"]] < order[by_key[k]["durum"]]:
            by_key[k] = r
    groups = {g: [] for g in "ABCDEF"}
    for k, r in sorted(by_key.items(), key=lambda x: (x[0][0], x[0][1])):
        groups[r["durum"]].append(r)
        if r["durum"] in ("A", "B") and (r.get("kaynak_turu") in ("pdf", "gorsel", "word", "excel")):
            groups["E"].append(r)
        if r["durum"] == "B" or r.get("kontrol") == "gorsel_elle":
            groups["F"].append({**r, "f_neden": r.get("neden") or "görselden elle okundu, OCR ile doğrulanamadı"})
    teyit = [e for e in preview if (e.get("tarife") or {}).get("dogrulama") == "teyit_gerekli"]
    for e in teyit:
        groups["F"].append({"il": e["il"], "isim": e["isim"], "kaynak": e.get("kaynak") or "(kaynak yok)",
                            "f_neden": "fiyatlar.json'daki mevcut değer korundu; resmî kaynakta güncel olarak doğrulanamadı"})
    researched = set(by_key)
    not_researched = [t for t in master if (t["il"], t["isim"]) not in researched]
    tip_cnt = Counter(t.get("tip") for t in not_researched)

    L = ["# Resmî fiyat araştırması raporu (kontrol tarihi 27.09.2026)", ""]
    L.append(f"- Veritabanındaki tesis: **{len(master)}**")
    L.append(f"- Araştırılıp sınıflanan tesis: **{len(by_key)}**")
    L.append(f"- **A — resmî güncel fiyatla güncellenen/eklenen: {len(groups['A'])}**")
    L.append(f"- B — resmî kaynak var, tarih belirsiz/güncel değil (yazılmadı): {len(groups['B'])}")
    L.append(f"- C — resmî kaynakta fiyat bulunamadı: {len(groups['C'])}")
    L.append(f"- D — tesis bulundu, tarife yayımlanmıyor: {len(groups['D'])}")
    L.append(f"- E — PDF/Excel/Word/görselden işlenen (A+B içinden): {len(groups['E'])}")
    L.append(f"- F — teyit gerekli: {len(groups['F'])}")
    L.append(f"- Hiç sınıflanamayan (araştırma kapsamı dışında kalan): {len(not_researched)}")
    L.append("")
    titles = {"A": "A — Resmî güncel fiyatla güncellenen", "B": "B — Resmî kaynak, tarih belirsiz / güncel değil",
              "C": "C — Resmî kaynakta fiyat yok", "D": "D — Tarife yayımlanmıyor",
              "E": "E — PDF/Excel/Word/görselden işlenen", "F": "F — Teyit gerekli"}
    for g in "ABCDEF":
        L.append(f"## {titles[g]} ({len(groups[g])})")
        L.append("")
        for r in groups[g]:
            extra = ""
            if g in ("B", "C", "D"):
                extra = f" — {r.get('neden', '')}"
            elif g == "E":
                extra = f" — {r.get('kaynak_turu')}"
            elif g == "F":
                extra = f" — {r.get('f_neden', '')}"
            L.append(f"- {r['il']} | {r['isim']} | {r.get('kaynak', '')}{extra}")
        L.append("")
    L.append(f"## Sınıflanamayanlar ({len(not_researched)})")
    L.append("")
    for tip, c in tip_cnt.most_common():
        L.append(f"- {tip}: {c}")
    L.append("")
    for t in sorted(not_researched, key=lambda t: (str(t["il"]), t["isim"])):
        L.append(f"- {t['il']} | {t['isim']} | {t.get('tip')}")
    (OUT / "FIYAT_RAPORU.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print({g: len(v) for g, v in groups.items()}, "sınıflanamayan", len(not_researched))


if __name__ == "__main__":
    main()
