#!/usr/bin/env python3
"""fiyatlar.json'da olup master'da olmayan tesisleri listeler."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fold(s: str) -> str:
    t = (s or "").strip().casefold()
    for a, b in (
        ("ı", "i"),
        ("i̇", "i"),
        ("ş", "s"),
        ("ğ", "g"),
        ("ü", "u"),
        ("ö", "o"),
        ("ç", "c"),
    ):
        t = t.replace(a, b)
    return " ".join(t.split())


def main() -> None:
    master = json.loads(
        (ROOT / "master_database_updated.json").read_text(encoding="utf-8")
    )
    tesis = list(master.get("tesisler") or master.get("misafirhaneler") or [])
    master_keys: set[str] = set()
    for t in tesis:
        if not isinstance(t, dict):
            continue
        il = fold(str(t.get("il") or ""))
        isim = fold(str(t.get("isim") or t.get("name") or ""))
        master_keys.add(f"{il}|{isim}")

    fiyat = json.loads((ROOT / "fiyatlar.json").read_text(encoding="utf-8"))
    missing: list[tuple[str, str]] = []
    for t in fiyat.get("tesisler") or []:
        if not isinstance(t, dict):
            continue
        il = str(t.get("il") or "").strip()
        isim = str(t.get("isim") or t.get("name") or "").strip()
        if f"{fold(il)}|{fold(isim)}" not in master_keys:
            missing.append((il, isim))

    print(f"fiyatlar: {len(fiyat.get('tesisler') or [])}")
    print(f"master tesis: {len(tesis)}")
    print(f"masterda olmayan: {len(missing)}")
    print("---")
    for il, isim in sorted(missing, key=lambda x: (fold(x[0]), fold(x[1]))):
        print(f"{il} | {isim}")


if __name__ == "__main__":
    main()
