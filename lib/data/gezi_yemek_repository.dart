import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/gezi_yemek_item.dart';
import '../services/network_service.dart';
// Overlay geçici kapalı; yeniden açınca gerekli importlar:
// import 'gezi_yemek_local_cache.dart';
// import 'gezi_yemek_sync_prefs.dart';
// import 'github_gezi_yemek_data_source.dart';

/// `geziler.json` / `yemekler.json` — görselli listeler (GitHub).
///
/// Master DB'deki gezi/yemek ile birleşir: ayrı dosya varsa onu tercih eder.
class GeziYemekRepository {
  GeziYemekRepository._();

  static final GeziYemekRepository instance = GeziYemekRepository._();

  List<GeziYemekItem> _geziler = const [];
  List<GeziYemekItem> _yemekler = const [];

  List<GeziYemekItem> get geziler => _geziler;
  List<GeziYemekItem> get yemekler => _yemekler;

  bool get hasGeziOverlay => _geziler.isNotEmpty;
  bool get hasYemekOverlay => _yemekler.isNotEmpty;

  Future<void> ensureLocalDataReady() async {
    // Gezi / yemek görsel overlay'leri geçici kapalı — arama metinsel (master).
    // Yeniden açmak için aşağıdaki _ensureKind çağrılarını geri getirin.
    _geziler = const [];
    _yemekler = const [];
  }

  /// Master listesi + overlay: aynı il+isim varsa görselli kaydı kullan.
  List<GeziYemekItem> mergeWithMaster(List<GeziYemekItem> master, {required bool gezi}) {
    final overlay = gezi ? _geziler : _yemekler;
    if (overlay.isEmpty) return master;
    final byKey = <String, GeziYemekItem>{};
    for (final o in overlay) {
      byKey[_key(o.il, o.isim)] = o;
    }
    if (master.isEmpty) return overlay;

    final used = <String>{};
    final out = <GeziYemekItem>[];
    for (final m in master) {
      final k = _key(m.il, m.isim);
      final o = byKey[k];
      if (o != null) {
        used.add(k);
        out.add(_mergeItem(m, o));
      } else {
        out.add(m);
      }
    }
    for (final e in byKey.entries) {
      if (!used.contains(e.key)) out.add(e.value);
    }
    return out;
  }

  GeziYemekItem _mergeItem(GeziYemekItem master, GeziYemekItem overlay) {
    return GeziYemekItem(
      il: overlay.il.isNotEmpty ? overlay.il : master.il,
      isim: overlay.isim.isNotEmpty ? overlay.isim : master.isim,
      adres: overlay.adres.isNotEmpty ? overlay.adres : master.adres,
      aciklama:
          overlay.aciklama.isNotEmpty ? overlay.aciklama : master.aciklama,
      enlem: overlay.enlem ?? master.enlem,
      boylam: overlay.boylam ?? master.boylam,
      tur: overlay.tur ?? master.tur,
      accommodationInfo: overlay.accommodationInfo ?? master.accommodationInfo,
      day: overlay.day ?? master.day,
      imageUrls: overlay.imageUrls.isNotEmpty
          ? overlay.imageUrls
          : master.imageUrls,
    );
  }

  static String _key(String il, String isim) =>
      '${il.trim().toLowerCase()}\u0001${isim.trim().toLowerCase()}';

  // Overlay yeniden açıldığında ensureLocalDataReady içinden çağrılır.
  // ignore: unused_element
  Future<void> _ensureKind({
    required bool isGezi,
    required Future<bool> Function() hasCache,
    required Future<String?> Function() readCache,
    required Future<void> Function(String) writeCache,
    required Future<String?> Function() fetchRemote,
    required Future<String?> Function() fetchVersion,
    required Future<String?> Function() getLocalVersion,
    required Future<void> Function(String) setLocalVersion,
    required void Function(List<GeziYemekItem>) apply,
  }) async {
    final label = isGezi ? 'gezi' : 'yemek';
    if (await hasCache()) {
      await _loadCache(readCache, apply, label);
      unawaited(_maybeSync(
        writeCache: writeCache,
        fetchRemote: fetchRemote,
        fetchVersion: fetchVersion,
        getLocalVersion: getLocalVersion,
        setLocalVersion: setLocalVersion,
        apply: apply,
        label: label,
      ));
      return;
    }
    if (!await NetworkService.instance.isConnected()) return;
    await _download(
      writeCache: writeCache,
      fetchRemote: fetchRemote,
      fetchVersion: fetchVersion,
      setLocalVersion: setLocalVersion,
      apply: apply,
      label: label,
    );
  }

  Future<void> _maybeSync({
    required Future<void> Function(String) writeCache,
    required Future<String?> Function() fetchRemote,
    required Future<String?> Function() fetchVersion,
    required Future<String?> Function() getLocalVersion,
    required Future<void> Function(String) setLocalVersion,
    required void Function(List<GeziYemekItem>) apply,
    required String label,
  }) async {
    if (!await NetworkService.instance.isConnected()) return;
    final remote = await fetchVersion();
    if (remote == null) return;
    final local = await getLocalVersion();
    if (local == remote) {
      _log('$label güncel (sürüm aynı)');
      return;
    }
    _log('$label güncellendi; indiriliyor');
    await _download(
      writeCache: writeCache,
      fetchRemote: fetchRemote,
      fetchVersion: () async => remote,
      setLocalVersion: setLocalVersion,
      apply: apply,
      label: label,
      expectedVersion: remote,
    );
  }

  Future<void> _loadCache(
    Future<String?> Function() readCache,
    void Function(List<GeziYemekItem>) apply,
    String label,
  ) async {
    try {
      final raw = await readCache();
      if (raw == null) {
        apply(const []);
        return;
      }
      apply(_parseList(jsonDecode(raw)));
      _log('$label önbellekten yüklendi');
    } catch (e, st) {
      _log('$label önbellek okunamadı: $e', st);
      apply(const []);
    }
  }

  Future<void> _download({
    required Future<void> Function(String) writeCache,
    required Future<String?> Function() fetchRemote,
    required Future<String?> Function() fetchVersion,
    required Future<void> Function(String) setLocalVersion,
    required void Function(List<GeziYemekItem>) apply,
    required String label,
    String? expectedVersion,
  }) async {
    try {
      final json = await fetchRemote();
      if (json == null) {
        _log('$label indirilemedi');
        return;
      }
      await writeCache(json);
      apply(_parseList(jsonDecode(json)));
      final version = expectedVersion ?? await fetchVersion();
      if (version != null) await setLocalVersion(version);
      _log('$label yüklendi');
    } catch (e, st) {
      _log('$label indirme hatası: $e', st);
    }
  }

  static List<GeziYemekItem> _parseList(dynamic root) {
    List? list;
    if (root is List) {
      list = root;
    } else if (root is Map) {
      final m = root.map((k, v) => MapEntry(k.toString(), v));
      final raw = m['items'] ?? m['tesisler'] ?? m['geziler'] ?? m['yemekler'];
      if (raw is List) list = raw;
    }
    if (list == null) return const [];
    final out = <GeziYemekItem>[];
    for (final e in list) {
      final item = GeziYemekItem.tryParse(e);
      if (item != null) out.add(item);
    }
    return out;
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[GeziYemekRepository] $message');
    if (kDebugMode && st != null) debugPrint(st.toString());
  }
}
