#!/usr/bin/env python3
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
    adres_path = ROOT / "data_out" / "tesisler_adres.json"
    if not adres_path.is_file():
        adres_path = ROOT / "tesisler_adres.json"
    overlay: dict[str, dict] = {}
    if adres_path.is_file():
        od = json.loads(adres_path.read_text(encoding="utf-8"))
        for it in od.get("items") or od.get("tesisler") or []:
            if not isinstance(it, dict):
                continue
            key = f"{fold(str(it.get('il') or ''))}|{fold(str(it.get('isim') or ''))}"
            overlay[key] = it
        print("overlay", adres_path, "n=", len(overlay))
    else:
        print("overlay yok")

    for i, t in enumerate(master["tesisler"]):
        if not (isinstance(t.get("adres"), (int, float)) or t.get("tip") is None):
            continue
        key = f"{fold(str(t.get('il') or ''))}|{fold(str(t.get('isim') or ''))}"
        ov = overlay.get(key)
        print(f"[{i}] {t.get('il')} | {t.get('isim')}")
        print(
            "  master adres=",
            t.get("adres"),
            "lat=",
            t.get("latitude"),
            "lon=",
            t.get("longitude"),
            "tip=",
            t.get("tip"),
        )
        if ov:
            print(
                "  overlay=",
                {
                    x: ov.get(x)
                    for x in ("adres", "ilce", "formatted_address", "telefon")
                    if ov.get(x)
                },
            )
        else:
            print("  overlay=YOK")


if __name__ == "__main__":
    main()
