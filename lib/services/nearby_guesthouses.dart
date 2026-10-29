import 'dart:math' as math;
import '../models/misafirhane.dart';
import '../utils/safe_map_coordinates.dart';

class NearbyGuesthouse {
  const NearbyGuesthouse(this.facility, this.km);
  final Misafirhane facility;
  final double km;
  String get distanceLabel =>
      '${km.toStringAsFixed(1).replaceAll('.', ',')} km uzaklıkta · (Kuş Uçuşu)';

  /// Konuma Göre kartları. Mevcut yakın liste etiketi [distanceLabel] olarak kalır.
  String get birdFlightLabel =>
      '${km.toStringAsFixed(1).replaceAll('.', ',')} km · Kuş uçuşu';
}

/// Coordinates stay in memory. Zero coordinates in the existing data mean missing.
abstract final class NearbyGuesthouses {
  static double haversineKm(
    double lat,
    double lon,
    double otherLat,
    double otherLon,
  ) {
    const radians = math.pi / 180;
    final dLat = (otherLat - lat) * radians;
    final dLon = (otherLon - lon) * radians;
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat * radians) *
            math.cos(otherLat * radians) *
            math.pow(math.sin(dLon / 2), 2);
    return 6371.0088 * 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  static List<NearbyGuesthouse> find(
    Iterable<Misafirhane> source,
    double lat,
    double lon, {
    double radiusKm = 20,
  }) {
    if (!isValidWgs84LatLng(lat, lon)) return [];
    final seen = <String>{};
    final results = <NearbyGuesthouse>[];
    for (final f in source) {
      if (!isValidWgs84LatLng(f.latitude, f.longitude) ||
          f.latitude == 0 ||
          f.longitude == 0) {
        continue;
      }
      if (!seen.add(f.stableFacilityId)) continue;
      final km = haversineKm(lat, lon, f.latitude, f.longitude);
      if (km <= radiusKm) results.add(NearbyGuesthouse(f, km));
    }
    results.sort((a, b) {
      final distance = a.km.compareTo(b.km);
      return distance != 0
          ? distance
          : a.facility.stableFacilityId.compareTo(b.facility.stableFacilityId);
    });
    return results;
  }
}
