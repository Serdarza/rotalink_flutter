import 'package:shared_preferences/shared_preferences.dart';

abstract final class GeziYemekSyncPrefs {
  static const _kGeziVersion = 'rotalink_geziler_data_version';
  static const _kYemekVersion = 'rotalink_yemekler_data_version';

  static Future<String?> getGeziVersion() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kGeziVersion);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  static Future<void> setGeziVersion(String version) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kGeziVersion, version.trim());
  }

  static Future<String?> getYemekVersion() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kYemekVersion);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  static Future<void> setYemekVersion(String version) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kYemekVersion, version.trim());
  }
}
