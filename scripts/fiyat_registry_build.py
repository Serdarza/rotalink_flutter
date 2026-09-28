#!/usr/bin/env python3
"""İlk fiyat araştırmasının (data_out/fiyat/manual/*.json) resmî kaynaklarını
rotalink-data/price_research/sources.json kaynak kaydına dönüştür.

Aylık GitHub Actions işi (rotalink-data/price_research/monitor.py) bu kaydı okur.
"""

from __future__ import annotations

import json
import re
import sys
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data_out" / "fiyat"
DATA = ROOT.parent / "rotalink-data"
sys.path.insert(0, str(ROOT / "scripts"))
from fiyat_build import load_source_text, prices_in, source_numbers  # noqa: E402

RANK = {"A": 0, "B": 1, "D": 2, "C": 3}
FILE_RE = re.compile(r"\.(pdf|docx?|xlsx?|jpe?g|png|webp)(\?|$)", re.I)
MEVZUAT = "mevzuat.gov.tr"
# Kullanıcının tesisin kendi resmî sitesi olarak onayladığı .gov.tr dışı alan adları
ONAYLI_ALANLAR = ["belediyeis.org.tr", "ilkyatirimgrupdidim.com", "adanatakav.tr.gg", "sungurluogretmenevi.com.tr",
                  "tuzlauygulamaoteli.com", "kayseriuygulamaoteli.com", "samsunuygulamaoteli.com",
                  "kinikogretmenevi.com.tr", "tigem.gov.tr", "tse.org.tr", "ziraatbank.com.tr",
                  "halkbank.com.tr", "vakifbank.com.tr", "bddk.org.tr", "trt.net.tr"]


def tur_of(url: str, fallback: str | None = None) -> str:
    m = FILE_RE.search(url)
    if not m:
        return fallback if fallback in ("web", "pdf", "gorsel", "word", "excel") and not url.endswith(".html") else "web"
    e = m.group(1).lower()
    return {"pdf": "pdf", "doc": "word", "docx": "word", "xls": "excel", "xlsx": "excel"}.get(e, "gorsel")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    master = json.loads((DATA / "master_database_updated.json").read_text(encoding="utf-8"))["tesisler"]
    mk = {(t.get("il"), t.get("isim")): t for t in master}
    fiyat = json.loads((DATA / "fiyatlar.json").read_text(encoding="utf-8"))["tesisler"]
    pages = {}
    for pf in sorted(OUT.glob("*_pages.json")):
        pages.update(json.loads(pf.read_text(encoding="utf-8")))

    recs: dict[tuple[str, str], list[dict]] = {}
    for f in sorted((OUT / "manual").glob("*.json")):
        for r in json.loads(f.read_text(encoding="utf-8")):
            recs.setdefault((r["il"], r["isim"]), []).append(r)

    tesisler = []
    for key, rs in recs.items():
        if key not in mk:
            continue
        best = min(rs, key=lambda r: RANK.get(r.get("durum"), 9))
        srcs: dict[str, dict] = {}

        def add(url: str | None, rol: str, rec: dict) -> None:
            if not url or not url.startswith("http") or url in srcs:
                return
            srcs[url] = {"url": url, "tur": tur_of(url, rec.get("kaynak_turu") if rol == "fiyat" else None), "rol": rol,
                         "alan_adi": urlparse(url).hostname}
            if rol == "fiyat":
                for k_src, k_dst in (("kaynak_baslik", "baslik"), ("kaynak_tarihi", "tarih")):
                    if rec.get(k_src):
                        srcs[url][k_dst] = rec[k_src]

        for r in sorted(rs, key=lambda r: RANK.get(r.get("durum"), 9)):
            add(r.get("kaynak"), "fiyat" if r.get("durum") in ("A", "B") else "sayfa", r)
            for u in r.get("ek_kaynaklar") or []:
                add(u, "fiyat_ek" if FILE_RE.search(u) else "sayfa", r)
        hosts = {s["alan_adi"] for s in srcs.values() if s["alan_adi"] and s["alan_adi"].endswith(".meb.k12.tr")}
        for h in sorted(hosts):
            add(f"https://{h}/", "ana_sayfa", best)

        durum = best.get("durum")
        only_mevzuat = srcs and all(MEVZUAT in (s["alan_adi"] or "") for s in srcs.values())
        if not srcs or only_mevzuat:
            yontem, aktif = "pasif", False
        elif durum == "A":
            yontem, aktif = "rakam_dogrulama", True
        else:
            yontem, aktif = "yeni_tarife_arama", True

        ocr_eksik: list[float] = []
        if durum == "A" and best.get("tarife"):
            txt = load_source_text(best["kaynak"], pages)
            for u in best.get("ek_kaynaklar") or []:
                txt += "\n" + load_source_text(u, pages)
            nums = source_numbers(txt)
            ocr_eksik = sorted({p for p in prices_in(best["tarife"]) if p not in nums})

        m = mk[key]
        tesisler.append({
            "il": key[0], "isim": key[1], "kurum": m.get("tip"), "telefon": str(m.get("telefon") or "") or None,
            "durum": durum, "aktif": aktif, "kontrol_yontemi": yontem,
            "kaynaklar": list(srcs.values()),
            "ocr_eksik": ocr_eksik,
            "neden": best.get("neden"),
            "son_kontrol": None, "son_basarili_kontrol": None, "son_sonuc": None,
        })

    known = {(t["il"], t["isim"]) for t in tesisler}
    for e in fiyat:
        key = (e["il"], e["isim"])
        if key in known or key not in mk:
            continue
        k = e.get("kaynak") or ""
        srcs = [{"url": k, "tur": tur_of(k), "rol": "sayfa", "alan_adi": urlparse(k).hostname}] if k.startswith("http") else []
        m = mk[key]
        resmi = (e.get("tarife") or {}).get("dogrulama") == "resmi_kaynak"
        tesisler.append({
            "il": key[0], "isim": key[1], "kurum": m.get("tip"), "telefon": str(m.get("telefon") or "") or None,
            "durum": "A" if resmi else "eski_fiyat",
            "aktif": bool(srcs),
            "kontrol_yontemi": ("rakam_dogrulama" if resmi else "yeni_tarife_arama") if srcs else "pasif",
            "kaynaklar": srcs, "ocr_eksik": [],
            "neden": None if resmi else "İlk araştırmada resmî kaynakta güncel olarak doğrulanamadı; eski fiyat korunuyor.",
            "son_kontrol": None, "son_basarili_kontrol": None, "son_sonuc": None,
        })

    tesisler.sort(key=lambda t: (t["il"], t["isim"]))
    reg = {
        "aciklama": "RotaLink kamu konaklama tesisleri resmî fiyat kaynak kaydı. Aylık kontrol: price_research/monitor.py",
        "olusturma": date.today().isoformat(),
        "onayli_alan_adlari": ONAYLI_ALANLAR,
        "tesisler": tesisler,
        "url_durumu": {},
    }
    dst = DATA / "price_research" / "sources.json"
    dst.write_text(json.dumps(reg, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    from collections import Counter
    print("tesis", len(tesisler), "aktif", sum(t["aktif"] for t in tesisler),
          "url", len({s["url"] for t in tesisler for s in t["kaynaklar"]}))
    print(Counter(t["kontrol_yontemi"] for t in tesisler), Counter(t["durum"] for t in tesisler))


if __name__ == "__main__":
    main()
