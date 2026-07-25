"""Bunny'deki görsellerde yeniden sıkıştırma kazancını ölçer (yalnızca ölçüm)."""

from __future__ import annotations

import io
import json
import random
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT / "data_out" / "tesisler_gorseller.json"
SAMPLE = 14
UA = {"User-Agent": "RotalinkBench/1.0"}


def fetch(url: str) -> bytes:
    safe = urllib.parse.quote(url, safe=":/?&=%")
    req = urllib.request.Request(safe, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def encode(img: Image.Image, max_h: int, fmt: str, quality: int) -> int:
    im = img.copy()
    if im.height > max_h:
        ratio = max_h / im.height
        im = im.resize((max(1, round(im.width * ratio)), max_h), Image.LANCZOS)
    if im.mode not in ("RGB", "L"):
        im = im.convert("RGB")
    buf = io.BytesIO()
    if fmt == "JPEG":
        im.save(
            buf,
            "JPEG",
            quality=quality,
            optimize=True,
            progressive=True,
            subsampling=2,
        )
    else:
        im.save(buf, "WEBP", quality=quality, method=6)
    return buf.tell()


def main() -> None:
    data = json.loads(OVERLAY.read_text(encoding="utf-8"))
    urls = [u for e in data["items"] for u in e.get("image_urls", [])]
    random.seed(7)
    picks = random.sample(urls, SAMPLE)

    variants = [
        ("jpeg960 q78", 960, "JPEG", 78),
        ("jpeg960 q72", 960, "JPEG", 72),
        ("jpeg800 q75", 800, "JPEG", 75),
        ("webp960 q80", 960, "WEBP", 80),
        ("webp800 q78", 800, "WEBP", 78),
    ]
    totals = {name: 0 for name, *_ in variants}
    orig_total = 0
    ok = 0

    for url in picks:
        try:
            blob = fetch(url)
            img = Image.open(io.BytesIO(blob))
            img.load()
        except Exception as exc:
            print("ERR", exc, url[-40:])
            continue
        ok += 1
        orig_total += len(blob)
        row = [f"{img.width}x{img.height}", f"orj {len(blob)//1024}KB"]
        for name, h, fmt, q in variants:
            size = encode(img, h, fmt, q)
            totals[name] += size
            row.append(f"{name} {size//1024}KB")
        print(" | ".join(row))

    if not ok:
        return
    print(f"\n{ok} görsel — toplam orijinal {orig_total//1024} KB "
          f"(ort {orig_total//ok//1024} KB)")
    for name, *_ in variants:
        t = totals[name]
        print(f"  {name:12} {t//1024:6} KB  ort {t//ok//1024:4} KB  "
              f"kazanç %{100 - round(t * 100 / orig_total)}")


if __name__ == "__main__":
    main()
