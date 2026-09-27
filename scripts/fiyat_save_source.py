#!/usr/bin/env python3
"""Resmî bir kaynak URL'sini indirip doğrulama için metnini kaydet.

Kullanım: python scripts/fiyat_save_source.py <url> [<url> ...]
Çıktı   : data_out/fiyat/extra/<sha1(url)>.txt  (HTML: metin + tablolar; PDF/Word/Excel: metin; görsel: OCR)
          görsel/PDF dosyası da data_out/fiyat/extra/<sha1>.<uzantı> olarak saklanır (Read ile açıp bakmak için).
fiyat_build.py bu dosyaları kaynak metni olarak kullanır.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
EXTRA = ROOT / "data_out" / "fiyat" / "extra"
sys.path.insert(0, str(ROOT / "scripts"))
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"


def html_text(html: str) -> str:
    soup = BeautifulSoup(html, "lxml")
    for el in soup(["script", "style", "noscript"]):
        el.decompose()
    out = []
    t = soup.find("title")
    if t:
        out.append("BAŞLIK: " + t.get_text(" ", strip=True))
    out.append(re.sub(r"\s+", " ", soup.get_text(" ", strip=True)))
    for tb in soup.find_all("table"):
        out.append("--- TABLO")
        for tr in tb.find_all("tr"):
            out.append(" | ".join(re.sub(r"\s+", " ", c.get_text(" ", strip=True)) for c in tr.find_all(["td", "th"])))
    links = []
    for a in soup.find_all("a", href=True):
        if re.search(r"\.(pdf|docx?|xlsx?|jpe?g|png)(\?|$)", a["href"], re.I):
            links.append(f"EK: {a.get_text(' ', strip=True)[:80]} -> {a['href']}")
    for im in soup.find_all("img", src=True):
        if re.search(r"fiyat|ucret|ücret|tarife|liste", im["src"] + " " + im.get("alt", ""), re.I):
            links.append(f"GÖRSEL: {im.get('alt', '')[:80]} -> {im['src']}")
    if links:
        out.append("--- EKLER\n" + "\n".join(links))
    return "\n".join(out)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    from fiyat_extract_files import extract  # OCR/PDF/Office çıkarıcı

    EXTRA.mkdir(parents=True, exist_ok=True)
    for url in sys.argv[1:]:
        h = hashlib.sha1(url.encode("utf-8")).hexdigest()
        try:
            r = requests.get(url, headers={"User-Agent": UA}, timeout=40, verify=True)
        except requests.exceptions.SSLError:
            r = requests.get(url, headers={"User-Agent": UA}, timeout=40, verify=False)
        except Exception as e:  # noqa: BLE001
            print(f"HATA {url}: {e}")
            continue
        ctype = r.headers.get("content-type", "").lower()
        m = re.search(r"\.(pdf|docx|xlsx|xls|jpe?g|png|webp)(\?|$)", url, re.I)
        ext = None
        if "pdf" in ctype:
            ext = "pdf"
        elif "image/" in ctype:
            ext = ctype.split("image/")[1].split(";")[0].replace("jpeg", "jpg")
        elif "spreadsheet" in ctype or "excel" in ctype:
            ext = "xlsx" if "openxml" in ctype else "xls"
        elif "wordprocessing" in ctype:
            ext = "docx"
        elif m and "html" not in ctype:
            ext = m.group(1).lower()
        if ext:
            fp = EXTRA / f"{h}.{ext}"
            fp.write_bytes(r.content)
            txt = extract(fp)
        else:
            r.encoding = r.apparent_encoding if not r.encoding or r.encoding.lower() == "iso-8859-1" else r.encoding
            txt = html_text(r.text)
        header = f"URL: {url}\nHTTP: {r.status_code}\nLast-Modified: {r.headers.get('Last-Modified', '-')}\n"
        (EXTRA / f"{h}.txt").write_text(header + txt, encoding="utf-8")
        print(f"OK {r.status_code} {url}\n   -> data_out/fiyat/extra/{h}.txt" + (f" (dosya: extra/{h}.{ext})" if ext else ""))


if __name__ == "__main__":
    main()
