import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/facility_price_entry.dart';
import 'package:rotalink_flutter/models/facility_tariff.dart';
import 'package:rotalink_flutter/widgets/facility_tariff_view.dart';

void main() {
  group('fiyatlar.json (rotalink-data)', () {
    final file = File('../rotalink-data/fiyatlar.json');

    test('tüm kayıtlar okunur; eski özet alanları korunur', () {
      if (!file.existsSync()) return;
      final root = jsonDecode(file.readAsStringSync()) as Map;
      final list = root['tesisler'] as List;
      for (final raw in list) {
        final e = FacilityPriceEntry.tryParse(raw)!;
        expect(e.hasFiyatBilgisi, isTrue, reason: e.isim);
        expect(e.fiyatSivil, (raw as Map)['fiyat_sivil'], reason: e.isim);
        expect(e.fiyatKamuPersoneli, raw['fiyat_kamu_personeli']);
        expect(e.fiyatKurumPersoneli, raw['fiyat_kurum_personeli']);
        expect(e.tarife == null, raw['tarife'] == null, reason: e.isim);
      }
    });

    test('Akçakoca Öğretmen Evi detaylı tarifesi', () {
      if (!file.existsSync()) return;
      final root = jsonDecode(file.readAsStringSync()) as Map;
      final raw = (root['tesisler'] as List).firstWhere(
        (t) => t['isim'] == 'Akçakoca Öğretmen Evi',
      );
      final e = FacilityPriceEntry.tryParse(raw)!;
      final t = e.tarife!;
      expect(t.tablolar, hasLength(1));
      expect(t.tablolar.single.kategoriler.map((c) => c.ad).toList(), [
        'Öğretmen / Bakanlık Personeli',
        'Kamu',
        'Sivil',
      ]);
      expect(t.tablolar.single.satirlar, hasLength(6));
      expect(t.dogrulama, TariffVerification.resmiKaynak);
      expect(t.girisSaati, '14:00');

      final ranges = t.derivedRanges();
      expect(
        ranges.map((r) => '${r.label}: ${formatTlRange(r.min, r.max)}'),
        [
          'Öğretmen / Bakanlık Personeli: 1.850 – 5.000 TL',
          'Kamu: 2.250 – 6.000 TL',
          'Sivil: 3.000 – 7.000 TL',
        ],
      );
    });
  });

  test('farklı kurum yapısı: 4 kategori, metin fiyat, eksik hücre', () {
    final t = FacilityTariff.tryParse({
      'birim': 'kişi başı / gece',
      'tablolar': [
        {
          'baslik': 'Yaz dönemi',
          'kategoriler': ['Akademik', 'Öğrenci', 'Kamu', 'Sivil'],
          'satirlar': [
            {
              'ad': 'Tek kişilik oda',
              'fiyatlar': {'Akademik': 900, 'Kamu': 'Bilgi için arayınız'},
            },
          ],
        },
      ],
    })!;
    final table = t.tablolar.single;
    expect(table.kategoriler, hasLength(4));
    expect(table.birim, 'kişi başı / gece');
    final row = table.satirlar.single;
    expect(row.fiyatlar['Akademik']!.amount, 900);
    expect(row.fiyatlar['Kamu']!.text, 'Bilgi için arayınız');
    expect(row.fiyatlar['Öğrenci'], isNull);
  });

  test('yalnızca eski alanlar: tarife yok, davranış aynı', () {
    final e = FacilityPriceEntry.tryParse({
      'il': 'X',
      'isim': 'Y',
      'fiyat_sivil': '1.000 TL',
      'fiyat_kamu_personeli': null,
    })!;
    expect(e.tarife, isNull);
    expect(e.fiyatKamuDefined, isTrue);
    expect(e.fiyatKamuPersoneli, isNull);
    expect(e.fiyatKurumDefined, isFalse);
  });

  test('boş tarife yok sayılır', () {
    expect(FacilityTariff.tryParse({'baslik': 'Boş'}), isNull);
  });

  test('formatTl', () {
    expect(formatTl(1850), '1.850 TL');
    expect(formatTl(450.5), '450,50 TL');
    expect(formatTl(12500), '12.500 TL');
  });

  testWidgets('dar ekranda kart, geniş ekranda tablo', (tester) async {
    final t = FacilityTariff.tryParse({
      'kategoriler': [
        {'id': 'a', 'ad': 'Öğretmen'},
        {'id': 'b', 'ad': 'Kamu'},
        {'id': 'c', 'ad': 'Sivil'},
      ],
      'tablolar': [
        {
          'satirlar': [
            {'ad': 'Tek Kişi', 'fiyatlar': {'a': 1850, 'b': 2250, 'c': 3000}},
          ],
        },
      ],
      'kurallar': ['Kahvaltı dahildir.'],
    })!;

    Future<void> pump(double width) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: SingleChildScrollView(
                    child: FacilityTariffView(tariff: t),
                  ),
                ),
              ),
            ),
          ),
        );

    await pump(330);
    expect(find.byType(Table), findsNothing);
    expect(find.text('Tek Kişi'), findsOneWidget);
    expect(find.text('1.850 TL'), findsOneWidget);
    expect(find.text('• Kahvaltı dahildir.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pump(700);
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('Tek Kişi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
