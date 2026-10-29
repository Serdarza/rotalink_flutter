import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../utils/safe_map_coordinates.dart';
import '../utils/text_encoding.dart';

/// Kotlin [MainActivity.drawRealRoute] OSRM segmentleri.
class OsrmSegment {
  const OsrmSegment({
    required this.points,
    required this.distanceM,
    required this.durationS,
  });

  final List<LatLng> points;
  final double distanceM;
  final double durationS;
}

abstract final class OsrmRouteService {
  static const _agent = 'RotalinkFlutter/1.0 (https://rotalink.tr)';

  /// Tek başlangıç–varış. [mode] `drive` veya `walk`. Ücretsiz OSRM; Google’a gitmez.
  static Future<OsrmSegment?> fetchDirect({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required String mode,
  }) async {
    if (!isValidWgs84LatLng(originLat, originLon) ||
        !isValidWgs84LatLng(destLat, destLon)) {
      return null;
    }
    final coord = '$originLon,$originLat;$destLon,$destLat';
    final query = '?overview=full&geometries=geojson';
    // router.project-osrm.org her profil için araba grafiğini döndürür.
    // Yürüyüş ayrı sunucudan alınır; araba yedeği yürüme süresini bozar.
    if (mode == 'walk') {
      return _readRoute(
        'https://routing.openstreetmap.de/routed-foot/route/v1/foot/$coord$query',
      );
    }
    return await _readRoute(
          'https://routing.openstreetmap.de/routed-car/route/v1/driving/$coord$query',
        ) ??
        _readRoute(
          'https://router.project-osrm.org/route/v1/driving/$coord$query',
        );
  }

  static Future<OsrmSegment?> _readRoute(String url) async {
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': _agent})
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(responseText(resp));
      if (json is! Map || json['code'] != 'Ok') return null;
      final routes = json['routes'];
      if (routes is! List || routes.isEmpty || routes.first is! Map) {
        return null;
      }
      final route = routes.first as Map;
      final coords = (route['geometry'] as Map?)?['coordinates'];
      if (coords is! List) return null;
      final pts = <LatLng>[];
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          final lon = (c[0] as num).toDouble();
          final lat = (c[1] as num).toDouble();
          if (isValidWgs84LatLng(lat, lon)) pts.add(LatLng(lat, lon));
        }
      }
      if (pts.length < 2) return null;
      return OsrmSegment(
        points: pts,
        distanceM: (route['distance'] as num?)?.toDouble() ?? 0,
        durationS: (route['duration'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<OsrmSegment>> fetchSegments(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return const [];
    final out = <OsrmSegment>[];
    for (var i = 0; i < waypoints.length - 1; i++) {
      final a = waypoints[i];
      final b = waypoints[i + 1];
      if (!isValidWgs84LatLng(a.latitude, a.longitude) ||
          !isValidWgs84LatLng(b.latitude, b.longitude)) {
        continue;
      }
      final coord = '${a.longitude},${a.latitude};${b.longitude},${b.latitude}';
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coord?overview=full&geometries=geojson',
      );
      try {
        final resp = await http.get(uri).timeout(const Duration(seconds: 20));
        if (resp.statusCode != 200) continue;
        final json = jsonDecode(responseText(resp)) as Map<String, dynamic>;
        if (json['code'] != 'Ok') continue;
        final routes = json['routes'] as List<dynamic>?;
        if (routes == null || routes.isEmpty) continue;
        final route = routes.first as Map<String, dynamic>;
        final distance = (route['distance'] as num?)?.toDouble() ?? 0;
        final duration = (route['duration'] as num?)?.toDouble() ?? 0;
        final geometry = route['geometry'] as Map<String, dynamic>?;
        final coords = geometry?['coordinates'] as List<dynamic>?;
        if (coords == null || coords.isEmpty) continue;
        final pts = <LatLng>[];
        for (final c in coords) {
          if (c is List && c.length >= 2) {
            final lon = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            if (isValidWgs84LatLng(lat, lon)) pts.add(LatLng(lat, lon));
          }
        }
        if (pts.length >= 2) {
          out.add(OsrmSegment(points: pts, distanceM: distance, durationS: duration));
        }
      } catch (_) {
        if (isValidWgs84LatLng(a.latitude, a.longitude) &&
            isValidWgs84LatLng(b.latitude, b.longitude)) {
          out.add(OsrmSegment(points: [a, b], distanceM: 0, durationS: 0));
        }
      }
    }
    return out;
  }

  /// OSRM başarısız olursa Kotlin gibi düz segment.
  static List<LatLng> straightFallback(List<LatLng> waypoints) {
    if (waypoints.length < 2) return const [];
    return onlyValidLatLngs(waypoints);
  }
}
