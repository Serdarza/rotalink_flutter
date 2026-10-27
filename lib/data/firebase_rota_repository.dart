import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute, debugPrint, kDebugMode;

import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../models/sosyal_item.dart';
import '../services/network_service.dart';
import 'github_rota_data_source.dart';
import 'rota_bundled_data.dart';
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
  Future<void>? _readyInFlight;
  final _stateUpdates = StreamController<RotaDataState>.broadcast();

  /// Splash sonrası bellekte hazır veri (StreamBuilder [initialData] için).
  RotaDataState? get currentState => _memoryState;

  /// Önce yerel önbellek veya uygulamayla gelen veri; GitHub arka planda yenilenir.
  /// En fazla günde bir sürüm kontrolü yapılır (değiştiyse yeniden indirilir).
  /// Aynı anda birden fazla çağrı tek yüklemeyi paylaşır (açılış hızı).
  Future<void> ensureLocalDataReady() async {
    if (_memoryState != null && _memoryState!.initialLoadCompleted) {
      return;
    }
    final inFlight = _readyInFlight;
    if (inFlight != null) return inFlight;

    final done = Completer<void>();
    _readyInFlight = done.future;
    try {
      await _ensureLocalDataReadyBody();
      if (!done.isCompleted) done.complete();
    } catch (e, st) {
      _log('ensureLocalDataReady: $e', st);
      if (!done.isCompleted) done.complete();
    } finally {
      _readyInFlight = null;
    }
  }

  Future<void> _ensureLocalDataReadyBody() async {
    if (await RotaLocalCache.hasCache()) {
      await _loadFromLocalCache();
      // Gömülü yedekten yüklendiyse (geçersiz önbellek) uzak veriyi hemen dene.
      if (_loadedFromBundled) {
        unawaited(_downloadAndPersistRoot());
      } else {
        unawaited(_maybeSyncIfRemoteVersionChanged());
      }
      return;
    }
    // İlk kurulumda da hazır içerik göster; yavaş/yanıtsız ağ açılışı bekletmesin.
    await _loadFromBundled();
    if (_memoryState?.aramaIcinTumTesisler.isNotEmpty ?? false) {
      unawaited(_downloadAndPersistRoot());
    } else {
      // Gömülü veri de kullanılamıyorsa mevcut uzak veri kurtarma yolunu koru.
      await _downloadAndPersistRoot();
    }
  }

  Future<void> primeRootSnapshot() => ensureLocalDataReady();

  /// Paylaşılan broadcast akış — harita, Rota ve rota planı aynı anda dinleyebilir.
  Stream<RotaDataState> watchRoot() {
    return _watchRootStream ??= Stream<RotaDataState>.multi((controller) {
      RotaDataState? lastState;
      void publish(RotaDataState state) {
        if (identical(lastState, state)) return;
        lastState = state;
        controller.add(state);
      }

      final subscription = _stateUpdates.stream.listen(publish);
      controller.onCancel = subscription.cancel;
      unawaited(
        _resolveState().then(
          (state) => publish(_memoryState ?? state),
          onError: controller.addError,
        ),
      );
    }, isBroadcast: true);
  }

  Future<RotaDataState> _resolveState() async {
    await ensureLocalDataReady();
    return _memoryState ?? const RotaDataState(initialLoadCompleted: true);
  }

  /// Yerel önbellekteki JSON geçerli değilse true (gömülü yedeğe düşüldü).
  bool _loadedFromBundled = false;

  Future<RotaDataState> _loadFromLocalCache() async {
    try {
      final raw = await RotaLocalCache.readJson();
      if (raw == null) {
        return _loadFromBundled();
      }
      // Tek parse; bozuk/eksik önbellekte (ör. geçmişte inen hatalı JSON)
      // istisna → gömülü yedeğe düş, arama boş kalmasın.
      final parsed = await compute(_parseRootState, raw);
      if (parsed == null) {
        _log('Yerel önbellek geçersiz/boş; gömülü yedeğe düşülüyor.');
        return _loadFromBundled();
      }
      _loadedFromBundled = false;
      final state = parsed.copyWith(loadedFromLocalCache: true);
      return _memoryState = state;
    } catch (err, st) {
      _log('Yerel önbellek okunamadı: $err', st);
      return _loadFromBundled();
    }
  }

  static bool _hasUsableTesis(dynamic decoded) {
    if (decoded is! Map) return false;
    final tesis = decoded['tesisler'] ?? decoded['misafirhaneler'];
    return tesis is List && tesis.isNotEmpty;
  }

  /// Büyük JSON çözümleme ve model dönüşümü mobilde arayüzü durdurmasın.
  static RotaDataState? _parseRootState(String raw) {
    final decoded = jsonDecode(raw);
    if (!_hasUsableTesis(decoded)) return null;
    return _mapSnapshotToState(decoded);
  }

  /// Önbellek yoksa uygulamayla gelen hazır veritabanını yükler.
  Future<RotaDataState> _loadFromBundled() async {
    try {
      final raw = await RotaBundledData.load();
      if (raw == null) {
        _log('Gömülü yedek veritabanı yok.');
        return _memoryState = const RotaDataState(initialLoadCompleted: true);
      }
      final parsed = await compute(_parseRootState, raw);
      if (parsed == null) {
        _log('Gömülü yedek geçersiz.');
        return _memoryState = const RotaDataState(initialLoadCompleted: true);
      }
      _loadedFromBundled = true;
      _log('Gömülü yedek veritabanı yüklendi.');
      final state = parsed.copyWith(loadedFromLocalCache: true);
      return _memoryState = state;
    } catch (err, st) {
      _log('Gömülü yedek okunamadı: $err', st);
      return _memoryState = const RotaDataState(initialLoadCompleted: true);
    }
  }

  /// En fazla günde bir: hafif HEAD ile sürüm bak; sadece değiştiyse JSON indir.
  Future<void> _maybeSyncIfRemoteVersionChanged() async {
    if (!await NetworkService.instance.isConnected()) return;
    if (!await RotaSyncPrefs.isCheckDue()) return;

    await RotaSyncPrefs.markVersionCheckCompleted();

    final remoteVersion = await GithubRotaDataSource.fetchRemoteVersion();
    if (remoteVersion == null) return;

    final localVersion = await RotaSyncPrefs.getLocalVersion();
    if (localVersion == remoteVersion) {
      _log('GitHub veritabanı güncel (sürüm aynı); indirme yok.');
      return;
    }

    _log(
      'GitHub veritabanı güncellendi (yerel: $localVersion → uzak: $remoteVersion); indiriliyor.',
    );
    await _downloadAndPersistRoot(expectedVersion: remoteVersion);
  }

  /// Uzak veriyi indirip önbelleğe yazar. Başarılıysa true.
  Future<bool> _downloadAndPersistRoot({String? expectedVersion}) async {
    try {
      if (!await NetworkService.instance.isConnected()) {
        _log('İnternet yok; GitHub veritabanı indirilemedi.');
        return false;
      }

      final json = await GithubRotaDataSource.fetchMasterDatabaseFromGitHub();
      if (json == null) {
        _log('GitHub veritabanı boş veya ulaşılamadı.');
        return false;
      }

      final state = await compute(_parseRootState, json);
      if (state == null) return false;
      await RotaLocalCache.writeJson(json);
      _loadedFromBundled = false;
      _memoryState = state;
      _stateUpdates.add(state);

      final version =
          expectedVersion ?? await GithubRotaDataSource.fetchRemoteVersion();
      if (version != null) {
        await RotaSyncPrefs.setLocalVersion(version);
      }
      return true;
    } catch (e, st) {
      _log('Veritabanı işleme hatası: $e', st);
      return false;
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

  static RotaDataState _mapSnapshotToState(dynamic root) {
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

  static List<SosyalItem> _parseSosyalList(dynamic v) {
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

  static List<GeziYemekItem> _parseGeziYemekList(dynamic v) {
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

  static List<Misafirhane> _distinctByStableFacilityIdPreferCoords(
    List<Misafirhane> full,
  ) {
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

  static List<Misafirhane> _distinctByIlPreferCoords(List<Misafirhane> full) {
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

  static List<Misafirhane> _loadTesisFull(Map<String, dynamic> m) {
    final primary = _parseMisafirhaneList(m[pathTesisler]);
    if (primary.isNotEmpty) return primary;
    return _parseMisafirhaneList(m[pathTesislerLegacy]);
  }

  static List<Misafirhane> _parseMisafirhaneList(dynamic v) {
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
