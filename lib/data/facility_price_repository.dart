import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kDebugMode;

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

  /// Katalog belleğe alındığında artar. Liste ve detay bunu dinler.
  final ValueNotifier<int> updates = ValueNotifier(0);

  bool get isReady => _byKey.isNotEmpty || _loadedEmpty;

  /// İndirme denendi ve katalog hâlâ yok. Bu, tesiste fiyat olmadığı anlamına gelmez.
  bool get loadFailed => _loadFailed;

  bool _loadedEmpty = false;
  bool _loadFailed = false;
  Future<void>? _readyInFlight;

  /// Açılışta: önbellek + en fazla saatte bir sürüm kontrolü (değiştiyse indir).
  /// Debug derlemede her açılışta kontrol edilir.
  Future<void> ensureLocalDataReady() => _readyInFlight ??=
      _ensureLocalDataReady().whenComplete(() => _readyInFlight = null);

  Future<void> _ensureLocalDataReady() async {
    if (isReady) return;
    if (_loadFailed) {
      _loadFailed = false;
      updates.value++;
    }
    if (await FiyatLocalCache.hasCache()) {
      final loaded = await _loadFromLocalCache();
      if (loaded) {
        unawaited(_maybeSyncIfRemoteVersionChanged());
        return;
      }
    }
    if (!await NetworkService.instance.isConnected()) {
      _markFailed();
      return;
    }
    await _downloadAndPersist();
    if (!isReady) _markFailed();
  }

  /// Arka plan görevi: indirilen `fiyatlar.json` belleğe alınır; önbelleğe yazılmaz.
  void applyJsonString(String json) => _applyDecoded(jsonDecode(json));

  FacilityPriceEntry? lookup(String il, String isim) {
    final key = FacilityPriceEntry.matchKey(il, isim);
    return _byKey[key];
  }

  /// Katalog hazırsa fiyatlar.json kaydını kullanır.
  /// Henüz yüklenmediyse tesisi olduğu gibi bırakır; "kayıt yok" denmez.
  Misafirhane resolveFacility(Misafirhane m) {
    if (!isReady) return m;
    final entry = lookup(m.il, m.isim);
    if (entry == null) return m.copyWithoutPrices();
    return m.copyWithPriceEntry(entry);
  }

  Future<void> _maybeSyncIfRemoteVersionChanged() async {
    if (!await NetworkService.instance.isConnected()) return;
    if (!kDebugMode && !await FiyatSyncPrefs.isCheckDue()) return;
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

  /// Bozuk veya boş önbellek "fiyat yok" sayılmaz; çağıran uzak dosyayı dener.
  Future<bool> _loadFromLocalCache() async {
    try {
      final raw = await FiyatLocalCache.readJson();
      if (raw == null) return false;
      final decoded = _decode(jsonDecode(raw));
      if (decoded == null || decoded.map.isEmpty) return false;
      _commit(decoded.map, decoded.note);
      return true;
    } catch (e, st) {
      _log('Yerel fiyat önbelleği okunamadı: $e', st);
      return false;
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
    final decoded = _decode(root);
    if (decoded == null) {
      _log('Fiyat dosyası okunamadı.');
      return;
    }
    _commit(decoded.map, decoded.note);
    _log('Fiyat kaydı yüklendi: ${decoded.map.length} tesis');
  }

  ({Map<String, FacilityPriceEntry> map, String? note})? _decode(dynamic root) {
    final map = <String, FacilityPriceEntry>{};
    String? note;
    List<dynamic>? list;

    if (root is Map) {
      final m = root.map((k, v) => MapEntry(k.toString(), v));
      final n = m['not'] ?? m['note'] ?? m['aciklama'];
      if (n != null) {
        final s = n.toString().trim();
        if (s.isNotEmpty) note = s;
      }
      final raw = m['tesisler'] ?? m['fiyatlar'] ?? m['items'];
      if (raw is List) list = raw;
    } else if (root is List) {
      list = root;
    }
    if (list == null) return null;

    for (final item in list) {
      final e = FacilityPriceEntry.tryParse(item);
      if (e == null || !e.hasFiyatBilgisi) continue;
      map[e.key] = e;
    }
    return (map: map, note: note);
  }

  void _commit(Map<String, FacilityPriceEntry> map, String? note) {
    _note = note;
    _byKey = map;
    _loadedEmpty = map.isEmpty;
    _loadFailed = false;
    updates.value++;
  }

  void _markFailed() {
    if (isReady || _loadFailed) return;
    _loadFailed = true;
    updates.value++;
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[FacilityPriceRepository] $message');
    if (kDebugMode && st != null) {
      debugPrint(st.toString());
    }
  }
}
