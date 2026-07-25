#!/usr/bin/env python3
"""image_fetch_progress.json → data_out/geziler.json + yemekler.json (kısmi entegrasyon).

Fetch script bitmeden, şu ana kadar bulunan görselleri overlay JSON'a yazar.
Fetch devam ederken güvenle çalışır (progress dosyasını sadece okur).

  python scripts/export_partial_images.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data_out"
PROGRESS = OUT_DIR / "image_fetch_progress.json"
DATA_REPO = ROOT.parent / "rotalink-data"

MASTER_CANDIDATES = [
    Path(os.environ.get("ROTALINK_MASTER", "")),
    ROOT / "master_database_updated.json",
    OUT_DIR / "master_database_fixed.json",
    DATA_REPO / "master_database_updated.json",
]


def load_master() -> dict:
    for p in MASTER_CANDIDATES:
        if p and p.is_file() and p.stat().st_size > 1000:
            print(f"Master: {p}")
            return json.loads(p.read_text(encoding="utf-8"))
    raise SystemExit("master bulunamadı")


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


def export_kind(raw_list: list, kind: str, progress: dict) -> list[dict]:
    out: list[dict] = []
    with_img = 0
    for raw in raw_list:
        item = normalize_item(raw)
        if item is None:
            continue
        pk = f"{kind}|{item['il']}|{item['isim']}"
        imgs = progress.get(pk) or []
        if isinstance(imgs, list) and imgs:
            item["image_urls"] = [u for u in imgs if isinstance(u, str) and u.strip()][:3]
            if item["image_urls"]:
                with_img += 1
        out.append(item)
    print(f"{kind}: {with_img}/{len(out)} görselli")
    return out


def main() -> None:
    if not PROGRESS.is_file():
        raise SystemExit(f"Progress yok: {PROGRESS}")
    progress = json.loads(PROGRESS.read_text(encoding="utf-8"))
    master = load_master()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    note = (
        "Kısmi görsel export (Pexels+Wiki). Fetch bitince tam listeyle güncellenir."
    )
    geziler = export_kind(master.get("geziler") or [], "gezi", progress)
    yemekler = export_kind(master.get("yemekler") or [], "yemek", progress)

    gezi_path = OUT_DIR / "geziler.json"
    yemek_path = OUT_DIR / "yemekler.json"
    gezi_path.write_text(
        json.dumps({"not": note, "items": geziler}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    yemek_path.write_text(
        json.dumps({"not": note, "items": yemekler}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"Yazıldı: {gezi_path}")
    print(f"Yazıldı: {yemek_path}")

    if DATA_REPO.is_dir():
        for src, name in ((gezi_path, "geziler.json"), (yemek_path, "yemekler.json")):
            dst = DATA_REPO / name
            dst.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
            print(f"Kopyalandı → {dst}")
        bust = DATA_REPO / "CACHE_BUST.txt"
        bust.write_text(
            f"partial-images-{__import__('time').strftime('%Y%m%d-%H%M%S')}\n",
            encoding="utf-8",
        )
        print(f"CACHE_BUST güncellendi: {bust}")
    else:
        print("rotalink-data klasörü yok — sadece data_out yazıldı")


if __name__ == "__main__":
    main()
