#!/usr/bin/env python3
"""Duplicate tesis/gezi detayini goster."""

from __future__ import annotations

import json
from collections import defaultdict
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


def haversine(lat1, lon1, lat2, lon2):
    from math import radians, sin, cos, asin, sqrt

    r = 6371000
    p1, p2 = radians(lat1), radians(lat2)
    dp = radians(lat2 - lat1)
    dl = radians(lon2 - lon1)
    a = sin(dp / 2) ** 2 + cos(p1) * cos(p2) * sin(dl / 2) ** 2
    return 2 * r * asin(sqrt(a))


def score(t: dict) -> int:
    s = 0
    adres = t.get("adres")
    if isinstance(adres, str) and adres.strip():
        s += 10 + min(len(adres.strip()), 80) // 10
    if isinstance(t.get("telefon"), str) and t["telefon"].strip():
        s += 5
    if isinstance(t.get("tip"), str) and t["tip"].strip():
        s += 3
    if isinstance(t.get("ilce"), str) and t["ilce"].strip():
        s += 2
    if t.get("latitude") and t.get("longitude"):
        s += 2
    return s


def main() -> None:
    data = json.loads(
        (ROOT / "master_database_updated.json").read_text(encoding="utf-8")
    )
    for section in ("tesisler", "geziler"):
        arr = data[section]
        dups: dict[str, list[int]] = defaultdict(list)
        for i, t in enumerate(arr):
            k = f"{fold(str(t.get('il') or ''))}|{fold(str(t.get('isim') or ''))}"
            dups[k].append(i)
        print(f"\n===== {section} =====")
        for k, idxs in sorted(dups.items()):
            if len(idxs) < 2:
                continue
            print(f"\n{k}  idxs={idxs}")
            for i in idxs:
                t = arr[i]
                print(
                    f"  [{i}] score={score(t)} tip={t.get('tip')!r} "
                    f"tel={t.get('telefon')!r}"
                )
                print(f"       adres={t.get('adres')!r}")
                print(
                    f"       lat={t.get('latitude')} lon={t.get('longitude')} "
                    f"ilce={t.get('ilce')!r}"
                )
            if len(idxs) == 2:
                a, b = arr[idxs[0]], arr[idxs[1]]
                try:
                    d = haversine(
                        float(a["latitude"]),
                        float(a["longitude"]),
                        float(b["latitude"]),
                        float(b["longitude"]),
                    )
                    print(f"  mesafe={d:.0f} m")
                except Exception as e:
                    print("  mesafe?", e)


if __name__ == "__main__":
    main()
