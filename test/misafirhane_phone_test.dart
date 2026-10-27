import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';

void main() {
  Map<String, dynamic> record(String phone) => {
    'isim': 'Konya Orduevi',
    'il': 'Konya',
    'tip': 'Orduevi',
    'adres': 'Karatay / Konya',
    'telefon': phone,
    'latitude': 0,
    'longitude': 0,
  };

  test('tek numara okunur', () {
    expect(
      Misafirhane.tryParse(record('(0332) 351 75 45'))!.telefonNumaralari,
      ['(0332) 351 75 45'],
    );
  });

  test(
    'telefon ve telefon2 ayrı okunur, kopyalarda ve JSON kaydında korunur',
    () {
      final input = record('(0332) 321 14 11')
        ..['telefon2'] = '(0332) 322 69 70';
      final facility = Misafirhane.tryParse(input)!;
      expect(facility.telefonNumaralari, [
        '(0332) 321 14 11',
        '(0332) 322 69 70',
      ]);
      expect(facility.copyWithoutPrices().telefon2, '(0332) 322 69 70');
      expect(
        facility.copyWithAddress(adres: 'Yeni adres').telefon2,
        '(0332) 322 69 70',
      );
      expect(
        Misafirhane.tryParse(facility.toJson())!.telefonNumaralari,
        facility.telefonNumaralari,
      );
    },
  );

  test('eski birleşik iki numara ayrı okunur', () {
    expect(
      Misafirhane.tryParse(
        record('(0332) 321 14 11 / (0332) 322 69 70'),
      )!.telefonNumaralari,
      ['(0332) 321 14 11', '(0332) 322 69 70'],
    );
  });

  test('eski numara1 ve numara2 alanları okunur', () {
    final input = record('')
      ..remove('telefon')
      ..['numara1'] = '0532 123 45 67'
      ..['numara2'] = '0533 123 45 67';
    expect(Misafirhane.tryParse(input)!.telefonNumaralari, [
      '0532 123 45 67',
      '0533 123 45 67',
    ]);
  });

  test('ikinci numara boşsa, yoksa veya aynıysa ikinci seçenek yoktur', () {
    final empty = record('0532 123 45 67')..['telefon2'] = '';
    expect(Misafirhane.tryParse(empty)!.telefonNumaralari.length, 1);
    final duplicate = record('0532 123 45 67')..['telefon2'] = '05321234567';
    expect(Misafirhane.tryParse(duplicate)!.telefonNumaralari.length, 1);
    expect(Misafirhane.tryParse(record(''))!.telefonNumaralari, isEmpty);
  });
}
