import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/github_hediyelik_config.dart';
import '../services/network_service.dart';
import '../utils/search_normalize.dart';

class HediyelikItem {
  const HediyelikItem({
    required this.il,
    required this.ad,
    this.aciklama = '',
    this.kategori = '',
    this.cografiIsaret = false,
  });

  final String il;
  final String ad;
  final String aciklama;
  final String kategori;
  final bool cografiIsaret;
}

/// `hediyelik.json` — il başına yöresel hediyelik ürünler; yerel önbellek + günlük yenileme.
class HediyelikRepository {
  HediyelikRepository._();

  static final HediyelikRepository instance = HediyelikRepository._();

  static const _prefsJson = 'rotalink_hediyelik_json';
  static const _prefsFetchedMs = 'rotalink_hediyelik_fetched_ms';
  static const _refreshEvery = Duration(hours: 24);
  static const _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';

  /// Normalize il adı → ürünler. Değiştiğinde dinleyiciler yeniden çizer.
  final ValueNotifier<Map<String, List<HediyelikItem>>> byIl =
      ValueNotifier(const {});

  Future<void>? _loading;

  Future<void> ensureLoaded() => _loading ??= _load().whenComplete(() {
        if (byIl.value.isEmpty) _loading = null;
      });

  List<HediyelikItem> forIller(Set<String> normalizedIller) {
    final map = byIl.value;
    if (normalizedIller.isEmpty) {
      return [for (final list in map.values) ...list];
    }
    return [
      for (final il in normalizedIller) ...?map[il],
    ];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsJson);
    if (cached != null) {
      try {
        applyJsonString(cached);
      } catch (e) {
        debugPrint('[HediyelikRepository] Önbellek okunamadı: $e');
      }
    }
    final fetchedMs = prefs.getInt(_prefsFetchedMs) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - fetchedMs;
    if (cached != null && age < _refreshEvery.inMilliseconds) return;
    if (!await NetworkService.instance.isConnected()) return;
    try {
      final res = await http
          .get(
            GithubHediyelikConfig.uri,
            headers: const {'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return;
      final body = utf8.decode(res.bodyBytes).trim();
      if (body.isEmpty) return;
      applyJsonString(body);
      await prefs.setString(_prefsJson, body);
      await prefs.setInt(
        _prefsFetchedMs,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('[HediyelikRepository] İndirme hatası: $e');
    }
  }

  @visibleForTesting
  void applyJsonString(String json) {
    final root = jsonDecode(json);
    final iller = root is Map ? root['iller'] : null;
    if (iller is! Map) return;
    final map = <String, List<HediyelikItem>>{};
    iller.forEach((il, raw) {
      if (raw is! List) return;
      final name = il.toString().trim();
      final items = <HediyelikItem>[
        for (final e in raw)
          if (e is Map && (e['ad']?.toString().trim() ?? '').isNotEmpty)
            HediyelikItem(
              il: name,
              ad: e['ad'].toString().trim(),
              aciklama: e['aciklama']?.toString().trim() ?? '',
              kategori: e['kategori']?.toString().trim() ?? '',
              cografiIsaret: e['cografi_isaret'] == true,
            ),
      ];
      if (items.isNotEmpty) map[normalizeForSearch(name)] = items;
    });
    byIl.value = map;
  }
}
