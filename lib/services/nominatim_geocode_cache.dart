import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Kotlin [GeocodingRepository] / Nominatim kullanımına uyumlu; [User-Agent] ve istek aralığı politikaya uygun.
abstract final class NominatimGeocodeCache {
  static final Map<String, LatLng?> _cache = {};
  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minGap = Duration(milliseconds: 1100);
  static const String _userAgent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';

  static String _key(String query) => query.trim().toLowerCase();

  static Future<LatLng?> search(String query) async {
    final raw = query.trim();
    if (raw.isEmpty) return null;
    final k = _key(raw);
    if (_cache.containsKey(k)) return _cache[k];

    final wait = _minGap - DateTime.now().difference(_lastCall);
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
    }
    _lastCall = DateTime.now();

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(raw)}&format=json&limit=1',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        _cache[k] = null;
        return null;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      if (list.isEmpty) {
        _cache[k] = null;
        return null;
      }
      final o = list.first as Map<String, dynamic>;
      final lat = double.parse(o['lat'].toString());
      final lon = double.parse(o['lon'].toString());
      final ll = LatLng(lat, lon);
      _cache[k] = ll;
      return ll;
    } catch (_) {
      _cache[k] = null;
      return null;
    }
  }
}
