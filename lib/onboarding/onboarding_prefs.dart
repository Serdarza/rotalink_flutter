import 'package:shared_preferences/shared_preferences.dart';

/// İlk açılış turu — bir kez tamamlanınca tekrar gösterilmez.
abstract final class OnboardingPrefs {
  static const _kCompleted = 'rotalink_onboarding_completed_v1';

  static Future<bool> shouldShow() async {
    final p = await SharedPreferences.getInstance();
    return !(p.getBool(_kCompleted) ?? false);
  }

  static Future<void> markCompleted() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCompleted, true);
  }
}
