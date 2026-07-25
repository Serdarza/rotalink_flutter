#!/usr/bin/env python3
"""Bunny'deki konaklama görsellerini yeniden sıkıştırır (WebP, aynı URL).

Akış (her görsel için):
  1. CDN'den orijinali indir, data_out/bunny_backup/ altına yedekle.
  2. Maks. 800px yükseklik + WebP q78 olarak yeniden kodla.
  3. Yeni dosya belirgin küçükse aynı Bunny yoluna üzerine yaz
     (uzantı .jpg kalır; Flutter formatı dosya içeriğinden çözer).

Not: Yükleme sonrası Bunny pull zone önbelleği panelden "Purge Cache" ile
temizlenmelidir; yoksa CDN eski dosyayı servis etmeye devam eder.

Ortam değişkenleri:
  OPT_CITIES=Adana,Ankara   (boş = tüm iller)
  OPT_MAX_HEIGHT=800
  OPT_QUALITY=78
  OPT_MIN_GAIN=0.10         (en az %10 küçülmezse dokunma)
  OPT_DRY_RUN=1             (yükleme yapmadan raporla)
"""

from __future__ import annotations

import io
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data_out"
OVERLAY = OUT_DIR / "tesisler_gorseller.json"
BACKUP_DIR = OUT_DIR / "bunny_backup"
STATE = OUT_DIR / "bunny_optimize_progress.json"

UA = "RotalinkOptimize/1.0 (rotalink.tr)"
MAX_HEIGHT = int(os.environ.get("OPT_MAX_HEIGHT", "800"))
QUALITY = int(os.environ.get("OPT_QUALITY", "78"))
MIN_GAIN = float(os.environ.get("OPT_MIN_GAIN", "0.10"))
DRY_RUN = os.environ.get("OPT_DRY_RUN", "").strip() == "1"


def fold_tr(s: str) -> str:
    t = (s or "").strip().casefold()
    for a, b in (("ı", "i"), ("i̇", "i"), ("ş", "s"), ("ğ", "g"),
                 ("ü", "u"), ("ö", "o"), ("ç", "c")):
        t = t.replace(a, b)
    return t


def load_bunny() -> dict:
    cfg = ROOT / "scripts" / ".bunny_config.json"
    return json.loads(cfg.read_text(encoding="utf-8"))


def load_state() -> dict:
    if STATE.is_file():
        return json.loads(STATE.read_text(encoding="utf-8"))
    return {}


def save_state(state: dict) -> None:
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=1),
                     encoding="utf-8")


def fetch(url: str) -> bytes:
    safe = urllib.parse.quote(url, safe=":/?&=%")
    req = urllib.request.Request(safe, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def recompress(blob: bytes) -> bytes | None:
    try:
        img = Image.open(io.BytesIO(blob))
        img.load()
    except Exception:
        return None
    if img.height > MAX_HEIGHT:
        ratio = MAX_HEIGHT / img.height
        img = img.resize((max(1, round(img.width * ratio)), MAX_HEIGHT),
                         Image.LANCZOS)
    if img.mode != "RGB":
        img = img.convert("RGB")
    buf = io.BytesIO()
    try:
        img.save(buf, "WEBP", quality=QUALITY, method=6)
    except Exception:
        return None
    return buf.getvalue()


def bunny_overwrite(bunny: dict, cdn_url: str, content: bytes) -> None:
    zone = bunny["storage_zone"].strip()
    password = bunny["storage_password"].strip()
    endpoint = (bunny.get("storage_endpoint") or "storage.bunnycdn.com") \
        .strip().removeprefix("https://").removesuffix("/")
    cdn_base = bunny["cdn_base_url"].strip().rstrip("/")

    if not cdn_url.startswith(cdn_base + "/"):
        raise RuntimeError(f"CDN taban uyuşmadı: {cdn_url}")
    rel = cdn_url[len(cdn_base) + 1:]

    enc_zone = urllib.parse.quote(zone, safe="")
    enc_path = "/".join(urllib.parse.quote(p, safe="") for p in rel.split("/"))
    url = f"https://{endpoint}/{enc_zone}/{enc_path}"

    req = urllib.request.Request(
        url,
        data=content,
        method="PUT",
        headers={
            "AccessKey": password,
            "Content-Type": "image/webp",
            "User-Agent": UA,
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        if resp.status not in (200, 201):
            raise RuntimeError(f"Bunny upload status {resp.status}")


def backup_path(cdn_url: str) -> Path:
    rel = urllib.parse.urlparse(cdn_url).path.lstrip("/")
    return BACKUP_DIR / rel


def main() -> None:
    bunny = load_bunny()
    data = json.loads(OVERLAY.read_text(encoding="utf-8"))
    cities_raw = (os.environ.get("OPT_CITIES") or "").strip()
    cities = {fold_tr(c) for c in cities_raw.split(",") if c.strip()} or None

    urls: list[str] = []
    for item in data["items"]:
        if cities and fold_tr(str(item.get("il") or "")) not in cities:
            continue
        urls.extend(item.get("image_urls") or [])

    state = load_state()
    print(f"Hedef: {len(urls)} gorsel  (iller: {cities_raw or 'HEPSI'}) "
          f"{'[DRY RUN]' if DRY_RUN else ''}")
    print(f"Ayar: WebP maks {MAX_HEIGHT}px q{QUALITY}, min kazanc %{MIN_GAIN*100:.0f}")

    done = skipped = failed = 0
    total_old = total_new = 0

    for i, url in enumerate(urls, 1):
        prev = state.get(url)
        if isinstance(prev, dict) and prev.get("status") in ("done", "skipped"):
            done += 1 if prev["status"] == "done" else 0
            skipped += 1 if prev["status"] == "skipped" else 0
            total_old += prev.get("old", 0)
            total_new += prev.get("new", prev.get("old", 0))
            continue
        try:
            blob = fetch(url)
        except Exception as exc:
            print(f"[{i}/{len(urls)}] indirme hata: {exc} — {url[-50:]}")
            state[url] = {"status": "fetch_error", "err": str(exc)[:200]}
            failed += 1
            continue

        # WebP zaten işlenmişse tekrar dokunma
        if blob[:4] == b"RIFF" and blob[8:12] == b"WEBP":
            state[url] = {"status": "skipped", "old": len(blob), "reason": "webp"}
            skipped += 1
            total_old += len(blob)
            total_new += len(blob)
            continue

        bp = backup_path(url)
        if not bp.is_file():
            bp.parent.mkdir(parents=True, exist_ok=True)
            bp.write_bytes(blob)

        new_blob = recompress(blob)
        if new_blob is None:
            print(f"[{i}/{len(urls)}] decode edilemedi — {url[-50:]}")
            state[url] = {"status": "decode_error"}
            failed += 1
            continue

        gain = 1 - len(new_blob) / len(blob)
        total_old += len(blob)
        if gain < MIN_GAIN:
            state[url] = {"status": "skipped", "old": len(blob),
                          "new": len(blob), "reason": "kazanç az"}
            skipped += 1
            total_new += len(blob)
            continue

        total_new += len(new_blob)
        if DRY_RUN:
            print(f"[{i}/{len(urls)}] {len(blob)//1024}->{len(new_blob)//1024} KB "
                  f"(%{gain*100:.0f}) [dry] {url.split('/')[-1]}")
            state[url] = {"status": "dry", "old": len(blob), "new": len(new_blob)}
            continue

        try:
            bunny_overwrite(bunny, url, new_blob)
        except Exception as exc:
            print(f"[{i}/{len(urls)}] upload hata: {exc}")
            state[url] = {"status": "upload_error", "err": str(exc)[:200]}
            failed += 1
            continue

        state[url] = {"status": "done", "old": len(blob), "new": len(new_blob)}
        done += 1
        name = url.split("/")[-1]
        try:
            print(f"[{i}/{len(urls)}] {len(blob)//1024}->{len(new_blob)//1024} KB "
                  f"(%{gain*100:.0f}) {name}")
        except UnicodeEncodeError:
            print(f"[{i}/{len(urls)}] {len(blob)//1024}->{len(new_blob)//1024} KB "
                  f"(%{gain*100:.0f})")

        if i % 10 == 0:
            save_state(state)
        time.sleep(0.05)

    save_state(state)
    print(f"\nBitti: {done} yazıldı, {skipped} atlandı, {failed} hata")
    if total_old:
        print(f"Toplam {total_old//1024//1024} MB -> {total_new//1024//1024} MB "
              f"(kazanc %{100 - round(total_new*100/total_old)})")
    if not DRY_RUN and done:
        print("UYARI: Bunny panelinde pull zone icin 'Purge Cache' yapilmali.")


if __name__ == "__main__":
    main()
