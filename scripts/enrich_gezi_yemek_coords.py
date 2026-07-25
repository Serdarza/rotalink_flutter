#!/usr/bin/env python3
"""Gezi / yemek için doğrulanmış koordinat (enlem/boylam).

Kaynak: Photon (öncelik) → Nominatim (yedek).
Doğrulama: Türkiye bbox + mümkünse il/province eşleşmesi.

Kullanım:
  python scripts/enrich_gezi_yemek_coords.py
  set FETCH_KINDS=gezi
  set FETCH_LIMIT=20
  set FORCE_REFRESH=1

Çıktı:
  data_out/gezi_yemek_coords_progress.json
  data_out/geziler.json / yemekler.json  (enlem/boylam + varsa görseller)
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
PROGRESS = OUT_DIR / "gezi_yemek_coords_progress.json"
IMAGE_PROGRESS = OUT_DIR / "image_fetch_progress.json"
MASTER_CANDIDATES = [
    Path(os.environ.get("ROTALINK_MASTER", "")),
    ROOT / "master_database_updated.json",
]

USER_AGENT = "RotalinkCoordsBot/1.0 (rotalink.tr; contact=dev)"
PHOTON_SLEEP = float(os.environ.get("PHOTON_SLEEP", "0.35"))
NOMINATIM_SLEEP = float(os.environ.get("NOMINATIM_SLEEP", "1.25"))
TR_BBOX = "25.5,35.8,45.0,42.3"  # minLon,minLat,maxLon,maxLat


def http_get_json(url: str, *, retries_429: bool = True) -> dict | list | None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=25) as res:
            return json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 429 and retries_429:
            print("  429 — 45s…")
            time.sleep(45)
            return http_get_json(url, retries_429=False)
        print(f"  HTTP {e.code}: {e}")
        return None
    except Exception as e:
        print(f"  HTTP hata: {e}")
        return None


def load_master() -> dict:
    for p in MASTER_CANDIDATES:
        if p and p.is_file() and p.stat().st_size > 1000:
            print(f"Master: {p}")
            return json.loads(p.read_text(encoding="utf-8"))
    raise SystemExit("master_database bulunamadı.")


def norm_key(s: str) -> str:
    s = re.sub(r"\s+", " ", (s or "").strip()).casefold()
    return s.translate(str.maketrans("çğıöşüâîû", "cgiosuaiu"))


def in_turkey(lat: float, lon: float) -> bool:
    return 35.5 <= lat <= 42.5 and 25.0 <= lon <= 45.5


def province_ok(props_or_addr: dict, il: str) -> bool:
    il_n = norm_key(il)
    if not il_n:
        return True
    for key in ("state", "province", "county", "city", "district"):
        v = norm_key(str(props_or_addr.get(key) or ""))
        if not v:
            continue
        if v == il_n or il_n in v or v in il_n:
            return True
    return False


def load_progress() -> dict:
    if PROGRESS.is_file():
        return json.loads(PROGRESS.read_text(encoding="utf-8"))
    return {}


def save_progress(progress: dict) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PROGRESS.write_text(
        json.dumps(progress, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def load_image_progress() -> dict:
    if IMAGE_PROGRESS.is_file():
        try:
            return json.loads(IMAGE_PROGRESS.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def photon_search(query: str, il: str) -> tuple[float, float, str] | None:
    q = re.sub(r"\s+", " ", query.replace(",", " ")).strip()
    url = (
        "https://photon.komoot.io/api/"
        f"?q={urllib.parse.quote(q)}&limit=8&bbox={TR_BBOX}"
    )
    time.sleep(PHOTON_SLEEP)
    data = http_get_json(url)
    if not isinstance(data, dict):
        return None
    features = data.get("features") or []
    best_any: tuple[float, float, str] | None = None
    for f in features:
        if not isinstance(f, dict):
            continue
        props = f.get("properties") if isinstance(f.get("properties"), dict) else {}
        geom = f.get("geometry") if isinstance(f.get("geometry"), dict) else {}
        coords = geom.get("coordinates")
        if not isinstance(coords, list) or len(coords) < 2:
            continue
        try:
            lon = float(coords[0])
            lat = float(coords[1])
        except (TypeError, ValueError):
            continue
        if not in_turkey(lat, lon):
            continue
        cc = str(props.get("countrycode") or "").upper()
        if cc and cc != "TR":
            continue
        name = str(props.get("name") or props.get("street") or query)
        cand = (lat, lon, f"photon:{name}")
        if province_ok(props, il):
            return cand
        if best_any is None:
            best_any = cand
    # İl eşleşmesi yoksa ama tek TR sonucu varsa kabul (bazı POI state boş)
    return best_any


def nominatim_search(query: str, il: str) -> tuple[float, float, str] | None:
    params = urllib.parse.urlencode(
        {
            "q": query,
            "format": "json",
            "limit": 5,
            "addressdetails": 1,
            "countrycodes": "tr",
            "accept-language": "tr",
        }
    )
    url = f"https://nominatim.openstreetmap.org/search?{params}"
    time.sleep(NOMINATIM_SLEEP)
    data = http_get_json(url)
    if not isinstance(data, list):
        return None
    best_any = None
    for item in data:
        if not isinstance(item, dict):
            continue
        try:
            lat = float(item.get("lat"))
            lon = float(item.get("lon"))
        except (TypeError, ValueError):
            continue
        if not in_turkey(lat, lon):
            continue
        addr = item.get("address") if isinstance(item.get("address"), dict) else {}
        name = str(item.get("display_name") or query)[:80]
        cand = (lat, lon, f"nominatim:{name}")
        if province_ok(addr, il):
            return cand
        if best_any is None:
            best_any = cand
    return best_any


def resolve_coords(
    isim: str,
    il: str,
    adres: str,
    kind: str,
    *,
    allow_nominatim: bool,
) -> dict | None:
    queries: list[str] = []
    if isim and il:
        queries.append(f"{isim} {il} Türkiye")
        queries.append(f"{isim} {il}")
    if adres and il and len(adres) < 80 and "tüm" not in adres.casefold():
        queries.append(f"{isim} {adres} {il}")
    if kind == "yemek" and il:
        queries.append(f"{isim} {il} restoran")

    seen: set[str] = set()
    for q in queries:
        qn = q.strip().lower()
        if not qn or qn in seen:
            continue
        seen.add(qn)
        hit = photon_search(q, il)
        if hit:
            lat, lon, src = hit
            return {
                "enlem": round(lat, 7),
                "boylam": round(lon, 7),
                "source": src,
                "query": q,
            }

    if allow_nominatim:
        for q in list(queries)[:2]:
            hit = nominatim_search(q, il)
            if hit:
                lat, lon, src = hit
                return {
                    "enlem": round(lat, 7),
                    "boylam": round(lon, 7),
                    "source": src,
                    "query": q,
                }
    return None


def write_kind_json(
    path: Path,
    items_raw: list,
    kind: str,
    progress: dict,
    image_progress: dict,
) -> None:
    out: list[dict] = []
    for raw in items_raw:
        if not isinstance(raw, dict):
            continue
        isim = str(raw.get("isim") or "").strip()
        il = str(raw.get("il") or "").strip()
        if not isim and not il:
            continue
        pk = f"{kind}|{il}|{isim}"
        row = {
            "il": il,
            "isim": isim,
            "adres": str(raw.get("adres") or "").strip(),
            "aciklama": str(raw.get("aciklama") or "").strip(),
        }
        c = progress.get(pk)
        if isinstance(c, dict) and c.get("enlem") is not None:
            row["enlem"] = c["enlem"]
            row["boylam"] = c["boylam"]
        imgs = image_progress.get(pk)
        if isinstance(imgs, list) and imgs:
            row["image_urls"] = imgs[:3]
        out.append(row)

    path.write_text(
        json.dumps(
            {
                "not": "Koordinat: Photon/Nominatim, il doğrulamalı. Görseller image progress.",
                "items": out,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    ok = sum(1 for x in out if x.get("enlem") is not None)
    print(f"Yazıldı: {path} ({ok}/{len(out)} koordinatlı)")


def main() -> None:
    master = load_master()
    kinds_env = (os.environ.get("FETCH_KINDS") or "gezi,yemek").strip().lower()
    kinds = {k.strip() for k in kinds_env.split(",") if k.strip()}
    force = (os.environ.get("FORCE_REFRESH") or "").strip() in {"1", "true", "yes"}
    allow_nominatim = (os.environ.get("USE_NOMINATIM") or "0").strip() in {
        "1",
        "true",
        "yes",
    }
    print(
        f"FETCH_KINDS={','.join(sorted(kinds))} FORCE={force} "
        f"NOMINATIM={allow_nominatim}"
    )

    limit = int(os.environ.get("FETCH_LIMIT", "0") or "0")
    progress = {} if force else load_progress()
    image_progress = load_image_progress()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    def run_list(raw_list: list, kind: str) -> None:
        items = [x for x in raw_list if isinstance(x, dict)]
        work = items[:limit] if limit > 0 else items
        total = len(work)
        found = 0
        for i, raw in enumerate(work):
            isim = str(raw.get("isim") or "").strip()
            il = str(raw.get("il") or "").strip()
            adres = str(raw.get("adres") or "").strip()
            pk = f"{kind}|{il}|{isim}"
            prev = progress.get(pk)
            if (
                not force
                and isinstance(prev, dict)
                and prev.get("enlem") is not None
                and prev.get("boylam") is not None
            ):
                found += 1
                continue

            print(f"[{kind} {i+1}/{total}] {il} — {isim}")
            hit = resolve_coords(
                isim, il, adres, kind, allow_nominatim=allow_nominatim
            )
            if hit:
                progress[pk] = hit
                found += 1
                print(f"  → {hit['enlem']}, {hit['boylam']} ({hit['source']})")
            else:
                progress[pk] = {"enlem": None, "boylam": None, "source": "miss"}
                print("  → bulunamadı")

            if (i + 1) % 15 == 0:
                save_progress(progress)
                print(f"  … progress ({i+1})")

        save_progress(progress)
        out_name = "geziler.json" if kind == "gezi" else "yemekler.json"
        write_kind_json(
            OUT_DIR / out_name,
            items,
            kind,
            progress,
            image_progress,
        )
        print(f"{kind}: bu turda/toplam koordinatlı progress≈{found}/{total}")

    if "gezi" in kinds:
        run_list(master.get("geziler") or [], "gezi")
    if "yemek" in kinds:
        run_list(master.get("yemekler") or [], "yemek")

    print("Bitti.")


if __name__ == "__main__":
    main()
