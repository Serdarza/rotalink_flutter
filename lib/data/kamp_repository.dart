import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/github_camp_config.dart';
import '../services/network_service.dart';
import '../utils/il_ilce.dart';
import '../utils/search_normalize.dart';
import '../utils/text_encoding.dart';

class KampAlani {
  const KampAlani({
    required this.id,
    required this.ad,
    required this.il,
    required this.enlem,
    required this.boylam,
    required this.ucret,
    required this.kampTuru,
    required this.sonKontrol,
    required this.dogrulama,
    required this.kaynakUrl,
    this.ilce,
    this.adres,
    this.telefon,
    this.web,
    this.atif = '',
    this.cadir,
    this.karavan,
    this.motokaravan,
    this.elektrik,
    this.tuvalet,
    this.dus,
    this.icmeSuyu,
    this.atik,
    this.wifi,
    this.otopark,
    this.denizeYakin,
    this.fiyat,
    this.fiyatBirim,
    this.rezervasyon,
    this.bakanlikBelgeNo,
  });

  final String id;
  final String ad;
  final String il;
  final String? ilce;
  final String? adres;
  final double enlem;
  final double boylam;
  final String? telefon;
  final String? web;
  final Uri? kaynakUrl;
  final String atif;
  final String kampTuru;
  final bool? cadir;
  final bool? karavan;
  final bool? motokaravan;
  final bool? elektrik;
  final bool? tuvalet;
  final bool? dus;
  final bool? icmeSuyu;
  final bool? atik;
  final bool? wifi;
  final bool? otopark;
  final bool? denizeYakin;
  final double? fiyat;
  final String? fiyatBirim;
  final String ucret;
  final String? rezervasyon;
  final DateTime? sonKontrol;
  final String dogrulama;
  final String? bakanlikBelgeNo;

  bool get resmiFiyat => fiyat != null && dogrulama == 'resmi';
}

class KampFiltre {
  const KampFiltre({
    this.sorgu = '',
    this.cadir = false,
    this.karavan = false,
    this.ucretsiz = false,
    this.ucretli = false,
    this.elektrik = false,
    this.dus = false,
    this.tuvalet = false,
  });

  final String sorgu;
  final bool cadir;
  final bool karavan;
  final bool ucretsiz;
  final bool ucretli;
  final bool elektrik;
  final bool dus;
  final bool tuvalet;
}

bool _http(Uri? u) {
  if (u == null) return false;
  if (u.scheme != 'https' && u.scheme != 'http') return false;
  return u.userInfo.isEmpty && u.host.isNotEmpty;
}

bool? _bool(dynamic v) => v is bool ? v : null;

double? _fiyat(dynamic v) {
  if (v == null) return null;
  final n = v is num ? v.toDouble() : double.tryParse('$v');
  if (n == null || n <= 0) return null;
  return n;
}

/// `camp_sites.json` — günlük önbellek. Yalnız durum=aktif kayıtlar gösterilir.
class KampRepository {
  KampRepository._();

  static final KampRepository instance = KampRepository._();

  static const _prefsJson = 'rotalink_camp_json';
  static const _prefsFetchedMs = 'rotalink_camp_fetched_ms';
  static const _refreshEvery = Duration(hours: 24);
  static const _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';

  final ValueNotifier<List<KampAlani>> items = ValueNotifier(const []);
  String atif = '';

  Future<void>? _loading;

  Future<void> ensureLoaded() => _loading ??= _load().whenComplete(() {
        if (items.value.isEmpty) _loading = null;
      });

  List<KampAlani> forIller(Set<String> normalizedIller) {
    final all = items.value;
    if (normalizedIller.isEmpty) return all;
    return all.where((k) => normalizedIller.contains(normalizeForSearch(k.il))).toList();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsJson);
    if (cached != null) {
      try {
        applyJsonString(fixMojibake(cached));
      } catch (e) {
        debugPrint('[KampRepository] Önbellek okunamadı: $e');
      }
    }
    final fetchedMs = prefs.getInt(_prefsFetchedMs) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - fetchedMs;
    if (cached != null && age < _refreshEvery.inMilliseconds) return;
    if (!await NetworkService.instance.isConnected()) return;
    try {
      final res = await http
          .get(GithubCampConfig.uri, headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 45));
      if (res.statusCode != 200) return;
      final body = responseText(res).trim();
      if (body.isEmpty) return;
      applyJsonString(body);
      await prefs.setString(_prefsJson, body);
      await prefs.setInt(_prefsFetchedMs, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[KampRepository] İndirme hatası: $e');
    }
  }

  @visibleForTesting
  void applyJsonString(String json) {
    final root = jsonDecode(json);
    if (root is! Map) return;
    atif = (root['atif'] ?? '').toString();
    final raw = root['items'];
    final list = <KampAlani>[];
    if (raw is List) {
      for (final e in raw) {
        final item = tryParse(e);
        if (item != null) list.add(item);
      }
    }
    list.sort((a, b) {
      final c = IlIlce.key(a.il).compareTo(IlIlce.key(b.il));
      return c != 0 ? c : IlIlce.key(a.ad).compareTo(IlIlce.key(b.ad));
    });
    items.value = list;
  }

  static KampAlani? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    if ((raw['durum'] ?? 'aktif').toString() != 'aktif') return null;
    final ad = (raw['ad'] ?? '').toString().trim();
    final il = (raw['il'] ?? '').toString().trim();
    final lat = raw['enlem'];
    final lon = raw['boylam'];
    final enlem = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final boylam = lon is num ? lon.toDouble() : double.tryParse('$lon');
    if (ad.isEmpty || il.isEmpty || enlem == null || boylam == null) return null;
    if (enlem < 35 || enlem > 43 || boylam < 25 || boylam > 45.5) return null;
    final kaynak = Uri.tryParse((raw['kaynak_url'] ?? '').toString().trim());
    String? opt(String key) {
      final s = (raw[key] ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    return KampAlani(
      id: (raw['id'] ?? '').toString(),
      ad: ad,
      il: il,
      ilce: opt('ilce'),
      adres: opt('adres'),
      enlem: enlem,
      boylam: boylam,
      telefon: opt('telefon'),
      web: opt('web'),
      kaynakUrl: _http(kaynak) ? kaynak : null,
      atif: (raw['atif'] ?? '').toString(),
      kampTuru: (raw['kamp_turu'] ?? 'kamping').toString(),
      cadir: _bool(raw['cadir']),
      karavan: _bool(raw['karavan']),
      motokaravan: _bool(raw['motokaravan']),
      elektrik: _bool(raw['elektrik']),
      tuvalet: _bool(raw['tuvalet']),
      dus: _bool(raw['dus']),
      icmeSuyu: _bool(raw['icme_suyu']),
      atik: _bool(raw['atik']),
      wifi: _bool(raw['wifi']),
      otopark: _bool(raw['otopark']),
      denizeYakin: _bool(raw['denize_yakin']),
      fiyat: (raw['dogrulama'] ?? '').toString() == 'resmi' ? _fiyat(raw['fiyat']) : null,
      fiyatBirim: opt('fiyat_birim'),
      ucret: (raw['ucret'] ?? 'bilinmiyor').toString(),
      rezervasyon: opt('rezervasyon'),
      sonKontrol: DateTime.tryParse((raw['son_kontrol'] ?? '').toString()),
      dogrulama: (raw['dogrulama'] ?? '').toString(),
      bakanlikBelgeNo: opt('bakanlik_belge_no'),
    );
  }
}

List<KampAlani> kampFiltrele(List<KampAlani> items, KampFiltre f) {
  final q = normalizeForSearch(f.sorgu);
  return [
    for (final k in items)
      if (_uyar(k, f, q)) k,
  ];
}

bool _uyar(KampAlani k, KampFiltre f, String q) {
  if (q.isNotEmpty) {
    final blob = normalizeForSearch('${k.il} ${k.ilce ?? ''} ${k.ad}');
    if (!blob.contains(q)) return false;
  }
  if (f.cadir && f.karavan) {
    if (k.cadir != true && k.karavan != true && k.kampTuru != 'karavan') return false;
  } else if (f.cadir && k.cadir != true) {
    return false;
  } else if (f.karavan && k.karavan != true && k.kampTuru != 'karavan') {
    return false;
  }
  if (f.ucretsiz && f.ucretli) {
    if (k.ucret != 'ucretsiz' && k.ucret != 'ucretli') return false;
  } else if (f.ucretsiz && k.ucret != 'ucretsiz') {
    return false;
  } else if (f.ucretli && k.ucret != 'ucretli') {
    return false;
  }
  if (f.elektrik && k.elektrik != true) return false;
  if (f.dus && k.dus != true) return false;
  if (f.tuvalet && k.tuvalet != true) return false;
  return true;
}

String kampTuruEtiket(String tur) {
  switch (tur) {
    case 'cadir':
      return 'Çadır';
    case 'karavan':
      return 'Karavan';
    case 'glamping':
      return 'Glamping';
    case 'belediye':
      return 'Belediye';
    case 'milli_park':
      return 'Millî park';
    case 'orman_parki':
      return 'Orman parkı';
    case 'ozel':
      return 'Özel işletme';
    default:
      return 'Kamping';
  }
}
