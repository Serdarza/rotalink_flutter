import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
TR = str.maketrans("çÇğĞıİöÖşŞüÜ", "ccggiioossuu")
norm = lambda s: " ".join(w.translate(TR).lower() for w in (s or "").split())
EXCL = re.compile(r"ek yatak|ilave|cocuk|bebek|ogrenci|kahvalti|yemek|otopark|havuz|aylik|haftalik|saatlik|grup|toplanti|salon")
PP = re.compile(r"kisi ?bas|kisi/gece|kisi ?gecelik|kisi ?icin")
SINGLE = re.compile(r"tek kisilik|1 kisilik|tek yatak|single")

d = json.loads((Path(__file__).resolve().parents[2] / "rotalink-data/fiyatlar.json").read_text(encoding="utf-8"))


def price(t, word):
    best = None
    shared = t.get("kategoriler") or []
    for tb in t.get("tablolar") or []:
        cats = tb.get("kategoriler") or shared
        ids = {(c.get("id") if isinstance(c, dict) else c) for c in cats
               if word in norm(f"{c.get('id','')} {c.get('ad','')}" if isinstance(c, dict) else c)}
        for r in tb.get("satirlar") or []:
            name = norm(r.get("ad"))
            if EXCL.search(name):
                continue
            unit = norm(r.get("birim") or tb.get("birim") or t.get("birim") or "")
            if not (PP.search(unit) or PP.search(name) or r.get("kisi") == 1 or SINGLE.search(name)):
                continue
            for i in ids:
                v = (r.get("fiyatlar") or {}).get(i)
                if isinstance(v, (int, float)) and v > 0 and (best is None or v < best):
                    best = v
    return best


stat = Counter()
by_il = defaultdict(list)
for e in d["tesisler"]:
    t = e.get("tarife") or {}
    if t.get("dogrulama") not in ("resmi_kaynak", "tesis_dogruladi"):
        stat["dogrulanmamis"] += 1
        continue
    s, k = price(t, "sivil"), price(t, "kamu")
    stat["sivil" if s else ("kamu" if k else "yok")] += 1
    if s:
        by_il[e["il"]].append((s, e["isim"]))
print(stat)
print("sivil fiyatli il sayisi", len(by_il))
for il in ["Ankara", "Antalya", "İzmir", "Muğla", "Adana"]:
    print(il, sorted(by_il.get(il, []))[:3])
