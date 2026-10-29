import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../services/place_resolver.dart';
import '../utils/text_encoding.dart';

enum GeocodeStatus {
  /// Koordinat bulundu.
  hit,
  /// Kaynak cevap verdi, sonuç yok.
  miss,
  /// Ağ / 429 / zaman aşımı — tekrar denenebilir.
  error,
}

class GeocodeOutcome {
  const GeocodeOutcome._(this.status, this.point);
  const GeocodeOutcome.hit(LatLng point)
      : this._(GeocodeStatus.hit, point);
  const GeocodeOutcome.miss() : this._(GeocodeStatus.miss, null);
  const GeocodeOutcome.error() : this._(GeocodeStatus.error, null);

  final GeocodeStatus status;
  final LatLng? point;
}

/// Yer adı → koordinat (Photon önce, Nominatim yedek).
///
/// Gezi/yemek master verisinde `enlem`/`boylam` yok; çalışma anında buradan çözülür.
/// Ağ / 429 hatalarında `null` cache’lenmez.
abstract final class NominatimGeocodeCache {
  static final Map<String, LatLng> _hits = {};
  /// Miss sonuçları kısa süre hatırlanır; süre dolunca haritada yeniden aranır.
  static final Map<String, DateTime> _missUntil = {};
  static const Duration _missTtl = Duration(seconds: 40);
  static DateTime _lastNominatimCall = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _nominatimMinGap = Duration(milliseconds: 1200);
  static const String _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';

  /// Türkiye bbox (Photon): minLon,minLat,maxLon,maxLat
  static const String _trBbox = '25.5,35.8,45.0,42.3';

  static String _key(String query) => query.trim().toLowerCase();

  static Future<LatLng?> search(String query) async {
    final o = await searchDetailed(query);
    return o.point;
  }

  static Future<GeocodeOutcome> nominatim(String query) =>
      _searchNominatim(query.trim());

  /// Cami, adres ve tesis adı. İl sonda yazılır; en uygun Türkiye sonucu seçilir.
  static Future<({String name, double latitude, double longitude})?> rankedPlace(
    String query,
  ) async {
    final phrase = PlaceResolver.searchPhrase(query);
    List<_NominatimHit> rows = const [];
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        rows = await _nominatimRows(phrase);
        break;
      } on _NominatimFailure {
        if (attempt == 1) return null;
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    if (rows.isEmpty) return null;
    rows.sort((a, b) {
      final byName = _rank(b, query).compareTo(_rank(a, query));
      if (byName != 0) return byName;
      return b.importance.compareTo(a.importance);
    });
    final best = rows.first;
    final label = best.name.trim().isEmpty ? phrase : best.name.trim();
    return (name: label, latitude: best.latitude, longitude: best.longitude);
  }

  static int _rank(_NominatimHit hit, String query) {
    var score = PlaceResolver.placeScore('${hit.name} ${hit.display}', query);
    if (hit.type == 'place_of_worship' || hit.type == 'mosque') score += 4;
    return score;
  }

  static Future<GeocodeOutcome> searchDetailed(String query) async {
    final raw = query.trim();
    if (raw.isEmpty) return const GeocodeOutcome.miss();
    final k = _key(raw);
    final hit = _hits[k];
    if (hit != null) return GeocodeOutcome.hit(hit);

    final until = _missUntil[k];
    if (until != null && DateTime.now().isBefore(until)) {
      return const GeocodeOutcome.miss();
    }
    _missUntil.remove(k);

    final photonQ = raw.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ');
    final photon = await _searchPhoton(photonQ);
    debugPrint('[Geocode] photon "$photonQ": ${photon.status.name}');
    if (photon.status == GeocodeStatus.hit) {
      _hits[k] = photon.point!;
      return photon;
    }

    final nom = await _searchNominatim(raw);
    debugPrint('[Geocode] nominatim "$raw": ${nom.status.name}');
    if (nom.status == GeocodeStatus.hit) {
      _hits[k] = nom.point!;
      return nom;
    }

    // İkisi de kesin miss → kısa TTL; hata varsa cache yok (hemen yeniden dene).
    if (photon.status == GeocodeStatus.miss &&
        nom.status == GeocodeStatus.miss) {
      _missUntil[k] = DateTime.now().add(_missTtl);
      return const GeocodeOutcome.miss();
    }
    return const GeocodeOutcome.error();
  }

  static void invalidate(String query) {
    final k = _key(query);
    _hits.remove(k);
    _missUntil.remove(k);
  }

  /// Süresi dolmuş miss kayıtlarını temizle — arka plan yeniden denemesi için.
  static void clearExpiredMisses() {
    final now = DateTime.now();
    _missUntil.removeWhere((_, until) => !now.isBefore(until));
  }

  static void clearAllMisses() {
    _missUntil.clear();
  }

  static Future<GeocodeOutcome> _searchPhoton(String query) async {
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/api/'
        '?q=${Uri.encodeComponent(query)}'
        '&limit=5'
        '&bbox=$_trBbox',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 429 || res.statusCode >= 500) {
        return const GeocodeOutcome.error();
      }
      if (res.statusCode != 200) return const GeocodeOutcome.error();
      final root = jsonDecode(responseText(res));
      if (root is! Map) return const GeocodeOutcome.miss();
      final features = root['features'];
      if (features is! List || features.isEmpty) {
        return const GeocodeOutcome.miss();
      }

      for (final f in features) {
        if (f is! Map) continue;
        final props = f['properties'];
        final geom = f['geometry'];
        if (props is! Map || geom is! Map) continue;
        final cc = props['countrycode']?.toString().toUpperCase();
        if (cc != null && cc.isNotEmpty && cc != 'TR') continue;
        final coords = geom['coordinates'];
        if (coords is! List || coords.length < 2) continue;
        final lon = double.tryParse(coords[0].toString());
        final lat = double.tryParse(coords[1].toString());
        if (lat == null || lon == null) continue;
        if (lat < 35.5 || lat > 42.5 || lon < 25.0 || lon > 45.5) continue;
        return GeocodeOutcome.hit(LatLng(lat, lon));
      }
      return const GeocodeOutcome.miss();
    } catch (_) {
      return const GeocodeOutcome.error();
    }
  }

  static Future<GeocodeOutcome> _searchNominatim(String query) async {
    try {
      final rows = await _nominatimRows(query, limit: 1);
      if (rows.isEmpty) return const GeocodeOutcome.miss();
      final first = rows.first;
      return GeocodeOutcome.hit(LatLng(first.latitude, first.longitude));
    } on _NominatimFailure {
      return const GeocodeOutcome.error();
    }
  }

  static Future<List<_NominatimHit>> _nominatimRows(
    String query, {
    int limit = 5,
  }) async {
    final wait =
        _nominatimMinGap - DateTime.now().difference(_lastNominatimCall);
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
    }
    _lastNominatimCall = DateTime.now();
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=jsonv2&limit=$limit&countrycodes=tr',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 429 || res.statusCode >= 500) {
        throw const _NominatimFailure();
      }
      if (res.statusCode != 200) throw const _NominatimFailure();
      final list = jsonDecode(responseText(res));
      if (list is! List) return const [];
      final rows = <_NominatimHit>[];
      for (final item in list) {
        if (item is! Map) continue;
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        if (lat == null || lon == null) continue;
        final importance = item['importance'];
        rows.add(
          _NominatimHit(
            name: item['name']?.toString() ?? '',
            display: item['display_name']?.toString() ?? '',
            type: item['type']?.toString() ?? '',
            latitude: lat,
            longitude: lon,
            importance: importance is num ? importance.toDouble() : 0,
          ),
        );
      }
      return rows;
    } catch (error) {
      if (error is _NominatimFailure) rethrow;
      throw const _NominatimFailure();
    }
  }
}

class _NominatimHit {
  const _NominatimHit({
    required this.name,
    required this.display,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.importance,
  });

  final String name;
  final String display;
  final String type;
  final double latitude;
  final double longitude;
  final double importance;
}

class _NominatimFailure {
  const _NominatimFailure();
}
