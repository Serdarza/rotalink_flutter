#!/usr/bin/env python3
"""Resmi öğretmenevi sitelerinde fiyat/ücret/tarife içeriklerini topla (ham veri).

Girdi : data_out/fiyat/meb_sites.json
Çıktı : data_out/fiyat/meb_pages.json  (host -> sayfalar: başlık, tarih, metin, tablolar, ekler)
        data_out/fiyat/files/            (indirilen PDF/Word/Excel/görsel ekler)
Veritabanına yazmaz.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data_out" / "fiyat"
FILES = OUT / "files"
HTML = OUT / "html"
sys.path.insert(0, str(ROOT / "scripts"))
from preview_missing_tesisler import fold_tr  # noqa: E402

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"
KEY = re.compile(r"fiyat|ucret|tarife|konaklama|oda\s*fiyat|oda\s*ucret", re.I)
ATTACH = re.compile(r"\.(pdf|docx?|xlsx?|jpe?g|png|webp)(\?|$)", re.I)
SKIP_IMG = re.compile(r"harita_thumb|logo|banner|slider|k_\d+_|/tema/|icon|atat", re.I)


def get(sess: requests.Session, url: str) -> str | None:
    HTML.mkdir(parents=True, exist_ok=True)
    p = HTML / (hashlib.sha1(url.encode("utf-8")).hexdigest() + ".html")
    if p.is_file():
        return p.read_text(encoding="utf-8")
    try:
        r = sess.get(url, timeout=25)
        if r.status_code != 200 or "text/html" not in r.headers.get("content-type", "text/html"):
            return None
        r.encoding = "utf-8"
        p.write_text(r.text, encoding="utf-8")
        return r.text
    except Exception:
        return None


def download(sess: requests.Session, url: str) -> str | None:
    FILES.mkdir(parents=True, exist_ok=True)
    ext = ATTACH.search(url)
    ext = ext.group(1).lower() if ext else "bin"
    p = FILES / (hashlib.sha1(url.encode("utf-8")).hexdigest() + "." + ext)
    if p.is_file() and p.stat().st_size > 0:
        return p.name
    try:
        r = sess.get(url, timeout=40)
        if r.status_code != 200 or len(r.content) < 200:
            return None
        p.write_bytes(r.content)
        return p.name
    except Exception:
        return None


def table_matrix(tbl) -> list[list[str]]:
    rows = []
    for tr in tbl.find_all("tr"):
        cells = []
        for td in tr.find_all(["td", "th"]):
            txt = re.sub(r"\s+", " ", td.get_text(" ", strip=True)).strip()
            span = int(td.get("colspan", 1) or 1) if str(td.get("colspan", "1")).isdigit() else 1
            cells.extend([txt] * max(1, min(span, 12)))
        if any(cells):
            rows.append(cells)
    return rows


def content_root(soup: BeautifulSoup):
    for sel in ("#icerik_detay", ".icerik_detay", "#icerik", ".icerik", "div.content", "article"):
        el = soup.select_one(sel)
        if el and len(el.get_text(strip=True)) > 50:
            return el
    return soup.body or soup


def parse_page(sess, host: str, url: str, html: str) -> dict:
    soup = BeautifulSoup(html, "lxml")
    root = content_root(soup)
    title = ""
    h = soup.find(["h1", "h2", "h3"], string=True)
    t = soup.find("title")
    title = re.sub(r"\s+", " ", (h.get_text(" ", strip=True) if h else (t.get_text() if t else ""))).strip()
    text = re.sub(r"\s+", " ", root.get_text(" ", strip=True))
    dates = re.findall(r"\b\d{1,2}[./]\d{1,2}[./]20\d{2}\b", text)
    tables = [table_matrix(tb) for tb in root.find_all("table")]
    tables = [m for m in tables if m and any(re.search(r"\d", c) for r in m for c in r)]
    atts = []
    for a in root.find_all("a", href=True):
        href = urljoin(url, a["href"])
        if ATTACH.search(href) and urlparse(href).netloc.endswith(host.split(".", 1)[1]) or ATTACH.search(href) and host in href:
            atts.append({"url": href, "text": a.get_text(" ", strip=True)[:120]})
    for im in root.find_all("img", src=True):
        src = urljoin(url, im["src"])
        if "meb_iys_dosyalar" in src and not SKIP_IMG.search(src):
            atts.append({"url": src, "text": im.get("alt", "")[:120], "img": True})
    seen = set()
    uniq = []
    for a in atts:
        if a["url"] in seen:
            continue
        seen.add(a["url"])
        a["file"] = download(sess, a["url"])
        uniq.append(a)
    return {"url": url, "title": title, "text": text[:6000], "dates": dates[:20], "tables": tables, "attachments": uniq}


def crawl(host: str) -> dict:
    sess = requests.Session()
    sess.headers.update({"User-Agent": UA})
    base = f"https://{host}/"
    home = get(sess, base) or ""
    soup = BeautifulSoup(home, "lxml")
    list_pages = {base}
    for a in soup.find_all("a", href=True):
        href = urljoin(base, a["href"])
        if urlparse(href).netloc != host:
            continue
        if "listele" in href or "siteharitasi" in href:
            list_pages.add(href)
    links: dict[str, str] = {}
    for lp in list_pages:
        html = home if lp == base else get(sess, lp)
        if not html:
            continue
        s2 = BeautifulSoup(html, "lxml")
        for a in s2.find_all("a", href=True):
            href = urljoin(lp, a["href"])
            if urlparse(href).netloc != host:
                continue
            label = a.get_text(" ", strip=True)
            key_text = fold_tr(label + " " + href)
            if KEY.search(key_text) and ("icerikler/" in href or "sayfa" in href or ATTACH.search(href)):
                links[href] = label
    pages = []
    direct_atts = []
    for href, label in list(links.items())[:25]:
        if ATTACH.search(href):
            direct_atts.append({"url": href, "text": label, "file": download(sess, href)})
            continue
        html = get(sess, href)
        if not html:
            continue
        pg = parse_page(sess, host, href, html)
        pg["link_text"] = label
        pages.append(pg)
    return {"host": host, "pages": pages, "direct_attachments": direct_atts, "n_links": len(links)}


def main() -> None:
    sites = json.loads((OUT / "meb_sites.json").read_text(encoding="utf-8"))
    hosts = sorted({s["host"] for s in sites if s["host"]})
    res_p = OUT / "meb_pages.json"
    done = json.loads(res_p.read_text(encoding="utf-8")) if res_p.is_file() else {}
    todo = [h for h in hosts if h not in done]
    print(f"host {len(hosts)} | yapılacak {len(todo)}", flush=True)
    with ThreadPoolExecutor(max_workers=8) as ex:
        for i, r in enumerate(ex.map(crawl, todo), 1):
            done[r["host"]] = r
            if i % 20 == 0:
                print(f"  {i}/{len(todo)}", flush=True)
                res_p.write_text(json.dumps(done, ensure_ascii=False), encoding="utf-8")
    res_p.write_text(json.dumps(done, ensure_ascii=False), encoding="utf-8")
    with_pages = sum(1 for v in done.values() if v["pages"] or v["direct_attachments"])
    print(f"bitti | fiyat içerikli sayfa/ek bulunan host: {with_pages}/{len(done)}")


if __name__ == "__main__":
    main()
