import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../constants/github_gezi_yemek_config.dart';

/// GitHub Raw — geziler.json / yemekler.json.
abstract final class GithubGeziYemekDataSource {
  static const _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';
  static const _downloadTimeout = Duration(seconds: 60);
  static const _headTimeout = Duration(seconds: 20);

  static Future<String?> fetchRemoteVersion(Uri uri) async {
    try {
      final res = await http
          .head(uri, headers: const {'User-Agent': _userAgent})
          .timeout(_headTimeout);
      if (res.statusCode != 200) {
        _log('Sürüm kontrolü başarısız: HTTP ${res.statusCode} ($uri)');
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
      _log('Sürüm kontrolü hatası: $e', st);
      return null;
    }
  }

  static Future<String?> fetchJson(Uri uri) async {
    try {
      final res = await http
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(_downloadTimeout);
      if (res.statusCode != 200) {
        _log('İndirme başarısız: HTTP ${res.statusCode} ($uri)');
        return null;
      }
      final body = res.body.trim();
      if (body.isEmpty) {
        _log('Boş yanıt: $uri');
        return null;
      }
      return body;
    } catch (e, st) {
      _log('İndirme hatası: $e', st);
      return null;
    }
  }

  static Future<String?> fetchGeziler() =>
      fetchJson(GithubGeziYemekConfig.gezilerUri);

  static Future<String?> fetchYemekler() =>
      fetchJson(GithubGeziYemekConfig.yemeklerUri);

  static Future<String?> fetchGezilerVersion() =>
      fetchRemoteVersion(GithubGeziYemekConfig.gezilerUri);

  static Future<String?> fetchYemeklerVersion() =>
      fetchRemoteVersion(GithubGeziYemekConfig.yemeklerUri);

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[GithubGeziYemekDataSource] $message');
    if (kDebugMode && st != null) debugPrint(st.toString());
  }
}
