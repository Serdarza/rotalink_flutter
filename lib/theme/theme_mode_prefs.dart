import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcının seçtiği görünüm: normal (açık) veya karanlık.
abstract final class ThemeModePrefs {
  static const _key = 'rotalink_theme_mode';

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode.value = decode(prefs.getString(_key));
  }

  static Future<void> setDark(bool enabled) =>
      setMode(enabled ? ThemeMode.dark : ThemeMode.light);

  static Future<void> setMode(ThemeMode value) async {
    final resolved = value == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    mode.value = resolved;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encode(resolved));
  }

  static ThemeMode decode(String? raw) =>
      raw == 'dark' ? ThemeMode.dark : ThemeMode.light;

  static String encode(ThemeMode value) =>
      value == ThemeMode.dark ? 'dark' : 'light';
}
