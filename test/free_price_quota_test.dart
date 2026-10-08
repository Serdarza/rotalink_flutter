import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/billing/free_price_quota.dart';
import 'package:rotalink_flutter/billing/price_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ücretsiz açılan tesisler kalıcı ve kalan hak doğru', () async {
    SharedPreferences.setMockInitialValues({
      'rotalink_free_price_facilities': ['Ankara\u0001A Tesisi'],
    });
    final quota = FreePriceQuota.instance;
    await quota.initialize();

    expect(FreePriceQuota.limit, 3);
    expect(quota.remaining, 2);
    expect(quota.contains('Ankara\u0001A Tesisi'), isTrue);
    expect(quota.contains('Ankara\u0001B Tesisi'), isFalse);
    expect(PriceAccess.unlockedFor('Ankara\u0001A Tesisi'), isTrue);
    expect(await quota.unlock('Ankara\u0001A Tesisi'), isNull);
  });
}
