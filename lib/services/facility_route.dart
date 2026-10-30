import 'dart:math' as math;

/// In-app driving and walking figures. Bird-flight distance is calculated separately.
class FacilityRoute {
  const FacilityRoute({
    required this.mode,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.points,
  });

  final String mode;
  final int distanceMeters;
  final int durationSeconds;
  final List<({double latitude, double longitude})> points;
}

abstract final class FacilityRouteFormat {
  static const double walkLimitKm = 5;

  static bool walkingOffered(double birdKm) => birdKm <= walkLimitKm;

  static String distance(int meters) {
    if (meters < 1000) return '$meters m';
    final km = (meters / 1000).toStringAsFixed(1).replaceAll('.', ',');
    return '$km km';
  }

  static String duration(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes dk';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '$hours sa';
    return '$hours sa $rest dk';
  }

  static String summary(int meters, int seconds) =>
      '${distance(meters)} · ${duration(seconds)}';
}

/// Yürüme çizgisinin haritada nereden başlayıp nerede biteceği.
///
/// Yol servisi çizgiyi en yakın yürünebilir sokağa oturtur. İşaretlenen nokta
/// ve tesis kapısı bu çizginin dışında kalabilir; ekranda ikisi de bağlanır.
class FacilityRouteDraw {
  const FacilityRouteDraw({
    required this.road,
    this.fromMarkedPoint = const [],
    this.toFacility = const [],
  });

  final List<({double latitude, double longitude})> road;
  final List<({double latitude, double longitude})> fromMarkedPoint;
  final List<({double latitude, double longitude})> toFacility;

  static FacilityRouteDraw of(
    FacilityRoute route, {
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) {
    final road = [...route.points];
    if (road.length < 2) {
      return FacilityRouteDraw(road: road);
    }
    final startToFirst = _meters(
      originLatitude,
      originLongitude,
      road.first.latitude,
      road.first.longitude,
    );
    final startToLast = _meters(
      originLatitude,
      originLongitude,
      road.last.latitude,
      road.last.longitude,
    );
    if (startToLast + 40 < startToFirst) {
      final flipped = road.reversed.toList(growable: false);
      road
        ..clear()
        ..addAll(flipped);
    }
    final fromMarkedPoint = <({double latitude, double longitude})>[];
    final toFacility = <({double latitude, double longitude})>[];
    if (_meters(
          originLatitude,
          originLongitude,
          road.first.latitude,
          road.first.longitude,
        ) >
        12) {
      fromMarkedPoint.add((
        latitude: originLatitude,
        longitude: originLongitude,
      ));
      fromMarkedPoint.add(road.first);
    }
    if (_meters(
          destinationLatitude,
          destinationLongitude,
          road.last.latitude,
          road.last.longitude,
        ) >
        12) {
      toFacility.add(road.last);
      toFacility.add((
        latitude: destinationLatitude,
        longitude: destinationLongitude,
      ));
    }
    return FacilityRouteDraw(
      road: road,
      fromMarkedPoint: fromMarkedPoint,
      toFacility: toFacility,
    );
  }
}

double _meters(
  double latitude,
  double longitude,
  double otherLatitude,
  double otherLongitude,
) {
  const earth = 6371008.8;
  final dLat = (otherLatitude - latitude) * math.pi / 180;
  final dLon = (otherLongitude - longitude) * math.pi / 180;
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(latitude * math.pi / 180) *
          math.cos(otherLatitude * math.pi / 180) *
          math.pow(math.sin(dLon / 2), 2);
  return earth * 2 * math.asin(math.sqrt(math.min(1, h.toDouble())));
}
