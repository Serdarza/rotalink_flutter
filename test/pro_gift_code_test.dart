import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/billing/pro_gift_code.dart';

void main() {
  test('kod özeti rotalink-data/pro_kod/kod_uret.py ile aynı', () {
    expect(ProGiftCodes.normalize('rl-ab2c 3d4e-fghj'), 'RLAB2C3D4EFGHJ');
    expect(
      ProGiftCodes.hash(ProGiftCodes.normalize('RL-AB2C-3D4E-FGHJ')),
      'c5df1eb90b02ab60c362a34e3aa9efdccc3889ed84ca6caff5e1247e4bff6d25',
    );
  });

  test('kod listesi ayrıştırma ve süreler', () {
    final entries = ProGiftCodes.parse('''
{"kodlar": [
  {"ozet": "${'a' * 64}", "plan": "aylik", "son_kullanma": "2026-12-31"},
  {"ozet": "${'b' * 64}", "plan": "yillik", "kullanim": 50},
  {"ozet": "kisa", "plan": "aylik"},
  {"ozet": "${'c' * 64}", "plan": "haftalik"}
]}''');
    expect(entries, hasLength(2));
    expect(entries[0].sure, const Duration(days: 30));
    expect(entries[0].expiredAt(DateTime(2026, 12, 31, 20)), isFalse);
    expect(entries[0].expiredAt(DateTime(2027, 1, 1, 0, 1)), isTrue);
    expect(entries[1].sure, const Duration(days: 365));
    expect(entries[1].kullanim, 50);
    expect(entries[1].expiredAt(DateTime(2030)), isFalse);
  });
}
