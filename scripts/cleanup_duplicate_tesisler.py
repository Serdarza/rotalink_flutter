#!/usr/bin/env python3
"""Konaklama tekrarlarını güvenli biçimde raporla/temizle.

Varsayılan yalnızca rapor üretir. --apply verilmedikçe dosyalara dokunmaz.
Resimli kayıt korunur; yalnızca aynı tesise ait olduğu yüksek güvenle belirlenen
resimsiz kayıt silinir. İsim değişiklikleri tüm overlay dosyalarına taşınır.

  python scripts/cleanup_duplicate_tesisler.py --all
  python scripts/cleanup_duplicate_tesisler.py --all --apply
  python scripts/cleanup_duplicate_tesisler.py --cities-prefix B --apply
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "master_database_updated.json"
IMAGES = ROOT / "data_out" / "tesisler_gorseller.json"
ADDRESSES = ROOT / "data_out" / "tesisler_adres.json"
BASELINE = ROOT / "data_out" / "master_database_fixed.json"
REPORT = ROOT / "data_out" / "cleanup_duplicates_report.json"

TR_FOLD = str.maketrans(
    {
        "ı": "i",
        "İ": "i",
        "ş": "s",
        "Ş": "s",
        "ğ": "g",
        "Ğ": "g",
        "ü": "u",
        "Ü": "u",
        "ö": "o",
        "Ö": "o",
        "ç": "c",
        "Ç": "c",
    }
)

STOP = {
    "ve",
    "and",
    "the",
    "of",
    "ile",
    "mudurlugu",
    "mudurluk",
    "directorate",
    "evening",
    "art",
    "school",
    "aso",
    "a",
    "s",
    "o",
}

TOKEN_EQUIV = {
    "hope": "hopa",
    "teachers": "ogretmenev",
    "teacher": "ogretmenev",
    "ogretmenevi": "ogretmenev",
    "ogretmenev": "ogretmenev",
    "hotel": "otel",
    "oteli": "otel",
    "applications": "uygulama",
    "application": "uygulama",
    "guesthouse": "konukev",
    "guest": "konukev",
    "house": "konukev",
    "konukevi": "konukev",
    "misafirhanesi": "misafirhane",
    "facilities": "tesis",
    "facility": "tesis",
    "tesisleri": "tesis",
    "tesisi": "tesis",
    "social": "sosyal",
    "military": "askeri",
    "casino": "gazino",
    "police": "polis",
    "gendarmerie": "jandarma",
    "provincial": "il",
    "regiment": "alay",
    "command": "komutanlik",
    "university": "universite",
    "lodgings": "lojman",
}

# Elle doğrulanmış / bilinen özel çeviriler (il, eski) → yeni
MANUAL_RENAMES: dict[tuple[str, str], str] = {
    ("Ankara", "TEKSİF EĞİTİM & DİNLENME TESİSİ"): "TEKSİF Eğitim ve Dinlenme Tesisi",
    ("Ankara", "GEST SOSYAL TESİSLERİ"): "GEST Sosyal Tesisleri",
    ("Adana", "Evliya Celebi VeriLoan Application Hotel"): "Evliya Çelebi Uygulama Oteli",
    ("Ankara", "Sincan Teachers' Lodgings"): "Sincan Öğretmen Lojmanları",
    ("Ankara", "DSI BAHÇELİEVLER SOCIAL CLUB"): "DSİ Bahçelievler Sosyal Tesisi",
    ("Ankara", "Union of Municipalities of the guest house"): "Türkiye Belediyeler Birliği Konukevi",
    ("Ankara", "METU Guesthouse for Graduate Students"): "ODTÜ Lisansüstü Öğrenci Konukevi",
    ("Ankara", "Republic of Turkey Gendarmerie General Command"): "T.C. Jandarma Genel Komutanlığı",
    ("Ankara", "Anittepe Gendarmerie"): "Anıttepe Jandarma",
    ("Ankara", "TURK-SEN TDVS RELIGION FOUNDATION GUEST"): "Türk Diyanet Vakıf-Sen Misafirhanesi",
    ("Aydın", "BayKus Konuk Evi Guesthouse"): "BayKuş Konuk Evi",
    ("Aydın", "Ionia Guest House / İonia Konuk Evi ( Saman Ev / Saman Otel )"): "İonia Konuk Evi (Saman Ev / Saman Otel)",
    ("Kıbrıs", "METU NCC Guest House"): "ODTÜ KKK Konukevi",
    ("Çanakkale", "Çanakkale Municipality Social Facilities"): "Çanakkale Belediyesi Sosyal Tesisleri",
    ("Düzce", "Highways Social Facilities"): "Karayolları Sosyal Tesisleri",
    ("Balıkesir", "ALTINOLUK Teacher Social Facilities"): "Altınoluk Öğretmen Sosyal Tesisleri",
    ("Balıkesir", "Balıkesir Teacher's Lodge"): "Balıkesir Öğretmen Lojmanı",
    ("Balıkesir", "Cunda Uygulama Hotel"): "Cunda Uygulama Oteli",
    ("Bingöl", "Bingol Police House"): "Bingöl Polisevi",
    ("Bursa", "Uludag Police House"): "Uludağ Polisevi",
    ("Denizli", "Pamukkale University Social Facilities"): "Pamukkale Üniversitesi Sosyal Tesisleri",
    ("Edirne", "Trakya University Application Hotel"): "Trakya Üniversitesi Uygulama Oteli",
    ("Elazığ", "Teachers Elazig"): "Elazığ Öğretmenevi",
    ("Erzurum", "Erzurum Technical University Guest House"): "Erzurum Teknik Üniversitesi Konukevi",
    ("Erzurum", "Teachers and Evening Art School Directorate"): "Öğretmenevi ve Akşam Sanat Okulu Müdürlüğü",
    ("Hatay", "Iskenderun Guest House for Teachers and Evening Art School"): "İskenderun Öğretmenevi ve Akşam Sanat Okulu",
}

FORCED_KEEP: set[tuple[str, str]] = {
    ("Adıyaman", "Adıyaman İl Jandarma Sosyal Tesisi"),
    ("Ağrı", "Ağrı Öğretmenevi (Merkez Burçin Uysal Öğretmenevi ve A.S.O. Müdürlüğü)"),
    ("Artvin", "Hopa Öğretmenevi"),
    ("Ankara", "Türk Telekom Misafirhane"),
    ("Antalya", "Konyaaltı Mehmet Zeki Balcı Öğretmenevi ve ASO Müdürlüğü"),
}

TYPE_EQUIV = {
    "kamu misafirhanesi": "kamu",
    "universite konukevi": "universite",
    "universite misafirhanesi": "universite",
    "ogretmenevi": "ogretmenev",
    "uygulama oteli": "uygulama",
    "orduevi": "ordu",
    "polisevi": "polis",
    "jandarma sosyal tesisi": "jandarma",
}

SMALL_WORDS = {"ve", "ile", "veya", "de", "da", "ki", "için", "of", "the", "and"}
ACRONYM_KEEP = {
    "dsi",
    "tcd",
    "tcdd",
    "ptt",
    "aso",
    "ibb",
    "meb",
    "odtü",
    "odtu",
    "metu",
    "tobb",
    "etü",
    "etu",
    "tbb",
    "teiaş",
    "teias",
    "eüaş",
    "euas",
    "tdvs",
    "mke",
    "gsb",
    "takav",
    "tigem",
    "tmo",
}


def tr_lower(value: object) -> str:
    s = str(value or "")
    s = s.replace("I", "ı").replace("İ", "i")
    return s.lower()


def fold(value: object) -> str:
    return tr_lower(value).strip().translate(TR_FOLD)


def normalized(value: object) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", fold(value)))


def tokens(name: str, city: str) -> frozenset[str]:
    city_parts = set(normalized(city).split())
    out: list[str] = []
    for raw in normalized(name).split():
        if raw in STOP or raw in city_parts:
            continue
        out.append(TOKEN_EQUIV.get(raw, raw))
    if "konukev" in out:
        out = [x for x in out if x != "house"]
    return frozenset(out)


def distance_m(a: dict, b: dict) -> float | None:
    try:
        lat1, lng1 = float(a["latitude"]), float(a["longitude"])
        lat2, lng2 = float(b["latitude"]), float(b["longitude"])
    except (KeyError, TypeError, ValueError):
        return None
    if (lat1 == 0 and lng1 == 0) or (lat2 == 0 and lng2 == 0):
        return None
    r = 6_371_000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    x = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(x)))


def same_type(a: dict, b: dict) -> bool:
    ta = TYPE_EQUIV.get(normalized(a.get("tip")), normalized(a.get("tip")))
    tb = TYPE_EQUIV.get(normalized(b.get("tip")), normalized(b.get("tip")))
    return bool(ta and tb and ta == tb)


@dataclass(frozen=True)
class Match:
    duplicate: bool
    reason: str
    distance: float | None = None


def compare(a: dict, b: dict) -> Match:
    if fold(a.get("il")) != fold(b.get("il")):
        return Match(False, "farklı il")
    na, nb = normalized(a.get("isim")), normalized(b.get("isim"))
    dist = distance_m(a, b)
    if na == nb and dist is not None and dist <= 150:
        return Match(True, "aynı normalize isim+yakın konum", dist)
    ta = tokens(str(a.get("isim") or ""), str(a.get("il") or ""))
    tb = tokens(str(b.get("isim") or ""), str(b.get("il") or ""))
    if ta and ta == tb and dist is not None and dist <= 150:
        return Match(True, "aynı kelimeler/eşanlamlar+yakın konum", dist)
    union = ta | tb
    overlap = len(ta & tb) / len(union) if union else 0.0
    # Ayırt edici ekstra yer adı (dağ, ilçe vb.) varsa daha sıkı eşik
    only_a, only_b = ta - tb, tb - ta
    placeish = {
        "dag",
        "dagi",
        "merkez",
        "yeni",
        "eski",
        "kuzey",
        "guney",
        "yazlik",
        "kisla",
    }
    distinctive = (only_a | only_b) & placeish
    min_overlap = 0.75 if distinctive else 0.34
    if dist is not None and dist <= 35 and overlap >= max(min_overlap, 0.34) and same_type(a, b):
        if distinctive and overlap < 0.75:
            return Match(False, "ayırt edici yer adı", dist)
        return Match(True, f"aynı tip+yakın konum+isim benzerliği ({overlap:.2f})", dist)
    if dist is not None and dist <= 35 and overlap >= 0.60 and not distinctive:
        return Match(True, f"yakın konum+güçlü isim benzerliği ({overlap:.2f})", dist)
    if dist is not None and dist <= 12 and overlap >= 0.25 and not distinctive:
        return Match(True, f"aynı pin+isim benzerliği ({overlap:.2f})", dist)
    return Match(False, "yetersiz kanıt", dist)


def image_keys(root: dict) -> set[tuple[str, str]]:
    result = set()
    for item in root.get("items") or []:
        urls = item.get("image_urls") or []
        if any(str(url).startswith("http") for url in urls):
            result.add((normalized(item.get("il")), normalized(item.get("isim"))))
    return result


def has_image(item: dict, keys: set[tuple[str, str]]) -> bool:
    return (normalized(item.get("il")), normalized(item.get("isim"))) in keys


def fingerprint(item: dict) -> tuple[str, str, float | None, float | None]:
    try:
        lat = round(float(item.get("latitude")), 7)
        lng = round(float(item.get("longitude")), 7)
    except (TypeError, ValueError):
        lat, lng = None, None
    return (fold(item.get("il")), normalized(item.get("isim")), lat, lng)


def looks_english(name: str) -> bool:
    return bool(
        re.search(
            r"\b(teachers?|applications?|hotel|guest\s*house|guesthouse|"
            r"social\s*facilit(?:y|ies)|military|gendarmerie|directorate|"
            r"university|provincial|command|lodgings|police\s*house)\b",
            name,
            re.IGNORECASE,
        )
    )


_ACRONYM_MAP = {
    "dsi": "DSİ",
    "tcdd": "TCDD",
    "ptt": "PTT",
    "aso": "ASO",
    "ibb": "İBB",
    "meb": "MEB",
    "odtü": "ODTÜ",
    "odtu": "ODTÜ",
    "metu": "ODTÜ",
    "tobb": "TOBB",
    "etü": "ETÜ",
    "etu": "ETÜ",
    "tbb": "TBB",
    "teiaş": "TEİAŞ",
    "teias": "TEİAŞ",
    "eüaş": "EÜAŞ",
    "euas": "EÜAŞ",
    "tdvs": "TDVS",
    "mke": "MKE",
    "gsb": "GSB",
    "takav": "TAKAV",
    "tigem": "TİGEM",
    "tmo": "TMO",
}


def title_tr(word: str) -> str:
    if not word:
        return word
    low = fold(word)
    if low in _ACRONYM_MAP:
        return _ACRONYM_MAP[low]
    if len(word) <= 5 and word.isupper() and any(c.isalpha() for c in word) and low in ACRONYM_KEEP:
        return word.upper()
    rest = tr_lower(word[1:]) if len(word) > 1 else ""
    first = word[0]
    if first in "iIıİ":
        return "İ" + rest
    # ASCII I already handled in tr_lower path for rest; capitalize first normally
    if first == "i":
        return "İ" + rest
    return first.upper() + rest


def auto_title_case(name: str) -> str | None:
    """Yalnızca tamamen BÜYÜK veya tamamen küçük adları Baş Harf biçimine çevir."""
    s = re.sub(r"\s+", " ", name.strip())
    if not s or looks_english(s):
        return None
    letters = [c for c in s if c.isalpha()]
    if len(letters) < 5:
        return None
    all_up = all(c.isupper() for c in letters)
    all_lo = all(c.islower() for c in letters)
    if not (all_up or all_lo):
        return None
    # ASCII ALLCAPS (Türkçe diyakritik yok): I harfini İ gibi i yap
    ascii_only = not any(c in s for c in "ığüşöçİĞÜŞÖÇ")
    parts = []
    for i, raw in enumerate(s.split(" ")):
        piece = raw
        if ascii_only and all_up:
            piece = raw.replace("I", "i").replace("İ", "i")
        if "-" in piece:
            parts.append("-".join(title_tr(p) if p else p for p in piece.split("-")))
            continue
        low = fold(piece if not ascii_only else piece)
        if i > 0 and low in SMALL_WORDS:
            parts.append(tr_lower(piece) if not ascii_only else piece.lower())
        else:
            if ascii_only and all_up:
                # title_tr I→İ yoluna girmeden düz ASCII title
                low2 = fold(piece)
                if low2 in _ACRONYM_MAP:
                    parts.append(_ACRONYM_MAP[low2])
                else:
                    parts.append(piece[:1].upper() + piece[1:].lower() if piece else piece)
            else:
                parts.append(title_tr(piece))
    out = " ".join(parts)
    if "\u0307" in out:
        return None
    return out if out != name else None


def pattern_rename(il: str, name: str) -> str | None:
    """Yüksek güvenli İngilizce→Türkçe kalıplar."""
    manual = MANUAL_RENAMES.get((il, name))
    if manual:
        return manual

    n = name.strip()
    # Teachers and ASO Directorate → Öğretmenevi ve ASO Müdürlüğü
    m = re.match(
        r"^(.+?)\s+Teachers(?:'?|\s+and)?\s*(?:and\s+ASO\s+Directorate|Lodgings)?$",
        n,
        re.IGNORECASE,
    )
    if m and "Teachers" in n:
        base = m.group(1).strip()
        if re.search(r"Directorate", n, re.I):
            return f"{base} Öğretmenevi ve ASO Müdürlüğü"
        if re.search(r"Lodgings", n, re.I):
            return f"{base} Öğretmen Lojmanları"
        return f"{base} Öğretmenevi"

    m = re.match(r"^(.+?)\s+Police\s+House$", n, re.IGNORECASE)
    if m:
        return f"{m.group(1).strip()} Polisevi"

    m = re.match(r"^(.+?)\s+University\s+Social\s+Facilities$", n, re.IGNORECASE)
    if m:
        return f"{m.group(1).strip()} Üniversitesi Sosyal Tesisleri"

    m = re.match(r"^(.+?)\s+Social\s+Facilities$", n, re.IGNORECASE)
    if m:
        base = m.group(1).strip()
        # "Teacher Social Facilities" / Municipality / Highways gibi yarım İngilizce kalmasın
        if looks_english(base) or re.search(
            r"\b(municipality|highways|teacher|teachers|hotel|guest|university)\b",
            base,
            re.I,
        ):
            return None
        return f"{base} Sosyal Tesisleri"

    m = re.match(
        r"^(.+?)\s+Provincial\s+Gendarmerie(?:\s+Regiment)?\s+Command$",
        n,
        re.IGNORECASE,
    )
    if m:
        base = m.group(1).strip()
        if re.search(r"Regiment", n, re.I):
            return f"{base} İl Jandarma Alay Komutanlığı"
        return f"{base} İl Jandarma Komutanlığı"

    m = re.match(r"^(.+?)\s+Province\s+Gendarmerie\s+Command$", n, re.IGNORECASE)
    if m:
        return f"{m.group(1).strip()} İl Jandarma Komutanlığı"

    m = re.match(r"^(.+?)\s+Practice\s+Hotel$", n, re.IGNORECASE)
    if m:
        base = m.group(1).strip()
        if looks_english(base) or re.search(
            r"\b(tourism|vocational|high\s+school|research|practice)\b", base, re.I
        ):
            return None
        return f"{base} Uygulama Oteli"

    m = re.match(r"^(.+?)\s+Application\s+Hotel$", n, re.IGNORECASE)
    if m:
        base = m.group(1).strip()
        if re.search(r"\b(university|tourism|vocational)\b", base, re.I):
            base2 = re.sub(r"\bUniversity\b", "Üniversitesi", base, flags=re.I)
            if not looks_english(base2):
                return f"{base2} Uygulama Oteli"
            # Tamamen İngilizce uzun isim → sadece bilinen kısa kalıplar
            return None
        return f"{base} Uygulama Oteli"

    m = re.match(r"^(.+?)\s+Guest\s+House$", n, re.IGNORECASE)
    if m:
        base = m.group(1).strip()
        if looks_english(base) and re.search(r"\bUniversity\b", base, re.I):
            base = re.sub(r"\bUniversity\b", "Üniversitesi", base, flags=re.I)
        if looks_english(base):
            return None
        return f"{base} Konukevi"

    if re.fullmatch(r"Police\s+House", n, re.IGNORECASE):
        return "Polisevi"

    m = re.match(
        r"^(.+?)\s+Teachers?(?:\s+and\s+Evening\s+Art\s+School(?:\s+Directorate)?)?$",
        n,
        re.IGNORECASE,
    )
    if m and re.search(r"Teachers?", n, re.I):
        base = m.group(1).strip()
        if base and not looks_english(base):
            if re.search(r"Evening\s+Art\s+School", n, re.I):
                return f"{base} Öğretmenevi ve Akşam Sanat Okulu"
            return f"{base} Öğretmenevi"
        if re.fullmatch(r"Teachers?\s+and\s+Evening\s+Art\s+School(?:\s+Directorate)?", n, re.I):
            return "Öğretmenevi ve Akşam Sanat Okulu Müdürlüğü"

    # ASCII Ogretmenevi → Öğretmenevi (yalnızca bu bozukluk)
    if "Ogretmenevi" in n or "ogretmenevi" in n:
        fixed = n.replace("Ogretmenevi", "Öğretmenevi").replace("ogretmenevi", "Öğretmenevi")
        fixed = fixed.replace("Aksam", "Akşam").replace("aksam", "Akşam")
        if fixed != n:
            return fixed

    titled = auto_title_case(n)
    if titled:
        return titled
    return None


def suspicious_name(name: str) -> list[str]:
    reasons = []
    if looks_english(name):
        reasons.append("İngilizce/yabancı ifade")
    letters = [c for c in name if c.isalpha()]
    if len(letters) >= 5 and (all(c.isupper() for c in letters) or all(c.islower() for c in letters)):
        reasons.append("büyük/küçük harf")
    if "  " in name or re.search(r"\s+[,.]", name):
        reasons.append("bozuk boşluk/noktalama")
    if "Ogretmenevi" in name or "ogretmenevi" in name:
        reasons.append("ASCII transliterasyon")
    return reasons


def quality_score(item: dict, image_set: set[tuple[str, str]], baseline: set[tuple[str, str]]) -> int:
    """Yüksek = korunmaya daha uygun."""
    name = str(item.get("isim") or "")
    il = str(item.get("il") or "")
    score = 0
    if has_image(item, image_set):
        score += 100
    if (fold(item.get("il")), normalized(item.get("isim"))) in baseline:
        score += 40
    if looks_english(name):
        score -= 50
    if "Ogretmenevi" in name or re.fullmatch(r"[A-ZÇĞİÖŞÜ0-9 &\-/().]+", name or ""):
        score -= 20
    if any(c in name for c in "ığüşöçİĞÜŞÖÇ"):
        score += 10
    letters = [c for c in name if c.isalpha()]
    if letters and not (all(c.isupper() for c in letters) or all(c.islower() for c in letters)):
        score += 5
    # İl adı geçen / daha spesifik uzun isimler tercih edilir
    if fold(il) and fold(il) in fold(name):
        score += 15
    score += min(20, len(name) // 8)
    return score


def build_groups(items: list[dict]) -> list[list[int]]:
    parent = list(range(len(items)))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for i, a in enumerate(items):
        for j in range(i + 1, len(items)):
            if compare(a, items[j]).duplicate:
                union(i, j)

    grouped: dict[int, list[int]] = {}
    for i in range(len(items)):
        grouped.setdefault(find(i), []).append(i)
    return [idxs for idxs in grouped.values() if len(idxs) > 1]


def load_baseline_keys() -> set[tuple[str, str]]:
    if not BASELINE.is_file():
        return set()
    data = json.loads(BASELINE.read_text(encoding="utf-8"))
    return {
        (fold(t.get("il")), normalized(t.get("isim")))
        for t in (data.get("tesisler") or [])
        if isinstance(t, dict)
    }


def resolve_group(
    rows: list[dict],
    image_set: set[tuple[str, str]],
    baseline: set[tuple[str, str]],
) -> tuple[dict | None, list[dict], str] | None:
    """(keeper, to_delete, reason_kind) veya None (belirsiz)."""
    pictured = [r for r in rows if has_image(r, image_set)]
    plain = [r for r in rows if not has_image(r, image_set)]

    forced = [
        row
        for row in rows
        if (str(row.get("il") or ""), str(row.get("isim") or "")) in FORCED_KEEP
    ]
    if len(forced) == 1:
        keeper = forced[0]
        return keeper, [r for r in rows if r is not keeper], "elle doğrulanmış kanonik"

    if len(pictured) == 1 and plain:
        keeper = pictured[0]
        safe = []
        for row in plain:
            match = compare(keeper, row)
            if match.duplicate:
                safe.append(row)
            else:
                return None
        if safe:
            return keeper, safe, "resimli korunur"

    # Aynı normalize isim + yakın konum → tek satır bırak
    names = {normalized(row.get("isim")) for row in rows}
    if len(names) == 1 and all(
        (distance_m(rows[0], row) is not None and (distance_m(rows[0], row) or 9999) <= 150)
        for row in rows[1:]
    ):
        ranked = sorted(rows, key=lambda r: quality_score(r, image_set, baseline), reverse=True)
        return ranked[0], ranked[1:], "tam mükerrer satır"

    # Hiçbiri resimli değilse: Türkçe/kaliteli olanı tut, İngilizce/ASCII kopyayı sil
    if not pictured and len(rows) >= 2:
        ranked = sorted(rows, key=lambda r: quality_score(r, image_set, baseline), reverse=True)
        keeper = ranked[0]
        drop = []
        for row in ranked[1:]:
            match = compare(keeper, row)
            if not match.duplicate:
                return None
            # Yalnızca keeper belirgin şekilde daha iyi ise sil
            if quality_score(keeper, image_set, baseline) - quality_score(row, image_set, baseline) >= 30:
                drop.append(row)
            else:
                return None
        if drop:
            return keeper, drop, "Türkçe/kaliteli korunur"

    # İkisi de resimli: yalnızca neredeyse aynı pin + aynı token ise birini bırak
    if len(pictured) >= 2 and not plain:
        ranked = sorted(pictured, key=lambda r: quality_score(r, image_set, baseline), reverse=True)
        keeper = ranked[0]
        drop = []
        for row in ranked[1:]:
            dist = distance_m(keeper, row)
            if dist is not None and dist <= 40 and (
                normalized(keeper.get("isim")) == normalized(row.get("isim"))
                or tokens(str(keeper.get("isim") or ""), str(keeper.get("il") or ""))
                == tokens(str(row.get("isim") or ""), str(row.get("il") or ""))
            ):
                drop.append(row)
            else:
                return None
        if drop:
            return keeper, drop, "çift resimli mükerrer pin"
    return None


def city_filter(item: dict, prefix: str | None, exclude_a: bool) -> bool:
    ilf = fold(item.get("il"))
    if not ilf:
        return False
    if exclude_a and ilf.startswith("a"):
        return False
    if prefix is None:
        return True
    return ilf.startswith(prefix)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cities-prefix", default=None, help="Örn. B; --all ile birlikte kullanma")
    parser.add_argument("--all", action="store_true", help="Tüm iller")
    parser.add_argument(
        "--exclude-a",
        action="store_true",
        help="A illerini atla (önceden temizlendiyse)",
    )
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if args.all:
        prefix = None
        scope_label = "ALL"
    else:
        prefix = fold(args.cities_prefix or "A")
        scope_label = (args.cities_prefix or "A").upper()

    master = json.loads(MASTER.read_text(encoding="utf-8"))
    images = json.loads(IMAGES.read_text(encoding="utf-8"))
    image_set = image_keys(images)
    baseline = load_baseline_keys()

    all_items = list(master.get("tesisler") or [])
    scoped = [item for item in all_items if city_filter(item, prefix, args.exclude_a)]
    # Gruplama şehir bazında (performans + güven)
    by_city: dict[str, list[dict]] = {}
    for item in scoped:
        by_city.setdefault(fold(item.get("il")), []).append(item)

    removals: list[dict] = []
    ambiguous: list[dict] = []
    delete_rows_for_apply: list[dict] = []

    for city_rows in by_city.values():
        for idxs in build_groups(city_rows):
            rows = [city_rows[i] for i in idxs]
            info = {
                "il": rows[0].get("il"),
                "records": [
                    {
                        "isim": r.get("isim"),
                        "tip": r.get("tip"),
                        "latitude": r.get("latitude"),
                        "longitude": r.get("longitude"),
                        "resimli": has_image(r, image_set),
                        "skor": quality_score(r, image_set, baseline),
                    }
                    for r in rows
                ],
            }
            resolved = resolve_group(rows, image_set, baseline)
            if not resolved:
                ambiguous.append(info)
                continue
            keeper, drop, kind = resolved
            info["keep"] = keeper.get("isim")
            info["delete"] = [r.get("isim") for r in drop]
            info["reasons"] = [
                {
                    "isim": r.get("isim"),
                    "neden": kind,
                    "mesafe_m": round(distance_m(keeper, r) or 0, 1),
                }
                for r in drop
            ]
            removals.append(info)
            delete_rows_for_apply.extend(drop)

    planned_renames = []
    for row in scoped:
        il = str(row.get("il") or "")
        isim = str(row.get("isim") or "")
        new = pattern_rename(il, isim)
        if new and new != isim:
            planned_renames.append({"il": il, "eski": isim, "yeni": new})

    suspicious = []
    for row in scoped:
        reasons = suspicious_name(str(row.get("isim") or ""))
        if reasons and not any(
            x["eski"] == row.get("isim") and x["il"] == row.get("il") for x in planned_renames
        ):
            suspicious.append(
                {
                    "il": row.get("il"),
                    "isim": row.get("isim"),
                    "neden": reasons,
                    "resimli": has_image(row, image_set),
                }
            )

    report = {
        "scope": scope_label + ("-noA" if args.exclude_a else ""),
        "tesis_sayisi": len(scoped),
        "guvenli_silinecek_grup": len(removals),
        "guvenli_silinecek_kayit": sum(len(x["delete"]) for x in removals),
        "belirsiz_grup": len(ambiguous),
        "isim_duzeltme_plan": len(planned_renames),
        "isim_duzeltme_atlanan": len(suspicious),
        "safe_removals": removals,
        "ambiguous_groups": ambiguous,
        "planned_renames": planned_renames,
        "suspicious_names": suspicious,
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        f"Kapsam={report['scope']} Aday={len(scoped)} güvenli_sil={report['guvenli_silinecek_kayit']} "
        f"belirsiz_grup={len(ambiguous)} rename={len(planned_renames)} atlanan_isim={len(suspicious)}"
    )
    print(f"Rapor: {REPORT}")

    if not args.apply:
        print("DRY RUN: dosyalar değiştirilmedi")
        return

    delete_fingerprints = {fingerprint(row) for row in delete_rows_for_apply}
    rename_map = {
        (fold(x["il"]), normalized(x["eski"])): x["yeni"] for x in planned_renames
    }
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    tag = fold(scope_label)
    backup = ROOT / "data_out" / f"master_backup_before_cleanup_{tag}_{stamp}.json"
    shutil.copy2(MASTER, backup)
    shutil.copy2(ADDRESSES, ROOT / "data_out" / f"tesisler_adres_backup_before_cleanup_{tag}_{stamp}.json")
    shutil.copy2(IMAGES, ROOT / "data_out" / f"tesisler_gorseller_backup_before_cleanup_{tag}_{stamp}.json")

    kept = []
    renamed = 0
    for row in all_items:
        if fingerprint(row) in delete_fingerprints:
            continue
        # Scoped dışı illere rename uygulama
        if not city_filter(row, prefix, args.exclude_a):
            kept.append(row)
            continue
        key = (fold(row.get("il")), normalized(row.get("isim")))
        new_name = rename_map.get(key)
        if new_name and str(row.get("isim") or "") != new_name:
            row = dict(row)
            row["isim"] = new_name
            renamed += 1
        kept.append(row)

    master["tesisler"] = kept
    remaining_keys = {(fold(row.get("il")), normalized(row.get("isim"))) for row in kept}
    deleted_keys = {
        (fp[0], fp[1]) for fp in delete_fingerprints if (fp[0], fp[1]) not in remaining_keys
    }

    MASTER.write_text(json.dumps(master, ensure_ascii=False, indent=2), encoding="utf-8")

    for path in (ADDRESSES, IMAGES):
        root = json.loads(path.read_text(encoding="utf-8"))
        updated = []
        for item in root.get("items") or []:
            key = (fold(item.get("il")), normalized(item.get("isim")))
            if key in deleted_keys:
                continue
            # Rename yalnızca scoped illerde
            il_ok = True
            if prefix is not None and not fold(item.get("il")).startswith(prefix):
                il_ok = False
            if args.exclude_a and fold(item.get("il")).startswith("a"):
                il_ok = False
            new_name = rename_map.get(key) if il_ok or prefix is None else None
            if prefix is None and args.exclude_a and fold(item.get("il")).startswith("a"):
                new_name = None
            if new_name and str(item.get("isim") or "") != new_name:
                item = dict(item)
                item["isim"] = new_name
            updated.append(item)
        root["items"] = updated
        path.write_text(json.dumps(root, ensure_ascii=False, indent=2), encoding="utf-8")

    print(
        f"UYGULANDI: {len(all_items) - len(kept)} kayıt silindi, "
        f"{renamed} isim düzeltildi; yedek={backup}"
    )


if __name__ == "__main__":
    main()
