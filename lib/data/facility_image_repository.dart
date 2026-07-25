import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/misafirhane.dart';
import '../services/network_service.dart';
import '../utils/search_normalize.dart';
import 'github_tesis_gorsel_data_source.dart';
import 'tesis_gorsel_local_cache.dart';
import 'tesis_gorsel_sync_prefs.dart';

/// `tesisler_gorseller.json` — tesislerle [il]+[isim] üzerinden eşleşir.
class FacilityImageRepository {
  FacilityImageRepository._();

  static final FacilityImageRepository instance = FacilityImageRepository._();

  /// matchKey → en fazla 3 URL
  Map<String, List<String>> _byKey = const {};

  int get count => _byKey.length;

  static String matchKey(String il, String isim) =>
      '${normalizeForSearch(il)}\u0001${normalizeForSearch(isim)}';

  Future<void> ensureLocalDataReady() async {
    if (await TesisGorselLocalCache.hasCache()) {
      await _loadFromLocalCache();
      unawaited(_maybeSyncIfRemoteVersionChanged());
      return;
    }
    if (!await NetworkService.instance.isConnected()) return;
    await _downloadAndPersist();
  }

  List<String> lookup(String il, String isim) {
    return _byKey[matchKey(il, isim)] ?? const [];
  }

  Misafirhane resolveFacility(Misafirhane m) {
    final urls = lookup(m.il, m.isim);
    if (urls.isEmpty) return m;
    return m.copyWithImageUrls(urls);
  }

  Future<void> _maybeSyncIfRemoteVersionChanged() async {
    if (!await NetworkService.instance.isConnected()) return;
    if (!await TesisGorselSyncPrefs.isCheckDue()) return;
    await TesisGorselSyncPrefs.markVersionCheckCompleted();

    final remoteVersion =
        await GithubTesisGorselDataSource.fetchRemoteVersion();
    if (remoteVersion == null) return;

    final localVersion = await TesisGorselSyncPrefs.getLocalVersion();
    if (localVersion == remoteVersion) {
      _log('Tesis görselleri güncel (sürüm aynı); indirme yok.');
      return;
    }

    _log('Tesis görselleri güncellendi; indiriliyor.');
    await _downloadAndPersist(expectedVersion: remoteVersion);
  }

  Future<void> _loadFromLocalCache() async {
    try {
      final raw = await TesisGorselLocalCache.readJson();
      if (raw == null) {
        _byKey = const {};
        return;
      }
      _applyDecoded(jsonDecode(raw));
    } catch (e, st) {
      _log('Yerel tesis görsel önbelleği okunamadı: $e', st);
      _byKey = const {};
    }
  }

  Future<void> _downloadAndPersist({String? expectedVersion}) async {
    try {
      if (!await NetworkService.instance.isConnected()) {
        _log('İnternet yok; tesis görselleri indirilemedi.');
        return;
      }

      final json = await GithubTesisGorselDataSource.fetchFromGitHub();
      if (json == null) {
        _log('GitHub tesis görselleri boş veya ulaşılamadı.');
        return;
      }

      final decoded = jsonDecode(json);
      await TesisGorselLocalCache.writeJson(json);
      _applyDecoded(decoded);

      final version = expectedVersion ??
          await GithubTesisGorselDataSource.fetchRemoteVersion();
      if (version != null) {
        await TesisGorselSyncPrefs.setLocalVersion(version);
      }
    } catch (e, st) {
      _log('Tesis görsel işleme hatası: $e', st);
    }
  }

  void _applyDecoded(dynamic root) {
    final map = <String, List<String>>{};

    List? list;
    if (root is Map) {
      final m = root.map((k, v) => MapEntry(k.toString(), v));
      final raw = m['items'] ?? m['tesisler'] ?? m['gorseller'];
      if (raw is List) list = raw;
    } else if (root is List) {
      list = root;
    }

    if (list != null) {
      for (final item in list) {
        if (item is! Map) continue;
        final m = item.map((k, v) => MapEntry(k.toString(), v));
        final isim = _str(m, const ['isim', 'name', 'tesis_adi']);
        final il = _str(m, const ['il', 'sehir', 'province']);
        if (isim.isEmpty && il.isEmpty) continue;
        final urls = _parseUrls(m);
        if (urls.isEmpty) continue;
        map[matchKey(il, isim)] = urls.take(3).toList(growable: false);
      }
    }

    _byKey = map;
    _log('Tesis görseli yüklendi: ${map.length} tesis');
  }

  static String _str(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static List<String> _parseUrls(Map<String, dynamic> m) {
    final raw = m['image_urls'] ?? m['images'] ?? m['gorseller'] ?? m['urls'];
    if (raw is! List) return const [];
    final out = <String>[];
    for (final e in raw) {
      final s = e?.toString().trim() ?? '';
      if (s.startsWith('http')) out.add(s);
      if (out.length >= 3) break;
    }
    return out;
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[FacilityImageRepository] $message');
    if (kDebugMode && st != null) {
      debugPrint(st.toString());
    }
  }
}
