import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../constants/tr_il_ilce.dart';
import '../kami/recommendation/province_centers.dart';
import '../models/misafirhane.dart';
import '../utils/il_ilce.dart';
import '../utils/text_encoding.dart';

/// Harita aramasında yazılan yer adının çözüldüğü nokta.
class ResolvedPlace {
  const ResolvedPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;
}

/// Yer adı → koordinat. Önce cihazdaki veri, sonra ücretsiz Open-Meteo.
///
/// Yerel: il merkezi, il + ilçe (ilçedeki tesislerin merkezi), yalnız ilçe
/// adı (birden çok ilde varsa hepsi). Google buraya hiç girmez.
abstract final class PlaceResolver {
  static const _agent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';

  /// İl ve ilçe eşleşmeleri; ilçe merkezi o ilçedeki tesislerden hesaplanır.
  static List<ResolvedPlace> local(
    String query,
    List<Misafirhane> facilities,
  ) {
    final raw = query.trim();
    if (raw.isEmpty) return const [];
    final out = <ResolvedPlace>[];
    for (final match in IlIlce.matchQuery(raw, kTrIlIlceleri.keys)) {
      final ilce = match.ilce;
      if (ilce == null) {
        final center = KamiProvinceCenters.centerFor(match.il);
        if (center != null) {
          out.add(
            ResolvedPlace(
              name: match.il,
              latitude: center.latitude,
              longitude: center.longitude,
            ),
          );
        }
        continue;
      }
      final center =
          districtCenter(match.il, ilce, facilities) ??
          _provincePlace(match.il, ilce);
      if (center != null) out.add(center);
    }
    return out;
  }

  /// "Ankara'dan İstanbul'a" gibi yalnız illerden oluşan aramayı varış iline çözer.
  ///
  /// Cami, tesis veya ilçe adı geçiyorsa null döner; o arama yer araması olarak kalır.
  static ResolvedPlace? travelDestination(String query) {
    final provinces = <String>[];
    for (final token in query.trim().split(RegExp(r"[\s,;/–—\-]+"))) {
      if (token.trim().isEmpty) continue;
      final glue = IlIlce.key(token);
      if (glue == 'ile' || glue == 've' || glue == 'dan' || glue == 'den') {
        continue;
      }
      final il = _provinceToken(token);
      if (il == null) return null;
      provinces.add(il);
    }
    if (provinces.isEmpty) return null;
    return _provincePlace(provinces.last, null);
  }

  static String? _provinceToken(String token) {
    final direct = IlIlce.canonicalIl(token);
    if (direct != null) return direct;
    final key = IlIlce.key(token);
    const suffixes = [
      'dan',
      'den',
      'tan',
      'ten',
      'da',
      'de',
      'ta',
      'te',
      'ya',
      'ye',
      'na',
      'ne',
      'a',
      'e',
    ];
    for (final suffix in suffixes) {
      if (key.length <= suffix.length + 2 || !key.endsWith(suffix)) continue;
      final il = IlIlce.canonicalIl(key.substring(0, key.length - suffix.length));
      if (il != null) return il;
    }
    return null;
  }

  /// Sorgudaki il adları. Ağ gerekmez; tesis listesi boş olsa da çalışır.
  static List<ResolvedPlace> provincesInQuery(String query) {
    final out = <ResolvedPlace>[];
    final seen = <String>{};
    for (final part in query.split(RegExp(r'[\s,/]+'))) {
      final il = IlIlce.canonicalIl(part);
      if (il == null || !seen.add(IlIlce.key(il))) continue;
      final place = _provincePlace(il, null);
      if (place != null) out.add(place);
    }
    return out;
  }

  static ResolvedPlace? _provincePlace(String il, String? ilce) {
    final center = KamiProvinceCenters.centerFor(il);
    if (center == null) return null;
    return ResolvedPlace(
      name: ilce == null ? il : IlIlce.label(il, ilce),
      latitude: center.latitude,
      longitude: center.longitude,
    );
  }

  /// Sorguda geçen il adı (ör. "Kızılay Ankara" → Ankara); yoksa null.
  static String? ilInQuery(String query) {
    for (final token in IlIlce.key(query).isEmpty
        ? const <String>[]
        : query.split(RegExp(r'[\s,/]+'))) {
      final il = IlIlce.canonicalIl(token);
      if (il != null) return il;
    }
    return null;
  }

  /// "Bursa Ulu Camii" → "Ulu Camii, Bursa". İl yoksa sorgu aynı kalır.
  static String searchPhrase(String query) {
    final raw = query.trim();
    final il = ilInQuery(raw);
    if (il == null) return raw;
    final rest = withoutIl(raw);
    if (rest.isEmpty) return il;
    return '$rest, $il';
  }

  /// Yer adı eşleşmesi. "camii" ile "cami" aynı sayılır.
  static int placeScore(String name, String query) {
    final folded = IlIlce.key(name);
    var score = 0;
    for (final token in query.split(RegExp(r'[\s,/]+'))) {
      final key = IlIlce.key(token);
      if (key.length < 3) continue;
      final province = IlIlce.canonicalIl(token) != null;
      if (folded.contains(key)) {
        score += province ? 2 : 8;
        continue;
      }
      if (!province &&
          key.endsWith('ii') &&
          key.length > 3 &&
          folded.contains(key.substring(0, key.length - 1))) {
        score += 8;
      }
    }
    return score;
  }

  /// Sorgudan il adı çıkarılmış hali; il yoksa sorgunun kendisi.
  static String withoutIl(String query) {
    final parts = query.split(RegExp(r'[\s,/]+'));
    final kept = [
      for (final part in parts)
        if (part.trim().isNotEmpty && IlIlce.canonicalIl(part) == null) part,
    ];
    return kept.join(' ').trim();
  }

  /// İlçedeki tesislerin koordinat ortalaması; ilçede tesis yoksa null.
  static ResolvedPlace? districtCenter(
    String il,
    String ilce,
    List<Misafirhane> facilities,
  ) {
    var lat = 0.0, lon = 0.0, n = 0;
    for (final f in facilities) {
      if (f.latitude == 0 || f.longitude == 0) continue;
      if (!IlIlce.sameIl(f.il, il)) continue;
      final inferred = IlIlce.inferIlce(il, ilce: f.ilce, adres: f.adres);
      if (IlIlce.key(inferred) != IlIlce.key(ilce)) continue;
      lat += f.latitude;
      lon += f.longitude;
      n += 1;
    }
    if (n == 0) return null;
    return ResolvedPlace(
      name: IlIlce.label(il, ilce),
      latitude: lat / n,
      longitude: lon / n,
    );
  }

  /// Open-Meteo yer adı araması (ücretsiz, anahtar yok). Sorguda il geçiyorsa
  /// sonuçlar o ile süzülür; nüfusa göre sıralanır, en çok 5 aday döner.
  static Future<List<ResolvedPlace>> openMeteo(String query) async {
    final raw = query.trim();
    if (raw.length < 2) return const [];
    final il = ilInQuery(raw);
    final name = il == null ? raw : withoutIl(raw);
    if (name.isEmpty) return const [];
    final candidates = await _openMeteoRaw(name);
    if (candidates.isEmpty && name != raw) {
      candidates.addAll(await _openMeteoRaw(raw));
    }
    final inIl = il == null
        ? const <_OpenMeteoPlace>[]
        : candidates.where((c) => IlIlce.sameIl(c.admin1, il)).toList();
    final filtered = inIl.isNotEmpty ? inIl : candidates;
    filtered.sort((a, b) => b.population.compareTo(a.population));
    final seen = <String>{};
    final out = <ResolvedPlace>[];
    for (final c in filtered) {
      final key = IlIlce.key('${c.name}${c.admin1}');
      if (!seen.add(key)) continue;
      final where = [
        if (c.admin2.isNotEmpty && IlIlce.key(c.admin2) != IlIlce.key(c.name))
          c.admin2,
        if (c.admin1.isNotEmpty) c.admin1,
      ].join(', ');
      out.add(
        ResolvedPlace(
          name: where.isEmpty ? c.name : '${c.name} · $where',
          latitude: c.latitude,
          longitude: c.longitude,
        ),
      );
      if (out.length == 5) break;
    }
    return out;
  }

  static Future<List<_OpenMeteoPlace>> _openMeteoRaw(String name) async {
    try {
      final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': name,
        'count': '10',
        'language': 'tr',
        'countryCode': 'TR',
      });
      final res = await http
          .get(uri, headers: {'User-Agent': _agent})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        debugPrint('[PlaceResolver] open-meteo HTTP ${res.statusCode}');
        return [];
      }
      final root = jsonDecode(responseText(res));
      if (root is! Map) return [];
      final results = root['results'];
      if (results is! List) return [];
      final out = <_OpenMeteoPlace>[];
      for (final item in results) {
        if (item is! Map) continue;
        final lat = item['latitude'], lon = item['longitude'];
        if (lat is! num || lon is! num) continue;
        if (lat < 35.5 || lat > 42.5 || lon < 25 || lon > 45.5) continue;
        final pop = item['population'];
        out.add(
          _OpenMeteoPlace(
            name: item['name']?.toString() ?? name,
            admin1: item['admin1']?.toString() ?? '',
            admin2: item['admin2']?.toString() ?? '',
            population: pop is num ? pop.toInt() : 0,
            latitude: lat.toDouble(),
            longitude: lon.toDouble(),
          ),
        );
      }
      return out;
    } catch (error) {
      debugPrint('[PlaceResolver] open-meteo hata: $error');
      return [];
    }
  }
}

class _OpenMeteoPlace {
  const _OpenMeteoPlace({
    required this.name,
    required this.admin1,
    required this.admin2,
    required this.population,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String admin1;
  final String admin2;
  final int population;
  final double latitude;
  final double longitude;
}
