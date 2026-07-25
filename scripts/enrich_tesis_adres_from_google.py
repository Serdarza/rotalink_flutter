#!/usr/bin/env python3
"""Konaklama adreslerini Google Place Details (Essentials) ile düzelt.

- Kayıtlı place_id kullanır (google_bunny_progress.json) → Text Search yok
- Sadece formattedAddress + addressComponents (ücretsiz kota: 10k/ay)
- Çıktı: data_out/tesisler_adres.json (uygulama GitHub overlay; runtime Google yok)

  python scripts/enrich_tesis_adres_from_google.py
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data_out"
SCRIPTS = ROOT / "scripts"
PROGRESS_PLACES = OUT_DIR / "google_bunny_progress.json"
PROGRESS_ADRES = OUT_DIR / "google_adres_progress.json"
OUT_FILE = OUT_DIR / "tesisler_adres.json"

MASTER_CANDIDATES = [
    Path(os.environ.get("ROTALINK_MASTER", "")),
    ROOT / "master_database_updated.json",
    OUT_DIR / "master_database_fixed.json",
    ROOT.parent / "rotalink-data" / "master_database_updated.json",
]

USER_AGENT = "RotalinkAdresEnrich/1.0 (rotalink.tr)"
GOOGLE_SLEEP = float(os.environ.get("GOOGLE_SLEEP", "0.25"))


def _read_key() -> str:
    key = os.environ.get("GOOGLE_PLACES_API_KEY", "").strip()
    if key:
        return key
    p = SCRIPTS / ".google_places_key"
    if p.is_file():
        return p.read_text(encoding="utf-8").strip().splitlines()[0].strip()
    return ""


def load_master() -> dict:
    for p in MASTER_CANDIDATES:
        if p and p.is_file() and p.stat().st_size > 1000:
            print(f"Master: {p}")
            return json.loads(p.read_text(encoding="utf-8"))
    raise SystemExit("master_database bulunamadı")


def load_json(path: Path, default):
    if path.is_file():
        return json.loads(path.read_text(encoding="utf-8"))
    return default


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


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


def place_key(il: str, isim: str) -> str:
    return f"{fold_tr(il)}|{fold_tr(isim)}"


def http_json(url: str, *, headers: dict, timeout: int = 45) -> dict:
    req = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, **headers}, method="GET"
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            raw = res.read()
            return json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code}: {body[:400]}") from e


def place_details(api_key: str, place_id: str) -> dict:
    """Place Details Essentials — formattedAddress + addressComponents."""
    pid = place_id.strip()
    if pid.startswith("places/"):
        pid = pid[len("places/") :]
    enc = urllib.parse.quote(pid, safe="")
    url = f"https://places.googleapis.com/v1/places/{enc}"
    headers = {
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": "id,formattedAddress,shortFormattedAddress,addressComponents",
    }
    return http_json(url, headers=headers)


def extract_ilce(components: list) -> str:
    """Türkiye için ilçe: administrative_area_level_2, yoksa locality."""
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
        if by_type.get(key):
            return by_type[key]
    return ""


def clean_adres(s: str) -> str:
    t = (s or "").strip()
    # Ülke tekrarını kısalt
    for suf in (", Türkiye", ", Turkey", " Türkiye", " Turkey"):
        if t.endswith(suf):
            t = t[: -len(suf)].rstrip(" ,")
    return t


def main() -> None:
    api_key = _read_key()
    if not api_key:
        raise SystemExit("Google Places API key yok (scripts/.google_places_key)")

    master = load_master()
    tesisler = list(master.get("tesisler") or master.get("misafirhaneler") or [])
    places_prog = load_json(PROGRESS_PLACES, {})
    adres_prog = load_json(PROGRESS_ADRES, {})
    old_overlay = load_json(OUT_FILE, {"items": []})
    old_by_key = {}
    for it in old_overlay.get("items") or []:
        if isinstance(it, dict):
            old_by_key[place_key(str(it.get("il") or ""), str(it.get("isim") or ""))] = it

    # place_id haritası
    id_by_key: dict[str, str] = {}
    for k, v in places_prog.items():
        if not str(k).startswith("konaklama|"):
            continue
        if not isinstance(v, dict):
            continue
        parts = str(k).split("|", 2)
        if len(parts) < 3:
            continue
        _, il, isim = parts
        pid = str(v.get("place_id") or "").strip()
        if pid:
            id_by_key[place_key(il, isim)] = pid

    limit = int(os.environ.get("FETCH_LIMIT", "0") or "0")
    print(f"Tesis: {len(tesisler)} | place_id: {len(id_by_key)} | LIMIT={limit or 'ALL'}")
    print("SKU: Place Details Essentials (formattedAddress) — Text Search yok")

    out_items: list[dict] = []
    ok = skip = fail = no_id = 0

    for i, raw in enumerate(tesisler):
        if not isinstance(raw, dict):
            continue
        il = str(raw.get("il") or "").strip()
        isim = str(raw.get("isim") or "").strip()
        if not isim:
            continue
        pk = place_key(il, isim)
        prev = adres_prog.get(pk) if isinstance(adres_prog.get(pk), dict) else None
        if prev and prev.get("adres"):
            out_items.append(
                {
                    "il": il,
                    "isim": isim,
                    "adres": prev["adres"],
                    "ilce": prev.get("ilce") or "",
                }
            )
            skip += 1
            continue

        place_id = id_by_key.get(pk, "")
        old = old_by_key.get(pk) or {}

        if not place_id:
            # Google'a gitme — eski overlay / master adres kalsın
            adres = str(old.get("adres") or raw.get("adres") or "").strip()
            ilce = str(old.get("ilce") or raw.get("ilce") or "").strip()
            out_items.append({"il": il, "isim": isim, "adres": adres, "ilce": ilce})
            no_id += 1
            continue

        if limit > 0 and (ok + fail) >= limit:
            adres = str(old.get("adres") or raw.get("adres") or "").strip()
            ilce = str(old.get("ilce") or "").strip()
            out_items.append({"il": il, "isim": isim, "adres": adres, "ilce": ilce})
            continue

        print(f"[{i+1}/{len(tesisler)}] {isim} / {il}")
        try:
            data = place_details(api_key, place_id)
            time.sleep(GOOGLE_SLEEP)
            adres = clean_adres(
                str(
                    data.get("formattedAddress")
                    or data.get("shortFormattedAddress")
                    or ""
                )
            )
            ilce = extract_ilce(data.get("addressComponents") or [])
            if not adres:
                raise RuntimeError("formattedAddress boş")
            entry = {"il": il, "isim": isim, "adres": adres, "ilce": ilce}
            out_items.append(entry)
            adres_prog[pk] = {
                "adres": adres,
                "ilce": ilce,
                "place_id": place_id,
            }
            ok += 1
            print(f"  OK → {adres}" + (f" | {ilce}" if ilce else ""))
        except Exception as e:
            print(f"  HATA: {e}")
            fail += 1
            adres = str(old.get("adres") or raw.get("adres") or "").strip()
            ilce = str(old.get("ilce") or "").strip()
            out_items.append({"il": il, "isim": isim, "adres": adres, "ilce": ilce})
            adres_prog[pk] = {
                "adres": adres,
                "ilce": ilce,
                "place_id": place_id,
                "error": str(e)[:200],
            }

        if (ok + fail) % 20 == 0:
            save_json(PROGRESS_ADRES, adres_prog)

    note = (
        "Google Place Details Essentials (formattedAddress) ile doğrulandı. "
        "Uygulama yalnızca bu JSON'u kullanır; runtime Google'a gitmez."
    )
    save_json(OUT_FILE, {"not": note, "items": out_items})
    save_json(PROGRESS_ADRES, adres_prog)
    print(
        f"Bitti. Yazıldı: {OUT_FILE} ({len(out_items)} kayıt) "
        f"yeni={ok} cache={skip} no_place_id={no_id} hata={fail}"
    )


if __name__ == "__main__":
    main()
