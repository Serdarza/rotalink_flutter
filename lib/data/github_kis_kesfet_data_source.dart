import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../constants/github_kis_kesfet_config.dart';
import '../utils/text_encoding.dart';

/// GitHub Raw üzerinden Kış Keşfet JSON indirme.
abstract final class GithubKisKesfetDataSource {
  static const _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';
  static const _downloadTimeout = Duration(seconds: 20);

  static Future<String?> fetch() async {
    try {
      final res = await http
          .get(
            GithubKisKesfetConfig.uri,
            headers: const {'User-Agent': _userAgent},
          )
          .timeout(_downloadTimeout);
      if (res.statusCode != 200) {
        _log('Kış Keşfet indirilemedi: HTTP ${res.statusCode}');
        return null;
      }
      final body = responseText(res).trim();
      if (body.isEmpty) {
        _log('Kış Keşfet yanıtı boş.');
        return null;
      }
      return body;
    } catch (e, st) {
      _log('Kış Keşfet indirme hatası: $e', st);
      return null;
    }
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[GithubKisKesfetDataSource] $message');
    if (kDebugMode && st != null) {
      debugPrint(st.toString());
    }
  }
}
