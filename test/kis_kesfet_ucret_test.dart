import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/data/kis_kesfet_repository.dart';
import 'package:rotalink_flutter/models/kis_kesfet_place.dart';
import 'package:rotalink_flutter/models/kis_kesfet_ucret.dart';

Map<String, Object?> kalem({
  String tur = 'havuz',
  num tutar = 250,
  bool baslangic = true,
}) => {
  'tur': tur,
  'ad': 'Umumi havuz',
  'tutar': tutar,
  'birim': 'kişi / 90 dakika',
  'kaynakUrl': 'https://tesis.bel.tr/tarife',
  'baslangic': baslangic,
};

Map<String, Object?> bilgi({String tarih = '2026-10-24'}) => {
  'sonKontrol': tarih,
  'kalemler': [kalem()],
};

String katalog(Object? fees, {String telefon = '123'}) => jsonEncode({
  'kayitlar': [
    {
      'id': 'termal-test',
      'kategori': 'termal',
      'isim': 'Termal tesis',
      'il': 'Ankara',
      'tesisSinifi': 'kamu',
      'telefon': telefon,
      'resmiKaynak': 'https://tesis.bel.tr',
      'ucretBilgisi': ?fees,
    },
  ],
});

void main() {
  final kontrol = DateTime(2026, 10, 24);

  test('başlangıç fiyatı çocuk ve ilave ücretlerden seçilmez', () {
    final raw = bilgi()
      ..['kalemler'] = [
        kalem(tutar: 0, baslangic: false),
        kalem(tutar: 100, baslangic: false),
        kalem(tutar: 250),
        kalem(tur: 'konaklama', tutar: 2000),
      ];
    final fees = KisKesfetUcretBilgisi.fromJson(raw)!;
    expect(fees.baslangicUcreti(kontrol)!.tutar, 250);
    expect(fees.baslangicUcreti(kontrol)!.tur, KisKesfetUcretTuru.havuz);
  });

  test('süresi biten tarife gösterilmez ve başlangıç fiyatı olamaz', () {
    final expired = kalem()..['gecerlilikBitis'] = '2026-10-23';
    final raw = bilgi()..['kalemler'] = [expired];
    final fees = KisKesfetUcretBilgisi.fromJson(raw)!;
    expect(fees.gecerliKalemler(DateTime(2026, 10, 23)), hasLength(1));
    expect(fees.gecerliKalemler(kontrol), isEmpty);
    expect(fees.baslangicUcreti(kontrol), isNull);
  });

  test(
    'bozuk, negatif, kaynaksız veya tutarı metin olan tarife kabul edilmez',
    () {
      for (final invalid in [
        kalem(tutar: -1),
        kalem(tur: 'bilinmeyen'),
        kalem()..['tutar'] = '250 TL',
        kalem()..['kaynakUrl'] = 'dosya.pdf',
        kalem()..['gecerlilikBitis'] = 'bilinmiyor',
      ]) {
        expect(
          KisKesfetUcretBilgisi.fromJson(bilgi()..['kalemler'] = [invalid]),
          isNull,
        );
      }
      expect(
        KisKesfetUcretBilgisi.fromJson(bilgi(tarih: '2026-02-30')),
        isNull,
      );
      expect(
        KisKesfetUcretBilgisi.fromJson(bilgi()..['kalemler'] = 'bozuk'),
        isNull,
      );
    },
  );

  test('eski şema ve eski tarihli uzak kayıt ücretleri silemez', () {
    final local = KisKesfetRepository.parse(katalog(bilgi()));
    for (final remoteFees in [
      null,
      bilgi(tarih: '2026-10-01'),
      bilgi()..['kalemler'] = [kalem(tutar: -10)],
    ]) {
      final remote = KisKesfetRepository.parse(
        katalog(remoteFees, telefon: '456'),
      );
      final merged = KisKesfetRepository.mergeById(local, remote).single;
      expect(merged.telefon, '456');
      expect(merged.ucretBilgisi!.sonKontrol, '2026-10-24');
      expect(merged.ucretBilgisi!.kalemler.single.tutar, 250);
    }
  });

  test('daha yeni doğrulanmış tarife güncellenir ve açıkça boşaltılabilir', () {
    final local = KisKesfetRepository.parse(katalog(bilgi()));
    final yeni = bilgi(tarih: '2026-10-25')..['kalemler'] = [kalem(tutar: 300)];
    final updated = KisKesfetRepository.mergeById(
      local,
      KisKesfetRepository.parse(katalog(yeni)),
    ).single;
    expect(updated.ucretBilgisi!.kalemler.single.tutar, 300);
    final empty = bilgi(tarih: '2026-10-26')..['kalemler'] = [];
    final cleared = KisKesfetRepository.mergeById([
      updated,
    ], KisKesfetRepository.parse(katalog(empty))).single;
    expect(cleared.ucretBilgisi!.kalemler, isEmpty);
  });

  test(
    'tüm termal kayıtlarında araştırma sonucu ve kaynak var; kayak değişmez',
    () {
      final places = KisKesfetRepository.parse(
        File(KisKesfetRepository.assetPath).readAsStringSync(),
      );
      final thermal = places
          .where((p) => p.kategori == KisKesfetKategori.termal)
          .toList();
      expect(thermal, hasLength(51));
      expect(
        thermal.where((p) => p.ucretBilgisi!.kalemler.isNotEmpty),
        hasLength(12),
      );
      for (final place in thermal) {
        final fees = place.ucretBilgisi!;
        expect(fees.sonKontrol, '2026-10-24');
        expect(fees.kaynaklar, isNotEmpty);
        if (fees.kalemler.isNotEmpty) {
          expect(fees.baslangicUcreti(kontrol), isNotNull);
        }
      }
      final bingol = thermal.singleWhere(
        (p) => p.id == 'termal-bingol-universite',
      );
      expect(
        bingol.ucretBilgisi!.kalemler.where(
          (k) => k.tur == KisKesfetUcretTuru.havuz,
        ),
        isEmpty,
      );
      final aziziye = thermal.singleWhere(
        (p) => p.id == 'termal-erzurum-aziziye',
      );
      expect(aziziye.ucretBilgisi!.kalemler, isEmpty);
      expect(
        places.where((p) => p.isKayak).every((p) => p.ucretBilgisi == null),
        isTrue,
      );
    },
  );
}
