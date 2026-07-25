import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/misafirhane.dart';
import '../services/network_service.dart';
import '../utils/search_normalize.dart';
import 'github_tesis_adres_data_source.dart';
import 'tesis_adres_local_cache.dart';
import 'tesis_adres_sync_prefs.dart';

class FacilityAddressEntry {
  const FacilityAddressEntry({
    required this.il,
    required this.isim,
    this.adres = '',
    this.ilce = '',
  });

  final String il;
  final String isim;
  final String adres;
  final String ilce;

  static String matchKey(String il, String isim) =>
      '${normalizeForSearch(il)}\u0001${normalizeForSearch(isim)}';

  String get key => matchKey(il, isim);

  bool get hasData => adres.trim().isNotEmpty || ilce.trim().isNotEmpty;
}

/// `tesisler_adres.json` — il+isim ile adres / ilçe birleştirir.
class FacilityAddressRepository {
  FacilityAddressRepository._();

  static final FacilityAddressRepository instance =
      FacilityAddressRepository._();

  Map<String, FacilityAddressEntry> _byKey = const {};

  int get count => _byKey.length;

  Future<void> ensureLocalDataReady() async {
    if (await TesisAdresLocalCache.hasCache()) {
      await _loadFromLocalCache();
      unawaited(_maybeSyncIfRemoteVersionChanged());
      return;
    }
    if (!await NetworkService.instance.isConnected()) return;
    await _downloadAndPersist();
  }

  FacilityAddressEntry? lookup(String il, String isim) =>
      _byKey[FacilityAddressEntry.matchKey(il, isim)];

  Misafirhane resolveFacility(Misafirhane m) {
    final e = lookup(m.il, m.isim);
    if (e == null || !e.hasData) {
      // Overlay yoksa bile master ilçe mahalle gibi görünmesin.
      final cleaned = sanitizeIlce(m.ilce, il: m.il, isim: m.isim);
      if (cleaned == m.ilce.trim()) return m;
      return m.copyWithAddress(ilce: cleaned);
    }
    final ilce = sanitizeIlce(e.ilce, il: m.il, isim: m.isim);
    return m.copyWithAddress(
      adres: e.adres.trim().isNotEmpty ? e.adres : m.adres,
      ilce: ilce.isNotEmpty ? ilce : m.ilce,
    );
  }

  /// Liste altında sadece ilçe: mahalle / sokak / cadde yazılmaz.
  static String sanitizeIlce(
    String raw, {
    required String il,
    String isim = '',
  }) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    final low = s.toLowerCase();
    final looksMahalle = low.contains('mahallesi') ||
        low.contains('sokak') ||
        low.contains('caddesi') ||
        low.contains('bulvar') ||
        low.contains('belediye sınır') ||
        RegExp(r'\bmah\.?\b').hasMatch(low);
    // Yenimahalle gerçek ilçe — dokunma.
    final isYenimahalle = low.replaceAll(' ', '') == 'yenimahalle';
    if (looksMahalle && !isYenimahalle) {
      s = '';
    }
    if (s.length > 32) s = '';
    final ilN = il.trim().toLowerCase();
    if (s.isNotEmpty && s.toLowerCase() == ilN) return 'Merkez';
    if (s.isNotEmpty) return s;

    // İsimden kaba ilçe (Yığılca Öğretmenevi).
    final name = isim.trim();
    if (name.isEmpty) return 'Merkez';
    var n = name;
    for (final suf in [
      ' Öğretmenevi',
      ' Orduevi',
      ' Polisevi',
      ' Polis Evi',
      ' Misafirhanesi',
      ' Konukevi',
    ]) {
      if (n.toLowerCase().endsWith(suf.toLowerCase())) {
        n = n.substring(0, n.length - suf.length).trim();
        break;
      }
    }
    if (n.isEmpty || n.toLowerCase() == ilN) return 'Merkez';
    final first = n.split(RegExp(r'\s+')).first;
    if (first.toLowerCase() == ilN) return 'Merkez';
    if (first.contains('Mahalle')) return 'Merkez';
    return first;
  }

  Future<void> _maybeSyncIfRemoteVersionChanged() async {
    if (!await NetworkService.instance.isConnected()) return;
    if (!await TesisAdresSyncPrefs.isCheckDue()) return;
    await TesisAdresSyncPrefs.markVersionCheckCompleted();

    final remoteVersion = await GithubTesisAdresDataSource.fetchRemoteVersion();
    if (remoteVersion == null) return;
    final localVersion = await TesisAdresSyncPrefs.getLocalVersion();
    if (localVersion == remoteVersion) {
      _log('Tesis adres güncel; indirme yok.');
      return;
    }
    _log('Tesis adres güncellendi; indiriliyor.');
    await _downloadAndPersist(expectedVersion: remoteVersion);
  }

  Future<void> _loadFromLocalCache() async {
    try {
      final raw = await TesisAdresLocalCache.readJson();
      if (raw == null) {
        _byKey = const {};
        return;
      }
      _applyDecoded(jsonDecode(raw));
    } catch (e, st) {
      _log('Yerel tesis adres önbelleği okunamadı: $e', st);
      _byKey = const {};
    }
  }

  Future<void> _downloadAndPersist({String? expectedVersion}) async {
    try {
      if (!await NetworkService.instance.isConnected()) return;
      final json = await GithubTesisAdresDataSource.fetchFromGitHub();
      if (json == null) return;
      await TesisAdresLocalCache.writeJson(json);
      _applyDecoded(jsonDecode(json));
      final version = expectedVersion ??
          await GithubTesisAdresDataSource.fetchRemoteVersion();
      if (version != null) {
        await TesisAdresSyncPrefs.setLocalVersion(version);
      }
    } catch (e, st) {
      _log('Tesis adres işleme hatası: $e', st);
    }
  }

  void _applyDecoded(dynamic root) {
    final map = <String, FacilityAddressEntry>{};
    List? list;
    if (root is Map) {
      final m = root.map((k, v) => MapEntry(k.toString(), v));
      final raw = m['items'] ?? m['tesisler'] ?? m['adresler'];
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
        final e = FacilityAddressEntry(
          il: il,
          isim: isim,
          adres: _str(m, const ['adres', 'address']),
          ilce: _str(m, const ['ilce', 'ilce_adi', 'district', 'ilçe']),
        );
        if (!e.hasData) continue;
        map[e.key] = e;
      }
    }
    _byKey = map;
    _log('Tesis adres yüklendi: ${map.length}');
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

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[FacilityAddressRepository] $message');
    if (kDebugMode && st != null) debugPrint(st.toString());
  }
}
