#!/usr/bin/env python3
"""tesisler_adres.json ilçe alanını temizle: mahalle/sokak yok, sadece ilçe.

Çıktı: data_out/tesisler_adres.json (üzerine yazar)
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data_out" / "tesisler_adres.json"
MASTER = ROOT / "master_database_updated.json"
PROGRESS = ROOT / "data_out" / "tesis_adres_progress.json"


def norm_space(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


def norm_key(s: str) -> str:
    s = norm_space(s).casefold()
    return s.translate(str.maketrans("çğıöşüâîû", "cgiosuaiu"))


NAME_STRIP = (
    r"ve\s+aso",
    r"ve\s+akşam\s+sanat\s+okulu",
    r"öğretmenevi",
    r"ogretmenevi",
    r"orduevi",
    r"polisevi",
    r"polis\s+evi",
    r"misafirhanesi",
    r"misafirhane",
    r"konukevi",
    r"konuk\s+evi",
    r"uygulama\s+oteli",
)


def ilce_from_isim(isim: str, il: str) -> str:
    n = norm_space(isim)
    for suf in NAME_STRIP:
        n = re.sub(rf"(?i)\s*{suf}\s*$", "", n).strip(" -–,")
    n = norm_space(re.sub(r"\s*\(.*?\)\s*", " ", n))
    if not n:
        return ""
    if norm_key(n) == norm_key(il):
        return "Merkez"
    tokens = n.split()
    if not tokens:
        return ""
    first = tokens[0]
    if norm_key(first) == norm_key(il):
        return "Merkez"
    low = isim.casefold()
    if any(x in low for x in ("öğretmenevi", "ogretmenevi", "polisevi", "orduevi")):
        return first
    return first if len(tokens) <= 2 else " ".join(tokens[:2])


def ilce_from_adres(adres: str, il: str) -> str:
    a = norm_space(adres)
    if not a:
        return ""
    il_n = norm_space(il)
    # Çınarcık/Yalova
    m = re.search(
        rf"([A-Za-zÇĞİÖŞÜçğıöşü\-]{{2,40}})\s*/\s*{re.escape(il_n)}\b",
        a,
        re.I,
    )
    if m:
        cand = norm_space(m.group(1))
        cl = cand.casefold()
        if not any(x in cl for x in ("mah", "sk", "sok", "cad", "no", "blv")):
            if norm_key(cand) != norm_key(il_n):
                parts = re.split(r"[\s,]+", cand)
                return parts[-1] if parts else cand
    m2 = re.search(rf"(Merkez)\s*[-–]\s*{re.escape(il_n)}\b", a, re.I)
    if m2:
        return "Merkez"
    m3 = re.search(
        rf",\s*([A-Za-zÇĞİÖŞÜçğıöşü\-]{{3,30}})\s*,\s*{re.escape(il_n)}\b",
        a,
        re.I,
    )
    if m3:
        cand = norm_space(m3.group(1))
        if norm_key(cand) != norm_key(il_n) and "mah" not in cand.casefold():
            return cand
    return ""


def is_mahalle_or_street(ilce: str) -> bool:
    low = ilce.casefold()
    if not low:
        return True
    bad = (
        "mahallesi",
        " mah.",
        "mah ",
        "sokak",
        "sokağı",
        "caddesi",
        "bulvar",
        "bulvarı",
        "belediye sınır",
        "no:",
        "sk.",
        "cd.",
        "blv",
    )
    if any(b in low for b in bad):
        return True
    # "... Mahallesi" exact end
    if low.endswith(" mahallesi") or low.endswith(" mahalle"):
        return True
    return False


def looks_like_ilce(ilce: str, il: str) -> bool:
    if not ilce or is_mahalle_or_street(ilce):
        return False
    if len(ilce) > 32:
        return False
    if norm_key(ilce) == norm_key(il):
        return True  # will map to Merkez
    # too many words → not a district name
    if len(ilce.split()) > 3:
        return False
    return True


def clean_ilce(ilce: str, isim: str, il: str, adres: str) -> str:
    ilce = norm_space(ilce)
    # İl adı ile aynıysa Merkez
    if ilce and norm_key(ilce) == norm_key(il):
        return "Merkez"

    if looks_like_ilce(ilce, il):
        # Yenimahalle gibi gerçek ilçe adlarını koru
        return ilce

    # Mahalle/sokak → yeniden üret
    for cand in (
        ilce_from_isim(isim, il),
        ilce_from_adres(adres, il),
    ):
        cand = norm_space(cand)
        if cand and looks_like_ilce(cand, il):
            if norm_key(cand) == norm_key(il):
                return "Merkez"
            return cand

    return "Merkez"


def main() -> None:
    src = OUT if OUT.is_file() else None
    if src is None:
        raise SystemExit("tesisler_adres.json yok")

    data = json.loads(src.read_text(encoding="utf-8"))
    items = data.get("items") or []
    master_by = {}
    if MASTER.is_file():
        md = json.loads(MASTER.read_text(encoding="utf-8"))
        for t in md.get("tesisler") or []:
            if isinstance(t, dict):
                master_by[(norm_space(str(t.get("il") or "")), norm_space(str(t.get("isim") or "")))] = t

    out_items = []
    fixed = 0
    for x in items:
        if not isinstance(x, dict):
            continue
        il = norm_space(str(x.get("il") or ""))
        isim = norm_space(str(x.get("isim") or ""))
        adres = norm_space(str(x.get("adres") or ""))
        # Adres tercihen master (orijinal)
        m = master_by.get((il, isim))
        if m:
            ma = norm_space(str(m.get("adres") or ""))
            if ma and not ma.replace(".", "", 1).isdigit():
                adres = ma
        old = norm_space(str(x.get("ilce") or ""))
        new = clean_ilce(old, isim, il, adres)
        if new != old:
            fixed += 1
        out_items.append(
            {
                "il": il,
                "isim": isim,
                "adres": adres,
                "ilce": new,
            }
        )

    payload = {
        "not": "il+isim eslesmesi. Liste altinda sadece ilce (mahalle yok).",
        "items": out_items,
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    # safety
    if re.search(r"^\s*//", text, re.M):
        raise SystemExit("Yorum satiri uretildi — iptal")
    json.loads(text)
    OUT.write_text(text + "\n", encoding="utf-8")

    mahalle_left = sum(
        1
        for x in out_items
        if is_mahalle_or_street(x["ilce"]) or "mahallesi" in x["ilce"].casefold()
    )
    print(f"Yazildi: {OUT}")
    print(f"  kayit={len(out_items)}  ilce_duzeltilen={fixed}  mahalle_kalan={mahalle_left}")


if __name__ == "__main__":
    main()
