#!/usr/bin/env python3
"""Öğretmenevlerinin resmi meb.k12.tr sitelerini bul.

MEB geçersiz alt alan adlarını www.meb.k12.tr/HataliDns.php'ye yönlendirir; geçerli
sitelerin <title> değeri "İL / İLÇE - Kurum Adı" biçimindedir.
Çıktı: data_out/fiyat/meb_sites.json
"""

from __future__ import annotations

import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data_out" / "fiyat"
MASTER = ROOT.parent / "rotalink-data" / "master_database_updated.json"
sys.path.insert(0, str(ROOT / "scripts"))
from preview_missing_tesisler import category, norm_text  # noqa: E402

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"
S = requests.Session()
S.headers.update({"User-Agent": UA})

SUFFIXES = ["ogretmenevi", "ogretmeneviaso", "ogretmenevivaso", "ogretmenevleri", "ogretmenevimudurlugu"]
DROP = {"ve", "aksam", "sanat", "okulu", "mudurlugu", "ogretmenevi", "ogretmen", "evi", "aso", "merkez", "il", "prof", "dr"}


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", norm_text(s))


def core_words(name: str) -> list[str]:
    n = norm_text(name)
    n = re.sub(r"\bogretmen evi\b", "ogretmenevi", n)
    words = [w for w in n.split() if w not in DROP]
    return words


def candidates(il: str, ilce: str, name: str) -> list[str]:
    il_s, ilce_s = slug(il), slug(ilce)
    w = core_words(name)
    words_nt = [x for x in w if x not in (il_s, ilce_s)]
    bases = []
    full = "".join(w)
    for b in (full, "".join(words_nt), ilce_s + "".join(words_nt), il_s + "".join(words_nt),
              il_s + ilce_s + "".join(words_nt), ilce_s, il_s, il_s + ilce_s, il_s + "merkez"):
        if b and b not in bases:
            bases.append(b)
    if w:
        for b in (w[0], il_s + w[0], ilce_s + w[0]):
            if b and b not in bases:
                bases.append(b)
    out = []
    for s in SUFFIXES[:2]:
        for b in bases:
            h = f"{b}{s}"
            if h not in out and len(h) < 64:
                out.append(h)
    return out[:12]


def check(host: str) -> dict | None:
    try:
        h = S.head(f"https://{host}.meb.k12.tr/", timeout=15, allow_redirects=False)
        if h.status_code != 200:
            return None
        r = S.get(f"https://{host}.meb.k12.tr/", timeout=20, allow_redirects=False)
    except Exception:
        return None
    if r.status_code != 200:
        return None
    r.encoding = "utf-8"
    t = re.search(r"<title>(.*?)</title>", r.text, re.S)
    title = re.sub(r"\s+", " ", t.group(1)).strip() if t else ""
    if "meb_iys_dosyalar" not in r.text:
        return None
    return {"host": f"{host}.meb.k12.tr", "title": title}


def title_matches(title: str, il: str, ilce: str, name: str) -> bool:
    tt = norm_text(title)
    if norm_text(il) not in tt:
        return False
    if "ogretmen" not in tt:
        return False
    w = [x for x in core_words(name) if x not in (slug(il),)]
    return all(x in tt.replace(" ", "") or x in tt for x in w) if w else True


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    parsed = json.loads((ROOT / "data_out" / "sources_parsed.json").read_text(encoding="utf-8"))
    master = json.loads(MASTER.read_text(encoding="utf-8"))["tesisler"]
    targets = []
    for r in parsed["meb"]:
        targets.append({"kaynak": "meb_liste", "il": r["il"], "ilce": r["ilce"], "isim": r["isim"], "tel": r["telefon"]})
    for t in master:
        if category(f"{t.get('isim','')} {t.get('tip') or ''}") == "ogretmenevi":
            targets.append({"kaynak": "db", "il": t["il"], "ilce": "", "isim": t["isim"], "tel": t.get("telefon", "")})

    cache_p = OUT / "meb_host_cache.json"
    cache = json.loads(cache_p.read_text(encoding="utf-8")) if cache_p.is_file() else {}
    done = [0]

    def resolve(tg: dict) -> dict:
        done[0] += 1
        if done[0] % 50 == 0:
            print(f"  {done[0]}/{len(targets)}", flush=True)
            cache_p.write_text(json.dumps(dict(cache), ensure_ascii=False), encoding="utf-8")
        for h in candidates(tg["il"], tg["ilce"], tg["isim"]):
            if h in cache:
                res = cache[h]
            else:
                res = check(h)
                cache[h] = res
            if res and title_matches(res["title"], tg["il"], tg["ilce"], tg["isim"]):
                return {**tg, **res}
        return {**tg, "host": None, "title": None}

    with ThreadPoolExecutor(max_workers=16) as ex:
        results = list(ex.map(resolve, targets))
    cache_p.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
    (OUT / "meb_sites.json").write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")
    found = [r for r in results if r["host"]]
    print(f"hedef {len(results)} | site bulundu {len(found)} | benzersiz host {len({r['host'] for r in found})}")
    print("meb_liste:", sum(1 for r in found if r['kaynak'] == 'meb_liste'), "/", sum(1 for r in results if r['kaynak'] == 'meb_liste'))
    print("db:", sum(1 for r in found if r['kaynak'] == 'db'), "/", sum(1 for r in results if r['kaynak'] == 'db'))


if __name__ == "__main__":
    main()
