#!/usr/bin/env python3
"""Onaylanmış önizleme kayıtlarını master'daki `tesisler` dizisinin sonuna ekle.

Mevcut metne dokunmaz: yalnızca dizinin kapanışından önce yeni kayıtlar eklenir.
Kullanım: python scripts/apply_preview_additions.py data_out/preview_additions.json [hedef.json]
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT.parent / "rotalink-data" / "master_database_updated.json"
FIELDS = ("isim", "tip", "il", "adres", "telefon", "latitude", "longitude")


def main() -> None:
    global MASTER
    src = Path(sys.argv[1])
    if len(sys.argv) > 2:
        MASTER = Path(sys.argv[2])
    items = json.loads(src.read_text(encoding="utf-8"))
    for it in items:
        if tuple(it.keys()) != FIELDS:
            raise SystemExit(f"Alan yapısı farklı: {it}")
        if it["latitude"] is None or it["longitude"] is None:
            raise SystemExit(f"Koordinatsız kayıt: {it['isim']}")

    raw = MASTER.read_bytes()
    txt = raw.decode("utf-8")
    nl = "\r\n" if "\r\n" in txt[:2000] else "\n"
    before = json.loads(txt)
    n0 = len(before["tesisler"])
    existing = {(t.get("il"), t.get("isim")) for t in before["tesisler"]}
    already = [it["isim"] for it in items if (it["il"], it["isim"]) in existing]
    if already:
        raise SystemExit(f"{len(already)} kayıt zaten master'da (ör. {already[0]}); hiçbir şey yazılmadı")

    start = txt.index('"tesisler": [')
    close = txt.index(f"{nl}  ],", start)
    last_obj_end = txt.rindex("}", start, close)
    if txt[last_obj_end + 1:close].strip():
        raise SystemExit("Beklenmeyen dizi sonu")

    chunks = []
    for it in items:
        body = json.dumps(it, ensure_ascii=False, indent=2)
        chunks.append(nl.join("    " + line for line in body.split("\n")))
    insert = "," + nl + ("," + nl).join(chunks)
    new_txt = txt[: last_obj_end + 1] + insert + txt[last_obj_end + 1:]

    after = json.loads(new_txt)
    assert new_txt.startswith(txt[: last_obj_end + 1])
    assert new_txt.endswith(txt[last_obj_end + 1:])
    assert after["tesisler"][:n0] == before["tesisler"]
    assert after["tesisler"][n0:] == items
    for k in before:
        if k != "tesisler":
            assert after[k] == before[k], k

    backup = ROOT / "data_out" / f"before_apply_{MASTER.parent.parent.name}_{MASTER.name}"
    shutil.copyfile(MASTER, backup)
    MASTER.write_bytes(new_txt.encode("utf-8"))
    print(f"Yedek: {backup}")
    print(f"tesisler: {n0} -> {len(after['tesisler'])} (+{len(items)})")


if __name__ == "__main__":
    main()
