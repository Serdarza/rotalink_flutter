#!/usr/bin/env python3
"""master_database_updated.json yapi / sema denetimi."""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "master_database_updated.json"

EXPECTED_TOP = {
    "tesisler",
    "geziler",
    "yemekler",
    "sosyal_tesisler",
    "not",
    "surum",
    "version",
}

KNOWN_FIELDS = {
    "il",
    "isim",
    "tip",
    "adres",
    "telefon",
    "enlem",
    "boylam",
    "aciklama",
    "web",
    "website",
    "lat",
    "lng",
    "latitude",
    "longitude",
    "email",
    "mail",
    "ilce",
    "ilçe",
    "sehir",
    "şehir",
    "kaynak",
    "not",
    "notes",
    "image_urls",
    "gorseller",
    "görseller",
    "id",
    "place_id",
    "google_place_id",
    "url",
    "fax",
    "faks",
    "kapasite",
    "oda",
    "yildiz",
    "yıldız",
    "puan",
    "rating",
}


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
    raw = MASTER.read_text(encoding="utf-8")
    print(f"dosya: {MASTER} ({MASTER.stat().st_size / 1024 / 1024:.2f} MB)")
    print(f"BOM: {raw.startswith(chr(0xFEFF))}")
    print(f"replacement: {raw.count(chr(0xFFFD))}")
    print(f"combining_dot: {raw.count(chr(0x0307))}")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"JSON PARSE ERROR: {e}")
        return

    if not isinstance(data, dict):
        print(f"KOK tip hatali: {type(data)}")
        return

    print("ust anahtarlar:", sorted(data.keys()))
    unknown_top = set(data.keys()) - EXPECTED_TOP
    if unknown_top:
        print("beklenmeyen ust anahtar:", sorted(unknown_top))

    issues: list[str] = []

    for section in ("tesisler", "geziler", "yemekler", "sosyal_tesisler"):
        arr = data.get(section)
        if arr is None:
            print(f"\n=== {section}: YOK ===")
            continue
        if not isinstance(arr, list):
            issues.append(f"{section}: liste degil ({type(arr).__name__})")
            continue

        print(f"\n=== {section}: {len(arr)} kayit ===")
        key_counter: Counter[str] = Counter()
        type_map: dict[str, Counter[str]] = defaultdict(Counter)
        missing_req = 0
        bad_coord = 0
        empty_name = 0
        non_obj = 0
        dups: dict[str, list[int]] = defaultdict(list)
        weird_values: list[str] = []
        swapped_coord = 0

        for i, item in enumerate(arr):
            if not isinstance(item, dict):
                non_obj += 1
                if non_obj <= 8:
                    issues.append(
                        f"{section}[{i}]: dict degil ({type(item).__name__}) = {item!r}"[:200]
                    )
                continue

            for k, v in item.items():
                key_counter[k] += 1
                type_map[k][type(v).__name__] += 1

            il = str(item.get("il") or "").strip()
            isim = str(item.get("isim") or "").strip()
            if not il or not isim:
                missing_req += 1
                if missing_req <= 12:
                    issues.append(
                        f"{section}[{i}]: zorunlu eksik il={item.get('il')!r} isim={item.get('isim')!r}"
                    )
            if not isim:
                empty_name += 1

            dups[f"{fold(il)}|{fold(isim)}"].append(i)

            lat_raw = item.get("enlem", item.get("lat", item.get("latitude")))
            lng_raw = item.get("boylam", item.get("lng", item.get("longitude")))

            lat_f = lng_f = None
            for label, val in (("enlem", lat_raw), ("boylam", lng_raw)):
                if val is None or val == "":
                    continue
                try:
                    f = float(val)
                except (TypeError, ValueError):
                    bad_coord += 1
                    if bad_coord <= 12:
                        issues.append(
                            f"{section}[{i}] {il}/{isim}: {label} sayi degil: {val!r}"
                        )
                    continue
                if label == "enlem":
                    lat_f = f
                else:
                    lng_f = f

            if lat_f is not None and lng_f is not None:
                # Turkiye bounding box
                ok_lat = 35.5 <= lat_f <= 42.5
                ok_lng = 25.5 <= lng_f <= 45.5
                # swapped?
                if (not ok_lat or not ok_lng) and (
                    35.5 <= lng_f <= 42.5 and 25.5 <= lat_f <= 45.5
                ):
                    swapped_coord += 1
                    if swapped_coord <= 12:
                        issues.append(
                            f"{section}[{i}] {il}/{isim}: KOORDINAT TERS "
                            f"enlem={lat_f} boylam={lng_f}"
                        )
                elif not ok_lat or not ok_lng:
                    bad_coord += 1
                    if bad_coord <= 12:
                        issues.append(
                            f"{section}[{i}] {il}/{isim}: supheli koordinat "
                            f"enlem={lat_f} boylam={lng_f}"
                        )

            for k, v in item.items():
                if isinstance(v, (list, dict)):
                    weird_values.append(f"{section}[{i}].{k}={type(v).__name__}")

            # bos string vs null inconsistency not an error, but null keys?
            for k in list(item.keys()):
                if k is None or str(k).strip() == "":
                    issues.append(f"{section}[{i}]: bos anahtar")

        print("alan frekansi:", key_counter.most_common(25))
        print("karisik / garip tipler:")
        for k, tc in sorted(type_map.items()):
            if len(tc) > 1:
                print(f"  MIXED {k}: {dict(tc)}")
                issues.append(f"{section}: alan '{k}' karisik tip {dict(tc)}")
            elif next(iter(tc)) not in ("str", "int", "float", "bool", "NoneType"):
                print(f"  UNUSUAL {k}: {dict(tc)}")

        print(
            f"non_obj={non_obj} missing_req={missing_req} empty_name={empty_name} "
            f"bad_coord={bad_coord} swapped={swapped_coord}"
        )
        if weird_values:
            print(f"ic ice deger ({len(weird_values)}):", weird_values[:10])
            issues.extend(weird_values[:15])

        real_dups = {k: idxs for k, idxs in dups.items() if len(idxs) > 1 and k != "|"}
        print(f"tam isim+il kopya grubu: {len(real_dups)}")
        for _, idxs in list(sorted(real_dups.items(), key=lambda x: -len(x[1])))[:20]:
            sample = arr[idxs[0]]
            issues.append(
                f"{section} DUPLICATE x{len(idxs)}: "
                f"{sample.get('il')} | {sample.get('isim')} @idxs={idxs[:8]}"
            )

        uncommon = sorted(k for k in key_counter if k not in KNOWN_FIELDS)
        if uncommon:
            print("bilinmeyen alanlar:", uncommon)

    print("\n========== OZET SORUNLAR ==========")
    if not issues:
        print("Ciddi yapisal sorun bulunamadi.")
    else:
        for line in issues[:100]:
            print("-", line)
        if len(issues) > 100:
            print(f"... +{len(issues) - 100} daha")
        print(f"TOPLAM issue satiri: {len(issues)}")


if __name__ == "__main__":
    main()
