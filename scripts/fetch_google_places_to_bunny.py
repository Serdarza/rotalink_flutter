#!/usr/bin/env python3
"""Google Places (N foto) → Bunny Storage → data_out overlay JSON.

Pexels yerine: her kayıt için Google'dan fotoğraf indirip Bunny'e yükler.
Uygulama yalnızca Bunny CDN URL'sini kullanır (Google'a tekrar gitmez).

Kurulum:
  1) scripts/.google_places_key  → Places API (New) API key
  2) scripts/.bunny_config.json  → storage zone + CDN (örnek: .bunny_config.example.json)

Misafirhane — 7 il × en fazla 3 foto (ücretsiz kota ~1000 foto/ay):
  set FETCH_KINDS=konaklama
  set FETCH_LIMIT=0
  set PHOTOS_PER_PLACE=3
  set FETCH_CITIES=Antalya,İzmir,İstanbul,Ankara,Aydın,Mersin,Muğla
  python scripts/fetch_google_places_to_bunny.py

Ortam:
  FETCH_KINDS=konaklama     (gezi|yemek|konaklama)
  FETCH_LIMIT=0             (0 = hepsi)
  PHOTOS_PER_PLACE=3
  FETCH_CITIES=Antalya,... (boş = tüm iller)
  GOOGLE_SLEEP=0.35
  MAX_HEIGHT_PX=960
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data_out"
PROGRESS = OUT_DIR / "google_bunny_progress.json"
SCRIPTS = ROOT / "scripts"

MASTER_CANDIDATES = [
    Path(os.environ.get("ROTALINK_MASTER", "")),
    ROOT / "master_database_updated.json",
    OUT_DIR / "master_database_fixed.json",
    ROOT.parent / "rotalink-data" / "master_database_updated.json",
]

USER_AGENT = "RotalinkPlacesBunny/1.0 (rotalink.tr)"
GOOGLE_SLEEP = float(os.environ.get("GOOGLE_SLEEP", "0.35"))
MAX_HEIGHT_PX = int(os.environ.get("MAX_HEIGHT_PX", "960") or "960")
PHOTOS_PER_PLACE = max(1, int(os.environ.get("PHOTOS_PER_PLACE", "1") or "1"))


def _read_key_file(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8").strip().splitlines()[0].strip()


def load_google_key() -> str:
    key = os.environ.get("GOOGLE_PLACES_API_KEY", "").strip()
    if key:
        return key
    return _read_key_file(SCRIPTS / ".google_places_key")


def load_bunny() -> dict:
    raw = os.environ.get("BUNNY_CONFIG_JSON", "").strip()
    if raw:
        return json.loads(raw)
    cfg_path = SCRIPTS / ".bunny_config.json"
    if not cfg_path.is_file():
        raise SystemExit(
            "Bunny config yok. scripts/.bunny_config.example.json dosyasını "
            "kopyalayıp scripts/.bunny_config.json yapın ve doldurun."
        )
    return json.loads(cfg_path.read_text(encoding="utf-8"))


def load_master() -> dict:
    for p in MASTER_CANDIDATES:
        if p and p.is_file() and p.stat().st_size > 1000:
            print(f"Master: {p}")
            return json.loads(p.read_text(encoding="utf-8"))
    raise SystemExit("master_database bulunamadı")


def load_progress() -> dict:
    if PROGRESS.is_file():
        return json.loads(PROGRESS.read_text(encoding="utf-8"))
    return {}


def save_progress(progress: dict) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PROGRESS.write_text(
        json.dumps(progress, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def fold_tr(s: str) -> str:
    """Türkçe karakterleri ASCII-ish kıyas için katla."""
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


def parse_cities_env() -> set[str] | None:
    raw = (os.environ.get("FETCH_CITIES") or "").strip()
    if not raw:
        return None
    return {fold_tr(x) for x in raw.split(",") if x.strip()}


def normalize_item(raw: dict) -> dict | None:
    if not isinstance(raw, dict):
        return None
    isim = str(raw.get("isim") or raw.get("name") or "").strip()
    il = str(raw.get("il") or raw.get("sehir") or "").strip()
    if not isim and not il:
        return None
    out = {
        "il": il,
        "isim": isim,
        "tip": str(raw.get("tip") or raw.get("type") or "").strip(),
        "adres": str(raw.get("adres") or "").strip(),
        "aciklama": str(raw.get("aciklama") or "").strip(),
        "image_urls": [],
    }
    for k in ("enlem", "latitude", "lat"):
        if raw.get(k) is not None:
            try:
                out["enlem"] = float(raw[k])
                break
            except (TypeError, ValueError):
                pass
    for k in ("boylam", "longitude", "lng", "lon"):
        if raw.get(k) is not None:
            try:
                out["boylam"] = float(raw[k])
                break
            except (TypeError, ValueError):
                pass
    return out


def build_search_query(item: dict) -> str:
    """Daha doğru yer eşleşmesi: isim + tip + il (+ kısa adres)."""
    parts = [item.get("isim") or "", item.get("tip") or "", item.get("il") or ""]
    adres = (item.get("adres") or "").strip()
    if adres and len(adres) <= 80:
        parts.append(adres)
    parts.append("Türkiye")
    return " ".join(p for p in parts if p).strip()


def slugify(*parts: str) -> str:
    s = "-".join(p.strip() for p in parts if p and str(p).strip())
    s = s.lower()
    s = re.sub(r"[^\w\-]+", "-", s, flags=re.UNICODE)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    if len(s) > 80:
        s = s[:80].rstrip("-")
    if not s:
        s = hashlib.sha1("|".join(parts).encode("utf-8")).hexdigest()[:16]
    return s


def http_json(
    method: str,
    url: str,
    *,
    headers: dict | None = None,
    body: dict | None = None,
    timeout: int = 45,
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
            if not raw:
                return {}
            return json.loads(raw.decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code} {url}: {err_body[:500]}") from e


def http_bytes(url: str, *, headers: dict | None = None, timeout: int = 60) -> bytes:
    req = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, **(headers or {})}
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            return res.read()
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code} {url}: {err_body[:300]}") from e


def places_text_search(
    api_key: str,
    query: str,
    *,
    lat: float | None = None,
    lng: float | None = None,
) -> dict | None:
    """Places API (New) Text Search — ilk sonucu döner.

    Koordinat varsa locationBias ile yakın sonuçları tercih eder (yanlış tesis azalır).
    """
    url = "https://places.googleapis.com/v1/places:searchText"
    body: dict = {
        "textQuery": query,
        "languageCode": "tr",
        "regionCode": "TR",
        "pageSize": 1,
    }
    if lat is not None and lng is not None:
        body["locationBias"] = {
            "circle": {
                "center": {"latitude": lat, "longitude": lng},
                "radius": 15000.0,
            }
        }
    headers = {
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": "places.id,places.name,places.displayName,places.photos",
    }
    data = http_json("POST", url, headers=headers, body=body)
    places = data.get("places") or []
    return places[0] if places else None


def download_place_photo(api_key: str, photo_name: str) -> bytes:
    q = urllib.parse.urlencode(
        {
            "maxHeightPx": str(MAX_HEIGHT_PX),
            "key": api_key,
        }
    )
    url = f"https://places.googleapis.com/v1/{photo_name}/media?{q}"
    return http_bytes(url)


def bunny_upload(
    bunny: dict,
    relative_path: str,
    content: bytes,
    content_type: str = "image/jpeg",
) -> str:
    zone = bunny["storage_zone"].strip()
    password = bunny["storage_password"].strip()
    endpoint = (
        bunny.get("storage_endpoint") or "storage.bunnycdn.com"
    ).strip().removeprefix("https://").removesuffix("/")
    cdn = bunny["cdn_base_url"].strip().rstrip("/")

    path = relative_path.lstrip("/")
    enc_zone = urllib.parse.quote(zone, safe="")
    enc_path = "/".join(urllib.parse.quote(p, safe="") for p in path.split("/"))
    url = f"https://{endpoint}/{enc_zone}/{enc_path}"

    req = urllib.request.Request(
        url,
        data=content,
        method="PUT",
        headers={
            "AccessKey": password,
            "Content-Type": content_type,
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            if res.status not in (200, 201):
                raise RuntimeError(f"Bunny upload status {res.status}")
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Bunny HTTP {e.code}: {err[:300]}") from e

    return f"{cdn}/{path}"


def guess_content_type(data: bytes) -> str:
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG"):
        return "image/png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return "image/jpeg"


def ext_for_ctype(ctype: str) -> str:
    if "png" in ctype:
        return "png"
    if "webp" in ctype:
        return "webp"
    return "jpg"


def progress_urls(prev: dict | None) -> list[str]:
    if not isinstance(prev, dict):
        return []
    urls = prev.get("cdn_urls")
    if isinstance(urls, list):
        return [str(u).strip() for u in urls if str(u).strip()]
    one = str(prev.get("cdn_url") or "").strip()
    return [one] if one else []


def process_kind(
    items_raw: list,
    kind: str,
    *,
    api_key: str,
    bunny: dict,
    progress: dict,
    photos_per: int,
) -> list[dict]:
    out: list[dict] = []
    total = len(items_raw)
    for i, raw in enumerate(items_raw):
        item = normalize_item(raw)
        if item is None:
            continue
        pk = f"{kind}|{item['il']}|{item['isim']}"
        prev = progress.get(pk)
        existing = progress_urls(prev if isinstance(prev, dict) else None)
        if len(existing) >= photos_per:
            item["image_urls"] = existing[:photos_per]
            out.append(item)
            continue
        # Kısmi tamamlanmışsa eksikleri doldurmak için devam (aynı place yeniden aranır)

        query = build_search_query(item)
        print(f"[{kind} {i+1}/{total}] {query} (hedef {photos_per} foto)")
        try:
            place = places_text_search(
                api_key,
                query,
                lat=item.get("enlem"),
                lng=item.get("boylam"),
            )
            time.sleep(GOOGLE_SLEEP)
            if not place:
                print("  yer bulunamadı")
                progress[pk] = {
                    "cdn_urls": existing,
                    "error": "not_found",
                }
                item["image_urls"] = existing
                out.append(item)
                continue
            photos = place.get("photos") or []
            if not photos:
                print("  foto yok")
                progress[pk] = {
                    "cdn_urls": existing,
                    "place_id": place.get("id") or "",
                    "error": "no_photo",
                }
                item["image_urls"] = existing
                out.append(item)
                continue

            cdn_urls = list(existing)
            used_names = set()
            if isinstance(prev, dict):
                for n in prev.get("photo_names") or []:
                    used_names.add(str(n))

            for photo in photos:
                if len(cdn_urls) >= photos_per:
                    break
                photo_name = (photo.get("name") or "").strip()
                if not photo_name or photo_name in used_names:
                    continue
                try:
                    blob = download_place_photo(api_key, photo_name)
                    time.sleep(GOOGLE_SLEEP)
                except Exception as pe:
                    print(f"  foto indirme hatası: {pe}")
                    continue
                ctype = guess_content_type(blob)
                ext = ext_for_ctype(ctype)
                idx = len(cdn_urls) + 1
                file_name = f"{slugify(item['il'], item['isim'])}-{idx}.{ext}"
                rel = f"{kind}/{slugify(item['il'])}/{file_name}"
                cdn_url = bunny_upload(bunny, rel, blob, content_type=ctype)
                print(f"  OK [{idx}/{photos_per}] → {cdn_url}")
                cdn_urls.append(cdn_url)
                used_names.add(photo_name)

            item["image_urls"] = cdn_urls
            progress[pk] = {
                "cdn_urls": cdn_urls,
                "cdn_url": cdn_urls[0] if cdn_urls else "",
                "place_id": place.get("id") or "",
                "photo_names": sorted(used_names),
            }
            if not cdn_urls:
                progress[pk]["error"] = "download_failed"
        except Exception as e:
            print(f"  HATA: {e}")
            progress[pk] = {
                "cdn_urls": existing,
                "cdn_url": existing[0] if existing else "",
                "error": str(e)[:300],
            }
            item["image_urls"] = existing

        out.append(item)
        if (i + 1) % 3 == 0:
            save_progress(progress)

    return out


def write_overlay(path: Path, items: list[dict], note: str) -> None:
    path.write_text(
        json.dumps({"not": note, "items": items}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    ok = sum(1 for x in items if x.get("image_urls"))
    print(f"Yazıldı: {path} ({ok}/{len(items)} görselli)")


def merge_overlay_items(path: Path, new_items: list[dict]) -> list[dict]:
    """Aynı il+isim varsa yenisiyle değiştir; diğerlerini koru."""
    by_key: dict[str, dict] = {}
    if path.is_file():
        try:
            old = json.loads(path.read_text(encoding="utf-8"))
            for it in old.get("items") or []:
                if not isinstance(it, dict):
                    continue
                k = f"{fold_tr(str(it.get('il') or ''))}|{fold_tr(str(it.get('isim') or ''))}"
                by_key[k] = it
        except Exception as e:
            print(f"Eski overlay okunamadı ({path.name}): {e}")
    for it in new_items:
        k = f"{fold_tr(str(it.get('il') or ''))}|{fold_tr(str(it.get('isim') or ''))}"
        by_key[k] = it
    return list(by_key.values())


def filter_by_cities(raw: list, cities: set[str] | None) -> list:
    if not cities:
        return raw
    out = []
    for r in raw:
        if not isinstance(r, dict):
            continue
        il = fold_tr(str(r.get("il") or r.get("sehir") or ""))
        if il in cities:
            out.append(r)
    return out


def main() -> None:
    api_key = load_google_key()
    if not api_key:
        raise SystemExit(
            "Google Places API key yok.\n"
            "  scripts/.google_places_key dosyasına tek satır key yazın\n"
            "  veya GOOGLE_PLACES_API_KEY ortam değişkeni verin."
        )
    bunny = load_bunny()
    for req in ("storage_zone", "storage_password", "cdn_base_url"):
        if not str(bunny.get(req) or "").strip():
            raise SystemExit(f".bunny_config.json içinde '{req}' gerekli")

    master = load_master()
    kinds_env = (os.environ.get("FETCH_KINDS") or "konaklama").strip().lower()
    kinds = {k.strip() for k in kinds_env.split(",") if k.strip()}
    limit = int(os.environ.get("FETCH_LIMIT", "0") or "0")
    cities = parse_cities_env()
    photos_per = PHOTOS_PER_PLACE

    print(
        f"FETCH_KINDS={','.join(sorted(kinds))} LIMIT={limit or 'ALL'} "
        f"PHOTOS={photos_per} CITIES={','.join(sorted(cities)) if cities else 'ALL'}"
    )
    print("Pexels kullanılmıyor — Google Places → Bunny")

    progress = load_progress()
    note = (
        f"Görseller Google Places (en fazla {photos_per}) → Bunny CDN. "
        "Uygulama Bunny URL kullanır."
    )
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if "gezi" in kinds:
        raw = filter_by_cities(list(master.get("geziler") or []), cities)
        if limit > 0:
            raw = raw[:limit]
        items = process_kind(
            raw,
            "gezi",
            api_key=api_key,
            bunny=bunny,
            progress=progress,
            photos_per=photos_per,
        )
        save_progress(progress)
        write_overlay(OUT_DIR / "geziler.json", items, note)

    if "yemek" in kinds:
        raw = filter_by_cities(list(master.get("yemekler") or []), cities)
        if limit > 0:
            raw = raw[:limit]
        items = process_kind(
            raw,
            "yemek",
            api_key=api_key,
            bunny=bunny,
            progress=progress,
            photos_per=photos_per,
        )
        save_progress(progress)
        write_overlay(OUT_DIR / "yemekler.json", items, note)

    if "konaklama" in kinds or "tesis" in kinds:
        raw = filter_by_cities(
            list(
                master.get("tesisler")
                or master.get("misafirhaneler")
                or []
            ),
            cities,
        )
        if limit > 0:
            raw = raw[:limit]
        print(f"Konaklama aday: {len(raw)} (kota ~{len(raw) * photos_per} foto)")
        items = process_kind(
            raw,
            "konaklama",
            api_key=api_key,
            bunny=bunny,
            progress=progress,
            photos_per=photos_per,
        )
        save_progress(progress)
        slim = [
            {
                "il": t.get("il", ""),
                "isim": t.get("isim", ""),
                "image_urls": t.get("image_urls") or [],
            }
            for t in items
            if t.get("image_urls")
        ]
        merged = merge_overlay_items(OUT_DIR / "tesisler_gorseller.json", slim)
        # Görselsiz eski kayıtları temizlemeden birleştir; sadece URL'li tut
        merged = [m for m in merged if m.get("image_urls")]
        write_overlay(OUT_DIR / "tesisler_gorseller.json", merged, note)

    save_progress(progress)
    print("Bitti. Overlay JSON'u rotalink-data'ya kopyalayıp push edin.")


if __name__ == "__main__":
    main()
