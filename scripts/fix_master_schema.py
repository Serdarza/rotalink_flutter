#!/usr/bin/env python3
"""master_database_updated.json sema hatalarini duzelt."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "master_database_updated.json"
OVERLAY = ROOT / "data_out" / "tesisler_adres.json"


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
    data = json.loads(MASTER.read_text(encoding="utf-8"))
    overlay: dict[str, dict] = {}
    if OVERLAY.is_file():
        od = json.loads(OVERLAY.read_text(encoding="utf-8"))
        for it in od.get("items") or od.get("tesisler") or []:
            if isinstance(it, dict):
                key = f"{fold(str(it.get('il') or ''))}|{fold(str(it.get('isim') or ''))}"
                overlay[key] = it

    fixes: list[str] = []
    for i, t in enumerate(data.get("tesisler") or []):
        if not isinstance(t, dict):
            continue
        key = f"{fold(str(t.get('il') or ''))}|{fold(str(t.get('isim') or ''))}"
        ov = overlay.get(key) or {}
        name = f"{t.get('il')} | {t.get('isim')}"

        # 1) adres sayi olamaz
        if isinstance(t.get("adres"), (int, float)):
            old = t.get("adres")
            new_adres = str(ov.get("adres") or "").strip() or None
            t["adres"] = new_adres
            if ov.get("ilce") and not t.get("ilce"):
                t["ilce"] = ov["ilce"]
            fixes.append(
                f"tesisler[{i}] {name}: adres {old!r} (float) -> {new_adres!r}"
            )

        # 2) tip null olamaz (string bekleniyor)
        if t.get("tip") is None:
            tip = "Sosyal Tesis" if "sosyal" in fold(str(t.get("isim") or "")) else ""
            t["tip"] = tip
            # adres de null ise overlay doldur
            if t.get("adres") is None and ov.get("adres"):
                t["adres"] = ov["adres"]
                if ov.get("ilce") and not t.get("ilce"):
                    t["ilce"] = ov["ilce"]
            fixes.append(f"tesisler[{i}] {name}: tip null -> {tip!r}")

        # 3) telefon sayi ise stringe cevir
        if isinstance(t.get("telefon"), (int, float)):
            old = t["telefon"]
            t["telefon"] = str(int(old)) if float(old).is_integer() else str(old)
            fixes.append(f"tesisler[{i}] {name}: telefon {old!r} -> {t['telefon']!r}")

        # 4) latitude/longitude string ise float
        for field in ("latitude", "longitude", "enlem", "boylam"):
            if field not in t:
                continue
            v = t[field]
            if isinstance(v, str):
                try:
                    t[field] = float(v.replace(",", ".").strip())
                    fixes.append(f"tesisler[{i}] {name}: {field} str -> float")
                except ValueError:
                    pass

    # Sosyal / gezi / yemek: adres float vs
    for section in ("sosyal", "geziler", "yemekler"):
        for i, t in enumerate(data.get(section) or []):
            if not isinstance(t, dict):
                continue
            name = f"{t.get('il')} | {t.get('isim')}"
            if isinstance(t.get("adres"), (int, float)):
                t["adres"] = None
                fixes.append(f"{section}[{i}] {name}: adres sayi -> null")
            if isinstance(t.get("aciklama"), (int, float)):
                t["aciklama"] = str(t["aciklama"])
                fixes.append(f"{section}[{i}] {name}: aciklama sayi -> str")

    MASTER.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Duzeltme sayisi: {len(fixes)}")
    for line in fixes:
        print("-", line)


if __name__ == "__main__":
    main()
