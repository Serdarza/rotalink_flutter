import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama puanlama ve çıkış akışı için [SharedPreferences] anahtarları.
abstract final class AppRatingPrefs {
  static const _kHasRated = 'rotalink_has_rated_app';
  static const _kRateDeferred = 'rotalink_rate_deferred';
  static const _kLaunchCount = 'rotalink_app_launch_count';

  static Future<int> getLaunchCount() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kLaunchCount) ?? 0;
  }

  static Future<void> incrementLaunchCount() async {
    final p = await SharedPreferences.getInstance();
    final n = (p.getInt(_kLaunchCount) ?? 0) + 1;
    await p.setInt(_kLaunchCount, n);
  }

  static Future<bool> getHasRated() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kHasRated) ?? false;
  }

  static Future<bool> getRateDeferred() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kRateDeferred) ?? false;
  }

  static Future<void> setRated() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHasRated, true);
    await p.setBool(_kRateDeferred, false);
  }

  static Future<void> setDeferred() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kRateDeferred, true);
  }

  /// Çıkış öncesi puanlama diyaloğu gösterilmeli mi?
  static Future<bool> shouldPromptRatingBeforeExit() async {
    if (await getHasRated()) return false;
    final deferred = await getRateDeferred();
    if (!deferred) return true;
    final n = await getLaunchCount();
    return n % 5 == 0;
  }
}
