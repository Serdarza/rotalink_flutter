#!/usr/bin/env python3
"""Öğretmenevi sitelerini veritabanı kayıtlarıyla eşle ve okuma paketleri üret.

Çıktı: data_out/fiyat/host_db.json, data_out/fiyat/batches/batch_XX.txt
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data_out" / "fiyat"
MASTER = ROOT.parent / "rotalink-data" / "master_database_updated.json"
sys.path.insert(0, str(ROOT / "scripts"))
from preview_missing_tesisler import MRec, Rec, category, compare  # noqa: E402

BOILER = re.compile(r"(Beğen \|.*$)|(Hata Bildir.*$)", re.S)


def clean_text(t: str) -> str:
    t = re.sub(r"^.*?(Duyurular Arşiv|T\.C\. M[İI]LL[ÎI] E[ĞG][İI]T[İI]M BAKANLI[ĞG]I)", "", t, count=1, flags=re.S | re.I)
    t = BOILER.sub("", t)
    return t.strip()


def main() -> None:
    sites = json.loads((OUT / "meb_sites.json").read_text(encoding="utf-8"))
    pages = json.loads((OUT / "meb_pages.json").read_text(encoding="utf-8"))
    master = json.loads(MASTER.read_text(encoding="utf-8"))["tesisler"]
    ms = [MRec(i, t) for i, t in enumerate(master) if category(f"{t.get('isim','')} {t.get('tip') or ''}") == "ogretmenevi"]
    by_il = {}
    for m in ms:
        by_il.setdefault(m.il, []).append(m)

    host_db: dict[str, list[dict]] = {}
    for s in sites:
        if not s["host"]:
            continue
        lst = host_db.setdefault(s["host"], [])
        if s["kaynak"] == "db":
            key = {"il": s["il"], "isim": s["isim"]}
            if key not in lst:
                lst.append(key)
    for s in sites:
        if not s["host"] or s["kaynak"] != "meb_liste" or host_db[s["host"]]:
            continue
        r = Rec("meb", "", s["il"].title() if s["il"].isupper() else s["il"], s["ilce"], s["isim"], s["tel"], "", "", "Öğretmenevi", None, None, {})
        from preview_missing_tesisler import build_il_map, map_il
        il = map_il(s["il"], build_il_map(list(by_il)))
        for m in by_il.get(il, []):
            r.il = il
            res = compare(r, m)
            if res and res[0] == "match":
                host_db[s["host"]].append({"il": m.il, "isim": m.isim})
                break
    (OUT / "host_db.json").write_text(json.dumps(host_db, ensure_ascii=False, indent=1), encoding="utf-8")
    print("host", len(host_db), "db eşleşen host", sum(1 for v in host_db.values() if v))

    bdir = OUT / "batches"
    bdir.mkdir(exist_ok=True)
    blocks = []
    for host in sorted(pages):
        v = pages[host]
        seen_ids = set()
        pg_blocks = []
        for p in v["pages"]:
            blob = p["title"] + " " + p.get("link_text", "") + " " + p["text"][:3000]
            if "2026" not in blob:
                continue
            pid = re.search(r"_(\d+)\.html", p["url"])
            pid = pid.group(1) if pid else p["url"]
            if pid in seen_ids:
                continue
            seen_ids.add(pid)
            tbls = [t for t in p["tables"] if len(t) >= 2]
            money = re.findall(r"\d[\d.]*,\d{2}\s*(?:TL|₺)|\d{3,5}\s*(?:TL|₺)", p["text"])
            atts = [a for a in p["attachments"] if a.get("file")]
            if not tbls and len(money) < 2 and not atts:
                continue
            b = [f"--- SAYFA: {p['url']}", f"    BAŞLIK: {p['title'][:150]}", f"    METİN: {clean_text(p['text'])[:2200]}"]
            for t in tbls[:3]:
                b.append("    TABLO:")
                prev = None
                for row in t[:25]:
                    dedup = []
                    for c in row:
                        if not dedup or dedup[-1] != c:
                            dedup.append(c)
                    line = " | ".join(dedup)
                    if line != prev:
                        b.append("      " + line[:400])
                    prev = line
            for a in atts[:8]:
                b.append(f"    EK: {a['url']}  [{a['file']}]")
            pg_blocks.append("\n".join(b))
        direct = [a for a in v["direct_attachments"] if a.get("file")]
        if not pg_blocks and not direct:
            continue
        head = f"########## HOST: {host}\n    DB: {json.dumps(host_db.get(host, []), ensure_ascii=False)}"
        dl = [f"    DOGRUDAN_EK: {a['text'][:80]} -> {a['url']} [{a['file']}]" for a in direct[:6]]
        blocks.append("\n".join([head] + pg_blocks + dl))
    size = 20
    for i in range(0, len(blocks), size):
        (bdir / f"batch_{i // size + 1:02d}.txt").write_text("\n\n".join(blocks[i:i + size]), encoding="utf-8")
    print("okuma bloğu", len(blocks), "paket", (len(blocks) + size - 1) // size)


if __name__ == "__main__":
    main()
