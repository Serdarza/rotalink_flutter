#!/usr/bin/env python3
"""Koordinatsız aday tesisler için Google Places Text Search ile konum bul — SADECE ÖNİZLEME.

Girdi : data_out/preview_report.json -> "koordinatsizlar"
Çıktı : data_out/geocode_preview.json, data_out/geocode_additions.json
Master'a yazmaz.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
import time
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data_out"
CACHE = OUT / "cache_places"
sys.path.insert(0, str(ROOT / "scripts"))
from discover_missing_tesisler import _read_key, http_json  # noqa: E402
from preview_missing_tesisler import (  # noqa: E402
    MASTER, MRec, Rec, compare, distinctive, haversine_m, norm_text, same_facility, tokens,
)

FIELDS = "places.id,places.displayName,places.formattedAddress,places.location,places.businessStatus"


def text_search(key: str, query: str, bias: tuple[float, float] | None) -> dict:
    CACHE.mkdir(parents=True, exist_ok=True)
    p = CACHE / (hashlib.sha1(query.encode("utf-8")).hexdigest() + ".json")
    if p.is_file():
        return json.loads(p.read_text(encoding="utf-8"))
    body: dict = {"textQuery": query, "languageCode": "tr", "regionCode": "TR", "pageSize": 5}
    if bias:
        body["locationBias"] = {"circle": {"center": {"latitude": bias[0], "longitude": bias[1]}, "radius": 50000.0}}
    data = http_json("POST", "https://places.googleapis.com/v1/places:searchText",
                     headers={"X-Goog-Api-Key": key, "X-Goog-FieldMask": FIELDS}, body=body)
    p.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    time.sleep(0.3)
    return data


def nominatim_search(query: str) -> dict:
    """OSM Nominatim (1 istek/sn). Google Places biçimine çevrilir."""
    import urllib.parse
    import urllib.request

    CACHE.mkdir(parents=True, exist_ok=True)
    p = CACHE / ("osm_" + hashlib.sha1(query.encode("utf-8")).hexdigest() + ".json")
    if p.is_file():
        return json.loads(p.read_text(encoding="utf-8"))
    url = "https://nominatim.openstreetmap.org/search?" + urllib.parse.urlencode(
        {"q": query, "format": "jsonv2", "countrycodes": "tr", "limit": 5, "addressdetails": 0, "accept-language": "tr"})
    req = urllib.request.Request(url, headers={"User-Agent": "RotalinkFacilityImport/1.0 (+https://rotalink.tr)"})
    with urllib.request.urlopen(req, timeout=60) as res:
        rows = json.loads(res.read().decode("utf-8"))
    time.sleep(1.1)
    data = {"places": [
        {"displayName": {"text": r.get("name") or ""}, "formattedAddress": r.get("display_name") or "",
         "location": {"latitude": float(r["lat"]), "longitude": float(r["lon"])}}
        for r in rows if r.get("name")
    ]}
    p.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return data


def main() -> None:
    key = _read_key()
    use_osm = "--osm" in sys.argv
    if not key and not use_osm:
        raise SystemExit("Google Places anahtarı yok")
    rep = json.loads((OUT / "preview_report.json").read_text(encoding="utf-8"))
    items = rep["koordinatsizlar"]
    master = json.loads(MASTER.read_text(encoding="utf-8"))["tesisler"]
    ms = [MRec(i, t) for i, t in enumerate(master)]
    by_il = defaultdict(list)
    for m in ms:
        by_il[m.il].append(m)
    center = {}
    for il, lst in by_il.items():
        la = sorted(m.lat for m in lst if m.lat is not None)
        ln = sorted(m.lng for m in lst if m.lng is not None)
        if la:
            center[il] = (la[len(la) // 2], ln[len(ln) // 2])

    found, not_found, dup, unc = [], [], [], []
    accepted_recs: list[Rec] = []
    for it in items:
        e = dict(it["aday"])
        il = e["il"]
        q = f"{e['isim']} {il}"
        try:
            data = nominatim_search(q) if use_osm else text_search(key, q, center.get(il))
        except Exception as ex:  # noqa: BLE001
            not_found.append({"il": il, "isim": e["isim"], "neden": f"API hata: {ex}"})
            continue
        want = distinctive(tokens(e["isim"], il))
        best = None
        for pl in data.get("places") or []:
            name = (pl.get("displayName") or {}).get("text", "")
            addr = pl.get("formattedAddress") or ""
            loc = pl.get("location") or {}
            if str(pl.get("businessStatus") or "").upper() == "CLOSED_PERMANENTLY":
                continue
            if "latitude" not in loc:
                continue
            lat, lng = float(loc["latitude"]), float(loc["longitude"])
            in_il = norm_text(il) in norm_text(addr)
            c = center.get(il)
            near = c is not None and haversine_m(lat, lng, c[0], c[1]) < 120000
            if not (in_il and near):
                continue
            got = distinctive(tokens(name, il))
            ov = len(want & got)
            same_kind = Rec("x", "", il, "", name, "", "", "", "", None, None, {}).cat == Rec("x", "", il, "", e["isim"], "", "", "", "", None, None, {}).cat
            if (want and ov >= max(1, (len(want) + 1) // 2) and same_kind) or (not want and same_kind):
                best = (name, addr, lat, lng, ov)
                break
        if not best:
            not_found.append({"il": il, "isim": e["isim"], "neden": "Google'da ilde isim/tür uyuşan sonuç yok"})
            continue
        name, addr, lat, lng, _ = best
        e["latitude"], e["longitude"] = lat, lng
        if not e.get("adres") or e["adres"].count(",") < 1:
            e["adres"] = re.sub(r",?\s*(Türkiye|Turkey)$", "", addr).strip()
        r = Rec("aday", "", il, "", e["isim"], e["telefon"], e["adres"], "", e["tip"], lat, lng, e)
        hit = None
        for m in by_il[il]:
            res = compare(r, m)
            if res:
                hit = (res, m.isim)
                if res[0] == "match":
                    break
        if hit and hit[0][0] == "match":
            dup.append({"il": il, "isim": e["isim"], "master": hit[1], "neden": hit[0][1], "google": name})
            continue
        if hit:
            unc.append({"il": il, "isim": e["isim"], "master": hit[1], "neden": hit[0][1], "google": name})
            continue
        if any(same_facility(r, a) for a in accepted_recs):
            dup.append({"il": il, "isim": e["isim"], "master": "(aynı turdaki başka aday)", "neden": "aday tekrar", "google": name})
            continue
        # aynı Google noktasına birden fazla aday düşmesin
        if any(a.lat is not None and haversine_m(lat, lng, a.lat, a.lng) < 30 for a in accepted_recs):
            unc.append({"il": il, "isim": e["isim"], "master": "-", "neden": "başka adayla aynı Google noktası", "google": name})
            continue
        accepted_recs.append(r)
        found.append({"entry": e, "google_isim": name, "google_adres": addr})

    (OUT / "geocode_additions.json").write_text(
        json.dumps([f["entry"] for f in found], ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT / "geocode_preview.json").write_text(json.dumps(
        {"bulunan": found, "bulunamayan": not_found, "zaten_var": dup, "belirsiz": unc},
        ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"toplam {len(items)} | eklenebilir {len(found)} | zaten var {len(dup)} | belirsiz {len(unc)} | bulunamadı {len(not_found)}")


if __name__ == "__main__":
    main()
