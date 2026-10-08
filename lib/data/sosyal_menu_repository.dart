import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/network_service.dart';
import '../utils/search_normalize.dart';
import '../utils/text_encoding.dart';

class SosyalMenuUrun {
  const SosyalMenuUrun({
    required this.ad,
    required this.fiyat,
    this.birim = '',
    this.oncekiFiyat,
  });

  final String ad;
  final double fiyat;

  /// `porsiyon`, `kg`, `bardak`, `kişilik`… (belgede yazıyorsa).
  final String birim;

  /// Son fiyat değişikliğinden önceki fiyat.
  final double? oncekiFiyat;
}

class SosyalMenuKategori {
  const SosyalMenuKategori({required this.ad, required this.urunler});

  final String ad;
  final List<SosyalMenuUrun> urunler;
}

/// Belediyenin resmî sitesinde yayımlanan yeme-içme fiyatları (`sosyal_menuler.json`).
class SosyalMenu {
  const SosyalMenu({
    required this.il,
    required this.isim,
    required this.kapsam,
    required this.kaynak,
    required this.kaynakAdi,
    required this.belge,
    required this.yil,
    required this.kontrol,
    required this.kategoriler,
    this.durum = 'guncel',
    this.dogrulama,
    this.kaynakTarihi,
  });

  final String il;
  final String isim;

  /// `tesis` = tesisin kendi menüsü, `belediye` = belediyenin genel sosyal tesis tarifesi.
  final String kapsam;
  final Uri kaynak;
  final String kaynakAdi;
  final String belge;
  final int? yil;
  final DateTime? kontrol;
  final List<SosyalMenuKategori> kategoriler;

  /// `guncel` | `kaynak_bulunamadi` (kaynak kalktı; son doğrulanan fiyatlar gösterilir).
  final String durum;

  /// Fiyatların resmî kaynakta en son doğrulandığı gün.
  final DateTime? dogrulama;

  /// Kaynak belgenin yayım / güncellenme tarihi (sunucu bildiriyorsa).
  final DateTime? kaynakTarihi;

  bool get tesisMenusu => kapsam == 'tesis';

  bool get kaynakBulunamadi => durum == 'kaynak_bulunamadi';

  int get urunSayisi => kategoriler.fold(0, (a, k) => a + k.urunler.length);

  static String matchKey(String il, String isim) =>
      '${normalizeForSearch(il)}\u0001${normalizeForSearch(isim)}';

  /// Kaynak bağlantısı yalnız resmî alan adına (https/http) işaret ediyorsa kabul edilir.
  static bool isOfficialSource(Uri u) {
    if (u.scheme != 'https' && u.scheme != 'http') return false;
    if (u.userInfo.isNotEmpty || u.hasPort && u.port != 80 && u.port != 443) {
      return false;
    }
    final h = u.host.toLowerCase();
    return h.endsWith('.bel.tr') ||
        h.endsWith('.gov.tr') ||
        h == 'ibb.istanbul' ||
        h.endsWith('.ibb.istanbul') ||
        h == 'beltur.istanbul' ||
        h.endsWith('.beltur.istanbul');
  }

  static SosyalMenu? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final il = (m['il'] ?? '').toString().trim();
    final isim = (m['isim'] ?? '').toString().trim();
    final kaynak = Uri.tryParse((m['kaynak'] ?? '').toString().trim());
    if (il.isEmpty || isim.isEmpty || kaynak == null || !isOfficialSource(kaynak)) {
      return null;
    }
    final kategoriler = <SosyalMenuKategori>[];
    final rawCats = m['kategoriler'];
    if (rawCats is List) {
      for (final c in rawCats) {
        if (c is! Map) continue;
        final urunler = <SosyalMenuUrun>[];
        final rawItems = c['urunler'];
        if (rawItems is List) {
          for (final u in rawItems) {
            if (u is! Map) continue;
            final ad = (u['ad'] ?? '').toString().trim();
            final f = u['fiyat'];
            final fiyat = f is num ? f.toDouble() : double.tryParse('$f');
            if (ad.isEmpty || fiyat == null || fiyat <= 0) continue;
            final o = u['onceki'];
            final of = o is Map ? o['fiyat'] : null;
            final onceki = of is num ? of.toDouble() : null;
            urunler.add(SosyalMenuUrun(
              ad: ad,
              fiyat: fiyat,
              birim: (u['birim'] ?? '').toString().trim(),
              oncekiFiyat: onceki != null && onceki > 0 && onceki != fiyat ? onceki : null,
            ));
          }
        }
        final ad = (c['ad'] ?? '').toString().trim();
        if (ad.isNotEmpty && urunler.isNotEmpty) {
          kategoriler.add(SosyalMenuKategori(ad: ad, urunler: urunler));
        }
      }
    }
    if (kategoriler.isEmpty) return null;
    final yil = m['yil'];
    return SosyalMenu(
      il: il,
      isim: isim,
      kapsam: (m['kapsam'] ?? '').toString(),
      kaynak: kaynak,
      kaynakAdi: (m['kaynak_adi'] ?? '').toString().trim(),
      belge: (m['belge'] ?? '').toString().trim(),
      yil: yil is num ? yil.toInt() : int.tryParse('$yil'),
      kontrol: DateTime.tryParse((m['kontrol'] ?? '').toString()),
      kategoriler: kategoriler,
      durum: (m['durum'] ?? 'guncel').toString(),
      dogrulama: DateTime.tryParse((m['dogrulama'] ?? '').toString()),
      kaynakTarihi: DateTime.tryParse((m['kaynak_tarihi'] ?? '').toString()),
    );
  }
}

/// `sosyal_menuler.json` — aylık GitHub Actions taramasının çıktısı; il+isim ile eşlenir.
class SosyalMenuRepository {
  SosyalMenuRepository._();

  static final SosyalMenuRepository instance = SosyalMenuRepository._();

  static const rawUrl =
      'https://raw.githubusercontent.com/Serdarza/rotalink-data/refs/heads/main/sosyal_menuler.json';
  static const _fileName = 'rotalink_sosyal_menuler.json';
  static const _kLocalVersion = 'rotalink_sosyal_menu_data_version';
  static const _kLastCheckMs = 'rotalink_sosyal_menu_last_version_check_ms';
  static const _checkInterval = Duration(days: 1);
  static const _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';

  Map<String, SosyalMenu> _byKey = const {};

  int get count => _byKey.length;

  SosyalMenu? lookup(String il, String isim) =>
      _byKey[SosyalMenu.matchKey(il, isim)];

  Future<void> ensureLocalDataReady() async {
    final cached = await _readCache();
    if (cached != null) {
      _apply(cached);
      unawaited(_maybeSync());
      return;
    }
    if (!await NetworkService.instance.isConnected()) return;
    await _download();
  }

  @visibleForTesting
  void applyJsonForTest(String json) => _apply(json);

  void _apply(String json) {
    try {
      final root = jsonDecode(json);
      final list = root is Map ? root['items'] : root;
      final map = <String, SosyalMenu>{};
      if (list is List) {
        for (final raw in list) {
          final menu = SosyalMenu.tryParse(raw);
          if (menu != null) map[SosyalMenu.matchKey(menu.il, menu.isim)] = menu;
        }
      }
      _byKey = map;
      _log('Sosyal tesis menüleri yüklendi: ${map.length}');
    } catch (e, st) {
      _log('Sosyal tesis menüleri okunamadı: $e', st);
    }
  }

  Future<void> _maybeSync() async {
    if (!await NetworkService.instance.isConnected()) return;
    final p = await SharedPreferences.getInstance();
    final lastMs = p.getInt(_kLastCheckMs);
    if (lastMs != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
            _checkInterval) {
      return;
    }
    await p.setInt(_kLastCheckMs, DateTime.now().millisecondsSinceEpoch);
    final remote = await _remoteVersion();
    if (remote == null || remote == p.getString(_kLocalVersion)) return;
    await _download(expectedVersion: remote);
  }

  Future<String?> _remoteVersion() async {
    try {
      final res = await http
          .head(Uri.parse(rawUrl), headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final etag = res.headers['etag']?.trim();
      if (etag != null && etag.isNotEmpty) return etag;
      return res.headers['last-modified']?.trim();
    } catch (e, st) {
      _log('Sürüm kontrolü hatası: $e', st);
      return null;
    }
  }

  Future<void> _download({String? expectedVersion}) async {
    try {
      final res = await http
          .get(Uri.parse(rawUrl), headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 45));
      // Dosya henüz oluşturulmadıysa (ilk tarama öncesi) 404 normaldir.
      if (res.statusCode != 200) return;
      final body = responseText(res).trim();
      if (body.isEmpty) return;
      _apply(body);
      final file = await _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(body, flush: true);
      final version = expectedVersion ?? await _remoteVersion();
      if (version != null) {
        final p = await SharedPreferences.getInstance();
        await p.setString(_kLocalVersion, version);
      }
    } catch (e, st) {
      _log('İndirme hatası: $e', st);
    }
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<String?> _readCache() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return null;
      final text = fixMojibake(await f.readAsString());
      return text.trim().length > 2 ? text : null;
    } catch (_) {
      return null;
    }
  }

  static void _log(String message, [StackTrace? st]) {
    debugPrint('[SosyalMenuRepository] $message');
    if (kDebugMode && st != null) debugPrint(st.toString());
  }
}
