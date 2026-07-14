import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../models/sosyal_item.dart';
import '../services/network_service.dart';
import 'github_rota_data_source.dart';
import 'rota_local_cache.dart';
import 'rota_sync_prefs.dart';

class RotaDataState {
  const RotaDataState({
    this.misafirhaneler = const [],
    this.aramaIcinTumTesisler = const [],
    this.gezi = const [],
    this.yemek = const [],
    this.sosyal = const [],
    this.initialLoadCompleted = false,
    this.errorMessage,
    this.loadedFromLocalCache = false,
  });

  final List<Misafirhane> misafirhaneler;
  final List<Misafirhane> aramaIcinTumTesisler;
  final List<GeziYemekItem> gezi;
  final List<GeziYemekItem> yemek;
  final List<SosyalItem> sosyal;
  final bool initialLoadCompleted;
  final String? errorMessage;

  /// Veri yerel dosyadan yüklendiyse true.
  final bool loadedFromLocalCache;
}

/// Rota verisi GitHub'daki [master_database_updated.json] dosyasından okunur.
class FirebaseRotaRepository {
  FirebaseRotaRepository();

  RotaDataState? _memoryState;
  Stream<RotaDataState>? _watchRootStream;

  /// Splash sonrası bellekte hazır veri (StreamBuilder [initialData] için).
  RotaDataState? get currentState => _memoryState;

  /// İlk kurulumda GitHub'dan indirir; sonraki açılışlarda yerel önbellek + günlük kontrol.
  Future<void> ensureLocalDataReady() async {
    if (await RotaLocalCache.hasCache()) {
      await _loadFromLocalCache();
      await _maybeSyncIfRemoteVersionChanged();
      _watchRootStream = null;
      return;
    }
    if (!await NetworkService.instance.isConnected()) return;
    await _downloadAndPersistRoot();
    _watchRootStream = null;
  }

  Future<void> primeRootSnapshot() => ensureLocalDataReady();

  /// Paylaşılan broadcast akış — harita, KAMİ ve rota planı aynı anda dinleyebilir.
  Stream<RotaDataState> watchRoot() {
    return _watchRootStream ??=
        Stream.fromFuture(_resolveState()).asBroadcastStream();
  }

  Future<RotaDataState> _resolveState() async {
    if (_memoryState != null) return _memoryState!;
    if (await RotaLocalCache.hasCache()) {
      return _loadFromLocalCache();
    }
    if (!await NetworkService.instance.isConnected()) {
      return _memoryState = const RotaDataState(initialLoadCompleted: true);
    }
    await _downloadAndPersistRoot();
    return _memoryState ?? const RotaDataState(initialLoadCompleted: true);
  }

  Future<RotaDataState> _loadFromLocalCache() async {
    try {
      final raw = await RotaLocalCache.readJson();
      if (raw == null) {
        return _memoryState = const RotaDataState(initialLoadCompleted: true);
      }
      final decoded = jsonDecode(raw);
      final state = _mapSnapshotToState(decoded).copyWith(
        loadedFromLocalCache: true,
      );
      return _memoryState = state;
    } catch (err, st) {
      _log('Yerel önbellek okunamadı: $err', st);
      return _memoryState = RotaDataState(
        initialLoadCompleted: true,
        errorMessage: kDebugMode ? err.toString() : 'Yerel veri okunamadı.',
      );
    }
  }

  /// Günde bir: HEAD isteği ile sürüm kontrolü; değiştiyse tam JSON indirme.
  Future<void> _maybeSyncIfRemoteVersionChanged() async {
    if (!await NetworkService.instance.isConnected()) return;
    if (!await RotaSyncPrefs.isCheckDue()) return;

    await RotaSyncPrefs.markVersionCheckCompleted();

    final remoteVersion = await GithubRotaDataSource.fetchRemoteVersion();
    if (remoteVersion == null) return;

    final localVersion = await RotaSyncPrefs.getLocalVersion();
    if (localVersion == remoteVersion) return;

    if (localVersion == null) {
      await RotaSyncPrefs.setLocalVersion(remoteVersion);
      return;
    }

    await _downloadAndPersistRoot(expectedVersion: remoteVersion);
  }

  Future<void> _downloadAndPersistRoot({String? expectedVersion}) async {
    try {
      if (!await NetworkService.instance.isConnected()) {
        _log('İnternet yok; GitHub veritabanı indirilemedi.');
        return;
      }

      final json = await GithubRotaDataSource.fetchMasterDatabaseFromGitHub();
      if (json == null) {
        _log('GitHub veritabanı boş veya ulaşılamadı.');
        return;
      }

      final decoded = jsonDecode(json);
      await RotaLocalCache.writeJson(json);
      _memoryState = _mapSnapshotToState(decoded);
      _watchRootStream = null;

      final version =
          expectedVersion ?? await GithubRotaDataSource.fetchRemoteVersion();
      if (version != null) {
        await RotaSyncPrefs.setLocalVersion(version);
      }
    } catch (e, st) {
      _log('Veritabanı işleme hatası: $e', st);
    }
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[FirebaseRotaRepository] $message');
    if (kDebugMode && st != null) {
      debugPrint(st.toString());
    }
  }

  static const String pathTesisler = 'tesisler';
  static const String pathTesislerLegacy = 'misafirhaneler';
  static const String pathGeziler = 'geziler';
  static const String pathYemekler = 'yemekler';
  static const String pathSosyal = 'sosyal';

  RotaDataState _mapSnapshotToState(dynamic root) {
    if (root is! Map) {
      return const RotaDataState(initialLoadCompleted: true);
    }
    final m = root.map((k, v) => MapEntry(k.toString(), v));
    final tesisFull = _loadTesisFull(m);
    final deduplicated = _distinctByStableFacilityIdPreferCoords(tesisFull);
    final gezi = _parseGeziYemekList(m[pathGeziler]);
    final yemek = _parseGeziYemekList(m[pathYemekler]);
    final sosyal = _parseSosyalList(m[pathSosyal]);
    return RotaDataState(
      misafirhaneler: _distinctByIlPreferCoords(deduplicated),
      aramaIcinTumTesisler: deduplicated,
      gezi: gezi,
      yemek: yemek,
      sosyal: sosyal,
      initialLoadCompleted: true,
    );
  }

  List<SosyalItem> _parseSosyalList(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v.map(SosyalItem.tryParse).whereType<SosyalItem>().toList();
    }
    if (v is Map) {
      final entries = v.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key.toString()) ?? 1 << 30;
          final ib = int.tryParse(b.key.toString()) ?? 1 << 30;
          return ia.compareTo(ib);
        });
      return entries
          .map((e) => SosyalItem.tryParse(e.value))
          .whereType<SosyalItem>()
          .toList();
    }
    return [];
  }

  List<GeziYemekItem> _parseGeziYemekList(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v.map(GeziYemekItem.tryParse).whereType<GeziYemekItem>().toList();
    }
    if (v is Map) {
      final entries = v.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key.toString()) ?? 1 << 30;
          final ib = int.tryParse(b.key.toString()) ?? 1 << 30;
          return ia.compareTo(ib);
        });
      return entries
          .map((e) => GeziYemekItem.tryParse(e.value))
          .whereType<GeziYemekItem>()
          .toList();
    }
    return [];
  }

  List<Misafirhane> _distinctByStableFacilityIdPreferCoords(List<Misafirhane> full) {
    final seen = <String, Misafirhane>{};
    for (final t in full) {
      final k = t.stableFacilityId;
      final ex = seen[k];
      if (ex == null) {
        seen[k] = t;
        continue;
      }
      final exBad = ex.latitude == 0 || ex.longitude == 0;
      final tGood = t.latitude != 0 && t.longitude != 0;
      if (exBad && tGood) seen[k] = t;
    }
    return seen.values.toList();
  }

  List<Misafirhane> _distinctByIlPreferCoords(List<Misafirhane> full) {
    final byIl = <String, Misafirhane>{};
    for (final t in full) {
      final k = t.il.trim();
      if (k.isEmpty) continue;
      final ex = byIl[k];
      if (ex == null) {
        byIl[k] = t;
        continue;
      }
      final exBad = ex.latitude == 0 || ex.longitude == 0;
      final tGood = t.latitude != 0 && t.longitude != 0;
      if (exBad && tGood) {
        byIl[k] = t;
      }
    }
    return byIl.values.toList();
  }

  List<Misafirhane> _loadTesisFull(Map<String, dynamic> m) {
    final primary = _parseMisafirhaneList(m[pathTesisler]);
    if (primary.isNotEmpty) return primary;
    return _parseMisafirhaneList(m[pathTesislerLegacy]);
  }

  List<Misafirhane> _parseMisafirhaneList(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v.map(Misafirhane.tryParse).whereType<Misafirhane>().toList();
    }
    if (v is Map) {
      final entries = v.entries.toList()
        ..sort((a, b) {
          final ia = int.tryParse(a.key.toString()) ?? 1 << 30;
          final ib = int.tryParse(b.key.toString()) ?? 1 << 30;
          return ia.compareTo(ib);
        });
      return entries
          .map((e) => Misafirhane.tryParse(e.value))
          .whereType<Misafirhane>()
          .toList();
    }
    return [];
  }
}

extension on RotaDataState {
  RotaDataState copyWith({bool? loadedFromLocalCache}) {
    return RotaDataState(
      misafirhaneler: misafirhaneler,
      aramaIcinTumTesisler: aramaIcinTumTesisler,
      gezi: gezi,
      yemek: yemek,
      sosyal: sosyal,
      initialLoadCompleted: initialLoadCompleted,
      errorMessage: errorMessage,
      loadedFromLocalCache: loadedFromLocalCache ?? this.loadedFromLocalCache,
    );
  }
}
