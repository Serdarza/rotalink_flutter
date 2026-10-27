import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/models/misafirhane.dart';

void main() {
  Map<String, dynamic> base(String phone) => {
        'isim': 'Konya Orduevi',
        'il': 'Konya',
        'tip': 'Orduevi',
        'adres': 'Karatay / Konya',
        'telefon': phone,
        'latitude': 0,
        'longitude': 0,
      };

  test('eski slash ile birleştirilmiş iki numara ayrı okunur', () {
    final facility = Misafirhane.tryParse(base(
      '(0332) 321 14 11 / (0332) 322 69 70',
    ))!;
    expect(facility.telefonNumaralari, [
      '(0332) 321 14 11',
      '(0332) 322 69 70',
    ]);
  });

  test('yeni telefon2 alanı ve saklama/okuma korunur', () {
    final data = base('(0332) 321 14 11')
      ..['telefon2'] = '(0332) 322 69 70';
    final facility = Misafirhane.tryParse(data)!;
    expect(facility.telefonNumaralari.length, 2);
    expect(Misafirhane.tryParse(facility.toJson())!.telefonNumaralari.length, 2);
    expect(facility.copyWithoutPrices().telefon2, '(0332) 322 69 70');
    expect(facility.copyWithAddress(adres: 'Yeni adres').telefon2,
        '(0332) 322 69 70');
  });

  test('tek numarada seçim gerekmez', () {
    final facility = Misafirhane.tryParse(base('(0332) 351 75 45'))!;
    expect(facility.telefonNumaralari, ['(0332) 351 75 45']);
  });

  test('tekrarlanan ve geçersiz numaralar ikinci seçenek üretmez', () {
    final data = base('(0332) 321 14 11')
      ..['telefon2'] = '0332 321 14 11';
    expect(Misafirhane.tryParse(data)!.telefonNumaralari.length, 1);
    expect(Misafirhane.tryParse(base('numara yok'))!.telefonNumaralari, isEmpty);
  });
}
