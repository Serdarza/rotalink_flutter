import 'package:shared_preferences/shared_preferences.dart';

/// Pro destek soft banner — günde en fazla bir kez.
abstract final class ProSupportBannerPrefs {
  static const _kLastShownDay = 'rotalink_pro_support_banner_day';

  static String _todayKey() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  static Future<bool> wasShownToday() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastShownDay) == _todayKey();
  }

  static Future<void> markShownToday() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastShownDay, _todayKey());
  }
}
