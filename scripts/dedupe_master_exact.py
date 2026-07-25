#!/usr/bin/env python3
"""Master'daki ayni il+isim kopyalarini temizle."""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "master_database_updated.json"


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


def quality_tesis(t: dict) -> tuple:
    """Yuksek = daha iyi. Tip isimle uyumluysa bonus."""
    adres = t.get("adres") if isinstance(t.get("adres"), str) else ""
    tip = t.get("tip") if isinstance(t.get("tip"), str) else ""
    tel = t.get("telefon") if isinstance(t.get("telefon"), str) else ""
    isim_f = fold(str(t.get("isim") or ""))
    tip_f = fold(tip)

    tip_bonus = 0
    if "jandarma" in isim_f and ("jandarma" in tip_f or "orduevi" in tip_f or "orduev" in tip_f):
        tip_bonus += 20
    if "teias" in isim_f or "teiaş" in isim_f:
        if "tedas" in tip_f or "teias" in tip_f or "enerji" in tip_f:
            tip_bonus += 20
        if "dsi" in tip_f:
            tip_bonus -= 10
    # Yanlis il/adres kirliligi
    adres_l = adres.casefold()
    if "karaman" in adres_l and fold(str(t.get("il") or "")) == "karabuk":
        tip_bonus -= 30
    if "kutahya" in fold(adres) and fold(str(t.get("il") or "")) == "konya":
        tip_bonus -= 30
    if "universite" in tip_f and "jandarma" in isim_f:
        tip_bonus -= 25

    return (
        tip_bonus,
        len(adres.strip()),
        1 if tel.strip() else 0,
        1 if tip.strip() else 0,
        1 if t.get("ilce") else 0,
    )


def quality_gezi(t: dict) -> tuple:
    acik = t.get("aciklama") if isinstance(t.get("aciklama"), str) else ""
    adres = t.get("adres") if isinstance(t.get("adres"), str) else ""
    isim = str(t.get("isim") or "")
    # Dogru Turkce karakterli isim tercih
    tr_bonus = 1 if any(c in isim for c in "ığüşöçİĞÜŞÖÇ") else 0
    return (len(acik.strip()), len(adres.strip()), tr_bonus)


def dedupe_section(arr: list, *, kind: str) -> tuple[list, list[str]]:
    groups: dict[str, list[int]] = defaultdict(list)
    for i, t in enumerate(arr):
        if not isinstance(t, dict):
            continue
        key = f"{fold(str(t.get('il') or ''))}|{fold(str(t.get('isim') or ''))}"
        groups[key].append(i)

    remove: set[int] = set()
    logs: list[str] = []

    for key, idxs in groups.items():
        if len(idxs) < 2:
            continue
        scored = []
        for i in idxs:
            t = arr[i]
            q = quality_tesis(t) if kind == "tesis" else quality_gezi(t)
            scored.append((q, i))
        scored.sort(reverse=True)
        keep_i = scored[0][1]
        keep = arr[keep_i]

        # Ozel: Bolu Kizik -> Kızık yazimi
        if kind == "gezi" and key == "bolu|kizik yaylasi":
            keep["isim"] = "Kızık Yaylası"
            # Daha uzun aciklama/adres varsa birlestir
            for _, j in scored[1:]:
                other = arr[j]
                oa = other.get("aciklama") or ""
                ka = keep.get("aciklama") or ""
                if len(str(oa)) > len(str(ka)):
                    keep["aciklama"] = oa
                od = other.get("adres") or ""
                kd = keep.get("adres") or ""
                if len(str(od)) > len(str(kd)):
                    keep["adres"] = od

        for _, j in scored[1:]:
            remove.add(j)
            dropped = arr[j]
            logs.append(
                f"{kind}: TUTULDU [{keep_i}] {keep.get('il')} | {keep.get('isim')} "
                f"(tip={keep.get('tip')!r})  |  SILINDI [{j}] tip={dropped.get('tip')!r} "
                f"adres={str(dropped.get('adres') or '')[:60]!r}"
            )

    new_arr = [t for i, t in enumerate(arr) if i not in remove]
    return new_arr, logs


def main() -> None:
    data = json.loads(MASTER.read_text(encoding="utf-8"))
    all_logs: list[str] = []

    before_t = len(data["tesisler"])
    before_g = len(data["geziler"])

    data["tesisler"], logs_t = dedupe_section(data["tesisler"], kind="tesis")
    data["geziler"], logs_g = dedupe_section(data["geziler"], kind="gezi")
    all_logs.extend(logs_t)
    all_logs.extend(logs_g)

    MASTER.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"tesisler: {before_t} -> {len(data['tesisler'])}")
    print(f"geziler:  {before_g} -> {len(data['geziler'])}")
    print("---")
    for line in all_logs:
        print("-", line)


if __name__ == "__main__":
    main()
