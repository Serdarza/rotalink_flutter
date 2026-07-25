import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract final class GeziYemekLocalCache {
  static const _geziFile = 'rotalink_geziler.json';
  static const _yemekFile = 'rotalink_yemekler.json';

  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  static Future<bool> hasGeziCache() async {
    try {
      final f = await _file(_geziFile);
      return await f.exists() && await f.length() > 2;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasYemekCache() async {
    try {
      final f = await _file(_yemekFile);
      return await f.exists() && await f.length() > 2;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> readGeziJson() async {
    try {
      final f = await _file(_geziFile);
      if (!await f.exists()) return null;
      final t = await f.readAsString();
      return t.trim().isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> readYemekJson() async {
    try {
      final f = await _file(_yemekFile);
      if (!await f.exists()) return null;
      final t = await f.readAsString();
      return t.trim().isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeGeziJson(String json) async {
    final f = await _file(_geziFile);
    await f.parent.create(recursive: true);
    await f.writeAsString(json, flush: true);
  }

  static Future<void> writeYemekJson(String json) async {
    final f = await _file(_yemekFile);
    await f.parent.create(recursive: true);
    await f.writeAsString(json, flush: true);
  }
}
