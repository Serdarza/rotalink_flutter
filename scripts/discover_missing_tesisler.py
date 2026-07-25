#!/usr/bin/env python3
"""Google Places'te olup master'da olmayan kamu konaklamalarını bul / ekle.

- Alfabetik il harfi: FETCH_LETTER=A (varsayılan)
- Veya belirli iller: FETCH_CITIES=Kahramanmaraş,Karabük,Karaman
- CLOSED_PERMANENTLY eklenmez
- Master yapısı: isim, tip, il, adres, telefon, latitude, longitude

Ücret (kabaca):
  Text Search Pro ~$32/1000 (ayda 5000 ücretsiz)
  Place Details: adres Essentials; telefon Contact/Enterprise kademesi

  set FETCH_LETTER=A
  python scripts/discover_missing_tesisler.py
"""

from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data_out"
SCRIPTS = ROOT / "scripts"
PROGRESS = OUT_DIR / "discover_tesis_progress.json"
NEW_OUT = OUT_DIR / "new_tesisler_discovered.json"

MASTER_CANDIDATES = [
    Path(os.environ.get("ROTALINK_MASTER", "")),
    ROOT / "master_database_updated.json",
    OUT_DIR / "master_database_fixed.json",
    ROOT.parent / "rotalink-data" / "master_database_updated.json",
]

USER_AGENT = "RotalinkDiscoverTesis/1.0 (rotalink.tr)"
GOOGLE_SLEEP = float(os.environ.get("GOOGLE_SLEEP", "0.35"))

SEARCH_TERMS = [
    "öğretmenevi",
    "orduevi",
    "polisevi",
    "polis evi",
    "misafirhane",
    "konukevi",
    "uygulama oteli",
    "öğretmenler lokali",
    "jandarma kamp",
    "askeri gazino",
]

NAME_MUST_MATCH = re.compile(
    r"öğretmenevi|ogretmenevi|orduevi|polisevi|polis\s*evi|misafirhane|"
    r"konukevi|uygulama\s*oteli|öğretmenler|ogretmenler|jandarma|"
    r"askeri|sendika|kampı|kamp\b|sosyal\s*tesis|hekimevi|hekim\s*evi|"
    r"loji[sz]tik\s*misafir|personel\s*misafir|konuk\s*evi",
    re.IGNORECASE,
)


def fold_tr(s: str) -> str:
    t = (s or "").strip().casefold()
    for a, b in (
        ("ı", "i"),
        ("İ", "i"),
        ("i̇", "i"),
        ("ş", "s"),
        ("ğ", "g"),
        ("ü", "u"),
        ("ö", "o"),
        ("ç", "c"),
    ):
        t = t.replace(a.casefold(), b)
    return t


def _read_key() -> str:
    key = os.environ.get("GOOGLE_PLACES_API_KEY", "").strip()
    if key:
        return key
    p = SCRIPTS / ".google_places_key"
    if p.is_file():
        return p.read_text(encoding="utf-8").strip().splitlines()[0].strip()
    return ""


def load_master_path() -> Path:
    for p in MASTER_CANDIDATES:
        if p and p.is_file() and p.stat().st_size > 1000:
            return p
    raise SystemExit("master_database bulunamadı")


def http_json(
    method: str,
    url: str,
    *,
    headers: dict | None = None,
    body: dict | None = None,
    timeout: int = 60,
) -> dict:
    data = None
    hdrs = {"User-Agent": USER_AGENT, **(headers or {})}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            raw = res.read()
            return json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code}: {err[:400]}") from e


def cities_for_letter(master: dict, letter: str) -> list[str]:
    letter = fold_tr(letter)[:1]
    ils = sorted(
        {str(t.get("il") or "").strip() for t in (master.get("tesisler") or []) if t},
        key=fold_tr,
    )
    return [il for il in ils if il and fold_tr(il).startswith(letter)]


def cities_from_env(master: dict) -> list[str] | None:
    """FETCH_CITIES=İl1,İl2 → master’daki gerçek il adlarıyla eşleştir."""
    raw = (os.environ.get("FETCH_CITIES") or "").strip()
    if not raw:
        return None
    wanted = [p.strip() for p in raw.split(",") if p.strip()]
    if not wanted:
        return None
    all_ils = sorted(
        {str(t.get("il") or "").strip() for t in (master.get("tesisler") or []) if t},
        key=fold_tr,
    )
    by_fold = {fold_tr(il): il for il in all_ils if il}
    out: list[str] = []
    for w in wanted:
        hit = by_fold.get(fold_tr(w))
        if hit and hit not in out:
            out.append(hit)
        else:
            print(f"  UYARI: FETCH_CITIES il bulunamadı: {w}")
    return out


def existing_keys(tesisler: list) -> set[str]:
    keys = set()
    for t in tesisler:
        if not isinstance(t, dict):
            continue
        il = str(t.get("il") or "").strip()
        isim = str(t.get("isim") or "").strip()
        if isim:
            keys.add(f"{fold_tr(il)}|{fold_tr(isim)}")
    return keys


# Ortak ekler: "uygulama oteli" ↔ "otel uygulama", "öğretmenevi" ↔ "öğretmen evi"
_NAME_STOP = {
    "ve",
    "ile",
    "the",
    "of",
    "mudurlugu",
    "mudurluk",
    "mudur",
    "asomudur",
    "aso",
    "a",
    "s",
    "o",
    "ltd",
    "sti",
}


def _stem_token(tok: str) -> str:
    t = tok
    for suf in (
        "misafirhanesi",
        "misafirhane",
        "ogretmenevi",
        "ogretmenleri",
        "ogretmenler",
        "ogretmen",
        "orduevi",
        "polisevi",
        "konukevi",
        "tesisleri",
        "tesisler",
        "tesisi",
        "tesis",
        "oteli",
        "otel",
        "kampi",
        "kamp",
        "lokali",
        "lokal",
        "gazinosu",
        "gazino",
        "amiriigi",
        "amirligi",
        "komutanligi",
        "komutanlik",
    ):
        if t == suf or t.endswith(suf) and len(t) > len(suf) + 2:
            # Tam eşleşme veya anlamlı kök bırak
            if t == suf:
                return suf.rstrip("i") if suf.endswith("i") and len(suf) > 4 else suf
    # Basit Türkçe çoğul / iyelik sadeleştirme
    for suf, root in (
        ("misafirhanesi", "misafirhane"),
        ("ogretmenevi", "ogretmenev"),
        ("orduevi", "orduev"),
        ("polisevi", "polisev"),
        ("konukevi", "konukev"),
        ("oteli", "otel"),
        ("tesisleri", "tesis"),
        ("tesisler", "tesis"),
        ("tesisi", "tesis"),
        ("kampi", "kamp"),
        ("lokali", "lokal"),
        ("gazinosu", "gazino"),
        ("evi", "ev"),
    ):
        if t == suf or t.endswith(suf):
            if t == suf:
                return root
            prefix = t[: -len(suf)]
            if len(prefix) >= 2:
                return prefix + root
            return root
    return t


def name_tokens(isim: str, il: str = "") -> frozenset[str]:
    """Kelime sırasından bağımsız imza: 'Düzce Uygulama Oteli' == 'Düzce Otel Uygulama'."""
    n = fold_tr(isim)
    n = re.sub(r"[^a-z0-9\s]", " ", n)
    toks = []
    il_f = fold_tr(il)
    for raw in n.split():
        if not raw or raw in _NAME_STOP:
            continue
        if il_f and (raw == il_f or raw.startswith(il_f) or il_f.startswith(raw)):
            continue
        st = _stem_token(raw)
        if st and st not in _NAME_STOP and len(st) > 1:
            toks.append(st)
    return frozenset(toks)


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    import math

    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


class ExistingIndex:
    """Aynı ilde: tam isim, kelime-kümesi veya yakın koordinat → mevcut tesis."""

    def __init__(self, tesisler: list, *, near_m: float = 120.0):
        self.near_m = near_m
        self.exact: set[str] = set()
        self.token_keys: set[str] = set()  # fold(il)|sorted_tokens
        self.by_il_coords: dict[str, list[tuple[float, float, str]]] = {}

        for t in tesisler:
            if not isinstance(t, dict):
                continue
            self.add(t)

    def _tok_key(self, il: str, isim: str) -> str | None:
        toks = name_tokens(isim, il)
        if len(toks) < 1:
            return None
        return f"{fold_tr(il)}|{' '.join(sorted(toks))}"

    def add(self, t: dict) -> None:
        il = str(t.get("il") or "").strip()
        isim = str(t.get("isim") or "").strip()
        if not isim:
            return
        self.exact.add(f"{fold_tr(il)}|{fold_tr(isim)}")
        tk = self._tok_key(il, isim)
        if tk:
            self.token_keys.add(tk)
        try:
            lat = float(t["latitude"])
            lng = float(t["longitude"])
        except (KeyError, TypeError, ValueError):
            return
        if lat == 0 and lng == 0:
            return
        self.by_il_coords.setdefault(fold_tr(il), []).append((lat, lng, isim))

    def is_duplicate(self, *, il: str, isim: str, lat: float | None = None, lng: float | None = None) -> str | None:
        """Yineleniyorsa neden; değilse None."""
        exact = f"{fold_tr(il)}|{fold_tr(isim)}"
        if exact in self.exact:
            return "aynı isim"
        tk = self._tok_key(il, isim)
        if tk and tk in self.token_keys:
            return "aynı kelimeler (sıra farklı)"
        if lat is not None and lng is not None and not (lat == 0 and lng == 0):
            for elat, elng, ename in self.by_il_coords.get(fold_tr(il), []):
                if haversine_m(lat, lng, elat, elng) <= self.near_m:
                    # Konum aynıysa: isim token kesişimi veya tip benzerliği
                    a = name_tokens(isim, il)
                    b = name_tokens(ename, il)
                    if a and b and (a & b):
                        return f"aynı konum (~{int(haversine_m(lat, lng, elat, elng))}m) ≈ {ename}"
                    # Çok yakın (<40m) ise tipik kamu tesis tekrarı
                    if haversine_m(lat, lng, elat, elng) <= 40.0:
                        return f"aynı pin (~{int(haversine_m(lat, lng, elat, elng))}m) ≈ {ename}"
        return None


def infer_tip(isim: str) -> str:
    n = fold_tr(isim)
    rules = [
        ("ogretmenevi", "Öğretmenevi"),
        ("ogretmenler", "Öğretmenevi"),
        ("orduevi", "Orduevi"),
        ("polisevi", "Polisevi"),
        ("polis evi", "Polisevi"),
        ("uygulama oteli", "Uygulama Oteli"),
        ("konukevi", "Üniversite Konukevi"),
        ("konuk evi", "Üniversite Konukevi"),
        ("universite", "Üniversite Misafirhanesi"),
        ("dsi", "DSİ Misafirhanesi"),
        ("karayollari", "Karayolları Misafirhanesi"),
        ("orman", "Orman Misafirhanesi"),
        ("ptt", "PTT Misafirhanesi"),
        ("belediye", "Belediye Misafirhanesi"),
        ("jandarma", "Jandarma Sosyal Tesisi"),
        ("askeri", "Orduevi"),
        ("sendika", "Kamu Misafirhanesi"),
        ("misafirhane", "Kamu Misafirhanesi"),
        ("sosyal tesis", "Kamu Misafirhanesi"),
    ]
    for needle, tip in rules:
        if needle in n:
            return tip
    return "Kamu Misafirhanesi"


def extract_ilce(components: list, il: str) -> str:
    by_type: dict[str, str] = {}
    for c in components or []:
        if not isinstance(c, dict):
            continue
        name = str(c.get("longText") or c.get("shortText") or "").strip()
        if not name:
            continue
        for t in c.get("types") or []:
            by_type[str(t)] = name
    for key in (
        "administrative_area_level_2",
        "locality",
        "sublocality_level_1",
        "postal_town",
    ):
        v = by_type.get(key) or ""
        if v and fold_tr(v) != fold_tr(il):
            return v
    return by_type.get("administrative_area_level_2") or by_type.get("locality") or ""


def city_centroid(tesisler: list, il: str) -> tuple[float, float] | None:
    pts = []
    for t in tesisler:
        if not isinstance(t, dict):
            continue
        if fold_tr(str(t.get("il") or "")) != fold_tr(il):
            continue
        try:
            pts.append((float(t["latitude"]), float(t["longitude"])))
        except (KeyError, TypeError, ValueError):
            pass
    if not pts:
        return None
    return (
        sum(p[0] for p in pts) / len(pts),
        sum(p[1] for p in pts) / len(pts),
    )


def belongs_to_il(
    *,
    il: str,
    isim: str,
    adres: str,
    components: list,
    lat: float,
    lng: float,
    centroid: tuple[float, float] | None,
) -> bool:
    """Başka ile ait sonuçları ele (Google Text Search bazen yanlış şehir döner)."""
    il_f = fold_tr(il)
    # Adres / bileşenlerde il adı
    if il_f and il_f in fold_tr(adres):
        return True
    for c in components or []:
        if not isinstance(c, dict):
            continue
        name = fold_tr(str(c.get("longText") or c.get("shortText") or ""))
        types = [str(x) for x in (c.get("types") or [])]
        if "administrative_area_level_1" in types and il_f in name:
            return True
        if "administrative_area_level_2" in types and il_f in name:
            return True
    # İsimde il adı (Adana Öğretmenevi)
    if il_f and il_f in fold_tr(isim):
        return True
    # Merkeze yakınlık (~80 km)
    if centroid is not None:
        dlat = (lat - centroid[0]) * 111.0
        dlng = (lng - centroid[1]) * 111.0 * max(0.2, abs(__import__("math").cos(centroid[0] * 3.1416 / 180)))
        if (dlat * dlat + dlng * dlng) ** 0.5 <= 80.0:
            return True
    return False


def text_search(
    api_key: str,
    query: str,
    page_token: str | None = None,
    *,
    lat: float | None = None,
    lng: float | None = None,
) -> dict:
    url = "https://places.googleapis.com/v1/places:searchText"
    body: dict = {
        "textQuery": query,
        "languageCode": "tr",
        "regionCode": "TR",
        "pageSize": 20,
    }
    if page_token:
        body["pageToken"] = page_token
    if lat is not None and lng is not None:
        body["locationBias"] = {
            "circle": {
                "center": {"latitude": lat, "longitude": lng},
                "radius": 45000.0,
            }
        }
    headers = {
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": (
            "places.id,places.displayName,places.formattedAddress,"
            "places.location,places.businessStatus,places.types,nextPageToken"
        ),
    }
    return http_json("POST", url, headers=headers, body=body)


def place_details(api_key: str, place_id: str) -> dict:
    pid = place_id.strip()
    if pid.startswith("places/"):
        pid = pid[len("places/") :]
    enc = urllib.parse.quote(pid, safe="")
    url = f"https://places.googleapis.com/v1/places/{enc}"
    headers = {
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": (
            "id,displayName,formattedAddress,shortFormattedAddress,"
            "addressComponents,location,businessStatus,"
            "nationalPhoneNumber,internationalPhoneNumber"
        ),
    }
    return http_json("GET", url, headers=headers)


def normalize_phone(raw: str) -> str:
    s = (raw or "").strip()
    if not s:
        return ""
    digits = re.sub(r"\D", "", s)
    if digits.startswith("90") and len(digits) >= 12:
        digits = "0" + digits[2:]
    if len(digits) == 10 and digits.startswith("5"):
        digits = "0" + digits
    if len(digits) == 11 and digits.startswith("0"):
        return f"{digits[0:4]} {digits[4:7]} {digits[7:9]} {digits[9:11]}"
    return s


def clean_adres(s: str) -> str:
    t = (s or "").strip()
    for suf in (", Türkiye", ", Turkey", " Türkiye", " Turkey"):
        if t.endswith(suf):
            t = t[: -len(suf)].rstrip(" ,")
    return t


def display_name(pl: dict) -> str:
    disp = pl.get("displayName") or {}
    if isinstance(disp, dict):
        return str(disp.get("text") or "").strip()
    return str(disp or "").strip()


def main() -> None:
    api_key = _read_key()
    if not api_key:
        raise SystemExit("Google Places API key yok")

    letter = (os.environ.get("FETCH_LETTER") or "A").strip() or "A"
    dry = (os.environ.get("DRY_RUN") or "").strip().lower() in ("1", "true", "yes")
    max_new = int(os.environ.get("FETCH_LIMIT", "0") or "0")

    master_path = load_master_path()
    print(f"Master: {master_path}")
    master = json.loads(master_path.read_text(encoding="utf-8"))
    tesisler = list(master.get("tesisler") or [])
    index = ExistingIndex(tesisler)
    cities_override = cities_from_env(master)
    if cities_override is not None:
        cities = cities_override
        print(f"FETCH_CITIES iller={cities}")
    else:
        cities = cities_for_letter(master, letter)
        print(f"Harf={letter} iller={cities}")
    print(f"Mevcut tesis={len(tesisler)} | DRY_RUN={dry}")

    progress: dict = {}
    if PROGRESS.is_file():
        progress = json.loads(PROGRESS.read_text(encoding="utf-8"))

    seen_place_ids: set[str] = set(progress.get("seen_place_ids") or [])
    discovered: list[dict] = list(progress.get("discovered") or [])
    for d in discovered:
        index.add(d)

    search_count = 0
    details_count = 0
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    stop = False
    for il in cities:
        if stop:
            break
        centroid = city_centroid(tesisler, il)
        for term in SEARCH_TERMS:
            if stop:
                break
            query_done_key = f"{fold_tr(il)}|{fold_tr(term)}"
            if progress.get("queries", {}).get(query_done_key) == "done":
                continue

            query = f"{term} {il} Türkiye"
            page_token = None
            for pages in range(1, 4):
                print(f"SEARCH [{il}] {query} (sayfa {pages})")
                try:
                    data = text_search(
                        api_key,
                        query,
                        page_token,
                        lat=centroid[0] if centroid else None,
                        lng=centroid[1] if centroid else None,
                    )
                    search_count += 1
                    time.sleep(GOOGLE_SLEEP)
                except Exception as e:
                    print(f"  HATA search: {e}")
                    break

                places = data.get("places") or []
                if not places:
                    break

                for pl in places:
                    pid = str(pl.get("id") or "").strip()
                    if not pid or pid in seen_place_ids:
                        continue
                    status = str(pl.get("businessStatus") or "").upper()
                    if status == "CLOSED_PERMANENTLY":
                        print(f"  atla (kapalı): {display_name(pl) or pid}")
                        seen_place_ids.add(pid)
                        continue

                    isim = display_name(pl)
                    if not isim or not NAME_MUST_MATCH.search(isim):
                        continue
                    if "uygulama" in fold_tr(term) and "uygulama" not in fold_tr(isim):
                        continue

                    k = f"{fold_tr(il)}|{fold_tr(isim)}"
                    why = index.is_duplicate(il=il, isim=isim)
                    if why:
                        print(f"  atla ({why}): {isim}")
                        seen_place_ids.add(pid)
                        continue

                    try:
                        det = place_details(api_key, pid)
                        details_count += 1
                        time.sleep(GOOGLE_SLEEP)
                    except Exception as e:
                        print(f"  HATA details {isim}: {e}")
                        continue

                    st2 = str(det.get("businessStatus") or status).upper()
                    if st2 == "CLOSED_PERMANENTLY":
                        print(f"  atla details kapalı: {isim}")
                        seen_place_ids.add(pid)
                        continue

                    isim = display_name(det) or isim
                    why = index.is_duplicate(il=il, isim=isim)
                    if why:
                        print(f"  atla ({why}): {isim}")
                        seen_place_ids.add(pid)
                        continue

                    loc = det.get("location") or pl.get("location") or {}
                    try:
                        lat = float(loc.get("latitude"))
                        lng = float(loc.get("longitude"))
                    except (TypeError, ValueError):
                        print(f"  atla (koordinat yok): {isim}")
                        continue

                    why = index.is_duplicate(il=il, isim=isim, lat=lat, lng=lng)
                    if why:
                        print(f"  atla ({why}): {isim}")
                        seen_place_ids.add(pid)
                        continue

                    adres = clean_adres(
                        str(
                            det.get("formattedAddress")
                            or det.get("shortFormattedAddress")
                            or pl.get("formattedAddress")
                            or ""
                        )
                    )
                    components = det.get("addressComponents") or []
                    if not belongs_to_il(
                        il=il,
                        isim=isim,
                        adres=adres,
                        components=components,
                        lat=lat,
                        lng=lng,
                        centroid=centroid,
                    ):
                        print(f"  atla (yanlış il): {isim} | {adres[:70]}")
                        seen_place_ids.add(pid)
                        continue

                    telefon = normalize_phone(
                        str(
                            det.get("nationalPhoneNumber")
                            or det.get("internationalPhoneNumber")
                            or ""
                        )
                    )
                    tip = infer_tip(isim)
                    entry = {
                        "isim": isim,
                        "tip": tip,
                        "il": il,
                        "adres": adres,
                        "telefon": telefon,
                        "latitude": lat,
                        "longitude": lng,
                        "_place_id": pid,
                        "_ilce": extract_ilce(components, il),
                        "_source": "google_places_discover",
                    }
                    discovered.append(entry)
                    index.add(entry)
                    seen_place_ids.add(pid)
                    print(f"  + YENİ: {isim} | {tip} | {telefon or 'tel yok'}")

                    if max_new > 0 and len(discovered) >= max_new:
                        stop = True
                        break

                progress["seen_place_ids"] = sorted(seen_place_ids)
                progress["discovered"] = discovered
                PROGRESS.write_text(
                    json.dumps(progress, ensure_ascii=False, indent=2), encoding="utf-8"
                )

                if stop:
                    break
                page_token = (data.get("nextPageToken") or "").strip() or None
                if not page_token:
                    break
                time.sleep(max(GOOGLE_SLEEP, 1.5))

            progress.setdefault("queries", {})[query_done_key] = "done"
            PROGRESS.write_text(
                json.dumps(progress, ensure_ascii=False, indent=2), encoding="utf-8"
            )

    clean_new = []
    adres_extra = []
    for d in discovered:
        clean_new.append(
            {
                "isim": d["isim"],
                "tip": d["tip"],
                "il": d["il"],
                "adres": d.get("adres") or "",
                "telefon": d.get("telefon") or "",
                "latitude": d["latitude"],
                "longitude": d["longitude"],
            }
        )
        adres_extra.append(
            {
                "il": d["il"],
                "isim": d["isim"],
                "adres": d.get("adres") or "",
                "ilce": d.get("_ilce") or "",
            }
        )

    NEW_OUT.write_text(
        json.dumps(
            {
                "not": f"Google Places keşif harf={letter}. Kapalı kalıcı yok.",
                "search_calls_approx": search_count,
                "details_calls_approx": details_count,
                "items": clean_new,
                "adres_items": adres_extra,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Keşfedilen yeni: {len(clean_new)} → {NEW_OUT}")
    print(f"Bu koşu: search≈{search_count} details≈{details_count}")

    if dry:
        print("DRY_RUN=1 — master yazılmadı")
        return
    if not clean_new:
        print("Eklenecek yeni tesis yok")
        return

    backup = OUT_DIR / f"master_backup_before_discover_{letter}.json"
    backup.write_text(master_path.read_text(encoding="utf-8"), encoding="utf-8")
    print(f"Yedek: {backup}")

    existing = ExistingIndex(tesisler)
    added = 0
    for item in clean_new:
        why = existing.is_duplicate(
            il=item["il"],
            isim=item["isim"],
            lat=item.get("latitude"),
            lng=item.get("longitude"),
        )
        if why:
            print(f"  master atla ({why}): {item['isim']}")
            continue
        tesisler.append(item)
        existing.add(item)
        added += 1

    master["tesisler"] = tesisler
    master_path.write_text(
        json.dumps(master, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Master güncellendi: +{added} tesis (toplam {len(tesisler)})")
    print("Not: rotalink-data'ya kopyalayıp push edin.")


if __name__ == "__main__":
    main()
