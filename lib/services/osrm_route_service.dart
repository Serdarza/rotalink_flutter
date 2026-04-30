import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../utils/safe_map_coordinates.dart';

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
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
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
