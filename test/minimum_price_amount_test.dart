import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/utils/minimum_price_amount.dart';

void main() {
  test('TL aralıklarında yalnızca en düşük gerçek tutarı seçer', () {
    for (final entry in {
      '1.150 – 3.475 TL': 1150.0,
      '850 – 2.650 TL': 850.0,
      '700 – 2.237,50 TL': 700.0,
      '2.237,50 TL – 700 TL': 700.0,
      '₺1.150 — ₺3.475': 1150.0,
      '1.234,50 TL / gece': 1234.5,
      '1234.50 TL': 1234.5,
      '1 150 - 3 475 TL': 1150.0,
      '0 TL': 0.0,
    }.entries) {
      expect(minimumPriceAmount(entry.key), entry.value, reason: entry.key);
    }
  });
  test('sayısal olmayan fiyat açıklamalarını ücret gibi yorumlamaz', () {
    for (final value in [
      '',
      'Kalamaz',
      'Bilgi için arayınız',
      '2026 tarifesi',
      '1.200 TL + kahvaltı',
      '-100 TL',
    ]) {
      expect(minimumPriceAmount(value), isNull, reason: value);
    }
  });
}
