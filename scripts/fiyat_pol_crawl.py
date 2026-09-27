#!/usr/bin/env python3
"""İl emniyet müdürlüğü sitelerinde (www.{il}.pol.tr) polisevi/sosyal tesis fiyat sayfalarını topla.

Çıktı: data_out/fiyat/pol_pages.json (meb_pages.json ile aynı yapı), ekler data_out/fiyat/files/
       data_out/fiyat/pol_batches/pol_NN.txt  (okuma paketleri; DB'deki polisevi kayıtları ile)
Veritabanına yazmaz.
"""

from __future__ import annotations

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
sys.path.insert(0, str(ROOT / "scripts"))
from fiyat_meb_crawl import ATTACH, UA, download, get, table_matrix  # noqa: E402
from preview_missing_tesisler import fold_tr  # noqa: E402

MASTER = ROOT.parent / "rotalink-data" / "master_database_updated.json"
LINK_KEY = re.compile(r"pol(is)?[-\s]?evi|sosyal[-\s]?tesis|kamp|misafirhane|konaklama|oda[-\s]?fiyat|fiyat[-\s]?liste|tarife", re.I)
IMG_KEY = re.compile(r"fiyat|ucret|tarife|liste|konaklama|oda", re.I)


def slug(il: str) -> str:
    return re.sub(r"[^a-z]", "", fold_tr(il).lower())


def content_root(soup: BeautifulSoup):
    for sel in ("div.content-detail", "div.icerik", "div.page-content", "article", "div.content", "main"):
        for el in soup.select(sel):
            txt = el.get_text(" ", strip=True)
            if len(txt) > 80 and "ÇEREZ POLİTİKASI" not in txt[:200]:
                return el
    body = soup.body or soup
    for m in body.select(".modal"):
        m.decompose()
    return body


def parse_page(sess, host: str, url: str, html: str) -> dict:
    soup = BeautifulSoup(html, "lxml")
    for m in soup.select(".modal, header, footer, nav"):
        m.decompose()
    root = content_root(soup)
    t = soup.find("title")
    title = re.sub(r"\s+", " ", t.get_text() if t else "").strip()
    text = re.sub(r"\s+", " ", root.get_text(" ", strip=True))
    dates = re.findall(r"\b\d{1,2}[./]\d{1,2}[./]20\d{2}\b", text)
    tables = [table_matrix(tb) for tb in root.find_all("table")]
    tables = [m for m in tables if m and any(re.search(r"\d", c) for r in m for c in r)]
    atts = []
    for a in root.find_all("a", href=True):
        href = urljoin(url, a["href"])
        if ATTACH.search(href.split("?")[0]) and host in urlparse(href).netloc:
            name = href.split("?")[0]
            if re.search(r"\.(pdf|docx?|xlsx?)$", name, re.I) or IMG_KEY.search(fold_tr(name + " " + a.get_text(" ", strip=True))):
                atts.append({"url": name, "text": a.get_text(" ", strip=True)[:120]})
    for im in root.find_all("img", src=True):
        src = urljoin(url, im["src"]).split("?")[0]
        if IMG_KEY.search(fold_tr(src + " " + im.get("alt", ""))) and host in urlparse(src).netloc:
            atts.append({"url": src, "text": im.get("alt", "")[:120], "img": True})
    seen, uniq = set(), []
    for a in atts:
        if a["url"] in seen:
            continue
        seen.add(a["url"])
        a["file"] = download(sess, a["url"])
        uniq.append(a)
    return {"url": url, "title": title, "text": text[:8000], "dates": dates[:20], "tables": tables, "attachments": uniq}


def crawl(host: str) -> dict:
    sess = requests.Session()
    sess.headers.update({"User-Agent": UA})
    base = f"https://{host}/"
    home = get(sess, base) or ""
    soup = BeautifulSoup(home, "lxml")
    links: dict[str, str] = {}
    def collect(s, page_url):
        for a in s.find_all("a", href=True):
            href = urljoin(page_url, a["href"]).split("#")[0]
            if urlparse(href).netloc != host:
                continue
            label = a.get_text(" ", strip=True)
            if LINK_KEY.search(fold_tr(label + " " + href)) and not re.search(r"harc|ozel-guvenlik|ruhsat", href):
                links.setdefault(href, label)
    collect(soup, base)
    # sosyal tesisler / polisevi ana sayfalarından ikinci seviye bağlantılar
    for href in list(links)[:10]:
        if ATTACH.search(href.split("?")[0]):
            continue
        html = get(sess, href)
        if html:
            collect(BeautifulSoup(html, "lxml"), href)
    pages, direct = [], []
    for href, label in list(links.items())[:30]:
        if ATTACH.search(href.split("?")[0]):
            direct.append({"url": href, "text": label, "file": download(sess, href)})
            continue
        html = get(sess, href)
        if not html:
            continue
        pg = parse_page(sess, host, href, html)
        pg["link_text"] = label
        pages.append(pg)
    return {"host": host, "pages": pages, "direct_attachments": direct, "n_links": len(links), "home_ok": bool(home)}


def main() -> None:
    master = json.loads(MASTER.read_text(encoding="utf-8"))["tesisler"]
    pol = [t for t in master if "polis" in fold_tr((t.get("tip") or "") + " " + t["isim"]).lower()]
    by_il: dict[str, list] = {}
    for t in pol:
        by_il.setdefault(t["il"], []).append({"il": t["il"], "isim": t["isim"]})
    hosts = {f"www.{slug(il)}.pol.tr": il for il in by_il}
    res_p = OUT / "pol_pages.json"
    done = json.loads(res_p.read_text(encoding="utf-8")) if res_p.is_file() else {}
    todo = [h for h in hosts if h not in done]
    print(f"polisevi kaydı {len(pol)} | il {len(by_il)} | yapılacak host {len(todo)}", flush=True)
    with ThreadPoolExecutor(max_workers=8) as ex:
        for r in ex.map(crawl, todo):
            done[r["host"]] = r
    res_p.write_text(json.dumps(done, ensure_ascii=False), encoding="utf-8")

    bdir = OUT / "pol_batches"
    bdir.mkdir(exist_ok=True)
    blocks = []
    for host, il in sorted(hosts.items(), key=lambda x: x[1]):
        v = done.get(host, {})
        lines = [f"########## HOST: {host}", f"    DB: {json.dumps(by_il[il], ensure_ascii=False)}"]
        if not v.get("home_ok"):
            lines.append("    (site açılamadı)")
        for p in v.get("pages", []):
            lines.append(f"--- SAYFA: {p['url']}")
            lines.append(f"    BAŞLIK: {p['title']}")
            lines.append(f"    METİN: {p['text'][:3000]}")
            for tb in p["tables"]:
                lines.append("    TABLO:")
                lines.extend("      " + " | ".join(r) for r in tb[:40])
            for a in p["attachments"]:
                lines.append(f"    EK: {a['url']}  [{a.get('file')}]")
        for a in v.get("direct_attachments", []):
            lines.append(f"    DOGRUDAN_EK: {a['text']} -> {a['url']} [{a.get('file')}]")
        blocks.append("\n".join(lines))
    n = 0
    for i in range(0, len(blocks), 15):
        n += 1
        (bdir / f"pol_{n:02d}.txt").write_text("\n\n".join(blocks[i:i + 15]), encoding="utf-8")
    ok = sum(1 for h in hosts if done.get(h, {}).get("home_ok"))
    withp = sum(1 for h in hosts if done.get(h, {}).get("pages"))
    print(f"site açılan {ok}/{len(hosts)} | sayfa bulunan {withp} | paket {n}")


if __name__ == "__main__":
    main()
