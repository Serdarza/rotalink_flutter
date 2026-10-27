import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/data/kis_kesfet_official_sources.dart';
import 'package:rotalink_flutter/data/kis_kesfet_repository.dart';
import 'package:rotalink_flutter/models/kis_kesfet_place.dart';

void main() {
  test('gömülü termaller rehber yerine tesis veya kamu sayfasını kullanır', () {
    final places = KisKesfetRepository.parse(
      File(KisKesfetRepository.assetPath).readAsStringSync(),
    );
    final thermals = places
        .where((p) => p.kategori == KisKesfetKategori.termal)
        .toList();
    expect(thermals, isNotEmpty);
    expect(
      thermals.where(
        (p) => Uri.parse(p.resmiKaynak).host.contains('kamutesisleri'),
      ),
      isEmpty,
    );
    for (final entry in KisKesfetOfficialSources.thermalSources.entries) {
      expect(
        thermals.singleWhere((p) => p.id == entry.key).resmiKaynak,
        entry.value,
      );
    }
  });

  test(
    'eski uzak rehber bağlantıları düzelir, tesis güncellemeleri korunur',
    () {
      final local = KisKesfetRepository.parse(
        File(KisKesfetRepository.assetPath).readAsStringSync(),
      );
      final remote = KisKesfetRepository.parse(
        jsonEncode({
          'kayitlar': [
            for (final id in KisKesfetOfficialSources.thermalSources.keys)
              {
                'id': id,
                'kategori': 'termal',
                'il': 'Ankara',
                'isim': 'Güncellenen tesis',
                'tesisSinifi': 'kamu',
                'telefon': '0312 123 45 67',
                'resmiKaynak': 'https://www.kamutesisleri.com/eski-tesis',
              },
          ],
        }),
      );
      final merged = KisKesfetRepository.mergeById(local, remote);
      for (final entry in KisKesfetOfficialSources.thermalSources.entries) {
        final place = merged.singleWhere((p) => p.id == entry.key);
        expect(place.resmiKaynak, entry.value);
        expect(place.telefon, '0312 123 45 67');
        expect(place.isim, 'Güncellenen tesis');
      }
    },
  );

  test('yeni kurum bağlantısı ve diğer tesislerin kaynağı değiştirilmez', () {
    final places = KisKesfetRepository.parse(
      jsonEncode({
        'kayitlar': [
          {
            'id': 'termal-ankara-sifa',
            'kategori': 'termal',
            'il': 'Ankara',
            'isim': 'Şifa Termal',
            'tesisSinifi': 'kamu',
            'resmiKaynak': 'https://www.ankara.bel.tr/tesis/yeni-sayfa',
          },
          {
            'id': 'kayak-1',
            'kategori': 'kayak',
            'il': 'Bursa',
            'isim': 'Kayak merkezi',
            'resmiKaynak': 'https://ornek.gov.tr/kayak',
          },
        ],
      }),
    );
    expect(
      places.first.resmiKaynak,
      'https://www.ankara.bel.tr/tesis/yeni-sayfa',
    );
    expect(places.last.resmiKaynak, 'https://ornek.gov.tr/kayak');
  });

  const raw = '''
{
  "kayitlar": [
    {
      "id": "kayak-1",
      "kategori": "kayak",
      "il": "Bursa",
      "ilce": "",
      "isim": "Uludağ",
      "kurumTuru": "Kış sporları merkezi",
      "kisaAciklama": "Kısa",
      "adres": "",
      "telefon": "",
      "kullanimTuru": "",
      "anaBilgiler": [
        {"baslik": "Pist uzunluğu", "deger": "13 pist"},
        {"baslik": "", "deger": "boş"},
        {"baslik": "Sezon", "deger": ""}
      ],
      "latitude": 0,
      "longitude": 0,
      "resmiKaynak": "https://www.ktb.gov.tr/ornek",
      "sonDogrulama": "2026-10-22",
      "pistHaritasi": {
        "sayfaUrl": "https://gouludag.com/tr/harita",
        "kaynakAdi": "Uludağ Alan Başkanlığı",
        "resmi": true,
        "sonKontrol": "2026-10-22",
        "durum": "sayfa"
      }
    },
    {
      "id": "termal-1",
      "kategori": "termal",
      "il": "Ankara",
      "isim": "Kaplıca",
      "telefon": "0312 000 00 00",
      "tesisSinifi": "kamu",
      "kurumTuru": "Belediye",
      "latitude": 40.1,
      "longitude": 32.6,
      "resmiKaynak": "https://hsgm.saglik.gov.tr/ornek.pdf"
    },
    {
      "isim": "Kaynaksız",
      "il": "Bolu",
      "kategori": "kayak",
      "resmiKaynak": "dosya.pdf"
    },
    {
      "isim": "",
      "il": "Bolu",
      "kategori": "kayak",
      "resmiKaynak": "https://www.ktb.gov.tr/ornek"
    },
    {
      "isim": "Bilinmeyen",
      "il": "Bolu",
      "kategori": "yaz",
      "resmiKaynak": "https://www.ktb.gov.tr/ornek"
    }
  ]
}
''';

  test('boş telefon, boş koordinat ve geçersiz kaynağı ayırır', () {
    final places = KisKesfetRepository.parse(raw);
    expect(places, hasLength(2));

    final uludag = places.first;
    expect(uludag.isim, 'Uludağ');
    expect(uludag.hasPhone, isFalse);
    expect(uludag.hasCoordinates, isFalse);
    expect(uludag.hasOfficialSource, isTrue);
    expect(uludag.hasFacts, isTrue);
    expect(uludag.anaBilgiler, hasLength(1));
    expect(uludag.anaBilgiler.single.deger, '13 pist');
    expect(uludag.pistHaritasi, isNotNull);
    expect(uludag.pistHaritasi!.durum, KisKesfetPistDurum.sayfa);
    expect(uludag.pistHaritasi!.hasGorsel, isFalse);
    expect(uludag.pistHaritasi!.hasSayfa, isTrue);
    expect(uludag.pistHaritasi!.sayfaUrl, 'https://gouludag.com/tr/harita');

    final kaplica = places.last;
    expect(kaplica.hasPhone, isTrue);
    expect(kaplica.latitude, 40.1);
    expect(kaplica.longitude, 32.6);
    expect(kaplica.kategori, KisKesfetKategori.termal);
    expect(kaplica.isKamuTesis, isTrue);
    expect(kaplica.tesisRozeti, 'Kamu · Belediye');
  });

  test('geçersiz koordinatı yok sayar, kaydı düşürmez', () {
    const broken = '''
{"kayitlar":[{"isim":"Merkez","il":"Van","kategori":"kisGezisi","latitude":120,"longitude":10,"resmiKaynak":"https://ornek.gov.tr/a"}]}
''';
    final place = KisKesfetRepository.parse(broken).single;
    expect(place.hasCoordinates, isFalse);
    expect(place.kategori, KisKesfetKategori.kisGezisi);
  });

  test('illeri ve kategori sayılarını gruplar', () {
    final places = KisKesfetRepository.parse(raw);
    final kayak = KisKesfetRepository.forCategory(
      places,
      KisKesfetKategori.kayak,
    );
    final grouped = KisKesfetRepository.groupByIl(kayak);
    expect(KisKesfetRepository.sortedIller(grouped), ['Bursa']);
    expect(grouped['Bursa'], hasLength(1));
  });

  test('özel termal tesisi yüklemez', () {
    const ozel = '''
{"kayitlar":[{
  "id":"termal-x","kategori":"termal","il":"Ankara","isim":"Özel Kaplıca",
  "tesisSinifi":"ozel","kurumTuru":"Özel tesis",
  "resmiKaynak":"https://hsgm.saglik.gov.tr/ornek.pdf"
}]}
''';
    expect(KisKesfetRepository.parse(ozel), isEmpty);
  });

  test('kırık görsel URL pist haritasını sayfaya düşürür', () {
    const rawMap = '''
{"kayitlar":[{
  "id":"kayak-x","kategori":"kayak","il":"Kayseri","isim":"Erciyes",
  "resmiKaynak":"https://ornek.gov.tr/a",
  "pistHaritasi":{"durum":"gorsel","gorselUrl":"not-a-url","sayfaUrl":"https://kayserierciyes.com.tr/kayak-haritasi"}
}]}
''';
    final map = KisKesfetRepository.parse(rawMap).single.pistHaritasi!;
    expect(map.durum, KisKesfetPistDurum.sayfa);
    expect(map.hasGorsel, isFalse);
    expect(map.hasSayfa, isTrue);
  });

  test('uzak kayıt aynı idyi günceller, yerel idyi silmez', () {
    final local = KisKesfetRepository.parse(raw);
    const remoteRaw = '''
{"kayitlar":[{
  "id":"kayak-1","kategori":"kayak","il":"Bursa","isim":"Uludağ Kayak Merkezi",
  "resmiKaynak":"https://www.ktb.gov.tr/guncel",
  "sonDogrulama":"2026-11-01"
},{
  "id":"kayak-kartepe","kategori":"kayak","il":"Kocaeli","isim":"Kartepe Kayak Merkezi",
  "resmiKaynak":"https://kocaeli.ktb.gov.tr/genel"
}]}
''';
    final merged = KisKesfetRepository.mergeById(
      local,
      KisKesfetRepository.parse(remoteRaw),
    );
    expect(
      merged.map((p) => p.id),
      containsAll(['kayak-1', 'termal-1', 'kayak-kartepe']),
    );
    expect(
      merged.singleWhere((p) => p.id == 'kayak-1').resmiKaynak,
      'https://www.ktb.gov.tr/guncel',
    );
  });
}
