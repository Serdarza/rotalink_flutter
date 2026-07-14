import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/github_ad_config.dart';
import '../models/ad_config_policy.dart';

/// GitHub Raw üzerinden reklam_ayar.json okuma ve yerel önbellek.
abstract final class GithubAdConfigDataSource {
  static const _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';
  static const _timeout = Duration(seconds: 15);
  static const _cacheKey = 'rotalink_ad_config_json';

  static Future<AdConfigPolicy?> fetchPolicy({bool allowCache = true}) async {
    try {
      final res = await http
          .get(
            GithubAdConfig.uri,
            headers: const {'User-Agent': _userAgent},
          )
          .timeout(_timeout);

      if (res.statusCode != 200) {
        _log('reklam_ayar.json indirilemedi: HTTP ${res.statusCode}');
        return allowCache ? _readCachedPolicy() : null;
      }

      final body = res.body.trim();
      if (body.isEmpty) return allowCache ? _readCachedPolicy() : null;

      final decoded = jsonDecode(body);
      if (decoded is! Map) return allowCache ? _readCachedPolicy() : null;

      final policy = AdConfigPolicy.fromJson(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
      await _writeCache(body);
      return policy;
    } catch (e, st) {
      _log('reklam_ayar.json okunamadı: $e', st);
      return allowCache ? _readCachedPolicy() : null;
    }
  }

  static Future<AdConfigPolicy?> _readCachedPolicy() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_cacheKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AdConfigPolicy.fromJson(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_cacheKey, json);
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[GithubAdConfigDataSource] $message');
    if (kDebugMode && st != null) {
      debugPrint(st.toString());
    }
  }
}
