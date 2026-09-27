#!/usr/bin/env python3
"""Eksik kamu tesislerini kaynak sitelerden bul ve master'a ekle."""

from __future__ import annotations

import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "assets" / "data" / "master_database_updated.json"
OUT_DIR = ROOT / "data_out"
REPORT = OUT_DIR / "import_missing_report.json"
MEB_URL = "https://dhgm.meb.gov.tr/edestek/ogretmenevi/ogretmenevi_liste.aspx"
USER_AGENT = "RotalinkFacilityImport/1.0 (+https://rotalink.tr; data-sync)"
SLEEP = 0.15

sys.path.insert(0, str(ROOT / "scripts"))
from discover_missing_tesisler import (  # noqa: E402
    ExistingIndex,
    fold_tr,
    infer_tip,
    normalize_phone,
)

NS = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}


def log(msg: str) -> None:
    print(msg, flush=True)


def http_get(url: str, timeout: int = 60) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return res.read().decode("utf-8", errors="replace")


def build_city_slug_map(master: dict) -> dict[str, str]:
    m: dict[str, str] = {}
    for t in master.get("tesisler") or []:
        il = str(t.get("il") or "").strip()
        if il:
            m[fold_tr(il).replace(" ", "-")] = il
            m[fold_tr(il)] = il
    extras = {
        "afyonkarahisar": "Afyonkarahisar",
        "kahramanmaras": "Kahramanmaraş",
        "sanliurfa": "Şanlıurfa",
        "agri": "Ağrı",
        "igdir": "Iğdır",
        "usak": "Uşak",
        "kirsehir": "Kırşehir",
        "kirikkale": "Kırıkkale",
        "canakkale": "Çanakkale",
        "corum": "Çorum",
        "duzce": "Düzce",
        "elazig": "Elazığ",
        "eskisehir": "Eskişehir",
        "istanbul": "İstanbul",
        "izmir": "İzmir",
        "diyarbakir": "Diyarbakır",
        "gaziantep": "Gaziantep",
        "kutahya": "Kütahya",
        "mugla": "Muğla",
        "nevsehir": "Nevşehir",
        "nigde": "Niğde",
        "tekirdag": "Tekirdağ",
        "karabuk": "Karabük",
        "sirnak": "Şırnak",
        "bartin": "Bartın",
        "mus": "Muş",
        "adana": "Adana",
        "adiyaman": "Adıyaman",
        "ankara": "Ankara",
        "antalya": "Antalya",
        "artvin": "Artvin",
        "aydin": "Aydın",
        "balikesir": "Balıkesir",
        "bilecik": "Bilecik",
        "bingol": "Bingöl",
        "bitlis": "Bitlis",
        "bolu": "Bolu",
        "burdur": "Burdur",
        "bursa": "Bursa",
        "denizli": "Denizli",
        "edirne": "Edirne",
        "erzincan": "Erzincan",
        "erzurum": "Erzurum",
        "giresun": "Giresun",
        "hatay": "Hatay",
        "isparta": "Isparta",
        "kars": "Kars",
        "kastamonu": "Kastamonu",
        "kayseri": "Kayseri",
        "kilis": "Kilis",
        "kocaeli": "Kocaeli",
        "konya": "Konya",
        "malatya": "Malatya",
        "manisa": "Manisa",
        "mersin": "Mersin",
        "rize": "Rize",
        "ardahan": "Ardahan",
        "bayburt": "Bayburt",
        "batman": "Batman",
        "aksaray": "Aksaray",
        "amasya": "Amasya",
        "gumushane": "Gümüşhane",
        "karaman": "Karaman",
        "osmaniye": "Osmaniye",
        "sakarya": "Sakarya",
        "samsun": "Samsun",
        "siirt": "Siirt",
        "sinop": "Sinop",
        "sivas": "Sivas",
        "tokat": "Tokat",
        "trabzon": "Trabzon",
        "tunceli": "Tunceli",
        "van": "Van",
        "yalova": "Yalova",
        "yozgat": "Yozgat",
        "zonguldak": "Zonguldak",
    }
    m.update(extras)
    return m


def slug_to_city(slug: str, city_map: dict[str, str]) -> str:
    return city_map.get(slug.strip().lower(), slug.replace("-", " ").title())


def parse_meb_html(raw: str) -> list[dict]:
    rows: list[dict] = []
    pattern = re.compile(
        r"lbl_il[^>]*>([^<]+)</span>.*?lbl_ilce[^>]*>([^<]+)</span>.*?lbl_kurum[^>]*>([^<]+)</span>.*?lbl_telefon[^>]*>([^<]*)</span>",
        re.I | re.S,
    )
    for m in pattern.finditer(raw):
        rows.append(
            {
                "il": html.unescape(m.group(1).strip()),
                "ilce": html.unescape(m.group(2).strip()),
                "isim": html.unescape(m.group(3).strip()),
                "telefon": html.unescape(m.group(4).strip()),
            }
        )
    if rows:
        return rows
    # Yedek: markdown tablo (fetch aracı çıktısı)
    for line in raw.splitlines():
        m = re.match(
            r"\|\s*(\d+)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\s*\|",
            line,
        )
        if m:
            rows.append(
                {
                    "il": m.group(2).strip(),
                    "ilce": m.group(3).strip(),
                    "isim": m.group(4).strip(),
                    "telefon": m.group(5).strip(),
                }
            )
    return rows


def meb_display_name(il: str, ilce: str, kurum: str) -> str:
    base = re.sub(
        r"\s+ve\s+Ak[sş]am\s+Sanat\s+Okulu\s*$",
        "",
        kurum,
        flags=re.I,
    ).strip()
    base = base.replace("Öğretmen Evi", "Öğretmenevi")
    il_f = fold_tr(il)
    ilce_f = fold_tr(ilce)
    base_f = fold_tr(base)

    # Merkez ilçe + jenerik "Merkez Öğretmenevi" → il adıyla
    if ilce_f == "merkez" and re.match(r"^Merkez\s+Öğretmenevi", base, re.I):
        return f"{il} Öğretmenevi"
    if il_f in base_f:
        return base
    if ilce_f in ("merkez", "buyuksehir", "efeler", "konyaalti", "kepez", "seyhan"):
        if "ogretmen" in base_f:
            cleaned = re.sub(r"^Merkez\s+", "", base, flags=re.I).strip()
            return f"{il} {cleaned}".strip()
    if "ogretmen" in base_f and ilce_f not in base_f:
        return f"{il} {ilce} Öğretmenevi"
    return f"{il} {base}"


def phone_index(tesisler: list) -> dict[str, set[str]]:
    idx: dict[str, set[str]] = defaultdict(set)
    for t in tesisler:
        il = fold_tr(str(t.get("il") or ""))
        tel = normalize_phone(str(t.get("telefon") or ""))
        if il and tel:
            idx[il].add(tel)
    return idx


def is_dup(
    index: ExistingIndex,
    phones: dict[str, set[str]],
    *,
    il: str,
    isim: str,
    telefon: str = "",
    lat: float | None = None,
    lng: float | None = None,
) -> str | None:
    why = index.is_duplicate(il=il, isim=isim, lat=lat, lng=lng)
    if why:
        return why
    tel = normalize_phone(telefon)
    if tel and tel in phones.get(fold_tr(il), set()):
        return "aynı telefon"
    return None


def fetch_kamu_urls() -> list[str]:
    urls: list[str] = []
    index = http_get("https://kamutesisleri.com/sitemap.xml")
    root = ET.fromstring(index)
    maps = [
        sm.find("sm:loc", NS).text.strip()
        for sm in root.findall("sm:sitemap", NS)
        if sm.find("sm:loc", NS) is not None
        and "sitemap-facilities" in (sm.find("sm:loc", NS).text or "")
    ]
    for sm_url in maps:
        xml = http_get(sm_url)
        r = ET.fromstring(xml)
        for u in r.findall("sm:url", NS):
            loc = u.find("sm:loc", NS)
            if loc is not None and loc.text:
                urls.append(loc.text.strip())
        time.sleep(SLEEP)
    return urls


def parse_kamu_page(url: str, city_map: dict[str, str]) -> dict | None:
    raw = http_get(url)
    parts = urllib.parse.urlparse(url).path.strip("/").split("/")
    if len(parts) < 4:
        return None
    il = slug_to_city(parts[0], city_map)

    title_m = re.search(r"<h1[^>]*>([^<]+)</h1>", raw, re.I)
    isim = html.unescape(title_m.group(1).strip()) if title_m else ""
    if not isim:
        return None

    tel_m = re.search(r'href="tel:([^"]+)"', raw)
    telefon = normalize_phone(tel_m.group(1)) if tel_m else ""

    adres = ""
    adr_m = re.search(r"Adres\s*</[^>]+>\s*([^<\n]+)", raw, re.I)
    if adr_m:
        adres = re.sub(r"\s+", " ", adr_m.group(1)).strip()

    lat, lng = 0.0, 0.0
    gm = re.search(r"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)", raw)
    if not gm:
        gm = re.search(r"@(-?\d+\.\d+),(-?\d+\.\d+)", raw)
    if gm:
        lat, lng = float(gm.group(1)), float(gm.group(2))

    return {
        "isim": isim,
        "tip": infer_tip(isim),
        "il": il,
        "adres": adres,
        "telefon": telefon,
        "latitude": lat,
        "longitude": lng,
    }


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    master = json.loads(MASTER.read_text(encoding="utf-8"))
    tesisler = list(master.get("tesisler") or [])
    index = ExistingIndex(tesisler)
    phones = phone_index(tesisler)

    report = {
        "scanned_provinces": 81,
        "sources": {"meb": False, "kamutesisleri": False, "kamusosyal": False},
        "examined": 0,
        "matched_existing": 0,
        "added": 0,
        "added_by_il": {},
        "added_items": [],
        "uncertain": [],
    }

    candidates: list[dict] = []

    # MEB
    log("MEB öğretmenevi listesi...")
    meb_raw = http_get(MEB_URL)
    meb_rows = parse_meb_html(meb_raw)
    report["sources"]["meb"] = True
    log(f"  {len(meb_rows)} kayıt")
    for row in meb_rows:
        report["examined"] += 1
        isim = meb_display_name(row["il"], row["ilce"], row["isim"])
        if is_dup(index, phones, il=row["il"], isim=isim, telefon=row["telefon"]):
            report["matched_existing"] += 1
            continue
        candidates.append(
            {
                "isim": isim,
                "tip": "Öğretmenevi",
                "il": row["il"],
                "adres": "",
                "telefon": normalize_phone(row["telefon"]),
                "latitude": 0.0,
                "longitude": 0.0,
            }
        )

    log(f"MEB aday (yeni): {len(candidates)}")

    # kamutesisleri
    log("kamutesisleri.com sitemap...")
    urls = fetch_kamu_urls()
    report["sources"]["kamutesisleri"] = True
    city_map = build_city_slug_map(master)
    log(f"  {len(urls)} tesis URL")
    new_from_kamu = 0
    for i, url in enumerate(urls, 1):
        report["examined"] += 1
        if i % 100 == 0:
            log(f"  {i}/{len(urls)}")
        try:
            row = parse_kamu_page(url, city_map)
        except Exception:
            continue
        if not row:
            continue
        if is_dup(
            index,
            phones,
            il=row["il"],
            isim=row["isim"],
            telefon=row["telefon"],
            lat=row["latitude"] or None,
            lng=row["longitude"] or None,
        ):
            report["matched_existing"] += 1
            continue
        candidates.append(row)
        new_from_kamu += 1
        time.sleep(SLEEP)

    log(f"kamutesisleri aday (yeni): {new_from_kamu}")

    # Adayları tekilleştir ve ekle
    seen: set[str] = set()
    to_add: list[dict] = []
    for c in candidates:
        key = f"{fold_tr(c['il'])}|{fold_tr(c['isim'])}"
        if key in seen:
            continue
        why = is_dup(
            index,
            phones,
            il=c["il"],
            isim=c["isim"],
            telefon=c.get("telefon") or "",
            lat=c.get("latitude") or None,
            lng=c.get("longitude") or None,
        )
        if why:
            report["matched_existing"] += 1
            continue
        seen.add(key)
        to_add.append(c)

    backup = OUT_DIR / "master_backup_before_import.json"
    backup.write_text(json.dumps(master, ensure_ascii=False, indent=2), encoding="utf-8")

    for item in to_add:
        tesisler.append(item)
        index.add(item)
        tel = normalize_phone(item.get("telefon") or "")
        if tel:
            phones[fold_tr(item["il"])].add(tel)
        report["added"] += 1
        report["added_by_il"][item["il"]] = report["added_by_il"].get(item["il"], 0) + 1
        report["added_items"].append(item)

    master["tesisler"] = tesisler
    MASTER.write_text(json.dumps(master, ensure_ascii=False, indent=2), encoding="utf-8")
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    log("\n=== SONUÇ ===")
    log(f"İncelenen kayıt: {report['examined']}")
    log(f"Zaten vardı: {report['matched_existing']}")
    log(f"Eklenen: {report['added']}")
    log(f"Belirsiz: {len(report['uncertain'])}")
    log(f"Toplam tesis: {len(tesisler)}")
    log(f"Rapor: {REPORT}")


if __name__ == "__main__":
    main()
