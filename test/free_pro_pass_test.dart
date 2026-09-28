import 'package:flutter_test/flutter_test.dart';
import 'package:rotalink_flutter/billing/pro_service.dart';
import 'package:rotalink_flutter/widgets/free_pro_pass.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('formatFreePassRemaining', () {
    expect(
      formatFreePassRemaining(const Duration(minutes: 42, seconds: 5)),
      '42:05',
    );
    expect(formatFreePassRemaining(const Duration(hours: 1)), '1:00:00');
    expect(formatFreePassRemaining(Duration.zero), '00:00');
  });

  group('free pass counts as Pro for background checks', () {
    Future<SharedPreferences> prefsWithStart(DateTime start) async {
      SharedPreferences.setMockInitialValues({
        'rotalink_pro_free_pass_start_ms': start.millisecondsSinceEpoch,
      });
      return SharedPreferences.getInstance();
    }

    test('within 15 minutes', () async {
      final prefs = await prefsWithStart(
        DateTime.now().subtract(const Duration(minutes: 10)),
      );
      expect(ProService.cachedEntitlementActive(prefs), isTrue);
    });

    test('after 15 minutes', () async {
      final prefs = await prefsWithStart(
        DateTime.now().subtract(const Duration(minutes: 16)),
      );
      expect(ProService.cachedEntitlementActive(prefs), isFalse);
    });

    test('clock moved back before the start', () async {
      final prefs = await prefsWithStart(
        DateTime.now().add(const Duration(minutes: 10)),
      );
      expect(ProService.cachedEntitlementActive(prefs), isFalse);
    });
  });
}
