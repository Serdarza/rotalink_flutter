#!/usr/bin/env python3
"""Elle okunmuş resmi tarifeleri doğrula, sınıflandır ve fiyatlar.json önizlemesi üret.

Girdi : data_out/fiyat/manual/*.json   (her biri kayıt listesi; şema: data_out/fiyat/YAZIM_KURALLARI.md)
Kaynak: data_out/fiyat/meb_pages.json, data_out/fiyat/files/*.txt, data_out/fiyat/extra/*.txt
Çıktı : data_out/fiyat/tarifeler.json          doğrulanmış kayıtlar (+ durum sınıfı)
        data_out/fiyat/build_report.txt        hatalar / uyarılar
        data_out/fiyat/fiyatlar_preview.json   rotalink-data/fiyatlar.json'un birleşmiş önizlemesi

Kural: tarifedeki her sayısal fiyat kaynağın metninde/tablosunda/ek dosyasının çıkarılmış metninde
birebir geçmelidir. Geçmiyorsa kayıt reddedilir; yalnızca kaynak_turu=gorsel olup OCR'ın okuyamadığı
durumda kayıt "gorsel_elle" uyarısıyla tutulur (elle kontrol listesine girer).
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data_out" / "fiyat"
DATA = ROOT.parent / "rotalink-data"
MASTER = DATA / "master_database_updated.json"
FIYATLAR = DATA / "fiyatlar.json"
KONTROL_TARIHI = "2026-09-27"

TURLER = {"web", "pdf", "gorsel", "word", "excel"}
# Resmî kaynaktan tam tarifeyle zaten doğru yazılmış kayıtlar (kullanıcının örnek kaydı) — değiştirilmez.
KEEP_EXISTING = [("Düzce", "Akçakoca Öğretmen Evi")]
DURUMLAR = {"A", "B", "C", "D"}
TARIFE_KEYS = ["baslik", "donem", "birim", "guncelleme", "dogrulama", "kategoriler", "tablolar", "kurallar",
               "giris_saati", "cikis_saati", "dahil", "indirimler", "ek_ucretler", "notlar"]


def source_numbers(text: str) -> set[float]:
    nums: set[float] = set()
    t = text.replace("\xa0", " ")
    for m in re.finditer(r"\d+(?:[.,\s]\d+)*", t):
        raw = m.group(0)
        pieces = {raw} | set(re.split(r"\s+", raw))
        # "1 500" gibi binlik boşluklu yazım
        for m2 in re.finditer(r"\d{1,3}(?:\s\d{3})+", raw):
            pieces.add(m2.group(0).replace(" ", ""))
        for part in pieces:
            part = part.strip(" .,")
            if not part:
                continue
            cands = {part}
            if re.fullmatch(r"\d{1,3}(\.\d{3})+(,\d+)?", part):
                cands.add(part.replace(".", "").replace(",", "."))
            if re.fullmatch(r"\d{1,3}(,\d{3})+(\.\d+)?", part):
                cands.add(part.replace(",", ""))
            if re.fullmatch(r"\d+,\d{1,2}", part):
                cands.add(part.replace(",", "."))
            if re.fullmatch(r"\d+\.\d{1,2}", part):
                cands.add(part)
            # "1.100.00 TL" gibi binlik ve kuruş ayracı ikisi de nokta olan yazım
            if re.fullmatch(r"\d{1,3}(\.\d{3})+\.\d{2}", part):
                cands.add(part[:-3].replace(".", "") + part[-3:])
            for c in cands:
                try:
                    nums.add(float(c))
                except ValueError:
                    pass
    return nums


def _file_text(name: str | None) -> str:
    if not name:
        return ""
    tp = OUT / "files" / (name + ".txt")
    return tp.read_text(encoding="utf-8") if tp.is_file() else ""


def _id_of(url: str) -> str:
    m = re.search(r"_(\d+)\.html", url)
    return m.group(1) if m else url


def load_source_text(url: str, pages: dict) -> str:
    chunks = []
    uid = _id_of(url)
    for host, v in pages.items():
        for p in v["pages"]:
            if p["url"] == url or (host in url and _id_of(p["url"]) == uid):
                chunks.append(p["title"])
                chunks.append(p["text"])
                for t in p["tables"]:
                    chunks.extend(" ; ".join(r) for r in t)
                for a in p["attachments"]:
                    chunks.append(_file_text(a.get("file")))
            else:
                for a in p["attachments"]:
                    if a["url"] == url:
                        chunks.append(_file_text(a.get("file")))
        for a in v.get("direct_attachments", []):
            if a["url"] == url:
                chunks.append(_file_text(a.get("file")))
    h = hashlib.sha1(url.encode("utf-8")).hexdigest()
    extra = OUT / "extra"
    if extra.is_dir():
        for cand in extra.glob(h + "*.txt"):
            chunks.append(cand.read_text(encoding="utf-8"))
    return "\n".join(c for c in chunks if c)


def iter_tables(tarife: dict):
    tables = tarife.get("tablolar") or ([tarife] if tarife.get("satirlar") else [])
    for t in tables:
        yield t


def prices_in(tarife: dict) -> list[float]:
    out = []
    for t in iter_tables(tarife):
        for r in t.get("satirlar") or []:
            for v in (r.get("fiyatlar") or {}).values():
                if isinstance(v, (int, float)) and not isinstance(v, bool):
                    out.append(float(v))
    return out


def fmt_tl(v: float) -> str:
    if abs(v - round(v)) < 1e-9:
        s = f"{int(round(v)):,}".replace(",", ".")
    else:
        s = f"{v:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return s


def ozet_range(tarife: dict, cat_ids: list[str]) -> str | None:
    vals = []
    for t in iter_tables(tarife):
        for r in t.get("satirlar") or []:
            for cid, v in (r.get("fiyatlar") or {}).items():
                if cid in cat_ids and isinstance(v, (int, float)) and not isinstance(v, bool):
                    vals.append(float(v))
    if not vals:
        return None
    lo, hi = min(vals), max(vals)
    return f"{fmt_tl(lo)} TL" if lo == hi else f"{fmt_tl(lo)} – {fmt_tl(hi)} TL"


def validate_tarife_shape(tarife: dict) -> list[str]:
    errs = []
    for k in tarife:
        if k not in TARIFE_KEYS:
            errs.append(f"tarife içinde bilinmeyen alan: {k}")
    cats = {c["id"] for c in tarife.get("kategoriler") or []}
    for t in iter_tables(tarife):
        tcats = cats | {c["id"] for c in t.get("kategoriler") or []}
        for r in t.get("satirlar") or []:
            if not r.get("ad"):
                errs.append("satırda ad yok")
            for cid in (r.get("fiyatlar") or {}):
                if cid not in tcats:
                    errs.append(f"kategori tanımsız: {cid}")
    return errs


def compose_entry(rec: dict) -> dict:
    tarife = {k: rec["tarife"][k] for k in TARIFE_KEYS if rec["tarife"].get(k) not in (None, [], "")}
    tarife.setdefault("dogrulama", "resmi_kaynak")
    tarife["guncelleme"] = KONTROL_TARIHI
    entry = {"il": rec["il"], "isim": rec["isim"]}
    oz = rec.get("ozet") or {}
    for field, key in (("fiyat_sivil", "sivil"), ("fiyat_kamu_personeli", "kamu"), ("fiyat_kurum_personeli", "kurum")):
        ids = oz.get(key)
        if ids:
            r = ozet_range(rec["tarife"], ids)
            if r:
                entry[field] = r
    entry["kaynak"] = rec["kaynak"]
    parts = []
    if rec.get("gecerlilik_baslangic"):
        parts.append(f"{rec['gecerlilik_baslangic']} tarihinden itibaren geçerli")
    elif rec["tarife"].get("donem"):
        parts.append(f"{rec['tarife']['donem']} tarifesi")
    tur = {"web": "resmî web sayfası", "pdf": "resmî PDF", "gorsel": "resmî sitedeki tarife görseli",
           "word": "resmî Word belgesi", "excel": "resmî Excel belgesi"}[rec["kaynak_turu"]]
    src = f"Kaynak: {tur}"
    if rec.get("kaynak_baslik"):
        src += f" “{rec['kaynak_baslik']}”"
    if rec.get("kaynak_tarihi"):
        src += f" ({rec['kaynak_tarihi']})"
    parts.append(src)
    parts.append(f"son kontrol {KONTROL_TARIHI[8:10]}.{KONTROL_TARIHI[5:7]}.{KONTROL_TARIHI[:4]}")
    entry["gecerlilik"] = "; ".join(parts)
    entry["tarife"] = tarife
    return entry


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    pages = {}
    for pf in sorted(OUT.glob("*_pages.json")):
        pages.update(json.loads(pf.read_text(encoding="utf-8")))
    master = json.loads(MASTER.read_text(encoding="utf-8"))["tesisler"]
    db_keys = {(t["il"], t["isim"]) for t in master}
    only = set(sys.argv[1:])
    records, report, errors, warns = [], [], [], []
    for f in sorted((OUT / "manual").glob("*.json")):
        if only and f.name not in only:
            continue
        try:
            items = json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            errors.append(f"{f.name}: JSON bozuk: {e}")
            continue
        for rec in items:
            tag = f"{f.name}: {rec.get('il')} / {rec.get('isim')}"
            durum = rec.get("durum")
            if durum not in DURUMLAR:
                errors.append(f"{tag}: durum A/B/C/D olmalı")
                continue
            if (rec.get("il"), rec.get("isim")) not in db_keys:
                errors.append(f"{tag}: veritabanında bu il+isim yok")
                continue
            if not rec.get("kaynak"):
                errors.append(f"{tag}: kaynak URL yok")
                continue
            if durum in ("C", "D") or not rec.get("tarife"):
                report.append({**rec, "fiyat_yazildi": False})
                continue
            if rec.get("kaynak_turu") not in TURLER:
                errors.append(f"{tag}: kaynak_turu geçersiz")
                continue
            shape = validate_tarife_shape(rec["tarife"])
            if shape:
                errors.append(f"{tag}: {shape}")
                continue
            ps = prices_in(rec["tarife"])
            if not ps:
                errors.append(f"{tag}: tarifede sayısal fiyat yok")
                continue
            src = load_source_text(rec["kaynak"], pages)
            for extra in rec.get("ek_kaynaklar") or []:
                src += "\n" + load_source_text(extra, pages)
            nums = source_numbers(src)
            bad = sorted({p for p in ps if p not in nums})
            flag = None
            if bad:
                if rec["kaynak_turu"] == "gorsel":
                    flag = "gorsel_elle"
                    warns.append(f"{tag}: OCR'da geçmeyen {bad} → görselden elle okundu, kontrol listesinde")
                else:
                    errors.append(f"{tag}: kaynakta geçmeyen fiyat(lar) {bad}")
                    continue
            rec = {**rec, "kontrol": flag or "rakamlar_kaynakta"}
            records.append(rec)
            report.append({**rec, "fiyat_yazildi": durum == "A"})

    by_key = {}
    for r in records:
        by_key[(r["il"], r["isim"])] = r
    (OUT / "tarifeler.json").write_text(json.dumps(list(by_key.values()), ensure_ascii=False, indent=1), encoding="utf-8")
    (OUT / "report_records.json").write_text(json.dumps(report, ensure_ascii=False, indent=1), encoding="utf-8")

    # fiyatlar.json önizlemesi: yalnızca durum A yazılır; mevcut kayıt sırası korunur.
    # Mevcut olup bu kontrolde resmî kaynakta doğrulanamayan kayıtlar silinmez → teyit_gerekli işaretlenir.
    cur = json.loads(FIYATLAR.read_text(encoding="utf-8"))
    idx = {(e["il"], e["isim"]): i for i, e in enumerate(cur["tesisler"])}
    new_list = list(cur["tesisler"])
    added = replaced = teyit = 0
    keep_existing = set(KEEP_EXISTING)
    for key, r in by_key.items():
        if r["durum"] != "A" or key in keep_existing:
            continue
        entry = compose_entry(r)
        if key in idx:
            new_list[idx[key]] = entry
            replaced += 1
        else:
            new_list.append(entry)
            added += 1
    updated = {k for k, r in by_key.items() if r["durum"] == "A"} | keep_existing
    if not only:
        for key, i in idx.items():
            if key in updated:
                continue
            e = dict(new_list[i])
            t = dict(e.get("tarife") or {})
            t["dogrulama"] = "teyit_gerekli"
            t["guncelleme"] = KONTROL_TARIHI
            notlar = [n for n in (t.get("notlar") or []) if not n.startswith("Bu fiyat 27.09.2026")]
            notlar.append("Bu fiyat 27.09.2026 kontrolünde resmî kaynakta güncel olarak doğrulanamadı; rezervasyon öncesi tesisle teyit ediniz.")
            t["notlar"] = notlar
            e["tarife"] = t
            new_list[i] = e
            teyit += 1
    preview = {**cur, "tesisler": new_list}
    (OUT / "fiyatlar_preview.json").write_text(json.dumps(preview, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    (OUT / "build_report.txt").write_text("\n".join(["HATALAR:"] + errors + ["", "UYARILAR:"] + warns), encoding="utf-8")
    cnt = {}
    for r in report:
        cnt[r["durum"]] = cnt.get(r["durum"], 0) + 1
    print(f"doğrulanan tarife {len(by_key)} | durumlar {cnt} | önizleme: +{added} yeni, {replaced} güncellenen, {teyit} teyit_gerekli")
    print(f"hata {len(errors)} | görsel-elle uyarı {len(warns)}")
    for e in errors:
        print("  X", e)
    for w in warns:
        print("  !", w)


if __name__ == "__main__":
    main()
