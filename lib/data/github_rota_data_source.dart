import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../constants/github_rota_config.dart';

/// GitHub / CDN üzerinden master_database_updated.json indirme ve sürüm kontrolü.
abstract final class GithubRotaDataSource {
  static const _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';
  static const _downloadTimeout = Duration(seconds: 90);
  static const _headTimeout = Duration(seconds: 20);

  /// Birincil + yedek kaynaklar (CDN gecikmesi / bozuk cache’e karşı).
  static List<Uri> get _downloadUris => [
        GithubRotaConfig.databaseUri,
        Uri.parse(GithubRotaConfig.jsDelivrDatabaseUrl),
        Uri.parse(GithubRotaConfig.rawDatabaseUrlAlt),
      ];

  /// Haftalık güncelleme kontrolü — HEAD isteği, JSON gövdesi indirilmez.
  static Future<String?> fetchRemoteVersion() async {
    for (final uri in _downloadUris) {
      try {
        final res = await http
            .head(uri, headers: const {'User-Agent': _userAgent})
            .timeout(_headTimeout);
        if (res.statusCode != 200) continue;

        final etag = res.headers['etag']?.trim();
        if (etag != null && etag.isNotEmpty) return etag;

        final lastMod = res.headers['last-modified']?.trim();
        final length = res.headers['content-length']?.trim();
        if (lastMod != null && lastMod.isNotEmpty) {
          return length != null ? '$lastMod|$length' : lastMod;
        }
        if (length != null && length.isNotEmpty) return length;
      } catch (e, st) {
        _log('Sürüm kontrolü hata ($uri): $e', st);
      }
    }
    _log('GitHub sürüm kontrolü başarısız (tüm kaynaklar).');
    return null;
  }

  /// Master JSON indirir; parse edilemeyen / yorum satırlı gövdeyi reddeder.
  static Future<String?> fetchMasterDatabaseFromGitHub() async {
    for (final uri in _downloadUris) {
      try {
        final res = await http
            .get(uri, headers: const {'User-Agent': _userAgent})
            .timeout(_downloadTimeout);

        if (res.statusCode != 200) {
          _log('İndirme HTTP ${res.statusCode}: $uri');
          continue;
        }

        final body = res.body.trim();
        if (body.isEmpty) {
          _log('Boş yanıt: $uri');
          continue;
        }
        if (!looksLikeValidMasterJson(body)) {
          _log('Geçersiz / bozuk JSON reddedildi: $uri');
          continue;
        }
        _log('Master indirildi: $uri (${body.length} char)');
        return body;
      } catch (e, st) {
        _log('İndirme hatası ($uri): $e', st);
      }
    }
    _log('GitHub veritabanı hiçbir kaynaktan alınamadı.');
    return null;
  }

  /// Üretimde sessiz boş liste yerine bozuk dosyayı erken yakala.
  static bool looksLikeValidMasterJson(String body) {
    // JSON standartında // yorum yok — geçmişte production’ı kırdı.
    if (RegExp(r'^\s*//', multiLine: true).hasMatch(body)) {
      return false;
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return false;
      final tesis = decoded['tesisler'] ?? decoded['misafirhaneler'];
      if (tesis is! List || tesis.isEmpty) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[GithubRotaDataSource] $message');
    if (kDebugMode && st != null) {
      debugPrint(st.toString());
    }
  }
}
