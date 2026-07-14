import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// RTDB kök anlık görüntüsü — ağ olmadan harita verisi için yerel dosya önbelleği.
abstract final class RotaLocalCache {
  static const _fileName = 'rotalink_rota_root.json';

  static Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<bool> hasCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return false;
      return await file.length() > 2;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> readJson() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeJson(String json) async {
    final file = await _cacheFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(json, flush: true);
  }

  static Future<void> clear() async {
    try {
      final file = await _cacheFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
