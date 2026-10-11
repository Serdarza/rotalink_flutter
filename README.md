# rotalink_flutter

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Tesis iletişim e-postaları

`data/emails/` ve `data/institutions/` altındaki dosyalar, kamu konaklama tesisleri için **doğrulanmış resmî** iletişim adreslerini tutar. Adres, kurumun kendi sitesinden, resmî alt alan adından veya aynı sitedeki iletişim sayfası / PDF üzerinden okunmadan kaydedilmez. Sayfada adres yoksa alan `null` kalır. İl veya kurum adından `sariyer@meb.gov.tr`, `info@dsi.gov.tr` gibi adres **üretilmez**.

Mevcut tesis fiyatları (`fiyat_sivil`, `fiyat_kamu_personeli`, `fiyat_kurum_personeli`) olduğu gibi `civil_price`, `public_price` ve `institution_price` alanlarına kopyalanır. Fiyat ve tesis ana verisi bu çalışmayla değiştirilmez.

### Dosyalar

| Yol | İçerik |
| --- | --- |
| `data/emails/tum_iller.json` | 81 ilin tesisleri tek dosyada. `provinces` dizisi il sırasını korur. |
| `data/emails/<il>.json` | İlin bütün tesisleri. Dosya adı ASCII: `şanlıurfa` → `sanliurfa`, `çanakkale` → `canakkale`, `iğdır` → `igdir`, `kahramanmaraş` → `kahramanmaras`. |
| `data/emails/manual_review.json` | Resmî adresi doğrulanamayan tesisler. |
| `data/emails/ozet.json` | İl ve durum sayıları. |
| `data/institutions/kurumlar.json` | Aynı kuruma bir kez bakılan önbellek. |

JSON UTF-8'dir. Dosya adları ASCII, il / tesis / kurum adları Türkçe'dir. 81 il dışındaki kayıtlar (örneğin Kıbrıs) bu klasöre yazılmaz.

### Tesis kaydı

Tesisin kendi adresi varsa `facility_email` doludur, `needs_email_fallback` false'tur ve üst kurum adresiyle değiştirilmez. Kendi adresi yoksa `needs_email_fallback` true olur; bulunan üst kurum adresi `parent_email` alanındadır.

`email_status` değerleri:

- `facility_verified` — tesisin kendi sayfası
- `parent_verified` — ilçe veya il müdürlüğü, belediye, üniversite, il emniyeti
- `region_verified` — bölge müdürlüğü
- `general_directorate_verified` — genel müdürlük veya bakanlık
- `not_found` — bakılan resmî sayfada adres yok
- `manual_review` — birden fazla aday vardı, biri seçilmedi

`email_verified` yalnızca `email` ve `source_url` birlikte varsa true olur. `source_type`: `official_website`, `official_pdf`, `official_document` veya `other_official_source`. `email_channel` `kep` ise adres KEP'tir; olağan SMTP gelen kutusu değildir.

Öğretmenevinde sıra ilçe MEM, yoksa il MEM'dir. DSİ, Karayolları, OGM, DHMİ, emniyet, jandarma, üniversite, belediye, adalet, diyanet ve diğer kamu tesislerinde de önce tesise en yakın resmî birim, o yoksa bir üst birim denenir.

### Çalıştırma

Salt okunur katalog `rotalink-data` klasöründedir (`master_database_updated.json`, `tesisler_adres.json`, `fiyatlar.json`).

```bash
python3 scripts/find_missing_emails.py --self-test
python3 scripts/find_missing_emails.py --province İstanbul --limit 10 --out-dir /tmp/email_sample
python3 scripts/find_missing_emails.py --data-root /yol/rotalink-data --out-dir data
```

İstekler kurum başına ve genel olarak seyreltilir. Aynı kurum ikinci tesiste yeniden indirilmez; sonuç `kurumlar.json` içindedir. HTTP önbelleği depoya yazılmaz.
