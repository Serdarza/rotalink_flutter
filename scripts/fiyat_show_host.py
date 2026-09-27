#!/usr/bin/env python3
"""Bir hostun taranmış resmi sayfalarını tam metin + tablo + ek metni ile göster.

Kullanım: python scripts/fiyat_show_host.py <host> [<host> ...]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data_out" / "fiyat"


def main() -> None:
    args = sys.argv[1:]
    if args and args[0] == "--out":
        sys.stdout = open(args[1], "w", encoding="utf-8")
        args = args[2:]
    else:
        sys.stdout.reconfigure(encoding="utf-8")
    pages = {}
    for pf in sorted(OUT.glob("*_pages.json")):
        pages.update(json.loads(pf.read_text(encoding="utf-8")))
    host_db = json.loads((OUT / "host_db.json").read_text(encoding="utf-8"))
    for host in args:
        v = pages.get(host)
        print(f"########## {host}")
        print("DB:", json.dumps(host_db.get(host, []), ensure_ascii=False))
        if not v:
            print("  (tarama yok)")
            continue
        for p in v["pages"]:
            print(f"--- SAYFA {p['url']}\nBAŞLIK: {p['title']}\nTARİHLER: {p['dates']}\nMETİN: {p['text']}")
            for t in p["tables"]:
                print("TABLO:")
                for r in t:
                    print("   ", " | ".join(r))
            for a in p["attachments"]:
                print(f"EK: {a['url']} [{a.get('file')}]")
                if a.get("file"):
                    tp = OUT / "files" / (a["file"] + ".txt")
                    if tp.is_file():
                        print("   >>", tp.read_text(encoding="utf-8")[:3000].replace("\n", "\n   >> "))
        for a in v.get("direct_attachments", []):
            print(f"DOGRUDAN_EK: {a['text']} -> {a['url']} [{a.get('file')}]")
            if a.get("file"):
                tp = OUT / "files" / (a["file"] + ".txt")
                if tp.is_file():
                    print("   >>", tp.read_text(encoding="utf-8")[:3000].replace("\n", "\n   >> "))
        print()


if __name__ == "__main__":
    main()
