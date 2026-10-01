#!/usr/bin/env python3
"""Resmî kamu tesisi iletişim e-postalarını doğrular.

E-posta yalnızca getirilen resmî sayfanın (veya aynı sitedeki iletişim sayfasının
/ PDF'inin) metninden çıkarılır. Alan adı kalıbından adres üretilmez.
Kaynak URL'si olmayan adres kaydedilmez.

Girdi (salt okunur): rotalink-data master_database_updated.json, tesisler_adres.json,
fiyatlar.json. Mevcut fiyat ve tesis kayıtları değiştirilmez.
"""

from __future__ import annotations

import argparse
import json
import re
import threading
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import date
from html import unescape
from pathlib import Path
from urllib.parse import quote, unquote, urljoin, urlsplit, urlunsplit

import requests

TODAY = date.today().isoformat()
UA = (
    "Mozilla/5.0 (compatible; RotalinkEmailResearch/1.0; "
    "+https://github.com/Serdarza/rotalink_flutter)"
)
TR_MAP = str.maketrans(
    {
        "ç": "c",
        "Ç": "c",
        "ğ": "g",
        "Ğ": "g",
        "ı": "i",
        "İ": "i",
        "ö": "o",
        "Ö": "o",
        "ş": "s",
        "Ş": "s",
        "ü": "u",
        "Ü": "u",
    }
)
PROVINCES = [
    "Adana",
    "Adıyaman",
    "Afyonkarahisar",
    "Ağrı",
    "Amasya",
    "Ankara",
    "Antalya",
    "Artvin",
    "Aydın",
    "Balıkesir",
    "Bilecik",
    "Bingöl",
    "Bitlis",
    "Bolu",
    "Burdur",
    "Bursa",
    "Çanakkale",
    "Çankırı",
    "Çorum",
    "Denizli",
    "Diyarbakır",
    "Edirne",
    "Elazığ",
    "Erzincan",
    "Erzurum",
    "Eskişehir",
    "Gaziantep",
    "Giresun",
    "Gümüşhane",
    "Hakkari",
    "Hatay",
    "Isparta",
    "Mersin",
    "İstanbul",
    "İzmir",
    "Kars",
    "Kastamonu",
    "Kayseri",
    "Kırklareli",
    "Kırşehir",
    "Kocaeli",
    "Konya",
    "Kütahya",
    "Malatya",
    "Manisa",
    "Kahramanmaraş",
    "Mardin",
    "Muğla",
    "Muş",
    "Nevşehir",
    "Niğde",
    "Ordu",
    "Rize",
    "Sakarya",
    "Samsun",
    "Siirt",
    "Sinop",
    "Sivas",
    "Tekirdağ",
    "Tokat",
    "Trabzon",
    "Tunceli",
    "Şanlıurfa",
    "Uşak",
    "Van",
    "Yozgat",
    "Zonguldak",
    "Aksaray",
    "Bayburt",
    "Karaman",
    "Kırıkkale",
    "Batman",
    "Şırnak",
    "Bartın",
    "Ardahan",
    "Iğdır",
    "Yalova",
    "Karabük",
    "Kilis",
    "Osmaniye",
    "Düzce",
]
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")
BAD_TLD = {
    "png",
    "jpg",
    "jpeg",
    "gif",
    "svg",
    "webp",
    "css",
    "js",
    "ico",
    "woff",
    "woff2",
    "ttf",
    "map",
    "html",
    "php",
}
FREEMAIL = {
    "gmail.com",
    "hotmail.com",
    "outlook.com",
    "yahoo.com",
    "yahoo.com.tr",
    "hotmail.com.tr",
    "yandex.com",
    "windowslive.com",
    "live.com",
}
GENERIC_LOCAL = {
    "info",
    "iletisim",
    "bilgi",
    "kurum",
    "basin",
    "destek",
    "mem",
    "mudurluk",
    "bolge",
    "eposta",
    "mail",
    "contact",
    "iletisimmerkezi",
    "halklailiskiler",
    "genel",
    "basvuru",
}
REJECT_LOCAL = {
    "user",
    "name",
    "email",
    "example",
    "test",
    "domain",
    "username",
    "noreply",
    "no-reply",
    "donotreply",
    "webmaster",
    "postmaster",
    "hostmaster",
    "sentry",
}
STOP_TOKENS = {
    "ogretmenevi",
    "ogretmen",
    "misafirhane",
    "misafirhanesi",
    "misafirevi",
    "mudurlugu",
    "mudurluk",
    "universitesi",
    "universite",
    "belediyesi",
    "belediye",
    "baskanligi",
    "bolge",
    "ilce",
    "sehit",
    "sosyal",
    "tesisi",
    "tesisleri",
    "konukevi",
    "konuk",
    "uygulama",
    "oteli",
    "egitim",
    "dinlenme",
    "kamu",
    "personel",
    "genel",
    "merkez",
    "sube",
    "sefligi",
    "lokali",
    "evleri",
    "aksi",
    "asam",
    "sanat",
    "okulu",
    "mudurlugu",
    "ve",
    "ile",
    "icin",
    "olan",
    "tarihi",
}
# Resmî alan adları. E-posta değil; site ancak buradan açılırsa kabul edilir.
UNIVERSITIES = [
    ("cukurova universitesi", "cu.edu.tr", "Çukurova Üniversitesi"),
    ("adnan menderes universitesi", "adu.edu.tr", "Adnan Menderes Üniversitesi"),
    ("adiyaman universitesi", "adiyaman.edu.tr", "Adıyaman Üniversitesi"),
    ("afyon kocatepe universitesi", "aku.edu.tr", "Afyon Kocatepe Üniversitesi"),
    ("kocatepe universitesi", "aku.edu.tr", "Afyon Kocatepe Üniversitesi"),
    ("akdeniz universitesi", "akdeniz.edu.tr", "Akdeniz Üniversitesi"),
    ("amasya universitesi", "amasya.edu.tr", "Amasya Üniversitesi"),
    ("anadolu universitesi", "anadolu.edu.tr", "Anadolu Üniversitesi"),
    ("ankara haci bayram veli universitesi", "hacibayram.edu.tr", "Ankara Hacı Bayram Veli Üniversitesi"),
    ("haci bayram veli universitesi", "hacibayram.edu.tr", "Ankara Hacı Bayram Veli Üniversitesi"),
    ("ankara yildirim beyazit universitesi", "aybu.edu.tr", "Ankara Yıldırım Beyazıt Üniversitesi"),
    ("yildirim beyazit universitesi", "aybu.edu.tr", "Ankara Yıldırım Beyazıt Üniversitesi"),
    ("ankara universitesi", "ankara.edu.tr", "Ankara Üniversitesi"),
    ("ardahan universitesi", "ardahan.edu.tr", "Ardahan Üniversitesi"),
    ("erzurum teknik universitesi", "erzurum.edu.tr", "Erzurum Teknik Üniversitesi"),
    ("ataturk universitesi", "atauni.edu.tr", "Atatürk Üniversitesi"),
    ("agri ibrahim cecen universitesi", "agri.edu.tr", "Ağrı İbrahim Çeçen Üniversitesi"),
    ("ibrahim cecen universitesi", "agri.edu.tr", "Ağrı İbrahim Çeçen Üniversitesi"),
    ("batman universitesi", "batman.edu.tr", "Batman Üniversitesi"),
    ("bayburt universitesi", "bayburt.edu.tr", "Bayburt Üniversitesi"),
    ("bingol universitesi", "bingol.edu.tr", "Bingöl Üniversitesi"),
    ("bitlis eren universitesi", "beu.edu.tr", "Bitlis Eren Üniversitesi"),
    ("bogazici universitesi", "bogazici.edu.tr", "Boğaziçi Üniversitesi"),
    ("bursa uludag universitesi", "uludag.edu.tr", "Bursa Uludağ Üniversitesi"),
    ("uludag universitesi", "uludag.edu.tr", "Bursa Uludağ Üniversitesi"),
    ("cumhuriyet universitesi", "cumhuriyet.edu.tr", "Cumhuriyet Üniversitesi"),
    ("pamukkale universitesi", "pau.edu.tr", "Pamukkale Üniversitesi"),
    ("dicle universitesi", "dicle.edu.tr", "Dicle Üniversitesi"),
    ("kutahya dumlupinar universitesi", "dpu.edu.tr", "Kütahya Dumlupınar Üniversitesi"),
    ("dumlupinar universitesi", "dpu.edu.tr", "Kütahya Dumlupınar Üniversitesi"),
    ("duzce universitesi", "duzce.edu.tr", "Düzce Üniversitesi"),
    ("trakya universitesi", "trakya.edu.tr", "Trakya Üniversitesi"),
    ("ege universitesi", "ege.edu.tr", "Ege Üniversitesi"),
    ("erciyes universitesi", "erciyes.edu.tr", "Erciyes Üniversitesi"),
    ("eskisehir osmangazi universitesi", "ogu.edu.tr", "Eskişehir Osmangazi Üniversitesi"),
    ("osmangazi universitesi", "ogu.edu.tr", "Eskişehir Osmangazi Üniversitesi"),
    ("firat universitesi", "firat.edu.tr", "Fırat Üniversitesi"),
    ("gazi universitesi", "gazi.edu.tr", "Gazi Üniversitesi"),
    ("gaziantep universitesi", "gantep.edu.tr", "Gaziantep Üniversitesi"),
    ("giresun universitesi", "giresun.edu.tr", "Giresun Üniversitesi"),
    ("gumushane universitesi", "gumushane.edu.tr", "Gümüşhane Üniversitesi"),
    ("hacettepe universitesi", "hacettepe.edu.tr", "Hacettepe Üniversitesi"),
    ("hakkari universitesi", "hakkari.edu.tr", "Hakkari Üniversitesi"),
    ("hatay mustafa kemal universitesi", "mku.edu.tr", "Hatay Mustafa Kemal Üniversitesi"),
    ("mustafa kemal universitesi", "mku.edu.tr", "Hatay Mustafa Kemal Üniversitesi"),
    ("igdir universitesi", "igdir.edu.tr", "Iğdır Üniversitesi"),
    ("kafkas universitesi", "kafkas.edu.tr", "Kafkas Üniversitesi"),
    ("kahramanmaras sutcu imam universitesi", "ksu.edu.tr", "Kahramanmaraş Sütçü İmam Üniversitesi"),
    ("sutcu imam universitesi", "ksu.edu.tr", "Kahramanmaraş Sütçü İmam Üniversitesi"),
    ("karabuk universitesi", "karabuk.edu.tr", "Karabük Üniversitesi"),
    ("karamanoglu mehmetbey universitesi", "kmu.edu.tr", "Karamanoğlu Mehmetbey Üniversitesi"),
    ("kastamonu universitesi", "kastamonu.edu.tr", "Kastamonu Üniversitesi"),
    ("kocaeli universitesi", "kocaeli.edu.tr", "Kocaeli Üniversitesi"),
    ("kirikkale universitesi", "kku.edu.tr", "Kırıkkale Üniversitesi"),
    ("manisa celal bayar universitesi", "cbu.edu.tr", "Manisa Celal Bayar Üniversitesi"),
    ("celal bayar universitesi", "cbu.edu.tr", "Manisa Celal Bayar Üniversitesi"),
    ("mardin artuklu universitesi", "artuklu.edu.tr", "Mardin Artuklu Üniversitesi"),
    ("artuklu universitesi", "artuklu.edu.tr", "Mardin Artuklu Üniversitesi"),
    ("marmara universitesi", "marmara.edu.tr", "Marmara Üniversitesi"),
    ("mersin cag universitesi", "cag.edu.tr", "Çağ Üniversitesi"),
    ("cag universitesi", "cag.edu.tr", "Çağ Üniversitesi"),
    ("mersin universitesi", "mersin.edu.tr", "Mersin Üniversitesi"),
    ("mugla sitki kocman universitesi", "mu.edu.tr", "Muğla Sıtkı Koçman Üniversitesi"),
    ("sitki kocman universitesi", "mu.edu.tr", "Muğla Sıtkı Koçman Üniversitesi"),
    ("mus alparslan universitesi", "alparslan.edu.tr", "Muş Alparslan Üniversitesi"),
    ("alparslan universitesi", "alparslan.edu.tr", "Muş Alparslan Üniversitesi"),
    ("nevsehir haci bektas veli universitesi", "nevsehir.edu.tr", "Nevşehir Hacı Bektaş Veli Üniversitesi"),
    ("haci bektas veli universitesi", "nevsehir.edu.tr", "Nevşehir Hacı Bektaş Veli Üniversitesi"),
    ("nigde omer halisdemir universitesi", "ohu.edu.tr", "Niğde Ömer Halisdemir Üniversitesi"),
    ("omer halisdemir universitesi", "ohu.edu.tr", "Niğde Ömer Halisdemir Üniversitesi"),
    ("ordu universitesi", "odu.edu.tr", "Ordu Üniversitesi"),
    ("ortadogu teknik universitesi", "metu.edu.tr", "Orta Doğu Teknik Üniversitesi"),
    ("osmaniye korkut ata universitesi", "osmaniye.edu.tr", "Osmaniye Korkut Ata Üniversitesi"),
    ("korkut ata universitesi", "osmaniye.edu.tr", "Osmaniye Korkut Ata Üniversitesi"),
    ("recep tayyip erdogan universitesi", "erdogan.edu.tr", "Recep Tayyip Erdoğan Üniversitesi"),
    ("sakarya universitesi", "sakarya.edu.tr", "Sakarya Üniversitesi"),
    ("ondokuzmayis universitesi", "omu.edu.tr", "Ondokuz Mayıs Üniversitesi"),
    ("ondokuz mayis universitesi", "omu.edu.tr", "Ondokuz Mayıs Üniversitesi"),
    ("selcuk universitesi", "selcuk.edu.tr", "Selçuk Üniversitesi"),
    ("siirt universitesi", "siirt.edu.tr", "Siirt Üniversitesi"),
    ("suleyman demirel universitesi", "sdu.edu.tr", "Süleyman Demirel Üniversitesi"),
    ("tekirdag namik kemal universitesi", "nku.edu.tr", "Tekirdağ Namık Kemal Üniversitesi"),
    ("namik kemal universitesi", "nku.edu.tr", "Tekirdağ Namık Kemal Üniversitesi"),
    ("tokat gaziosmanpasa universitesi", "gop.edu.tr", "Tokat Gaziosmanpaşa Üniversitesi"),
    ("gaziosmanpasa universitesi", "gop.edu.tr", "Tokat Gaziosmanpaşa Üniversitesi"),
    ("tunceli munzur universitesi", "munzur.edu.tr", "Tunceli Munzur Üniversitesi"),
    ("munzur universitesi", "munzur.edu.tr", "Munzur Üniversitesi"),
    ("usak universitesi", "usak.edu.tr", "Uşak Üniversitesi"),
    ("yozgat bozok universitesi", "bozok.edu.tr", "Yozgat Bozok Üniversitesi"),
    ("bozok universitesi", "bozok.edu.tr", "Yozgat Bozok Üniversitesi"),
    ("yildiz teknik universitesi", "yildiz.edu.tr", "Yıldız Teknik Üniversitesi"),
    ("zonguldak bulent ecevit universitesi", "beun.edu.tr", "Zonguldak Bülent Ecevit Üniversitesi"),
    ("bulent ecevit universitesi", "beun.edu.tr", "Zonguldak Bülent Ecevit Üniversitesi"),
    ("cankiri karatekin universitesi", "karatekin.edu.tr", "Çankırı Karatekin Üniversitesi"),
    ("karatekin universitesi", "karatekin.edu.tr", "Çankırı Karatekin Üniversitesi"),
    ("inonu universitesi", "inonu.edu.tr", "İnönü Üniversitesi"),
    ("istanbul teknik universitesi", "itu.edu.tr", "İstanbul Teknik Üniversitesi"),
    ("istanbul universitesi", "istanbul.edu.tr", "İstanbul Üniversitesi"),
    ("izmir dokuz eylul universitesi", "deu.edu.tr", "Dokuz Eylül Üniversitesi"),
    ("dokuz eylul universitesi", "deu.edu.tr", "Dokuz Eylül Üniversitesi"),
    ("tinaztepe universitesi", "tinaztepe.edu.tr", "Tınaztepe Üniversitesi"),
    ("harran universitesi", "harran.edu.tr", "Harran Üniversitesi"),
    ("sirnak universitesi", "sirnak.edu.tr", "Şırnak Üniversitesi"),
    ("karadeniz teknik universitesi", "ktu.edu.tr", "Karadeniz Teknik Üniversitesi"),
    ("canakkale onsekiz mart universitesi", "comu.edu.tr", "Çanakkale Onsekiz Mart Üniversitesi"),
    ("onsekiz mart universitesi", "comu.edu.tr", "Çanakkale Onsekiz Mart Üniversitesi"),
    ("milli savunma universitesi", "msu.edu.tr", "Milli Savunma Üniversitesi"),
    ("galatasaray universitesi", "gsu.edu.tr", "Galatasaray Üniversitesi"),
    ("istanbul medeniyet universitesi", "medeniyet.edu.tr", "İstanbul Medeniyet Üniversitesi"),
    ("medeniyet universitesi", "medeniyet.edu.tr", "İstanbul Medeniyet Üniversitesi"),
    ("saglik bilimleri universitesi", "sbu.edu.tr", "Sağlık Bilimleri Üniversitesi"),
    ("yildiz teknik", "yildiz.edu.tr", "Yıldız Teknik Üniversitesi"),
]
UNIVERSITIES.sort(key=lambda item: len(item[0]), reverse=True)


def fold_text(value: str) -> str:
    return (value or "").translate(TR_MAP).lower()


def ascii_slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", fold_text(value))


def norm_key(value: str) -> str:
    """Uygulamadaki normalizeForSearch ile aynı: boşluk silinir, noktalama kalır."""
    return fold_text(value).replace(" ", "")


def compact(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", fold_text(value))


def as_text(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        text = value.strip()
        return text or None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(value, float) and value != value:
            return None
        return str(value)
    return None


def name_tokens(value: str) -> list[str]:
    words = re.findall(r"[a-z0-9]+", fold_text(value))
    out = []
    for word in words:
        if word in STOP_TOKENS or len(word) < 4:
            continue
        if word not in out:
            out.append(word)
    return out


def region_number(name: str) -> int | None:
    match = re.search(r"(\d+)\s*\.\s*bolge", fold_text(name))
    if not match:
        return None
    number = int(match.group(1))
    if 1 <= number <= 30:
        return number
    return None


def classify(name: str, tip: str) -> str:
    blob = fold_text(f"{name} {tip or ''}")
    name_f = fold_text(name)
    if "sendika" in name_f or "vakif sen" in name_f or "vakıf sen" in name.lower():
        return "sendika"
    if "jandarma" in name_f:
        return "jandarma"
    if "polisevi" in name_f or "polis evi" in name_f or "emniyet" in name_f:
        return "polis"
    if "teias" in name_f:
        return "teias"
    if "tedas" in name_f:
        return "tedas"
    if "meteoroloji" in name_f or "metoroloji" in name_f:
        return "mgm"
    if any(k in name_f for k in ("havalimani", "havalimanı", "dhmi")):
        return "dhmi"
    if "dsi" in name_f or "devlet su" in name_f:
        return "dsi"
    if "karayol" in name_f:
        return "kgm"
    if "diyanet evi" in name_f or "muftu" in name_f or "müftü" in name.lower():
        return "diyanet"
    if "diyanet vakfi" in name_f or "diyanet vakfı" in name.lower():
        return "tdv"
    if "tarim" in name_f or "gida tarim" in name_f:
        return "tarim"
    if "orman" in name_f:
        return "ogm"
    if "universite" in name_f or "ktü" in name.lower() or re.search(r"\bktu\b", name_f):
        return "universite"
    if "belediye" in name_f:
        return "belediye"
    if any(k in name_f for k in ("hekimevi", "hekim evi", "il saglik", "saglik mud")):
        return "saglik"
    if any(k in name_f for k in ("maliye", "defterdar", "hazine ve maliye", "pergen")):
        return "maliye"
    if re.search(r"\bsgk\b", name_f):
        return "sgk"
    if re.search(r"\bptt\b", name_f):
        return "ptt"
    if "tcdd" in name_f or "tuy" in name_f and "tusas" in name_f:
        return "tcdd"
    if any(k in name_f for k in ("hakimevi", "hakim evi", "adalet", "adliye", "ceza infaz")):
        return "adalet"
    if "cevre" in name_f or "sehircilik" in name_f or "csb" in name_f:
        return "csb"
    if re.search(r"\bmke\b", name_f):
        return "mke"
    if "eti maden" in name_f or "etimaden" in name_f:
        return "etimaden"
    if "vakiflar" in name_f or "vakıflar" in name.lower():
        return "vgm"
    if "ogretmenevi" in name_f or "ogretmen evi" in name_f or "aksam sanat okulu" in name_f:
        return "ogretmenevi"
    if any(k in name_f for k in ("orduevi", "ordu evi", "fuzze", "kisla", "askeri")):
        return "ordu"
    tip_f = fold_text(tip or "")
    for key, label in (
        ("ogretmenevi", "ogretmenevi"),
        ("orduevi", "ordu"),
        ("polisevi", "polis"),
        ("dsi", "dsi"),
        ("karayol", "kgm"),
        ("orman", "ogm"),
        ("universite", "universite"),
        ("belediye", "belediye"),
        ("diyanet", "diyanet"),
        ("hakim", "adalet"),
        ("adalet", "adalet"),
        ("jandarma", "jandarma"),
        ("meteoroloji", "mgm"),
        ("dhmi", "dhmi"),
        ("havaliman", "dhmi"),
        ("saglik", "saglik"),
        ("tarim", "tarim"),
        ("maliye", "maliye"),
        ("sgk", "sgk"),
        ("ptt", "ptt"),
        ("tcdd", "tcdd"),
        ("teias", "teias"),
        ("tedas", "tedas"),
    ):
        if key in tip_f:
            return label
    if "universite" in blob:
        return "universite"
    return "diger"


def match_university(name: str) -> tuple[str, str] | None:
    folded = fold_text(name)
    if "karadeniz teknik" in folded or re.search(r"\bktu\b", folded):
        return ("ktu.edu.tr", "Karadeniz Teknik Üniversitesi")
    for key, domain, label in UNIVERSITIES:
        if key in folded:
            return (domain, label)
    return None


def municipality_name(facility_name: str, province: str) -> str:
    match = re.search(
        r"([A-ZÇĞİÖŞÜÂÎÛ][\wÇĞİÖŞÜçğıöşüÂâÎîÛû'’\-\. ]{1,50}?) Belediye",
        facility_name,
    )
    if match:
        return re.sub(r"\s+", " ", match.group(1)).strip()
    return province


@dataclass
class EmailHit:
    email: str
    context: str
    mailto: bool
    channel: str


@dataclass
class Resolution:
    institution_id: str
    name: str
    kind: str
    level: str
    province: str | None = None
    district: str | None = None
    email: str | None = None
    email_channel: str | None = None
    email_verified: bool = False
    email_status: str = "not_found"
    source_url: str | None = None
    source_type: str | None = None
    searched_urls: list[str] = field(default_factory=list)
    note: str | None = None
    unresolved_candidates: list[str] = field(default_factory=list)

    def to_json(self) -> dict:
        return {
            "id": self.institution_id,
            "name": self.name,
            "kind": self.kind,
            "level": self.level,
            "province": self.province,
            "district": self.district,
            "email": self.email,
            "email_channel": self.email_channel,
            "email_verified": self.email_verified,
            "email_status": self.email_status,
            "source_url": self.source_url,
            "source_type": self.source_type,
            "searched_urls": self.searched_urls,
            "note": self.note,
            "unresolved_candidates": self.unresolved_candidates,
        }


def host_of(url: str) -> str:
    return (urlsplit(url).netloc or "").lower().split(":")[0]


def host_official(host: str) -> bool:
    host = host.lower().split(":")[0]
    if host in {"ibb.istanbul", "www.ibb.istanbul"}:
        return True
    return host.endswith((".gov.tr", ".edu.tr", ".bel.tr", ".pol.tr", ".kep.tr", ".k12.tr"))


def normalize_url(url: str) -> str:
    parts = urlsplit(url.strip())
    path = quote(unquote(parts.path), safe="/%")
    query = quote(unquote(parts.query), safe="=&%+")
    return urlunsplit((parts.scheme, parts.netloc, path, query, ""))


def visible_text(html: str) -> str:
    cleaned = re.sub(r"(?is)<script[^>]*>.*?</script>", " ", html)
    cleaned = re.sub(r"(?is)<style[^>]*>.*?</style>", " ", cleaned)
    cleaned = re.sub(r"(?is)<!--.*?-->", " ", cleaned)
    cleaned = unescape(cleaned)
    cleaned = re.sub(r"[\u200b\u200c\u200d\ufeff]", "", cleaned)
    cleaned = re.sub(r"(?s)<[^>]+>", " ", cleaned)
    return re.sub(r"\s+", " ", cleaned).strip()


def extract_hits(html: str) -> list[EmailHit]:
    if not html:
        return []
    decoded = unescape(html)
    decoded = re.sub(r"[\u200b\u200c\u200d\ufeff]", "", decoded)
    text = visible_text(decoded)
    found: dict[str, EmailHit] = {}
    for raw in re.findall(r"(?i)mailto:([^\"'\s>?#]+)", decoded):
        email = raw.strip().strip(".").lower()
        hit = _hit_or_none(email, text, True)
        if hit:
            found[hit.email] = hit
    for email in EMAIL_RE.findall(text):
        hit = _hit_or_none(email, text, False)
        if hit and hit.email not in found:
            found[hit.email] = hit
    return list(found.values())


def _hit_or_none(email: str, text: str, mailto: bool) -> EmailHit | None:
    email = email.strip().strip(".").lower()
    if email.count("@") != 1:
        return None
    local, domain = email.split("@")
    if not local or not domain or "." not in domain:
        return None
    tld = domain.rsplit(".", 1)[-1]
    if tld in BAD_TLD or local in REJECT_LOCAL:
        return None
    if len(local) > 64 or len(email) > 120:
        return None
    channel = "kep" if domain.endswith(".kep.tr") or ".kep." in domain else "smtp"
    index = text.lower().find(email)
    if index >= 0:
        context = text[max(0, index - 160) : index + len(email) + 160]
    else:
        context = ""
    return EmailHit(email=email, context=context, mailto=mailto, channel=channel)


def email_allowed(email: str, page_host: str) -> bool:
    domain = email.split("@", 1)[1]
    if domain in FREEMAIL or domain.endswith((".gmail.com",)):
        return host_official(page_host)
    if domain.endswith((".gov.tr", ".edu.tr", ".bel.tr", ".pol.tr", ".kep.tr", ".k12.tr")):
        return True
    return False


def score_hit(hit: EmailHit, hints: list[str], page_host: str) -> int:
    if not email_allowed(hit.email, page_host):
        return -100
    local = hit.email.split("@", 1)[0]
    flat = re.sub(r"[^a-z0-9]", "", local)
    if any(bad in flat for bad in ("eapostil", "filateli", "kargo", "ihbar")):
        return -100
    score = 0
    if hit.channel == "smtp":
        score += 5
    if local in GENERIC_LOCAL or flat in GENERIC_LOCAL:
        score += 40
    if re.fullmatch(r"\d{4,10}", local):
        score += 35
    if re.fullmatch(r"[a-z]{3,}\.[a-z]{3,}", local):
        score -= 25
    for hint in hints:
        token = re.sub(r"[^a-z0-9]", "", hint or "")
        if len(token) >= 3 and token in flat:
            score += 30
    if host_official(page_host):
        score += 10
    if hit.mailto:
        score += 20
    if re.search(r"e-?posta|eposta|mail|iletişim|iletisim|kep", hit.context, re.I):
        score += 8
    return score


def pick_email(
    hits: list[EmailHit],
    page_host: str,
    hints: list[str],
    ignore: set[str],
) -> tuple[EmailHit | None, str]:
    smtp = [hit for hit in hits if hit.channel == "smtp" and hit.email not in ignore]
    pool = smtp or [hit for hit in hits if hit.email not in ignore]
    scored = []
    for hit in pool:
        scored.append((score_hit(hit, hints, page_host), hit))
    scored = [(score, hit) for score, hit in scored if score >= 25]
    if not scored:
        return None, "not_found"
    scored.sort(key=lambda item: item[0], reverse=True)
    best = scored[0][0]
    tied = [hit for score, hit in scored if score == best]
    unique = {hit.email for hit in tied}
    if len(unique) > 1:
        return None, "manual_review"
    return tied[0], "verified"


def looks_bad(final_url: str, html: str) -> bool:
    if "hatalidns" in (final_url or "").lower():
        return True
    title = re.search(r"(?is)<title>(.*?)</title>", html or "")
    if not title:
        return False
    folded = fold_text(re.sub(r"\s+", " ", title.group(1)))
    return "404" in folded or "sayfa bulunamadi" in folded or "hatali dns" in folded


def page_has(html: str, token: str) -> bool:
    if not token:
        return True
    return token in compact(visible_text(html))


def contact_links(html: str, base_url: str) -> list[str]:
    links = []
    for href in re.findall(r"""(?i)href=["']([^"'#]+)["']""", html or ""):
        if href.lower().startswith(("mailto:", "javascript:", "tel:")):
            continue
        absolute = normalize_url(urljoin(base_url, href))
        if host_of(absolute) != host_of(base_url):
            continue
        folded = fold_text(unquote(absolute))
        if "eposta_gonder" in folded:
            continue
        if not re.search(r"iletisim|iletişim|bize-ulasin|bizeulasin|contact", folded):
            continue
        if absolute not in links:
            links.append(absolute)
        if len(links) >= 3:
            break
    return links


def pdf_links(html: str, base_url: str) -> list[str]:
    links = []
    for href in re.findall(r"""(?i)href=["']([^"'#]+)["']""", html or ""):
        absolute = normalize_url(urljoin(base_url, href))
        if host_of(absolute) != host_of(base_url):
            continue
        if not absolute.lower().split("?")[0].endswith(".pdf"):
            continue
        folded = fold_text(unquote(absolute))
        if not re.search(r"iletisim|hizmet|standart|eposta|tarif", folded):
            continue
        links.append(absolute)
        if len(links) >= 1:
            break
    return links


class Http:
    def __init__(self, cache_path: Path, global_gap: float, host_gap: float) -> None:
        self.cache_path = cache_path
        self.global_gap = global_gap
        self.host_gap = host_gap
        self.lock = threading.Lock()
        self.limiter = threading.Lock()
        self.next_at = 0.0
        self.host_next: dict[str, float] = {}
        self.local = threading.local()
        self.writes = 0
        self.cache: dict[str, dict] = {}
        if cache_path.is_file():
            try:
                self.cache = json.loads(cache_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                self.cache = {}

    def session(self) -> requests.Session:
        session = getattr(self.local, "session", None)
        if session is None:
            session = requests.Session()
            session.headers.update({"User-Agent": UA, "Accept": "text/html,application/pdf,*/*"})
            self.local.session = session
        return session

    def _wait(self, host: str) -> None:
        with self.limiter:
            now = time.monotonic()
            delay = max(self.next_at, self.host_next.get(host, 0.0)) - now
            self.next_at = max(now, self.next_at) + self.global_gap
            self.host_next[host] = max(now, self.host_next.get(host, 0.0)) + self.host_gap
        if delay > 0:
            time.sleep(delay)

    def get(self, url: str) -> dict:
        url = normalize_url(url)
        with self.lock:
            cached = self.cache.get(url)
        if cached:
            return cached
        host = host_of(url)
        self._wait(host)
        item = {"status": 0, "final_url": url, "text": "", "content_type": ""}
        try:
            response = self.session().get(url, timeout=(5, 12), allow_redirects=True, stream=True)
            raw = b""
            for chunk in response.iter_content(65536):
                if not chunk:
                    continue
                raw += chunk
                if len(raw) > 500_000:
                    break
            response.close()
            ctype = (response.headers.get("Content-Type") or "").lower()
            if "pdf" in ctype or url.lower().split("?")[0].endswith(".pdf"):
                text = pdf_to_text(raw)
            else:
                text = decode_body(raw)
            item = {
                "status": response.status_code,
                "final_url": response.url,
                "text": text[:180000],
                "content_type": ctype,
            }
        except requests.RequestException as exc:
            item["error"] = type(exc).__name__
        with self.lock:
            self.cache[url] = item
            self.writes += 1
            if self.writes % 25 == 0:
                self._flush_locked()
        return item

    def flush(self) -> None:
        with self.lock:
            self._flush_locked()

    def _flush_locked(self) -> None:
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        self.cache_path.write_text(json.dumps(self.cache, ensure_ascii=False), encoding="utf-8")


def decode_body(raw: bytes) -> str:
    for encoding in ("utf-8", "windows-1254", "iso-8859-9"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def pdf_to_text(data: bytes) -> str:
    try:
        from pypdf import PdfReader
        import io

        reader = PdfReader(io.BytesIO(data))
        return "\n".join((page.extract_text() or "") for page in reader.pages[:6])
    except Exception:
        return data.decode("latin-1", errors="ignore")


class Researcher:
    def __init__(self, http: Http) -> None:
        self.http = http
        self.results: dict[str, Resolution] = {}
        self.locks: dict[str, threading.Lock] = {}
        self.master = threading.Lock()
        self.dsi_map: dict[str, int] | None = None
        self.dsi_map_lock = threading.Lock()
        self.footer_emails = {
            "kgm": set(),
        }

    def _lock(self, key: str) -> threading.Lock:
        with self.master:
            return self.locks.setdefault(key, threading.Lock())

    def resolve(self, key: str, builder) -> Resolution:
        with self._lock(key):
            existing = self.results.get(key)
            if existing:
                return existing
            value = builder()
            self.results[key] = value
            return value

    def pages_for(
        self,
        urls: list[str],
        required: list[str],
        hints: list[str],
        ignore: set[str],
        follow_pdf: bool,
    ) -> Resolution | None:
        """İlk uygun sayfadan e-posta seçer. Eşleşme yoksa None döner; çağıran not_found yazar."""
        searched: list[str] = []
        ambiguous: list[str] = []
        for seed in urls:
            page = self.http.get(seed)
            searched.append(page.get("final_url") or seed)
            html = page.get("text") or ""
            if page.get("status") != 200 or looks_bad(page.get("final_url") or "", html):
                continue
            if required and not all(page_has(html, token) for token in required):
                continue
            bundle = [(page.get("final_url") or seed, html)]
            for link in contact_links(html, page.get("final_url") or seed):
                extra = self.http.get(link)
                searched.append(extra.get("final_url") or link)
                if extra.get("status") == 200 and not looks_bad(extra.get("final_url") or "", extra.get("text") or ""):
                    bundle.append((extra.get("final_url") or link, extra.get("text") or ""))
            if follow_pdf:
                for link in pdf_links(html, page.get("final_url") or seed):
                    extra = self.http.get(link)
                    searched.append(extra.get("final_url") or link)
                    if extra.get("status") == 200:
                        bundle.append((extra.get("final_url") or link, extra.get("text") or ""))
            hits_by_url: list[tuple[str, EmailHit]] = []
            for url, body in bundle:
                for hit in extract_hits(body):
                    hits_by_url.append((url, hit))
            # Sayfaları birlikte değerlendir; kaynak, seçilen adresin geçtiği URL olsun.
            chosen_url = None
            chosen_hit = None
            status = "not_found"
            best_score = -1
            scores: list[tuple[int, str, EmailHit]] = []
            for url, hit in hits_by_url:
                score = score_hit(hit, hints, host_of(url))
                if hit.email in ignore:
                    continue
                if score >= 25:
                    scores.append((score, url, hit))
            smtp_scores = [item for item in scores if item[2].channel == "smtp"]
            pool = smtp_scores or scores
            if not pool:
                continue
            pool.sort(key=lambda item: item[0], reverse=True)
            top = pool[0][0]
            tied = [item for item in pool if item[0] == top]
            if len({item[2].email for item in tied}) > 1:
                ambiguous = sorted({item[2].email for item in tied})[:8]
                partial = Resolution(
                    institution_id="",
                    name="",
                    kind="",
                    level="",
                    email_status="manual_review",
                    searched_urls=searched,
                    unresolved_candidates=ambiguous,
                    note="Aynı sayfada birden fazla resmî aday vardı; biri seçilmedi.",
                )
                return partial
            chosen_hit = tied[0][2]
            chosen_url = tied[0][1]
            best_score = top
            status = "verified"
            source_type = "official_pdf" if chosen_url.lower().split("?")[0].endswith(".pdf") else "official_website"
            found = Resolution(
                institution_id="",
                name="",
                kind="",
                level="",
                email=chosen_hit.email,
                email_channel=chosen_hit.channel,
                email_verified=True,
                email_status=status,
                source_url=chosen_url,
                source_type=source_type,
                searched_urls=searched,
                note="KEP adresi; olağan SMTP gelen kutusu değildir." if chosen_hit.channel == "kep" else None,
            )
            if best_score < 25:
                continue
            return found
        if ambiguous:
            return Resolution(
                institution_id="",
                name="",
                kind="",
                level="",
                email_status="manual_review",
                searched_urls=searched,
                unresolved_candidates=ambiguous,
                note="Aynı sayfada birden fazla resmî aday vardı; biri seçilmedi.",
            )
        return None

    def finish(
        self,
        key: str,
        name: str,
        kind: str,
        level: str,
        province: str | None,
        district: str | None,
        urls: list[str],
        required: list[str],
        hints: list[str],
        ignore: set[str] | None = None,
        follow_pdf: bool = False,
    ) -> Resolution:
        def build() -> Resolution:
            found = self.pages_for(urls, required, hints, ignore or set(), follow_pdf)
            if found is None:
                found = Resolution(
                    institution_id=key,
                    name=name,
                    kind=kind,
                    level=level,
                    email_status="not_found",
                    searched_urls=urls,
                    note="Resmî sayfada doğrulanmış e-posta yok.",
                )
            found.institution_id = key
            found.name = name
            found.kind = kind
            found.level = level
            found.province = province
            found.district = district
            if found.email and not found.source_url:
                found.email = None
                found.email_verified = False
                found.email_status = "not_found"
            if found.email_status == "verified":
                found.email_status = _status_for_level(level)
            return found

        return self.resolve(key, build)

    def load_kgm_footer(self) -> set[str]:
        def build() -> Resolution:
            page = self.http.get("https://www.kgm.gov.tr/")
            hits = extract_hits(page.get("text") or "")
            self.footer_emails["kgm"] = {hit.email for hit in hits}
            # Asıl genel müdürlük adresi bu sayfadan ayrıca çözülür.
            return Resolution(institution_id="kgm-footer", name="KGM altbilgi", kind="kgm", level="general_directorate")

        self.resolve("kgm-footer", build)
        return self.footer_emails["kgm"]

    def dsi_province_map(self) -> dict[str, int]:
        with self.dsi_map_lock:
            if self.dsi_map is not None:
                return self.dsi_map
            claims: dict[str, set[int]] = defaultdict(set)
            for number in range(1, 27):
                home = self.http.get(f"https://bolge{number:02d}.dsi.gov.tr/")
                html = home.get("text") or ""
                if home.get("status") != 200:
                    continue
                duty = None
                for href, label in re.findall(r'(?is)href="([^"]+)"[^>]*>(.*?)</a>', html):
                    label_f = fold_text(re.sub(r"<[^>]+>", " ", label))
                    if "gorev alani" in label_f:
                        duty = normalize_url(urljoin(home.get("final_url") or f"https://bolge{number:02d}.dsi.gov.tr/", href))
                        break
                if not duty:
                    continue
                page = self.http.get(duty)
                text = visible_text(page.get("text") or "")
                folded = fold_text(text)
                start = folded.rfind("gorev alani")
                if start >= 0:
                    folded = folded[start:]
                end = folded.find("tarihce")
                if end > 40:
                    folded = folded[:end]
                if folded.count(" ili") > 12 or len(folded) < 40:
                    continue
                compact_text = re.sub(r"[^a-z0-9]+", " ", folded)
                for province in PROVINCES:
                    token = fold_text(province)
                    if re.search(rf"(?<![a-z]){re.escape(token)}(?![a-z])", compact_text):
                        claims[ascii_slug(province)].add(number)
            mapped = {}
            for slug, numbers in claims.items():
                if len(numbers) == 1:
                    mapped[slug] = next(iter(numbers))
            self.dsi_map = mapped
            return mapped

    def dsi_region(self, number: int, province: str | None) -> Resolution:
        key = f"dsi-bolge-{number:02d}"

        def build() -> Resolution:
            home_url = f"https://bolge{number:02d}.dsi.gov.tr/"
            home = self.http.get(home_url)
            found_urls = []
            html = home.get("text") or ""
            base = home.get("final_url") or home_url
            for href, label in re.findall(r'(?is)href="([^"]+)"[^>]*>(.*?)</a>', html):
                label_f = fold_text(re.sub(r"<[^>]+>", " ", label))
                if "iletisim" in label_f:
                    found_urls.append(normalize_url(urljoin(base, href)))
            if not found_urls:
                found_urls.append(home_url)
            found = self.pages_for(
                found_urls[:2],
                [],
                [f"dsi{number}", f"dsi{number:02d}", "dsi"],
                set(),
                True,
            )
            if found is None:
                found = Resolution(
                    institution_id=key,
                    name=f"DSİ {number}. Bölge Müdürlüğü",
                    kind="dsi",
                    level="region",
                    email_status="not_found",
                    searched_urls=found_urls[:2],
                    note="Resmî sayfada doğrulanmış e-posta yok.",
                )
            found.institution_id = key
            found.name = f"DSİ {number}. Bölge Müdürlüğü"
            found.kind = "dsi"
            found.level = "region"
            found.province = province
            if found.email_status == "verified":
                found.email_status = "region_verified"
            if found.email and not found.source_url:
                found.email = None
                found.email_verified = False
                found.email_status = "not_found"
            return found

        return self.resolve(key, build)

    def dsi_gm(self) -> Resolution:
        return self.finish(
            "dsi-gm",
            "Devlet Su İşleri Genel Müdürlüğü",
            "dsi",
            "general_directorate",
            None,
            None,
            ["https://www.dsi.gov.tr/"],
            [],
            ["dsi", "iletisim"],
            follow_pdf=True,
        )


def _status_for_level(level: str) -> str:
    return {
        "facility": "facility_verified",
        "district": "parent_verified",
        "province": "parent_verified",
        "region": "region_verified",
        "general_directorate": "general_directorate_verified",
    }.get(level, "not_found")


def find_data_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit)
    candidates = [
        Path("/tmp/rotalink-data"),
        Path("/workspace/../rotalink-data"),
        Path("/workspace"),
    ]
    for candidate in candidates:
        if (candidate / "master_database_updated.json").is_file() or (
            candidate / "assets/data/master_database_updated.json"
        ).is_file():
            return candidate
    raise SystemExit("Tesis verisi bulunamadı. --data-root verin.")


def load_inputs(root: Path) -> tuple[list[dict], dict[tuple[str, str], str], dict[tuple[str, str], dict]]:
    master_path = root / "master_database_updated.json"
    if not master_path.is_file():
        master_path = root / "assets/data/master_database_updated.json"
    adres_path = root / "tesisler_adres.json"
    fiyat_path = root / "fiyatlar.json"
    master = json.loads(master_path.read_text(encoding="utf-8"))
    facilities = master["tesisler"] if isinstance(master, dict) else master
    districts: dict[tuple[str, str], str] = {}
    if adres_path.is_file():
        adres = json.loads(adres_path.read_text(encoding="utf-8"))
        items = adres.get("items") if isinstance(adres, dict) else adres
        for item in items or []:
            ilce = as_text(item.get("ilce"))
            if not ilce:
                continue
            districts[(norm_key(item.get("il") or ""), norm_key(item.get("isim") or ""))] = ilce
    prices: dict[tuple[str, str], dict] = {}
    if fiyat_path.is_file():
        fiyat = json.loads(fiyat_path.read_text(encoding="utf-8"))
        rows = fiyat.get("tesisler") if isinstance(fiyat, dict) else fiyat
        for row in rows or []:
            prices[(norm_key(row.get("il") or ""), norm_key(row.get("isim") or ""))] = row
    return facilities, districts, prices


def district_from_address(address: str | None, province: str, placeholder: set[str]) -> str | None:
    if not address or address in placeholder:
        return None
    match = re.search(
        r"([A-Za-zÇĞİÖŞÜçğıöşüÂâÎîÛû][A-Za-zÇĞİÖŞÜçğıöşüÂâÎîÛû\.\- ]{1,40})\s*/\s*"
        r"([A-Za-zÇĞİÖŞÜçğıöşüÂâÎîÛû\.\- ]{2,30})\s*$",
        address,
    )
    if not match:
        return None
    left, right = match.group(1).strip(" ."), match.group(2).strip(" .")
    if ascii_slug(right) != ascii_slug(province) and ascii_slug(province) not in ascii_slug(right):
        return None
    if ascii_slug(left) in {"merkez", ascii_slug(province)}:
        return None
    return left


def price_fields(row: dict | None) -> dict:
    if not row:
        return {
            "price_available": False,
            "civil_price": None,
            "public_price": None,
            "institution_price": None,
            "price_source": None,
        }
    civil = as_text(row.get("fiyat_sivil"))
    public = as_text(row.get("fiyat_kamu_personeli"))
    institution = as_text(row.get("fiyat_kurum_personeli"))
    available = bool(civil or public or institution or row.get("tarife"))
    return {
        "price_available": available,
        "civil_price": civil,
        "public_price": public,
        "institution_price": institution,
        "price_source": as_text(row.get("kaynak")),
    }


def prepare_facility(
    raw: dict,
    districts: dict[tuple[str, str], str],
    prices: dict[tuple[str, str], dict],
    placeholder: set[str],
) -> dict:
    province = as_text(raw.get("il")) or ""
    name = as_text(raw.get("isim")) or ""
    tip = as_text(raw.get("tip")) or ""
    address = as_text(raw.get("adres"))
    key = (norm_key(province), norm_key(name))
    district = districts.get(key) or district_from_address(address, province, placeholder)
    if district and ascii_slug(district) in {"merkez", "merkezilce"}:
        district = None
    return {
        "facility_name": name,
        "province": province,
        "district": district,
        "facility_type": tip,
        "facility_class": classify(name, tip),
        "address": address,
        "phone": as_text(raw.get("telefon")),
        "latitude": raw.get("latitude"),
        "longitude": raw.get("longitude"),
        "existing_email": as_text(raw.get("email") or raw.get("eposta") or raw.get("facility_email")),
        **price_fields(prices.get(key)),
    }


def distinctive_tokens(facility: dict) -> list[str]:
    province_slug = ascii_slug(facility["province"])
    tokens = []
    for token in name_tokens(facility["facility_name"]):
        if token == province_slug:
            continue
        if token not in tokens:
            tokens.append(token)
    return tokens


class Engine:
    def __init__(self, http: Http) -> None:
        self.http = http
        self.research = Researcher(http)
        self.collisions: set[str] = set()

    def facility_page_email(self, facility: dict) -> Resolution | None:
        tokens = distinctive_tokens(facility)
        hints = tokens + [ascii_slug(facility["province"]), ascii_slug(facility["district"] or "")]
        source = facility.get("price_source") or ""
        if source.startswith("http") and host_official(host_of(source)):
            if not source.lower().split("?")[0].endswith(".pdf"):
                found = self._email_on_page(source, tokens, hints, facility)
                if found:
                    return found
        if facility["facility_class"] != "ogretmenevi":
            return None
        for host in ogretmenevi_hosts(facility)[:3]:
            url = f"https://{host}.meb.k12.tr/"
            page = self.http.get(url)
            html = page.get("text") or ""
            final = page.get("final_url") or url
            if page.get("status") != 200 or looks_bad(final, html):
                continue
            if "meb_iys_dosyalar" not in html and "meb.k12.tr" not in final:
                continue
            blob = compact(visible_text(html) + " " + final)
            province_ok = ascii_slug(facility["province"]) in blob
            district_ok = bool(facility["district"]) and ascii_slug(facility["district"]) in blob
            if "ogretmen" not in blob:
                continue
            if facility["district"] is None and not province_ok:
                continue
            if facility["district"] and not (district_ok or province_ok):
                continue
            found = self._email_on_page(final, tokens, hints, facility, html=html)
            if found and found.email:
                return found
        return None

    def _email_on_page(
        self,
        url: str,
        tokens: list[str],
        hints: list[str],
        facility: dict,
        html: str | None = None,
    ) -> Resolution | None:
        page = {"text": html, "final_url": url, "status": 200} if html is not None else self.http.get(url)
        body = page.get("text") or ""
        final = page.get("final_url") or url
        if page.get("status") != 200 or looks_bad(final, body):
            return None
        visible = compact(visible_text(body))
        if tokens and not any(token in visible or token in compact(final) for token in tokens):
            # İl adı yetmez; tesisin ayırt edici adı sayfada yoksa tesis e-postası sayma.
            if not any(token in compact(host_of(final)) for token in tokens):
                return None
        hits = []
        pages = [(final, body)]
        for link in contact_links(body, final):
            extra = self.http.get(link)
            if extra.get("status") == 200:
                pages.append((extra.get("final_url") or link, extra.get("text") or ""))
        chosen = None
        chosen_url = None
        best = -1
        candidates = []
        for page_url, page_html in pages:
            for hit in extract_hits(page_html):
                score = score_hit(hit, hints, host_of(page_url))
                if score < 25:
                    continue
                context_ok = any(token in compact(hit.context) for token in tokens) or any(
                    token in compact(host_of(page_url)) for token in tokens
                )
                host = host_of(page_url)
                if host.endswith(".k12.tr") and "ogretmen" in compact(page_html):
                    context_ok = True
                if not context_ok:
                    continue
                candidates.append((score, page_url, hit))
        if not candidates:
            return None
        smtp = [item for item in candidates if item[2].channel == "smtp"]
        pool = smtp or candidates
        pool.sort(key=lambda item: item[0], reverse=True)
        top = pool[0][0]
        tied = {item[2].email for item in pool if item[0] == top}
        if len(tied) != 1:
            return Resolution(
                institution_id=f"facility-{ascii_slug(facility['province'])}-{ascii_slug(facility['facility_name'])}",
                name=facility["facility_name"],
                kind=facility["facility_class"],
                level="facility",
                province=facility["province"],
                district=facility["district"],
                email_status="manual_review",
                unresolved_candidates=sorted(tied)[:8],
                note="Tesis sayfasında birden fazla aday vardı.",
            )
        chosen = pool[0][2]
        chosen_url = pool[0][1]
        return Resolution(
            institution_id=f"facility-{ascii_slug(facility['province'])}-{ascii_slug(facility['facility_name'])}",
            name=facility["facility_name"],
            kind=facility["facility_class"],
            level="facility",
            province=facility["province"],
            district=facility["district"],
            email=chosen.email,
            email_channel=chosen.channel,
            email_verified=True,
            email_status="facility_verified",
            source_url=chosen_url,
            source_type="official_pdf" if chosen_url.lower().split("?")[0].endswith(".pdf") else "official_website",
            note="KEP adresi; olağan SMTP gelen kutusu değildir." if chosen.channel == "kep" else None,
        )

    def parent_chain(self, facility: dict) -> list[Resolution]:
        kind = facility["facility_class"]
        province = facility["province"]
        district = facility["district"]
        pslug = ascii_slug(province)
        dslug = ascii_slug(district or "")
        chain: list[Resolution] = []
        if kind == "ogretmenevi":
            if district and dslug not in self.collisions and dslug != pslug:
                chain.append(self.mem_ilce(province, district))
            elif district and dslug in self.collisions:
                chain.append(self.mem_ilce(province, district, require_province=True))
            chain.append(self.mem_il(province))
        elif kind == "dsi":
            number = region_number(facility["facility_name"])
            if number is None:
                number = self.research.dsi_province_map().get(pslug)
            if number:
                chain.append(self.research.dsi_region(number, province))
            chain.append(self.research.dsi_gm())
        elif kind == "kgm":
            number = region_number(facility["facility_name"])
            ignore = self.research.load_kgm_footer()
            if number:
                chain.append(
                    self.research.finish(
                        f"kgm-bolge-{number}",
                        f"Karayolları {number}. Bölge Müdürlüğü",
                        "kgm",
                        "region",
                        province,
                        None,
                        [f"https://www.kgm.gov.tr/Sayfalar/KGM/SiteTr/Bolgeler/{number}Bolge/Bolge{number}.aspx"],
                        [],
                        [f"bolge{number}", pslug],
                        ignore=ignore,
                    )
                )
            chain.append(
                self.research.finish(
                    "kgm-gm",
                    "Karayolları Genel Müdürlüğü",
                    "kgm",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.kgm.gov.tr/Sayfalar/KGM/SiteTr/Root/Iletisim.aspx"],
                    [],
                    ["kgm", "iletisim"],
                )
            )
        elif kind == "ogm":
            if "genel mudurlugu" in fold_text(facility["facility_name"]):
                chain.append(self.ogm_gm())
            else:
                chain.append(self.ogm_province(province))
                chain.append(self.ogm_gm())
        elif kind == "tarim":
            chain.append(
                self.simple(
                    f"tarim-{pslug}",
                    f"{province} İl Tarım ve Orman Müdürlüğü",
                    "tarim",
                    "province",
                    province,
                    None,
                    [f"https://{pslug}.tarimorman.gov.tr/"],
                    [pslug],
                    [pslug, "tarim"],
                )
            )
        elif kind == "polis":
            chain.append(
                self.simple(
                    f"emniyet-{pslug}",
                    f"{province} İl Emniyet Müdürlüğü",
                    "polis",
                    "province",
                    province,
                    None,
                    [f"https://www.{pslug}.pol.tr/", f"https://{pslug}.pol.tr/"],
                    [pslug],
                    [pslug, "emniyet", "polis"],
                )
            )
            chain.append(
                self.simple(
                    "egm",
                    "Emniyet Genel Müdürlüğü",
                    "polis",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.egm.gov.tr/"],
                    [],
                    ["egm", "emniyet"],
                    follow_pdf=True,
                )
            )
        elif kind == "jandarma":
            chain.append(
                self.simple(
                    f"jandarma-{pslug}",
                    f"{province} İl Jandarma Komutanlığı",
                    "jandarma",
                    "province",
                    province,
                    None,
                    [f"https://www.jandarma.gov.tr/{pslug}"],
                    [pslug],
                    [pslug, "jandarma"],
                )
            )
            chain.append(
                self.simple(
                    "jandarma-gm",
                    "Jandarma Genel Komutanlığı",
                    "jandarma",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.jandarma.gov.tr/iletisim"],
                    [],
                    ["jandarma"],
                )
            )
        elif kind == "dhmi":
            chain.append(
                self.simple(
                    "dhmi-gm",
                    "Devlet Hava Meydanları İşletmesi Genel Müdürlüğü",
                    "dhmi",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.dhmi.gov.tr/Sayfalar/Iletisim.aspx"],
                    [],
                    ["dhmi", "iletisim"],
                )
            )
        elif kind == "universite":
            matched = match_university(facility["facility_name"])
            if matched:
                domain, label = matched
                chain.append(
                    self.simple(
                        f"uni-{ascii_slug(domain)}",
                        f"{label} Rektörlüğü",
                        "universite",
                        "province",
                        province,
                        None,
                        [f"https://{domain}/", f"https://www.{domain}/"],
                        [],
                        [ascii_slug(label), "rektor", "iletisim"],
                    )
                )
        elif kind == "belediye":
            mun = municipality_name(facility["facility_name"], province)
            mun_fold = fold_text(mun)
            slug = ascii_slug(mun)
            if "buyuksehir" in mun_fold:
                parts = mun_fold.split()
                if "buyuksehir" in parts and parts.index("buyuksehir") > 0:
                    slug = ascii_slug(parts[parts.index("buyuksehir") - 1])
            urls = [f"https://{slug}.bel.tr/", f"https://www.{slug}.bel.tr/"]
            if slug == "istanbul":
                urls = ["https://ibb.istanbul/", "https://www.ibb.istanbul/", "https://istanbul.bel.tr/"]
            chain.append(
                self.simple(
                    f"bel-{slug}",
                    f"{mun} Belediyesi",
                    "belediye",
                    "province" if "buyuksehir" in mun_fold else "district",
                    province,
                    district,
                    urls,
                    [] if slug == "istanbul" else [slug],
                    [slug, "belediye", "iletisim"],
                )
            )
        elif kind == "diyanet":
            if "diyanet evi" in fold_text(facility["facility_name"]):
                chain.append(
                    self.simple(
                        "diyanet-evi",
                        "Diyanet Evi",
                        "diyanet",
                        "province",
                        province,
                        None,
                        ["https://diyanetevi.diyanet.gov.tr/"],
                        [],
                        ["diyanet"],
                    )
                )
            chain.append(
                self.simple(
                    f"muftuluk-{pslug}",
                    f"{province} İl Müftülüğü",
                    "diyanet",
                    "province",
                    province,
                    None,
                    [f"https://{pslug}.diyanet.gov.tr/"],
                    [pslug],
                    [pslug, "muftu", "diyanet"],
                )
            )
        elif kind == "tdv":
            chain.append(
                self.simple(
                    "tdv",
                    "Türkiye Diyanet Vakfı",
                    "tdv",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.diyanetvakfi.org.tr/", "https://tdv.org/"],
                    [],
                    ["diyanet", "vakfi", "tdv"],
                )
            )
        elif kind == "mgm":
            number = region_number(facility["facility_name"])
            if number:
                chain.append(
                    self.simple(
                        f"mgm-bolge-{number}",
                        f"Meteoroloji {number}. Bölge Müdürlüğü",
                        "mgm",
                        "region",
                        province,
                        None,
                        [f"https://{pslug}.mgm.gov.tr/"],
                        [],
                        [pslug, "meteoroloji", f"bolge{number}"],
                    )
                )
            else:
                chain.append(
                    self.simple(
                        f"mgm-{pslug}",
                        f"{province} Meteoroloji İl Müdürlüğü",
                        "mgm",
                        "province",
                        province,
                        None,
                        [f"https://{pslug}.mgm.gov.tr/"],
                        [pslug],
                        [pslug, "meteoroloji"],
                    )
                )
            chain.append(
                self.simple(
                    "mgm-gm",
                    "Meteoroloji Genel Müdürlüğü",
                    "mgm",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.mgm.gov.tr/site/iletisim.aspx"],
                    [],
                    ["meteoroloji"],
                )
            )
        elif kind == "teias":
            number = region_number(facility["facility_name"])
            hints = ["teias", pslug] + ([f"{number}bolge", f"bolge{number}"] if number else [])
            chain.append(
                self.simple(
                    "teias-iletisim",
                    "TEİAŞ" + (f" {number}. Bölge Müdürlüğü" if number else ""),
                    "teias",
                    "region" if number else "general_directorate",
                    province,
                    None,
                    ["https://www.teias.gov.tr/iletisim"],
                    [],
                    hints,
                )
            )
        elif kind == "tedas":
            chain.append(
                self.simple(
                    "tedas",
                    "TEDAŞ Genel Müdürlüğü",
                    "tedas",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.tedas.gov.tr/iletisim", "https://www.tedas.gov.tr/"],
                    [],
                    ["tedas"],
                )
            )
        elif kind == "saglik":
            chain.append(
                self.simple(
                    f"saglik-{pslug}",
                    f"{province} İl Sağlık Müdürlüğü",
                    "saglik",
                    "province",
                    province,
                    None,
                    [f"https://{pslug}ism.saglik.gov.tr/"],
                    [pslug],
                    [pslug, "saglik"],
                )
            )
        elif kind == "maliye":
            chain.append(
                self.simple(
                    "hmb",
                    "Hazine ve Maliye Bakanlığı",
                    "maliye",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.hmb.gov.tr/iletisim", "https://www.hmb.gov.tr/"],
                    [],
                    ["hazine", "maliye", "hmb"],
                )
            )
        elif kind == "sgk":
            chain.append(
                self.simple(
                    "sgk",
                    "Sosyal Güvenlik Kurumu",
                    "sgk",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.sgk.gov.tr/"],
                    [],
                    ["sgk"],
                    follow_pdf=True,
                )
            )
        elif kind == "ptt":
            chain.append(
                self.simple(
                    "ptt",
                    "PTT A.Ş.",
                    "ptt",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.ptt.gov.tr/iletisim", "https://www.ptt.gov.tr/"],
                    [],
                    ["ptt", "iletisim"],
                )
            )
        elif kind == "tcdd":
            chain.append(
                self.simple(
                    "tcdd",
                    "TCDD Taşımacılık",
                    "tcdd",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.tcddtasimacilik.gov.tr/", "https://www.tcdd.gov.tr/"],
                    [],
                    ["tcdd"],
                )
            )
        elif kind == "adalet":
            chain.append(
                self.simple(
                    "adalet",
                    "Adalet Bakanlığı",
                    "adalet",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.adalet.gov.tr/iletisim", "https://www.adalet.gov.tr/"],
                    [],
                    ["adalet"],
                    follow_pdf=True,
                )
            )
        elif kind == "csb":
            chain.append(
                self.simple(
                    f"csb-{pslug}",
                    f"{province} Çevre, Şehircilik ve İklim Değişikliği İl Müdürlüğü",
                    "csb",
                    "province",
                    province,
                    None,
                    [f"https://{pslug}.csb.gov.tr/"],
                    [pslug],
                    [pslug, "csb", "cevre"],
                )
            )
        elif kind == "mke":
            chain.append(
                self.simple(
                    "mke",
                    "Makine ve Kimya Endüstrisi",
                    "mke",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.mke.gov.tr/iletisim"],
                    [],
                    ["mke"],
                )
            )
        elif kind == "etimaden":
            chain.append(
                self.simple(
                    "etimaden",
                    "Eti Maden",
                    "etimaden",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.etimaden.gov.tr/iletisim", "https://www.etimaden.gov.tr/"],
                    [],
                    ["etimaden", "eti"],
                )
            )
        elif kind == "vgm":
            chain.append(
                self.simple(
                    "vgm",
                    "Vakıflar Genel Müdürlüğü",
                    "vgm",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.vgm.gov.tr/iletisim"],
                    [],
                    ["vgm", "vakif"],
                )
            )
        elif kind == "ordu":
            chain.append(
                self.simple(
                    "msb",
                    "Millî Savunma Bakanlığı",
                    "ordu",
                    "general_directorate",
                    None,
                    None,
                    ["https://www.msb.gov.tr/Iletisim", "https://www.msb.gov.tr/"],
                    [],
                    ["msb", "savunma"],
                )
            )
        return chain

    def mem_ilce(self, province: str, district: str, require_province: bool = False) -> Resolution:
        pslug, dslug = ascii_slug(province), ascii_slug(district)
        required = [dslug] + ([pslug] if require_province else [])
        return self.research.finish(
            f"mem-ilce-{pslug}-{dslug}",
            f"{district} İlçe Millî Eğitim Müdürlüğü",
            "ilce_mem",
            "district",
            province,
            district,
            [f"https://{dslug}.meb.gov.tr/www/iletisim.php", f"https://{dslug}.meb.gov.tr/"],
            required,
            [dslug, pslug, "mem", "meb"],
            follow_pdf=True,
        )

    def mem_il(self, province: str) -> Resolution:
        pslug = ascii_slug(province)
        return self.research.finish(
            f"mem-il-{pslug}",
            f"{province} İl Millî Eğitim Müdürlüğü",
            "il_mem",
            "province",
            province,
            None,
            [f"https://{pslug}.meb.gov.tr/www/iletisim.php", f"https://{pslug}.meb.gov.tr/"],
            [pslug],
            [pslug, "mem", "meb"],
            follow_pdf=True,
        )

    def ogm_province(self, province: str) -> Resolution:
        pslug = ascii_slug(province)
        return self.research.finish(
            f"ogm-{pslug}",
            f"{province} Orman Bölge Müdürlüğü",
            "ogm",
            "region",
            province,
            None,
            [f"https://www.ogm.gov.tr/{pslug}obm/iletisim/bize-ulasin"],
            [pslug],
            [pslug, "obm", "ogm"],
        )

    def ogm_gm(self) -> Resolution:
        return self.research.finish(
            "ogm-gm",
            "Orman Genel Müdürlüğü",
            "ogm",
            "general_directorate",
            None,
            None,
            ["https://www.ogm.gov.tr/"],
            [],
            ["ogm"],
            follow_pdf=True,
        )

    def simple(
        self,
        key: str,
        name: str,
        kind: str,
        level: str,
        province: str | None,
        district: str | None,
        urls: list[str],
        required: list[str],
        hints: list[str],
        ignore: set[str] | None = None,
        follow_pdf: bool = False,
    ) -> Resolution:
        return self.research.finish(
            key, name, kind, level, province, district, urls, required, hints, ignore, follow_pdf
        )

    def research_facility(self, facility: dict) -> dict:
        suggested = suggested_parent(facility)
        facility_email = None
        facility_source = None
        note = None
        status = "not_found"
        source_url = None
        source_type = None
        channel = None
        verified = False
        parent_name = None
        parent_email = None
        parent_source = None
        parent_level = None
        institution_id = None
        if facility.get("existing_email"):
            facility_email = facility["existing_email"]
            status = "manual_review"
            note = "Kayıtta e-posta vardı; kaynak doğrulanmadığı için verified yapılmadı ve değiştirilmedi."
        else:
            own = self.facility_page_email(facility)
            if own and own.email and own.email_verified and own.source_url:
                facility_email = own.email
                facility_source = own.source_url
                status = "facility_verified"
                source_url = own.source_url
                source_type = own.source_type
                channel = own.email_channel
                verified = True
                note = own.note
                institution_id = own.institution_id
                self.research.results[own.institution_id] = own
            elif own and own.email_status == "manual_review":
                status = "manual_review"
                note = own.note
                institution_id = own.institution_id
                self.research.results[own.institution_id] = own
            else:
                for parent in self.parent_chain(facility):
                    parent_name = parent.name
                    institution_id = parent.institution_id
                    if parent.email and parent.email_verified and parent.source_url:
                        parent_email = parent.email
                        parent_source = parent.source_url
                        parent_level = parent.level
                        status = parent.email_status
                        source_url = parent.source_url
                        source_type = parent.source_type
                        channel = parent.email_channel
                        verified = True
                        note = parent.note
                        break
                    if parent.email_status == "manual_review":
                        status = "manual_review"
                        note = parent.note
                        parent_level = parent.level
                        break
                else:
                    status = "not_found"
                    note = note or "Resmî kaynakta doğrulanmış e-posta bulunamadı."
        email = facility_email or parent_email
        if email and not source_url:
            verified = False
            if status.endswith("_verified"):
                status = "manual_review"
        record = {
            "facility_name": facility["facility_name"],
            "province": facility["province"],
            "district": facility["district"],
            "facility_type": facility["facility_type"],
            "facility_class": facility["facility_class"],
            "address": facility["address"],
            "phone": facility["phone"],
            "latitude": facility["latitude"],
            "longitude": facility["longitude"],
            "price_available": facility["price_available"],
            "civil_price": facility["civil_price"],
            "public_price": facility["public_price"],
            "institution_price": facility["institution_price"],
            "price_source": facility["price_source"],
            "facility_email": facility_email,
            "facility_email_source": facility_source,
            "needs_email_fallback": facility_email is None,
            "parent_institution": parent_name,
            "parent_email": parent_email,
            "parent_email_source": parent_source,
            "parent_level": parent_level,
            "email": email,
            "email_status": status,
            "email_verified": bool(verified and email and source_url),
            "source_url": source_url if email else None,
            "source_type": source_type if email else None,
            "email_channel": channel if email else None,
            "suggested_parent": suggested,
            "institution_id": institution_id,
            "note": note,
        }
        return record


def suggested_parent(facility: dict) -> str:
    kind = facility["facility_class"]
    province = facility["province"]
    district = facility["district"]
    names = {
        "ogretmenevi": (
            f"{district} İlçe Millî Eğitim Müdürlüğü" if district else f"{province} İl Millî Eğitim Müdürlüğü"
        ),
        "dsi": "DSİ Bölge Müdürlüğü",
        "kgm": "Karayolları Bölge Müdürlüğü",
        "ogm": f"{province} Orman Bölge Müdürlüğü",
        "tarim": f"{province} İl Tarım ve Orman Müdürlüğü",
        "polis": f"{province} İl Emniyet Müdürlüğü",
        "jandarma": f"{province} İl Jandarma Komutanlığı",
        "dhmi": "DHMİ Genel Müdürlüğü",
        "belediye": f"{municipality_name(facility['facility_name'], province)} Belediyesi",
        "diyanet": f"{province} İl Müftülüğü",
        "tdv": "Türkiye Diyanet Vakfı",
        "mgm": "Meteoroloji Genel Müdürlüğü",
        "teias": "TEİAŞ",
        "tedas": "TEDAŞ Genel Müdürlüğü",
        "saglik": f"{province} İl Sağlık Müdürlüğü",
        "maliye": "Hazine ve Maliye Bakanlığı",
        "sgk": "Sosyal Güvenlik Kurumu",
        "ptt": "PTT",
        "tcdd": "TCDD",
        "adalet": "İlgili adliye / Adalet Bakanlığı",
        "csb": f"{province} Çevre, Şehircilik ve İklim Değişikliği İl Müdürlüğü",
        "mke": "Makine ve Kimya Endüstrisi",
        "etimaden": "Eti Maden",
        "vgm": "Vakıflar Genel Müdürlüğü",
        "ordu": "İlgili kuvvet komutanlığı / Millî Savunma Bakanlığı",
        "sendika": "Sendika",
        "universite": "Üniversite rektörlüğü",
        "diger": "Bağlı kamu kurumu doğrulanamadı",
    }
    if kind == "universite":
        matched = match_university(facility["facility_name"])
        if matched:
            return f"{matched[1]} Rektörlüğü"
    number = region_number(facility["facility_name"])
    if kind == "dsi" and number:
        return f"DSİ {number}. Bölge Müdürlüğü"
    if kind == "kgm" and number:
        return f"Karayolları {number}. Bölge Müdürlüğü"
    return names.get(kind, "Bağlı kamu kurumu doğrulanamadı")


def ogretmenevi_hosts(facility: dict) -> list[str]:
    province = ascii_slug(facility["province"])
    district = ascii_slug(facility["district"] or "")
    words = re.findall(r"[a-z0-9]+", fold_text(facility["facility_name"]).replace("ogretmen evi", "ogretmenevi"))
    drop = STOP_TOKENS | {"il", "ili", "aso", "prof", "doc", "dr"}
    kept = [word for word in words if word not in drop and word not in {province, district}]
    bases = []
    for base in (
        "".join(kept) + "ogretmenevi" if kept else "",
        district + "ogretmenevi" if district else "",
        province + "ogretmenevi",
        (district + "ogretmeneviaso") if district else "",
    ):
        if base and base not in bases and 6 <= len(base) <= 60:
            bases.append(base)
    return bases


def placeholder_addresses(raw_facilities: list[dict]) -> set[str]:
    counts: dict[str, int] = defaultdict(int)
    for raw in raw_facilities:
        address = as_text(raw.get("adres"))
        if address:
            counts[address] += 1
    return {address for address, count in counts.items() if count > 5}


def select_facilities(facilities: list[dict], province: str | None, limit: int | None) -> list[dict]:
    chosen = facilities
    if province:
        wanted = ascii_slug(province)
        chosen = [item for item in facilities if ascii_slug(item["province"]) == wanted]
    chosen = sorted(chosen, key=lambda item: (ascii_slug(item["province"]), norm_key(item["facility_name"])))
    if not limit or limit >= len(chosen):
        return chosen
    groups: dict[str, list[dict]] = defaultdict(list)
    for item in chosen:
        groups[item["facility_class"]].append(item)
    picked: list[dict] = []
    while len(picked) < limit and any(groups.values()):
        for key in sorted(groups):
            if groups[key]:
                picked.append(groups[key].pop(0))
            if len(picked) >= limit:
                break
    return picked


def write_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    json.loads(path.read_text(encoding="utf-8"))


def summarize(records: list[dict]) -> dict:
    counts = {
        "facility_verified": 0,
        "parent_verified": 0,
        "region_verified": 0,
        "general_directorate_verified": 0,
        "not_found": 0,
        "manual_review": 0,
    }
    kep = 0
    for record in records:
        status = record.get("email_status") or "not_found"
        counts[status] = counts.get(status, 0) + 1
        if record.get("email_channel") == "kep" and record.get("email"):
            kep += 1
    found = sum(counts[key] for key in (
        "facility_verified",
        "parent_verified",
        "region_verified",
        "general_directorate_verified",
    ))
    return {"counts": counts, "email_found": found, "kep": kep, "facilities": len(records)}


def self_test() -> None:
    assert len(PROVINCES) == 81
    assert len({ascii_slug(name) for name in PROVINCES}) == 81
    assert ascii_slug("Şanlıurfa") == "sanliurfa"
    assert ascii_slug("Çanakkale") == "canakkale"
    assert ascii_slug("Iğdır") == "igdir"
    assert ascii_slug("Kahramanmaraş") == "kahramanmaras"
    assert norm_key("Küçükçekmece Öğretmenevi (ASO)") == "kucukcekmeceogretmenevi(aso)"
    assert classify("Sarıyer Öğretmenevi", "Öğretmenevi") == "ogretmenevi"
    assert classify("Baltalimanı Polisevi", "Öğretmenevi") == "polis"
    assert classify("DSİ 5. Bölge Misafirhanesi", "Kamu Misafirhanesi") == "dsi"
    assert classify("Adana Jandarma Sosyal Tesisi", "Orduevi") == "jandarma"
    assert classify("Ataşehir Belediyesi Bahriye Üçok Konukevi", "Öğretmenevi") == "belediye"
    assert classify("Belediye - İş Sendikası Konuk Evi", "Sendika") == "sendika"
    assert classify("Adana Seyhan İlçe Tarım ve Orman Müdürlüğü Misafirhanesi", "Kamu") == "tarim"
    assert classify("Amasya Orman Bölge Müdürlüğü Misafirhanesi", "Orman") == "ogm"
    html = (
        '<img src="cimer@2x.png"><p>E-posta: istanbulobm@ogm.gov.tr '
        "KEP: ogm@ogm.hs01.kep.tr</p>"
    )
    hits = extract_hits(html)
    emails = {hit.email for hit in hits}
    assert "istanbulobm@ogm.gov.tr" in emails
    assert "cimer@2x.png" not in emails
    chosen, state = pick_email(hits, "www.ogm.gov.tr", ["istanbul", "obm"], set())
    assert state == "verified" and chosen and chosen.email == "istanbulobm@ogm.gov.tr"
    hidden = "E\u200b-posta: istanbulobm\u200b@ogm.gov.tr"
    assert any(hit.email == "istanbulobm@ogm.gov.tr" for hit in extract_hits(hidden))
    assert region_number("DSİ 14. Bölge Misafirhanesi") == 14
    assert region_number("Ağrı Dsi 85. Şube Misafirhanesi") is None
    assert match_university("Adana Çukurova Üniversitesi Balcalı Konukevi")[0] == "cu.edu.tr"
    print("self-test ok")


def main() -> None:
    parser = argparse.ArgumentParser(description="Doğrulanmış resmî tesis e-postalarını il JSON dosyalarına yazar.")
    parser.add_argument("--data-root", default=None)
    parser.add_argument("--out-dir", default="/workspace/data")
    parser.add_argument("--province", default=None)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--cache", default="/tmp/rotalink_email_http_cache.json")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    root = find_data_root(args.data_root)
    raw_facilities, districts, prices = load_inputs(root)
    placeholder = placeholder_addresses(raw_facilities)
    prepared = []
    outside = defaultdict(int)
    allowed = {ascii_slug(name) for name in PROVINCES}
    for raw in raw_facilities:
        province = as_text(raw.get("il")) or ""
        if ascii_slug(province) not in allowed:
            outside[province] += 1
            continue
        prepared.append(prepare_facility(raw, districts, prices, placeholder))
    by_slug: dict[str, list[str]] = defaultdict(list)
    for item in prepared:
        if item["district"]:
            by_slug[ascii_slug(item["district"])].append(item["province"])
    collisions = {slug for slug, provinces in by_slug.items() if len(set(provinces)) > 1}
    selected = select_facilities(prepared, args.province, args.limit)
    http = Http(Path(args.cache), global_gap=0.12, host_gap=0.4)
    engine = Engine(http)
    engine.collisions = collisions
    records: list[dict] = []
    if args.workers <= 1 or len(selected) <= 1:
        for index, facility in enumerate(selected, start=1):
            record = engine.research_facility(facility)
            records.append(record)
            if record.get("email"):
                print(
                    f"[{index}/{len(selected)}] {record['email_status']} {record['facility_name']} -> {record['email']}",
                    flush=True,
                )
    else:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {pool.submit(engine.research_facility, facility): facility for facility in selected}
            done = 0
            for future in as_completed(futures):
                done += 1
                record = future.result()
                records.append(record)
                if record.get("email") or done % 25 == 0:
                    print(
                        f"[{done}/{len(selected)}] {record['province']} {record['facility_name']} "
                        f"{record['email_status']} {record.get('email')}",
                        flush=True,
                    )
    http.flush()
    records.sort(key=lambda item: (ascii_slug(item["province"]), norm_key(item["facility_name"])))
    out = Path(args.out_dir)
    sample = bool(args.limit)
    if sample:
        slug = ascii_slug(args.province or "ornek")
        write_json(out / "emails" / f"_sample_{slug}.json", {"generated_at": TODAY, "facilities": records})
    else:
        grouped: dict[str, list[dict]] = defaultdict(list)
        for record in records:
            grouped[ascii_slug(record["province"])].append(record)
        for province in PROVINCES:
            slug = ascii_slug(province)
            rows = grouped.get(slug, [])
            display = rows[0]["province"] if rows else province
            stats = summarize(rows)
            write_json(
                out / "emails" / f"{slug}.json",
                {
                    "province": display,
                    "province_slug": slug,
                    "generated_at": TODAY,
                    "facility_count": len(rows),
                    "email_found_count": stats["email_found"],
                    "counts": stats["counts"],
                    "facilities": rows,
                },
            )
    institutions = [item.to_json() for item in engine.research.results.values() if item.institution_id != "kgm-footer"]
    institutions.sort(key=lambda item: item["id"])
    write_json(
        out / "institutions" / "kurumlar.json",
        {"generated_at": TODAY, "institution_count": len(institutions), "institutions": institutions},
    )
    manual = []
    for record in records:
        if record.get("email"):
            continue
        manual.append(
            {
                "facility_name": record["facility_name"],
                "province": record["province"],
                "district": record["district"],
                "facility_class": record["facility_class"],
                "email_status": record["email_status"],
                "reason": record.get("note") or "Official email could not be verified",
                "suggested_parent": record.get("suggested_parent"),
                "institution_id": record.get("institution_id"),
                "searched_at": TODAY,
            }
        )
    manual_name = "manual_review.json" if not sample else "_sample_manual_review.json"
    write_json(out / "emails" / manual_name, manual)
    stats = summarize(records)
    provinces_done = len({ascii_slug(item["province"]) for item in records}) if records else 0
    if not sample:
        provinces_done = 81
    summary = {
        "generated_at": TODAY,
        "data_root": str(root),
        "province_count": provinces_done,
        "facility_count": stats["facilities"],
        "email_found": stats["email_found"],
        "counts": stats["counts"],
        "kep": stats["kep"],
        "excluded_outside_81_provinces": dict(outside),
        "sample": sample,
    }
    if not sample:
        write_json(out / "emails" / "ozet.json", summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
