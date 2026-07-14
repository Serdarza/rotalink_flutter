import 'package:latlong2/latlong.dart';

import '../../data/firebase_rota_repository.dart';
import '../../utils/safe_map_coordinates.dart';
import '../engine/city_resolver.dart';
import 'province_centers.dart';

/// İl merkezleri / mesafe ve yarıçap halkaları.
abstract final class KamiDistanceService {
  static const List<double> radiusKmRings = [50, 100, 150, 250, 350];
  static final Distance _distance = const Distance();

  /// Veriden il → yaklaşık merkez (koordinat ortalaması / ilk tesis).
  static Map<String, LatLng> cityCentroidsFromData(RotaDataState data) {
    final buckets = <String, List<LatLng>>{};

    void add(String il, double? lat, double? lon) {
      if (lat == null || lon == null) return;
      if (lat == 0 || lon == 0) return;
      if (!isValidWgs84LatLng(lat, lon)) return;
      final key = il.trim();
      if (key.isEmpty) return;
      buckets.putIfAbsent(key, () => <LatLng>[]).add(LatLng(lat, lon));
    }

    for (final m in data.aramaIcinTumTesisler) {
      add(m.il, m.latitude, m.longitude);
    }
    for (final g in data.gezi) {
      add(g.il, g.enlem, g.boylam);
    }
    for (final s in data.sosyal) {
      add(s.il, s.enlem, s.boylam);
    }
    for (final y in data.yemek) {
      add(y.il, y.enlem, y.boylam);
    }

    final out = <String, LatLng>{};
    for (final e in buckets.entries) {
      if (e.value.isEmpty) continue;
      var lat = 0.0;
      var lon = 0.0;
      for (final p in e.value) {
        lat += p.latitude;
        lon += p.longitude;
      }
      out[e.key] = LatLng(lat / e.value.length, lon / e.value.length);
    }
    return out;
  }

  /// 81 il referans merkezleri + veritabanından eksik kalanlar.
  static Map<String, LatLng> mergedCentroids(RotaDataState data) {
    final out = Map<String, LatLng>.from(KamiProvinceCenters.byDisplayName);
    final db = cityCentroidsFromData(data);
    for (final e in db.entries) {
      final raw = e.key.trim();
      if (raw.isEmpty) continue;
      final ref = KamiProvinceCenters.centerFor(raw);
      if (ref != null) {
        final display = KamiProvinceCenters.displayNameForNorm(
              KamiCityResolver.normalize(raw),
            ) ??
            raw;
        out.putIfAbsent(display, () => ref);
        continue;
      }
      out.putIfAbsent(raw, () => e.value);
    }
    return out;
  }

  static Map<String, LatLng> cityCentroids(RotaDataState data) =>
      mergedCentroids(data);

  /// GPS → en yakın il (81 il referans merkezlerine göre).
  static String? nearestProvinceName(LatLng user) {
    String? best;
    var bestKm = double.infinity;
    for (final p in KamiCityResolver.provinces) {
      final center = KamiProvinceCenters.centerFor(p);
      if (center == null) continue;
      final km = _distance.as(LengthUnit.Kilometer, user, center);
      if (km < bestKm) {
        bestKm = km;
        best = p;
      }
    }
    return best;
  }

  static String? nearestCityName(LatLng user, Map<String, LatLng> centroids) {
    String? best;
    var bestKm = double.infinity;
    for (final e in centroids.entries) {
      final km = _distance.as(LengthUnit.Kilometer, user, e.value);
      if (km < bestKm) {
        bestKm = km;
        best = e.key;
      }
    }
    return best;
  }

  static String? resolveHomeCity(LatLng user, RotaDataState data) {
    final fromRef = nearestProvinceName(user);
    if (fromRef != null) return fromRef;
    return nearestCityName(user, mergedCentroids(data));
  }

  static LatLng? centerForCity(String city, RotaDataState data) {
    final ref = KamiProvinceCenters.centerFor(city);
    if (ref != null) return ref;
    final centroids = mergedCentroids(data);
    for (final e in centroids.entries) {
      if (KamiCityResolver.sameCity(e.key, city)) return e.value;
    }
    return null;
  }

  static double kmBetween(LatLng a, LatLng b) =>
      _distance.as(LengthUnit.Kilometer, a, b);

  /// [maxKm] içindeki iller (kendi ili hariç), mesafeye göre.
  static List<({String city, double km, LatLng center})> citiesWithin({
    required LatLng user,
    required Map<String, LatLng> centroids,
    required String? excludeCity,
    double maxKm = 350,
  }) {
    final exclude = excludeCity == null
        ? ''
        : KamiCityResolver.normalize(excludeCity);
    final list = <({String city, double km, LatLng center})>[];
    for (final e in centroids.entries) {
      if (KamiCityResolver.normalize(e.key) == exclude) continue;
      final km = kmBetween(user, e.value);
      if (km > maxKm) continue;
      list.add((city: e.key, km: km, center: e.value));
    }
    list.sort((a, b) => a.km.compareTo(b.km));
    return list;
  }

  static int estimateDriveMinutes(double distanceKm) =>
      (distanceKm / 75 * 60).round().clamp(15, 24 * 60);

  static String formatDrive(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h <= 0) return '$m dk';
    if (m == 0) return '$h saat';
    return '$h saat $m dk';
  }

  static String formatKm(double km) {
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.round()} km';
  }
}
