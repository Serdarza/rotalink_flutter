import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/billing/premium_auth_service.dart';

void main() {
  test('Play account binding uses stable SHA-256 base64url digest', () {
    expect(
      obfuscatedPremiumAccountId('test-user-123'),
      '1RloYX0JQNezzMaDOUpA-cQPsV0P_95DQwP5f5GPsg0',
    );
    expect(
      obfuscatedPremiumAccountId('another-user'),
      isNot(equals(obfuscatedPremiumAccountId('test-user-123'))),
    );
    expect(() => obfuscatedPremiumAccountId(''), throwsArgumentError);
  });
}
