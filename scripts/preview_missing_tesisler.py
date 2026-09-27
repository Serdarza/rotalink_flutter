#!/usr/bin/env python3
"""Kaynaklardan gelen tesisleri master ile karşılaştır — SADECE ÖNİZLEME.

Girdi : data_out/sources_parsed.json (harvest_tesis_sources.py)
Master: ../rotalink-data/master_database_updated.json (salt okunur)
Çıktı : data_out/preview_additions.json, data_out/preview_report.json, data_out/preview_report.txt

Master dosyasına hiçbir şey yazmaz.
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data_out"
MASTER = ROOT.parent / "rotalink-data" / "master_database_updated.json"
PARSED = OUT_DIR / "sources_parsed.json"

sys.path.insert(0, str(ROOT / "scripts"))
from discover_missing_tesisler import _stem_token, fold_tr, haversine_m  # noqa: E402

TR_ALPHA = "abcçdefgğhıijklmnoöprsştuüvyz"


def tr_sort_key(s: str) -> list[int]:
    s = (s or "").replace("İ", "i").replace("I", "ı").lower()
    return [TR_ALPHA.index(ch) if ch in TR_ALPHA else 100 + ord(ch) for ch in s]


# ---------------------------------------------------------------- normalize

PHRASES = [
    (r"\bve\s+aksam\s+sanat\s+okulu(\s+mudurlugu)?\b", " "),
    (r"\baksam\s+sanat\s+okulu\b", " "),
    (r"\baso\b", " "),
    (r"\bdevlet\s+su\s+isleri(\s+genel\s+mudurlugu)?\b", " dsi "),
    (r"\bdevlet\s+hava\s+meydanlari(\s+isletmesi)?(\s+genel\s+mudurlugu)?\b", " dhmi "),
    (r"\bkarayollari\s+genel\s+mudurlugu\b", " karayollari "),
    (r"\bogretmen\s+evi\b", " ogretmenevi "),
    (r"\bpolis\s+evi\b", " polisevi "),
    (r"\bordu\s+evi\b", " orduevi "),
    (r"\bkonuk\s+evi\b", " konukevi "),
    (r"\bhakim\s+evi\b", " hakimevi "),
    (r"\bhekim\s+evi\b", " hekimevi "),
    (r"\bmisafir\s+hane(si)?\b", " misafirhane "),
    (r"\buniversitesi\b", " universite "),
    (r"\bno\s*\.?\s*lu\b|\bnolu\b|\bnumarali\b", " no "),
    (r"\bt\s*c\b", " "),
    (r"\bpr\b|\bprof\b", " prof "),
    (r"\bdoc\b|\bdoc\s+dr\b", " doc "),
]

IL_ALIASES = {
    "afyonkarahisar": {"afyon"},
    "sanliurfa": {"urfa"},
    "gaziantep": {"antep"},
    "kahramanmaras": {"maras", "k maras", "kmaras"},
    "mersin": {"icel"},
    "kibris": {"kktc", "lefkosa"},
}

ADDR_STOP = {
    "mah", "mahallesi", "mahalle", "cad", "caddesi", "cd", "sk", "sok", "sokak", "sokagi", "no", "blv", "bulvari",
    "bulv", "merkez", "kat", "yani", "karsisi", "uzeri", "mevkii", "turkiye", "koyu", "ve", "ile",
}

STOP = {
    "ve", "ile", "mudurlugu", "mudurluk", "mudur", "mud", "md", "lugu", "a", "s", "o", "sti", "ltd",
    "il", "ilce", "merkez", "merkezi", "tesisi", "tesisleri", "tesis", "no", "nolu", "sube", "ligi",
    "mah", "mahallesi", "the",
}
GENERIC = {
    "ogretmenev", "orduev", "polisev", "misafirhane", "konukev", "hakimev", "hekimev", "sosyal",
    "egitim", "otel", "uygulama", "kamp", "dinlenme", "lokal", "gazino", "bolge", "genel",
    "kurum", "kurumu", "baskanlig", "baskanligi", "bakanlig", "bakanligi", "müdürlüğü", "tesis",
    "evi", "ev", "sitesi", "site",
}


def norm_text(s: str) -> str:
    t = fold_tr(s)
    t = t.replace("i̇", "i")
    t = re.sub(r"\([^)]*konaklama[^)]*\)", " ", t)
    t = re.sub(r"[^a-z0-9\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    for pat, rep in PHRASES:
        t = re.sub(pat, rep, t)
    return re.sub(r"\s+", " ", t).strip()


def addr_tokens(adres: str, il: str = "") -> frozenset[str]:
    il_f = norm_text(il)
    drop = {il_f} | IL_ALIASES.get(il_f.replace(" ", ""), set())
    return frozenset(
        t for t in norm_text(adres).split()
        if t not in ADDR_STOP and t not in drop and (len(t) >= 3 or t.isdigit())
    )


def tokens(isim: str, il: str = "") -> frozenset[str]:
    il_f = norm_text(il)
    il_drop = {il_f} | IL_ALIASES.get(il_f.replace(" ", ""), set())
    out = []
    for raw in norm_text(isim).split():
        if raw in STOP or len(raw) < 2 and not raw.isdigit():
            continue
        if il_f and raw in il_drop:
            continue
        st = _stem_token(raw)
        if st.endswith("si") and st[:-2] in ("misafirhane",):
            st = st[:-2]
        if st and st not in STOP:
            out.append(st)
    return frozenset(out)


def distinctive(toks: frozenset[str]) -> frozenset[str]:
    return frozenset(t for t in toks if t not in GENERIC)


def phone_key(raw: str) -> str:
    d = re.sub(r"\D", "", raw or "")
    if d.startswith("90") and len(d) >= 12:
        d = d[2:]
    d = d.lstrip("0")
    return d if len(d) == 10 else ""


def fmt_phone(raw: str) -> str:
    k = phone_key(raw)
    if not k:
        return (raw or "").strip()
    return f"(0{k[0:3]}) {k[3:6]} {k[6:8]} {k[8:10]}"


def category(text: str) -> str:
    n = norm_text(text)
    rules = [
        (r"ogretmenevi|ogretmen", "ogretmenevi"),
        (r"polisevi|emniyet|polis", "polisevi"),
        (r"uygulama oteli|uygulama otel", "uygulama"),
        (r"orduevi|askeri|gazino|kislasi|garnizon|tsk|msb|kara kuvvet|hava kuvvet|deniz kuvvet|jandarma|astsubay|subay|komutanlig", "orduevi"),
        (r"\bdsi\b", "dsi"),
        (r"karayollari", "karayollari"),
        (r"\bdhmi\b|hava meydan|havalimani", "dhmi"),
        (r"hakimevi|adliye|adalet", "adalet"),
        (r"universite", "universite"),
        (r"\bptt\b", "ptt"),
        (r"tcdd|demiryol", "tcdd"),
        (r"orman", "orman"),
        (r"hekimevi|saglik|hastane", "saglik"),
    ]
    for pat, cat in rules:
        if re.search(pat, n):
            return cat
    return "misafirhane"


TIP_BY_CAT = {
    "ogretmenevi": "Öğretmenevi",
    "polisevi": "Polisevi",
    "orduevi": "Orduevi",
    "uygulama": "Uygulama Oteli",
    "dsi": "DSİ Misafirhanesi",
    "karayollari": "Karayolları Misafirhanesi",
    "dhmi": "DHMİ Misafirhanesi",
    "ptt": "PTT Misafirhanesi",
    "tcdd": "TCDD Misafirhanesi",
    "orman": "Orman Misafirhanesi",
    "saglik": "Sağlık Müdürlüğü Misafirhanesi",
}


def tip_for(cat: str, text: str) -> str:
    if cat in TIP_BY_CAT:
        return TIP_BY_CAT[cat]
    n = norm_text(text)
    if cat == "adalet":
        return "Hakimevi" if "hakimevi" in n else "Adalet Bakanlığı Misafirhanesi"
    if cat == "universite":
        if "konukevi" in n:
            return "Üniversite Konukevi"
        if "sosyal tesis" in n:
            return "Üniversite Sosyal Tesisi"
        return "Üniversite Misafirhanesi"
    for needle, tip in (
        ("belediye", "Belediye Misafirhanesi"),
        ("maliye", "Maliye Misafirhanesi"),
        ("defterdarlik", "Maliye Misafirhanesi"),
        ("tedas", "TEDAŞ Misafirhanesi"),
        ("teias", "TEİAŞ Misafirhanesi"),
        ("meteoroloji", "Meteoroloji Misafirhanesi"),
        ("ozel idare", "İl Özel İdaresi Misafirhanesi"),
        ("sgk", "SGK Misafirhanesi"),
        ("sosyal guvenlik", "SGK Misafirhanesi"),
        ("tarim", "Tarım Misafirhanesi"),
        ("cevre", "Çevre ve Şehircilik Misafirhanesi"),
        ("sendika", "Sendika Misafirhanesi"),
        ("diyanet", "Diyanet Misafirhanesi"),
        ("genclik", "Gençlik ve Spor Misafirhanesi"),
        ("gumruk", "Gümrük Misafirhanesi"),
        ("konukevi", "Konukevi"),
    ):
        if needle in n:
            return tip
    return "Kamu Misafirhanesi"


# ---------------------------------------------------------------- il mapping

def build_il_map(master_ils: list[str]) -> dict[str, str]:
    m = {}
    for il in master_ils:
        k = norm_text(il).replace(" ", "")
        m[k] = il
    m["afyon"] = m.get("afyonkarahisar", "Afyonkarahisar")
    for k in ("kktc", "kibris", "kuzeykibris", "kuzeykibristurkcumhuriyeti", "lefkosa"):
        m[k] = m.get("kibris", "Kıbrıs")
    m["icel"] = m.get("mersin", "Mersin")
    return m


def map_il(raw: str, il_map: dict[str, str]) -> str:
    k = norm_text(raw).replace(" ", "").replace("-", "")
    return il_map.get(k, "")


# ---------------------------------------------------------------- records

def valid_coord(lat, lng) -> bool:
    try:
        lat, lng = float(lat), float(lng)
    except (TypeError, ValueError):
        return False
    return 35.0 <= lat <= 43.0 and 25.0 <= lng <= 45.5


def clean_display_name(isim: str) -> str:
    s = re.sub(r"\s+", " ", isim or "").strip()
    s = re.sub(r"\s*\((?:[^)]*konaklama[^)]*)\)\s*", " ", s, flags=re.I)
    s = re.sub(r"\s+ve\s+Ak[şs]am\s+Sanat\s+Okulu(\s+M[üu]d[üu]rl[üu][ğg][üu])?\s*$", "", s, flags=re.I)
    s = re.sub(r"\s+M[üu]d[üu]rl[üu][ğg][üu]\s*$", "", s, flags=re.I)
    s = s.replace("Öğretmen Evi", "Öğretmenevi").replace("Polis Evi", "Polisevi").replace("Ordu Evi", "Orduevi")
    if s.isupper():
        s = " ".join(w[:1] + w[1:].replace("I", "ı").replace("İ", "i").lower() for w in s.split())
    return s.strip()


def display_with_il(isim: str, il: str, ilce: str) -> str:
    s = clean_display_name(isim)
    if norm_text(il) in norm_text(s).split():
        return s
    s2 = re.sub(r"^Merkez\s+", "", s, flags=re.I)
    return f"{il} {s2}".strip()


class Rec:
    __slots__ = ("src", "url", "il", "ilce", "isim", "tel", "tel2", "adres", "kurum", "statu", "lat", "lng",
                 "toks", "dist", "cat", "raw", "atoks")

    def __init__(self, src, url, il, ilce, isim, tel, adres, kurum, statu, lat, lng, raw, tel2=""):
        self.src, self.url, self.il, self.ilce, self.isim = src, url, il, ilce, isim
        self.tel, self.tel2, self.adres, self.kurum, self.statu = tel, tel2, adres, kurum, statu
        ok = valid_coord(lat, lng)
        self.lat = float(lat) if ok else None
        self.lng = float(lng) if ok else None
        self.toks = tokens(isim, il)
        ilce_n = norm_text(ilce)
        self.dist = frozenset(t for t in distinctive(self.toks) if t != ilce_n or True)
        self.cat = category(f"{isim} {statu} {kurum}")
        self.raw = raw
        self.atoks = addr_tokens(adres, il)

    def phones(self) -> set[str]:
        return {p for p in (phone_key(self.tel), phone_key(self.tel2)) if p}


def dist_m(a, b) -> float | None:
    if a.lat is None or b.lat is None:
        return None
    return haversine_m(a.lat, a.lng, b.lat, b.lng)


def ilce_of_master(t: dict) -> str:
    if t.get("ilce"):
        return norm_text(str(t["ilce"]))
    return ""


class MRec:
    """Master kaydı (salt okunur görünüm)."""

    def __init__(self, idx: int, t: dict):
        self.idx = idx
        self.t = t
        self.il = str(t.get("il") or "").strip()
        self.isim = str(t.get("isim") or "").strip()
        self.toks = tokens(self.isim, self.il)
        self.dist = distinctive(self.toks)
        self.cat = category(f"{self.isim} {t.get('tip') or ''}")
        self.tel = phone_key(str(t.get("telefon") or ""))
        self.blob = norm_text(f"{self.isim} {t.get('adres') or ''} {t.get('ilce') or ''}")
        self.atoks = addr_tokens(str(t.get("adres") or ""), self.il)
        ok = valid_coord(t.get("latitude"), t.get("longitude"))
        self.lat = float(t["latitude"]) if ok else None
        self.lng = float(t["longitude"]) if ok else None


def compare(s: Rec, m: MRec) -> tuple[str, str] | None:
    """('match'|'uncertain', neden) ya da None."""
    d = dist_m(s, m)
    same_cat = s.cat == m.cat
    ilce_n = norm_text(s.ilce)
    ilce_in = bool(ilce_n) and ilce_n not in ("merkez",) and re.search(rf"\b{re.escape(ilce_n)}\b", m.blob) is not None

    if s.toks and s.toks == m.toks:
        return "match", "aynı isim"
    if s.dist and s.dist == m.dist and same_cat:
        return "match", "aynı ayırt edici isim + aynı tür"
    sp = s.phones()
    if m.tel and m.tel in sp:
        if (s.dist & m.dist) or same_cat or (d is not None and d < 1500):
            return "match", "aynı telefon"
        return "uncertain", "aynı telefon ama isim/tür farklı"
    if d is not None and d <= 60 and same_cat:
        return "match", f"aynı konum (~{int(d)} m) + aynı tür"
    if d is not None and d <= 150 and (s.dist & m.dist):
        return "match", f"yakın konum (~{int(d)} m) + ortak isim"
    if same_cat and s.atoks and m.atoks:
        common = s.atoks & m.atoks
        ajac = len(common) / max(1, len(s.atoks | m.atoks))
        if len(common) >= 3 and ajac >= 0.5:
            return "match", "aynı adres + aynı tür"
        if len(common) >= 3 and ajac >= 0.35 and (d is None or d < 2000):
            return "uncertain", "benzer adres + aynı tür"
    if same_cat and s.dist and m.dist and (s.dist <= m.dist or m.dist <= s.dist):
        small = s.dist if len(s.dist) <= len(m.dist) else m.dist
        if len(small) >= 2 or (ilce_in and (d is None or d < 5000)):
            return "match", "isim birbirini kapsıyor + aynı tür"
        return "uncertain", "isim kısmen örtüşüyor"
    if same_cat and ilce_in and (d is None or d < 3000):
        if not s.dist or not m.dist:
            return "uncertain", "aynı ilçe + aynı tür (isim genel)"
        jac = len(s.dist & m.dist) / max(1, len(s.dist | m.dist))
        if jac >= 0.34:
            return "uncertain", "aynı ilçe + aynı tür + benzer isim"
    if same_cat and d is not None:
        if s.cat != "misafirhane" and d <= 500:
            return "uncertain", f"aynı tür, yakın konum (~{int(d)} m), isim farklı"
        if s.cat == "misafirhane" and (d <= 100 or (d <= 500 and (s.dist & m.dist))):
            return "uncertain", f"yakın konum (~{int(d)} m), isim farklı"
    if d is not None and d <= 500 and {s.cat, m.cat} <= {"saglik", "misafirhane"} and "saglik" in {s.cat, m.cat} and s.cat != m.cat:
        return "uncertain", f"yakın konum (~{int(d)} m), sağlık/hekimevi olabilir"
    if s.dist and m.dist and same_cat:
        jac = len(s.dist & m.dist) / max(1, len(s.dist | m.dist))
        if jac >= 0.6:
            return "uncertain", "benzer isim + aynı tür"
    return None


def same_facility(a: Rec, b: Rec) -> bool:
    if a.il != b.il:
        return False
    d = dist_m(a, b)
    same_cat = a.cat == b.cat
    if a.toks and a.toks == b.toks:
        return d is None or d < 3000
    if a.dist and a.dist == b.dist and same_cat:
        return d is None or d < 3000
    if a.phones() & b.phones():
        return bool(a.dist & b.dist) or (same_cat and (d is None or d < 2000))
    if d is not None and d <= 60 and same_cat:
        return True
    if d is not None and d <= 150 and (a.dist & b.dist):
        return True
    if same_cat and a.dist and b.dist and (a.dist <= b.dist or b.dist <= a.dist):
        small = a.dist if len(a.dist) <= len(b.dist) else b.dist
        if len(small) >= 2 and (d is None or d < 3000):
            return True
        an, bn = norm_text(a.ilce), norm_text(b.ilce)
        if an and an == bn and (d is None or d < 3000):
            return True
    return False


def load_sources(parsed: dict, il_map: dict[str, str]) -> tuple[list[Rec], dict]:
    recs: list[Rec] = []
    excl = defaultdict(list)
    for r in parsed["meb"]:
        il = map_il(r["il"], il_map)
        if not il:
            excl["il eşleşmedi"].append(r)
            continue
        recs.append(Rec("meb", r["url"], il, r["ilce"], r["isim"], r["telefon"], "", r["kurum"], "Öğretmenevi",
                        None, None, r))
    for r in parsed["kamutesisleri"]:
        il = map_il(r["il"], il_map)
        if r.get("closed"):
            excl["kalıcı kapalı (kamutesisleri)"].append(r)
            continue
        if "LodgingBusiness" not in (r.get("types") or []):
            excl["konaklama yok (restoran/gazino)"].append(r)
            continue
        if not il:
            excl["il eşleşmedi"].append(r)
            continue
        recs.append(Rec("kamutesisleri", r["url"], il, r["ilce"], r["isim"], r["telefon"], r["adres"], r["kurum"],
                        r["statu"], r["latitude"], r["longitude"], r))
    for r in parsed["kamusosyal"]:
        il = map_il(r["il"], il_map)
        n = norm_text(r["isim"])
        if "konaklama bulunmamaktadir" in n or "konaklama yoktur" in n or re.search(r"\bkapali\b|\bkapatildi", n):
            excl["konaklama yok / kapalı (kamusosyal)"].append(r)
            continue
        if not il:
            excl["il eşleşmedi"].append(r)
            continue
        recs.append(Rec("kamusosyal", r["url"], il, r["ilce"], r["isim"], r["telefon"], r["adres"], r["kurum"],
                        r["statu"], r["latitude"], r["longitude"], r, tel2=r.get("telefon2", "")))
    return recs, excl


def cluster(recs: list[Rec]) -> list[list[Rec]]:
    parent = list(range(len(recs)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    by_il = defaultdict(list)
    for i, r in enumerate(recs):
        by_il[r.il].append(i)
    for il, ids in by_il.items():
        for a_i in range(len(ids)):
            for b_i in range(a_i + 1, len(ids)):
                a, b = recs[ids[a_i]], recs[ids[b_i]]
                if a.src == b.src and a.url == b.url:
                    continue
                if same_facility(a, b):
                    ra, rb = find(ids[a_i]), find(ids[b_i])
                    if ra != rb:
                        parent[ra] = rb
    groups = defaultdict(list)
    for i in range(len(recs)):
        groups[find(i)].append(recs[i])
    return list(groups.values())


SRC_PRI = {"kamusosyal": 0, "kamutesisleri": 1, "meb": 2}


def build_entry(group: list[Rec]) -> dict:
    g = sorted(group, key=lambda r: SRC_PRI[r.src])
    named = next((r for r in g if r.src != "meb"), g[0])
    il = named.il
    ilce = next((r.ilce for r in g if r.ilce), "")
    coord = next((r for r in g if r.lat is not None), None)
    meb = next((r for r in g if r.src == "meb"), None)
    tel_src = meb.tel if meb and phone_key(meb.tel) else next((r.tel for r in g if phone_key(r.tel)), "")
    adres = next((r.adres for r in g if r.adres), "")
    if not adres and ilce:
        adres = f"{ilce.title() if ilce.isupper() else ilce}, {il}"
    text = " ".join(f"{r.isim} {r.statu} {r.kurum}" for r in g)
    cat = named.cat
    return {
        "isim": display_with_il(named.isim, il, ilce),
        "tip": tip_for(cat, text),
        "il": il,
        "adres": adres,
        "telefon": fmt_phone(tel_src),
        "latitude": coord.lat if coord else None,
        "longitude": coord.lng if coord else None,
    }


def main() -> None:
    master = json.loads(MASTER.read_text(encoding="utf-8"))
    tesisler = master["tesisler"]
    master_ils = sorted({str(t.get("il") or "").strip() for t in tesisler if t.get("il")}, key=tr_sort_key)
    il_map = build_il_map(master_ils)
    mrecs = [MRec(i, t) for i, t in enumerate(tesisler)]
    m_by_il = defaultdict(list)
    for m in mrecs:
        m_by_il[m.il].append(m)

    parsed = json.loads(PARSED.read_text(encoding="utf-8"))
    recs, excluded = load_sources(parsed, il_map)
    groups = cluster(recs)

    meb_keys = defaultdict(list)
    for r in recs:
        if r.src == "meb":
            meb_keys[r.il].append(r)

    il_center = {}
    for il, lst in m_by_il.items():
        lats = sorted(m.lat for m in lst if m.lat is not None)
        lngs = sorted(m.lng for m in lst if m.lng is not None)
        if lats:
            il_center[il] = (lats[len(lats) // 2], lngs[len(lngs) // 2])

    matched, uncertain, additions, no_coord, bad_pin = [], [], [], [], []
    for g in groups:
        il = g[0].il
        best_match, unc = None, []
        for r in g:
            for m in m_by_il.get(il, []):
                res = compare(r, m)
                if not res:
                    continue
                if res[0] == "match":
                    best_match = (r, m, res[1])
                    break
                unc.append((r, m, res[1]))
            if best_match:
                break
        members = [{"kaynak": r.src, "isim": r.isim, "ilce": r.ilce, "telefon": r.tel, "url": r.url} for r in g]
        if best_match:
            r, m, why = best_match
            matched.append({"il": il, "kaynak_isim": r.isim, "master_isim": m.isim, "neden": why, "kaynaklar": members})
            continue
        entry = build_entry(g)
        if unc:
            r, m, why = unc[0]
            uncertain.append({
                "il": il, "aday": entry, "benzer_master": {"isim": m.isim, "tip": m.t.get("tip"), "adres": m.t.get("adres"), "telefon": m.t.get("telefon")},
                "neden": why, "kaynaklar": members,
            })
            continue
        cats = {r.cat for r in g}
        srcs = {r.src for r in g}
        if "ogretmenevi" in cats and "meb" not in srcs:
            uncertain.append({
                "il": il, "aday": entry, "benzer_master": None,
                "neden": "MEB resmi öğretmenevi listesinde yok (kapanmış/devredilmiş olabilir)", "kaynaklar": members,
            })
            continue
        if entry["latitude"] is None:
            no_coord.append({"il": il, "aday": entry, "kaynaklar": members})
            continue
        c = il_center.get(il)
        if c and haversine_m(entry["latitude"], entry["longitude"], c[0], c[1]) > 180000:
            bad_pin.append({"il": il, "aday": entry, "kaynaklar": members,
                            "neden": f"kaynaktaki konum ilden ~{int(haversine_m(entry['latitude'], entry['longitude'], c[0], c[1]) / 1000)} km uzakta"})
            continue
        additions.append({"entry": entry, "kaynaklar": members})

    # Adaylar arası son yineleme kontrolü
    final, dropped_internal = [], []
    for a in additions:
        e = a["entry"]
        ra = Rec("aday", "", e["il"], "", e["isim"], e["telefon"], e["adres"], "", e["tip"], e["latitude"], e["longitude"], e)
        dup = None
        for f in final:
            fe = f["entry"]
            rb = Rec("aday", "", fe["il"], "", fe["isim"], fe["telefon"], fe["adres"], "", fe["tip"], fe["latitude"], fe["longitude"], fe)
            if same_facility(ra, rb):
                dup = fe["isim"]
                break
        if dup:
            dropped_internal.append({"isim": e["isim"], "il": e["il"], "ayni": dup})
            continue
        final.append(a)

    # Slug-only (sayfası açılmayan kamusosyal kayıtları)
    all_recs_by_il = defaultdict(list)
    for r in recs:
        all_recs_by_il[r.il].append(r)
    for f in final:
        e = f["entry"]
        all_recs_by_il[e["il"]].append(Rec("aday", "", e["il"], "", e["isim"], e["telefon"], "", "", e["tip"], e["latitude"], e["longitude"], e))
    slug_cov, slug_unc = 0, []
    for s in parsed.get("kamusosyal_slug_only", []):
        il = map_il(s["il_slug"], il_map)
        rs = Rec("kamusosyal", s["url"], il, "", s["isim"], "", "", "", "", None, None, s)
        n = norm_text(s["isim"])
        if "konaklama bulunmamaktadir" in n or "konaklama yoktur" in n:
            excluded["konaklama yok / kapalı (kamusosyal)"].append(s)
            continue
        hit = any(compare(rs, m) and compare(rs, m)[0] == "match" for m in m_by_il.get(il, []))
        if not hit:
            hit = any(same_facility(rs, r) for r in all_recs_by_il.get(il, []))
        if hit:
            slug_cov += 1
        else:
            slug_unc.append({"il": il or s["il_slug"], "isim_slugdan": s["isim"], "url": s["url"],
                             "neden": "Kaynak sayfası veri döndürmüyor; adres/telefon/konum doğrulanamadı"})

    # Tüm veritabanı son yineleme kontrolü (master + yeni)
    post_dups = []
    for f in final:
        e = f["entry"]
        ra = Rec("aday", "", e["il"], "", e["isim"], e["telefon"], e["adres"], "", e["tip"], e["latitude"], e["longitude"], e)
        for m in m_by_il.get(e["il"], []):
            res = compare(ra, m)
            if res and res[0] == "match":
                post_dups.append({"yeni": e["isim"], "master": m.isim, "neden": res[1]})
                break
    post_dup_names = {p["yeni"] for p in post_dups}
    final = [f for f in final if f["entry"]["isim"] not in post_dup_names]

    # Rapor
    per_il_src = defaultdict(Counter)
    for r in recs:
        per_il_src[r.il][r.src] += 1
    added_by_il = Counter(f["entry"]["il"] for f in final)
    tip_counts = Counter(f["entry"]["tip"] for f in final)
    examined = len(parsed["meb"]) + len(parsed["kamutesisleri"]) + len(parsed["kamusosyal"]) + len(parsed.get("kamusosyal_slug_only", []))

    report = {
        "master": str(MASTER),
        "master_tesis_sayisi": len(tesisler),
        "taranan_il": len([il for il in master_ils if per_il_src.get(il)]),
        "kaynaklar": {
            "meb": len(parsed["meb"]),
            "kamutesisleri": len(parsed["kamutesisleri"]),
            "kamusosyal_veri": len(parsed["kamusosyal"]),
            "kamusosyal_sayfasi_acilmayan": len(parsed.get("kamusosyal_slug_only", [])),
        },
        "incelenen_kayit": examined,
        "elenen": {k: len(v) for k, v in excluded.items()},
        "fiziksel_tesis_grubu": len(groups),
        "mevcutla_eslesen_grup": len(matched),
        "yeni_eklenecek": len(final),
        "yeni_il_bazinda": {il: added_by_il[il] for il in sorted(added_by_il, key=tr_sort_key)},
        "yeni_tip_bazinda": dict(tip_counts.most_common()),
        "belirsiz": len(uncertain),
        "koordinatsiz_yeni": len(no_coord),
        "hatali_konum": len(bad_pin),
        "adaylar_arasi_tekrar_elenen": len(dropped_internal),
        "son_kontrol_elenen": len(post_dups),
        "slug_only_eslesen": slug_cov,
        "slug_only_belirsiz": len(slug_unc),
        "il_kaynak_dagilimi": {il: dict(per_il_src.get(il, {})) for il in master_ils},
    }
    OUT_DIR.joinpath("preview_additions.json").write_text(
        json.dumps([f["entry"] for f in final], ensure_ascii=False, indent=2), encoding="utf-8")
    OUT_DIR.joinpath("preview_report.json").write_text(json.dumps({
        "ozet": report,
        "eklenecekler": final,
        "belirsizler": uncertain,
        "koordinatsizlar": no_coord,
        "hatali_konum": bad_pin,
        "slug_only_belirsiz": slug_unc,
        "adaylar_arasi_tekrar": dropped_internal,
        "son_kontrol": post_dups,
        "eslesenler": matched,
    }, ensure_ascii=False, indent=1), encoding="utf-8")

    lines = [json.dumps(report, ensure_ascii=False, indent=1), "", "=== EKLENECEKLER ==="]
    for il in sorted(added_by_il, key=tr_sort_key):
        lines.append(f"\n## {il} ({added_by_il[il]})")
        for f in final:
            e = f["entry"]
            if e["il"] == il:
                lines.append(f"  + {e['isim']} | {e['tip']} | {e['telefon']} | {e['adres'][:70]}")
    lines.append("\n=== BELİRSİZLER ===")
    for u in sorted(uncertain, key=lambda x: tr_sort_key(x["il"])):
        b = u["benzer_master"]["isim"] if u["benzer_master"] else "-"
        lines.append(f"  ? [{u['il']}] {u['aday']['isim']}  <->  {b}  ({u['neden']})")
    lines.append("\n=== KOORDİNATSIZ (eklenmedi) ===")
    for n in no_coord:
        lines.append(f"  - [{n['il']}] {n['aday']['isim']} | {n['aday']['telefon']}")
    lines.append("\n=== HATALI KONUM (eklenmedi) ===")
    for b in bad_pin:
        lines.append(f"  - [{b['il']}] {b['aday']['isim']} ({b['neden']})")
    lines.append("\n=== SAYFASI AÇILMAYAN, EŞLEŞMEYEN (kamusosyal) ===")
    for s in slug_unc:
        lines.append(f"  - [{s['il']}] {s['isim_slugdan']}")
    OUT_DIR.joinpath("preview_report.txt").write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "il_kaynak_dagilimi"}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
