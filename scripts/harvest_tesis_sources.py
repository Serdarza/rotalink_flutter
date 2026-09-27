#!/usr/bin/env python3
"""Kaynak sitelerden kamu tesisi verisini indir (önbellekli) ve ayrıştır.

Master'a HİÇBİR ŞEY yazmaz. Çıktı: data_out/sources_parsed.json

Kaynaklar:
  - MEB öğretmenevi listesi (dhgm.meb.gov.tr)
  - kamutesisleri.com (sitemap-facilities + JSON-LD)
  - kamusosyaltesislerirehberi.com (sitemap + Angular ng-state)
"""

from __future__ import annotations

import hashlib
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data_out"
CACHE = OUT_DIR / "cache"
PARSED = OUT_DIR / "sources_parsed.json"
USER_AGENT = "RotalinkFacilityImport/1.0 (+https://rotalink.tr; data-sync)"
MEB_URL = "https://dhgm.meb.gov.tr/edestek/ogretmenevi/ogretmenevi_liste.aspx"
WORKERS = 6


def log(msg: str) -> None:
    print(msg, flush=True)


def cached_get(url: str, timeout: int = 60, retries: int = 3) -> str | None:
    CACHE.mkdir(parents=True, exist_ok=True)
    p = CACHE / (hashlib.sha1(url.encode("utf-8")).hexdigest() + ".html")
    if p.is_file() and p.stat().st_size > 0:
        return p.read_text(encoding="utf-8")
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=timeout) as res:
                raw = res.read().decode("utf-8", errors="replace")
            p.write_text(raw, encoding="utf-8")
            return raw
        except urllib.error.HTTPError as e:
            last = e
            if e.code == 404:
                return None
        except Exception as e:  # noqa: BLE001
            last = e
        time.sleep(1.5 * (attempt + 1))
    log(f"  HATA {url}: {last}")
    return None


def fetch_all(urls: list[str], label: str) -> dict[str, str | None]:
    out: dict[str, str | None] = {}
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(cached_get, u): u for u in urls}
        for i, f in enumerate(as_completed(futs), 1):
            out[futs[f]] = f.result()
            if i % 200 == 0 or i == len(urls):
                log(f"  {label}: {i}/{len(urls)}")
    return out


# ---------------- MEB ----------------

def parse_meb(raw: str) -> list[dict]:
    pattern = re.compile(
        r"lbl_il[^>]*>([^<]*)</span>.*?lbl_ilce[^>]*>([^<]*)</span>.*?"
        r"lbl_kurum[^>]*>([^<]*)</span>.*?lbl_telefon[^>]*>([^<]*)</span>",
        re.I | re.S,
    )
    rows = []
    for m in pattern.finditer(raw):
        rows.append(
            {
                "source": "meb",
                "url": MEB_URL,
                "il": html.unescape(m.group(1)).strip(),
                "ilce": html.unescape(m.group(2)).strip(),
                "isim": html.unescape(m.group(3)).strip(),
                "telefon": html.unescape(m.group(4)).strip(),
                "adres": "",
                "kurum": "Milli Eğitim Bakanlığı",
                "statu": "Öğretmenevi",
                "latitude": None,
                "longitude": None,
            }
        )
    return rows


# ---------------- kamutesisleri.com ----------------

def sitemap_locs(xml: str) -> list[str]:
    return [html.unescape(x.strip()) for x in re.findall(r"<loc>(.*?)</loc>", xml, re.S)]


def kamu_urls() -> list[str]:
    idx = cached_get("https://kamutesisleri.com/sitemap.xml") or ""
    urls: list[str] = []
    for sm in sitemap_locs(idx):
        if "sitemap-facilities" not in sm:
            continue
        urls.extend(sitemap_locs(cached_get(sm) or ""))
    return urls


def _jsonld_blocks(raw: str) -> list:
    out = []
    for m in re.finditer(r'<script[^>]+application/ld\+json[^>]*>(.*?)</script>', raw, re.S | re.I):
        try:
            d = json.loads(m.group(1))
        except Exception:  # noqa: BLE001
            continue
        if isinstance(d, list):
            out.extend(d)
        elif isinstance(d, dict) and "@graph" in d:
            out.extend(d["@graph"])
        else:
            out.append(d)
    return out


def parse_kamu(url: str, raw: str) -> dict | None:
    blocks = _jsonld_blocks(raw)
    node = None
    crumbs: list[str] = []
    faq_text = ""
    for b in blocks:
        if not isinstance(b, dict):
            continue
        typ = b.get("@type")
        if typ == "BreadcrumbList":
            crumbs = [str(x.get("name") or "") for x in b.get("itemListElement") or [] if isinstance(x, dict)]
        elif typ == "FAQPage":
            faq_text = json.dumps(b, ensure_ascii=False)
        elif node is None and b.get("name") and (b.get("address") or b.get("parentOrganization") or b.get("areaServed")):
            node = b
    if not node:
        return None
    addr = node.get("address") if isinstance(node.get("address"), dict) else {}
    parent = node.get("parentOrganization") or {}
    area = node.get("areaServed") or {}
    types = node.get("@type")
    types = types if isinstance(types, list) else [types]
    closed = bool(re.search(r"kal[ıi]c[ıi] olarak kapal[ıi]", faq_text + " " + str(node.get("description") or ""), re.I))
    if not closed and re.search(r"kal[ıi]c[ıi] olarak kapal[ıi]", raw, re.I):
        closed = True
    lat = lng = None
    geo = node.get("geo") or {}
    try:
        if geo.get("latitude") is not None:
            lat, lng = float(geo["latitude"]), float(geo["longitude"])
    except (TypeError, ValueError):
        lat = lng = None
    if lat is None:
        gm = re.search(r"!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)", raw) or re.search(
            r"@(-?\d{1,2}\.\d{4,}),(-?\d{1,3}\.\d{4,})", raw
        )
        if gm:
            lat, lng = float(gm.group(1)), float(gm.group(2))
    parts = urllib.parse.urlparse(url).path.strip("/").split("/")
    il = str(addr.get("addressRegion") or "").strip()
    if not il and isinstance(area, dict):
        il = str(area.get("name") or "").strip()
    if not il and len(crumbs) > 1:
        il = crumbs[1]
    ilce = str(addr.get("addressLocality") or "").strip() or (crumbs[2] if len(crumbs) > 2 else "")
    return {
        "source": "kamutesisleri",
        "url": url,
        "closed": closed,
        "types": [str(t) for t in types if t],
        "il": il,
        "ilce": ilce,
        "isim": html.unescape(str(node.get("name") or "")).strip(),
        "telefon": str(node.get("telephone") or "").strip(),
        "adres": html.unescape(str(addr.get("streetAddress") or "")).strip(),
        "kurum": str(parent.get("name") or "").strip() if isinstance(parent, dict) else "",
        "statu": parts[2] if len(parts) >= 3 else "",
        "latitude": lat,
        "longitude": lng,
    }


# ---------------- kamusosyaltesislerirehberi.com ----------------

def ksr_urls() -> list[str]:
    xml = cached_get("https://kamusosyaltesislerirehberi.com/sitemap.xml") or ""
    return [u for u in sitemap_locs(xml) if "/tesis/" in u]


def parse_ksr(url: str, raw: str) -> list[dict]:
    m = re.search(r'<script id="ng-state" type="application/json">(.*?)</script>', raw, re.S)
    if not m:
        return []
    try:
        st = json.loads(m.group(1))
    except Exception:  # noqa: BLE001
        return []
    rows = []
    for v in st.values():
        if not (isinstance(v, dict) and isinstance(v.get("b"), dict)):
            continue
        veri = v["b"].get("veri")
        if not isinstance(veri, list):
            continue
        for d in veri:
            if not isinstance(d, dict) or not d.get("ad"):
                continue
            try:
                lat = float(d.get("latitude")) if d.get("latitude") not in (None, "") else None
                lng = float(d.get("longitude")) if d.get("longitude") not in (None, "") else None
            except (TypeError, ValueError):
                lat = lng = None
            rows.append(
                {
                    "source": "kamusosyal",
                    "url": url,
                    "il": str(d.get("il") or "").strip(),
                    "ilce": str(d.get("ilce") or "").strip(),
                    "isim": str(d.get("ad") or "").strip(),
                    "telefon": str(d.get("telefon1") or "").strip(),
                    "telefon2": str(d.get("telefon2") or "").strip(),
                    "adres": str(d.get("adres") or "").strip(),
                    "kurum": str(d.get("kurum") or "").strip(),
                    "statu": str(d.get("statu") or "").strip(),
                    "latitude": lat,
                    "longitude": lng,
                }
            )
    return rows


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    result: dict = {"meb": [], "kamutesisleri": [], "kamusosyal": [], "kamusosyal_slug_only": [], "errors": []}

    log("MEB...")
    meb_raw = cached_get(MEB_URL) or ""
    result["meb"] = parse_meb(meb_raw)
    log(f"  MEB satır: {len(result['meb'])}")

    log("kamutesisleri.com...")
    ku = kamu_urls()
    log(f"  URL: {len(ku)}")
    pages = fetch_all(ku, "kamutesisleri")
    for u in ku:
        raw = pages.get(u)
        row = parse_kamu(u, raw) if raw else None
        if row:
            result["kamutesisleri"].append(row)
        else:
            result["errors"].append({"source": "kamutesisleri", "url": u})
    log(f"  ayrıştırılan: {len(result['kamutesisleri'])}")

    log("kamusosyaltesislerirehberi.com...")
    su = ksr_urls()
    log(f"  URL: {len(su)}")
    pages = fetch_all(su, "kamusosyal")
    for u in su:
        raw = pages.get(u)
        rows = parse_ksr(u, raw) if raw else []
        if rows:
            result["kamusosyal"].extend(rows)
        else:
            parts = urllib.parse.urlparse(u).path.split("/tesis/", 1)[-1].split("/", 1)
            result["errors"].append({"source": "kamusosyal", "url": u})
            result["kamusosyal_slug_only"].append(
                {
                    "source": "kamusosyal",
                    "url": u,
                    "il_slug": parts[0],
                    "isim": urllib.parse.unquote(parts[1] if len(parts) > 1 else "").replace("-", " "),
                }
            )
    log(f"  ayrıştırılan: {len(result['kamusosyal'])}")

    PARSED.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"Hata/boş sayfa: {len(result['errors'])}")
    log(f"Yazıldı: {PARSED}")


if __name__ == "__main__":
    sys.exit(main())
