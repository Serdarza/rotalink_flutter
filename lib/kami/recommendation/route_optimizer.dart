import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../../models/gezi_yemek_item.dart';
import '../../models/misafirhane.dart';
import '../../models/route_stop.dart';
import '../../models/sosyal_item.dart';
import '../../services/osrm_route_service.dart';
import '../../utils/route_facility_lookup.dart';
import 'distance_service.dart';
import '../engine/route_service.dart';
import 'trip_score_service.dart';

/// Seçilen öneri için rota + yol üzeri içerik.
abstract final class KamiRouteOptimizer {
  /// Kullanıcı konumu (veya en yakın il) → hedef il.
  static Future<KamiOptimizedTrip> buildTrip({
    required RotaDataState data,
    required LatLng user,
    required KamiCityScore destination,
  }) async {
    final homeName =
        KamiDistanceService.resolveHomeCity(user, data) ?? 'Konumum';

    final startCity = homeName;

    final stops = <RouteStop>[
      RouteStop(city: startCity, days: 0),
      RouteStop(
        city: destination.city,
        days: 1,
        items: [
          ...destination.facilities.take(2),
          ...destination.gezi.take(3).map(
                (g) => g.forRouteSuggestion(turLabel: 'Gezi', day: 1),
              ),
          ...destination.yemek.take(2).map(
                (y) => y.forRouteSuggestion(turLabel: 'Yemek', day: 1),
              ),
        ],
      ),
    ];

    final waypoints = waypointsForRouteStops(data, stops);
    List<LatLng> polyline = const [];
    List<OsrmSegment>? segments;
    var distanceM = destination.distanceKm * 1000;
    var durationS = destination.estimatedDriveMinutes * 60.0;

    if (waypoints.length >= 2) {
      try {
        final segs = await OsrmRouteService.fetchSegments(waypoints);
        segments = segs;
        polyline = [for (final s in segs) ...s.points];
        distanceM = 0;
        durationS = 0;
        for (final s in segs) {
          distanceM += s.distanceM;
          durationS += s.durationS;
        }
        if (polyline.length < 2) {
          polyline = OsrmRouteService.straightFallback(waypoints);
        }
      } catch (_) {
        polyline = OsrmRouteService.straightFallback(waypoints);
      }
    }

    final alongCities = <String>[];
    final alongGezi = <GeziYemekItem>[];
    final alongYemek = <GeziYemekItem>[];
    final alongSosyal = <SosyalItem>[];
    final alongFacilities = <Misafirhane>[];

    try {
      final sections = await KamiRouteService().buildCityRoute(
        data: data,
        fromCity: startCity,
        toCity: destination.city,
      );
      for (final s in sections) {
        if (s.roleLabel != 'Yol üzeri') continue;
        alongCities.add(s.city);
        alongGezi.addAll(s.gezi);
        alongYemek.addAll(s.yemek);
        alongSosyal.addAll(s.sosyal);
        alongFacilities.addAll(s.facilities);
      }
    } catch (_) {
      // Yol üzeri içerik opsiyonel; rota yine açılır.
    }

    return KamiOptimizedTrip(
      originCity: startCity,
      destination: destination,
      stops: stops,
      polyline: polyline,
      distanceM: distanceM,
      durationS: durationS,
      alongCities: alongCities,
      alongGezi: alongGezi,
      alongYemek: alongYemek,
      alongSosyal: alongSosyal,
      alongFacilities: alongFacilities,
      segments: segments,
    );
  }
}

class KamiOptimizedTrip {
  const KamiOptimizedTrip({
    required this.originCity,
    required this.destination,
    required this.stops,
    required this.polyline,
    required this.distanceM,
    required this.durationS,
    required this.alongCities,
    required this.alongGezi,
    required this.alongYemek,
    required this.alongSosyal,
    required this.alongFacilities,
    this.segments,
  });

  final String originCity;
  final KamiCityScore destination;
  final List<RouteStop> stops;
  final List<LatLng> polyline;
  final double distanceM;
  final double durationS;
  final List<String> alongCities;
  final List<GeziYemekItem> alongGezi;
  final List<GeziYemekItem> alongYemek;
  final List<SosyalItem> alongSosyal;
  final List<Misafirhane> alongFacilities;
  final List<OsrmSegment>? segments;

  String get distanceLabel =>
      KamiDistanceService.formatKm(distanceM / 1000);
  String get durationLabel =>
      KamiDistanceService.formatDrive((durationS / 60).round());
}
