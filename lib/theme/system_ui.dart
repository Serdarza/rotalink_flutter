import 'package:flutter/services.dart';

/// Android 15+ (API 35/36) edge-to-edge uyumlu sistem çubuğu stili.
///
/// `statusBarColor` / `systemNavigationBarColor` / divider **kullanılmaz** —
/// bu alanlar `Window.setStatusBarColor` vb. deprecated API'leri tetikler
/// (Play Console uyarısı). Renk arka plan widget'larından gelir.
abstract final class RotalinkSystemUi {
  /// Açılış / koyu üst bar (splash, harita AppBar).
  static const lightIcons = SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );

  /// Açık zeminli ekranlar (beyaz scaffold).
  static const darkIcons = SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );

  static Future<void> applyEdgeToEdge({
    SystemUiOverlayStyle style = lightIcons,
  }) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(style);
  }
}
