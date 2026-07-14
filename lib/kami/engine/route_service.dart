import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../../models/route_stop.dart';
import '../../services/osrm_route_service.dart';
import '../../utils/route_facility_lookup.dart';
import '../../utils/safe_map_coordinates.dart';
import 'accommodation_service.dart';
import 'city_resolver.dart';
import 'food_service.dart';
import 'kami_models.dart';
import 'municipal_service.dart';
import 'tourism_service.dart';

/// İl-il rota önerisi — OSRM/düz çizgi + yalnızca DB kayıtları.
class KamiRouteService {
  KamiRouteService({
    this.accommodation = const KamiAccommodationService(),
    this.tourism = const KamiTourismService(),
    this.food = const KamiFoodService(),
    this.municipal = const KamiMunicipalService(),
  });

  final KamiAccommodationService accommodation;
  final KamiTourismService tourism;
  final KamiFoodService food;
  final KamiMunicipalService municipal;

  static const double corridorKm = 70;
  static const double excludeEndsKm = 35;
  static final Distance _distance = const Distance();

  Future<List<KamiRouteSection>> buildCityRoute({
    required RotaDataState data,
    required String fromCity,
    required String toCity,
  }) async {
    final stops = <RouteStop>[
      RouteStop(city: fromCity, days: 0),
      RouteStop(city: toCity, days: 1),
    ];
    final waypoints = waypointsForRouteStops(data, stops);
    List<LatLng> polyline;
    if (waypoints.length >= 2) {
      try {
        final segs = await OsrmRouteService.fetchSegments(waypoints);
        polyline = [
          for (final s in segs) ...s.points,
        ];
        if (polyline.length < 2) {
          polyline = OsrmRouteService.straightFallback(waypoints);
        }
      } catch (_) {
        polyline = OsrmRouteService.straightFallback(waypoints);
      }
    } else {
      polyline = const [];
    }

    final along = polyline.length >= 2
        ? _discoverAlongCities(
            data: data,
            polyline: polyline,
            start: fromCity,
            end: toCity,
          )
        : <String>[];

    final sections = <KamiRouteSection>[
      KamiRouteSection(
        city: fromCity,
        roleLabel: 'Başlangıç',
        facilities: accommodation.byCity(data, fromCity, limit: 2),
        gezi: tourism.byCity(data, fromCity, limit: 2),
        yemek: food.byCity(data, fromCity, limit: 2),
        sosyal: municipal.byCity(data, fromCity, limit: 2),
      ),
      for (final city in along)
        KamiRouteSection(
          city: city,
          roleLabel: 'Yol üzeri',
          facilities: accommodation.byCity(data, city, limit: 2),
          gezi: tourism.byCity(data, city, limit: 2),
          yemek: food.byCity(data, city, limit: 2),
          sosyal: municipal.byCity(data, city, limit: 2),
        ),
      KamiRouteSection(
        city: toCity,
        roleLabel: 'Varış',
        facilities: accommodation.byCity(data, toCity, limit: 4),
        gezi: tourism.byCity(data, toCity, limit: 4),
        yemek: food.byCity(data, toCity, limit: 4),
        sosyal: municipal.byCity(data, toCity, limit: 3),
      ),
    ];
    return sections;
  }

  /// Hafta sonu: konuma yakın illeri puanla, en iyisini seç.
  ({String city, int score})? pickWeekendCity({
    required RotaDataState data,
    required LatLng user,
    double maxKm = 220,
  }) {
    final cityPoints = <String, LatLng>{};
    void consider(String il, double? lat, double? lon) {
      if (lat == null || lon == null) return;
      if (lat == 0 || lon == 0) return;
      if (!isValidWgs84LatLng(lat, lon)) return;
      final key = KamiCityResolver.normalize(il);
      if (key.isEmpty) return;
      cityPoints.putIfAbsent(il.trim(), () => LatLng(lat, lon));
    }

    for (final m in data.aramaIcinTumTesisler) {
      consider(m.il, m.latitude, m.longitude);
    }
    for (final g in data.gezi) {
      consider(g.il, g.enlem, g.boylam);
    }
    for (final s in data.sosyal) {
      consider(s.il, s.enlem, s.boylam);
    }

    ({String city, int score})? best;
    for (final entry in cityPoints.entries) {
      final km = _distance.as(LengthUnit.Kilometer, user, entry.value);
      if (km > maxKm) continue;
      final score = _scoreCity(data, entry.key, km);
      if (best == null || score > best.score) {
        best = (city: entry.key, score: score);
      }
    }
    return best;
  }

  int _scoreCity(RotaDataState data, String city, double km) {
    final g = tourism.byCity(data, city, limit: 50).length;
    final y = food.byCity(data, city, limit: 50).length;
    final t = accommodation.byCity(data, city, limit: 50).length;
    final s = municipal.byCity(data, city, limit: 50).length;
    final richness = g * 4 + y * 3 + t * 3 + s * 2;
    final proximity = ((220 - km).clamp(0, 220) / 10).round();
    return richness + proximity;
  }

  List<String> _discoverAlongCities({
    required RotaDataState data,
    required List<LatLng> polyline,
    required String start,
    required String end,
  }) {
    final startKey = KamiCityResolver.normalize(start);
    final endKey = KamiCityResolver.normalize(end);
    final sampled = _samplePolyline(polyline, maxPoints: 160);
    final anchors = <_KamiCityAnchor>[];

    final seen = <String>{};
    for (final m in data.aramaIcinTumTesisler) {
      final key = KamiCityResolver.normalize(m.il);
      if (key.isEmpty || key == startKey || key == endKey) continue;
      if (!seen.add(key)) continue;
      if (m.latitude == 0 ||
          m.longitude == 0 ||
          !isValidWgs84LatLng(m.latitude, m.longitude)) {
        continue;
      }
      final point = LatLng(m.latitude, m.longitude);
      final nearest = _nearestOnPolyline(sampled, point);
      if (nearest.distKm > corridorKm) continue;
      if (nearest.progress < 0.08 || nearest.progress > 0.92) continue;
      final startPt = sampled.first;
      final endPt = sampled.last;
      final dStart = _distance.as(LengthUnit.Kilometer, point, startPt);
      final dEnd = _distance.as(LengthUnit.Kilometer, point, endPt);
      if (dStart < excludeEndsKm || dEnd < excludeEndsKm) continue;
      anchors.add(
        _KamiCityAnchor(
          city: m.il.trim(),
          progress: nearest.progress,
          distKm: nearest.distKm,
        ),
      );
    }

    anchors.sort((a, b) => a.progress.compareTo(b.progress));
    // En fazla 5 yol üzeri il.
    if (anchors.length <= 5) {
      return [for (final a in anchors) a.city];
    }
    return [for (final a in anchors.take(5)) a.city];
  }

  List<LatLng> _samplePolyline(List<LatLng> pts, {required int maxPoints}) {
    if (pts.length <= maxPoints) return pts;
    final out = <LatLng>[];
    final step = (pts.length - 1) / (maxPoints - 1);
    for (var i = 0; i < maxPoints; i++) {
      out.add(pts[(i * step).round()]);
    }
    return out;
  }

  ({double progress, double distKm}) _nearestOnPolyline(
    List<LatLng> poly,
    LatLng point,
  ) {
    var bestDist = double.infinity;
    var bestProgress = 0.0;
    var traveled = 0.0;
    final lengths = <double>[0];
    for (var i = 1; i < poly.length; i++) {
      traveled += _distance.as(LengthUnit.Kilometer, poly[i - 1], poly[i]);
      lengths.add(traveled);
    }
    final total = traveled <= 0 ? 1.0 : traveled;

    for (var i = 1; i < poly.length; i++) {
      final a = poly[i - 1];
      final b = poly[i];
      final d = _distToSegmentKm(point, a, b);
      if (d < bestDist) {
        bestDist = d;
        final segLen = _distance.as(LengthUnit.Kilometer, a, b);
        final t = _projectT(point, a, b);
        bestProgress = (lengths[i - 1] + segLen * t) / total;
      }
    }
    return (progress: bestProgress.clamp(0.0, 1.0), distKm: bestDist);
  }

  double _distToSegmentKm(LatLng p, LatLng a, LatLng b) {
    final t = _projectT(p, a, b);
    final proj = LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
    return _distance.as(LengthUnit.Kilometer, p, proj);
  }

  double _projectT(LatLng p, LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    if (dx == 0 && dy == 0) return 0;
    final t =
        ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) /
            (dx * dx + dy * dy);
    return t.clamp(0.0, 1.0);
  }
}

class _KamiCityAnchor {
  const _KamiCityAnchor({
    required this.city,
    required this.progress,
    required this.distKm,
  });

  final String city;
  final double progress;
  final double distKm;
}
