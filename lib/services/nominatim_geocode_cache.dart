import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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
    if (photon.status == GeocodeStatus.hit) {
      _hits[k] = photon.point!;
      return photon;
    }

    final nom = await _searchNominatim(raw);
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
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 429 || res.statusCode >= 500) {
        return const GeocodeOutcome.error();
      }
      if (res.statusCode != 200) return const GeocodeOutcome.error();
      final root = jsonDecode(res.body);
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
        '&format=json&limit=1&countrycodes=tr',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 429 || res.statusCode >= 500) {
        return const GeocodeOutcome.error();
      }
      if (res.statusCode != 200) return const GeocodeOutcome.error();
      final list = jsonDecode(res.body);
      if (list is! List || list.isEmpty) {
        return const GeocodeOutcome.miss();
      }
      final o = list.first;
      if (o is! Map) return const GeocodeOutcome.miss();
      final lat = double.tryParse(o['lat']?.toString() ?? '');
      final lon = double.tryParse(o['lon']?.toString() ?? '');
      if (lat == null || lon == null) return const GeocodeOutcome.miss();
      return GeocodeOutcome.hit(LatLng(lat, lon));
    } catch (_) {
      return const GeocodeOutcome.error();
    }
  }
}
