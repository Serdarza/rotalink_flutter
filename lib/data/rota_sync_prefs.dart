import 'package:shared_preferences/shared_preferences.dart';

/// Rota verisi senkronizasyonu: yerel sürüm (GitHub ETag / Last-Modified).
abstract final class RotaSyncPrefs {
  static const _kLocalVersion = 'rotalink_rota_data_version';
  static const _kLastCheckMs = 'rotalink_rota_last_version_check_ms';

  /// Günde en fazla bir kez sunucu sürümü kontrol edilir.
  static const checkInterval = Duration(days: 1);

  static Future<String?> getLocalVersion() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kLocalVersion);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  static Future<void> setLocalVersion(String version) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLocalVersion, version.trim());
  }

  /// Yerel sürüm + son kontrol zamanını sıfırlar — bir sonraki açılışta
  /// (ör. gömülü yedeğe düşüldüyse) uzak veri yeniden denenir.
  static Future<void> clearVersion() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kLocalVersion);
    await p.remove(_kLastCheckMs);
  }

  static Future<bool> isCheckDue() async {
    final p = await SharedPreferences.getInstance();
    final lastMs = p.getInt(_kLastCheckMs);
    if (lastMs == null) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return DateTime.now().difference(last) >= checkInterval;
  }

  static Future<void> markVersionCheckCompleted() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLastCheckMs, DateTime.now().millisecondsSinceEpoch);
  }
}
