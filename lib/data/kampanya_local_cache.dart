import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Keşfet kampanyaları — yerel JSON önbelleği.
abstract final class KampanyaLocalCache {
  static const _fileName = 'rotalink_kampanyalar.json';

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
}
