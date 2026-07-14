import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/github_app_version_config.dart';
import '../models/app_version_policy.dart';

/// GitHub Raw üzerinden app_version.json okuma ve yerel önbellek.
abstract final class GithubAppVersionDataSource {
  static const _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';
  static const _timeout = Duration(seconds: 15);
  static const _cacheKey = 'rotalink_app_version_policy_json';
  static const _cacheAtKey = 'rotalink_app_version_policy_cached_at_ms';

  /// Açılışta taze veri; başarısız olursa önbellek.
  static Future<AppVersionPolicy?> fetchPolicy({bool allowCache = true}) async {
    try {
      final res = await http
          .get(
            GithubAppVersionConfig.uri,
            headers: const {'User-Agent': _userAgent},
          )
          .timeout(_timeout);

      if (res.statusCode != 200) {
        _log('app_version.json indirilemedi: HTTP ${res.statusCode}');
        return allowCache ? _readCachedPolicy() : null;
      }

      final body = res.body.trim();
      if (body.isEmpty) return allowCache ? _readCachedPolicy() : null;

      final decoded = jsonDecode(body);
      if (decoded is! Map) return allowCache ? _readCachedPolicy() : null;

      final map = decoded.map((k, v) => MapEntry(k.toString(), v));
      final policy = AppVersionPolicy.fromJson(map);
      await _writeCache(body);
      return policy;
    } catch (e, st) {
      _log('app_version.json okunamadı: $e', st);
      return allowCache ? _readCachedPolicy() : null;
    }
  }

  static Future<AppVersionPolicy?> _readCachedPolicy() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_cacheKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AppVersionPolicy.fromJson(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_cacheKey, json);
    await p.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[GithubAppVersionDataSource] $message');
    if (kDebugMode && st != null) {
      debugPrint(st.toString());
    }
  }
}
