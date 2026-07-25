#!/usr/bin/env python3
"""Tesis adres + ilçe — güvenilir zenginleştirme.

Kurallar (kullanıcı güveni):
  1) Sahte / placeholder koordinat (örn. 37.0005,37.0005) ile reverse YAPILMAZ.
  2) Nominatim sonucu il (province) ile uyuşmuyorsa reddedilir.
  3) Master adresi boş değilse varsayılan olarak korunur; yalnızca
     geçerli reverse + il uyumu varsa güncellenir.
  4) İlçe: adres kalıbı → isimden çıkarım → (opsiyonel) Nominatim.
  5) FORCE_REFRESH=1 progress'i yok sayar; REPAIR_ONLY=1 sadece şüpheli
     kayıtları yeniden işler.

Çıktı: data_out/tesisler_adres.json
"""

from __future__ import annotations

import json
import math
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data_out"
PROGRESS = OUT_DIR / "tesis_adres_progress.json"
OUT_FILE = OUT_DIR / "tesisler_adres.json"
MASTER_CANDIDATES = [
    Path(os.environ.get("ROTALINK_MASTER", "")),
    ROOT / "master_database_updated.json",
]

USER_AGENT = "RotalinkAddressBot/1.1 (rotalink.tr; contact=dev)"
SLEEP = float(os.environ.get("NOMINATIM_SLEEP", "1.2"))
TIMEOUT = 25

# Bilinen bozuk / placeholder koordinatlar
PLACEHOLDER_COORDS = {
    (37.0005, 37.0005),
    (0.0, 0.0),
}

NAME_STRIP_SUFFIXES = (
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
    r"sosyal\s+tesis(?:ler(?:i)?)?",
    r"dinlenme\s+tesis(?:ler(?:i)?)?",
    r"kampı",
    r"kampi",
)


def http_get_json(url: str) -> dict | list | None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            return json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 429:
            print("  429 — 60s bekleniyor…")
            time.sleep(60)
            try:
                with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
                    return json.loads(res.read().decode("utf-8"))
            except Exception as e2:
                print(f"  HTTP hata (retry): {e2}")
                return None
        print(f"  HTTP hata: {e}")
        return None
    except Exception as e:
        print(f"  HTTP hata: {e}")
        return None


def load_master() -> dict:
    for p in MASTER_CANDIDATES:
        if p and p.is_file() and p.stat().st_size > 1000:
            print(f"Master: {p}")
            with p.open(encoding="utf-8") as f:
                return json.load(f)
    raise SystemExit("master_database bulunamadı.")


def load_progress() -> dict:
    if PROGRESS.is_file():
        return json.loads(PROGRESS.read_text(encoding="utf-8"))
    return {}


def save_progress(progress: dict) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PROGRESS.write_text(
        json.dumps(progress, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def normalize_space(s: str) -> str:
    return re.sub(r"\s+", " ", str(s or "").strip())


def norm_key(s: str) -> str:
    s = normalize_space(s).casefold()
    tr = str.maketrans("çğıöşüâîû", "cgiosuaiu")
    return s.translate(tr)


def coords_usable(lat: float, lon: float) -> bool:
    if not math.isfinite(lat) or not math.isfinite(lon):
        return False
    if abs(lat) < 0.5 or abs(lon) < 0.5:
        return False
    if not (35.5 <= lat <= 42.5 and 25.0 <= lon <= 45.5):
        return False
    for plat, plon in PLACEHOLDER_COORDS:
        if abs(lat - plat) < 1e-4 and abs(lon - plon) < 1e-4:
            return False
    # Aynı sayıya yuvarlanmış şüpheli placeholder (37,37 gibi)
    if abs(lat - lon) < 1e-6 and abs(lat - round(lat, 0)) < 1e-6:
        return False
    return True


def parse_lat_lon(raw: dict) -> tuple[float, float]:
    try:
        lat = float(raw.get("latitude") or raw.get("enlem") or 0)
        lon = float(raw.get("longitude") or raw.get("boylam") or 0)
    except (TypeError, ValueError):
        return 0.0, 0.0
    return lat, lon


def province_matches(addr: dict | None, il: str) -> bool:
    if not isinstance(addr, dict):
        return False
    il_n = norm_key(il)
    if not il_n:
        return False
    for key in ("province", "state", "region"):
        v = norm_key(str(addr.get(key) or ""))
        if not v:
            continue
        if v == il_n or il_n in v or v in il_n:
            return True
    # Bazen city = il merkezi
    city = norm_key(str(addr.get("city") or ""))
    if city == il_n:
        return True
    return False


def extract_ilce(addr: dict | None, il: str) -> str:
    if not isinstance(addr, dict):
        return ""
    il_n = norm_key(il)
    for key in (
        "town",
        "municipality",
        "city_district",
        "district",
        "borough",
        "county",
        "suburb",
        "village",
    ):
        v = normalize_space(str(addr.get(key) or ""))
        if not v:
            continue
        vn = norm_key(v)
        if vn == il_n:
            continue
        if "belediye" in vn and "sinir" in vn:
            continue
        st = normalize_space(str(addr.get("state") or addr.get("province") or ""))
        if st and norm_key(st) == vn:
            continue
        return v
    city = normalize_space(str(addr.get("city") or ""))
    if city and norm_key(city) != il_n:
        return city
    return ""


def ilce_from_adres_text(adres: str, il: str) -> str:
    a = normalize_space(adres)
    if not a:
        return ""
    il_n = normalize_space(il)
    # Çınarcık/Yalova  |  Samanlı/Yalova
    m = re.search(
        r"([A-Za-zÇĞİÖŞÜçğıöşü0-9\.\-\s]{2,40})\s*/\s*" + re.escape(il_n) + r"\b",
        a,
        re.I,
    )
    if m:
        cand = normalize_space(m.group(1))
        cl = cand.casefold()
        if not any(x in cl for x in ("mah", "sk.", "sok", "cad", "no:", "blv")):
            if norm_key(cand) != norm_key(il_n):
                # "77340 Koruköy/Çınarcık" → son parça
                parts = re.split(r"[\s,]+", cand)
                if len(parts) >= 2 and parts[-1][0:1].isalpha():
                    return parts[-1]
                return cand
    # Merkez-Düzce / Merkez – Düzce
    m2 = re.search(
        r"(Merkez)\s*[-–]\s*" + re.escape(il_n) + r"\b",
        a,
        re.I,
    )
    if m2:
        return "Merkez"
    # "…, Akçakoca, Düzce"
    m3 = re.search(
        r",\s*([A-Za-zÇĞİÖŞÜçğıöşü\-]{3,30})\s*,\s*" + re.escape(il_n) + r"\b",
        a,
        re.I,
    )
    if m3:
        cand = normalize_space(m3.group(1))
        if norm_key(cand) != norm_key(il_n):
            return cand
    return ""


def ilce_from_isim(isim: str, il: str) -> str:
    """Yığılca Öğretmenevi → Yığılca; Düzce Öğretmenevi → Merkez."""
    n = normalize_space(isim)
    if not n:
        return ""
    low = n.casefold()
    for suf in NAME_STRIP_SUFFIXES:
        low = re.sub(rf"\s*{suf}\s*$", "", low, flags=re.I)
        n2 = re.sub(rf"(?i)\s*{suf}\s*$", "", n).strip(" -–,")
        n = n2
    n = normalize_space(re.sub(r"\s*\(.*?\)\s*", " ", n))
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
    # Öğretmenevi/polisevi kalıbında ilk kelime genelde ilçe (Yığılca, Cumayeri…)
    low_isim = normalize_space(isim).casefold()
    if any(x in low_isim for x in ("öğretmenevi", "ogretmenevi", "polisevi", "orduevi")):
        return first
    if len(tokens) > 3:
        return " ".join(tokens[:2])
    return n


def format_adres_from_hit(hit: dict) -> str:
    dn = normalize_space(str(hit.get("display_name") or ""))
    addr = hit.get("address") if isinstance(hit.get("address"), dict) else {}
    parts: list[str] = []
    for key in ("road", "pedestrian", "neighbourhood", "suburb", "quarter"):
        v = normalize_space(str(addr.get(key) or ""))
        if v and v not in parts:
            parts.append(v)
    house = normalize_space(str(addr.get("house_number") or ""))
    if house and parts:
        parts[0] = f"{parts[0]} No:{house}"
    for key in ("town", "municipality", "city_district", "district", "county", "city"):
        v = normalize_space(str(addr.get(key) or ""))
        if v and v not in parts:
            parts.append(v)
    state = normalize_space(str(addr.get("state") or addr.get("province") or ""))
    if state and state not in parts:
        parts.append(state)
    built = ", ".join(parts)
    if dn and len(dn) < 160:
        return dn
    return built or dn


def reverse_lookup(lat: float, lon: float) -> dict | None:
    params = urllib.parse.urlencode(
        {
            "lat": f"{lat:.7f}",
            "lon": f"{lon:.7f}",
            "format": "json",
            "addressdetails": 1,
            "zoom": 16,
            "accept-language": "tr",
        }
    )
    url = f"https://nominatim.openstreetmap.org/reverse?{params}"
    time.sleep(SLEEP)
    data = http_get_json(url)
    return data if isinstance(data, dict) else None


def forward_lookup(query: str) -> dict | None:
    params = urllib.parse.urlencode(
        {
            "q": query,
            "format": "json",
            "limit": 3,
            "addressdetails": 1,
            "countrycodes": "tr",
            "accept-language": "tr",
        }
    )
    url = f"https://nominatim.openstreetmap.org/search?{params}"
    time.sleep(SLEEP)
    data = http_get_json(url)
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                return item
    return None


def pick_forward(hits_query_il: str, il: str) -> dict | None:
    """Forward sonuçlarından il uyumlu ilk kayıt."""
    params = urllib.parse.urlencode(
        {
            "q": hits_query_il,
            "format": "json",
            "limit": 5,
            "addressdetails": 1,
            "countrycodes": "tr",
            "accept-language": "tr",
        }
    )
    url = f"https://nominatim.openstreetmap.org/search?{params}"
    time.sleep(SLEEP)
    data = http_get_json(url)
    if not isinstance(data, list):
        return None
    for item in data:
        if not isinstance(item, dict):
            continue
        addr = item.get("address") if isinstance(item.get("address"), dict) else {}
        if province_matches(addr, il):
            return item
    return None


def is_suspicious_row(row: dict, master_adres: str, lat: float, lon: float) -> bool:
    """Yeniden işlenmesi gereken şüpheli kayıt."""
    adres = normalize_space(str(row.get("adres") or ""))
    ilce = normalize_space(str(row.get("ilce") or ""))
    il = normalize_space(str(row.get("il") or ""))
    isim = normalize_space(str(row.get("isim") or ""))
    if "Musabeyli" in ilce and norm_key(il) != "kilis":
        return True
    if adres in {"37.0005", "0", "0.0"}:
        return True
    if not ilce:
        return True
    # İsimden gelen ilçe ile kayıt çelişiyorsa (Yığılca vs Merkez)
    name_ilce = ilce_from_isim(isim, il)
    if name_ilce and name_ilce != "Merkez" and norm_key(name_ilce) != norm_key(ilce):
        return True
    # Geçerli koordinat var ama adres hâlâ master kopyası olabilir → reverse dene
    if coords_usable(lat, lon) and (row.get("source") or "") in {
        "master",
        "fallback",
        "",
    }:
        return True
    return False


def enrich_one(raw: dict, *, allow_network: bool) -> dict:
    isim = normalize_space(str(raw.get("isim") or raw.get("name") or ""))
    il = normalize_space(str(raw.get("il") or raw.get("sehir") or ""))
    tip = normalize_space(str(raw.get("tip") or ""))
    old_adres = normalize_space(str(raw.get("adres") or ""))
    # Master'da adres bazen sayı olabiliyor
    if not old_adres or old_adres.replace(".", "", 1).isdigit():
        old_adres = ""

    lat, lon = parse_lat_lon(raw)
    usable = coords_usable(lat, lon)

    ilce = ""
    adres = old_adres
    source = "master"
    out_lat: float | None = lat if usable else None
    out_lon: float | None = lon if usable else None

    hit: dict | None = None
    if allow_network and usable:
        hit = reverse_lookup(lat, lon)
        if hit is not None:
            addr = hit.get("address") if isinstance(hit.get("address"), dict) else {}
            if not province_matches(addr, il):
                print(f"  reverse il uyuşmazı → reddedildi ({isim})")
                hit = None

    if allow_network and hit is None and (not old_adres or not usable):
        q = ", ".join(x for x in (isim, il, "Türkiye") if x)
        hit = pick_forward(q, il)

    if hit is not None:
        addr = hit.get("address") if isinstance(hit.get("address"), dict) else {}
        ilce = extract_ilce(addr, il)
        new_adres = format_adres_from_hit(hit)
        # Master adres boşsa veya master kopya/şüpheliyse reverse adresini kullan
        if new_adres and (
            not old_adres
            or not usable  # zaten forward
            or len(old_adres) < 12
        ):
            adres = new_adres
            source = "nominatim"
        elif new_adres and usable:
            # Geçerli reverse: master kopyalanmış olabilir → reverse tercih
            # (aynı il içinde farklı tesisler aynı master adres paylaşır)
            adres = new_adres
            source = "nominatim_reverse"
        try:
            out_lat = float(hit.get("lat") or lat)
            out_lon = float(hit.get("lon") or lon)
            if not coords_usable(out_lat, out_lon):
                out_lat, out_lon = (lat if usable else None), (lon if usable else None)
        except (TypeError, ValueError):
            pass

    # İlçe: isim (Yığılca Öğretmenevi) adresteki yanlış "Merkez-Düzce"den önce gelir.
    ilce_name = ilce_from_isim(isim, il)
    ilce_addr = ilce_from_adres_text(adres, il) or ilce_from_adres_text(old_adres, il)
    if not ilce:
        if ilce_name and ilce_name != "Merkez":
            ilce = ilce_name
        elif ilce_addr:
            ilce = ilce_addr
        elif ilce_name:
            ilce = ilce_name

    if not adres:
        adres = old_adres

    return {
        "il": il,
        "isim": isim,
        "adres": adres,
        "ilce": ilce,
        "latitude": out_lat,
        "longitude": out_lon,
        "source": source,
        "tip": tip,
    }


def write_out(rows: list[dict]) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "not": "Adres: master öncelikli + doğrulanmış Nominatim. İlçe zorunlu doldurma.",
        "items": [
            {
                "il": r["il"],
                "isim": r["isim"],
                "adres": r.get("adres") or "",
                "ilce": r.get("ilce") or "",
            }
            for r in rows
        ],
    }
    OUT_FILE.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    with_ilce = sum(1 for r in rows if r.get("ilce"))
    with_adres = sum(1 for r in rows if r.get("adres"))
    print(f"Yazıldı: {OUT_FILE}")
    print(f"  adresli={with_adres}/{len(rows)}  ilçeli={with_ilce}/{len(rows)}")


def main() -> None:
    master = load_master()
    tesisler = master.get("tesisler") or master.get("misafirhaneler") or []
    print(f"Girdi: {len(tesisler)} tesis")

    limit = int(os.environ.get("FETCH_LIMIT", "0") or "0")
    if limit > 0:
        tesisler = tesisler[:limit]
        print(f"LIMIT={limit}")

    force = (os.environ.get("FORCE_REFRESH") or "").strip() in {"1", "true", "yes"}
    repair_only = (os.environ.get("REPAIR_ONLY") or "").strip() in {
        "1",
        "true",
        "yes",
    }
    offline = (os.environ.get("OFFLINE_ONLY") or "").strip() in {"1", "true", "yes"}
    print(f"FORCE_REFRESH={force} REPAIR_ONLY={repair_only} OFFLINE_ONLY={offline}")

    progress = {} if force else load_progress()
    out: list[dict] = []
    total = len(tesisler)

    # Önce offline hızlı geçiş: herkese en azından ilçe
    if offline or force:
        print("Offline ilçe/adres doldurma…")
        for raw in tesisler:
            if not isinstance(raw, dict):
                continue
            row = enrich_one(raw, allow_network=False)
            pk = f"{row['il']}|{row['isim']}"
            progress[pk] = row
        save_progress(progress)

    for i, raw in enumerate(tesisler):
        if not isinstance(raw, dict):
            continue
        isim = normalize_space(str(raw.get("isim") or ""))
        il = normalize_space(str(raw.get("il") or ""))
        pk = f"{il}|{isim}"
        lat, lon = parse_lat_lon(raw)
        master_adres = normalize_space(str(raw.get("adres") or ""))

        prev = progress.get(pk) if isinstance(progress.get(pk), dict) else None
        if prev and not force:
            if repair_only and not is_suspicious_row(prev, master_adres, lat, lon):
                out.append(prev)
                continue
            if not repair_only and prev.get("ilce") and prev.get("adres"):
                # Yine de Musabeyli / placeholder kirliyse düzelt
                if not is_suspicious_row(prev, master_adres, lat, lon):
                    out.append(prev)
                    continue

        if offline:
            row = enrich_one(raw, allow_network=False)
        else:
            print(f"[tesis {i+1}/{total}] {il} — {isim}")
            row = enrich_one(raw, allow_network=True)

        progress[pk] = row
        out.append(row)

        if (i + 1) % 10 == 0:
            save_progress(progress)
            print(f"  … progress ({i+1})")

    save_progress(progress)
    write_out(out)

    # Kalite özeti
    from collections import defaultdict

    by_adres: dict[str, list[str]] = defaultdict(list)
    for r in out:
        a = normalize_space(r.get("adres") or "")
        if a:
            by_adres[a].append(f"{r.get('il')}|{r.get('isim')}")
    shared = sum(1 for v in by_adres.values() if len(v) > 1)
    print(f"Kalite: paylaşılan_adres_metni={shared}  ilçesiz={sum(1 for r in out if not r.get('ilce'))}")


if __name__ == "__main__":
    main()
