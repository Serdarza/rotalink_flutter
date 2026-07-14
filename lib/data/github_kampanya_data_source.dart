import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../constants/github_kampanya_config.dart';

/// GitHub Raw üzerinden kampanya.json indirme ve sürüm kontrolü.
abstract final class GithubKampanyaDataSource {
  static const _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';
  static const _downloadTimeout = Duration(seconds: 60);
  static const _headTimeout = Duration(seconds: 20);

  static Uri get _uri => GithubKampanyaConfig.databaseUri;

  static Future<String?> fetchRemoteVersion() async {
    try {
      final res = await http
          .head(_uri, headers: const {'User-Agent': _userAgent})
          .timeout(_headTimeout);
      if (res.statusCode != 200) {
        _log('GitHub kampanya sürüm kontrolü başarısız: HTTP ${res.statusCode}');
        return null;
      }

      final etag = res.headers['etag']?.trim();
      if (etag != null && etag.isNotEmpty) return etag;

      final lastMod = res.headers['last-modified']?.trim();
      final length = res.headers['content-length']?.trim();
      if (lastMod != null && lastMod.isNotEmpty) {
        return length != null ? '$lastMod|$length' : lastMod;
      }
      return length;
    } catch (e, st) {
      _log('GitHub kampanya sürüm kontrolü hatası: $e', st);
      return null;
    }
  }

  static Future<String?> fetchKampanyalarFromGitHub() async {
    try {
      final res = await http
          .get(_uri, headers: const {'User-Agent': _userAgent})
          .timeout(_downloadTimeout);

      if (res.statusCode != 200) {
        _log(
          'GitHub kampanya indirilemedi: HTTP ${res.statusCode} '
          '(${GithubKampanyaConfig.rawDatabaseUrl})',
        );
        return null;
      }

      final body = res.body.trim();
      if (body.isEmpty) {
        _log('GitHub kampanya yanıtı boş.');
        return null;
      }
      return body;
    } catch (e, st) {
      _log('GitHub kampanya indirme hatası: $e', st);
      return null;
    }
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[GithubKampanyaDataSource] $message');
    if (kDebugMode && st != null) {
      debugPrint(st.toString());
    }
  }
}
