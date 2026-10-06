"""TÜRKPATENT tescilli coğrafi işaretlerinden il başına hediyelik ürün listesi.

Girdi : scripts/out/ci_all.json (hediyelik_fetch_ci.py)
Çıktı : scripts/out/hediyelik.json + scripts/out/hediyelik_onizleme.md
"""
import collections
import json
import pathlib
import re
import sys
from datetime import date

sys.stdout.reconfigure(encoding="utf-8")
OUT = pathlib.Path(__file__).parent / "out"
ROOT = pathlib.Path(__file__).resolve().parents[1]
MAX_PER_IL = 10_000
MAX_PER_KATEGORI = 10_000

rows = json.loads((OUT / "ci_all.json").read_text(encoding="utf-8"))
master = json.loads((ROOT / "assets/data/master_database_updated.json").read_text(encoding="utf-8"))
APP_ILLER = sorted({t["il"] for t in master["tesisler"]})

IL_ALIAS = {"Hakkâri": "Hakkari", "İstanbul (Asya)": "İstanbul", "İstanbul (Avrupa)": "İstanbul"}

# Ürün grubu → (kategori etiketi, açıklamadaki tekil ad, öncelik: küçük = önce)
GROUPS = {
    "Halılar ve kilimler": ("El sanatı", "halı / kilim", 1),
    "Dokumalar": ("El sanatı", "dokuma", 1),
    "Halılar, kilimler ve dokumalar dışında kalan el sanatı ürünleri": ("El sanatı", "el sanatı ürünü", 1),
    "Çikolata, şekerleme ve türevi ürünler": ("Tatlı / şekerleme", "şekerleme", 1),
    "Fırıncılık ve pastacılık mamulleri, hamur işleri, tatlılar": ("Tatlı / şekerleme", "tatlı", 1),
    "Bal": ("Bal / peynir / şarküteri", "bal", 2),
    "Peynirler": ("Bal / peynir / şarküteri", "peynir", 2),
    "Peynirler ve tereyağı dışında kalan süt ürünleri": ("Bal / peynir / şarküteri", "süt ürünü", 3),
    "İşlenmiş ve işlenmemiş et ürünleri": ("Bal / peynir / şarküteri", "et ürünü", 2),
    "Tereyağı dâhil katı ve sıvı yağlar": ("Yağ / baharat", "yağ", 2),
    "Yiyecekler için çeşni / lezzet vericiler, soslar ve tuz": ("Yağ / baharat", "baharat / çeşni", 2),
    "İşlenmiş ve işlenmemiş meyve ve sebzeler ile mantarlar": ("Meyve / kuruyemiş", "tarım ürünü", 3),
    "Alkolsüz içecekler": ("İçecek", "içecek", 3),
    "Diğer ürünler": ("Yöresel ürün", "yöresel ürün", 2),
}

# "Diğer ürünler" grubunda el yapımı eşyalar.
CRAFT_NAME = re.compile(
    r"bıçağ|bıçak|baston|bebe|sabun|kolye|bilezi|çömle|çini|taşı|tespih|kaşık|tarak|semaver|sandığ|"
    r"oya|işleme|telkari|gümüş|bakır|keçe|sepet|zembil|çarık|nazar|kalsit|pomza|mermer|ney|cebe|fes",
    re.I,
)

# Fırıncılık grubundaki yemek/hamur işleri yerine eve götürülebilen tatlılar.
CARRYABLE_SWEET = re.compile(
    r"helva|lokum|pestil|köme|cezerye|pişmaniye|şeker|akide|baklava|kurabiye|peksimet|galeta|"
    r"bisküvi|cevizli sucuk|bastık|tahinli|çörek|kete|kaygana|kömbe|nuga|leblebi|gaziler|kadayıf",
    re.I,
)
CARRYABLE_MEAT = re.compile(r"pastırma|sucuk|kavurma|salam|sucuğu|kurutulmuş", re.I)
BANNED = re.compile(
    r"şarap|rakı|likör|bira|tütün|nargile|sigara|puro|enfiye|şıra|kanyak|votka|viski|alkol|cin\b|mezcal|"
    r"hardaliye|boğazkere|öküzgözü|şerbetçiotu|kalecik karası|çalkarası|ada karası|misket üzümü|lüle taşı",
    re.I,
)
# Taze tüketilen / taşınması zor ürünler ve yemekler (yöresel ama hediyelik değil).
NOT_SOUVENIR = re.compile(
    r"karpuz|kavun|lahana|marul|ıspanak|pırasa|kabağı\b|kabak\b|domates|yoğur|ayran|süt\b|"
    r"kebab|köfte|çorba|yemeğ|dolma(?!sı)|pilav|börek|kısır|sarma içi|tava\b|enginar|turp",
    re.I,
)
# Tescilli ama alınıp götürülen bir hediye olmayan kayıtlar (hayvan, yer, tekne, yapı taşı, ham madde).
NOT_GIFT = re.compile(
    r"köpe|koyunu|keçisi|sığırı|\batı\b|kaplıca|gulet|kotra|kağnı|lüfer|kahvaltısı|traverten|mermer|"
    r"pamuğu|tiftiği|hoşafı|sarısı ipeği|mardin taşı|lefke taşı|tohumu|buğdayı|granit|andezit|yonca|"
    r"sucuk içi|salatası|(?<!şeker )böreği",
    re.I,
)
# Coğrafi işaret listesinde olan, ilin simgesi sayılan ürünler: her zaman listenin başında.
PINNED = {"Antep Baklavası", "İzmit Pişmaniyesi", "Antep Fıstığı", "Afyon Lokumu", "Malatya Kayısısı", "Rize Çayı"}


def il_of(r):
    il = (r.get("CityName") or "").strip()
    return IL_ALIAS.get(il, il)


def keep(r):
    if r["StatusName"] != "Tescilli":
        return False
    g = r["ProductGroupName"]
    if g not in GROUPS:
        return False
    name = r["Name"]
    if name.strip() in PINNED:
        return True
    if BANNED.search(name) or NOT_SOUVENIR.search(name) or NOT_GIFT.search(name):
        return False
    if g.startswith("Fırıncılık") and not CARRYABLE_SWEET.search(name):
        return False
    if g.startswith("İşlenmiş ve işlenmemiş et") and not CARRYABLE_MEAT.search(name):
        return False
    return True


def tidy(name):
    name = re.sub(r"\s+", " ", name).strip()
    return name if name != name.upper() else name.title()


def kategori_of(r):
    kategori = GROUPS[r["ProductGroupName"]][0]
    if r["ProductGroupName"] == "Diğer ürünler" and CRAFT_NAME.search(r["Name"]):
        return "El sanatı"
    return kategori


def description(r, il):
    _, tekil, _ = GROUPS[r["ProductGroupName"]]
    if r["ProductGroupName"] == "Diğer ürünler" and CRAFT_NAME.search(r["Name"]):
        tekil = "el sanatı ürünü"
    ilce = (r.get("DistrictName") or "").strip()
    yer = f"{il} / {ilce}" if ilce and ilce.lower() not in ("merkez", il.lower()) else il
    tur = (r.get("TypeName") or "").strip() or "Coğrafi işaret"
    return f"{yer} yöresine özgü {tekil}. {tur} ile tescilli coğrafi işaretli ürün."


WIKI = json.loads((OUT / "ci_wiki.json").read_text(encoding="utf-8"))


def score(r, il):
    _, _, prio = GROUPS[r["ProductGroupName"]]
    s = prio * 10
    if r["Name"].strip() in PINNED:
        s -= 100
    if WIKI.get(str(r["Id"])):
        s -= 15
    if (r.get("TypeName") or "").strip() == "Menşe Adı":
        s -= 3
    if r["Name"].lower().startswith(il.lower()):
        s -= 4
    return (s, r["Name"])


by_il = collections.defaultdict(list)
for r in rows:
    if keep(r):
        by_il[il_of(r)].append(r)

def pick(il, cat_limit):
    picked, per_cat, seen = [], collections.Counter(), set()
    for r in sorted(by_il.get(il, []), key=lambda r: score(r, il)):
        kategori = kategori_of(r)
        key = re.sub(r"\W", "", r["Name"].lower())
        if key in seen or per_cat[kategori] >= cat_limit:
            continue
        seen.add(key)
        per_cat[kategori] += 1
        picked.append(
            {
                "ad": tidy(r["Name"]),
                "aciklama": description(r, il),
                "kategori": kategori,
                "cografi_isaret": True,
                "tescil_turu": (r.get("TypeName") or "").strip(),
                "kaynak_id": r["Id"],
            }
        )
        if len(picked) >= MAX_PER_IL:
            break
    return picked


result = {}
for il in APP_ILLER:
    picked = pick(il, MAX_PER_KATEGORI)
    if len(picked) < 4:
        picked = pick(il, 3)
    if picked:
        result[il] = picked

# Kullanıcının açıkça belirttiği, coğrafi işaret listesinde olmayan bilinen ürünler.
EXTRAS = {
    "Düzce": [
        {
            "ad": "Tütün Kolonyası",
            "aciklama": "Düzce'den hediyelik olarak alınan, tütün çiçeği kokulu geleneksel kolonya.",
            "kategori": "Yöresel ürün",
            "cografi_isaret": False,
        }
    ],
}
for il, items in EXTRAS.items():
    result.setdefault(il, [])
    names = {x["ad"].lower() for x in result[il]}
    for it in items:
        if it["ad"].lower() not in names:
            result[il].insert(0, it)
    del result[il][MAX_PER_IL:]

doc = {
    "guncelleme": date.today().isoformat(),
    "kaynak": "TÜRKPATENT Coğrafi İşaretler Portalı (ci.turkpatent.gov.tr) — tescilli ürünler",
    "iller": result,
}
(OUT / "hediyelik.json").write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")

missing = [il for il in APP_ILLER if il not in result]
lines = [f"# Hediyelik önizleme ({sum(len(v) for v in result.values())} ürün, {len(result)} il)", ""]
if missing:
    lines += [f"Ürün bulunamayan iller: {', '.join(missing)}", ""]
for il, items in result.items():
    lines.append(f"## {il}")
    for it in items:
        mark = "" if it["cografi_isaret"] else " *(coğrafi işaret değil)*"
        lines.append(f"- **{it['ad']}** — {it['kategori']}{mark}")
    lines.append("")
(OUT / "hediyelik_onizleme.md").write_text("\n".join(lines), encoding="utf-8")
print(lines[0])
print("eksik:", missing)
print(collections.Counter(len(v) for v in result.values()))
