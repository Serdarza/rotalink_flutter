import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/facility_price_entry.dart';
import '../models/misafirhane.dart';
import '../services/network_service.dart';
import 'fiyat_local_cache.dart';
import 'fiyat_sync_prefs.dart';
import 'github_fiyat_data_source.dart';

/// `fiyatlar.json` — tesislerle [il]+[isim] (normalize) üzerinden eşleşir.
class FacilityPriceRepository {
  FacilityPriceRepository._();

  static final FacilityPriceRepository instance = FacilityPriceRepository._();

  factory FacilityPriceRepository() => instance;

  /// matchKey → kayıt
  Map<String, FacilityPriceEntry> _byKey = const {};

  String? _note;

  String? get note => _note;

  int get count => _byKey.length;

  bool get isReady => _byKey.isNotEmpty || _loadedEmpty;

  bool _loadedEmpty = false;

  /// Açılışta: önbellek + en fazla günde bir sürüm kontrolü (değiştiyse indir).
  Future<void> ensureLocalDataReady() async {
    if (await FiyatLocalCache.hasCache()) {
      await _loadFromLocalCache();
      unawaited(_maybeSyncIfRemoteVersionChanged());
      return;
    }
    if (!await NetworkService.instance.isConnected()) return;
    await _downloadAndPersist();
  }

  FacilityPriceEntry? lookup(String il, String isim) {
    final key = FacilityPriceEntry.matchKey(il, isim);
    return _byKey[key];
  }

  /// Kart gösterimi: fiyatlar.json varsa onu kullan; yoksa tesis gömülü fiyat / yok.
  Misafirhane resolveFacility(Misafirhane m) {
    final entry = lookup(m.il, m.isim);
    if (entry == null) {
      // Ayrı dosyada yok → kartta "ücret kayıtlı değil" (tesis JSON fiyatına güvenme)
      return m.copyWithoutPrices();
    }
    return m.copyWithPriceEntry(entry);
  }

  Future<void> _maybeSyncIfRemoteVersionChanged() async {
    if (!await NetworkService.instance.isConnected()) return;
    if (!await FiyatSyncPrefs.isCheckDue()) return;
    await FiyatSyncPrefs.markVersionCheckCompleted();

    final remoteVersion = await GithubFiyatDataSource.fetchRemoteVersion();
    if (remoteVersion == null) return;

    final localVersion = await FiyatSyncPrefs.getLocalVersion();
    if (localVersion == remoteVersion) {
      _log('Fiyatlar güncel (sürüm aynı); indirme yok.');
      return;
    }

    _log('Fiyatlar güncellendi; indiriliyor.');
    await _downloadAndPersist(expectedVersion: remoteVersion);
  }

  Future<void> _loadFromLocalCache() async {
    try {
      final raw = await FiyatLocalCache.readJson();
      if (raw == null) {
        _byKey = const {};
        _loadedEmpty = true;
        return;
      }
      _applyDecoded(jsonDecode(raw));
    } catch (e, st) {
      _log('Yerel fiyat önbelleği okunamadı: $e', st);
      _byKey = const {};
      _loadedEmpty = true;
    }
  }

  Future<void> _downloadAndPersist({String? expectedVersion}) async {
    try {
      if (!await NetworkService.instance.isConnected()) {
        _log('İnternet yok; fiyatlar indirilemedi.');
        return;
      }

      final json = await GithubFiyatDataSource.fetchFiyatlarFromGitHub();
      if (json == null) {
        _log('GitHub fiyatlar boş veya ulaşılamadı.');
        return;
      }

      final decoded = jsonDecode(json);
      await FiyatLocalCache.writeJson(json);
      _applyDecoded(decoded);

      final version =
          expectedVersion ?? await GithubFiyatDataSource.fetchRemoteVersion();
      if (version != null) {
        await FiyatSyncPrefs.setLocalVersion(version);
      }
    } catch (e, st) {
      _log('Fiyat işleme hatası: $e', st);
    }
  }

  void _applyDecoded(dynamic root) {
    final map = <String, FacilityPriceEntry>{};
    String? note;

    if (root is Map) {
      final m = root.map((k, v) => MapEntry(k.toString(), v));
      final n = m['not'] ?? m['note'] ?? m['aciklama'];
      if (n != null) {
        final s = n.toString().trim();
        if (s.isNotEmpty) note = s;
      }
      final list = m['tesisler'] ?? m['fiyatlar'] ?? m['items'];
      if (list is List) {
        for (final item in list) {
          final e = FacilityPriceEntry.tryParse(item);
          if (e == null || !e.hasFiyatBilgisi) continue;
          map[e.key] = e;
        }
      }
    } else if (root is List) {
      for (final item in root) {
        final e = FacilityPriceEntry.tryParse(item);
        if (e == null || !e.hasFiyatBilgisi) continue;
        map[e.key] = e;
      }
    }

    _note = note;
    _byKey = map;
    _loadedEmpty = map.isEmpty;
    _log('Fiyat kaydı yüklendi: ${map.length} tesis');
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[FacilityPriceRepository] $message');
    if (kDebugMode && st != null) {
      debugPrint(st.toString());
    }
  }
}
